import SwiftUI

struct MetricTile: View {
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
            HealthTileBackground()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .overlay(
                            Image(systemName: glyph)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(tint)
                        )
                        .frame(width: 36, height: 36)
                    
                    Spacer()
                    
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .kerning(0.5)
                    
                    Text(value)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !sparklineData.isEmpty {
                    SparklineChart(
                        data: sparklineData,
                        lineColor: tint,
                        fillGradient: LinearGradient(
                            colors: [tint.opacity(0.3), tint.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom)
                    )
                    .frame(height: 32)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    if let trend {
                        HStack(spacing: 5) {
                            Image(systemName: icon(for: trend.direction))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(color(for: trend.direction))
                            
                            Text(formatPercent(trend.percentChange))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(color(for: trend.direction))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(color(for: trend.direction).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 155)
    }
    
    private func icon(for direction: Trend.Direction) -> String {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.left.and.right"
        }
    }
    
    private func color(for direction: Trend.Direction) -> Color {
        switch direction {
        case .up: return .green
        case .down: return .red
        case .flat: return .gray
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

