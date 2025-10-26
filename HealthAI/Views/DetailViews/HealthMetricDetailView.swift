import SwiftUI

struct HealthMetricDetailView: View {
    enum MetricKind: Hashable {
        case heartRate
        case hrv
        case vo2Max
        case sleep
        case bloodOxygen
        case respiratoryRate
        case stress
        case bodyComposition
        case hydration
    }
    
    struct MetricContext {
        let title: String
        let primaryValue: String
        let unit: String
        let description: String
        let trends: [Double]
        let weeklyAverage: String
        let dailyValues: [DailyMetric]
        let guidance: [String]
        let systemIcon: String
        let tint: Color
        let annotations: [Annotation]
    }
    
    struct DailyMetric: Identifiable {
        let id = UUID()
        let date: Date
        let value: String
        let delta: Double?
    }
    
    struct Annotation: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let icon: String
        let color: Color
    }
    
    var kind: MetricKind
    var context: MetricContext
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroCard
                trendSection
                dailyBreakdown
                insightsSection
            }
            .padding(22)
            .padding(.bottom, 40)
        }
        .background(BackgroundGradient(kind: kind))
        .navigationTitle(context.title)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var heroCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 26)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(context.tint.opacity(0.15))
                        .overlay(
                            Image(systemName: context.systemIcon)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(context.tint)
                        )
                        .frame(width: 66, height: 66)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.title)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text(context.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(context.primaryValue)
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                    Text(context.unit)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                if !context.annotations.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(context.annotations) { annotation in
                            HStack(spacing: 8) {
                                Image(systemName: annotation.icon)
                                    .font(.caption)
                                    .foregroundColor(annotation.color)
                                Text(annotation.title)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(annotation.color.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(26)
        }
    }
    
    private var trendSection: some View {
        ZStack {
            GlassCardBackground()
            VStack(alignment: .leading, spacing: 18) {
                Text("Recent Trend")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                SparklineChart(
                    data: context.trends,
                    lineColor: context.tint,
                    fillGradient: LinearGradient(
                        colors: [context.tint.opacity(0.3), context.tint.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2.5
                )
                .frame(height: 120)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekly Average")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(context.weeklyAverage)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                }
            }
            .padding(24)
        }
    }
    
    private var dailyBreakdown: some View {
        ZStack {
            GlassCardBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Daily Breakdown")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                VStack(spacing: 12) {
                    ForEach(context.dailyValues) { daily in
                        HStack {
                            Text(dateFormatter.string(from: daily.date))
                                .font(.subheadline)
                            Spacer()
                            Text(daily.value)
                                .font(.headline)
                            if let delta = daily.delta {
                                HStack(spacing: 4) {
                                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    Text(String(format: "%+.1f%%", delta))
                                }
                                .font(.caption)
                                .foregroundColor(delta >= 0 ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((delta >= 0 ? Color.green : Color.red).opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 6)
                        
                        if daily.id != context.dailyValues.last?.id {
                            Divider().background(Color.primary.opacity(0.1))
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private var insightsSection: some View {
        ZStack {
            GlassCardBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Guidance")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                ForEach(Array(context.guidance.enumerated()), id: \.offset) { index, insight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(context.tint)
                        Text(insight)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }
                    if index != context.guidance.count - 1 {
                        Divider().background(Color.primary.opacity(0.1))
                    }
                }
            }
            .padding(24)
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }
}

private struct BackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme
    var kind: HealthMetricDetailView.MetricKind
    
    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var gradientColors: [Color] {
        if colorScheme == .dark {
            switch kind {
            case .heartRate: return [Color.black, Color(white: 0.12)]
            case .hrv: return [Color.black, Color(white: 0.1)]
            case .vo2Max: return [Color.black, Color(white: 0.08)]
            case .sleep: return [Color.black, Color(white: 0.06)]
            case .bloodOxygen: return [Color.black, Color(white: 0.1)]
            case .respiratoryRate: return [Color.black, Color(white: 0.09)]
            case .stress: return [Color.black, Color(white: 0.1)]
            case .bodyComposition: return [Color.black, Color(white: 0.08)]
            case .hydration: return [Color.black, Color(white: 0.09)]
            }
        } else {
            switch kind {
            case .heartRate: return [Color(white: 0.98), Color(white: 0.93)]
            case .hrv: return [Color(white: 0.98), Color(white: 0.92)]
            case .vo2Max: return [Color(white: 0.98), Color(white: 0.92)]
            case .sleep: return [Color(white: 0.98), Color(white: 0.94)]
            case .bloodOxygen: return [Color(white: 0.98), Color(white: 0.92)]
            case .respiratoryRate: return [Color(white: 0.98), Color(white: 0.93)]
            case .stress: return [Color(white: 0.98), Color(white: 0.93)]
            case .bodyComposition: return [Color(white: 0.98), Color(white: 0.92)]
            case .hydration: return [Color(white: 0.98), Color(white: 0.93)]
            }
        }
    }
}

