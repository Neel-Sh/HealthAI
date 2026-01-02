import SwiftUI

struct MetricTile: View {
    @Environment(\.colorScheme) private var colorScheme
    
    struct Trend {
        enum Direction {
            case up
            case down
            case flat
        }
        var direction: Direction
        var percentChange: Double
        var timeframe: String
    }
    
    let title: String
    let subtitle: String
    let value: String
    let unit: String
    let glyph: String
    let tint: Color
    var sparklineData: [Double] = []
    var trend: Trend?
    var showsChevron: Bool = true
    
    var body: some View {
        ZStack {
            // Card Background
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(
                    color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.04),
                    radius: colorScheme == .dark ? 12 : 8,
                    x: 0,
                    y: colorScheme == .dark ? 6 : 3
                )
            
            VStack(alignment: .leading, spacing: 14) {
                // Header Row
                HStack(alignment: .top) {
                    // Icon Badge
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(colorScheme == .dark ? 0.15 : 0.1))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: glyph)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(tint)
                    }
                    
                    Spacer()
                    
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    }
                }
                
                // Value Section
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                        .kerning(0.6)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        if !unit.isEmpty {
                            Text(unit)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                        }
                    }
                }
                
                // Sparkline
                if !sparklineData.isEmpty {
                    SparklineChart(
                        data: sparklineData,
                        lineColor: tint,
                        fillGradient: LinearGradient(
                            colors: [tint.opacity(0.25), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 28)
                }
                
                // Footer Row
                HStack(alignment: .center, spacing: 8) {
                    if let trend {
                        trendBadge(trend)
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                        .lineLimit(1)
                    
                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 155)
    }
    
    private var cardBackground: some ShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white, Color.white.opacity(0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
    
    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.04)
    }
    
    private func trendBadge(_ trend: Trend) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon(for: trend.direction))
                .font(.system(size: 9, weight: .bold))
            
            Text(formatPercent(trend.percentChange))
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color(for: trend.direction))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color(for: trend.direction).opacity(colorScheme == .dark ? 0.15 : 0.1))
        )
    }
    
    private func icon(for direction: Trend.Direction) -> String {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "minus"
        }
    }
    
    private func color(for direction: Trend.Direction) -> Color {
        switch direction {
        case .up: return Color(hex: "34D399")
        case .down: return Color(hex: "EF4444")
        case .flat: return Color(hex: "9CA3AF")
        }
    }
    
    private func formatPercent(_ change: Double) -> String {
        let formatted = abs(change)
        if formatted >= 10 {
            return String(format: "%.0f%%", formatted)
        } else {
            return String(format: "%.1f%%", formatted)
        }
    }
}

// MARK: - Compact Metric Tile
struct CompactMetricTile: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let value: String
    let icon: String
    let color: Color
    var trend: Double? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Spacer()
                
                if let trend = trend, trend != 0 {
                    trendChip(trend: trend)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.03),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func trendChip(trend: Double) -> some View {
        let direction = trend > 0 ? "arrow.up.right" : "arrow.down.right"
        let trendColor = trend > 0 ? Color(hex: "34D399") : Color(hex: "EF4444")
        
        return HStack(spacing: 3) {
            Image(systemName: direction)
                .font(.system(size: 8, weight: .bold))
            
            Text(String(format: "%.0f%%", abs(trend)))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(trendColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(trendColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
        )
    }
}
