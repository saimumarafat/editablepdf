import Foundation
import UIKit
import PDFKit
import CoreGraphics

protocol PDFExporting: Sendable {
    func export(document: EditableDocument) throws -> Data
}

final class PDFExportService: PDFExporting, @unchecked Sendable {
    func export(document: EditableDocument) throws -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let meta: [String: Any] = [
            kCGPDFContextCreator as String: "EditablePDF",
            kCGPDFContextTitle   as String: document.title
        ]
        format.documentInfo = meta

        let bounds = document.pages.first?.size.cgRect ?? PageSize.a4.cgRect
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        return renderer.pdfData { context in
            for page in document.pages {
                let pageRect = page.size.cgRect
                context.beginPage(withBounds: pageRect, pageInfo: [:])

                UIGraphicsPushContext(context.cgContext)

                // If the page has extracted elements, build a reconstructed PDF page.
                // Otherwise, fall back to embedding the original source image.
                let hasStructuredElements = !page.elements.isEmpty

                if hasStructuredElements {
                    fillBackground(for: page, in: pageRect)

                    let sourceImage = page.sourceImageData.flatMap(UIImage.init(data:))
                    for element in page.elements {
                        switch element {
                        case .text(let text):
                            drawText(text, pageRect: pageRect)
                        case .image(let image):
                            drawImageElement(image, pageRect: pageRect, sourceImage: sourceImage)
                        case .table(let table):
                            drawTable(table, pageRect: pageRect)
                        }
                    }
                } else if let data = page.sourceImageData, let img = UIImage(data: data) {
                    img.draw(in: pageRect)
                } else {
                    fillBackground(for: page, in: pageRect)
                }

                UIGraphicsPopContext()
            }
        }
    }

    private func fillBackground(for page: DocumentPage, in pageRect: CGRect) {
        UIColor.white.setFill()
        UIRectFill(pageRect)
    }

    // MARK: - Text

    private func drawText(_ text: TextElement, pageRect: CGRect) {
        let frame = clamp(text.frame.cgRect, to: pageRect)
        guard frame.width > 1, frame.height > 1 else { return }

        // Add a background patch when the text block has a detected background color.
        // This helps preserve row/box coloring on reconstructed pages.
        // Do not paint sampled background patches in normalized mode.

        // ── Step 2: Draw real PDF text on top ─────────────────────────────
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = text.alignment.nsTextAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping

        let fontSize = max(text.fontSize, 9)
        let font = AppFont.resolveUIFont(id: text.fontName, size: fontSize)

        let inkColor = UIColor.black

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: inkColor,
            .paragraphStyle:  paragraphStyle
        ]

        (text.text as NSString).draw(in: frame, withAttributes: attrs)
    }

    // MARK: - Image / Color Box

    private func drawImageElement(_ element: ImageElement, pageRect: CGRect, sourceImage: UIImage?) {
        let frame = clamp(element.frame.cgRect, to: pageRect)
        guard frame.width > 1, frame.height > 1 else { return }

        if element.renderStyle == .imageSnippet,
           let src = sourceImage,
           let cgSrc = src.cgImage {
            drawSnippet(from: cgSrc, sourceImageSize: src.size, into: frame, pageRect: pageRect)
        } else {
            drawSolidColorBox(element.fillColor, into: frame)
        }
    }

    /// Crops the matching pixel region from the source image and draws it at the element frame.
    private func drawSnippet(from cgImage: CGImage, sourceImageSize: CGSize, into frame: CGRect, pageRect: CGRect) {
        // Map element frame (in page-point coords) → pixel coords in source image
        let scaleX = CGFloat(cgImage.width)  / pageRect.width
        let scaleY = CGFloat(cgImage.height) / pageRect.height
        let cropRect = CGRect(
            x: frame.minX * scaleX,
            y: frame.minY * scaleY,
            width: frame.width  * scaleX,
            height: frame.height * scaleY
        ).integral
        if let cropped = cgImage.cropping(to: cropRect) {
            UIImage(cgImage: cropped).draw(in: frame)
        }
    }

    /// Fills the frame with the detected dominant color (or a visible fallback).
    private func drawSolidColorBox(_ color: RGBAColor?, into frame: CGRect) {
        // If a color was detected and it is not near-white background, use it.
        let fillColor: UIColor
        if let c = color {
            let luma = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
            let maxCh = max(c.red, c.green, c.blue)
            let minCh = min(c.red, c.green, c.blue)
            let sat = maxCh < 0.001 ? 0.0 : (maxCh - minCh) / maxCh

            // Use the detected color if it has any meaningful chroma OR is clearly dark
            if sat > 0.06 || luma < 0.85 {
                fillColor = UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0)
            } else {
                // Very light / white detected — use a subtle gray so the box is visible
                fillColor = UIColor(white: 0.88, alpha: 1.0)
            }
        } else {
            // No color detected — use a neutral placeholder
            fillColor = UIColor(white: 0.85, alpha: 1.0)
        }

        fillColor.setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: 2).fill()

        // Thin border so box boundaries are clearly visible
        UIColor.black.withAlphaComponent(0.18).setStroke()
        let border = UIBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2)
        border.lineWidth = 0.5
        border.stroke()
    }

    // MARK: - Table

    private func drawTable(_ table: TableElement, pageRect: CGRect) {
        let frame = clamp(table.frame.cgRect, to: pageRect)
        guard frame.width > 4, frame.height > 4, !table.rows.isEmpty else { return }

        let rows    = table.rows
        let numRows = rows.count
        let numCols = rows.map { $0.count }.max() ?? 1
        let cellH   = frame.height / CGFloat(numRows)
        let cellW   = frame.width  / CGFloat(numCols)

        // Header row background for clearer hierarchy.
        if numRows > 0 {
            let headerRect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: cellH)
            UIColor(white: 0.92, alpha: 0.9).setFill()
            UIBezierPath(rect: headerRect).fill()
        }

        // ── 1. Grid lines only — NO opaque fills, background shows through ────
        for r in 0...numRows {
            let y    = frame.minY + CGFloat(r) * cellH
            let path = UIBezierPath()
            path.move(to: CGPoint(x: frame.minX, y: y))
            path.addLine(to: CGPoint(x: frame.maxX, y: y))
            let edge = (r == 0 || r == numRows)
            UIColor(white: 0.14, alpha: edge ? 0.9 : 0.5).setStroke()
            path.lineWidth = edge ? 1.4 : 0.65
            path.stroke()
        }
        for c in 0...numCols {
            let x    = frame.minX + CGFloat(c) * cellW
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: frame.minY))
            path.addLine(to: CGPoint(x: x, y: frame.maxY))
            let edge = (c == 0 || c == numCols)
            UIColor(white: 0.14, alpha: edge ? 0.9 : 0.5).setStroke()
            path.lineWidth = edge ? 1.4 : 0.65
            path.stroke()
        }

        // ── 2. Cell text (drawn after grid so it's on top) ────────────────────
        let fontSize  = max(8, min(17, cellH * 0.58))
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineBreakMode = .byTruncatingTail
        paraStyle.alignment     = .left

        for r in 0..<numRows {
            let row     = rows[r]
            let y       = frame.minY + CGFloat(r) * cellH
            let weight: UIFont.Weight = (r == 0) ? .bold : .regular
            let rowFont = UIFont.systemFont(ofSize: fontSize, weight: weight)

            for c in 0..<numCols {
                let x    = frame.minX + CGFloat(c) * cellW
                let text = c < row.count ? row[c] : ""
                guard !text.isEmpty else { continue }

                let textRect = CGRect(x: x + 4, y: y + 3,
                                     width: cellW - 8, height: cellH - 6)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font:            rowFont,
                    .foregroundColor: UIColor(white: 0.08, alpha: 0.92),
                    .paragraphStyle:  paraStyle
                ]
                (text as NSString).draw(in: textRect, withAttributes: attrs)
            }
        }
    }

    // MARK: - Helpers

    private func clamp(_ rect: CGRect, to pageRect: CGRect) -> CGRect {
        rect.intersection(pageRect)
    }
}

// MARK: - Extensions

private extension PageSize {
    var cgRect: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
}

private extension TextAlignmentOption {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left:      return .left
        case .center:    return .center
        case .right:     return .right
        case .justified: return .justified
        case .natural:   return .natural
        }
    }
}
