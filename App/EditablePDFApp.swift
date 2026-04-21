import SwiftUI

enum AppThemeMode: String {
    case dark
    case light

    var colorScheme: ColorScheme {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    var iconName: String {
        switch self {
        case .dark:
            return "moon.fill"
        case .light:
            return "sun.max.fill"
        }
    }

    mutating func toggle() {
        self = self == .dark ? .light : .dark
    }
}

@main
struct EditablePDFApp: App {
    @StateObject private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: DocumentStore
    @AppStorage("preferredAppTheme") private var preferredAppTheme = AppThemeMode.dark.rawValue

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: preferredAppTheme) ?? .dark
    }

    var body: some View {
        NavigationStack(path: $store.routePath) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .capture:
                        CaptureView()
                    case .editor:
                        EditorView()
                    case .previewEditor:
                        PDFKitEditorView()
                    }
                }
        }
        .tint(DesignSystem.Colors.accent)
        .preferredColorScheme(themeMode.colorScheme)
        .onChange(of: store.routePath) { _, newValue in
            if newValue.isEmpty {
                store.resetToFreshFrontPage()
            }
        }
    }
}
