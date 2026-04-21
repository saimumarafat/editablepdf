import SwiftUI
import PhotosUI
import UIKit

// ============================================================================
// MARK: - FLOATING GLASS DOCK (reusable capsule component)
// ============================================================================
// Matches the Safari-style floating frosted-glass pill toolbar.
// Usage: wrap any HStack of icons inside FloatingGlassDock { … }

struct FloatingGlassDock<Content: View>: View {
    let isDark: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            content
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        // ── Frosted glass material ────────────────────────────────────────────
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        // ── Specular lens overlay ─────────────────────────────────────────────
        .background(
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color.white.opacity(isDark ? 0.10 : 0.50),
                        Color.clear,
                        Color.black.opacity(isDark ? 0.06 : 0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        // ── Rim stroke ────────────────────────────────────────────────────────
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.55 : 0.90),
                            Color.white.opacity(isDark ? 0.08 : 0.30),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )
        )
        // ── Floating shadow ───────────────────────────────────────────────────
        .shadow(color: .black.opacity(isDark ? 0.55 : 0.22), radius: 30, x: 0, y: 14)
        .shadow(color: .black.opacity(isDark ? 0.22 : 0.08), radius:  6, x: 0, y:  2)
    }
}

// ── Dock item: circular icon button with active glow ─────────────────────────

struct DockIconButton: View {
    let icon:     String
    var accent:   Color  = .primary
    var isActive: Bool   = false
    var size:     CGFloat = 48
    var iconSize: CGFloat = 22
    var isDark:   Bool   = true
    let action:   () -> Void

    private var fg: Color { isDark ? .white : Color(white: 0.10) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? accent.opacity(0.20) : Color.clear)
                    .frame(width: size, height: size)
                Image(systemName: icon)
                    .font(.system(size: iconSize,
                                  weight: isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? accent : fg.opacity(0.50))
                    .scaleEffect(isActive ? 1.08 : 1.0)
                    .animation(.spring(response: 0.18, dampingFraction: 0.6),
                               value: isActive)
            }
        }
        .buttonStyle(.plain)
    }
}

// ── Thin vertical separator ───────────────────────────────────────────────────

struct DockDivider: View {
    var isDark: Bool = true
    var body: some View {
        Rectangle()
            .fill((isDark ? Color.white : Color.black).opacity(0.14))
            .frame(width: 1, height: 30)
            .padding(.horizontal, 6)
    }
}

// ============================================================================
// MARK: - HOME VIEW
// ============================================================================

