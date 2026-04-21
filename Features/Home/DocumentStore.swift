import Foundation
import SwiftUI
import UIKit

enum AppRoute: Hashable {
    case capture
    case editor
    case previewEditor
}

@MainActor
final class DocumentStore: ObservableObject {
    @Published var document: EditableDocument = .empty()
    @Published var routePath: [AppRoute] = []
    @Published var statusMessage: String?
    @Published var previewImage: UIImage?
    @Published var exportedPDFURL: URL?
    @Published var isProcessing = false
    /// Defaults to hybrid so exported PDFs include recognized text on top of the scan.
    /// Fidelity mode only draws **manually edited** text blocks (see `PDFExportService`).
    @Published var selectedExportMode: ExportMode = .hybrid {
        didSet {
            document.exportMode = selectedExportMode
        }
    }

    private var analysisImage: UIImage?

    private let processor: ImageProcessingPipeline
    let exportService: PDFExporting
    private let analysisClient: DocumentAnalysisClient

    init(
        processor: ImageProcessingPipeline = DefaultImageProcessingPipeline(),
        exportService: PDFExporting = PDFExportService(),
        analysisClient: DocumentAnalysisClient = VisionDocumentAnalysisClient()
    ) {
        self.processor = processor
        self.exportService = exportService
        self.analysisClient = analysisClient
    }

    func resetToFreshFrontPage() {
        document = .empty()
        selectedExportMode = .hybrid
        previewImage = nil
        exportedPDFURL = nil
        statusMessage = nil
        isProcessing = false
        analysisImage = nil
    }

    func ingest(image: UIImage, source: CaptureSource) async {
        let processor = processor
        let analysisClient = analysisClient

        do {
            isProcessing = true
            statusMessage = "Processing image..."

            let normalized = try await processor.normalize(image)
            let page = Self.makePage(from: normalized)

            previewImage = normalized
            analysisImage = normalized
            document = EditableDocument(
                title: source == .camera ? "Camera Scan" : "Imported Image",
                pages: [page],
                sourceImageURLs: [],
                analysisState: .analyzing,
                exportMode: selectedExportMode
            )
            statusMessage = "Image normalized and ready for analysis."

            await analyzeIfNeeded(using: analysisClient)

            isProcessing = false
            if document.analysisState == .failed {
                statusMessage = "Image is ready, but text recognition is unavailable for this scan. You can still edit manually."
            } else {
                statusMessage = "Image is ready. You can edit or save from the main screen."
            }
        } catch {
            isProcessing = false
            statusMessage = "Image processing failed: \(error.localizedDescription)"
            document.analysisState = .failed
        }
    }

    func makeExportDocument() throws -> PDFExportDocument {
        isProcessing = true
        statusMessage = "Preparing PDF..."
        defer {
            isProcessing = false
        }

        let data = try exportService.export(document: document, mode: selectedExportMode)
        statusMessage = "PDF is ready. Choose where to save it in Files."
        return PDFExportDocument(data: data)
    }

    private func analyzeIfNeeded(using analysisClient: DocumentAnalysisClient) async {
        guard let firstPage = document.pages.first, let sourceImage = analysisImage else { return }
        do {
            let response = try await analysisClient.analyze(documentID: document.id, pageIndex: firstPage.pageNumber, image: sourceImage)
            await MainActor.run {
                apply(response: response)
            }
        } catch {
            await MainActor.run {
                document.analysisState = .failed
                statusMessage = "Backend analysis unavailable. Preview remains editable locally."
            }
        }
    }

