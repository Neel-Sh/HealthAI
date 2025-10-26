import SwiftUI
import CoreData

struct SleepDetailView: View {
    let sleepData: HealthMetrics?
    let sleepHistory: [HealthMetrics]
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    private var totalSleep: Double {
        sleepData?.sleepHours ?? 0
    }
    
    private var remSleep: Double {
        sleepData?.remSleepHours ?? 0
    }
    
    private var deepSleep: Double {
        sleepData?.deepSleepHours ?? 0
    }
    
    private var coreSleep: Double {
        max(0, totalSleep - remSleep - deepSleep)
    }
    
    private var timeInBed: Double {
        sleepData?.timeInBed ?? 0
    }
    
    private var sleepEfficiency: Double {
        guard timeInBed > 0 else { return 0 }
        return (totalSleep / timeInBed) * 100
    }
    
    private var awakeTime: Double {
        max(0, timeInBed - totalSleep)
    }
    
    private var sleepQuality: Int {
        Int(sleepData?.sleepQuality ?? 0)
    }
    
    private var sleepQualityText: String {
        switch sleepQuality {
        case 8...10: return "Excellent"
        case 6...7: return "Good"
        case 4...5: return "Fair"
        case 2...3: return "Poor"
        default: return "No data"
        }
    }
    
    private var weeklyAverage: Double {
        guard !sleepHistory.isEmpty else { return 0 }
        return sleepHistory.map { $0.sleepHours }.reduce(0, +) / Double(sleepHistory.count)
    }
    
    // MARK: - Sleep Score Calculation
    private var sleepScore: Int {
        guard totalSleep > 0 else { return 0 }
        
        var score = 0.0
        
        // 1. Duration Score (30 points) - Optimal: 7-9 hours
        let durationScore: Double
        if totalSleep >= 7 && totalSleep <= 9 {
            durationScore = 30
        } else if totalSleep >= 6 && totalSleep < 7 {
            durationScore = 25
        } else if totalSleep > 9 && totalSleep <= 10 {
            durationScore = 25
        } else if totalSleep >= 5 && totalSleep < 6 {
            durationScore = 15
        } else if totalSleep > 10 && totalSleep <= 11 {
            durationScore = 20
        } else {
            durationScore = 10
        }
        score += durationScore
        
        // 2. REM Sleep Score (25 points) - Optimal: 20-25% of total sleep
        let remPercentage = (remSleep / totalSleep) * 100
        let remScore: Double
        if remPercentage >= 20 && remPercentage <= 25 {
            remScore = 25
        } else if remPercentage >= 15 && remPercentage < 20 {
            remScore = 20
        } else if remPercentage > 25 && remPercentage <= 30 {
            remScore = 20
        } else if remPercentage >= 10 && remPercentage < 15 {
            remScore = 12
        } else {
            remScore = 5
        }
        score += remScore
        
        // 3. Deep Sleep Score (25 points) - Optimal: 15-20% of total sleep
        let deepPercentage = (deepSleep / totalSleep) * 100
        let deepScore: Double
        if deepPercentage >= 15 && deepPercentage <= 20 {
            deepScore = 25
        } else if deepPercentage >= 10 && deepPercentage < 15 {
            deepScore = 18
        } else if deepPercentage > 20 && deepPercentage <= 25 {
            deepScore = 20
        } else if deepPercentage >= 5 && deepPercentage < 10 {
            deepScore = 10
        } else {
            deepScore = 5
        }
        score += deepScore
        
        // 4. Core/Light Sleep Score (20 points) - Optimal: 45-55% of total sleep
        let corePercentage = (coreSleep / totalSleep) * 100
        let coreScore: Double
        if corePercentage >= 45 && corePercentage <= 55 {
            coreScore = 20
        } else if corePercentage >= 40 && corePercentage < 45 {
            coreScore = 15
        } else if corePercentage > 55 && corePercentage <= 60 {
            coreScore = 15
        } else if corePercentage >= 35 && corePercentage < 40 {
            coreScore = 10
        } else {
            coreScore = 5
        }
        score += coreScore
        
        return Int(min(score, 100))
    }
    
    private var sleepScoreText: String {
        switch sleepScore {
        case 85...100: return "Exceptional"
        case 70..<85: return "Great"
        case 55..<70: return "Good"
        case 40..<55: return "Fair"
        default: return "Needs Improvement"
        }
    }
    
