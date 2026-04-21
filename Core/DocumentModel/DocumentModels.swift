import Foundation
import CoreGraphics
import UIKit

struct EditableDocument: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var pages: [DocumentPage]
    var sourceImageURLs: [URL] = []
    var analysisState: AnalysisState = .idle
    var exportMode: ExportMode = .fidelity

    static func empty() -> EditableDocument {
        EditableDocument(title: "Untitled Document", pages: [])
    }
}

enum ExportMode: String, Codable, Equatable, CaseIterable {
    case fidelity = "Fidelity"
    case hybrid = "Hybrid"
    case structured = "Structured"
}

struct DocumentPage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var pageNumber: Int
    var size: PageSize
    var background: PageBackground = .white
    var sourceImageData: Data?
    var elements: [PageElement]
}

struct PageSize: Codable, Equatable {
    var width: CGFloat
    var height: CGFloat

    static let letter = PageSize(width: 612, height: 792)
    static let a4 = PageSize(width: 595.2, height: 841.8)
}

enum PageBackground: Codable, Equatable {
    case white
    case originalImage
    case color(red: Double, green: Double, blue: Double, alpha: Double)
}

enum AnalysisState: String, Codable {
    case idle
    case analyzing
    case refined
    case failed
}

enum PageElement: Identifiable, Codable, Equatable {
    case text(TextElement)
    case image(ImageElement)
    case table(TableElement)

    var id: UUID {
        switch self {
        case .text(let element): return element.id
        case .image(let element): return element.id
        case .table(let element): return element.id
        }
    }
}

struct TextElement: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var frame: Rect
    var fontName: String = "SF Pro Text"
    var fontSize: CGFloat = 15
    var color: RGBAColor = .black
    var alignment: TextAlignmentOption = .left
    var confidence: Double = 1
    /// background color detected around the text block
    var backgroundColor: RGBAColor?
    /// true = manually added or edited by the user; false = auto-detected by OCR
    var isUserEdited: Bool = false
    /// normalized quality score [0, 1] used by frontend quality gate
    var qualityScore: Double = 1
    /// true when element should be reviewed before structured export
    var needsReview: Bool = false
}

enum TextAlignmentOption: String, Codable, Equatable {
    case left
    case center
    case right
    case justified
    case natural
}

struct ImageElement: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var assetName: String?
    var frame: Rect
    var fillColor: RGBAColor?
    var confidence: Double = 1
    var renderStyle: ImageRenderStyle = .imageSnippet
    var qualityScore: Double = 1
    var needsReview: Bool = false
}

enum ImageRenderStyle: String, Codable, Equatable, CaseIterable {
    case imageSnippet = "Image Snippet"
    case solidColor = "Solid Color"
}

struct TableElement: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var rows: [[String]]
    var frame: Rect
    var confidence: Double = 1
    var qualityScore: Double = 1
    var needsReview: Bool = false
}

struct Rect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct RGBAColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)

    var swiftUIColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct EditableTextBlock: Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var frame: CGRect
    var confidence: Double
}
