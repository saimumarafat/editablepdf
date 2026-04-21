import SwiftUI
import UIKit

struct CaptureView: View {
    @EnvironmentObject private var store: DocumentStore
    @AppStorage("preferredAppTheme") private var preferredAppTheme = AppThemeMode.dark.rawValue
    @State private var selectedImage: UIImage?
    @State private var isShowingPicker = false

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

            VStack(spacing: DesignSystem.Spacing.xl) {
            Text("Add a page")
                .font(DesignSystem.Typography.title)

            Text("Use the camera or import an image. The app will normalize the page and prepare it for editable export.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.subtleText)
                .multilineTextAlignment(.center)

            Button("Pick Image") {
                isShowingPicker = true
            }
            .buttonStyle(GlassButtonStyle(isDarkTheme: isDarkTheme))

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .padding(DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                            .fill(isDarkTheme ? Color.white.opacity(0.04) : Color.white.opacity(0.4))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous))
                            .shadow(color: .black.opacity(isDarkTheme ? 0.2 : 0.04), radius: 10, x: 0, y: 4)
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(colors: [.white.opacity(isDarkTheme ? 0.2 : 0.6), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1
                                    )
                            }
                    )
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.lg)
        }
        .sheet(isPresented: $isShowingPicker) {
            ImagePicker(sourceType: .photoLibrary) { image in
                Task {
                    selectedImage = image
                    await store.ingest(image: image, source: .upload)
                }
            }
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
    }
}
