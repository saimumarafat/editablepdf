import SwiftUI

enum DesignSystem {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
    }

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 16
        static let hero: CGFloat = 28
    }

    enum Colors {
        static let accent = Color(red: 0.12, green: 0.48, blue: 0.93)
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let text = Color.primary
        static let subtleText = Color.secondary
        
        // Premium Red for Docks
        static let premiumRed = Color(red: 0.58, green: 0.05, blue: 0.12)
        static let premiumRedGlass = Color(red: 0.65, green: 0.08, blue: 0.15).opacity(0.45)
    }

    enum Typography {
        static let title = Font.largeTitle.weight(.bold)
        static let headline = Font.headline.weight(.semibold)
        static let body = Font.body
        static let footnote = Font.footnote
    }
}

struct GlassButtonStyle: ButtonStyle {
    let isDarkTheme: Bool

    init(isDarkTheme: Bool = true) {
        self.isDarkTheme = isDarkTheme
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(isDarkTheme ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                    .fill(isDarkTheme ? Color.white.opacity(configuration.isPressed ? 0.15 : 0.1) : Color.white.opacity(configuration.isPressed ? 0.7 : 0.5))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isDarkTheme ? 0.3 : 0.8),
                                .white.opacity(isDarkTheme ? 0.05 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(isDarkTheme ? 0.2 : 0.05), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1), value: configuration.isPressed)
    }
}

struct LiquidGlassButtonStyle: ButtonStyle {
    let isDarkTheme: Bool

    init(isDarkTheme: Bool = true) {
        self.isDarkTheme = isDarkTheme
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.hero, style: .continuous)
                    .fill(DesignSystem.Colors.accent.opacity(configuration.isPressed ? 0.7 : 0.85))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.hero, style: .continuous))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.hero, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.5),
                                .white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: DesignSystem.Colors.accent.opacity(0.3), radius: 12, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1), value: configuration.isPressed)
    }
}

struct LiquidThemeToggleButtonStyle: ButtonStyle {
    let isDarkTheme: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isDarkTheme ? .white : .black)
            .frame(width: 116, height: 42)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill((isDarkTheme ? Color.white : Color.black).opacity(configuration.isPressed ? 0.05 : 0.08))
                    }
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder((isDarkTheme ? Color.white : Color.black).opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(configuration.isPressed ? 0.08 : 0.12), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SettingsThemeButtonStyle: ButtonStyle {
    let isActive: Bool
    let isDarkTheme: Bool

    func makeBody(configuration: Configuration) -> some View {
        let textColor = isActive ? (isDarkTheme ? Color.white : Color.black) : (isDarkTheme ? Color.white.opacity(0.60) : Color.black.opacity(0.50))
        let fillOpacity = isActive ? (configuration.isPressed ? 0.08 : 0.12) : 0.0
        let strokeOpacity = isActive ? 0.20 : 0.0
        
        return configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((isDarkTheme ? Color.white : Color.black).opacity(fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder((isDarkTheme ? Color.white : Color.black).opacity(strokeOpacity), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassToggleStyle: ToggleStyle {
    let isDarkTheme: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isDarkTheme ? .white : .black)
            
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((isDarkTheme ? Color.white : Color.black).opacity(configuration.isOn ? 0.12 : 0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder((isDarkTheme ? Color.white : Color.black).opacity(0.20), lineWidth: 1)
                    }
                
                Circle()
                    .fill(isDarkTheme ? .white : .black)
                    .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
                    .padding(3)
            }
            .frame(width: 50, height: 30)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.20)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

struct TranslucentGlassButtonStyle: ButtonStyle {
    let isDarkTheme: Bool

    init(isDarkTheme: Bool = true) {
        self.isDarkTheme = isDarkTheme
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(isDarkTheme ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                Capsule(style: .continuous)
                    .fill(isDarkTheme ? Color.white.opacity(configuration.isPressed ? 0.15 : 0.08) : Color.white.opacity(configuration.isPressed ? 0.6 : 0.4))
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isDarkTheme ? 0.2 : 0.6),
                                .white.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(isDarkTheme ? 0.15 : 0.05), radius: 12, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1), value: configuration.isPressed)
    }
}

struct AppLogoMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            DesignSystem.Colors.accent.opacity(0.98),
                            DesignSystem.Colors.accent.opacity(0.80),
                            Color.black.opacity(0.12)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.96
                    )
                )

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: DesignSystem.Colors.accent.opacity(0.20), radius: 14, x: 0, y: 6)
    }
}

