import SwiftUI
import PDFKit
import PencilKit
import UniformTypeIdentifiers

// ============================================================================
// MARK: - LIQUID GLASS EFFECT
// ============================================================================


// ============================================================================
// MARK: - EDITOR TOOL
// ============================================================================

enum PDFEditorTool: String, CaseIterable, Identifiable {
    case pencil     = "Pencil"
    case text       = "Text"
    case selection  = "Select"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pencil:    return "pencil.tip.crop.circle"
        case .text:      return "pencil.and.outline"
        case .selection: return "square.dashed"
        }
    }

    var accent: Color { .white }
}

// ============================================================================
// MARK: - THEME TOGGLE
// ============================================================================

struct ThemeToggleSwitch: View {
    @Binding var isDark: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(isDark ? Color(white: 0.20) : Color(white: 0.86))
                .frame(width: 64, height: 32)
                .overlay(Capsule().strokeBorder(
                    isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                    lineWidth: 1
                ))
            HStack(spacing: 0) {
                ZStack {
                    Circle().fill(isDark ? Color.white : .clear).frame(width: 26, height: 26)
                    Image(systemName: "moon.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isDark ? Color(white: 0.10) : Color(white: 0.55))
                }
                ZStack {
                    Circle().fill(!isDark ? Color.black : .clear).frame(width: 26, height: 26)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(!isDark ? .white : Color(white: 0.55))
                }
            }
        }
        .frame(width: 64, height: 32)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isDark)
        .onTapGesture { isDark.toggle() }
    }
}

// ============================================================================
// MARK: - STABLE PDF HOLDER
// ============================================================================

@MainActor
final class PDFViewHolder: ObservableObject {
    let view: PDFView

    init() {
        let v = PDFView()
        v.autoScales       = true
        v.displayMode      = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor  = .clear
        self.view = v
    }

    func load(_ doc: PDFDocument) { view.document = doc }
    var currentPage: PDFPage?    { view.currentPage }
    var document:    PDFDocument? { view.document }
}

// ============================================================================
// MARK: - PDF VIEW REPRESENTABLE
// ============================================================================

struct PDFViewRepresentable: UIViewRepresentable {
    @ObservedObject var holder: PDFViewHolder
    var activeTool: PDFEditorTool
    var onTap: ((CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let pdf = holder.view

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didTap(_:))
        )
        tap.delegate = context.coordinator
        pdf.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didPan(_:))
        )
        pan.delegate                 = context.coordinator
        pan.minimumNumberOfTouches   = 1
        pan.maximumNumberOfTouches   = 1
        pdf.addGestureRecognizer(pan)

        context.coordinator.holder = holder
        context.coordinator.onTap  = onTap
        context.coordinator.tool   = activeTool
        return pdf
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        context.coordinator.tool  = activeTool
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var holder: PDFViewHolder?
        var tool: PDFEditorTool = .pencil
        var onTap: ((CGPoint) -> Void)?
        var panStart: CGPoint = .zero

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func didTap(_ g: UITapGestureRecognizer) {
            guard tool != .pencil else { return }
            onTap?(g.location(in: g.view))
        }

        @objc func didPan(_ g: UIPanGestureRecognizer) {
            guard tool == .text, let pdf = holder?.view else { return }
            let pt = g.location(in: pdf)
            switch g.state {
            case .began:
                panStart = pt
            case .changed:
                guard let page = pdf.page(for: pt, nearest: true) else { return }
                let pagePt    = pdf.convert(pt, to: page)
                let pageStart = pdf.convert(panStart, to: page)
                let dx = pagePt.x - pageStart.x
                let dy = pagePt.y - pageStart.y
                if let ann = page.annotations.first(where: {
                    $0.type == PDFAnnotationSubtype.freeText.rawValue &&
                    $0.bounds.insetBy(dx: -12, dy: -12).contains(pageStart)
                }) {
                    ann.bounds = ann.bounds.offsetBy(dx: dx, dy: dy)
                    panStart = pt
                }
            default: break
            }
        }
    }
}

// ============================================================================
// MARK: - PENCIL CANVAS
// ============================================================================

struct PencilCanvasView: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    var tool: PKTool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.backgroundColor = .clear
        canvas.isOpaque        = false
        return canvas
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = tool
    }
}

// ============================================================================
// MARK: - FONT DATA
// ============================================================================


// ============================================================================
// MARK: - CONTEXT CONTROL STRIP  (Zone 3)
// ============================================================================