    private var sleepScoreColor: Color {
        switch sleepScore {
        case 85...100: return .green
        case 70..<85: return .teal
        case 55..<70: return .blue
        case 40..<55: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        sleepScoreCard
                        sleepStagesCard
                        weeklyTrendCard
                        insightsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Sleep Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
    
    // MARK: - Header Card
    private var headerCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 24)
            
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.indigo.opacity(0.18))
                        .overlay(
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.indigo)
                        )
                        .frame(width: 56, height: 56)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(sleepQualityText)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        qualityStars
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Sleep")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", totalSleep))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                        Text("hours")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    if totalSleep > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(sleepTimeRange)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(24)
        }
    }
    
    private var qualityStars: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                Image(systemName: index < (sleepQuality / 2) ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
            }
        }
    }
    
    private var sleepTimeRange: String {
        guard let data = sleepData else { return "" }
        // Approximate bed time (assuming sleep ended around wake time)
        let calendar = Calendar.current
        let wakeTime = calendar.date(byAdding: .hour, value: 8, to: data.date) ?? data.date
        let bedTime = calendar.date(byAdding: .hour, value: -Int(totalSleep), to: wakeTime) ?? data.date
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        return "\(formatter.string(from: bedTime)) - \(formatter.string(from: wakeTime))"
    }
    
    // MARK: - Sleep Score Card
    private var sleepScoreCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 20)
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sleep Score")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Based on duration and sleep stages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                HStack(spacing: 24) {
                    // Score Circle
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                            .frame(width: 120, height: 120)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(sleepScore) / 100)
                            .stroke(sleepScoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 1.0), value: sleepScore)
                        
                        VStack(spacing: 4) {
                            Text("\(sleepScore)")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundColor(sleepScoreColor)
                            Text(sleepScoreText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Score Breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        scoreBreakdownRow(
                            title: "Duration",
                            icon: "clock.fill",
                            color: .blue,
                            isOptimal: totalSleep >= 7 && totalSleep <= 9
                        )
                        
                        scoreBreakdownRow(
                            title: "REM Sleep",
                            icon: "brain.head.profile",
                            color: .purple,
                            isOptimal: (remSleep / max(totalSleep, 0.01)) >= 0.20 && (remSleep / max(totalSleep, 0.01)) <= 0.25
                        )
                        
                        scoreBreakdownRow(
                            title: "Deep Sleep",
                            icon: "bed.double.fill",
                            color: .indigo,
                            isOptimal: (deepSleep / max(totalSleep, 0.01)) >= 0.15 && (deepSleep / max(totalSleep, 0.01)) <= 0.20
                        )
                        
                        scoreBreakdownRow(
                            title: "Core Sleep",
                            icon: "moon.fill",
                            color: .cyan,
                            isOptimal: (coreSleep / max(totalSleep, 0.01)) >= 0.45 && (coreSleep / max(totalSleep, 0.01)) <= 0.55
                        )
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func scoreBreakdownRow(title: String, icon: String, color: Color, isOptimal: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.15))
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(color)
                )
                .frame(width: 28, height: 28)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            if isOptimal {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Sleep Stages Card
    private var sleepStagesCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 20)
            VStack(alignment: .leading, spacing: 18) {
                Text("Sleep Stages")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                // Sleep stages visualization
                if totalSleep > 0 {
                    VStack(spacing: 16) {
                        sleepStageBar
                        
                        VStack(spacing: 10) {
                            sleepStageRow(
                                title: "REM",
                                duration: remSleep,
                                percentage: (remSleep / totalSleep) * 100,
                                color: .purple,
                                icon: "brain.head.profile",
                                isOptimal: (remSleep / totalSleep) >= 0.20 && (remSleep / totalSleep) <= 0.25
                            )
                            
                            Divider()
                                .padding(.horizontal, -4)
                            
                            sleepStageRow(
                                title: "Deep",
                                duration: deepSleep,
                                percentage: (deepSleep / totalSleep) * 100,
                                color: .blue,
                                icon: "bed.double.fill",
                                isOptimal: (deepSleep / totalSleep) >= 0.15 && (deepSleep / totalSleep) <= 0.20
                            )
                            
                            Divider()
                                .padding(.horizontal, -4)
                            
                            sleepStageRow(
                                title: "Core",
                                duration: coreSleep,
                                percentage: (coreSleep / totalSleep) * 100,
                                color: .cyan,
                                icon: "moon.fill",
                                isOptimal: (coreSleep / totalSleep) >= 0.45 && (coreSleep / totalSleep) <= 0.55
                            )
                        }
                    }
                } else {
                    emptyStateView
                }
            }
            .padding(20)
        }
    }
    
    private var sleepStageBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if totalSleep > 0 {
                    Rectangle()
                        .fill(Color.purple.opacity(0.8))
                        .frame(width: geometry.size.width * CGFloat(remSleep / totalSleep))
                    
                    Rectangle()
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: geometry.size.width * CGFloat(deepSleep / totalSleep))
                    
                    Rectangle()
                        .fill(Color.cyan.opacity(0.8))
                        .frame(width: geometry.size.width * CGFloat(coreSleep / totalSleep))
                }
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(height: 40)
    }
    
    private func sleepStageRow(title: String, duration: Double, percentage: Double, color: Color, icon: String, isOptimal: Bool) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.15))
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(color)
                )
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if isOptimal {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                    }
                }
                Text(String(format: "%.1f hours • %.0f%%", duration, percentage))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("Optimal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(optimalPercentageText(for: title))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func optimalPercentageText(for stage: String) -> String {
        switch stage {
        case "REM": return "20-25%"
        case "Deep": return "15-20%"
        case "Core": return "45-55%"
        default: return ""
        }
    }
    
    
    // MARK: - Weekly Trend Card
    private var weeklyTrendCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 20)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("7-Day Trend")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    if weeklyAverage > 0 {
                        Text(String(format: "Avg • %.1f h", weeklyAverage))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !sleepHistory.isEmpty {
                    SleepTrendChart(sleepHistory: sleepHistory)
                        .frame(height: 180)
                } else {
                    emptyStateView
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Insights Card
    private var insightsCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 20)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.title3)
                        .foregroundColor(.yellow)
                    Text("Sleep Insights")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sleepInsights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.green)
                            Text(insight)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    private var sleepInsights: [String] {
        var insights: [String] = []
        
        if totalSleep >= 7 && totalSleep <= 9 {
            insights.append("You're getting the recommended 7-9 hours of sleep.")
        } else if totalSleep < 7 {
            insights.append("Try to increase your sleep duration to 7-9 hours for optimal recovery.")
        } else {
            insights.append("Consider if you might be over-sleeping. 7-9 hours is optimal for most adults.")
        }
        
        let remPercentage = totalSleep > 0 ? (remSleep / totalSleep) : 0
        if remPercentage >= 0.20 && remPercentage <= 0.25 {
            insights.append("Your REM sleep is in the optimal range for memory consolidation and learning.")
        } else if remPercentage < 0.20 {
            insights.append("Try to increase REM sleep by maintaining a consistent sleep schedule.")
        }
        
        let deepPercentage = totalSleep > 0 ? (deepSleep / totalSleep) : 0
        if deepPercentage >= 0.15 && deepPercentage <= 0.20 {
            insights.append("Your deep sleep is optimal for physical recovery and immune function.")
        } else if deepPercentage < 0.15 {
            insights.append("Avoid caffeine 6 hours before bed to improve deep sleep quality.")
        }
        
        if sleepEfficiency >= 85 {
            insights.append("Excellent sleep efficiency! You're making good use of your time in bed.")
        } else {
            insights.append("Try going to bed only when sleepy to improve sleep efficiency.")
        }
        
        return insights
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No sleep data available")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Sleep Trend Chart
struct SleepTrendChart: View {
    let sleepHistory: [HealthMetrics]
    
    private var chartData: [(date: Date, total: Double, rem: Double, deep: Double, core: Double)] {
        sleepHistory.suffix(7).map { metrics in
            let rem = metrics.remSleepHours
            let deep = metrics.deepSleepHours
            let total = metrics.sleepHours
            let core = max(0, total - rem - deep)
            return (metrics.date, total, rem, deep, core)
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Chart
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(chartData.enumerated()), id: \.offset) { index, data in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                // Background bar
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: barWidth(for: geometry.size.width), height: geometry.size.height * 0.8)
                                
                                // Stacked sleep stages
                                VStack(spacing: 0) {
                                    Spacer()
                                    if data.rem > 0 {
                                        Rectangle()
                                            .fill(Color.purple.opacity(0.8))
                                            .frame(height: barHeight(data.rem, maxHeight: geometry.size.height * 0.8))
                                    }
                                    if data.deep > 0 {
                                        Rectangle()
                                            .fill(Color.blue.opacity(0.8))
                                            .frame(height: barHeight(data.deep, maxHeight: geometry.size.height * 0.8))
                                    }
                                    if data.core > 0 {
                                        Rectangle()
                                            .fill(Color.cyan.opacity(0.8))
                                            .frame(height: barHeight(data.core, maxHeight: geometry.size.height * 0.8))
                                    }
                                }
                                .frame(width: barWidth(for: geometry.size.width))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            
                            Text(dayLabel(for: data.date))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Legend
            HStack(spacing: 16) {
                legendItem(color: .purple, label: "REM")
                legendItem(color: .blue, label: "Deep")
                legendItem(color: .cyan, label: "Core")
            }
            .font(.caption)
        }
    }
    
    private func barWidth(for totalWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = 8 * CGFloat(chartData.count - 1)
        return (totalWidth - spacing) / CGFloat(max(chartData.count, 1))
    }
    
    private func barHeight(_ hours: Double, maxHeight: CGFloat) -> CGFloat {
        let maxSleep = 10.0 // Maximum expected sleep hours
        return maxHeight * CGFloat(hours / maxSleep)
    }
    
    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Background Gradient
private struct BackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.black, Color(white: 0.12)]
                : [Color(white: 0.97), Color(white: 0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}


