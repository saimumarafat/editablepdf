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
                analysisState: .analyzing
            )
            statusMessage = "Image normalized and ready for analysis."

            await analyzeIfNeeded(using: analysisClient)

            isProcessing = false
            statusMessage = "Image is ready. You can edit or save from the main screen."
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

        let data = try exportService.export(document: document)
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

        // ── CRITICAL: Always use the original scanned image as the page background.
        // Attempting to reconstruct colours from Vision's sampler produces wrong results
        // (especially for coloured backgrounds, tables, or non-Latin scripts like Bangla).
        page.background = .originalImage

        let textBlocks = deduplicatedTextBlocks(response.page.textBlocks)

        // Auto-detected text: store for the editor overlay but mark isUserEdited = false.
        // The exporter will skip these so the original image is preserved.
        page.elements = textBlocks.map { block in
            .text(TextElement(
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
                isUserEdited: true   // All detected text is now considered "live" and editable
            ))
        }

        // ── Image blocks & table blocks are intentionally NOT added to page.elements.
        // They were drawing opaque boxes over the original image and misclassifying
        // coloured table rows as image regions. The source image shows them correctly.

        document.pages[0] = page
        document.analysisState = .refined
        statusMessage = "Analysis complete. Detected \(textBlocks.count) text block(s). Use the editor to add or correct content."
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

            document.pages[pageIndex].elements[index] = .text(element)
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
                // VERY aggressive overlap threshold (20%) to kill all ghosting
                candidateRect.intersectionRatio(with: existing.frame.cgRect) > 0.20
            }

            if !physicallyOverlaps {
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

enum CaptureSource: String {
    case upload
    case camera
}