struct ContextControlStrip: View {
    let activeTool:        PDFEditorTool
    @Binding var fontName: String
    @Binding var fontSize: CGFloat
    @Binding var penColor: Color
    @Binding var strokeW:  CGFloat
    let isDark:            Bool

    private var fg: Color { isDark ? .white : Color(white: 0.12) }

    var body: some View {
        Group {
            switch activeTool {
            case .text:
                textControls
            case .pencil:
                drawControls
            case .selection:
                shapeControls
            default:
                EmptyView()
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // ── Text controls ──────────────────────────────────────────────────────
    private var textControls: some View {
        HStack(spacing: 0) {
            // Font scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(AppFont.all) { font in
                        let sel = fontName == font.id
                        Button {
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.65)) {
                                fontName = font.id
                            }
                        } label: {
                            Text(font.preview)
                                .font(font.swiftUIFont)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(sel ? Color.blue.opacity(0.2) : fg.opacity(0.07))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(sel ? Color.blue.opacity(0.55) : Color.clear, lineWidth: 1.5)
                                )
                                .foregroundStyle(sel ? Color.blue : fg.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(sel ? 1.06 : 1.0)
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider().frame(height: 24).padding(.horizontal, 6)

            // Size stepper
            HStack(spacing: 0) {
                Button { fontSize = max(8, fontSize - 1) } label: {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                Text("\(Int(fontSize))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 28)
                    .foregroundStyle(fg)
                Button { fontSize = min(72, fontSize + 1) } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                }
            }
            .foregroundStyle(fg.opacity(0.8))
            .padding(.trailing, 8)
        }
        .frame(height: 44)
        .liquidGlassEffect(cornerRadius: 16, isDark: isDark)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // ── Draw controls ──────────────────────────────────────────────────────
    private static let penColors: [Color] = [
        .black, .white,
        Color(hue: 0.02, saturation: 0.85, brightness: 0.9),
        Color(hue: 0.58, saturation: 0.85, brightness: 1.0),
        Color(hue: 0.33, saturation: 0.75, brightness: 0.75),
        Color(hue: 0.12, saturation: 0.90, brightness: 1.0)
    ]
    private static let strokeWidths: [CGFloat] = [1.5, 3.5, 7.0]

    private var drawControls: some View {
        HStack(spacing: 12) {
            // Color swatches
            HStack(spacing: 6) {
                ForEach(Self.penColors, id: \.self) { c in
                    let sel = UIColor(penColor).cgColor == UIColor(c).cgColor
                    Button { penColor = c } label: {
                        Circle()
                            .fill(c)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(
                                sel ? Color.blue : fg.opacity(0.25), lineWidth: sel ? 2 : 0.5
                            ))
                            .scaleEffect(sel ? 1.12 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.16), value: sel)
                }
            }
            Divider().frame(height: 24)
            // Stroke widths
            HStack(spacing: 8) {
                ForEach(Self.strokeWidths, id: \.self) { w in
                    let sel = abs(strokeW - w) < 0.5
                    Button { strokeW = w } label: {
                        Circle()
                            .fill(fg)
                            .frame(width: w * 2.2, height: w * 2.2)
                            .frame(width: 32, height: 32)
                            .overlay(
                                sel ? Circle().strokeBorder(Color.blue.opacity(0.5), lineWidth: 1.5)
                                    : nil
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.16), value: sel)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .liquidGlassEffect(cornerRadius: 16, isDark: isDark)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // ── Shape controls ──────────────────────────────────────────────────────
    private var shapeControls: some View {
        HStack(spacing: 8) {
            ForEach(["rectangle.dashed", "circle.dashed", "square.fill"], id: \.self) { icon in
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(fg.opacity(0.7))
            }
            Divider().frame(height: 24)
            ForEach(ContextControlStrip.penColors.prefix(4), id: \.self) { c in
                Button { } label: {
                    Circle().fill(c).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(fg.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .liquidGlassEffect(cornerRadius: 16, isDark: isDark)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}


// ============================================================================
// MARK: - SAFARI-STYLE EDITOR DOCK  (Zone 4)
// ============================================================================

struct BottomEditorDock: View {
    @Binding var activeTool:   PDFEditorTool
    @Binding var isDark:       Bool
    var onUndo:   () -> Void
    var onShare:  () -> Void
    var onClear:  () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Left Pill: Creation Tools
            HStack(spacing: 20) {
                ToolIconButton(icon: "pencil.tip.crop.circle", isActive: activeTool == .pencil) {
                    activeTool = .pencil
                }
                
                ToolIconButton(icon: "pencil.and.outline", isActive: activeTool == .text) {
                    activeTool = .text
                }
                
                ToolIconButton(icon: "square.dashed", isActive: activeTool == .selection) {
                    activeTool = .selection
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .liquidGlassEffect(cornerRadius: 32, isDark: isDark)
            
            // Right Pill: Actions
            HStack(spacing: 20) {
                ToolIconButton(icon: "info.circle", isActive: false) { }
                
                ToolIconButton(icon: "square.and.arrow.up", isActive: false) {
                    onShare()
                }
                
                ToolIconButton(icon: "magnifyingglass", isActive: false) { }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .liquidGlassEffect(cornerRadius: 32, isDark: isDark)
        }
        .padding(.bottom, 24)
    }
}

struct ToolIconButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .symbolVariant(isActive ? .fill : .none)
                .scaleEffect(isActive ? 1.2 : 1.0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActive)
    }
}

// ============================================================================
// MARK: - TEXT EDIT SHEET  (Zone 5 — premium redesign)
// ============================================================================

struct TextBlockEditSheet: View {
    @Binding var text: String
    @Binding var fontName: String
    @Binding var fontSize: CGFloat
    var isDark: Bool
    var onCommit:  (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill((isDark ? Color.white : Color.black).opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Text")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Customize your text block")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                // Size controls
                HStack(spacing: 0) {
                    Button { fontSize = max(8, fontSize - 1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                    }
                    Text("\(Int(fontSize))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(width: 36)
                    Button { fontSize = min(72, fontSize + 1) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                }
                .foregroundStyle(isDark ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background((isDark ? Color.white : Color.black).opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, 24)

            // Font picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppFont.all) { font in
                        let sel = fontName == font.id
                        Button {
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.65)) {
                                fontName = font.id
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(font.preview)
                                    .font(font.swiftUIFont)
                                    .frame(width: 44, height: 32)
                                Text(font.id)
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(sel ? .white : (isDark ? .white.opacity(0.6) : .black.opacity(0.6)))
                            .frame(width: 64, height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(sel ? Color.blue : (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(sel ? .white.opacity(0.2) : .clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(sel ? 1.05 : 1.0)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 20)

            // Text editor
            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .frame(minHeight: 140, maxHeight: 200)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(isDark ? Color.black.opacity(0.2) : Color.white.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder((isDark ? Color.white : Color.black).opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                Text("\(text.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 36)
                    .padding(.bottom, 12)
            }

            // Actions
            HStack(spacing: 16) {
                Button("Dismiss") { onDismiss() }
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), in: Capsule())
                    .foregroundStyle(isDark ? .white : .black)

                Button {
                    onCommit(text)
                    onDismiss()
                } label: {
                    Text("Save Changes")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.blue, in: Capsule())
                        .foregroundStyle(.white)
                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .liquidGlassEffect(cornerRadius: 32, isDark: isDark)
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .presentationBackground(.clear) // Let our glass effect show
    }
}

// ============================================================================
// MARK: - PDF KIT EDITOR  (main view)
// ============================================================================

struct PDFKitEditorView: View {

    @Environment(\.dismiss)       private var dismiss
    @EnvironmentObject            private var store: DocumentStore
    @AppStorage("preferredAppTheme") private var preferredAppTheme = AppThemeMode.dark.rawValue

    private var isDark: Bool {
        preferredAppTheme == AppThemeMode.dark.rawValue
    }

    private var themeBinding: Binding<Bool> {
        Binding(
            get: { isDark },
            set: { preferredAppTheme = $0 ? AppThemeMode.dark.rawValue : AppThemeMode.light.rawValue }
        )
    }

    @StateObject private var pdfHolder = PDFViewHolder()

    // Tool state
    @State private var activeTool      = PDFEditorTool.pencil
    @State private var isDocumentReady = false

    // Draw
    @State private var canvas    = PKCanvasView()
    @State private var penColor  = Color.black
    @State private var strokeW   = CGFloat(3.5)

    // Text edit
    @State private var editingAnnotation: PDFAnnotation?
    @State private var editingText        = ""
    @State private var showTextEdit       = false
    @State private var selectedFontName   = "System"
    @State private var selectedFontSize   = CGFloat(15)

    // Shape / bg
    @State private var shapeColor     = Color.blue
    @State private var bgColor        = Color.white
    @State private var showBgPicker   = false
    @State private var showShapeSheet = false
    @State private var pendingPage:  PDFPage? = nil
    @State private var pendingPoint: CGPoint  = .zero

    // Share
    @State private var shareURL:      URL?
    @State private var showShareSheet = false

    // Undo
    @State private var undoAnnotations: [PDFAnnotation] = []

    // Flash  (Zone 6 — bottom toast)
    @State private var flashMessage:  String?
    @State private var flashIsError = false



    private var penTool: PKTool {
        PKInkingTool(.pen, color: UIColor(penColor), width: strokeW)
    }

    // ── Body ──────────────────────────────────────────────────────────────────

    var body: some View {
        ZStack {
            // ── Zone 2: Gradient canvas background ───────────────────────
            canvasBackground.ignoresSafeArea()

            // ── PDF view (full-bleed) ─────────────────────────────────────
            PDFViewRepresentable(
                holder:     pdfHolder,
                activeTool: activeTool,
                onTap:      handleTap(at:)
            )

            // ── PencilKit overlay ─────────────────────────────────────────
            PencilCanvasView(canvas: $canvas, tool: penTool)
                .allowsHitTesting(activeTool == .pencil)
                .opacity(activeTool == .pencil ? 1 : 0)

            // ── Zone 2: Active tool chip (top-right of canvas) ────────────
            if true { // Show chip for all tools now
                VStack {
                    HStack {
                        Spacer()
                        activeToolChip
                            .padding(.trailing, 16)
                            .padding(.top, 6)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // ── Zone 6: Bottom toast ──────────────────────────────────────
            if let msg = flashMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: flashIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(flashIsError ? .red : .green)
                        Text(msg)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(isDark ? Color.white : Color(white: 0.10))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder((isDark ? Color.white : Color.black).opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 102)  // sits just above the dock
                }
                .allowsHitTesting(false)
                .animation(.spring(response: 0.30, dampingFraction: 0.74), value: flashMessage)
            }
        }
        // ── Zone 3 + 4: Context strip + dock ─────────────────────────────
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // Context strip — only when relevant tool is active
                if activeTool == .text || activeTool == .pencil || activeTool == .selection {
                    ContextControlStrip(
                        activeTool: activeTool,
                        fontName:   $selectedFontName,
                        fontSize:   $selectedFontSize,
                        penColor:   $penColor,
                        strokeW:    $strokeW,
                        isDark:     isDark
                    )
                    .animation(.spring(response: 0.24, dampingFraction: 0.74), value: activeTool)
                }

                BottomEditorDock(
                    activeTool: $activeTool,
                    isDark:     themeBinding,
                    onUndo:     undoLastAction,
                    onShare:    exportAndShare,
                    onClear:    clearAnnotations
                )
            }
        }
        // ── Zone 1: Floating glass nav bar ────────────────────────────────
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { navToolbar }
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { customTopDock }
        .sheet(isPresented: $showTextEdit) { textEditSheet }
        .sheet(isPresented: $showBgPicker) { bgPickerSheet }
        .sheet(isPresented: $showShareSheet) { shareSheetView }
        .confirmationDialog("Insert Shape", isPresented: $showShapeSheet, titleVisibility: .visible) {
            shapeDialogButtons
        }
        .onAppear { buildDocument() }
        .onChange(of: bgColor) { _, c in applyBackground(c) }
        .animation(.spring(response: 0.24, dampingFraction: 0.74), value: activeTool)
        .animation(.easeInOut(duration: 0.16), value: isDark)
    }

    // ── Zone 1: Navigation Overlay ───────────────────────────────────────────
    private var customTopDock: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                    Text("Documents")
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .modifier(LiquidGlassEffect(cornerRadius: 20, isDark: isDark))
            }
            .foregroundStyle(.white)
            
            Spacer()
            
            ThemeToggleSwitch(isDark: themeBinding)
                .modifier(LiquidGlassEffect(cornerRadius: 16, isDark: isDark))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // ── Zone 2: Sheets ───────────────────────────────────────────────────────
    private var textEditSheet: some View {
        TextBlockEditSheet(
            text:      $editingText,
            fontName:  $selectedFontName,
            fontSize:  $selectedFontSize,
            isDark:    isDark,
            onCommit:  commitTextEdit,
            onDismiss: { showTextEdit = false }
        )
    }

    private var bgPickerSheet: some View {
        NavigationStack {
            ColorPicker("Page Background", selection: $bgColor, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.4)
                .padding(40)
                .navigationTitle("Background Color")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showBgPicker = false }
                    }
                }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var shareSheetView: some View {
        Group { if let url = shareURL { ShareSheet(url: url) } }
    }

    @ViewBuilder
    private var shapeDialogButtons: some View {
        Button("Rectangle")  { insertShape(.rectangle) }
        Button("Circle")     { insertShape(.circle) }
        Button("Filled Box") { insertShape(.filled) }
        Button("Cancel", role: .cancel) {}
    }

    // ── Zone 1: Nav toolbar ───────────────────────────────────────────────────
    @ToolbarContentBuilder
    private var navToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { dismiss() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    (isDark ? Color.white : Color.black).opacity(0.12), lineWidth: 1
                ))
            }
            .foregroundStyle(isDark ? .white : .primary)
        }

        ToolbarItem(placement: .principal) {
            Text(store.document.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            ThemeToggleSwitch(isDark: themeBinding)
        }
    }

    // ── Zone 2: Active tool chip ──────────────────────────────────────────────
    private var activeToolChip: some View {
        HStack(spacing: 6) {
            Image(systemName: activeTool.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(activeTool.accent)
            Text(activeTool.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDark ? .white : Color(white: 0.15))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(activeTool.accent.opacity(0.45), lineWidth: 1))
        .shadow(color: activeTool.accent.opacity(0.35), radius: 8, x: 0, y: 2)
    }

    // ── Zone 2: Canvas wallpaper ──────────────────────────────────────────────
    private var canvasBackground: some View {
        ZStack {
            if isDark {
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.05, green: 0.05, blue: 0.14), location: 0),
                        .init(color: Color(red: 0.08, green: 0.06, blue: 0.20), location: 0.4),
                        .init(color: Color(red: 0.04, green: 0.04, blue: 0.10), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint:   .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(red: 0.25, green: 0.20, blue: 0.55).opacity(0.25), Color.clear],
                    center: .center, startRadius: 0, endRadius: 350
                )
                .blendMode(.screen)
            } else {
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.90, green: 0.92, blue: 0.98), location: 0),
                        .init(color: Color(red: 0.94, green: 0.94, blue: 0.96), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint:   .bottomTrailing
                )
            }
        }
    }

    // ============================================================
    // MARK: - Build document
    // ============================================================

    private func buildDocument() {
        guard !isDocumentReady else { return }
        isDocumentReady = true

        // ── Use the real Export Service to build the "Raw PDF" for the editor ──
        if let pdfData = try? store.exportService.export(document: store.document),
           let pdfDoc  = PDFDocument(data: pdfData) {
            pdfHolder.load(pdfDoc)
        } else {
            let base = PDFDocument()
            if let p = PDFPage() as PDFPage? { base.insert(p, at: 0) }
            pdfHolder.load(base)
        }

        guard let page = pdfHolder.document?.page(at: 0) else { return }
        let pageH = page.bounds(for: .mediaBox).height

        // ── Invisible Annotations for tap interaction ──
        for element in store.textElements {
            let f = element.frame.cgRect
            let pdfRect = CGRect(x: f.minX, y: pageH - f.maxY, width: f.width, height: f.height)
            let ann = PDFAnnotation(bounds: pdfRect, forType: .freeText, withProperties: nil)
            ann.contents  = element.text
            ann.color     = .clear
            ann.fontColor = .clear
            ann.border    = PDFBorder()
            ann.userName  = element.id.uuidString
            page.addAnnotation(ann)
        }
    }

    // ============================================================
    // MARK: - Tap
    // ============================================================

    private func handleTap(at point: CGPoint) {
        let pdf = pdfHolder.view
        guard let page  = pdf.page(for: point, nearest: true) else { return }
        let pagePt = pdf.convert(point, to: page)

        switch activeTool {
        case .text:       openTextEditor(at: pagePt, on: page)
        case .selection:  pendingPage = page; pendingPoint = pagePt; showShapeSheet = true
        case .pencil:     showBgPicker = true
        default: break
        }
    }

    // ============================================================
    // MARK: - Text edit
    // ============================================================

    private func openTextEditor(at pt: CGPoint, on page: PDFPage) {
        if let ann = page.annotations.first(where: {
            $0.type == PDFAnnotationSubtype.freeText.rawValue &&
            $0.bounds.insetBy(dx: -10, dy: -10).contains(pt)
        }) {
            editingAnnotation = ann
            editingText       = ann.contents ?? ""
        } else {
            let rect = CGRect(x: pt.x - 80, y: pt.y - 15, width: 200, height: 30)
            let ann  = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
            ann.contents  = "New text"
            ann.font      = AppFont.resolveUIFont(id: selectedFontName, size: selectedFontSize)
            ann.color     = .clear
            ann.fontColor = isDark ? .white : .black
            ann.border    = PDFBorder()
            page.addAnnotation(ann)
            undoAnnotations.append(ann)
            editingAnnotation = ann
            editingText       = "New text"
        }
        showTextEdit = true
    }

    private func commitTextEdit(_ newText: String) {
        editingAnnotation?.contents = newText
        if let idStr = editingAnnotation?.userName, let uuid = UUID(uuidString: idStr),
           let el = store.textElements.first(where: { $0.id == uuid }) {
            var updated = el
            updated.text         = newText
            updated.fontName     = selectedFontName
            updated.fontSize     = selectedFontSize
            updated.isUserEdited = true
            store.updateTextElement(updated)
            
            // ── REBUILD RAW PDF ──
            // Since we use the real PDF rendering for the "raw" feel, 
            // we must refresh the background layer on edit.
            isDocumentReady = false
            buildDocument()
        }
        editingAnnotation = nil
    }

    // ============================================================
    // MARK: - Shape
    // ============================================================

    enum ShapeKind { case rectangle, circle, filled }

    private func insertShape(_ kind: ShapeKind) {
        guard let page = pendingPage ?? pdfHolder.currentPage else { return }
        let pt   = pendingPoint == .zero ? CGPoint(x: 100, y: 200) : pendingPoint
        let rect = CGRect(x: pt.x - 60, y: pt.y - 40, width: 120, height: 80)

        let ann: PDFAnnotation
        switch kind {
        case .rectangle:
            ann = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
            ann.color = UIColor(shapeColor); ann.interiorColor = .clear
        case .circle:
            ann = PDFAnnotation(bounds: rect, forType: .circle, withProperties: nil)
            ann.color = UIColor(shapeColor); ann.interiorColor = .clear
        case .filled:
            ann = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
            ann.color = UIColor(shapeColor)
            ann.interiorColor = UIColor(shapeColor).withAlphaComponent(0.35)
        }
        let b = PDFBorder(); b.lineWidth = 2; ann.border = b
        page.addAnnotation(ann)
        undoAnnotations.append(ann)
        pendingPage = nil; pendingPoint = .zero
        flash("Shape inserted ✓")
    }

    // ============================================================
    // MARK: - Background
    // ============================================================

    private func applyBackground(_ color: Color) {
        guard let page = pdfHolder.currentPage else { return }
        let bounds = page.bounds(for: .mediaBox)
        page.annotations.filter { $0.userName == "__bg__" }.forEach { page.removeAnnotation($0) }

        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        guard !(r > 0.96 && g > 0.96 && b > 0.96) else { return }

        let ann = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
        ann.color = ui; ann.interiorColor = ui
        let border = PDFBorder(); border.lineWidth = 0; ann.border = border
        ann.userName = "__bg__"
        page.addAnnotation(ann)
    }

    // ============================================================
    // MARK: - Undo / Clear / Export
    // ============================================================

    private func undoLastAction() {
        if activeTool == .pencil && !canvas.drawing.strokes.isEmpty {
            var d = canvas.drawing; d.strokes.removeLast(); canvas.drawing = d
        } else if let last = undoAnnotations.popLast() {
            last.page?.removeAnnotation(last)
            flash("Undone ↩")
        }
    }

    private func clearAnnotations() {
        guard let page = pdfHolder.currentPage else { return }
        let toRemove = page.annotations.filter { $0.userName != "__bg__" }
        toRemove.forEach { page.removeAnnotation($0) }
        undoAnnotations.removeAll()
        canvas.drawing = PKDrawing()
        flash("Annotations cleared")
    }

    private func exportAndShare() {
        guard let pdfDoc = pdfHolder.document else { return }
        guard let pdfData = pdfDoc.dataRepresentation() else { return }
        let title = store.document.title.isEmpty ? "EditablePDF" : store.document.title
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(title)
            .appendingPathExtension("pdf")
        do {
            try pdfData.write(to: tmp)
            shareURL      = tmp
            showShareSheet = true
        } catch {
            flash("Export failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func flash(_ msg: String, isError: Bool = false) {
        flashIsError = isError
        withAnimation { flashMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { flashMessage = nil }
        }
    }
}

// ============================================================================
// MARK: - SHARE SHEET
// ============================================================================

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
