import SwiftUI

// MARK: - Dashboard Card Component

struct DashboardCard: View {
    let title: String
    let description: String
    let progress: Double      // 0.0 – 1.0
    let iconName: String

    @State private var isPressed = false
    @State private var iconRotation: Double = 0
    @State private var animatedProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header Row
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 46, height: 46)

                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .rotationEffect(.degrees(iconRotation))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.system(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            // Progress Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Progress")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(animatedProgress * 100))%")
                        .font(.system(.caption, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: 8)
                        // Fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.7), Color.accentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * animatedProgress, height: 8)
                    }
                }
                .frame(height: 8)
            }

            // Start Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    isPressed = true
                    iconRotation += 360
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                        isPressed = false
                    }
                }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                animatedProgress = progress
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(.systemBackground), Color.accentColor.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        DashboardCard(
            title: "Document Processing",
            description: "Vision OCR is scanning your uploaded image for editable regions.",
            progress: 0.72,
            iconName: "doc.text.viewfinder"
        )
        .padding(24)
    }
}
