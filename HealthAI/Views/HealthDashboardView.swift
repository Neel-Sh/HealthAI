import SwiftUI
import CoreData
import Combine

struct HealthDashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var healthKitService: HealthKitService
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject var analyticsService: AnalyticsService
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        predicate: NSPredicate(format: "date == %@", Calendar.current.startOfDay(for: Date()) as NSDate),
        animation: .default)
    private var todaysMetrics: FetchedResults<HealthMetrics>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        animation: .default)
    private var allHealthMetrics: FetchedResults<HealthMetrics>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)],
        animation: .default)
    private var workouts: FetchedResults<WorkoutLog>
    
    @State private var isLoading = false
    @State private var lastRefreshTime = Date()
    @State private var refreshTimer: Timer?
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedMetricKind: HealthMetricDetailView.MetricKind?
    @State private var selectedMetricContext: HealthMetricDetailView.MetricContext?
    @State private var showSleepDetail = false
    
    private let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 16), count: 2)
    
    private var todaysData: HealthMetrics? {
        todaysMetrics.first
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
        }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
    
    private var healthScore: Int {
        guard let data = todaysData else { return 0 }
        let activityComponent = min(Double(data.stepCount) / 10000.0, 1.0) * 35
        let activeEnergyComponent = min(data.activeCalories / 500.0, 1.0) * 20
        let sleepComponent = min(data.sleepHours / 8.0, 1.0) * 20
        let qualityComponent = Double(data.sleepQuality) / 10.0 * 10
        let heartComponent: Double
        if data.restingHeartRate >= 60 && data.restingHeartRate <= 70 { heartComponent = 10 }
        else if data.restingHeartRate < 60 { heartComponent = 8 }
        else if data.restingHeartRate <= 80 { heartComponent = 6 }
        else { heartComponent = max(4 - Double(data.restingHeartRate - 80) * 0.1, 0) }
        let recoveryComponent = min(data.hrv / 80.0, 1.0) * 5
        return Int(min(activityComponent + activeEnergyComponent + sleepComponent + qualityComponent + heartComponent + recoveryComponent, 100))
    }
    
    private var healthScoreSummary: String {
        switch healthScore {
        case 85...100: return "Exceptional health day"
        case 70..<85: return "Strong recovery and readiness"
        case 55..<70: return "Moderate readiness"
        default: return "Focus on rest and hydration"
        }
    }
    
    private var activityScore: Int {
        guard let data = todaysData else { return 0 }
        let stepsScore = min(Double(data.stepCount) / 10000.0 * 60, 60)
        let caloriesScore = min(data.activeCalories / 500.0 * 40, 40)
        return Int(stepsScore + caloriesScore)
    }
    
    private var activitySummary: String {
        guard let data = todaysData else { return "No activity logged yet" }
        if data.stepCount >= 10000 && data.activeCalories >= 500 {
            return "You’ve hit today’s move and step goals"
        } else if data.stepCount >= 8000 {
            return "Almost there — a short walk pushes you over"
        } else {
            return "A quick walk will improve activity recovery"
        }
    }
    
    private var sleepScore: Int {
        guard let data = todaysData else { return 0 }
        let duration = data.sleepHours
        let durationScore: Double
        if duration >= 7 && duration <= 9 { durationScore = 70 }
        else if duration >= 6 && duration < 7 { durationScore = 55 }
        else if duration > 9 && duration <= 10 { durationScore = 60 }
        else { durationScore = max(40 - abs(duration - 8) * 8, 0) }
        let qualityScore = Double(data.sleepQuality) / 10.0 * 30
        return Int(min(durationScore + qualityScore, 100))
    }
    
    private var sleepSummary: String {
        guard let data = todaysData else { return "No sleep data" }
        if data.sleepHours >= 7.5 {
            return "Great sleep duration and efficiency"
        } else if data.sleepHours >= 6.5 {
            return "Nearly optimal rest – stay consistent"
        } else {
            return "Aim for 7-8 hours tonight"
        }
    }
    
    private var recoveryScore: Int {
        guard let data = todaysData else { return 0 }
        var score = 0.0
        if data.hrv >= 60 { score += 45 } else if data.hrv >= 40 { score += 35 } else if data.hrv >= 25 { score += 25 } else { score += 15 }
        if data.restingHeartRate >= 60 && data.restingHeartRate <= 70 { score += 35 }
        else if data.restingHeartRate < 60 { score += 30 }
        else if data.restingHeartRate <= 80 { score += 20 } else { score += 10 }
        if data.energyLevel >= 7 { score += 20 }
        else if data.energyLevel >= 5 { score += 15 }
        else { score += 10 }
        return Int(min(score, 100))
    }
    
    private var recoverySummary: String {
        if recoveryScore >= 80 { return "Body primed for high output" }
        if recoveryScore >= 60 { return "Moderate readiness – focus on form" }
        return "Recovery trending low – schedule easier efforts"
    }
    
    // MARK: - Helper Methods

    private func getMetrics(daysAgo: Int) -> HealthMetrics? {
        let targetDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: targetDate)
        return allHealthMetrics.first { Calendar.current.isDate($0.date, inSameDayAs: startOfDay) }
    }

    private func getWeekOfMetrics() -> [HealthMetrics] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allHealthMetrics.filter { $0.date >= weekAgo }
    }

    private func history(for keyPath: KeyPath<HealthMetrics, Double>, days: Int) -> [Double] {
        let values = (0..<days).compactMap { day -> Double? in
            guard let metrics = getMetrics(daysAgo: day) else { return nil }
            let value = metrics[keyPath: keyPath]
            return value > 0 ? value : nil
        }
        return Array(values.reversed())
    }

    private func history(for keyPath: KeyPath<HealthMetrics, Int16>, days: Int) -> [Double] {
        let values = (0..<days).compactMap { day -> Double? in
            guard let metrics = getMetrics(daysAgo: day) else { return nil }
            let value = Double(metrics[keyPath: keyPath])
            return value > 0 ? value : nil
        }
        return Array(values.reversed())
    }

    private func dailyMetrics(for keyPath: KeyPath<HealthMetrics, Double>, unit: String) -> [HealthMetricDetailView.DailyMetric] {
        (0..<7).compactMap { day -> HealthMetricDetailView.DailyMetric? in
            guard let metrics = getMetrics(daysAgo: day) else { return nil }
            let value = metrics[keyPath: keyPath]
            let previous = getMetrics(daysAgo: day + 1)?[keyPath: keyPath] ?? 0
            let delta: Double? = previous > 0 ? ((value - previous) / previous) * 100 : nil
            let date = Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date()
            return HealthMetricDetailView.DailyMetric(
                date: date,
                value: unit.isEmpty ? String(format: "%.1f", value) : String(format: "%.1f %@", value, unit),
                delta: delta
            )
        }.reversed()
    }

    private func dailyMetrics(for keyPath: KeyPath<HealthMetrics, Int16>, unit: String) -> [HealthMetricDetailView.DailyMetric] {
        (0..<7).compactMap { day -> HealthMetricDetailView.DailyMetric? in
            guard let metrics = getMetrics(daysAgo: day) else { return nil }
            let value = Double(metrics[keyPath: keyPath])
            let previous = Double(getMetrics(daysAgo: day + 1)?[keyPath: keyPath] ?? 0)
            let delta: Double? = previous > 0 ? ((value - previous) / previous) * 100 : nil
            let date = Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date()
            return HealthMetricDetailView.DailyMetric(
                date: date,
                value: unit.isEmpty ? String(format: "%.0f", value) : String(format: "%.0f %@", value, unit),
                delta: delta
            )
        }.reversed()
    }

    private var dailyStepsMetrics: [HealthMetricDetailView.DailyMetric] {
        (0..<7).compactMap { day -> HealthMetricDetailView.DailyMetric? in
            guard let metrics = getMetrics(daysAgo: day) else { return nil }
            let value = Double(metrics.stepCount)
            let previous = Double(getMetrics(daysAgo: day + 1)?.stepCount ?? 0)
            let delta: Double? = previous > 0 ? ((value - previous) / previous) * 100 : nil
            let date = Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date()
            return HealthMetricDetailView.DailyMetric(
                date: date,
                value: "\(Int(value)) steps",
                delta: delta
            )
        }.reversed()
    }

    // MARK: - Vitals Formatting
    private var formattedHRV: String { String(format: "%.0f", todaysData?.hrv ?? 0) }
    private var formattedVO2: String { String(format: "%.1f", todaysData?.vo2Max ?? 0) }
    private var formattedBloodOxygen: String { String(format: "%.0f", todaysData?.bloodOxygen ?? 0) }
    private var formattedRespiratoryRate: String { String(format: "%.0f", todaysData?.respiratoryRate ?? 0) }
    private var formattedStress: String { "\(todaysData?.stressLevel ?? 0)" }
    private var formattedRecovery: String { String(format: "%.0f", todaysData?.recoveryScore ?? 0) }
    private var formattedBodyFat: String { String(format: "%.1f", todaysData?.bodyFatPercentage ?? 0) }
    private var formattedHydration: String { String(format: "%.1f", todaysData?.hydrationLevel ?? 0) }
    private var hydrationStatus: String {
        guard let hydration = todaysData?.hydrationLevel, hydration > 0 else { return "No data" }
        if hydration >= 2.5 { return "Well hydrated" }
        if hydration >= 1.5 { return "Keep sipping" }
        return "Add more fluids"
    }
    private var bodyCompositionStatus: String {
        guard let bodyFat = todaysData?.bodyFatPercentage else { return "No data" }
        if bodyFat <= 15 { return "Athletic" }
        if bodyFat <= 22 { return "Optimal" }
        if bodyFat <= 28 { return "Healthy" }
        return "Consider adjustments"
    }
    private var respiratoryStatus: String {
        guard let rate = todaysData?.respiratoryRate, rate > 0 else { return "No data" }
        if rate < 12 { return "Below baseline" }
        if rate <= 20 { return "Stable" }
        return "Elevated"
    }
    private var stressStatus: String {
        guard let level = todaysData?.stressLevel else { return "No data" }
        if level <= 3 { return "Calm" }
        if level <= 6 { return "Managed" }
        return "High"
    }
    private var bloodOxygenStatus: String {
        guard let saturation = todaysData?.bloodOxygen, saturation > 0 else { return "No data" }
        if saturation >= 98 { return "Optimal" }
        if saturation >= 95 { return "Healthy" }
        if saturation >= 92 { return "Watch" }
        return "Low"
    }
    private var recoveryStatus: String {
        guard let score = todaysData?.recoveryScore else { return "No data" }
        if score >= 80 { return "Ready" }
        if score >= 60 { return "Solid" }
        return "Recovering"
    }
    private var restingHRSummary: String {
        guard let hr = todaysData?.restingHeartRate else { return "No data" }
        if hr <= 60 { return "Elite resting rate" }
        if hr <= 70 { return "Strong baseline" }
        if hr <= 80 { return "Within range" }
        return "Higher than usual"
    }
    
    private var heartRateHistory: [Double] { history(for: \HealthMetrics.restingHeartRate, days: 14) }
    private var hrvHistory: [Double] { history(for: \HealthMetrics.hrv, days: 14) }
    private var vo2History: [Double] { history(for: \HealthMetrics.vo2Max, days: 14) }
    private var bloodOxygenHistory: [Double] { history(for: \HealthMetrics.bloodOxygen, days: 14) }
    private var respiratoryHistory: [Double] { history(for: \HealthMetrics.respiratoryRate, days: 14) }
    private var stressHistory: [Double] { history(for: \HealthMetrics.stressLevel, days: 14) }
    private var recoveryHistory: [Double] { history(for: \HealthMetrics.recoveryScore, days: 14) }
    private var bodyCompositionHistory: [Double] { history(for: \HealthMetrics.bodyFatPercentage, days: 14) }
    private var hydrationHistory: [Double] { history(for: \HealthMetrics.hydrationLevel, days: 14) }

    private var heartRateTrend: Double { percentTrend(of: heartRateHistory) }
    private var hrvTrend: Double { percentTrend(of: hrvHistory) }
    private var vo2MaxTrend: Double { percentTrend(of: vo2History) }
    private var bloodOxygenTrend: Double { percentTrend(of: bloodOxygenHistory) }
    private var respiratoryTrend: Double { percentTrend(of: respiratoryHistory) }
    private var stressTrend: Double { percentTrend(of: stressHistory) }
    private var recoveryTrend: Double { percentTrend(of: recoveryHistory) }
    private var bodyCompositionTrend: Double { percentTrend(of: bodyCompositionHistory, invert: true) }
    private var hydrationTrend: Double { percentTrend(of: hydrationHistory) }
    
    private func percentTrend(of values: [Double], invert: Bool = false) -> Double {
        guard let last = values.last, let previous = values.dropLast().last, previous != 0 else { return 0 }
        let change = ((last - previous) / previous) * 100
        return invert ? -change : change
    }
    
    // MARK: - Detail Contexts
    private var heartRateContext: HealthMetricDetailView.MetricContext {
        let latest = todaysData?.restingHeartRate ?? 0
        let historyValues = history(for: \HealthMetrics.restingHeartRate, days: 14)
        return HealthMetricDetailView.MetricContext(
            title: "Resting Heart Rate",
            primaryValue: "\(latest)",
            unit: "bpm",
            description: "Resting heart rate reflects cardiovascular fitness and recovery status.",
            trends: historyValues,
            weeklyAverage: String(format: "Weekly avg • %.1f bpm", average(of: historyValues)),
            dailyValues: dailyMetrics(for: \HealthMetrics.restingHeartRate, unit: "bpm"),
            guidance: ["Stay hydrated and well rested to keep RHR in optimal ranges.", "Consider active recovery days when RHR trends high."],
            systemIcon: "heart.fill",
            tint: .red,
            annotations: annotations(for: historyValues, unit: "bpm")
        )
    }
    
    private var activityContext: HealthMetricDetailView.MetricContext {
        let value = formatNumber(todaysData?.stepCount ?? 0)
        return HealthMetricDetailView.MetricContext(
            title: "Daily Activity",
            primaryValue: value,
            unit: "steps",
            description: "Total movement for today including steps and cardiovascular effort.",
            trends: stepsHistory,
            weeklyAverage: "Avg steps • \(formatNumber(Int(average(of: stepsHistory))))",
            dailyValues: dailyStepsMetrics,
            guidance: ["Aim for consistent movement every hour.", "Mix in strength and flexibility to balance activity."],
            systemIcon: "figure.walk.motion",
            tint: .green,
            annotations: annotations(for: stepsHistory, unit: "steps")
        )
    }
    
    private var sleepContext: HealthMetricDetailView.MetricContext {
        let value = String(format: "%.1f", todaysData?.sleepHours ?? 0)
        return HealthMetricDetailView.MetricContext(
                        title: "Sleep",
            primaryValue: value,
            unit: "hours",
            description: "Duration and quality of last night’s sleep cycle.",
            trends: sleepHistory,
            weeklyAverage: String(format: "Avg duration • %.1f h", average(of: sleepHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.sleepHours, unit: "h"),
            guidance: ["Create a consistent sleep schedule", "Try winding down 30 minutes before bed"],
            systemIcon: "moon.zzz.fill",
            tint: .indigo,
            annotations: annotations(for: sleepHistory, unit: "h")
        )
    }
    
    private var recoveryContext: HealthMetricDetailView.MetricContext {
        let value = formattedRecovery
        return HealthMetricDetailView.MetricContext(
                    title: "Recovery",
            primaryValue: value,
            unit: "/100",
            description: "Recovery score blends HRV, resting HR, and subjective energy.",
            trends: recoveryHistory,
            weeklyAverage: String(format: "Avg recovery • %.0f", average(of: recoveryHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.recoveryScore, unit: ""),
            guidance: ["Low recovery? Focus on sleep and easy sessions", "Add mobility or meditation on high stress days"],
            systemIcon: "bolt.heart.fill",
            tint: .purple,
            annotations: annotations(for: recoveryHistory, unit: "")
        )
    }

    private var hrvContext: HealthMetricDetailView.MetricContext {
        let value = formattedHRV
        return HealthMetricDetailView.MetricContext(
            title: "Heart Rate Variability",
            primaryValue: value,
            unit: "ms",
            description: "HRV reflects nervous system balance and recovery readiness.",
            trends: hrvHistory,
            weeklyAverage: String(format: "Weekly avg • %.0f ms", average(of: hrvHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.hrv, unit: "ms"),
            guidance: ["Consistent sleep and stress management improve HRV", "Easy aerobic work raises HRV over time"],
            systemIcon: "waveform.path.ecg",
            tint: .teal,
            annotations: annotations(for: hrvHistory, unit: "ms")
        )
    }
    
    private var vo2Context: HealthMetricDetailView.MetricContext {
        let value = formattedVO2
        return HealthMetricDetailView.MetricContext(
                        title: "VO₂ Max",
            primaryValue: value,
                    unit: "ml/kg/min",
            description: "VO₂ Max measures aerobic capacity and overall fitness.",
            trends: vo2History,
            weeklyAverage: String(format: "Rolling avg • %.1f", average(of: vo2History)),
            dailyValues: dailyMetrics(for: \HealthMetrics.vo2Max, unit: "ml/kg/min"),
            guidance: ["Interval training improves VO₂ max", "Recover fully between intense cardio days"],
            systemIcon: "lungs.fill",
            tint: .mint,
            annotations: annotations(for: vo2History, unit: "ml/kg/min")
        )
    }
    
    private var bloodOxygenContext: HealthMetricDetailView.MetricContext {
        let value = formattedBloodOxygen
        return HealthMetricDetailView.MetricContext(
            title: "Blood Oxygen",
            primaryValue: value,
                        unit: "%",
            description: "Blood oxygen saturation indicates how efficiently your body distributes oxygen.",
            trends: bloodOxygenHistory,
            weeklyAverage: String(format: "Avg saturation • %.1f%%", average(of: bloodOxygenHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.bloodOxygen, unit: "%"),
            guidance: ["Maintain nasal breathing during easy efforts", "If saturation dips persistently, consult a clinician"],
            systemIcon: "drop.fill",
            tint: .blue,
            annotations: annotations(for: bloodOxygenHistory, unit: "%")
        )
    }
    
    private var respiratoryContext: HealthMetricDetailView.MetricContext {
        let value = formattedRespiratoryRate
        return HealthMetricDetailView.MetricContext(
            title: "Respiratory Rate",
            primaryValue: value,
            unit: "rpm",
            description: "Breaths per minute captured during sleep and at rest.",
            trends: respiratoryHistory,
            weeklyAverage: String(format: "Avg rate • %.1f", average(of: respiratoryHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.respiratoryRate, unit: "rpm"),
            guidance: ["Practice diaphragm breathing to lower rate", "Extra rest when rate trends high"],
            systemIcon: "wind",
            tint: .cyan,
            annotations: annotations(for: respiratoryHistory, unit: "rpm")
        )
    }
    
    // Live Heart Rate context (day chart)
    private var liveHeartRateContext: HealthMetricDetailView.MetricContext {
        let latest = liveHeartRateString
        let values = heartRateDayHistory
        return HealthMetricDetailView.MetricContext(
            title: "Heart Rate Today",
            primaryValue: latest,
            unit: "bpm",
            description: "Heart rate trend across the day.",
            trends: values,
            weeklyAverage: averageHRLabel,
            dailyValues: heartRateDailyAverages,
            guidance: ["Aerobic zones build endurance", "Include recovery between intervals"],
            systemIcon: "bolt.heart.fill",
            tint: .pink,
            annotations: []
        )
    }
    
    private var bodyCompositionContext: HealthMetricDetailView.MetricContext {
        let value = formattedBodyFat
        return HealthMetricDetailView.MetricContext(
            title: "Body Composition",
            primaryValue: value,
            unit: "%",
            description: "Tracking body fat percentage offers insight into long-term progress.",
            trends: bodyCompositionHistory,
            weeklyAverage: String(format: "Avg body fat • %.1f%%", average(of: bodyCompositionHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.bodyFatPercentage, unit: "%"),
            guidance: ["Consistency with nutrition drives sustainable change", "Lean mass improves metabolic health"],
            systemIcon: "figure.arms.open",
            tint: .blue,
            annotations: annotations(for: bodyCompositionHistory, unit: "%")
        )
    }
    
    private var hydrationContext: HealthMetricDetailView.MetricContext {
        let value = formattedHydration
        return HealthMetricDetailView.MetricContext(
            title: "Hydration",
            primaryValue: value,
            unit: "L",
            description: "Daily fluid intake helps regulate temperature, blood volume, and recovery.",
            trends: hydrationHistory,
            weeklyAverage: String(format: "Avg intake • %.1f L", average(of: hydrationHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.hydrationLevel, unit: "L"),
            guidance: ["Sip water steadily throughout the day", "Add electrolytes after intense workouts"],
            systemIcon: "drop.triangle.fill",
            tint: .teal,
            annotations: annotations(for: hydrationHistory, unit: "L")
        )
    }
    
    private func average(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func annotations(for values: [Double], unit: String) -> [HealthMetricDetailView.Annotation] {
        guard let latest = values.last else { return [] }
        var result: [HealthMetricDetailView.Annotation] = []
        if let maxValue = values.max(), maxValue == latest {
            result.append(HealthMetricDetailView.Annotation(title: "New High", detail: "Best value in the last 2 weeks", icon: "crown.fill", color: .green))
        }
        if let minValue = values.min(), minValue == latest {
            result.append(HealthMetricDetailView.Annotation(title: "New Low", detail: "Lowest value recently", icon: "arrow.down.to.line.compact", color: .orange))
        }
        if result.isEmpty {
            result.append(HealthMetricDetailView.Annotation(title: "Latest", detail: String(format: "%.1f %@ today", latest, unit), icon: "clock", color: .secondary))
        }
        return result
    }
    
    // Lifestyle replacements data
    private var activeMinutesHistory: [Double] {
        (0..<14).compactMap { day -> Double? in
            guard let metrics = getMetrics(daysAgo: day) else { return nil }
            return Double(metrics.activeMinutes)
        }.reversed()
    }
    private var activeMinutesTrend: Double { percentTrend(of: activeMinutesHistory) }
    private var activeMinutesContext: HealthMetricDetailView.MetricContext {
        let value = "\(todaysData?.activeMinutes ?? 0)"
        return HealthMetricDetailView.MetricContext(
            title: "Exercise Minutes",
            primaryValue: value,
            unit: "min",
            description: "Daily Apple Exercise Time contributing to Move/Workout.",
            trends: activeMinutesHistory,
            weeklyAverage: String(format: "Weekly avg • %.0f min", average(of: activeMinutesHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.activeMinutes, unit: "min"),
            guidance: ["Aim for 20–30 min of zone 2 most days", "Short walking breaks add up"],
            systemIcon: "figure.walk.motion",
            tint: .green,
            annotations: annotations(for: activeMinutesHistory, unit: "min")
        )
    }
    
    private var totalCaloriesHistory: [Double] {
        (0..<14).compactMap { day -> Double? in
            guard let metrics = getMetrics(daysAgo: day) else { return nil }
            return metrics.totalCalories
        }.reversed()
    }
    private var totalCaloriesTrend: Double { percentTrend(of: totalCaloriesHistory) }
    private var totalCaloriesContext: HealthMetricDetailView.MetricContext {
        let value = "\(Int(todaysData?.totalCalories ?? 0))"
        return HealthMetricDetailView.MetricContext(
            title: "Total Calories",
            primaryValue: value,
            unit: "kcal",
            description: "Total energy expenditure (basal + active).",
            trends: totalCaloriesHistory,
            weeklyAverage: String(format: "Weekly avg • %.0f kcal", average(of: totalCaloriesHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.totalCalories, unit: "kcal"),
            guidance: ["Match intake to goals: deficit for fat loss, surplus for gain"],
            systemIcon: "flame.fill",
            tint: .orange,
            annotations: annotations(for: totalCaloriesHistory, unit: "kcal")
        )
    }
    
    private var sleepHistory: [Double] { history(for: \HealthMetrics.sleepHours, days: 14) }
    private var stepsHistory: [Double] { stepsHistoryArray }
    private var stepsHistoryArray: [Double] {
        let values = (0..<14).compactMap { day -> Double? in
            guard let metrics = getMetrics(daysAgo: day) else { return nil }
            return Double(metrics.stepCount)
        }
        return Array(values.reversed())
    }
    
    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }
    
    private var healthStatusText: String {
        guard let data = todaysData else { return "Syncing your health data..." }
        let stepsProgress = Double(data.stepCount) / 10000.0
        let caloriesProgress = data.activeCalories / 500.0
        let sleepProgress = data.sleepHours / 8.0
        let overallProgress = (stepsProgress + caloriesProgress + sleepProgress) / 3.0
        switch overallProgress {
        case 0.8...1.0: return "You're crushing your health goals today!"
        case 0.6...0.8: return "Great progress on your health journey"
        case 0.4...0.6: return "You're making steady progress"
        case 0.2...0.4: return "Let's get moving and improve your day"
        default: return "Every step counts - let's start small"
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerSection
                        heroMetricsSection
                        vitalsSection
                        recoverySection
                        lifestyleSection
                        activitySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }
            }
            .navigationDestination(item: $selectedMetricKind) { kind in
                if let context = selectedMetricContext {
                    HealthMetricDetailView(kind: kind, context: context)
                }
            }
            .sheet(isPresented: $showSleepDetail) {
                SleepDetailView(
                    sleepData: todaysData,
                    sleepHistory: Array(allHealthMetrics.prefix(7))
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await refreshHealthData() }
            .task { await setupDashboard() }
            .onDisappear { stopAutoRefresh() }
            .onChange(of: scenePhase) { handleScenePhaseChange($0) }
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.primary.opacity(0.95), .primary.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(dateString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                refreshButton
            }
            
            if !healthKitService.hasValidAuthorization() {
                healthKitBanner
            }
        }
    }
    
    private var refreshButton: some View {
        Button(action: { Task { await refreshHealthData() } }) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                if isLoading || healthKitService.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
            } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading || healthKitService.isLoading)
    }
    
    private var healthKitBanner: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 20)
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.18))
                    .overlay(
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.red)
                    )
                    .frame(width: 52, height: 52)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect HealthKit")
                        .font(.headline)
                    Text("Enable permissions to unlock personalized insights and historical trends.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Button("Connect") {
                    Task {
                        await healthKitService.requestAuthorization()
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await healthKitService.refreshAuthorizationStatus()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(20)
        }
    }
    
    // MARK: - Hero Metrics
    private var heroMetricsSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                heroCard(title: "Health Score", value: "\(healthScore)", subtitle: healthScoreSummary, gradient: Gradient(colors: [Color.green.opacity(0.9), Color.green.opacity(0.6)]), action: { presentDetail(kind: .heartRate, context: heartRateContext) })
                VStack(spacing: 8) {
                    metricSummaryRow(title: "Activity", icon: "figure.walk.motion", color: .green, score: activityScore, description: activitySummary)
                    metricSummaryRow(title: "Sleep", icon: "moon.zzz.fill", color: .indigo, score: sleepScore, description: sleepSummary)
                    metricSummaryRow(title: "Recovery", icon: "waveform.path.ecg", color: .teal, score: recoveryScore, description: recoverySummary)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 200)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Today at a Glance")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 100), spacing: 12),
                    GridItem(.flexible(minimum: 100), spacing: 12),
                    GridItem(.flexible(minimum: 100), spacing: 12)
                ], spacing: 12) {
                    compactMetricTile(title: "Steps", value: formatNumber(todaysData?.stepCount ?? 0), icon: "shoeprints.fill", color: .green, trend: stepsTrend)
                    compactMetricTile(title: "Active", value: "\(Int(todaysData?.activeCalories ?? 0)) kcal", icon: "flame.fill", color: .orange, trend: caloriesTrend)
                    compactMetricTile(title: "Distance", value: String(format: "%.1f km", todaysData?.totalDistance ?? 0.0), icon: "map.fill", color: .blue, trend: distanceTrend)
                }
            }
        }
    }
    
    private func heroCard(title: String, value: String, subtitle: String, gradient: Gradient, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 8)
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                .font(.headline)
                        .foregroundColor(.white.opacity(0.92))
                    Text(value)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                            .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
        }
        .buttonStyle(.plain)
    }
    
    private func metricSummaryRow(title: String, icon: String, color: Color, score: Int, description: String) -> some View {
        Button {
            switch title {
            case "Activity": presentDetail(kind: .heartRate, context: activityContext)
            case "Sleep": showSleepDetail = true
            case "Recovery": presentDetail(kind: .hrv, context: recoveryContext)
            default: break
            }
        } label: {
            ZStack {
                GlassCardBackground(cornerRadius: 16)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.18))
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(color)
                        )
                        .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                Text(description)
                            .font(.caption2)
                    .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    scoreBadge(score: score, color: color)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func scoreBadge(score: Int, color: Color) -> some View {
        Text("\(score)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
                    
    private func compactMetricTile(title: String, value: String, icon: String, color: Color, trend: Double) -> some View {
        ZStack {
            GlassCardBackground(cornerRadius: 16)
        VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.18))
                        .overlay(
                Image(systemName: icon)
                                .font(.system(size: 13, weight: .medium))
                    .foregroundColor(color)
                        )
                        .frame(width: 28, height: 28)
                Spacer()
                    trendChip(trend: trend)
                        .layoutPriority(1)
                }
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .frame(minHeight: 88)
    }
    
    private func trendChip(trend: Double) -> some View {
        guard trend != 0 else { return AnyView(EmptyView()) }
        let direction: String = trend > 0 ? "arrow.up.right" : "arrow.down.right"
        let color: Color = trend > 0 ? .green : .red
        return AnyView(
            HStack(spacing: 4) {
                Image(systemName: direction)
                Text(String(format: "%+.1f%%", trend))
                    .monospacedDigit()
            }
            .font(.caption2)
                    .foregroundColor(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        )
    }
    
    // MARK: - Vitals Section
    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Vitals", subtitle: "Core health signals from today")
            
            LazyVGrid(columns: columns, spacing: 16) {
                metricTile(
                    kind: .heartRate,
                    title: "Resting HR",
                    subtitle: heartRateStatus,
                    value: "\(todaysData?.restingHeartRate ?? 0)",
                    unit: "bpm",
                    icon: "heart.fill",
                    tint: .red,
                    data: heartRateHistory,
                    trend: heartRateTrend,
                    context: heartRateContext
                )
                metricTile(
                    kind: .hrv,
                    title: "HRV",
                    subtitle: hrvStatus,
                    value: formattedHRV,
                    unit: "ms",
                    icon: "waveform.path.ecg",
                    tint: .teal,
                    data: hrvHistory,
                    trend: hrvTrend,
                    context: hrvContext
                )
                metricTile(
                    kind: .vo2Max,
                    title: "VO₂ Max",
                    subtitle: vo2MaxStatus,
                    value: formattedVO2,
                    unit: "ml/kg/min",
                    icon: "lungs.fill",
                    tint: .mint,
                    data: vo2History,
                    trend: vo2MaxTrend,
                    context: vo2Context
                )
                metricTile(
                    kind: .bloodOxygen,
                    title: "Blood O₂",
                    subtitle: bloodOxygenStatus,
                    value: formattedBloodOxygen,
                    unit: "%",
                    icon: "drop.fill",
                    tint: .blue,
                    data: bloodOxygenHistory,
                    trend: bloodOxygenTrend,
                    context: bloodOxygenContext
                )
                metricTile(
                    kind: .respiratoryRate,
                    title: "Respiratory",
                    subtitle: respiratoryStatus,
                    value: formattedRespiratoryRate,
                    unit: "rpm",
                    icon: "wind",
                    tint: .cyan,
                    data: respiratoryHistory,
                    trend: respiratoryTrend,
                    context: respiratoryContext
                )
                metricTile(
                    kind: .heartRate,
                    title: "Live HR",
                    subtitle: "Now",
                    value: liveHeartRateString,
                    unit: "bpm",
                    icon: "bolt.heart.fill",
                    tint: .pink,
                    data: heartRateDayHistory,
                    trend: heartRateTrend,
                    context: liveHeartRateContext
                )
            }
        }
    }
    
    private func sectionHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                .fontWeight(.semibold)
                Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            Button("See All") {
                // future expansion for full metrics list
            }
            .font(.footnote)
            .foregroundColor(.accentColor)
        }
    }
    
    private func metricTile(
        kind: HealthMetricDetailView.MetricKind,
        title: String,
        subtitle: String,
        value: String,
        unit: String,
        icon: String,
        tint: Color,
        data: [Double],
        trend: Double,
        context: HealthMetricDetailView.MetricContext
    ) -> some View {
        Button {
            presentDetail(kind: kind, context: context)
        } label: {
            MetricTile(
                title: title,
                subtitle: subtitle,
                value: value,
                unit: unit,
                glyph: icon,
                tint: tint,
                sparklineData: data,
                trend: MetricTile.Trend(direction: trend > 0 ? .up : (trend < 0 ? .down : .flat), percentChange: trend, timeframe: "vs. Yesterday")
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Recovery Section
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Recovery", subtitle: "How ready are you to perform?")
            
            LazyVGrid(columns: columns, spacing: 16) {
                metricTile(
                    kind: .hrv,
                    title: "Recovery Score",
                    subtitle: recoveryStatus,
                    value: formattedRecovery,
                    unit: "/100",
                    icon: "bolt.heart.fill",
                    tint: .purple,
                    data: recoveryHistory,
                    trend: recoveryTrend,
                    context: recoveryContext
                )
                metricTile(
                    kind: .heartRate,
                    title: "Resting HR Trend",
                    subtitle: restingHRSummary,
                    value: "\(todaysData?.restingHeartRate ?? 0)",
                    unit: "bpm",
                    icon: "chart.xyaxis.line",
                    tint: .pink,
                    data: heartRateHistory,
                    trend: heartRateTrend,
                    context: heartRateContext
                )
            }
        }
    }
    
    // MARK: - Lifestyle Section
    private var lifestyleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Lifestyle", subtitle: "Daily habits with measurable impact")
            
            metricTile(
                kind: .vo2Max,
                title: "Total Calories",
                subtitle: "Basal + Active today",
                value: "\(Int(todaysData?.totalCalories ?? 0))",
                unit: "kcal",
                icon: "flame.fill",
                tint: .orange,
                data: totalCaloriesHistory,
                trend: totalCaloriesTrend,
                context: totalCaloriesContext
            )
        }
    }
    
    // MARK: - Activity Section
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Recent Activity", subtitle: "Your latest workouts")
            ZStack {
                GlassCardBackground(cornerRadius: 20)
                if workouts.isEmpty {
            VStack(spacing: 12) {
                        Image(systemName: "figure.walk.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Workouts Logged")
                            .font(.headline)
                        Text("Start a workout on Apple Watch to see it here.")
                .font(.subheadline)
                    .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(workouts.prefix(3)) { workout in
                            workoutRow(workout)
                            if workout != workouts.prefix(3).last {
                                Divider().background(Color.primary.opacity(0.05))
                            }
                        }
                        Button(action: { /* navigate to all workouts */ }) {
            HStack {
                                Text("View All Workouts")
                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.footnote)
                            .foregroundColor(.accentColor)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
    
    private func workoutRow(_ workout: WorkoutLog) -> some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color(for: workout.workoutType).opacity(0.18))
                .overlay(
                    Image(systemName: icon(for: workout.workoutType))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(color(for: workout.workoutType))
                )
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutType.capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                Text(relativeFormatter.localizedString(for: workout.timestamp, relativeTo: Date()))
                    .font(.caption)
                        .foregroundColor(.secondary)
                }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.2f km", workout.distance))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(Int(workout.calories)) kcal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
    }
    
    private func presentDetail(kind: HealthMetricDetailView.MetricKind, context: HealthMetricDetailView.MetricContext) {
        selectedMetricKind = kind
        selectedMetricContext = context
    }
    
    // MARK: - Background
    private struct DashboardBackground: View {
        @Environment(\.colorScheme) private var colorScheme
    var body: some View {
            LinearGradient(
                colors: colorScheme == .dark ? [Color.black, Color(white: 0.12)] : [Color(white: 0.97), Color(white: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private func icon(for workoutType: String) -> String {
        switch workoutType {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "strength": return "dumbbell.fill"
        default: return "figure.mixed.cardio"
        }
    }
    
    private func color(for workoutType: String) -> Color {
        switch workoutType {
        case "run": return .orange
        case "walk": return .green
        case "bike": return .blue
        case "strength": return .purple
        default: return .gray
        }
    }
    
    // MARK: - Computed Properties (Improved Accuracy)
    
    // MARK: - Trend Calculations
    
    private func getYesterdaysMetrics() -> HealthMetrics? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let startOfYesterday = Calendar.current.startOfDay(for: yesterday)
        
        return allHealthMetrics.first { metrics in
            Calendar.current.isDate(metrics.date, inSameDayAs: startOfYesterday)
        }
    }
    
    private var stepsTrend: Double {
        guard let today = todaysData, let yesterday = getYesterdaysMetrics(),
              yesterday.stepCount > 0 else { return 0.0 }
        return ((Double(today.stepCount) - Double(yesterday.stepCount)) / Double(yesterday.stepCount)) * 100
    }
    
    private var caloriesTrend: Double {
        guard let today = todaysData, let yesterday = getYesterdaysMetrics(),
              yesterday.activeCalories > 0 else { return 0.0 }
        return ((today.activeCalories - yesterday.activeCalories) / yesterday.activeCalories) * 100
    }
    
    private var distanceTrend: Double {
        guard let today = todaysData, let yesterday = getYesterdaysMetrics(),
              yesterday.totalDistance > 0 else { return 0.0 }
        return ((today.totalDistance - yesterday.totalDistance) / yesterday.totalDistance) * 100
    }
    
    private var sleepTrend: Double {
        guard let today = todaysData, let yesterday = getYesterdaysMetrics(),
              yesterday.sleepHours > 0 else { return 0.0 }
        return ((today.sleepHours - yesterday.sleepHours) / yesterday.sleepHours) * 100
    }
    
    // MARK: - Status Indicators
    
    private var heartRateStatus: String {
        guard let hr = todaysData?.restingHeartRate, hr > 0 else { return "No data" }
        switch hr {
        case 0...60: return "Athletic"
        case 61...70: return "Excellent"
        case 71...80: return "Good"
        case 81...90: return "Average"
        default: return "High"
        }
    }
    
    private var sleepStatus: String {
        guard let sleep = todaysData?.sleepHours, sleep > 0 else { return "No data" }
        switch sleep {
        case 0..<6: return "Poor"
        case 6..<7: return "Fair"
        case 7...9: return "Excellent"
        default: return "Excessive"
        }
    }
    
    private var hrvStatus: String {
        guard let hrv = todaysData?.hrv, hrv > 0 else { return "No data" }
        switch hrv {
        case 0..<20: return "Low"
        case 20..<40: return "Average"
        case 40..<60: return "Good"
        default: return "Excellent"
        }
    }

    // Live heart rate string (latest reading or resting fallback)
    private var liveHeartRateString: String {
        if let latest = latestHeartRateReading { return "\(latest)" }
        return "\(todaysData?.restingHeartRate ?? 0)"
    }

    // Pull latest heart rate reading from Core Data
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HeartRateReading.timestamp, ascending: false)],
        animation: .default)
    private var heartRateReadings: FetchedResults<HeartRateReading>

    private var latestHeartRateReading: Int? {
        guard let first = heartRateReadings.first else { 
            print("⚠️ No heart rate readings found in Core Data. Total readings: \(heartRateReadings.count)")
            return nil 
        }
        let hr = Int(first.heartRate)
        print("💓 Latest heart rate: \(hr) bpm at \(first.timestamp)")
        return hr
    }

    // Build a normalized day-long series from readings for charting
    private var heartRateDayHistory: [Double] {
        let readings = Array(heartRateReadings.prefix(200)).reversed()
        let values = readings.map { Double($0.heartRate) }
        return values.isEmpty ? [Double(todaysData?.restingHeartRate ?? 0)] : Array(values)
    }

    // Daily averages for heart rate (limit to recent 7 days)
    private var heartRateDailyAverages: [HealthMetricDetailView.DailyMetric] {
        let calendar = Calendar.current
        let readings = Array(heartRateReadings.prefix(1000))
        let grouped = Dictionary(grouping: readings) { (reading: HeartRateReading) -> Date in
            calendar.startOfDay(for: reading.timestamp)
        }

        // Sort days descending and take up to 7 most recent
        let sortedDays = grouped.keys.sorted(by: >).prefix(7)

        var result: [HealthMetricDetailView.DailyMetric] = []
        for day in sortedDays {
            let dayReadings = grouped[day] ?? []
            let total = dayReadings.reduce(0.0) { $0 + Double($1.heartRate) }
            let avg = dayReadings.isEmpty ? 0.0 : total / Double(dayReadings.count)
            result.append(
                HealthMetricDetailView.DailyMetric(
                    date: day,
                    value: String(format: "%.0f", avg),
                    delta: nil
                )
            )
        }
        return result
    }

    private var averageHRLabel: String {
        let values = heartRateDailyAverages.map { Double($0.value) ?? 0 }
        guard !values.isEmpty else { return "" }
        let avg = values.reduce(0, +) / Double(values.count)
        return String(format: "Avg • %.0f bpm", avg)
    }
    
    private var vo2MaxStatus: String {
        guard let vo2 = todaysData?.vo2Max, vo2 > 0 else { return "No data" }
        switch vo2 {
        case 0..<35: return "Poor"
        case 35..<42: return "Average"
        case 42..<50: return "Good"
        case 50..<60: return "Excellent"
        default: return "Superior"
        }
    }
    
    // MARK: - Weekly Stats
    
    private var weeklyAvgSteps: Int {
        let weekMetrics = getWeekOfMetrics()
        guard !weekMetrics.isEmpty else { return 0 }
        return weekMetrics.reduce(0) { $0 + Int($1.stepCount) } / weekMetrics.count
    }
    
    private var weeklyAvgCalories: Double {
        let weekMetrics = getWeekOfMetrics()
        guard !weekMetrics.isEmpty else { return 0 }
        return weekMetrics.reduce(0.0) { $0 + $1.activeCalories } / Double(weekMetrics.count)
    }
    
    private var weeklyAvgSleep: Double {
        let weekMetrics = getWeekOfMetrics()
        guard !weekMetrics.isEmpty else { return 0 }
        return weekMetrics.reduce(0.0) { $0 + $1.sleepHours } / Double(weekMetrics.count)
    }
    
    private var weeklyStepsChange: String {
        let thisWeek = weeklyAvgSteps
        guard thisWeek > 0 else { return "No data" }
        
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let lastWeekMetrics = allHealthMetrics.filter { $0.date >= twoWeeksAgo && $0.date < oneWeekAgo }
        
        guard !lastWeekMetrics.isEmpty else { return "First week" }
        let lastWeekAvg = lastWeekMetrics.reduce(0) { $0 + Int($1.stepCount) } / lastWeekMetrics.count
        guard lastWeekAvg > 0 else { return "Improving" }
        
        let change = ((Double(thisWeek) - Double(lastWeekAvg)) / Double(lastWeekAvg)) * 100
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(Int(change))% vs last week"
    }
    
    private var weeklyCaloriesChange: String {
        let thisWeek = weeklyAvgCalories
        guard thisWeek > 0 else { return "No data" }
        
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let lastWeekMetrics = allHealthMetrics.filter { $0.date >= twoWeeksAgo && $0.date < oneWeekAgo }
        
        guard !lastWeekMetrics.isEmpty else { return "First week" }
        let lastWeekAvg = lastWeekMetrics.reduce(0.0) { $0 + $1.activeCalories } / Double(lastWeekMetrics.count)
        guard lastWeekAvg > 0 else { return "Improving" }
        
        let change = ((thisWeek - lastWeekAvg) / lastWeekAvg) * 100
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(Int(change))% vs last week"
    }
    
    private var weeklySleepChange: String {
        let thisWeek = weeklyAvgSleep
        guard thisWeek > 0 else { return "No data" }
        
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let lastWeekMetrics = allHealthMetrics.filter { $0.date >= twoWeeksAgo && $0.date < oneWeekAgo }
        
        guard !lastWeekMetrics.isEmpty else { return "First week" }
        let lastWeekAvg = lastWeekMetrics.reduce(0.0) { $0 + $1.sleepHours } / Double(lastWeekMetrics.count)
        guard lastWeekAvg > 0 else { return "Improving" }
        
        let change = ((thisWeek - lastWeekAvg) / lastWeekAvg) * 100
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(Int(change))% vs last week"
    }
    
    // MARK: - Helper Methods
    
    private func formatSleepTime(_ totalHours: Double) -> String {
        guard totalHours > 0 else { return "0h" }
        let hours = Int(totalHours)
        let minutes = Int((totalHours - Double(hours)) * 60)
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }
    
    private func formatNumber<T: BinaryInteger>(_ number: T) -> String {
        let intValue = Int(number)
        if intValue >= 1000 {
            let thousands = Double(intValue) / 1000.0
            return String(format: "%.1fK", thousands)
        }
        return "\(intValue)"
    }
    
    // MARK: - Lifecycle Methods
    
    private func setupDashboard() async {
        await healthKitService.refreshAuthorizationStatus()
        await refreshHealthData()
        startAutoRefresh()
    }
    
    private func refreshHealthData() async {
        isLoading = true
        await healthKitService.forceRefreshTodaysMetrics()
        await healthKitService.syncRecentWorkouts()
        await healthKitService.updateRecoveryScores()
        lastRefreshTime = Date()
        isLoading = false
    }
    
    private func startAutoRefresh() {
        // Refresh every 60 seconds for more up-to-date data
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task {
                await refreshHealthData()
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task {
                await healthKitService.refreshAuthorizationStatus()
                // Always refresh when coming back to active (more aggressive for live updates)
                if Date().timeIntervalSince(lastRefreshTime) > 30 {
                    await refreshHealthData()
                }
            }
            startAutoRefresh() // Restart timer when active
        case .background:
            stopAutoRefresh()
        default:
            break
        }
    }
}

#Preview {
    HealthDashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 

