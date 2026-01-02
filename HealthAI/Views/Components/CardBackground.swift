import SwiftUI

// MARK: - Premium Glass Card Background
struct GlassCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 20
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(backgroundFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderGradient, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowOffset)
    }
    
    private var backgroundFill: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
    
    private var borderGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.8),
                    Color.black.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.06)
    }
    
    private var shadowRadius: CGFloat {
        colorScheme == .dark ? 16 : 12
    }
    
    private var shadowOffset: CGFloat {
        colorScheme == .dark ? 8 : 4
    }
}

// MARK: - Health Tile Background
struct HealthTileBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(tileFill)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderGradient, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowOffset)
    }
    
    private var tileFill: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
    
    private var borderGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.7),
                    Color.black.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.05)
    }
    
    private var shadowRadius: CGFloat {
        colorScheme == .dark ? 14 : 10
    }
    
    private var shadowOffset: CGFloat {
        colorScheme == .dark ? 6 : 4
    }
}

// MARK: - Accent Card Background
struct AccentCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var color: Color = Color(hex: "E07A5F")
    var cornerRadius: CGFloat = 24
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(0.95),
                        color.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: color.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Subtle Card Background
struct SubtleCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 16
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colorScheme == .dark
                  ? Color.white.opacity(0.03)
                  : Color.black.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.06)
                            : Color.black.opacity(0.04),
                        lineWidth: 1
                    )
            )
    }
}