    private func apply(response: BackendAnalysisResponse) {
        guard !document.pages.isEmpty else { return }
        var page = document.pages[0]
        page.size = PageSize(width: response.page.pageSize.width, height: response.page.pageSize.height)
        page.sourceImageData = analysisImage?.jpegData(compressionQuality: 0.95)

        // Normalize final reconstruction to a clean logical black-on-white page.
        page.background = .white

        let textBlocks = deduplicatedTextBlocks(response.page.textBlocks)

        // Build a raw, reconstructed page from detected text + image regions + tables.
        let textElements: [PageElement] = textBlocks.map { block in
            let quality = textQualityScore(for: block)
            return .text(TextElement(
                text:        block.text,
                frame:       Rect(x: block.frame.x, y: block.frame.y, width: block.frame.width, height: block.frame.height),
                fontSize:    CGFloat(block.fontSize ?? 15),
                color:       block.textColor.map {
                    RGBAColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
                } ?? .black,
                confidence:  block.confidence,
                backgroundColor: block.backgroundColor.map {
                    RGBAColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
                },
                isUserEdited: false,
                qualityScore: quality,
                needsReview: quality < 0.58
            ))
        }

        let tableElements: [PageElement] = response.page.tableBlocks.map { block in
            let quality = tableQualityScore(for: block)
            return .table(TableElement(
                rows: block.rows,
                frame: Rect(x: block.frame.x, y: block.frame.y, width: block.frame.width, height: block.frame.height),
                confidence: block.confidence,
                qualityScore: quality,
                needsReview: quality < 0.62
            ))
        }

        let tableRects = tableElements.compactMap { element -> CGRect? in
            if case .table(let table) = element {
                return table.frame.cgRect
            }
            return nil
        }

        let textRects = textElements.compactMap { element -> CGRect? in
            if case .text(let text) = element {
                return text.frame.cgRect
            }
            return nil
        }

        let filteredImageBlocks = response.page.imageBlocks.filter { block in
            let rect = block.frame.cgRect
            let area = max(rect.width * rect.height, 1)
            let pageArea = max(page.size.width * page.size.height, 1)
            let areaRatio = area / pageArea
            guard block.confidence >= 0.40 else { return false }
            guard areaRatio >= 0.015 && areaRatio <= 0.35 else { return false }

            let tableCoverage = tableRects.reduce(0.0) { partial, t in
                let overlap = rect.intersection(t)
                guard !overlap.isNull, !overlap.isEmpty else { return partial }
                return partial + (overlap.width * overlap.height)
            } / area
            if tableCoverage > 0.20 { return false }

            let textCoverage = textRects.reduce(0.0) { partial, t in
                let overlap = rect.intersection(t)
                guard !overlap.isNull, !overlap.isEmpty else { return partial }
                return partial + (overlap.width * overlap.height)
            } / area
            if textCoverage > 0.45 { return false }

            return true
        }

        // Table-first mode: when structure is clearly tabular/textual, suppress image blocks.
        let useTableFirstMode = tableElements.count >= 1 && textElements.count >= 8
        let imageSource = useTableFirstMode ? [] : filteredImageBlocks

        let imageElements: [PageElement] = imageSource.map { block in
            let quality = imageQualityScore(for: block)
            return .image(ImageElement(
                frame: Rect(x: block.frame.x, y: block.frame.y, width: block.frame.width, height: block.frame.height),
                fillColor: block.dominantColor.map {
                    RGBAColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
                },
                confidence: block.confidence,
                renderStyle: .solidColor,
                qualityScore: quality,
                needsReview: quality < 0.60
            ))
        }

        page.elements = textElements + imageElements + tableElements

        document.pages[0] = page
        document.exportMode = selectedExportMode
        document.analysisState = .refined
        statusMessage = "Analysis complete. Detected \(textBlocks.count) text block(s), \(imageElements.count) image region(s), and \(tableElements.count) table(s). \(reviewQueueCount) item(s) need review."
    }

