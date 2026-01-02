import SwiftUI

// MARK: - Design System
// A sophisticated, modern design system inspired by Apple, OpenAI, and Anthropic

// MARK: - App Theme
struct AppTheme {
    // MARK: - Color Palette
    struct Colors {
        // Primary accent - warm terracotta/coral (Anthropic-inspired)
        static let accent = Color("AccentPrimary", bundle: nil)
        static let accentGradient = LinearGradient(
            colors: [Color(hex: "E07A5F"), Color(hex: "D4634C")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // Secondary accents
        static let teal = Color(hex: "2D9C9C")
        static let indigo = Color(hex: "5856D6")
        static let mint = Color(hex: "00C7BE")
        static let coral = Color(hex: "E07A5F")
        
        // Semantic colors
        static let success = Color(hex: "34C759")
        static let warning = Color(hex: "FF9500")
        static let error = Color(hex: "FF3B30")
        static let info = Color(hex: "007AFF")
        
        // Neutral palette
        static let neutral50 = Color(hex: "FAFAFA")
        static let neutral100 = Color(hex: "F5F5F5")
        static let neutral200 = Color(hex: "E5E5E5")
        static let neutral300 = Color(hex: "D4D4D4")
        static let neutral400 = Color(hex: "A3A3A3")
        static let neutral500 = Color(hex: "737373")
        static let neutral600 = Color(hex: "525252")
        static let neutral700 = Color(hex: "404040")
        static let neutral800 = Color(hex: "262626")
        static let neutral900 = Color(hex: "171717")
        
        // Background colors
        struct Background {
            static func primary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "FAFAFA")
            }
            
            static func secondary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color(hex: "141416") : Color(hex: "F5F5F5")
            }
            
            static func tertiary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color(hex: "1C1C1E") : Color(hex: "FFFFFF")
            }
            
            static func elevated(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color(hex: "1C1C1E") : Color.white
            }
        }
        
        // Surface colors for cards
        struct Surface {
            static func primary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
            }
            
            static func secondary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color.white.opacity(0.03) : Color(hex: "F8F8F8")
            }
        }
        
        // Text colors
        struct Text {
            static func primary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color.white : Color(hex: "1A1A1A")
            }
            
            static func secondary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color.white.opacity(0.6) : Color(hex: "6B6B6B")
            }
            
            static func tertiary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color.white.opacity(0.4) : Color(hex: "9CA3AF")
            }
        }
        
        // Border colors
        struct Border {
            static func primary(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
            }
            
            static func subtle(_ colorScheme: ColorScheme) -> Color {
                colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
            }
        }
    }
    
    // MARK: - Typography
    struct Typography {
        // Display
        static func displayLarge() -> Font {
            .system(size: 34, weight: .bold, design: .default)
        }
        
        static func displayMedium() -> Font {
            .system(size: 28, weight: .bold, design: .default)
        }
        
        static func displaySmall() -> Font {
            .system(size: 24, weight: .semibold, design: .default)
        }
        
        // Headlines
        static func headlineLarge() -> Font {
            .system(size: 20, weight: .semibold, design: .default)
        }
        
        static func headlineMedium() -> Font {
            .system(size: 17, weight: .semibold, design: .default)
        }
        
        static func headlineSmall() -> Font {
            .system(size: 15, weight: .semibold, design: .default)
        }
        
        // Body
        static func bodyLarge() -> Font {
            .system(size: 17, weight: .regular, design: .default)
        }
        
        static func bodyMedium() -> Font {
            .system(size: 15, weight: .regular, design: .default)
        }
        
        static func bodySmall() -> Font {
            .system(size: 13, weight: .regular, design: .default)
        }
        
        // Labels
        static func labelLarge() -> Font {
            .system(size: 14, weight: .medium, design: .default)
        }
        
        static func labelMedium() -> Font {
            .system(size: 12, weight: .medium, design: .default)
        }
        
        static func labelSmall() -> Font {
            .system(size: 11, weight: .medium, design: .default)
        }
        
        // Mono (for numbers)
        static func monoLarge() -> Font {
            .system(size: 32, weight: .semibold, design: .monospaced)
        }
        
        static func monoMedium() -> Font {
            .system(size: 24, weight: .medium, design: .monospaced)
        }
        
        static func monoSmall() -> Font {
            .system(size: 14, weight: .medium, design: .monospaced)
        }
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
    }
    
    // MARK: - Corner Radius
    struct Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let full: CGFloat = 999
    }
    
    // MARK: - Shadows
    struct Shadow {
        static func subtle(_ colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
            colorScheme == .dark
                ? (Color.black.opacity(0.5), 8, 0, 4)
                : (Color.black.opacity(0.04), 8, 0, 2)
        }
        
        static func medium(_ colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
            colorScheme == .dark
                ? (Color.black.opacity(0.6), 16, 0, 8)
                : (Color.black.opacity(0.08), 16, 0, 4)
        }
        
        static func prominent(_ colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
            colorScheme == .dark
                ? (Color.black.opacity(0.7), 24, 0, 12)
                : (Color.black.opacity(0.12), 24, 0, 8)
        }
    }
}