struct LiquidGlassEffect: ViewModifier {
    var cornerRadius: CGFloat = 24
    var isDark: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isDark 
                        ? DesignSystem.Colors.premiumRedGlass.opacity(0.85) 
                        : DesignSystem.Colors.premiumRedGlass.opacity(0.65))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            DesignSystem.Colors.premiumRed.opacity(isDark ? 0.3 : 0.6),
                            Color.clear,
                            Color.black.opacity(isDark ? 0.15 : 0.05)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(isDark ? 0.40 : 0.70),
                                DesignSystem.Colors.premiumRed.opacity(isDark ? 0.2 : 0.4),
                                .clear
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: DesignSystem.Colors.premiumRed.opacity(isDark ? 0.50 : 0.12), radius: 24, x: 0, y: 10)
            .shadow(color: .black.opacity(isDark ? 0.30 : 0.08),  radius: 6,  x: 0, y: 3)
    }
}

extension View {
    func liquidGlassEffect(cornerRadius: CGFloat = 24, isDark: Bool = true) -> some View {
        modifier(LiquidGlassEffect(cornerRadius: cornerRadius, isDark: isDark))
    }
}

struct AppFont: Identifiable {
    let id:      String
    let uiName:  String
    let preview: String

    static let all: [AppFont] = [
        AppFont(id: "System",   uiName: "",                          preview: "Aa"),
        AppFont(id: "Serif",    uiName: "Georgia",                   preview: "Aa"),
        AppFont(id: "Rounded",  uiName: "AvenirNext-Regular",        preview: "Aa"),
        AppFont(id: "Mono",     uiName: "Menlo-Regular",             preview: "Aa"),
        AppFont(id: "Thin",     uiName: "HelveticaNeue-Light",       preview: "Aa"),
        AppFont(id: "Bold",     uiName: "HelveticaNeue-Bold",        preview: "Aa"),
        AppFont(id: "Italic",   uiName: "Georgia-Italic",            preview: "Aa"),
        AppFont(id: "Display",  uiName: "Didot",                     preview: "Aa"),
        AppFont(id: "Code",     uiName: "Courier-Bold",              preview: "Aa"),
        AppFont(id: "Bangla",   uiName: "KohinoorBangla-Regular",    preview: "বাং"),
        AppFont(id: "BanglaBd", uiName: "KohinoorBangla-Semibold",   preview: "বাং"),
        AppFont(id: "Hindi",    uiName: "KohinoorDevanagari-Regular", preview: "हिं"),
        AppFont(id: "Arabic",   uiName: "GeezaPro",                  preview: "ع"),
    ]

    var uiFont: UIFont {
        guard !uiName.isEmpty, let f = UIFont(name: uiName, size: 16) else {
            return .systemFont(ofSize: 16)
        }
        return f
    }
    var swiftUIFont: Font {
        guard !uiName.isEmpty else { return .system(size: 16) }
        return .custom(uiName, size: 16)
    }

    static func resolveUIFont(id: String, size: CGFloat) -> UIFont {
        let match = all.first { $0.id == id }
        guard let uiName = match?.uiName, !uiName.isEmpty,
              let f = UIFont(name: uiName, size: size) else {
            return .systemFont(ofSize: size)
        }
        return f
    }
}
