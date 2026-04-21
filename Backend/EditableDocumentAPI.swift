import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

protocol DocumentAnalysisClient: Sendable {
    func analyze(documentID: UUID, pageIndex: Int, image: UIImage) async throws -> BackendAnalysisResponse
}

final class VisionDocumentAnalysisClient: DocumentAnalysisClient, @unchecked Sendable {
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .priorityRequestLow: true
    ])

    func analyze(documentID: UUID, pageIndex: Int, image: UIImage) async throws -> BackendAnalysisResponse {
        let normalized = normalizedUpright(image)
        guard let cgImage = normalized.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // ── Phase 1: Run all Vision passes in parallel ────────────────────────
        let (rawText, rawBoxes) = try recognizeAndDetect(cgImage: cgImage, imageSize: imageSize)

        // ── Phase 2: Classify boxes → tables vs plain image regions ──────────
        let (tableBlocks, imageBoxes) = classifyBoxes(
            rawBoxes:   rawBoxes,
            textBlocks: rawText,
            cgImage:    cgImage,
            imageSize:  imageSize
        )

        // ── Phase 3: Merge remaining (non-table) image boxes ─────────────────
        let mergedBoxes = mergeOverlappingBoxes(imageBoxes, imageSize: imageSize)

        // ── Phase 3.5: Suppress noisy regions over table/text-dense areas ────
        let tableRects = tableBlocks.map { $0.frame.cgRect }
        let textRects  = rawText.map { $0.frame.cgRect }
        let cleanedMergedBoxes = mergedBoxes.filter { item in
            let box = item.frame
            let boxArea = max(box.width * box.height, 1)

            let tableCoverage = tableRects.reduce(0.0) { partial, t in
                let overlap = box.intersection(t)
                guard !overlap.isNull, !overlap.isEmpty else { return partial }
                return partial + (overlap.width * overlap.height)
            } / boxArea
            if tableCoverage > 0.18 { return false }

            let textCoverage = textRects.reduce(0.0) { partial, t in
                let overlap = box.intersection(t)
                guard !overlap.isNull, !overlap.isEmpty else { return partial }
                return partial + (overlap.width * overlap.height)
            } / boxArea
            if textCoverage > 0.40 { return false }

            return true
        }

        // ── Phase 4: Colorize each merged box ─────────────────────────────────
        let colorizedBoxes: [(frame: CGRect, confidence: Float, color: RGBAColorCodable?)] =
            cleanedMergedBoxes.map { frame, conf in
                let color = sampleDominantColor(in: frame, from: cgImage, imageSize: imageSize)
                return (frame, conf, color)
            }

        // ── Phase 5: Remove boxes that are just text outlines (>85% overlap) ─
        let finalBoxes = colorizedBoxes.filter { item in
            !textRects.contains { tRect in
                tRect.intersectionRatio(with: item.frame) > 0.85
            }
        }

        let imageBlocks: [BackendImageBlock] = finalBoxes.map { item in
            BackendImageBlock(
                frame:        CGRectCodable(frame: item.frame),
                confidence:   Double(item.confidence),
                dominantColor: item.color
            )
        }

        // ── Phase 6: Fix text colors on coloured backgrounds ──────────────────
        let textBlocks: [BackendTextBlock] = rawText.map { block in
            let blockRect = block.frame.cgRect
            let underlyingBox = finalBoxes.first { item in
                item.frame.containsOrMostlyCovers(blockRect, threshold: 0.5)
            }
            var finalColor = block.textColor
            if let box = underlyingBox, let boxColor = box.color, !boxColor.isNeutralBackgroundLike {
                let boxLuma = 0.2126 * boxColor.red + 0.7152 * boxColor.green + 0.0722 * boxColor.blue
                let contrastColor: RGBAColorCodable = boxLuma > 0.5 ? .black : .white
                if let ink = finalColor {
                    let inkLuma = 0.2126 * ink.red + 0.7152 * ink.green + 0.0722 * ink.blue
                    if abs(inkLuma - boxLuma) < 0.25 { finalColor = contrastColor }
                } else { finalColor = contrastColor }
            }
            let bg = sampleDominantColor(in: blockRect, from: cgImage, imageSize: imageSize)
            return BackendTextBlock(
                text:            block.text,
                frame:           block.frame,
                fontSize:        block.fontSize,
                textColor:       finalColor,
                backgroundColor: bg,
                confidence:      block.confidence
            )
        }

        // ── Phase 7: Background sampling ──────────────────────────────────────
        let pageBgColor = samplePageBackgroundColor(cgImage: cgImage, imageSize: imageSize)

        return BackendAnalysisResponse(
            documentID: documentID,
            pageIndex:  pageIndex,
            page: BackendPage(
                pageSize:        BackendPageSize(width: Double(imageSize.width), height: Double(imageSize.height)),
                backgroundColor: pageBgColor,
                textBlocks:      textBlocks,
                imageBlocks:     imageBlocks,
                tableBlocks:     tableBlocks,
                confidence:      (textBlocks.isEmpty && imageBlocks.isEmpty && tableBlocks.isEmpty) ? 0.25 : 0.88
            )
        )
    }

    // ============================================================
    // MARK: - Core Vision Passes
    // ============================================================

    private func recognizeAndDetect(
        cgImage:   CGImage,
        imageSize: CGSize
    ) throws -> (textBlocks: [BackendTextBlock], imageBlocks: [BackendImageBlock]) {

        // ── Step 1: Pre-process the image once for best OCR quality ─────────
        // Run on the contrast-stretched grayscale — far better than raw colour
        // for low-contrast, faded, or printed documents.
        // ONE pass only: multiple passes on the same image produce duplicate text.
        let ocrImage = bestOCRImage(from: cgImage) ?? cgImage

        // ── Step 2: Discover all languages Vision supports on this device ────
        // This includes Bengali (bn-IN / bn) if available on iOS 16+.
        var languages = ["en-US"]
        let additionalLanguages = ["bn-IN", "bn", "hi-IN", "ar-SA", "zh-Hans", "zh-Hant", "ko-KR", "ja-JP"]
        if #available(iOS 16.0, *) {
            let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: .accurate,
                revision: VNRecognizeTextRequestRevision3
            )) ?? []
            for lang in additionalLanguages {
                if supported.contains(lang) { languages.append(lang) }
            }
        }
        // ── Step 3: Single OCR pass ───────────────────────────────────────────
        let textRequest = VNRecognizeTextRequest()
        if #available(iOS 16.0, *) { textRequest.revision = VNRecognizeTextRequestRevision3 }
        textRequest.recognitionLevel       = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages   = languages
        textRequest.minimumTextHeight      = 0.003

        let ocrHandler = VNImageRequestHandler(cgImage: ocrImage, orientation: .up, options: [:])
        do {
            try ocrHandler.perform([textRequest])
        } catch {
            // Fallback to Revision 2 if Revision 3 / Espresso fails
            if #available(iOS 16.0, *) {
                textRequest.revision = VNRecognizeTextRequestRevision2
                try? ocrHandler.perform([textRequest])
            }
        }

        // ── Step 4: Rectangle detection — Pass A on original, Pass B on sharpened
        let rectA = VNDetectRectanglesRequest()
        rectA.minimumAspectRatio  = 0.015
        rectA.maximumAspectRatio  = 1.0
        rectA.minimumSize         = 0.003
        rectA.maximumObservations = 250
        rectA.minimumConfidence   = 0.12
        rectA.quadratureTolerance = 30

        let rectB = VNDetectRectanglesRequest()
        rectB.minimumAspectRatio  = 0.015
        rectB.maximumAspectRatio  = 1.0
        rectB.minimumSize         = 0.003
        rectB.maximumObservations = 250
        rectB.minimumConfidence   = 0.10
        rectB.quadratureTolerance = 30

        let contourRequest = VNDetectContoursRequest()
        contourRequest.contrastAdjustment = 1.3
        contourRequest.detectsDarkOnLight = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([rectA])
        if let sharpenedCG = sharpenedImage(from: cgImage) {
            let handlerB = VNImageRequestHandler(cgImage: sharpenedCG, orientation: .up, options: [:])
            try? handlerB.perform([rectB])
        }
        // Run contour detection separately to prevent resource contention
        try? handler.perform([contourRequest])

        // ── Step 5: Build text blocks (no dedup needed — single pass) ─────────
        let textBlocks: [BackendTextBlock] = (textRequest.results ?? []).compactMap { obs in
            guard let top = obs.topCandidates(1).first, top.confidence > 0.22 else { return nil }
            let frame = visionToUIKit(obs.boundingBox, imageSize: imageSize)
            guard frame.width >= 1, frame.height >= 1 else { return nil }
            let normalizedText = normalizedOCRText(top.string, confidence: Double(top.confidence))
            let color = foregroundColorForText(in: frame, from: cgImage, imageSize: imageSize)
            return BackendTextBlock(
                text:       normalizedText,
                frame:      CGRectCodable(frame: frame),
                fontSize:   Double(frame.height * 0.78).clamped(to: 7...72),
                textColor:  color,
                backgroundColor: nil,
                confidence: Double(top.confidence)
            )
        }

        // ── Step 6: Collect shape/region candidates ───────────────────────────
        var candidateBoxes: [(CGRect, Float)] = []
        for obs in rectA.results ?? [] { candidateBoxes.append((obs.boundingBox, obs.confidence)) }
        for obs in rectB.results ?? [] { candidateBoxes.append((obs.boundingBox, obs.confidence)) }
        if let co = contourRequest.results?.first {
            for i in 0..<co.contourCount {
                if let c = try? co.contour(at: i), c.indexPath.count == 1 {
                    candidateBoxes.append((c.normalizedPath.boundingBox, 0.5))
                }
            }
        }

        let imageBlocks: [BackendImageBlock] = candidateBoxes.compactMap { box, conf in
            let frame = visionToUIKit(box, imageSize: imageSize).integral
            guard isValidRegion(frame, imageSize: imageSize) else { return nil }
            return BackendImageBlock(frame: CGRectCodable(frame: frame), confidence: Double(conf), dominantColor: nil)
        }

        return (textBlocks, imageBlocks)
    }

    // ── Build the single best OCR input image ────────────────────────────────
    // Grayscale + luminance sharpen + contrast boost = best single-pass input.

    private func bestOCRImage(from cgImage: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: cgImage)

        // Desaturate
        let grey = CIFilter.colorMonochrome()
        grey.inputImage = ci
        grey.color      = CIColor(red: 0.299, green: 0.587, blue: 0.114)
        grey.intensity  = 1.0

        // Contrast + tiny brightness lift
        let ctrl = CIFilter.colorControls()
        ctrl.inputImage  = grey.outputImage ?? ci
        ctrl.saturation  = 0.0
        ctrl.contrast    = 1.40
        ctrl.brightness  = 0.01

        // Sharpen edges
        let sharp = CIFilter.sharpenLuminance()
        sharp.inputImage = ctrl.outputImage ?? ci
        sharp.sharpness  = 0.75
        sharp.radius     = 1.2

        guard let out = sharp.outputImage else { return nil }
        let extent = ci.extent
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        return ciContext.createCGImage(out, from: extent)
    }

    // ── Kept for backward-compat, now unused — single pass eliminates need ──
    private struct OCRVariant {
        let image: CGImage
        let scale: CGFloat
    }

    private func buildOCRVariants(from cgImage: CGImage) -> [OCRVariant] {
        [OCRVariant(image: cgImage, scale: 1.0)]
    }

    // ── Remove duplicate/overlapping text observations ────────────────────────
    // When multiple passes find the same word, keep the one with higher confidence.

    private func deduplicateTextObservations(
        _ obs: [VNRecognizedTextObservation]
    ) -> [VNRecognizedTextObservation] {
        // Sort best-confidence first — we prefer keeping the most confident reading.
        let sorted = obs.sorted {
            ($0.topCandidates(1).first?.confidence ?? 0) > ($1.topCandidates(1).first?.confidence ?? 0)
        }
        var result: [VNRecognizedTextObservation] = []
        for candidate in sorted {
            let cText = candidate.topCandidates(1).first?.string ?? ""
            let cBox  = candidate.boundingBox

            let isDuplicate = result.contains { existing in
                let eBox = existing.boundingBox
                // ── IoU (Intersection over Union) ────────────────────────────
                let inter = cBox.intersection(eBox)
                guard !inter.isNull, !inter.isEmpty else { return false }
                let interArea = inter.width * inter.height
                let unionArea = cBox.width*cBox.height + eBox.width*eBox.height - interArea
                let iou = unionArea > 0 ? interArea / unionArea : 0

                // High IoU alone → duplicate
                if iou > 0.20 { return true }

                // Moderate spatial overlap + similar text → duplicate
                if iou > 0.08 {
                    let eText = existing.topCandidates(1).first?.string ?? ""
                    if textSimilarity(cText, eText) > 0.65 { return true }
                }
                return false
            }
            if !isDuplicate { result.append(candidate) }
        }
        return result
    }

    private func normalizedOCRText(_ value: String, confidence: Double) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return "[UNCLEAR]" }
        if confidence >= 0.80 { return trimmed }

        let alnumCount = trimmed.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let ratio = Double(alnumCount) / Double(max(trimmed.count, 1))
        if ratio < 0.45 || trimmed.count < 2 {
            return "[UNCLEAR]"
        }
        return trimmed
    }

    /// Normalised Levenshtein similarity in [0,1].
    private func textSimilarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        guard !a.isEmpty, !b.isEmpty  else { return 0.0 }
        if a == b { return 1.0 }

        let aArr = Array(a), bArr = Array(b)
        let m = aArr.count, n = bArr.count
        var dp = Array(0...n)
        for i in 1...m {
            var prev = dp
            dp[0] = i
            for j in 1...n {
                dp[j] = aArr[i-1] == bArr[j-1]
                    ? prev[j-1]
                    : 1 + min(prev[j], min(dp[j-1], prev[j-1]))
            }
        }
        return 1.0 - Double(dp[n]) / Double(max(m, n))
    }


    // ============================================================
    // MARK: - Table Classification Engine
    //
    // Strategy:
    //  1. After Vision finds rectangle candidates, cluster those whose
    //     gridlines are COLLINEAR and EVENLY SPACED in X or Y.
    //  2. A cluster of ≥2 collinear rects with shared edges = table.
    //  3. For each table candidate, collect the text blocks that fall
    //     inside it and group them by detected row/column centres.
    //  4. Return `BackendTableBlock` with the cell text matrix, plus
    //     remove those rectangles from the imageBox list.
    // ============================================================

    private func classifyBoxes(
        rawBoxes:   [BackendImageBlock],
        textBlocks: [BackendTextBlock],
        cgImage:    CGImage,
        imageSize:  CGSize
    ) -> (tables: [BackendTableBlock], imageBoxes: [BackendImageBlock]) {

        // Convert to pixel rects
        var pixelBoxes: [(rect: CGRect, conf: Float)] = rawBoxes.map {
            ($0.frame.cgRect, Float($0.confidence))
        }

        var tableBlocks: [BackendTableBlock] = []
        var usedIndices = Set<Int>()

        // ── Step 1: group by collinear / aligned shared edges ─────────────────
        // For each box, check how many other boxes share a nearly-equal left, right,
        // top or bottom edge. 3+ sharing → table column/row marker.
        let alignTolerance: CGFloat = imageSize.width * 0.015   // 1.5% of width

        // Build an adjacency: pairs whose edges share a side
        var groups: [[Int]] = []
        var ungrouped = Array(0..<pixelBoxes.count)

        while !ungrouped.isEmpty {
            let seed = ungrouped.removeFirst()
            var cluster: [Int] = [seed]

            var i = 0
            while i < ungrouped.count {
                let candidate = ungrouped[i]
                if isAdjacentOrAligned(
                    pixelBoxes[seed].rect,
                    pixelBoxes[candidate].rect,
                    tolerance: alignTolerance
                ) {
                    cluster.append(candidate)
                    ungrouped.remove(at: i)
                } else {
                    i += 1
                }
            }
            groups.append(cluster)
        }

        // ── Step 2: clusters with ≥ 3 aligned rects = potential table ────────
        for group in groups {
            guard group.count >= 3 else { continue }
            let rects = group.map { pixelBoxes[$0].rect }

            // Check that they plausibly form a grid (≥2 unique X origins, ≥2 unique Y origins,
            // OR they're all in the same row/column)
            let uniqueXs = Set(rects.map { roundToGrid($0.minX, step: alignTolerance) }).count
            let uniqueYs = Set(rects.map { roundToGrid($0.minY, step: alignTolerance) }).count
            let isGrid = (uniqueXs >= 2 && uniqueYs >= 2) ||
                         (uniqueXs == 1 && rects.count >= 3) ||
                         (uniqueYs == 1 && rects.count >= 3)
            guard isGrid else { continue }

            // Compute bounding box of the cluster
            let union = rects.reduce(CGRect.null) { $0.union($1) }
            guard isValidRegion(union, imageSize: imageSize) else { continue }

            // Collect & arrange text inside this region
            let cellMatrix = assembleCellMatrix(
                tableRect:  union,
                cellRects:  rects,
                textBlocks: textBlocks
            )
            guard !cellMatrix.isEmpty else { continue }

            let avgConf = group.map { Double(pixelBoxes[$0].conf) }.reduce(0,+) / Double(group.count)
            tableBlocks.append(BackendTableBlock(
                frame:      CGRectCodable(frame: union),
                rows:       cellMatrix,
                confidence: avgConf
            ))
            group.forEach { usedIndices.insert($0) }
        }

        // ── Step 3: also detect tables from VNRecognizeTextRequest grid cues ──
        // Even without rectangle observations, if we see text arranged in a tight
        // column-aligned grid, we synthesize a table.
        let syntheticTable = detectTextGridTable(textBlocks: textBlocks, imageSize: imageSize)
        if let tbl = syntheticTable {
            let isDuplicate = tableBlocks.contains { existing in
                existing.frame.cgRect.intersectionRatio(with: tbl.frame.cgRect) > 0.50
            }
            if !isDuplicate {
                tableBlocks.append(tbl)
            }
        }

        let remainingBoxes = pixelBoxes.enumerated()
            .filter { !usedIndices.contains($0.offset) }
            .map { BackendImageBlock(frame: CGRectCodable(frame: $0.element.rect),
                                    confidence: Double($0.element.conf),
                                    dominantColor: nil) }

        return (tableBlocks, remainingBoxes)
    }

    // ── Are two rects adjacent or share an aligned edge? ─────────────────────
    private func isAdjacentOrAligned(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        // They share a nearly-equal left/right alignment
        let shareLeft   = abs(a.minX - b.minX) < tolerance
        let shareRight  = abs(a.maxX - b.maxX) < tolerance
        let shareTop    = abs(a.minY - b.minY) < tolerance
        let shareBottom = abs(a.maxY - b.maxY) < tolerance

        // Or they are directly adjacent (touching within tolerance)
        let touchH = abs(a.maxX - b.minX) < tolerance || abs(b.maxX - a.minX) < tolerance
        let touchV = abs(a.maxY - b.minY) < tolerance || abs(b.maxY - a.minY) < tolerance
        let overlapH = a.minX < b.maxX + tolerance && b.minX < a.maxX + tolerance
        let overlapV = a.minY < b.maxY + tolerance && b.minY < a.maxY + tolerance

        // Two aligned edges in at least one axis, and overlap in the perpendicular axis
        let colAligned = (shareLeft || shareRight) && overlapH
        let rowAligned = (shareTop  || shareBottom) && overlapV
        let adjacent   = (touchH && overlapV) || (touchV && overlapH)

        return colAligned || rowAligned || adjacent
    }

    private func roundToGrid(_ v: CGFloat, step: CGFloat) -> Int {
        Int(v / step)
    }

    // ── Assign text blocks to cells and build a row-major string matrix ───────
    private func assembleCellMatrix(
        tableRect:  CGRect,
        cellRects:  [CGRect],
        textBlocks: [BackendTextBlock]
    ) -> [[String]] {

        guard !cellRects.isEmpty else { return [] }

        // Find text blocks inside or intersecting the table area
        let insideText = textBlocks.filter { blk in
            tableRect.intersects(blk.frame.cgRect)
        }
        guard !insideText.isEmpty else {
            // No OCR text → build empty skeleton from cell rects
            let sortedYs = Array(Set(cellRects.map { roundToGrid($0.midY, step: tableRect.height * 0.08) })).sorted()
            let sortedXs = Array(Set(cellRects.map { roundToGrid($0.midX, step: tableRect.width  * 0.08) })).sorted()
            return sortedYs.map { _ in sortedXs.map { _ in "" } }
        }

        // Sort unique row centres from detected cell Y-midpoints
        let rowStep = max(tableRect.height * 0.04, 6)
        let colStep = max(tableRect.width  * 0.04, 6)

        let rawRowCentres = cellRects.map { $0.midY }
        let rowCentres = clusterCentres(rawRowCentres, step: rowStep).sorted()

        let rawColCentres = cellRects.map { $0.midX }
        let colCentres = clusterCentres(rawColCentres, step: colStep).sorted()

        guard !rowCentres.isEmpty, !colCentres.isEmpty else { return [] }

        // Build empty grid
        var grid: [[String]] = Array(repeating: Array(repeating: "", count: colCentres.count),
                                     count: rowCentres.count)

        // Place each text block into its nearest row/col
        for blk in insideText {
            let bMidY = blk.frame.cgRect.midY
            let bMidX = blk.frame.cgRect.midX
            let rowIdx = nearestIndex(bMidY, in: rowCentres)
            let colIdx = nearestIndex(bMidX, in: colCentres)
            let existing = grid[rowIdx][colIdx]
            grid[rowIdx][colIdx] = existing.isEmpty ? blk.text : existing + " " + blk.text
        }

        // Remove completely empty rows
        return grid.filter { row in row.contains { !$0.isEmpty } }
    }

    // ── Detect tables from text alignment only (no rectangle Vision hits) ─────
    // If ≥3 text lines have tokens at the same X positions → tabular layout.
    private func detectTextGridTable(
        textBlocks: [BackendTextBlock],
        imageSize:  CGSize
    ) -> BackendTableBlock? {

        guard textBlocks.count >= 6 else { return nil }   // need enough text to form a table
        let colTol: CGFloat = imageSize.width * 0.018

        // Group blocks by approximate Y (row buckets)
        var rowBuckets: [[BackendTextBlock]] = []
        let sortedByY = textBlocks.sorted { $0.frame.cgRect.minY < $1.frame.cgRect.minY }
        for blk in sortedByY {
            if let last = rowBuckets.last,
               abs(last[0].frame.cgRect.midY - blk.frame.cgRect.midY) < blk.frame.cgRect.height * 1.4 {
                rowBuckets[rowBuckets.count - 1].append(blk)
            } else {
                rowBuckets.append([blk])
            }
        }

        // Need ≥3 rows with ≥2 cols each
        let multiColRows = rowBuckets.filter { $0.count >= 2 }
        guard multiColRows.count >= 3 else { return nil }

        // Verify column alignment: collect all minX values, check ≥2 are shared across ≥3 rows
        var colOccurrences: [Int: Int] = [:]   // gridded-X → row count
        for row in multiColRows {
            let xs = Set(row.map { roundToGrid($0.frame.cgRect.minX, step: colTol) })
            xs.forEach { colOccurrences[$0, default: 0] += 1 }
        }
        let sharedCols = colOccurrences.filter { $0.value >= 3 }
        guard sharedCols.count >= 2 else { return nil }

        // We have a text-grid table — build the bounding rect and cell matrix
        let allBlocks = multiColRows.flatMap { $0 }
        let union = allBlocks.map { $0.frame.cgRect }.reduce(CGRect.null) { $0.union($1) }
        guard isValidRegion(union, imageSize: imageSize) else { return nil }

        // Synthesize "cell rects" using row heights and shared column positions
        let sortedSharedXs = sharedCols.keys.map { CGFloat($0) * colTol }.sorted()
        var cellRects: [CGRect] = []
        for row in multiColRows {
            for cx in sortedSharedXs {
                let nearBlock = row.min(by: { abs($0.frame.cgRect.midX - cx) < abs($1.frame.cgRect.midX - cx) })
                if let nb = nearBlock {
                    cellRects.append(nb.frame.cgRect)
                }
            }
        }

        let matrix = assembleCellMatrix(tableRect: union, cellRects: cellRects, textBlocks: allBlocks)
        guard !matrix.isEmpty else { return nil }

        return BackendTableBlock(
            frame:      CGRectCodable(frame: union),
            rows:       matrix,
            confidence: 0.82
        )
    }

    // ── k-means–style 1D centre clustering ───────────────────────────────────
    private func clusterCentres(_ values: [CGFloat], step: CGFloat) -> [CGFloat] {
        var buckets: [CGFloat: [CGFloat]] = [:]
        for v in values {
            let key = CGFloat(Int(v / step)) * step
            buckets[key, default: []].append(v)
        }
        return buckets.values.map { $0.reduce(0,+) / CGFloat($0.count) }.sorted()
    }

    private func nearestIndex(_ value: CGFloat, in array: [CGFloat]) -> Int {
        array.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 0
    }

    // ============================================================
    // MARK: - Background Sampler
    // ============================================================

    private func samplePageBackgroundColor(cgImage: CGImage, imageSize: CGSize) -> RGBAColorCodable? {
        let inset: CGFloat = 8
        let w = imageSize.width - inset * 2
        let h = imageSize.height - inset * 2
        guard w > 0, h > 0 else { return nil }

        var reds = [Double](), greens = [Double](), blues = [Double]()
        for row in 0..<5 {
            for col in 0..<5 {
                let cx = inset + w * CGFloat(col) / 4
                let cy = inset + h * CGFloat(row) / 4
                let patch = CGRect(x: cx-2, y: cy-2, width: 4, height: 4)
                if let c = sampleDominantColor(in: patch, from: cgImage, imageSize: imageSize) {
                    reds.append(c.red); greens.append(c.green); blues.append(c.blue)
                }
            }
        }
        guard !reds.isEmpty else { return nil }
        reds.sort(); greens.sort(); blues.sort()
        let mid = reds.count / 2
        let r = reds[mid], g = greens[mid], b = blues[mid]
        let luma = 0.2126*r + 0.7152*g + 0.0722*b
        let maxC = max(r,g,b), minC = min(r,g,b)
        let sat  = maxC < 0.001 ? 0.0 : (maxC-minC)/maxC
        if luma > 0.94 && sat < 0.05 { return nil }
        return RGBAColorCodable(red: r, green: g, blue: b, alpha: 1.0)
    }

    // ============================================================
    // MARK: - Box Merging
    // ============================================================

    private func mergeOverlappingBoxes(
        _ blocks:    [BackendImageBlock],
        imageSize:   CGSize
    ) -> [(frame: CGRect, confidence: Float)] {
        var rects: [(CGRect, Float)] = blocks.map { ($0.frame.cgRect, Float($0.confidence)) }
        var merged = true
        while merged {
            merged = false
            var result: [(CGRect, Float)] = []
            var used = Array(repeating: false, count: rects.count)
            for i in 0..<rects.count {
                guard !used[i] else { continue }
                var cur = rects[i].0, maxConf = rects[i].1
                for j in (i+1)..<rects.count {
                    guard !used[j] else { continue }
                    if cur.insetBy(dx: -12, dy: -12).intersects(rects[j].0) {
                        cur = cur.union(rects[j].0)
                        maxConf = max(maxConf, rects[j].1)
                        used[j] = true; merged = true
                    }
                }
                result.append((cur, maxConf))
                used[i] = true
            }
            rects = result
        }
        return rects.filter { isValidRegion($0.0.integral, imageSize: imageSize) }
    }

    // ============================================================
    // MARK: - Coordinate Conversion
    // ============================================================

    private func visionToUIKit(_ box: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x:      box.minX * imageSize.width,
            y:      (1.0 - box.maxY) * imageSize.height,
            width:  box.width  * imageSize.width,
            height: box.height * imageSize.height
        ).intersection(CGRect(origin: .zero, size: imageSize))
    }

    // ============================================================
    // MARK: - Color Sampling
    // ============================================================

    private func sampleDominantColor(in rect: CGRect, from cgImage: CGImage, imageSize: CGSize) -> RGBAColorCodable? {
        let ciRect  = uikitToCICoords(rect, imageHeight: CGFloat(cgImage.height))
        let ciImage = CIImage(cgImage: cgImage)
        let cropped = ciImage.cropped(to: ciRect)
        
        guard !cropped.extent.isEmpty, !cropped.extent.isInfinite,
              cropped.extent.width >= 1, cropped.extent.height >= 1 else { return nil }
              
        let filter  = CIFilter.areaAverage()
        filter.inputImage = cropped
        filter.extent = cropped.extent
        
        guard let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return RGBAColorCodable(red: Double(px[0])/255, green: Double(px[1])/255,
                                blue: Double(px[2])/255, alpha: 1.0)
    }

    private func foregroundColorForText(in rect: CGRect, from cgImage: CGImage, imageSize: CGSize) -> RGBAColorCodable? {
        let expanded = rect.insetBy(dx: -2, dy: -2).intersection(CGRect(origin: .zero, size: imageSize))
        guard expanded.width > 2, expanded.height > 2 else { return nil }
        let ciRect  = uikitToCICoords(expanded, imageHeight: CGFloat(cgImage.height))
        let ciImage = CIImage(cgImage: cgImage)
        let cropped = ciImage.cropped(to: ciRect)
        
        guard !cropped.extent.isEmpty, !cropped.extent.isInfinite,
              cropped.extent.width >= 1, cropped.extent.height >= 1 else { return nil }
              
        let avgF = CIFilter.areaAverage()
        avgF.inputImage = cropped
        avgF.extent = cropped.extent
        
        var avgPx = [UInt8](repeating: 0, count: 4)
        if let avgOut = avgF.outputImage {
            ciContext.render(avgOut, toBitmap: &avgPx, rowBytes: 4,
                             bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                             format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        let avgLuma = 0.2126*Double(avgPx[0])/255 + 0.7152*Double(avgPx[1])/255 + 0.0722*Double(avgPx[2])/255

        let extrema: CIFilter = avgLuma > 0.45
            ? (CIFilter.areaMinimum() as CIFilter)
            : (CIFilter.areaMaximum() as CIFilter)
        extrema.setValue(cropped, forKey: kCIInputImageKey)
        extrema.setValue(CIVector(cgRect: cropped.extent), forKey: kCIInputExtentKey)
        guard let exOut = extrema.outputImage else { return nil }
        var ink = [UInt8](repeating: 0, count: 4)
        ciContext.render(exOut, toBitmap: &ink, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

        let inkR = Double(ink[0])/255, inkG = Double(ink[1])/255, inkB = Double(ink[2])/255
        let inkLuma = 0.2126*inkR + 0.7152*inkG + 0.0722*inkB
        if abs(inkLuma - avgLuma) < 0.08 { return avgLuma > 0.5 ? .black : .white }
        return RGBAColorCodable(red: inkR, green: inkG, blue: inkB, alpha: 1.0)
    }

    private func uikitToCICoords(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // ============================================================
    // MARK: - Image Sharpening
    // ============================================================

    private func sharpenedImage(from cgImage: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: cgImage)
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = ci; sharpen.sharpness = 1.2
        let contrast = CIFilter.colorControls()
        contrast.inputImage = sharpen.outputImage ?? ci
        contrast.contrast = 1.4; contrast.saturation = 1.0; contrast.brightness = 0.0
        guard let out = contrast.outputImage else { return nil }
        let extent = ci.extent
        guard !extent.isEmpty, !extent.isInfinite else { return nil }
        return ciContext.createCGImage(out, from: extent)
    }

    // ============================================================
    // MARK: - Normalization
    // ============================================================

    private func normalizedUpright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return out
    }

    // ============================================================
    // MARK: - Region Validation
    // ============================================================

    private func isValidRegion(_ frame: CGRect, imageSize: CGSize) -> Bool {
        guard frame.width >= 12, frame.height >= 12 else { return false }
        let imageArea = max(imageSize.width * imageSize.height, 1)
        let areaRatio = (frame.width * frame.height) / imageArea
        guard areaRatio >= 0.0005, areaRatio <= 0.90 else { return false }
        let m: CGFloat = 3
        let isFullPage = frame.minX <= m && frame.minY <= m
                      && frame.maxX >= imageSize.width - m
                      && frame.maxY >= imageSize.height - m
        guard !isFullPage else { return false }
        let aspect = max(frame.width, frame.height) / max(min(frame.width, frame.height), 1)
        guard aspect <= 20.0 else { return false }
        return true
    }
}

// ============================================================
// MARK: - CGRect helpers
// ============================================================

private extension CGRect {
    func intersectionRatio(with other: CGRect) -> CGFloat {
        let overlap = intersection(other)
        guard !overlap.isNull, !overlap.isEmpty else { return 0 }
        let minArea = min(width*height, other.width*other.height)
        guard minArea > 0 else { return 0 }
        return (overlap.width * overlap.height) / minArea
    }

    func containsOrMostlyCovers(_ rect: CGRect, threshold: CGFloat) -> Bool {
        let overlap = intersection(rect)
        guard !overlap.isNull, !overlap.isEmpty else { return false }
        let rectArea = rect.width * rect.height
        guard rectArea > 0 else { return false }
        return (overlap.width * overlap.height) / rectArea >= threshold
    }
}

private extension CGRectCodable {
    init(frame: CGRect) {
        self.init(x: Double(frame.minX), y: Double(frame.minY),
                  width: Double(frame.width), height: Double(frame.height))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// ============================================================
// MARK: - Backend Data Structures
// ============================================================

struct BackendAnalysisResponse: Codable {
    var documentID: UUID
    var pageIndex:  Int
    var page:       BackendPage
}

struct BackendPage: Codable {
    var pageSize:        BackendPageSize
    var backgroundColor: RGBAColorCodable?
    var textBlocks:      [BackendTextBlock]
    var imageBlocks:     [BackendImageBlock]
    var tableBlocks:     [BackendTableBlock]
    var confidence:      Double
}

struct BackendPageSize: Codable { var width: Double; var height: Double }

struct BackendTextBlock: Codable {
    var text:       String
    var frame:      CGRectCodable
    var fontSize:   Double?
    var textColor:  RGBAColorCodable?
    var backgroundColor: RGBAColorCodable?
    var confidence: Double
}

struct BackendImageBlock: Codable {
    var frame:         CGRectCodable
    var confidence:    Double
    var dominantColor: RGBAColorCodable?
}

struct BackendTableBlock: Codable {
    var frame:      CGRectCodable
    var rows:       [[String]]
    var confidence: Double
}

struct CGRectCodable: Codable {
    var x, y, width, height: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct RGBAColorCodable: Codable {
    var red, green, blue, alpha: Double
    static let black = RGBAColorCodable(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = RGBAColorCodable(red: 1, green: 1, blue: 1, alpha: 1)

    var isNeutralBackgroundLike: Bool { false }

    func distanceTo(_ other: RGBAColorCodable) -> Double {
        let dr = red-other.red, dg = green-other.green, db = blue-other.blue
        return sqrt(dr*dr + dg*dg + db*db)
    }
}