// MARK: - Refined Card Background
struct ModernCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    var padding: CGFloat = AppTheme.Spacing.lg
    var cornerRadius: CGFloat = AppTheme.Radius.xl
    var hasBorder: Bool = true
    
    init(
        padding: CGFloat = AppTheme.Spacing.lg,
        cornerRadius: CGFloat = AppTheme.Radius.xl,
        hasBorder: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.hasBorder = hasBorder
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.Surface.primary(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.Border.primary(colorScheme), lineWidth: hasBorder ? 1 : 0)
            )
            .shadow(
                color: AppTheme.Shadow.subtle(colorScheme).color,
                radius: AppTheme.Shadow.subtle(colorScheme).radius,
                x: AppTheme.Shadow.subtle(colorScheme).x,
                y: AppTheme.Shadow.subtle(colorScheme).y
            )
    }
}

// MARK: - Premium Glass Card
struct PremiumGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    var cornerRadius: CGFloat = AppTheme.Radius.xl
    
    init(
        cornerRadius: CGFloat = AppTheme.Radius.xl,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .background(
                ZStack {
                    // Base fill
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark
                              ? Color.white.opacity(0.04)
                              : Color.white.opacity(0.8))
                    
                    // Subtle gradient overlay
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.06), Color.white.opacity(0.02)]
                                    : [Color.white.opacity(0.6), Color.white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.04)]
                                : [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.06),
                radius: colorScheme == .dark ? 16 : 12,
                x: 0,
                y: colorScheme == .dark ? 8 : 4
            )
    }
}

// MARK: - Gradient Background
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var accentColor: Color? = nil
    
    var body: some View {
        ZStack {
            // Base
            AppTheme.Colors.Background.primary(colorScheme)
            
            // Subtle accent glow (optional)
            if let accent = accentColor {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    .blur(radius: 120)
                    .offset(x: -100, y: -200)
                    .frame(width: 400, height: 400)
            }
            
            // Top gradient fade
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.02), Color.clear]
                    : [Color.black.opacity(0.02), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Accent Button
struct AccentButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var icon: String? = nil
    var style: ButtonStyleType = .primary
    let action: () -> Void
    
    enum ButtonStyleType {
        case primary
        case secondary
        case ghost
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(AppTheme.Typography.labelLarge())
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
            .foregroundColor(foregroundColor)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            .overlay(border)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            AppTheme.Colors.coral
        case .secondary:
            AppTheme.Colors.coral.opacity(colorScheme == .dark ? 0.15 : 0.1)
        case .ghost:
            Color.clear
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary, .ghost:
            return AppTheme.Colors.coral
        }
    }
    
    @ViewBuilder
    private var border: some View {
        switch style {
        case .ghost:
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .stroke(AppTheme.Colors.Border.primary(colorScheme), lineWidth: 1)
        default:
            EmptyView()
        }
    }
}