    func addTextElement() {
        guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }) else { return }
        let pageSize = document.pages[pageIndex].size
        let newElement = TextElement(
            text: "New text",
            frame: Rect(
                x: pageSize.width * 0.1,
                y: pageSize.height * 0.1,
                width: pageSize.width * 0.6,
                height: max(pageSize.height * 0.06, 28)
            ),
            fontSize: 16,
            confidence: 1,
            isUserEdited: true   // user manually added this
        )
        document.pages[pageIndex].elements.append(.text(newElement))
        statusMessage = "Added a text block. Edit it before exporting the raw PDF."
    }

    func removeTextElement(id: UUID) {
        guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }) else { return }
        document.pages[pageIndex].elements.removeAll { element in
            if case .text(let textElement) = element {
                return textElement.id == id
            }
            return false
        }
        statusMessage = "Text block removed."
    }

    var textElements: [TextElement] {
        document.pages.first?.elements.compactMap {
            if case .text(let textElement) = $0 {
                return textElement
            }
            return nil
        } ?? []
    }

    var reviewQueueCount: Int {
        (textElements.filter { $0.needsReview }.count)
        + (imageElements.filter { $0.needsReview }.count)
        + tableElements.filter { $0.needsReview }.count
    }

    var tableElements: [TableElement] {
        document.pages.first?.elements.compactMap {
            if case .table(let tableElement) = $0 {
                return tableElement
            }
            return nil
        } ?? []
    }

    func toggleTextReview(id: UUID) {
        guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }) else { return }
        guard let elementIndex = document.pages[pageIndex].elements.firstIndex(where: {
            if case .text(let text) = $0 { return text.id == id }
            return false
        }) else { return }
        guard case .text(let existing) = document.pages[pageIndex].elements[elementIndex] else { return }

        var updated = existing
        updated.needsReview.toggle()
        updated.isUserEdited = true
        document.pages[pageIndex].elements[elementIndex] = .text(updated)
    }

    func toggleImageReview(id: UUID) {
        guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }) else { return }
        guard let elementIndex = document.pages[pageIndex].elements.firstIndex(where: {
            if case .image(let image) = $0 { return image.id == id }
            return false
        }) else { return }
        guard case .image(let existing) = document.pages[pageIndex].elements[elementIndex] else { return }

        var updated = existing
        updated.needsReview.toggle()
        document.pages[pageIndex].elements[elementIndex] = .image(updated)
    }

    func toggleTableReview(id: UUID) {
        guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }) else { return }
        guard let elementIndex = document.pages[pageIndex].elements.firstIndex(where: {
            if case .table(let table) = $0 { return table.id == id }
            return false
        }) else { return }
        guard case .table(let existing) = document.pages[pageIndex].elements[elementIndex] else { return }

        var updated = existing
        updated.needsReview.toggle()
        document.pages[pageIndex].elements[elementIndex] = .table(updated)
    }

    var imageElements: [ImageElement] {
        document.pages.first?.elements.compactMap {
            if case .image(let imageElement) = $0 {
                return imageElement
            }
            return nil
        } ?? []
    }

    var pageBackground: PageBackground {
        get {
            document.pages.first?.background ?? .white
        }
        set {
            guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }) else { return }
            document.pages[pageIndex].background = newValue
            statusMessage = "PDF Background preference updated."
        }
    }

    func textElementBinding(id: UUID) -> Binding<TextElement>? {
        guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }),
              let elementIndex = document.pages[pageIndex].elements.firstIndex(where: {
                  if case .text(let textElement) = $0 {
                      return textElement.id == id
                  }
                  return false
              }) else {
            return nil
        }

        return Binding(
            get: {
                guard case .text(let textElement) = self.document.pages[pageIndex].elements[elementIndex] else {
                    return TextElement(text: "", frame: Rect(x: 0, y: 0, width: 0, height: 0))
                }
                return textElement
            },
            set: { updatedValue in
                self.document.pages[pageIndex].elements[elementIndex] = .text(updatedValue)
            }
        )
    }

    func updateTextElement(_ element: TextElement) {
        guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }) else { return }

        for index in document.pages[pageIndex].elements.indices {
            guard case .text(let existingElement) = document.pages[pageIndex].elements[index], existingElement.id == element.id else {
                continue
            }

            var updatedElement = element
            updatedElement.isUserEdited = true
            document.pages[pageIndex].elements[index] = .text(updatedElement)
            document.analysisState = .refined
            statusMessage = "Text updated. Save again to write the edited PDF to Files."
            return
        }
    }

    func imageElementBinding(id: UUID) -> Binding<ImageElement>? {
        guard let pageIndex = document.pages.firstIndex(where: { $0.pageNumber == 1 }),
              let elementIndex = document.pages[pageIndex].elements.firstIndex(where: {
                  if case .image(let imageElement) = $0 {
                      return imageElement.id == id
                  }
                  return false
              }) else {
            return nil
        }

        return Binding(
            get: {
                guard case .image(let imageElement) = self.document.pages[pageIndex].elements[elementIndex] else {
                    return ImageElement(frame: Rect(x: 0, y: 0, width: 0, height: 0))
                }
                return imageElement
            },
            set: { updatedValue in
                self.document.pages[pageIndex].elements[elementIndex] = .image(updatedValue)
                self.document.analysisState = .refined
            }
        )
    }

    private func deduplicatedTextBlocks(_ blocks: [BackendTextBlock]) -> [BackendTextBlock] {
        let sortedBlocks = blocks.sorted { $0.confidence > $1.confidence }
        var uniqueBlocks: [BackendTextBlock] = []

        for candidate in sortedBlocks {
            let normalizedText = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedText.isEmpty { continue }

            let candidateRect = candidate.frame.cgRect
            
            // STRICT SPATIAL ANTI-OVERLAP: 
            // If any existing block physically overlaps this candidate by > 60%, 
            // it is structurally occupying the exact same space. The vision framework 
            // sometimes outputs multiple fragmented candidates for the same physical word.
            // We discard the lower confidence one regardless of string content.
            let physicallyOverlaps = uniqueBlocks.contains { existing in
                candidateRect.intersectionRatio(with: existing.frame.cgRect) > 0.60
            }

            let nearDuplicateText = uniqueBlocks.contains { existing in
                let existingText = existing.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !existingText.isEmpty else { return false }
                return normalizedText.jaroWinkler(existingText) > 0.93
            }

            if !physicallyOverlaps && !nearDuplicateText {
                uniqueBlocks.append(candidate)
            }
        }

        return uniqueBlocks
    }

    private static func makePage(from image: UIImage) -> DocumentPage {
        let pixelWidth = max(image.size.width, 1)
        let pixelHeight = max(image.size.height, 1)
        return DocumentPage(
            pageNumber: 1,
            size: PageSize(width: pixelWidth, height: pixelHeight),
            sourceImageData: image.jpegData(compressionQuality: 0.95),
            elements: []
        )
    }

    private func textQualityScore(for block: BackendTextBlock) -> Double {
        let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        let confidencePart = block.confidence
        let lengthPart = min(Double(text.count) / 24.0, 1.0)
        let area = block.frame.width * block.frame.height
        let geometryPart = area > 40 ? 1.0 : 0.5
        return (0.60 * confidencePart + 0.25 * lengthPart + 0.15 * geometryPart).clamped(to: 0...1)
    }

    private func imageQualityScore(for block: BackendImageBlock) -> Double {
        let confidencePart = block.confidence
        let area = block.frame.width * block.frame.height
        let geometryPart = area > 300 ? 1.0 : 0.45
        let colorPart: Double
        if let c = block.dominantColor {
            let maxChannel = max(c.red, c.green, c.blue)
            let minChannel = min(c.red, c.green, c.blue)
            colorPart = maxChannel - minChannel > 0.06 ? 1.0 : 0.55
        } else {
            colorPart = 0.45
        }
        return (0.55 * confidencePart + 0.20 * geometryPart + 0.25 * colorPart).clamped(to: 0...1)
    }

    private func tableQualityScore(for block: BackendTableBlock) -> Double {
        let confidencePart = block.confidence
        let rowCount = block.rows.count
        let colCount = block.rows.map(\.count).max() ?? 0
        let structurePart = (rowCount >= 2 && colCount >= 2) ? 1.0 : 0.45
        return (0.70 * confidencePart + 0.30 * structurePart).clamped(to: 0...1)
    }
}

private extension CGRect {
    func intersectionRatio(with other: CGRect) -> CGFloat {
        let intersectionRect = intersection(other)
        guard !intersectionRect.isNull, !intersectionRect.isEmpty else { return 0 }
        let minArea = min(width * height, other.width * other.height)
        guard minArea > 0 else { return 0 }
        return (intersectionRect.width * intersectionRect.height) / minArea
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum CaptureSource: String {
    case upload
    case camera
}
