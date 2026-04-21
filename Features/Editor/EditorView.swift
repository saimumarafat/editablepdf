import SwiftUI
import Foundation

struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DocumentStore
    @AppStorage("preferredAppTheme") private var preferredAppTheme = AppThemeMode.dark.rawValue
    @State private var exportDocument: PDFExportDocument?
    @State private var isPresentingExporter = false

    private var isDarkTheme: Bool {
        (AppThemeMode(rawValue: preferredAppTheme) ?? .dark) == .dark
    }

    private var ambientBackground: some View {
        ZStack {
            Color(isDarkTheme ? .black : .systemBackground).ignoresSafeArea()
            GeometryReader { proxy in
                RadialGradient(colors: [DesignSystem.Colors.accent.opacity(isDarkTheme ? 0.18 : 0.12), .clear], center: .topLeading, startRadius: 0, endRadius: proxy.size.width * 1.2)
                    .ignoresSafeArea()
                RadialGradient(colors: [DesignSystem.Colors.accent.opacity(isDarkTheme ? 0.12 : 0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: proxy.size.width)
                    .ignoresSafeArea()
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ambientBackground

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    header
                    documentPreview
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected text regions: \(store.textElements.count)")
                            .font(DesignSystem.Typography.footnote)
                            .foregroundStyle(DesignSystem.Colors.subtleText)

                        if let message = store.statusMessage {
                            Text(message)
                                .font(DesignSystem.Typography.footnote)
                                .foregroundStyle(DesignSystem.Colors.subtleText)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
                .padding(.bottom, 120) // Provide room for floating row
            }
            
            floatingActionRow
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                    }
                    .foregroundStyle(isDarkTheme ? .white : .black)
                }
            }
        }
        .fileExporter(
            isPresented: $isPresentingExporter,
            document: exportDocument ?? PDFExportDocument(data: Data()),
            contentType: .pdf,
            defaultFilename: sanitizedFilename(store.document.title)
        ) { result in
            switch result {
            case .success(let url):
                store.exportedPDFURL = url
                store.statusMessage = "PDF saved to Files."
            case .failure(let error):
                store.statusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(store.document.title)
                .font(DesignSystem.Typography.title)
            Text("Open the preview editor to tap and edit specific text regions, then export a plain raw PDF.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.subtleText)
        }
    }

    private var documentPreview: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Document")
                .font(DesignSystem.Typography.headline)

            Group {
                if let previewImage = store.previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.accent)
                        Text(store.document.pages.isEmpty ? "No pages yet" : "Pages ready for edit")
                            .font(DesignSystem.Typography.headline)
                        Text("Text blocks, image regions, and structured regions will appear here.")
                            .font(DesignSystem.Typography.footnote)
                            .foregroundStyle(DesignSystem.Colors.subtleText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .frame(height: 260)
            .padding(DesignSystem.Spacing.sm)
            .liquidGlassEffect(cornerRadius: DesignSystem.Radius.card, isDark: isDarkTheme)
        }
    }

    private var floatingActionRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            NavigationLink(value: AppRoute.previewEditor) {
                Label("Edit", systemImage: "text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(isDarkTheme: isDarkTheme))

            Button {
                Task {
                    do {
                        exportDocument = try store.makeExportDocument()
                        isPresentingExporter = true
                    } catch {
                        store.statusMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
            } label: {
                Label("Save", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(isDarkTheme: isDarkTheme))
            .disabled(store.document.pages.isEmpty)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            Rectangle()
                .fill(isDarkTheme ? Color.black.opacity(0.4) : Color.white.opacity(0.6))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
        )
    }

    private func sanitizedFilename(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = value.components(separatedBy: invalidCharacters)
        let joined = components.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "EditablePDF" : joined
    }
}

struct PreviewEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DocumentStore
    @State private var selectedElement: PreviewSelection?
    @AppStorage("preferredAppTheme") private var preferredAppTheme = AppThemeMode.dark.rawValue

    private var isDarkTheme: Bool {
        (AppThemeMode(rawValue: preferredAppTheme) ?? .dark) == .dark
    }

    private var ambientBackground: some View {
        ZStack {
            Color(isDarkTheme ? .black : .systemBackground).ignoresSafeArea()
            GeometryReader { proxy in
                RadialGradient(colors: [DesignSystem.Colors.accent.opacity(isDarkTheme ? 0.18 : 0.12), .clear], center: .topLeading, startRadius: 0, endRadius: proxy.size.width * 1.2)
                    .ignoresSafeArea()
                RadialGradient(colors: [DesignSystem.Colors.accent.opacity(isDarkTheme ? 0.12 : 0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: proxy.size.width)
                    .ignoresSafeArea()
            }
        }
    }

    var body: some View {
        ZStack {
            ambientBackground

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    header

                if let previewImage = store.previewImage {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                        Text("Tap text or a detected box to inspect")
                            .font(DesignSystem.Typography.headline)

                        GeometryReader { proxy in
                            let bounds = proxy.frame(in: .local)
                            let fitted = fittedImageRect(imageSize: previewImage.size, in: bounds)

                            ZStack(alignment: .topLeading) {
                                Image(uiImage: previewImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                if let page = store.document.pages.first {
                                    ForEach(store.textElements) { text in
                                        let rect = overlayRect(for: text.frame.cgRect, pageSize: page.size, imageRect: fitted)
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(Color.blue.opacity(selectedElement?.id == text.id ? 0.25 : 0.12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .stroke(Color.blue.opacity(selectedElement?.id == text.id ? 0.9 : 0.5), lineWidth: selectedElement?.id == text.id ? 2 : 1)
                                            )
                                            .frame(width: rect.width, height: rect.height)
                                            .position(x: rect.midX, y: rect.midY)
                                            .onTapGesture {
                                                selectedElement = .text(text.id)
                                            }
                                    }

                                    ForEach(store.imageElements) { image in
                                        let rect = overlayRect(for: image.frame.cgRect, pageSize: page.size, imageRect: fitted)
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color(uiColor: image.fillColor?.swiftUIColor ?? .systemOrange).opacity(selectedElement?.id == image.id ? 0.30 : 0.18))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(Color.orange.opacity(selectedElement?.id == image.id ? 0.95 : 0.6), lineWidth: selectedElement?.id == image.id ? 2 : 1)
                                            )
                                            .frame(width: rect.width, height: rect.height)
                                            .position(x: rect.midX, y: rect.midY)
                                            .onTapGesture {
                                                selectedElement = .image(image.id)
                                            }
                                    }
                                }
                            }
                        }
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous))
                    }
                } else {
                    ContentUnavailableView("No preview available", systemImage: "photo.badge.checkmark")
                }

                if let selection = selectedElement {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        if case .text(let id) = selection,
                           let selectedText = store.textElements.first(where: { $0.id == id }),
                           let textBinding = store.textElementBinding(id: id) {
                            Text("Edit Text")
                                .font(DesignSystem.Typography.headline)

                            Text("Detected confidence: \(Int(selectedText.confidence * 100))%")
                                .font(DesignSystem.Typography.footnote)
                                .foregroundStyle(DesignSystem.Colors.subtleText)

                            TextField("Updated text", text: Binding(
                                get: { textBinding.wrappedValue.text },
                                set: { newValue in
                                    var updated = textBinding.wrappedValue
                                    updated.text = newValue
                                    store.updateTextElement(updated)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        } else if case .image(let id) = selection,
                                  let imageBinding = store.imageElementBinding(id: id) {
                            Text("Detected Box")
                                .font(DesignSystem.Typography.headline)

                            Picker("Render Type", selection: imageBinding.renderStyle) {
                                ForEach(ImageRenderStyle.allCases, id: \.self) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical, 4)

                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(uiColor: imageBinding.wrappedValue.fillColor?.swiftUIColor ?? .systemOrange))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.black.opacity(0.15), lineWidth: 1)
                                    )
                                Text("Dominant color detected from image region")
                                    .font(DesignSystem.Typography.footnote)
                                    .foregroundStyle(DesignSystem.Colors.subtleText)
                            }

                            Text("Confidence: \(Int(imageBinding.wrappedValue.confidence * 100))%")
                                .font(DesignSystem.Typography.footnote)
                                .foregroundStyle(DesignSystem.Colors.subtleText)
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous))
                }

                Spacer()
            }
            .padding(DesignSystem.Spacing.lg)
            }
        }
        .navigationTitle("Preview Editor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                    }
                    .foregroundStyle(isDarkTheme ? .white : .black)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Edit text regions")
                .font(DesignSystem.Typography.title)
            Text("Select text or box regions to refine results before export.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.subtleText)
        }
    }

    private func fittedImageRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = bounds.minX + (bounds.width - width) / 2
        let y = bounds.minY + (bounds.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func overlayRect(for elementFrame: CGRect, pageSize: PageSize, imageRect: CGRect) -> CGRect {
        guard pageSize.width > 0, pageSize.height > 0 else { return .zero }
        let x = imageRect.minX + (elementFrame.minX / pageSize.width) * imageRect.width
        let y = imageRect.minY + (elementFrame.minY / pageSize.height) * imageRect.height
        let width = (elementFrame.width / pageSize.width) * imageRect.width
        let height = (elementFrame.height / pageSize.height) * imageRect.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private enum PreviewSelection: Equatable {
    case text(UUID)
    case image(UUID)

    var id: UUID {
        switch self {
        case .text(let id):
            return id
        case .image(let id):
            return id
        }
    }
}

#Preview {
    EditorView()
        .environmentObject(DocumentStore())
}