// MARK: - Metric Badge
struct MetricBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let value: String
    let trend: TrendDirection
    
    enum TrendDirection {
        case up, down, neutral
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "minus"
            }
        }
        
        var color: Color {
            switch self {
            case .up: return AppTheme.Colors.success
            case .down: return AppTheme.Colors.error
            case .neutral: return AppTheme.Colors.neutral400
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.icon)
                .font(.system(size: 10, weight: .bold))
            Text(value)
                .font(AppTheme.Typography.labelSmall())
        }
        .foregroundColor(trend.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(trend.color.opacity(colorScheme == .dark ? 0.15 : 0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"
    
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.headlineMedium())
                    .foregroundColor(AppTheme.Colors.Text.primary(colorScheme))
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.bodySmall())
                        .foregroundColor(AppTheme.Colors.Text.tertiary(colorScheme))
                }
            }
            
            Spacer()
            
            if let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(AppTheme.Typography.labelMedium())
                        .foregroundColor(AppTheme.Colors.coral)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Icon Badge
struct IconBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    var color: Color = AppTheme.Colors.coral
    var size: BadgeSize = .medium
    
    enum BadgeSize {
        case small, medium, large
        
        var dimension: CGFloat {
            switch self {
            case .small: return 28
            case .medium: return 36
            case .large: return 48
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 15
            case .large: return 20
            }
        }
        
        var radius: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 10
            case .large: return 14
            }
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
            
            Image(systemName: icon)
                .font(.system(size: size.iconSize, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(width: size.dimension, height: size.dimension)
    }
}

// MARK: - Loading Indicator
struct ModernLoader: View {
    @State private var isAnimating = false
    var color: Color = AppTheme.Colors.coral
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Get Started"
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(AppTheme.Colors.Text.tertiary(colorScheme))
            
            VStack(spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(AppTheme.Typography.headlineMedium())
                    .foregroundColor(AppTheme.Colors.Text.primary(colorScheme))
                
                Text(message)
                    .font(AppTheme.Typography.bodySmall())
                    .foregroundColor(AppTheme.Colors.Text.secondary(colorScheme))
                    .multilineTextAlignment(.center)
            }
            
            if let action = action {
                AccentButton(title: actionLabel, action: action)
            }
        }
        .padding(AppTheme.Spacing.xxl)
    }
}

// MARK: - Divider
struct ModernDivider: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Rectangle()
            .fill(AppTheme.Colors.Border.subtle(colorScheme))
            .frame(height: 1)
    }
}

// MARK: - Progress Ring
struct ModernProgressRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    var color: Color = AppTheme.Colors.coral
    var lineWidth: CGFloat = 8
    var size: CGFloat = 120
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    color.opacity(colorScheme == .dark ? 0.15 : 0.1),
                    lineWidth: lineWidth
                )
            
            // Progress ring
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Stat Tile
struct StatTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    var unit: String? = nil
    var icon: String? = nil
    var color: Color = AppTheme.Colors.coral
    var trend: (value: String, direction: MetricBadge.TrendDirection)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                if let icon = icon {
                    IconBadge(icon: icon, color: color, size: .small)
                }
                
                Spacer()
                
                if let trend = trend {
                    MetricBadge(value: trend.value, trend: trend.direction)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 24, weight: .semibold, design: .default))
                        .foregroundColor(AppTheme.Colors.Text.primary(colorScheme))
                    
                    if let unit = unit {
                        Text(unit)
                            .font(AppTheme.Typography.bodySmall())
                            .foregroundColor(AppTheme.Colors.Text.tertiary(colorScheme))
                    }
                }
                
                Text(title)
                    .font(AppTheme.Typography.labelMedium())
                    .foregroundColor(AppTheme.Colors.Text.secondary(colorScheme))
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppTheme.Colors.Surface.secondary(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(AppTheme.Colors.Border.subtle(colorScheme), lineWidth: 1)
        )
    }
}

// MARK: - Helper Extensions
extension View {
    func modernCard(
        padding: CGFloat = AppTheme.Spacing.lg,
        cornerRadius: CGFloat = AppTheme.Radius.xl
    ) -> some View {
        ModernCard(padding: padding, cornerRadius: cornerRadius) {
            self
        }
    }
    
    func premiumGlass(cornerRadius: CGFloat = AppTheme.Radius.xl) -> some View {
        PremiumGlassCard(cornerRadius: cornerRadius) {
            self
        }
    }
}