struct HomeView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var selectedItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var exportDocument: PDFExportDocument?
    @State private var isPresentingExporter = false
    @AppStorage("preferredAppTheme") private var preferredAppTheme = AppThemeMode.dark.rawValue

    private var isDark: Bool { (AppThemeMode(rawValue: preferredAppTheme) ?? .dark) == .dark }
    private var fg: Color   { isDark ? .white : Color(white: 0.08) }

    // Entry animation
    @State private var logoScale:      CGFloat = 0.6
    @State private var logoOpacity:    Double  = 0
    @State private var contentOffset:  CGFloat = 30
    @State private var contentOpacity: Double  = 0

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if store.document.pages.isEmpty && !store.isProcessing {
                onboardingScreen
            } else {
                documentScreen
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { navToolbar }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView { image in
                Task { await store.ingest(image: image, source: .camera) }
            }
        }
        .task(id: selectedItem) {
            guard let item = selectedItem else { return }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await store.ingest(image: image, source: .upload)
            }
            self.selectedItem = nil
        }
        .fileExporter(
            isPresented: $isPresentingExporter,
            document: exportDocument ?? PDFExportDocument(data: Data()),
            contentType: .pdf,
            defaultFilename: sanitizedFilename(store.document.title)
        ) { result in
            if case .success(let url) = result {
                store.exportedPDFURL = url
                store.statusMessage  = "PDF saved to Files."
                UIApplication.shared.open(url)
            } else if case .failure(let err) = result {
                store.statusMessage = "Save failed: \(err.localizedDescription)"
            }
        }
    }

    // ── Navbar ────────────────────────────────────────────────────────────────
    @ToolbarContentBuilder
    private var navToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if !store.document.pages.isEmpty || store.isProcessing {
                Button { store.resetToFreshFrontPage() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Back")
                            .font(.system(size: 15, weight: .medium))
                    }
                }
            }
        }

        ToolbarItem(placement: .principal) {
            if !store.document.pages.isEmpty || store.isProcessing {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Editable PDF")
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            ThemeToggleSwitch(isDark: Binding(
                get: { isDark },
                set: { v in
                    preferredAppTheme = v
                        ? AppThemeMode.dark.rawValue
                        : AppThemeMode.light.rawValue
                }
            ))
        }
    }

    // ============================================================
    // MARK: - Onboarding (page 1)
    // ============================================================

    private var onboardingScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            nestedLogoGraphic
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.70, dampingFraction: 0.62).delay(0.05)) {
                        logoScale   = 1.0
                        logoOpacity = 1.0
                    }
                }

            Spacer().frame(height: 48)

            // Copy
            VStack(alignment: .leading, spacing: 14) {
                Text("Turn any document\ninto an editable PDF.")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Snap a photo or upload an image. The app recognises text, detects coloured regions, and assembles a crisp, editable PDF you can share instantly.")
                    .font(.system(size: 15))
                    .foregroundStyle(fg.opacity(0.52))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .offset(y: contentOffset)
            .opacity(contentOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55).delay(0.22)) {
                    contentOffset = 0; contentOpacity = 1
                }
            }

            Spacer()

            // ── Floating glass dock (onboarding) ──────────────────────────────
            onboardingDock
                .padding(.bottom, 40)
        }
    }

    // Onboarding dock: Upload | Camera
    @ViewBuilder
    private var onboardingDock: some View {
        FloatingGlassDock(isDark: isDark) {
            // Upload photo
            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Upload")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(fg.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            DockDivider(isDark: isDark)

            DockIconButton(
                icon:     "camera.fill",
                accent:   .blue,
                isActive: isShowingCamera,
                isDark:   isDark
            ) { isShowingCamera = true }
        }
        .padding(.horizontal, 32)
    }

    // ============================================================
    // MARK: - Document Screen (page 2)
    // ============================================================

    private var documentScreen: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Preview card
                    if let preview = store.previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(fg.opacity(0.10), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    Spacer().frame(height: 20)

                    if store.isProcessing {
                        HStack(spacing: 12) {
                            ProgressView().tint(fg.opacity(0.5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Analysing document")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(fg)
                                Text("Detecting text, colors and boxes…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(fg.opacity(0.5))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }

                    if let msg = store.statusMessage {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundStyle(fg.opacity(0.45))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

                    // Space so content doesn't hide behind the dock
                    Spacer().frame(height: 110)
                }
            }

            // ── Floating glass dock (document screen) ─────────────────────────
            documentDock
                .padding(.bottom, 28)
        }
    }

    // Document dock: Edit | Save | New Scan
    @ViewBuilder
    private var documentDock: some View {
        FloatingGlassDock(isDark: isDark) {
            DockIconButton(
                icon:     "slider.horizontal.3",
                accent:   .blue,
                size:     52,
                iconSize: 22,
                isDark:   isDark
            ) {
                if store.routePath.last != .previewEditor {
                    store.routePath.append(.previewEditor)
                }
            }

            DockDivider(isDark: isDark)

            DockIconButton(
                icon:     "square.and.arrow.down",
                accent:   .green,
                size:     52,
                iconSize: 22,
                isDark:   isDark
            ) {
                Task {
                    do {
                        exportDocument = try store.makeExportDocument()
                        isPresentingExporter = true
                    } catch {
                        store.statusMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
            }

            DockDivider(isDark: isDark)

            // New scan — PhotosPicker wrapped in a dock item
            PhotosPicker(selection: $selectedItem, matching: .images) {
                ZStack {
                    Circle().fill(Color.clear).frame(width: 52, height: 52)
                    Image(systemName: "plus.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle((isDark ? Color.white : Color(white: 0.08)).opacity(0.50))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
    }

    // ============================================================
    // MARK: - Logo
    // ============================================================

    private var nestedLogoGraphic: some View {
        ZStack {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 148, weight: .ultraLight))
                .foregroundStyle(fg.opacity(0.04))
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 108, weight: .thin))
                .foregroundStyle(fg.opacity(0.10))
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(fg.opacity(0.85))
        }
    }

    private func sanitizedFilename(_ value: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let clean = value.components(separatedBy: bad)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "EditablePDF" : clean
    }
}

// ============================================================================
// MARK: - PILL BUTTON LABEL  (kept for backward compat, unused in new UI)
// ============================================================================

struct PillButtonLabel: View {
    let label: String
    let icon:  String
    var isSecondary: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
            Text(label).font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(isSecondary ? Color(white: 0.08) : .white)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(
            Capsule()
                .fill(isSecondary ? Color(white: 0.93) : Color(white: 0.06))
                .shadow(color: .black.opacity(isSecondary ? 0.04 : 0.20),
                        radius: isSecondary ? 6 : 16, x: 0,
                        y: isSecondary ? 2 : 7)
        )
    }
}
