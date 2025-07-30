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
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)],
        animation: .default)
    private var workouts: FetchedResults<WorkoutLog>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        animation: .default)
    private var allHealthMetrics: FetchedResults<HealthMetrics>
    
    @State private var isLoading = false
    @State private var weeklyHealthSummary: WeeklyHealthSummary?
    @State private var selectedTab = 0
    @State private var refreshTimer: Timer?
    @State private var lastRefreshTime = Date()
    @State private var showingWeeklyInsights = false
    @State private var showingQuickActions = false
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Refresh Methods
    
    private func refreshTodaysData() async {
        isLoading = true
        await healthKitService.forceRefreshTodaysMetrics()
        lastRefreshTime = Date()
        isLoading = false
    }
    
    var todaysData: HealthMetrics? {
        todaysMetrics.first
    }
    
    var recentWorkouts: [WorkoutLog] {
        Array(workouts.prefix(3))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Enhanced header with health score
                    enhancedHeaderSection
                    
                    // Health Score Summary Card
                    healthScoreCard
                    
                    // Today's overview with progress rings and trends
                    enhancedTodaysOverviewCard
                    
                    // Health metrics grid with trends
                    enhancedHealthMetricsGrid
                    
                    // Enhanced activity section with achievements
                    enhancedActivitySection
                    
                    // Improved weekly insights
                    enhancedWeeklyInsightsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarHidden(true)
            .refreshable {
                await refreshHealthData()
            }
            .onAppear {
                loadWeeklyHealthSummary()
                startAutoRefresh()
                Task {
                    await healthKitService.refreshAuthorizationStatus()
                    await refreshHealthData()
                }
            }
            .onDisappear {
                stopAutoRefresh()
            }
            .onChange(of: scenePhase) { newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
    }
    
    // MARK: - Enhanced Header Section
    private var enhancedHeaderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Quick refresh and settings
                HStack(spacing: 8) {
                    Button(action: {
                        Task {
                            await refreshTodaysData()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .disabled(isLoading)
                    
                    if healthKitService.isLoading || isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
            }
            
            // Enhanced Authorization Status
            if !healthKitService.hasValidAuthorization() {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect HealthKit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Enable for personalized insights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Connect") {
                        Task {
                            await healthKitService.requestAuthorization()
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await healthKitService.refreshAuthorizationStatus()
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red)
                .cornerRadius(8)
                }
                .padding(16)
                .background(Color.red.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Health Score Card
    private var healthScoreCard: some View {
        HStack(spacing: 20) {
            // Health Score Circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: CGFloat(healthScore) / 100.0)
                    .stroke(healthScoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(healthScore)")
                        .font(.title2)
                        .fontWeight(.bold)
                .foregroundColor(.primary)
            
                    Text("Score")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Health Summary")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                VStack(spacing: 6) {
                    HealthScoreFactorRow(
                        title: "Activity",
                        score: activityScore,
                        icon: "figure.walk",
                        color: .green
                    )
                    
                    HealthScoreFactorRow(
                        title: "Sleep",
                        score: sleepScore,
                        icon: "moon.fill",
                        color: .indigo
                    )
                    
                    HealthScoreFactorRow(
                        title: "Heart Health",
                        score: heartHealthScore,
                        icon: "heart.fill",
                        color: .red
                    )
                }
            }
            
            Spacer()
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Enhanced Today's Overview
    private var enhancedTodaysOverviewCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Today's Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Progress rings with better information
            HStack(spacing: 24) {
                NavigationLink(destination: StepsDetailView(healthMetrics: todaysData)) {
                    EnhancedProgressRing(
                        title: "Steps",
                        value: "\(todaysData?.stepCount ?? 0)",
                        goal: "10000",
                        unit: "",
                        color: .green,
                        progress: Double(todaysData?.stepCount ?? 0) / 10000.0,
                        trend: stepsTrend
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: CaloriesDetailView(healthMetrics: todaysData)) {
                    EnhancedProgressRing(
                        title: "Active Cal",
                        value: "\(Int(todaysData?.activeCalories ?? 0))",
                        goal: "500",
                        unit: "",
                        color: .orange,
                        progress: (todaysData?.activeCalories ?? 0) / 500.0,
                        trend: caloriesTrend
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: DistanceDetailView(healthMetrics: todaysData)) {
                    EnhancedProgressRing(
                        title: "Distance",
                        value: String(format: "%.1f", todaysData?.totalDistance ?? 0.0),
                        goal: "5.0",
                        unit: "km",
                        color: .blue,
                        progress: (todaysData?.totalDistance ?? 0.0) / 5.0,
                        trend: distanceTrend
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    

    
    // MARK: - Enhanced Health Metrics Grid
    private var enhancedHealthMetricsGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Health Vitals")
                .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View All") {
                    // Navigate to comprehensive health view
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                NavigationLink(destination: HeartRateDetailView(healthMetrics: todaysData)) {
                    EnhancedVitalCard(
                    title: "Heart Rate",
                    value: "\(todaysData?.restingHeartRate ?? 0)",
                    unit: "bpm",
                    icon: "heart.fill",
                    color: .red,
                        status: heartRateStatus,
                        trend: heartRateTrend,
                        subtitle: "Resting HR"
                )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: SleepDetailView(healthMetrics: todaysData)) {
                    EnhancedVitalCard(
                        title: "Sleep",
                        value: formatSleepTime(todaysData?.sleepHours ?? 0.0),
                        unit: "",
                        icon: "moon.fill",
                        color: .indigo,
                        status: sleepStatus,
                        trend: sleepTrend,
                        subtitle: "Last night"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: HRVDetailView(healthMetrics: todaysData)) {
                    EnhancedVitalCard(
                    title: "HRV",
                        value: String(format: "%.0f", todaysData?.hrv ?? 0.0),
                    unit: "ms",
                    icon: "waveform.path.ecg",
                        color: .teal,
                        status: hrvStatus,
                        trend: hrvTrend,
                        subtitle: "Recovery"
                )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: VO2MaxDetailView(healthMetrics: todaysData)) {
                    EnhancedVitalCard(
                        title: "VO₂ Max",
                    value: String(format: "%.1f", todaysData?.vo2Max ?? 0.0),
                    unit: "ml/kg/min",
                    icon: "lungs.fill",
                        color: .mint,
                        status: vo2MaxStatus,
                        trend: vo2MaxTrend,
                        subtitle: "Fitness"
                )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: BloodOxygenDetailView(healthMetrics: todaysData)) {
                    EnhancedVitalCard(
                        title: "Blood O₂",
                        value: String(format: "%.0f", todaysData?.bloodOxygen ?? 0.0),
                        unit: "%",
                        icon: "drop.circle.fill",
                        color: .blue,
                        status: bloodOxygenStatus,
                        trend: bloodOxygenTrend,
                        subtitle: "Saturation"
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                NavigationLink(destination: RespiratoryRateDetailView(healthMetrics: todaysData)) {
                    EnhancedVitalCard(
                        title: "Respiratory",
                        value: String(format: "%.0f", todaysData?.respiratoryRate ?? 0.0),
                        unit: "bpm",
                        icon: "wind",
                        color: .cyan,
                        status: respiratoryRateStatus,
                        trend: respiratoryRateTrend,
                        subtitle: "Breathing"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Enhanced Activity Section
    private var enhancedActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                NavigationLink(destination: AllWorkoutsView()) {
                    Text("View All")
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            }
            
            if recentWorkouts.isEmpty {
                EmptyStateView(
                    icon: "figure.run",
                    title: "No recent workouts",
                    subtitle: "Your workouts will appear here once you start exercising"
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(recentWorkouts, id: \.id) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            EnhancedActivityCard(workout: workout)
                    }
                        .buttonStyle(PlainButtonStyle())
                }
                    
                    // Achievement highlight
                    if let achievement = todaysAchievement {
                        AchievementCard(achievement: achievement)
                }
            }
        }
        }
    }
    
    // MARK: - Enhanced Weekly Insights
    private var enhancedWeeklyInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Weekly Insights")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    showingWeeklyInsights = true
                }) {
                    Text("View Details")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            
            VStack(spacing: 12) {
                EnhancedInsightCard(
                    title: "Weekly Average Steps",
                    value: "\(Int(weeklyHealthSummary?.averageSteps ?? 0))",
                    subtitle: "steps per day",
                    trend: weeklyHealthSummary?.stepsTrend ?? 0,
                    icon: "figure.walk",
                    color: .green,
                    recommendation: getStepRecommendation()
                ) {
                    showingWeeklyInsights = true
                }
                
                EnhancedInsightCard(
                    title: "Sleep Quality",
                    value: String(format: "%.1f/10", weeklyHealthSummary?.averageSleepQuality ?? 0.0),
                    subtitle: "average score",
                    trend: weeklyHealthSummary?.sleepQualityTrend ?? 0.0,
                    icon: "moon.fill",
                    color: .indigo,
                    recommendation: getSleepRecommendation()
                ) {
                    showingWeeklyInsights = true
                }
            }
        }
        .sheet(isPresented: $showingWeeklyInsights) {
            WeeklyInsightsDetailView(
                weeklyHealthSummary: weeklyHealthSummary,
                healthMetrics: Array(allHealthMetrics.prefix(30)),
                workouts: Array(workouts.prefix(20))
            )
        }
    }
    
    // MARK: - Computed Properties
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    private var healthScore: Int {
        let steps = Double(todaysData?.stepCount ?? 0) / 10000.0 * 35
        let sleep = (todaysData?.sleepHours ?? 0.0) / 8.0 * 25
        let calories = (todaysData?.activeCalories ?? 0.0) / 500.0 * 25
        let heartRate = todaysData?.restingHeartRate ?? 0 > 0 ? 15 : 0
        return Int(min(steps + sleep + calories + Double(heartRate), 100))
    }
    
    private var healthScoreColor: Color {
        switch healthScore {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
    
    private var healthStatusColor: Color {
        switch healthScore {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
    
    private var enhancedHealthStatusText: String {
        switch healthScore {
        case 90...100: return "Excellent health day! 🌟"
        case 80...89: return "Great progress today! 💪"
        case 70...79: return "Good healthy choices 👍"
        case 60...69: return "Making steady progress 📈"
        case 50...59: return "Room for improvement 🎯"
        default: return "Let's build healthy habits 🌱"
        }
    }
    
    private var activityScore: Int {
        let stepsScore = min(Double(todaysData?.stepCount ?? 0) / 10000.0 * 50, 50)
        let caloriesScore = min((todaysData?.activeCalories ?? 0.0) / 500.0 * 50, 50)
        return Int(stepsScore + caloriesScore)
    }
    
    private var sleepScore: Int {
        guard let sleepHours = todaysData?.sleepHours, sleepHours > 0 else { return 0 }
        let baseScore = min(sleepHours / 8.0 * 70, 70)
        let qualityBonus = Double(todaysData?.sleepQuality ?? 0) / 10.0 * 30
        return Int(baseScore + qualityBonus)
    }
    
    private var heartHealthScore: Int {
        guard let heartRate = todaysData?.restingHeartRate, heartRate > 0 else { return 0 }
        let heartScore: Double
        switch heartRate {
        case 0...60: heartScore = 100
        case 61...70: heartScore = 85
        case 71...80: heartScore = 70
        case 81...90: heartScore = 55
        default: heartScore = 40
        }
        
        let hrvBonus = min((todaysData?.hrv ?? 0.0) / 50.0 * 20, 20)
        return Int(min(heartScore * 0.8 + hrvBonus, 100))
    }
    
    // Trend calculations (vs yesterday)
    private var stepsTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics() else { return 0.0 }
        
        let todaySteps = Double(today.stepCount)
        let yesterdaySteps = Double(yesterday.stepCount)
        
        guard yesterdaySteps > 0 else { return 0.0 }
        return ((todaySteps - yesterdaySteps) / yesterdaySteps) * 100
    }
    
    private var caloriesTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics() else { return 0.0 }
        
        let todayCalories = today.activeCalories
        let yesterdayCalories = yesterday.activeCalories
        
        guard yesterdayCalories > 0 else { return 0.0 }
        return ((todayCalories - yesterdayCalories) / yesterdayCalories) * 100
    }
    
    private var distanceTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics() else { return 0.0 }
        
        let todayDistance = today.totalDistance
        let yesterdayDistance = yesterday.totalDistance
        
        guard yesterdayDistance > 0 else { return 0.0 }
        return ((todayDistance - yesterdayDistance) / yesterdayDistance) * 100
    }
    
    private var heartRateTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics(),
              today.restingHeartRate > 0,
              yesterday.restingHeartRate > 0 else { return 0.0 }
        
        let todayHR = Double(today.restingHeartRate)
        let yesterdayHR = Double(yesterday.restingHeartRate)
        
        return ((todayHR - yesterdayHR) / yesterdayHR) * 100
    }
    
    private var sleepTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics(),
              today.sleepHours > 0,
              yesterday.sleepHours > 0 else { return 0.0 }
        
        return ((today.sleepHours - yesterday.sleepHours) / yesterday.sleepHours) * 100
    }
    
    private var hrvTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics(),
              today.hrv > 0,
              yesterday.hrv > 0 else { return 0.0 }
        
        return ((today.hrv - yesterday.hrv) / yesterday.hrv) * 100
    }
    
    private var vo2MaxTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics(),
              today.vo2Max > 0,
              yesterday.vo2Max > 0 else { return 0.0 }
        
        return ((today.vo2Max - yesterday.vo2Max) / yesterday.vo2Max) * 100
    }
    
    private var bloodOxygenTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics(),
              today.bloodOxygen > 0,
              yesterday.bloodOxygen > 0 else { return 0.0 }
        
        return ((today.bloodOxygen - yesterday.bloodOxygen) / yesterday.bloodOxygen) * 100
    }
    
    private var respiratoryRateTrend: Double {
        guard let today = todaysData,
              let yesterday = getYesterdaysMetrics(),
              today.respiratoryRate > 0,
              yesterday.respiratoryRate > 0 else { return 0.0 }
        
        return ((today.respiratoryRate - yesterday.respiratoryRate) / yesterday.respiratoryRate) * 100
    }
    
    private var hrvStatus: String {
        guard let hrv = todaysData?.hrv, hrv > 0 else { return "No data" }
        
        switch hrv {
        case 0...20: return "Low"
        case 20...50: return "Average"
        case 50...100: return "Good"
        default: return "Excellent"
        }
    }
    
    private var todaysAchievement: Achievement? {
        // Simple achievement detection - you can enhance this
        if let todaysData = todaysData {
            if todaysData.stepCount >= 10000 && !recentWorkouts.isEmpty {
                return Achievement(
                    title: "Active Day!",
                    description: "Hit step goal and completed a workout",
                    icon: "star.fill",
                    color: .yellow
                )
            }
        }
        return nil
    }
    
    private func getYesterdaysMetrics() -> HealthMetrics? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let startOfYesterday = Calendar.current.startOfDay(for: yesterday)
        
        return allHealthMetrics.first { metrics in
            Calendar.current.isDate(metrics.date, inSameDayAs: startOfYesterday)
        }
    }
    
    private func getStepRecommendation() -> String {
        let avgSteps = Int(weeklyHealthSummary?.averageSteps ?? 0)
        
        switch avgSteps {
        case 0..<5000: return "Try to add more walking to your daily routine"
        case 5000..<8000: return "Great start! Aim for 10,000 steps daily"
        case 8000..<10000: return "Almost there! A few more steps to reach your goal"
        default: return "Excellent! Keep up the active lifestyle"
        }
    }
    
    private func getSleepRecommendation() -> String {
        let avgSleep = weeklyHealthSummary?.averageSleepQuality ?? 0.0
        
        switch avgSleep {
        case 0..<5: return "Focus on a consistent bedtime routine"
        case 5..<7: return "Try to get 7-8 hours of sleep nightly"
        case 7..<8: return "Good sleep habits! Maintain consistency"
        default: return "Excellent sleep quality! Keep it up"
        }
    }
    
    private var healthStatusText: String {
        guard let data = todaysData else { return "Syncing your health data..." }
        
        let stepsProgress = Double(data.stepCount) / 10000.0
        let caloriesProgress = data.totalCalories / 2500.0
        let sleepProgress = data.sleepHours / 8.0
        
        let overallProgress = (stepsProgress + caloriesProgress + sleepProgress) / 3.0
        
        switch overallProgress {
        case 0.8...1.0: return "You're crushing your health goals today! 🎉"
        case 0.6...0.8: return "Great progress on your health journey 💪"
        case 0.4...0.6: return "You're making steady progress 📈"
        case 0.2...0.4: return "Let's get moving and improve your day 🚀"
        default: return "Every step counts - let's start small 🌱"
        }
    }
    
    private var heartRateStatus: String {
        guard let hr = todaysData?.restingHeartRate, hr > 0 else { return "No data" }
        
        switch hr {
        case 0...60: return "Athletic"
        case 60...70: return "Excellent"
        case 70...80: return "Good"
        case 80...90: return "Fair"
        default: return "High"
        }
    }
    
    private var vo2MaxStatus: String {
        guard let vo2 = todaysData?.vo2Max, vo2 > 0 else { return "No data" }
        
        switch vo2 {
        case 0...30: return "Poor"
        case 30...40: return "Fair"
        case 40...50: return "Good"
        case 50...60: return "Excellent"
        default: return "Superior"
        }
    }
    
    private var sleepStatus: String {
        guard let sleep = todaysData?.sleepHours, sleep > 0 else { return "No data" }
        
        switch sleep {
        case 0...5: return "Poor"
        case 5...6: return "Fair"
        case 6...8: return "Good"
        case 8...9: return "Excellent"
        default: return "Too much"
        }
    }
    
    private var bloodOxygenStatus: String {
        guard let bloodOxygen = todaysData?.bloodOxygen, bloodOxygen > 0 else { return "No data" }
        
        switch bloodOxygen {
        case 0...90: return "Critical"
        case 90...95: return "Low"
        case 95...100: return "Normal"
        default: return "Error"
        }
    }
    
    private var respiratoryRateStatus: String {
        guard let respiratoryRate = todaysData?.respiratoryRate, respiratoryRate > 0 else { return "No data" }
        
        switch respiratoryRate {
        case 0...12: return "Low"
        case 12...20: return "Normal"
        case 20...30: return "High"
        default: return "Very high"
        }
    }
    

    
    // Helper function to format sleep time as hours and minutes
    private func formatSleepTime(_ totalHours: Double) -> String {
        guard totalHours > 0 else { return "0h 0m" }
        
        let hours = Int(totalHours)
        let minutes = Int((totalHours - Double(hours)) * 60)
        
        if hours == 0 {
            return "\(minutes)m"
        } else if minutes == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }
    
    // MARK: - Methods
    
    private func refreshHealthData() async {
        await MainActor.run {
            isLoading = true
        }
        
        await healthKitService.syncRecentWorkouts()
        await healthKitService.syncHealthMetrics()
        await loadWeeklyHealthSummary()
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    private func loadWeeklyHealthSummary() async {
        let summary = await calculateWeeklyHealthSummary()
        await MainActor.run {
            weeklyHealthSummary = summary
        }
    }
    
    private func loadWeeklyHealthSummary() {
        Task {
            await loadWeeklyHealthSummary()
        }
    }
    
    private func calculateWeeklyHealthSummary() async -> WeeklyHealthSummary {
        return await MainActor.run {
        let calendar = Calendar.current
            let today = Date()
            
            // Get metrics for the current week
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            let weekMetrics = allHealthMetrics.filter { 
                $0.date >= weekStart && $0.date <= today
            }
            
            // Get metrics for the previous week for trend calculation
            let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
            let previousWeekMetrics = allHealthMetrics.filter {
                $0.date >= previousWeekStart && $0.date < weekStart
            }
            
            // Calculate current week averages
            let averageSteps = weekMetrics.isEmpty ? 0.0 : 
                Double(weekMetrics.reduce(0) { $0 + $1.stepCount }) / Double(weekMetrics.count)
            
            let totalActiveMinutes = weekMetrics.reduce(0) { $0 + $1.activeMinutes }
            
            let averageSleepQuality = weekMetrics.isEmpty ? 0.0 :
                Double(weekMetrics.reduce(0) { $0 + $1.sleepQuality }) / Double(weekMetrics.count)
            
            // Calculate trends (percentage change from previous week)
            let previousAverageSteps = previousWeekMetrics.isEmpty ? 0.0 :
                Double(previousWeekMetrics.reduce(0) { $0 + $1.stepCount }) / Double(previousWeekMetrics.count)
            
            let previousTotalActiveMinutes = previousWeekMetrics.reduce(0) { $0 + $1.activeMinutes }
            
            let previousAverageSleepQuality = previousWeekMetrics.isEmpty ? 0.0 :
                Double(previousWeekMetrics.reduce(0) { $0 + $1.sleepQuality }) / Double(previousWeekMetrics.count)
            
            let stepsTrend = previousAverageSteps > 0 ? 
                ((averageSteps - previousAverageSteps) / previousAverageSteps) * 100 : 0.0
            
            let activeMinutesTrend = previousTotalActiveMinutes > 0 ?
                ((Double(totalActiveMinutes) - Double(previousTotalActiveMinutes)) / Double(previousTotalActiveMinutes)) * 100 : 0.0
            
            let sleepQualityTrend = previousAverageSleepQuality > 0 ?
                ((averageSleepQuality - previousAverageSleepQuality) / previousAverageSleepQuality) * 100 : 0.0
            
        return WeeklyHealthSummary(
                averageSteps: averageSteps,
                totalActiveMinutes: Double(totalActiveMinutes),
                averageSleepQuality: averageSleepQuality,
                stepsTrend: stepsTrend,
                sleepQualityTrend: sleepQualityTrend,
                activeMinutesTrend: activeMinutesTrend
            )
        }
    }
    
    // MARK: - Auto Refresh Methods
    
    private func startAutoRefresh() {
        // Stop any existing timer
        stopAutoRefresh()
        
        // Start a timer that refreshes every 30 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task {
                await refreshHealthDataIfNeeded()
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func refreshHealthDataIfNeeded() async {
        // Only refresh if it's been more than 15 seconds since last refresh
        let timeSinceLastRefresh = Date().timeIntervalSince(lastRefreshTime)
        guard timeSinceLastRefresh > 15 else { return }
        
        // Use lightweight sync for frequent updates
        await healthKitService.syncRecentHealthMetrics()
        await MainActor.run {
            lastRefreshTime = Date()
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App became active - refresh data and start timer
            startAutoRefresh()
            Task {
                await refreshHealthData()
            }
        case .inactive, .background:
            // App went to background - stop timer to save battery
            stopAutoRefresh()
        @unknown default:
            break
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let timeInterval = Date().timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Detail Views

struct StepsDetailView: View {
    let healthMetrics: HealthMetrics?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                VStack(alignment: .leading, spacing: 16) {
            HStack {
                        Image(systemName: "figure.walk")
                            .font(.title)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading) {
                            Text("Steps")
                    .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Today's Activity")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                
                Spacer()
            }
            
                    HStack {
                        Text("\(healthMetrics?.stepCount ?? 0)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.green)
                        
                        Text("steps")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        
                        Spacer()
                    }
                    
                    ProgressView(value: Double(healthMetrics?.stepCount ?? 0) / 10000.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                        .scaleEffect(x: 1, y: 2)
                    
                    Text("Goal: 10,000 steps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
                
                // Insights
                VStack(alignment: .leading, spacing: 16) {
                    Text("Insights")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        InsightRow(
                            icon: "target",
                            title: "Daily Goal",
                            value: "\(Int((Double(healthMetrics?.stepCount ?? 0) / 10000.0) * 100))% Complete",
                            color: .green
                        )
                        
                        InsightRow(
                            icon: "flame.fill",
                            title: "Calories Burned",
                            value: "~\(Int(Double(healthMetrics?.stepCount ?? 0) * 0.04)) cal",
                            color: .orange
                        )
                        
                        InsightRow(
                            icon: "location.fill",
                            title: "Distance Walked",
                            value: String(format: "~%.1f km", Double(healthMetrics?.stepCount ?? 0) * 0.0008),
                            color: .blue
                        )
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CaloriesDetailView: View {
    let healthMetrics: HealthMetrics?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "flame.fill")
                    .font(.title)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading) {
                            Text("Active Calories")
                                .font(.title2)
                    .fontWeight(.bold)
                
                            Text("Today's Burn")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text("\(Int(healthMetrics?.activeCalories ?? 0))")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.orange)
                        
                        Text("cal")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        
                        Spacer()
                    }
                    
                    ProgressView(value: (healthMetrics?.activeCalories ?? 0) / 500.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                        .scaleEffect(x: 1, y: 2)
                    
                    Text("Goal: 500 calories")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
                
                // Breakdown
                VStack(alignment: .leading, spacing: 16) {
                    Text("Breakdown")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        InsightRow(
                            icon: "figure.walk",
                            title: "From Steps",
                            value: "\(Int(Double(healthMetrics?.stepCount ?? 0) * 0.04)) cal",
                            color: .green
                        )
                        
                        InsightRow(
                            icon: "figure.run",
                            title: "From Workouts",
                            value: "\(Int((healthMetrics?.activeCalories ?? 0) - Double(healthMetrics?.stepCount ?? 0) * 0.04)) cal",
                            color: .blue
                        )
                        
                        InsightRow(
                            icon: "target",
                            title: "Goal Progress",
                            value: "\(Int(((healthMetrics?.activeCalories ?? 0) / 500.0) * 100))%",
                            color: .orange
                        )
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calories")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DistanceDetailView: View {
    let healthMetrics: HealthMetrics?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "location.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Distance")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Today's Movement")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text(String(format: "%.1f", healthMetrics?.totalDistance ?? 0.0))
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.blue)
                        
                        Text("km")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        
                        Spacer()
                    }
                    
                    ProgressView(value: (healthMetrics?.totalDistance ?? 0.0) / 5.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(x: 1, y: 2)
                    
                    Text("Goal: 5.0 km")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(Color(.systemBackground))
        .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
                
                // Details
                VStack(alignment: .leading, spacing: 16) {
                    Text("Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        InsightRow(
                            icon: "figure.walk",
                            title: "Walking Distance",
                            value: String(format: "%.1f km", healthMetrics?.totalDistance ?? 0.0),
                            color: .green
                        )
                        
                        InsightRow(
                            icon: "timer",
                            title: "Est. Time",
                            value: "\(Int((healthMetrics?.totalDistance ?? 0.0) * 12)) min",
                            color: .purple
                        )
                        
                        InsightRow(
                            icon: "target",
                            title: "Goal Progress",
                            value: "\(Int(((healthMetrics?.totalDistance ?? 0.0) / 5.0) * 100))%",
                            color: .blue
                        )
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Distance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HeartRateDetailView: View {
    let healthMetrics: HealthMetrics?
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTimeRange: TimeRange = .today
    @State private var showingTrends = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HeartRateReading.timestamp, ascending: true)],
        animation: .default)
    private var heartRateReadings: FetchedResults<HeartRateReading>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: true)],
        animation: .default)
    private var allHealthMetrics: FetchedResults<HealthMetrics>
    
    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "7 Days"
        case month = "30 Days"
    }
    
    init(healthMetrics: HealthMetrics?) {
        self.healthMetrics = healthMetrics
        
        // Filter readings for today initially
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
        
        self._heartRateReadings = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \HeartRateReading.timestamp, ascending: true)],
            predicate: NSPredicate(format: "timestamp >= %@ AND timestamp < %@", today as NSDate, tomorrow as NSDate)
        )
        
        // Get historical data for trends
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        self._allHealthMetrics = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: true)],
            predicate: NSPredicate(format: "date >= %@ AND restingHeartRate > 0", thirtyDaysAgo as NSDate)
        )
    }
    
    var filteredReadings: [HeartRateReading] {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        
        switch selectedTimeRange {
        case .today:
            startDate = calendar.startOfDay(for: now)
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
        
        return heartRateReadings.filter { $0.timestamp >= startDate }
    }
    
    var averageHeartRate: Int {
        guard !filteredReadings.isEmpty else { return Int(healthMetrics?.restingHeartRate ?? 0) }
        let total = filteredReadings.reduce(0) { $0 + Int($1.heartRate) }
        return total / filteredReadings.count
    }
    
    var maxHeartRate: Int {
        guard !filteredReadings.isEmpty else { return Int(healthMetrics?.restingHeartRate ?? 0) }
        return Int(filteredReadings.max(by: { $0.heartRate < $1.heartRate })?.heartRate ?? 0)
    }
    
    var minHeartRate: Int {
        guard !filteredReadings.isEmpty else { return Int(healthMetrics?.restingHeartRate ?? 0) }
        return Int(filteredReadings.min(by: { $0.heartRate < $1.heartRate })?.heartRate ?? 0)
    }
    
    var restingHeartRate: Int {
        Int(healthMetrics?.restingHeartRate ?? 0)
    }
    
    var maxTheoreticalHR: Int {
        // Simple formula: 220 - age (assuming age 25 if not available)
        220 - 25
    }
    
    var heartRateReserve: Int {
        maxTheoreticalHR - restingHeartRate
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Time Range Picker
                timeRangePicker
                
                // Enhanced Header Card with comprehensive stats
                enhancedHeaderCard
                
                // Heart Rate Chart with enhanced features
                if !filteredReadings.isEmpty {
                    enhancedHeartRateChart
                } else {
                    noDataCard
                }
                
                // Heart Rate Zones with detailed analysis
                enhancedHeartRateZones
                
                // Resting HR Trends
                restingHeartRateTrends
                
                // Training Insights & Recovery
                trainingInsights
                
                // Age-Based Comparison
                ageBasedComparison
                
                // Detailed Analytics
                detailedAnalytics
                
                // Health Recommendations
                healthRecommendations
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Heart Rate Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingTrends) {
            HeartRateTrendsView(healthMetrics: Array(allHealthMetrics))
        }
    }
    
    // MARK: - Time Range Picker
    private var timeRangePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Time Period")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View Trends") {
                    showingTrends = true
                }
                        .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Enhanced Header Card
    private var enhancedHeaderCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(restingHeartRate)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        
                        Text("bpm")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }
                    
                    Text("Resting HR")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 4) {
                        Text("Reserve")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text("\(heartRateReserve)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                        
                    VStack(spacing: 4) {
                        Text("Max Theory")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(maxTheoreticalHR)")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Today's Range")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                        Text("\(minHeartRate) - \(maxHeartRate)")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        Text("bpm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Average")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(averageHeartRate)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Heart Rate Status Indicators
            HStack(spacing: 16) {
                StatusIndicator(
                    title: "Fitness Level",
                    value: heartRateFitnessLevel,
                    color: heartRateFitnessColor,
                    icon: "heart.circle.fill"
                )
                
                StatusIndicator(
                    title: "Recovery",
                    value: recoveryStatus,
                    color: recoveryStatusColor,
                    icon: "arrow.clockwise.circle.fill"
                )
                
                StatusIndicator(
                    title: "Variability",
                    value: variabilityStatus,
                    color: .teal,
                    icon: "waveform.circle.fill"
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Enhanced Heart Rate Chart
    private var enhancedHeartRateChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(selectedTimeRange.rawValue) Heart Rate")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(filteredReadings.count) readings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            EnhancedHeartRateChartView(readings: filteredReadings, timeRange: selectedTimeRange)
                .frame(height: 250)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Enhanced Heart Rate Zones
    private var enhancedHeartRateZones: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Heart Rate Zones")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(heartRateZones, id: \.zone) { zoneData in
                    EnhancedHeartRateZoneRow(
                        zone: zoneData.zone,
                        range: zoneData.range,
                        percentage: zoneData.percentage,
                        color: zoneData.color,
                        timeSpent: zoneData.timeSpent,
                        description: zoneData.description
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Resting Heart Rate Trends
    private var restingHeartRateTrends: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Resting HR Trends")
                .font(.headline)
                .fontWeight(.semibold)
            
                Spacer()
                
                Text("Last 30 days")
                            .font(.caption)
                .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                RestingHRTrendCard(
                    title: "7-Day Average",
                    value: sevenDayAverageRestingHR,
                    trend: sevenDayRestingHRTrend,
                    color: .blue
                )
                
                RestingHRTrendCard(
                    title: "30-Day Average",
                    value: thirtyDayAverageRestingHR,
                    trend: thirtyDayRestingHRTrend,
                    color: .green
                )
                
                RestingHRTrendCard(
                    title: "Lowest",
                    value: lowestRestingHR,
                    trend: 0.0,
                    color: .mint
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Training Insights
    private var trainingInsights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                TrainingInsightRow(
                    icon: "target",
                    title: "Target HR Zones",
                    subtitle: "For optimal training",
                    value: "Zone 2: \(zone2Range) bpm",
                    color: .blue
                )
                
                TrainingInsightRow(
                    icon: "timer",
                    title: "Recovery Time",
                    subtitle: "Based on recent activity",
                    value: estimatedRecoveryTime,
                    color: .orange
                )
                
                TrainingInsightRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Fitness Trend",
                    subtitle: "Cardiovascular improvement",
                    value: fitnessTrend,
                    color: .green
                )
                
                TrainingInsightRow(
                    icon: "heart.text.square",
                    title: "HRV Status",
                    subtitle: "Recovery readiness",
                    value: String(format: "%.0f ms", healthMetrics?.hrv ?? 0),
                    color: .teal
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Age-Based Comparison
    private var ageBasedComparison: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Age-Based Comparison")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ComparisonRow(
                    title: "Your Resting HR",
                    value: "\(restingHeartRate) bpm",
                    comparison: restingHRComparison,
                    color: restingHRComparisonColor
                )
                
                ComparisonRow(
                    title: "Age Group Average",
                    value: "\(ageGroupAverageHR) bpm",
                    comparison: "Normal range: \(ageGroupNormalRange) bpm",
                    color: .gray
                )
                
                ComparisonRow(
                    title: "Fitness Level",
                    value: cardioFitnessLevel,
                    comparison: cardioFitnessComparison,
                    color: cardioFitnessColor
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Detailed Analytics
    private var detailedAnalytics: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detailed Analytics")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                AnalyticsCard(
                    title: "Heart Rate Reserve",
                    value: "\(heartRateReserve) bpm",
                    subtitle: "Available training range",
                    icon: "gauge.medium",
                    color: .orange
                )
                
                AnalyticsCard(
                    title: "Training Load",
                    value: trainingLoadStatus,
                    subtitle: "Based on HR zones",
                    icon: "dumbbell.fill",
                    color: .purple
                )
                
                AnalyticsCard(
                    title: "Recovery Index",
                    value: String(format: "%.1f", recoveryIndex),
                    subtitle: "0-10 scale",
                    icon: "arrow.clockwise",
                    color: .teal
                )
                
                AnalyticsCard(
                    title: "Aerobic Capacity",
                    value: aerobicCapacityStatus,
                    subtitle: "VO2 Max estimate",
                    icon: "lungs.fill",
                    color: .mint
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Health Recommendations
    private var healthRecommendations: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Health Recommendations")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(heartRateRecommendations, id: \.id) { recommendation in
                    RecommendationCard(
                        icon: recommendation.icon,
                        title: recommendation.title,
                        description: recommendation.description,
                        priority: recommendation.priority,
                        color: recommendation.color
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var heartRateChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Heart Rate")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(filteredReadings.count) readings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HeartRateChartView(readings: filteredReadings)
                .frame(height: 200)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var noDataCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Heart Rate Data")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("Heart rate readings will appear here throughout the day. Make sure HealthKit access is enabled.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }

    
    private var detailedInsights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Health Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                InsightRow(
                    icon: "heart.circle",
                    title: "Fitness Level",
                    value: heartRateStatus,
                    color: statusColor
                )
                
                InsightRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Variability",
                    value: "\(maxHeartRate - minHeartRate) bpm range",
                    color: .blue
                )
                
                InsightRow(
                    icon: "clock",
                    title: "Most Active",
                    value: mostActiveTime,
                    color: .orange
                )
                
                InsightRow(
                    icon: "info.circle",
                    title: "Normal Range",
                    value: "60-100 bpm at rest",
                    color: .gray
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var contextAnalysis: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Context Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(contextBreakdown, id: \.context) { item in
                    HStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: 12, height: 12)
                        
                        Text(item.context.capitalized)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(item.count) readings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("(\(item.percentage)%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var heartRateStatus: String {
        let avgHR = averageHeartRate > 0 ? averageHeartRate : Int(healthMetrics?.restingHeartRate ?? 0)
        
        switch avgHR {
        case 0...60: return "Athletic"
        case 60...70: return "Excellent"
        case 70...80: return "Good"
        case 80...90: return "Fair"
        default: return "High"
        }
    }
    
    private var statusColor: Color {
        switch heartRateStatus {
        case "Athletic", "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        default: return .red
        }
    }
    
    private var mostActiveTime: String {
        guard !filteredReadings.isEmpty else { return "No data" }
        
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "HH"
        
        let hourCounts = Dictionary(grouping: filteredReadings) { reading in
            hourFormatter.string(from: reading.timestamp)
        }
        
        let mostActiveHour = hourCounts.max { $0.value.count < $1.value.count }?.key ?? "Unknown"
        
        if let hour = Int(mostActiveHour) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h a"
            let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
            return timeFormatter.string(from: date)
        }
        
        return "Unknown"
    }
    
    private var contextBreakdown: [(context: String, count: Int, percentage: Int, color: Color)] {
        let total = filteredReadings.count
        guard total > 0 else { return [] }
        
        let contexts = Dictionary(grouping: filteredReadings) { $0.context ?? "unknown" }
        
        return contexts.map { (context, readings) in
            let percentage = Int(Double(readings.count) / Double(total) * 100)
            let color: Color = {
                switch context {
                case "resting": return .green
                case "active": return .blue
                case "elevated": return .orange
                case "workout": return .red
                default: return .gray
                }
            }()
            
            return (context, readings.count, percentage, color)
        }.sorted { $0.count > $1.count }
    }
    
    // MARK: - Enhanced Computed Properties
    private var heartRateFitnessLevel: String {
        switch restingHeartRate {
        case 0...60: return "Athletic"
        case 60...70: return "Excellent"
        case 70...80: return "Good"
        case 80...90: return "Fair"
        default: return "Poor"
        }
    }
    
    private var heartRateFitnessColor: Color {
        switch heartRateFitnessLevel {
        case "Athletic", "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        default: return .red
        }
    }
    
    private var recoveryStatus: String {
        let hrv = healthMetrics?.hrv ?? 0
        switch hrv {
        case 50...: return "Excellent"
        case 30..<50: return "Good"
        case 20..<30: return "Fair"
        default: return "Poor"
        }
    }
    
    private var recoveryStatusColor: Color {
        switch recoveryStatus {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        default: return .red
        }
    }
    
    private var variabilityStatus: String {
        let range = maxHeartRate - minHeartRate
        switch range {
        case 0..<20: return "Low"
        case 20..<40: return "Normal"
        case 40..<60: return "High"
        default: return "Very High"
        }
    }
    
    private var sevenDayAverageRestingHR: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentMetrics = allHealthMetrics.filter { $0.date >= sevenDaysAgo && $0.restingHeartRate > 0 }
        guard !recentMetrics.isEmpty else { return restingHeartRate }
        let total = recentMetrics.reduce(0.0) { $0 + Double($1.restingHeartRate) }
        return Int(total / Double(recentMetrics.count))
    }
    
    private var thirtyDayAverageRestingHR: Int {
        let recentMetrics = allHealthMetrics.filter { $0.restingHeartRate > 0 }
        guard !recentMetrics.isEmpty else { return restingHeartRate }
        let total = recentMetrics.reduce(0.0) { $0 + Double($1.restingHeartRate) }
        return Int(total / Double(recentMetrics.count))
    }
    
    private var lowestRestingHR: Int {
        let recentMetrics = allHealthMetrics.filter { $0.restingHeartRate > 0 }
        guard !recentMetrics.isEmpty else { return restingHeartRate }
        let minValue = recentMetrics.map { Double($0.restingHeartRate) }.min() ?? Double(restingHeartRate)
        return Int(minValue)
    }
    
    private var sevenDayRestingHRTrend: Double {
        let currentAvg = Double(sevenDayAverageRestingHR)
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let previousWeekMetrics = allHealthMetrics.filter { 
            $0.date >= fourteenDaysAgo && $0.date < sevenDaysAgo && $0.restingHeartRate > 0 
        }
        
        guard !previousWeekMetrics.isEmpty else { return 0.0 }
        let previousTotal = previousWeekMetrics.reduce(0.0) { $0 + Double($1.restingHeartRate) }
        let previousAvg = previousTotal / Double(previousWeekMetrics.count)
        
        return ((currentAvg - previousAvg) / previousAvg) * 100
    }
    
    private var thirtyDayRestingHRTrend: Double {
        let currentAvg = Double(thirtyDayAverageRestingHR)
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let previousMonthMetrics = allHealthMetrics.filter { 
            $0.date >= sixtyDaysAgo && $0.date < thirtyDaysAgo && $0.restingHeartRate > 0 
        }
        
        guard !previousMonthMetrics.isEmpty else { return 0.0 }
        let previousTotal = previousMonthMetrics.reduce(0.0) { $0 + Double($1.restingHeartRate) }
        let previousAvg = previousTotal / Double(previousMonthMetrics.count)
        
        return ((currentAvg - previousAvg) / previousAvg) * 100
    }
    
    private var zone2Range: String {
        let zone2Min = Int(Double(maxTheoreticalHR) * 0.6)
        let zone2Max = Int(Double(maxTheoreticalHR) * 0.7)
        return "\(zone2Min)-\(zone2Max)"
    }
    
    private var estimatedRecoveryTime: String {
        let currentHR = restingHeartRate
        let optimalHR = 60
        
        if currentHR <= optimalHR + 5 {
            return "Ready"
        } else if currentHR <= optimalHR + 10 {
            return "6-12 hours"
        } else {
            return "12-24 hours"
        }
    }
    
    private var fitnessTrend: String {
        let trend = thirtyDayRestingHRTrend
        if trend < -2 {
            return "Improving"
        } else if trend > 2 {
            return "Declining"
        } else {
            return "Stable"
        }
    }
    
    private var ageGroupAverageHR: Int {
        // Assuming age 25-35 group
        return 72
    }
    
    private var ageGroupNormalRange: String {
        return "60-85"
    }
    
    private var restingHRComparison: String {
        let avgHR = ageGroupAverageHR
        if restingHeartRate < avgHR - 10 {
            return "Excellent (well below average)"
        } else if restingHeartRate < avgHR - 5 {
            return "Very good (below average)"
        } else if restingHeartRate <= avgHR + 5 {
            return "Normal (average range)"
        } else {
            return "Above average"
        }
    }
    
    private var restingHRComparisonColor: Color {
        let avgHR = ageGroupAverageHR
        if restingHeartRate < avgHR - 5 {
            return .green
        } else if restingHeartRate <= avgHR + 5 {
            return .blue
        } else {
            return .orange
        }
    }
    
    private var cardioFitnessLevel: String {
        switch restingHeartRate {
        case 0...55: return "Superior"
        case 56...65: return "Excellent"
        case 66...75: return "Good"
        case 76...85: return "Fair"
        default: return "Poor"
        }
    }
    
    private var cardioFitnessComparison: String {
        return "Based on resting heart rate for your age group"
    }
    
    private var cardioFitnessColor: Color {
        switch cardioFitnessLevel {
        case "Superior", "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        default: return .red
        }
    }
    
    private var trainingLoadStatus: String {
        let readings = filteredReadings
        guard !readings.isEmpty else { return "No data" }
        
        let highIntensityCount = readings.filter { $0.heartRate > 140 }.count
        let percentage = Double(highIntensityCount) / Double(readings.count) * 100
        
        switch percentage {
        case 0..<10: return "Light"
        case 10..<25: return "Moderate"
        case 25..<40: return "High"
        default: return "Very High"
        }
    }
    
    private var recoveryIndex: Double {
        let hrv = healthMetrics?.hrv ?? 0
        let restingHR = Double(restingHeartRate)
        
        // Simple recovery index calculation
        let hrvScore = min(hrv / 50.0 * 5.0, 5.0)
        let hrScore = max(0, 5.0 - (restingHR - 50.0) / 10.0)
        
        return (hrvScore + hrScore) / 2.0 * 2.0
    }
    
    private var aerobicCapacityStatus: String {
        let vo2Max = healthMetrics?.vo2Max ?? 0
        switch vo2Max {
        case 50...: return "Superior"
        case 40..<50: return "Excellent"
        case 35..<40: return "Good"
        case 30..<35: return "Fair"
        default: return "Needs improvement"
        }
    }
    
    private var heartRateZones: [HeartRateZoneData] {
        let readings = filteredReadings
        let totalReadings = readings.count
        
        let zones: [(String, String, Color, String, (Int) -> Bool)] = [
            ("Zone 1", "0-\(Int(Double(maxTheoreticalHR) * 0.6)-1) bpm", Color.blue, "Active Recovery", { hr in hr < Int(Double(maxTheoreticalHR) * 0.6) }),
            ("Zone 2", "\(Int(Double(maxTheoreticalHR) * 0.6))-\(Int(Double(maxTheoreticalHR) * 0.7)-1) bpm", Color.green, "Aerobic Base", { hr in hr >= Int(Double(maxTheoreticalHR) * 0.6) && hr < Int(Double(maxTheoreticalHR) * 0.7) }),
            ("Zone 3", "\(Int(Double(maxTheoreticalHR) * 0.7))-\(Int(Double(maxTheoreticalHR) * 0.8)-1) bpm", Color.yellow, "Aerobic Threshold", { hr in hr >= Int(Double(maxTheoreticalHR) * 0.7) && hr < Int(Double(maxTheoreticalHR) * 0.8) }),
            ("Zone 4", "\(Int(Double(maxTheoreticalHR) * 0.8))-\(Int(Double(maxTheoreticalHR) * 0.9)-1) bpm", Color.orange, "Lactate Threshold", { hr in hr >= Int(Double(maxTheoreticalHR) * 0.8) && hr < Int(Double(maxTheoreticalHR) * 0.9) }),
            ("Zone 5", "\(Int(Double(maxTheoreticalHR) * 0.9))+ bpm", Color.red, "VO2 Max", { hr in hr >= Int(Double(maxTheoreticalHR) * 0.9) })
        ]
        
        return zones.map { (zoneName, rangeString, color, description, filter) in
            let count = readings.filter { hr in
                let heartRateInt = Int(hr.heartRate)
                return filter(heartRateInt)
            }.count
            
            let percentage = totalReadings > 0 ? Double(count) / Double(totalReadings) * 100 : 0
            let timeSpent = totalReadings > 0 ? count * 5 : 0 // Assuming 5 min per reading
            
            return HeartRateZoneData(
                zone: zoneName,
                range: rangeString,
                percentage: percentage,
                color: color,
                timeSpent: timeSpent,
                description: description
            )
        }
    }
    
    private var heartRateRecommendations: [HeartRateRecommendation] {
        var recommendations: [HeartRateRecommendation] = []
        
        if restingHeartRate > 80 {
            recommendations.append(HeartRateRecommendation(
                id: "high_resting_hr",
                icon: "heart.fill",
                title: "Consider Cardiovascular Exercise",
                description: "Your resting heart rate is elevated. Regular aerobic exercise can help lower it.",
                priority: .high,
                color: .red
            ))
        }
        
        if recoveryStatus == "Poor" {
            recommendations.append(HeartRateRecommendation(
                id: "poor_recovery",
                icon: "bed.double.fill",
                title: "Focus on Recovery",
                description: "Your HRV suggests poor recovery. Prioritize sleep and stress management.",
                priority: .high,
                color: .orange
            ))
        }
        
        if filteredReadings.filter({ $0.heartRate > 140 }).count < filteredReadings.count * 10 / 100 {
            recommendations.append(HeartRateRecommendation(
                id: "increase_intensity",
                icon: "bolt.fill",
                title: "Add High-Intensity Training",
                description: "Consider adding some higher intensity workouts to improve cardiovascular fitness.",
                priority: .medium,
                color: .blue
            ))
        }
        
        return recommendations
    }
}

struct HeartRateChartView: View {
    let readings: [HeartRateReading]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    
                    // Horizontal lines
                    for i in 0...4 {
                        let y = height * CGFloat(i) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    
                    // Vertical lines
                    for i in 0...6 {
                        let x = width * CGFloat(i) / 6
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                
                // Heart rate line
                if !readings.isEmpty {
                    HeartRateLineShape(readings: readings)
                        .stroke(Color.red, lineWidth: 2)
                    
                    // Data points
                    ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
                        let x = geometry.size.width * CGFloat(index) / CGFloat(max(readings.count - 1, 1))
                        let normalizedHR = CGFloat(Int(reading.heartRate) - minHR) / CGFloat(maxHR - minHR)
                        let y = geometry.size.height * (1 - normalizedHR)
                        
                        Circle()
                            .fill(contextColor(for: reading.context))
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                    }
                }
                
                // Y-axis labels
                VStack {
                    HStack {
                        Text("\(maxHR)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Spacer()
                    
                    HStack {
                        Text("\((maxHR + minHR) / 2)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Spacer()
                    
                    HStack {
                        Text("\(minHR)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                // X-axis labels
                VStack {
                    Spacer()
                    
                    HStack {
                        Text("6 AM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("12 PM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("6 PM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("12 AM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var minHR: Int {
        readings.map { Int($0.heartRate) }.min() ?? 60
    }
    
    private var maxHR: Int {
        readings.map { Int($0.heartRate) }.max() ?? 100
    }
    
    private func contextColor(for context: String?) -> Color {
        switch context {
        case "resting": return .green
        case "active": return .blue
        case "elevated": return .orange
        case "workout": return .red
        default: return .gray
        }
    }
}

struct HeartRateLineShape: Shape {
    let readings: [HeartRateReading]
    
    func path(in rect: CGRect) -> Path {
        guard !readings.isEmpty else { return Path() }
        
        let minHR = readings.map { Int($0.heartRate) }.min() ?? 60
        let maxHR = readings.map { Int($0.heartRate) }.max() ?? 100
        
        var path = Path()
        
        for (index, reading) in readings.enumerated() {
            let x = rect.width * CGFloat(index) / CGFloat(max(readings.count - 1, 1))
            let normalizedHR = CGFloat(Int(reading.heartRate) - minHR) / CGFloat(maxHR - minHR)
            let y = rect.height * (1 - normalizedHR)
            
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

struct HeartRateZoneRow: View {
    let title: String
    let range: String
    let color: Color
    let count: Int
    
    var body: some View {
            HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(range)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                    .foregroundColor(color)
        }
    }
}

struct SleepDetailView: View {
    let healthMetrics: HealthMetrics?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "moon.fill")
                            .font(.title)
                            .foregroundColor(.indigo)
                        
                        VStack(alignment: .leading) {
                            Text("Sleep")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Last Night")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                
                Spacer()
                        
                        Text(sleepStatus)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(sleepStatusColor.opacity(0.15))
                            .foregroundColor(sleepStatusColor)
                            .cornerRadius(8)
                    }
                    
                    HStack {
                        Text(formatSleepTime(healthMetrics?.sleepHours ?? 0.0))
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.indigo)
                        
                        Spacer()
                    }
                    
                    if let sleepHours = healthMetrics?.sleepHours, sleepHours > 0 {
                        ProgressView(value: sleepHours / 8.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .indigo))
                            .scaleEffect(x: 1, y: 2)
                        
                        Text("Goal: 8 hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
                
                // Sleep Breakdown
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sleep Breakdown")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        SleepBreakdownRow(
                            title: "Total Sleep",
                            value: formatSleepTime(healthMetrics?.sleepHours ?? 0.0),
                            color: .indigo
                        )
                        
                        SleepBreakdownRow(
                            title: "Deep Sleep",
                            value: formatSleepTime(healthMetrics?.deepSleepHours ?? 0.0),
                            color: .purple
                        )
                        
                        SleepBreakdownRow(
                            title: "REM Sleep",
                            value: formatSleepTime(healthMetrics?.remSleepHours ?? 0.0),
                            color: .blue
                        )
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
                
                // Sleep Insights
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sleep Insights")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        InsightRow(
                            icon: "bed.double",
                            title: "Sleep Quality",
                            value: sleepStatus,
                            color: sleepStatusColor
                        )
                        
                        InsightRow(
                            icon: "moon.stars",
                            title: "Sleep Efficiency",
                            value: sleepEfficiencyText,
                            color: .blue
                        )
                        
                        InsightRow(
                            icon: "clock",
                            title: "Recommended",
                            value: "7-9 hours nightly",
                            color: .gray
                        )
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var sleepStatus: String {
        guard let sleep = healthMetrics?.sleepHours, sleep > 0 else { return "No data" }
        
        switch sleep {
        case 0...5: return "Poor"
        case 5...6: return "Fair"
        case 6...8: return "Good"
        case 8...9: return "Excellent"
        default: return "Too much"
        }
    }
    
    private var sleepStatusColor: Color {
        switch sleepStatus {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        case "No data": return .gray
        default: return .red
        }
    }
    
    private var sleepEfficiencyText: String {
        guard let totalSleep = healthMetrics?.sleepHours,
              let timeInBed = healthMetrics?.timeInBed,
              timeInBed > 0 else { return "No data" }
        
        // Sleep efficiency = (Total Sleep Time / Time in Bed) × 100
        let efficiency = (totalSleep / timeInBed) * 100
        
        // Cap at 100% in case of data inconsistencies
        let cappedEfficiency = min(efficiency, 100.0)
        
        return String(format: "%.0f%%", cappedEfficiency)
    }
    
    private func formatSleepTime(_ totalHours: Double) -> String {
        guard totalHours > 0 else { return "0h 0m" }
        
        let hours = Int(totalHours)
        let minutes = Int((totalHours - Double(hours)) * 60)
        
        if hours == 0 {
            return "\(minutes)m"
        } else if minutes == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }
}

struct SleepBreakdownRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
                Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

struct HRVDetailView: View {
    let healthMetrics: HealthMetrics?
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: true)],
        animation: .default)
    private var allHealthMetrics: FetchedResults<HealthMetrics>
    
    init(healthMetrics: HealthMetrics?) {
        self.healthMetrics = healthMetrics
        
        // Filter metrics for the last 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        self._allHealthMetrics = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: true)],
            predicate: NSPredicate(format: "date >= %@ AND hrv > 0", thirtyDaysAgo as NSDate)
        )
    }
    
    var recentMetrics: [HealthMetrics] {
        Array(allHealthMetrics.suffix(30))
    }
    
    var currentHRV: Double {
        healthMetrics?.hrv ?? 0.0
    }
    
    var averageHRV: Double {
        guard !recentMetrics.isEmpty else { return currentHRV }
        return recentMetrics.reduce(0) { $0 + $1.hrv } / Double(recentMetrics.count)
    }
    
    var maxHRV: Double {
        guard !recentMetrics.isEmpty else { return currentHRV }
        return recentMetrics.map { $0.hrv }.max() ?? currentHRV
    }
    
    var minHRV: Double {
        guard !recentMetrics.isEmpty else { return currentHRV }
        return recentMetrics.map { $0.hrv }.min() ?? currentHRV
    }
    
    var hrvTrend: String {
        guard recentMetrics.count >= 7 else { return "Insufficient data" }
        
        let recent7Days = Array(recentMetrics.suffix(7))
        let previous7Days = Array(recentMetrics.dropLast(7).suffix(7))
        
        guard !previous7Days.isEmpty else { return "Stable" }
        
        let recentAvg = recent7Days.reduce(0) { $0 + $1.hrv } / Double(recent7Days.count)
        let previousAvg = previous7Days.reduce(0) { $0 + $1.hrv } / Double(previous7Days.count)
        
        let change = ((recentAvg - previousAvg) / previousAvg) * 100
        
        if change > 5 {
            return "Improving"
        } else if change < -5 {
            return "Declining"
        } else {
            return "Stable"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                headerCard
                
                // HRV Chart
                if !recentMetrics.isEmpty {
                    hrvChart
                } else {
                    noDataCard
                }
                
                // HRV Zones
                hrvZones
                
                // Detailed Insights
                detailedInsights
                
                // Recovery Analysis
                recoveryAnalysis
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("HRV")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title)
                    .foregroundColor(.teal)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("HRV")
                        .font(.title2)
                    .fontWeight(.bold)
                
                    Text("Heart Rate Variability")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(hrvStatus)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(hrvStatusColor.opacity(0.15))
                    .foregroundColor(hrvStatusColor)
                    .cornerRadius(8)
            }
            
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(String(format: "%.1f", currentHRV))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.teal)
                        
                        Text("ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("30-Day Avg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(String(format: "%.1f", averageHRV))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        Text("ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Peak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(String(format: "%.1f", maxHRV))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        
                        Text("ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("HRV Trend (30 Days)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(recentMetrics.count) readings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HRVChartView(metrics: recentMetrics)
                .frame(height: 200)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var noDataCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No HRV Data")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("HRV readings will appear here as your device collects data. Higher HRV generally indicates better recovery.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var hrvZones: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HRV Zones")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                HRVZoneRow(
                    title: "Excellent",
                    range: "50+ ms",
                    color: .green,
                    count: recentMetrics.filter { $0.hrv >= 50 }.count
                )
                
                HRVZoneRow(
                    title: "Good",
                    range: "30-50 ms",
                    color: .blue,
                    count: recentMetrics.filter { $0.hrv >= 30 && $0.hrv < 50 }.count
                )
                
                HRVZoneRow(
                    title: "Fair",
                    range: "20-30 ms",
                    color: .orange,
                    count: recentMetrics.filter { $0.hrv >= 20 && $0.hrv < 30 }.count
                )
                
                HRVZoneRow(
                    title: "Poor",
                    range: "< 20 ms",
                    color: .red,
                    count: recentMetrics.filter { $0.hrv < 20 }.count
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var detailedInsights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HRV Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                InsightRow(
                    icon: "waveform.path.ecg",
                    title: "Recovery Status",
                    value: hrvStatus,
                    color: hrvStatusColor
                )
                
                InsightRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Trend",
                    value: hrvTrend,
                    color: trendColor
                )
                
                InsightRow(
                    icon: "arrow.up.arrow.down",
                    title: "Variability",
                    value: String(format: "%.1f ms range", maxHRV - minHRV),
                    color: .purple
                )
                
                InsightRow(
                    icon: "info.circle",
                    title: "Optimal Range",
                    value: "30-50 ms typical",
                    color: .gray
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var recoveryAnalysis: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recovery Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery Score")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(recoveryScoreText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    CircularProgressView(
                        progress: recoveryScore / 100,
                        title: "Recovery",
                        subtitle: String(format: "%.0f", recoveryScore),
                        size: 60
                    )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("What affects HRV:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Good sleep, hydration, moderate exercise")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("Stress, alcohol, overtraining, poor sleep")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var hrvStatus: String {
        switch currentHRV {
        case 50...: return "Excellent"
        case 30..<50: return "Good"
        case 20..<30: return "Fair"
        case 0..<20: return "Poor"
        default: return "No data"
        }
    }
    
    private var hrvStatusColor: Color {
        switch hrvStatus {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        case "Poor": return .red
        default: return .gray
        }
    }
    
    private var trendColor: Color {
        switch hrvTrend {
        case "Improving": return .green
        case "Declining": return .red
        default: return .blue
        }
    }
    
    private var recoveryScore: Double {
        guard currentHRV > 0 else { return 0 }
        
        let normalizedHRV = min(currentHRV / 50.0, 1.0) // Normalize to 50ms as excellent
        return normalizedHRV * 100
    }
    
    private var recoveryScoreText: String {
        switch recoveryScore {
        case 80...100: return "Excellent recovery"
        case 60..<80: return "Good recovery"
        case 40..<60: return "Moderate recovery"
        case 20..<40: return "Poor recovery"
        default: return "Very poor recovery"
        }
    }
    
    private var recoveryColor: Color {
        switch recoveryScore {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
}

struct HRVChartView: View {
    let metrics: [HealthMetrics]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    
                    // Horizontal lines
                    for i in 0...4 {
                        let y = height * CGFloat(i) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    
                    // Vertical lines
                    for i in 0...6 {
                        let x = width * CGFloat(i) / 6
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                
                // HRV line
                if !metrics.isEmpty {
                    HRVLineShape(metrics: metrics)
                        .stroke(Color.teal, lineWidth: 2)
                    
                    // Data points
                    ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                        let x = geometry.size.width * CGFloat(index) / CGFloat(max(metrics.count - 1, 1))
                        let normalizedHRV = CGFloat(metric.hrv - minHRV) / CGFloat(maxHRV - minHRV)
                        let y = geometry.size.height * (1 - normalizedHRV)
                        
                        Circle()
                            .fill(hrvPointColor(for: metric.hrv))
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                    }
                }
                
                // Y-axis labels
                VStack {
                    HStack {
                        Text(String(format: "%.0f", maxHRV))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Spacer()
                    
                    HStack {
                        Text(String(format: "%.0f", (maxHRV + minHRV) / 2))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Spacer()
                    
                    HStack {
                        Text(String(format: "%.0f", minHRV))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                // X-axis labels
                VStack {
                    Spacer()
                    
                    HStack {
                        Text("30d ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("15d ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var minHRV: Double {
        metrics.map { $0.hrv }.min() ?? 0
    }
    
    private var maxHRV: Double {
        metrics.map { $0.hrv }.max() ?? 100
    }
    
    private func hrvPointColor(for hrv: Double) -> Color {
        switch hrv {
        case 50...: return .green
        case 30..<50: return .blue
        case 20..<30: return .orange
        default: return .red
        }
    }
}

struct HRVLineShape: Shape {
    let metrics: [HealthMetrics]
    
    func path(in rect: CGRect) -> Path {
        guard !metrics.isEmpty else { return Path() }
        
        let minHRV = metrics.map { $0.hrv }.min() ?? 0
        let maxHRV = metrics.map { $0.hrv }.max() ?? 100
        
        var path = Path()
        
        for (index, metric) in metrics.enumerated() {
            let x = rect.width * CGFloat(index) / CGFloat(max(metrics.count - 1, 1))
            let normalizedHRV = CGFloat(metric.hrv - minHRV) / CGFloat(maxHRV - minHRV)
            let y = rect.height * (1 - normalizedHRV)
            
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

struct HRVZoneRow: View {
    let title: String
    let range: String
    let color: Color
    let count: Int
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(range)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

struct VO2MaxDetailView: View {
    let healthMetrics: HealthMetrics?
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: true)],
        animation: .default)
    private var allHealthMetrics: FetchedResults<HealthMetrics>
    
    init(healthMetrics: HealthMetrics?) {
        self.healthMetrics = healthMetrics
        
        // Filter metrics for the last 90 days (VO2 Max changes slowly)
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        
        self._allHealthMetrics = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: true)],
            predicate: NSPredicate(format: "date >= %@ AND vo2Max > 0", ninetyDaysAgo as NSDate)
        )
    }
    
    var recentMetrics: [HealthMetrics] {
        Array(allHealthMetrics.suffix(90))
    }
    
    var currentVO2Max: Double {
        healthMetrics?.vo2Max ?? 0.0
    }
    
    var averageVO2Max: Double {
        guard !recentMetrics.isEmpty else { return currentVO2Max }
        return recentMetrics.reduce(0) { $0 + $1.vo2Max } / Double(recentMetrics.count)
    }
    
    var maxVO2Max: Double {
        guard !recentMetrics.isEmpty else { return currentVO2Max }
        return recentMetrics.map { $0.vo2Max }.max() ?? currentVO2Max
    }
    
    var minVO2Max: Double {
        guard !recentMetrics.isEmpty else { return currentVO2Max }
        return recentMetrics.map { $0.vo2Max }.min() ?? currentVO2Max
    }
    
    var vo2MaxTrend: String {
        guard recentMetrics.count >= 14 else { return "Insufficient data" }
        
        let recent14Days = Array(recentMetrics.suffix(14))
        let previous14Days = Array(recentMetrics.dropLast(14).suffix(14))
        
        guard !previous14Days.isEmpty else { return "Stable" }
        
        let recentAvg = recent14Days.reduce(0) { $0 + $1.vo2Max } / Double(recent14Days.count)
        let previousAvg = previous14Days.reduce(0) { $0 + $1.vo2Max } / Double(previous14Days.count)
        
        let change = ((recentAvg - previousAvg) / previousAvg) * 100
        
        if change > 2 {
            return "Improving"
        } else if change < -2 {
            return "Declining"
        } else {
            return "Stable"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Card
                headerCard
                
                // VO2 Max Chart
                if !recentMetrics.isEmpty {
                    vo2MaxChart
                } else {
                    noDataCard
                }
                
                // Fitness Level Analysis
                fitnessLevelAnalysis
                
                // Performance Insights
                performanceInsights
                
                // Training Recommendations
                trainingRecommendations
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("VO2 Max")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lungs.fill")
                    .font(.title)
                    .foregroundColor(.mint)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("VO2 Max")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Cardio Fitness")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(vo2MaxStatus)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(vo2MaxStatusColor.opacity(0.15))
                    .foregroundColor(vo2MaxStatusColor)
                    .cornerRadius(8)
            }
            
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(String(format: "%.1f", currentVO2Max))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.mint)
                        
                        Text("ml/kg/min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("90-Day Avg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(String(format: "%.1f", averageVO2Max))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        Text("ml/kg/min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Peak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(String(format: "%.1f", maxVO2Max))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        
                        Text("ml/kg/min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var vo2MaxChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("VO2 Max Progress (90 Days)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(recentMetrics.count) readings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VO2MaxChartView(metrics: recentMetrics)
                .frame(height: 200)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var noDataCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "lungs")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No VO2 Max Data")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("VO2 Max readings will appear here from cardio workouts. Higher values indicate better cardiovascular fitness.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var fitnessLevelAnalysis: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fitness Level Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fitness Level")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(fitnessLevelDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    CircularProgressView(
                        progress: fitnessProgress,
                        title: "Fitness",
                        subtitle: vo2MaxStatus,
                        size: 80
                    )
                }
                
                VStack(spacing: 12) {
                    VO2MaxZoneRow(
                        title: "Superior",
                        range: "60+ ml/kg/min",
                        color: .green,
                        isCurrentLevel: currentVO2Max >= 60
                    )
                    
                    VO2MaxZoneRow(
                        title: "Excellent",
                        range: "50-60 ml/kg/min",
                        color: .blue,
                        isCurrentLevel: currentVO2Max >= 50 && currentVO2Max < 60
                    )
                    
                    VO2MaxZoneRow(
                        title: "Good",
                        range: "40-50 ml/kg/min",
                        color: .orange,
                        isCurrentLevel: currentVO2Max >= 40 && currentVO2Max < 50
                    )
                    
                    VO2MaxZoneRow(
                        title: "Fair",
                        range: "30-40 ml/kg/min",
                        color: .yellow,
                        isCurrentLevel: currentVO2Max >= 30 && currentVO2Max < 40
                    )
                    
                    VO2MaxZoneRow(
                        title: "Poor",
                        range: "< 30 ml/kg/min",
                        color: .red,
                        isCurrentLevel: currentVO2Max < 30 && currentVO2Max > 0
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var performanceInsights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                InsightRow(
                    icon: "lungs.fill",
                    title: "Cardio Fitness",
                    value: vo2MaxStatus,
                    color: vo2MaxStatusColor
                )
                
                InsightRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Trend",
                    value: vo2MaxTrend,
                    color: trendColor
                )
                
                InsightRow(
                    icon: "arrow.up.arrow.down",
                    title: "Range",
                    value: String(format: "%.1f ml/kg/min", maxVO2Max - minVO2Max),
                    color: .purple
                )
                
                InsightRow(
                    icon: "target",
                    title: "Next Goal",
                    value: nextGoalText,
                    color: .mint
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var trainingRecommendations: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Recommendations")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                TrainingRecommendationRow(
                    icon: "figure.run",
                    title: "Interval Training",
                    description: "High-intensity intervals improve VO2 Max efficiently",
                    frequency: "2-3x per week"
                )
                
                TrainingRecommendationRow(
                    icon: "timer",
                    title: "Tempo Runs",
                    description: "Sustained efforts at threshold pace",
                    frequency: "1-2x per week"
                )
                
                TrainingRecommendationRow(
                    icon: "figure.walk",
                    title: "Base Building",
                    description: "Long, easy aerobic sessions build foundation",
                    frequency: "3-4x per week"
                )
                
                TrainingRecommendationRow(
                    icon: "heart.fill",
                    title: "Recovery",
                    description: "Adequate rest allows adaptations to occur",
                    frequency: "1-2 days per week"
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var vo2MaxStatus: String {
        switch currentVO2Max {
        case 60...: return "Superior"
        case 50..<60: return "Excellent"
        case 40..<50: return "Good"
        case 30..<40: return "Fair"
        case 0..<30: return "Poor"
        default: return "No data"
        }
    }
    
    private var vo2MaxStatusColor: Color {
        switch vo2MaxStatus {
        case "Superior": return .green
        case "Excellent": return .blue
        case "Good": return .orange
        case "Fair": return .yellow
        case "Poor": return .red
        default: return .gray
        }
    }
    
    private var trendColor: Color {
        switch vo2MaxTrend {
        case "Improving": return .green
        case "Declining": return .red
        default: return .blue
        }
    }
    
    private var fitnessProgress: Double {
        guard currentVO2Max > 0 else { return 0 }
        return min(currentVO2Max / 60.0, 1.0) // Normalize to 60 as superior
    }
    
    private var fitnessLevelDescription: String {
        switch vo2MaxStatus {
        case "Superior": return "Elite athlete level fitness"
        case "Excellent": return "Very high cardiovascular fitness"
        case "Good": return "Above average fitness level"
        case "Fair": return "Average fitness level"
        case "Poor": return "Below average fitness level"
        default: return "No data available"
        }
    }
    
    private var nextGoalText: String {
        switch currentVO2Max {
        case 0..<30: return "Reach 30 ml/kg/min"
        case 30..<40: return "Reach 40 ml/kg/min"
        case 40..<50: return "Reach 50 ml/kg/min"
        case 50..<60: return "Reach 60 ml/kg/min"
        default: return "Maintain current level"
        }
    }
}

struct VO2MaxChartView: View {
    let metrics: [HealthMetrics]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    
                    // Horizontal lines
                    for i in 0...4 {
                        let y = height * CGFloat(i) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    
                    // Vertical lines
                    for i in 0...6 {
                        let x = width * CGFloat(i) / 6
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                
                // VO2 Max line
                if !metrics.isEmpty {
                    VO2MaxLineShape(metrics: metrics)
                        .stroke(Color.mint, lineWidth: 2)
                    
                    // Data points
                    ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                        let x = geometry.size.width * CGFloat(index) / CGFloat(max(metrics.count - 1, 1))
                        let normalizedVO2 = CGFloat(metric.vo2Max - minVO2Max) / CGFloat(maxVO2Max - minVO2Max)
                        let y = geometry.size.height * (1 - normalizedVO2)
                        
                Circle()
                            .fill(vo2MaxPointColor(for: metric.vo2Max))
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                    }
                }
                
                // Y-axis labels
                VStack {
                    HStack {
                        Text(String(format: "%.0f", maxVO2Max))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Spacer()
                    
                    HStack {
                        Text(String(format: "%.0f", (maxVO2Max + minVO2Max) / 2))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Spacer()
                    
                    HStack {
                        Text(String(format: "%.0f", minVO2Max))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                // X-axis labels
                VStack {
                    Spacer()
                    
                    HStack {
                        Text("90d ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("45d ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Today")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    private var minVO2Max: Double {
        metrics.map { $0.vo2Max }.min() ?? 0
    }
    
    private var maxVO2Max: Double {
        metrics.map { $0.vo2Max }.max() ?? 100
    }
    
    private func vo2MaxPointColor(for vo2Max: Double) -> Color {
        switch vo2Max {
        case 60...: return .green
        case 50..<60: return .blue
        case 40..<50: return .orange
        case 30..<40: return .yellow
        default: return .red
        }
    }
}

struct VO2MaxLineShape: Shape {
    let metrics: [HealthMetrics]
    
    func path(in rect: CGRect) -> Path {
        guard !metrics.isEmpty else { return Path() }
        
        let minVO2Max = metrics.map { $0.vo2Max }.min() ?? 0
        let maxVO2Max = metrics.map { $0.vo2Max }.max() ?? 100
        
        var path = Path()
        
        for (index, metric) in metrics.enumerated() {
            let x = rect.width * CGFloat(index) / CGFloat(max(metrics.count - 1, 1))
            let normalizedVO2 = CGFloat(metric.vo2Max - minVO2Max) / CGFloat(maxVO2Max - minVO2Max)
            let y = rect.height * (1 - normalizedVO2)
            
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

struct VO2MaxZoneRow: View {
    let title: String
    let range: String
    let color: Color
    let isCurrentLevel: Bool
    
    var body: some View {
        HStack {
                Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isCurrentLevel ? .bold : .medium)
                
                Text(range)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isCurrentLevel {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(color)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isCurrentLevel ? color.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

struct TrainingRecommendationRow: View {
    let icon: String
    let title: String
    let description: String
    let frequency: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.mint)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Text(frequency)
                    .font(.caption)
                    .fontWeight(.medium)
                .foregroundColor(.mint)
        }
        .padding(.vertical, 4)
    }
}



struct AllWorkoutsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)],
        animation: .default)
    private var workouts: FetchedResults<WorkoutLog>
    
    var body: some View {
        List {
            ForEach(workouts, id: \.id) { workout in
                NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                    HStack(spacing: 16) {
                        Image(systemName: workoutIcon(for: workout.workoutType))
                            .font(.title2)
                            .foregroundColor(workoutColor(for: workout.workoutType))
                            .frame(width: 40, height: 40)
                            .background(workoutColor(for: workout.workoutType).opacity(0.1))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.workoutType.capitalized)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(workout.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            if workout.distance > 0 {
                                Text(String(format: "%.1f km", workout.distance))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                            
                            Text(formatTime(workout.duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("All Workouts")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func workoutIcon(for type: String) -> String {
        switch type {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "swim": return "figure.pool.swim"
        case "strength": return "dumbbell.fill"
        case "hiit": return "timer"
        default: return "figure.mixed.cardio"
        }
    }
    
    private func workoutColor(for type: String) -> Color {
        switch type {
        case "run": return .orange
        case "walk": return .green
        case "bike": return .blue
        case "swim": return .cyan
        case "strength": return .red
        case "hiit": return .purple
        default: return .gray
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Views

struct OverviewMetric: View {
    let title: String
    let value: String
    let goal: String
    let progress: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
                
                Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: min(progress, 1.0))
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                    .scaleEffect(x: 1, y: 0.8)
                
                Text("Goal: \(goal)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MinimalOverviewMetric: View {
    let title: String
    let value: String
    let progress: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            ProgressView(value: min(progress, 1.0))
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(x: 1, y: 0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ModernVitalCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
                
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)
                }
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch status {
        case "Excellent", "Athletic", "Superior": return .green
        case "Good", "Normal": return .blue
        case "Fair": return .orange
        case "No data": return .gray
        default: return .red
        }
    }
}

struct ModernActivityCard: View {
    let workout: WorkoutLog
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: workoutIcon)
                .font(.title2)
                .foregroundColor(workoutColor)
                .frame(width: 44, height: 44)
                .background(workoutColor.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutType.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(workout.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if workout.distance > 0 {
                Text(String(format: "%.1f km", workout.distance))
                    .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Text(formatTime(workout.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var workoutIcon: String {
        switch workout.workoutType {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "swim": return "figure.pool.swim"
        case "strength": return "dumbbell.fill"
        case "hiit": return "timer"
        default: return "figure.mixed.cardio"
        }
    }
    
    private var workoutColor: Color {
        switch workout.workoutType {
        case "run": return .orange
        case "walk": return .green
        case "bike": return .blue
        case "swim": return .cyan
        case "strength": return .red
        case "hiit": return .purple
        default: return .gray
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct InsightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let trend: Double
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
                
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Image(systemName: trend >= 0 ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                        .foregroundColor(trend >= 0 ? .green : .red)
                    
                    Text(String(format: "%.1f%%", abs(trend)))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(trend >= 0 ? .green : .red)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct TappableInsightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let trend: Double
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.1))
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                HStack(spacing: 4) {
                    Image(systemName: trend >= 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                        .foregroundColor(trend >= 0 ? .green : .red)
                    
                    Text(String(format: "%.1f%%", abs(trend)))
                            .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(trend >= 0 ? .green : .red)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
        }
        .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct WeeklyInsightsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let weeklyHealthSummary: WeeklyHealthSummary?
    let healthMetrics: [HealthMetrics]
    let workouts: [WorkoutLog]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Header Summary
                    headerSummary
                    
                    // Detailed Charts
                    weeklyChartsSection
                    
                    // Trends Analysis
                    trendsAnalysisSection
                    
                    // Workout Summary
                    workoutSummarySection
                    
                    // Recommendations
                    recommendationsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weekly Insights")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Week Overview")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Average Steps")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(Int(weeklyHealthSummary?.averageSteps ?? 0))")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sleep Quality")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f/10", weeklyHealthSummary?.averageSleepQuality ?? 0))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Minutes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(Int(weeklyHealthSummary?.totalActiveMinutes ?? 0))")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var weeklyChartsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Breakdown")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Steps chart
            VStack(alignment: .leading, spacing: 12) {
                Text("Steps")
                    .font(.subheadline)
                .fontWeight(.medium)
            
                let weeklySteps = getWeeklyStepsData()
                let maxSteps = weeklySteps.map { $0.steps }.max() ?? 10000
                
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(weeklySteps, id: \.day) { dayData in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: 32, height: CGFloat(dayData.steps / maxSteps) * 80)
                            
                            Text(dayData.day)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
            
            // Sleep quality chart
            VStack(alignment: .leading, spacing: 12) {
                Text("Sleep Quality")
                .font(.subheadline)
                    .fontWeight(.medium)
                
                let weeklySleep = getWeeklySleepData()
                
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(weeklySleep, id: \.day) { dayData in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.indigo)
                                .frame(width: 32, height: CGFloat(dayData.quality / 10.0) * 80)
                            
                            Text(dayData.day)
                                .font(.caption2)
                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var trendsAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trends Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                TrendRow(
                    title: "Steps",
                    trend: weeklyHealthSummary?.stepsTrend ?? 0,
                    interpretation: getTrendInterpretation(weeklyHealthSummary?.stepsTrend ?? 0)
                )
                
                TrendRow(
                    title: "Sleep Quality",
                    trend: weeklyHealthSummary?.sleepQualityTrend ?? 0,
                    interpretation: getTrendInterpretation(weeklyHealthSummary?.sleepQualityTrend ?? 0)
                )
                
                TrendRow(
                    title: "Active Minutes",
                    trend: weeklyHealthSummary?.activeMinutesTrend ?? 0,
                    interpretation: getTrendInterpretation(weeklyHealthSummary?.activeMinutesTrend ?? 0)
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var workoutSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workout Summary")
                .font(.headline)
                .fontWeight(.semibold)
            
            let weeklyWorkouts = getWeeklyWorkouts()
            
            if weeklyWorkouts.isEmpty {
                Text("No workouts this week")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(weeklyWorkouts, id: \.id) { workout in
                        HStack {
                            Image(systemName: workoutIcon(for: workout.workoutType))
                                .foregroundColor(workoutColor(for: workout.workoutType))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.workoutType.capitalized)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(workout.timestamp.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f km", workout.distance))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(formatDuration(workout.duration))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recommendations")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                RecommendationCard(
                    icon: "target",
                    title: "Step Goal",
                    description: getStepRecommendation(),
                    priority: .medium,
                    color: .green
                )
                
                RecommendationCard(
                    icon: "moon.fill",
                    title: "Sleep",
                    description: getSleepRecommendation(),
                    priority: .medium,
                    color: .indigo
                )
                
                RecommendationCard(
                    icon: "figure.run",
                    title: "Activity",
                    description: getActivityRecommendation(),
                    priority: .medium,
                    color: .orange
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Helper Methods
    
    private func getWeeklyStepsData() -> [DayStepsData] {
        let calendar = Calendar.current
        let today = Date()
        var weeklyData: [DayStepsData] = []
        
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: today) ?? today
            let dayMetrics = healthMetrics.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let steps = dayMetrics.first?.stepCount ?? 0
            
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "E"
            let dayName = dayFormatter.string(from: date)
            
            weeklyData.append(DayStepsData(day: dayName, steps: Double(steps)))
        }
        
        return weeklyData.reversed()
    }
    
    private func getWeeklySleepData() -> [DaySleepData] {
        let calendar = Calendar.current
        let today = Date()
        var weeklyData: [DaySleepData] = []
        
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: today) ?? today
            let dayMetrics = healthMetrics.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let quality = dayMetrics.first?.sleepQuality ?? 0
            
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "E"
            let dayName = dayFormatter.string(from: date)
            
            weeklyData.append(DaySleepData(day: dayName, quality: Double(quality)))
        }
        
        return weeklyData.reversed()
    }
    
    private func getWeeklyWorkouts() -> [WorkoutLog] {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        
        return workouts.filter { $0.timestamp >= weekStart && $0.timestamp <= today }
    }
    
    private func getTrendInterpretation(_ trend: Double) -> String {
        if abs(trend) < 2 {
            return "Stable"
        } else if trend > 0 {
            return "Improving"
        } else {
            return "Declining"
        }
    }
    
    private func getStepRecommendation() -> String {
        let avgSteps = weeklyHealthSummary?.averageSteps ?? 0
        if avgSteps < 8000 {
            return "Try to increase daily steps by 1,000 for better health benefits"
        } else if avgSteps < 10000 {
            return "You're doing well! Aim for 10,000 steps daily"
        } else {
            return "Excellent step count! Maintain this level of activity"
        }
    }
    
    private func getSleepRecommendation() -> String {
        let avgSleep = weeklyHealthSummary?.averageSleepQuality ?? 0
        if avgSleep < 6 {
            return "Focus on improving sleep quality with a consistent bedtime routine"
        } else if avgSleep < 8 {
            return "Good sleep quality! Consider optimizing your sleep environment"
        } else {
            return "Excellent sleep quality! Keep up the good sleep habits"
        }
    }
    
    private func getActivityRecommendation() -> String {
        let activeMinutes = weeklyHealthSummary?.totalActiveMinutes ?? 0
        if activeMinutes < 150 {
            return "Aim for 150 minutes of moderate activity per week"
        } else if activeMinutes < 300 {
            return "Great activity level! Consider adding strength training"
        } else {
            return "Outstanding activity level! Focus on recovery and variety"
        }
    }
    
    private func workoutIcon(for type: String) -> String {
        switch type.lowercased() {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "swim": return "figure.pool.swim"
        case "strength": return "dumbbell"
        default: return "figure.mixed.cardio"
        }
    }
    
    private func workoutColor(for type: String) -> Color {
        switch type.lowercased() {
        case "run": return .orange
        case "walk": return .green
        case "bike": return .blue
        case "swim": return .cyan
        case "strength": return .red
        default: return .gray
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Views

struct TrendRow: View {
    let title: String
    let trend: Double
    let interpretation: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: trend >= 0 ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                        .foregroundColor(trend >= 0 ? .green : .red)
                    
                    Text(String(format: "%.1f%%", abs(trend)))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(trend >= 0 ? .green : .red)
                }
                
                Text(interpretation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}



// MARK: - Data Models

struct DayStepsData {
    let day: String
    let steps: Double
}

struct DaySleepData {
    let day: String
    let quality: Double
}

// MARK: - New Enhanced UI Components

struct HealthScoreFactorRow: View {
    let title: String
    let score: Int
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(score)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

struct EnhancedProgressRing: View {
    let title: String
    let value: String
    let goal: String
    let unit: String
    let color: Color
    let progress: Double
    let trend: Double
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 1) {
                    Text("\(value)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    if abs(trend) > 0.1 {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                            .foregroundColor(trend > 0 ? .green : .red)
                        
                        Text(String(format: "%.0f%%", abs(trend)))
                            .font(.caption2)
                            .foregroundColor(trend > 0 ? .green : .red)
                    } else {
                        Text("—")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EnhancedVitalCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let status: String
    let trend: Double
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
                
                Text(status)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Trend indicator
                HStack(spacing: 4) {
                    if abs(trend) > 0.1 {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2)
                            .foregroundColor(trend > 0 ? .green : .red)
                        
                        Text(String(format: "%.1f%%", abs(trend)))
                            .font(.caption2)
                            .foregroundColor(trend > 0 ? .green : .red)
                    } else {
                        Text("No change")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 2)
    }
    
    private var statusColor: Color {
        switch status {
        case "Excellent", "Athletic", "Superior", "Good": return .green
        case "Normal", "Average": return .blue
        case "Fair": return .orange
        case "No data": return .gray
        default: return .red
        }
    }
}

struct EnhancedActivityCard: View {
    let workout: WorkoutLog
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: workoutIcon)
                .font(.title2)
                .foregroundColor(workoutColor)
                .frame(width: 48, height: 48)
                .background(workoutColor.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(workout.workoutType.capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 16) {
                    if workout.distance > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.1f km", workout.distance))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Distance")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatTime(workout.duration))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Duration")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if workout.calories > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(workout.calories))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Calories")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var workoutIcon: String {
        switch workout.workoutType.lowercased() {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "swim": return "figure.pool.swim"
        case "strength": return "dumbbell.fill"
        case "hiit": return "timer"
        case "yoga": return "figure.flexibility"
        default: return "figure.mixed.cardio"
        }
    }
    
    private var workoutColor: Color {
        switch workout.workoutType.lowercased() {
        case "run": return .orange
        case "walk": return .green
        case "bike": return .blue
        case "swim": return .cyan
        case "strength": return .red
        case "hiit": return .purple
        case "yoga": return .mint
        default: return .gray
        }
    }
    
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(workout.timestamp)
        
        if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct AchievementCard: View {
    let achievement: Achievement
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.icon)
                .font(.title2)
                .foregroundColor(achievement.color)
                .frame(width: 44, height: 44)
                .background(achievement.color.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("🎉")
                .font(.title3)
        }
        .padding(16)
        .background(achievement.color.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(achievement.color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct EnhancedInsightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let trend: Double
    let icon: String
    let color: Color
    let recommendation: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                        .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                        .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 8) {
                            Text(value)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                        }
            }
            
            Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: trend >= 0 ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                                .foregroundColor(trend >= 0 ? .green : .red)
                            
                            Text(String(format: "%.1f%%", abs(trend)))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(trend >= 0 ? .green : .red)
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(recommendation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct Achievement {
    let title: String
    let description: String
    let icon: String
    let color: Color
}

struct ModernQuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.1))
        .cornerRadius(12)
                
                VStack(spacing: 2) {
                Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                    .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            
                Text(subtitle)
                    .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
        }
        .padding(32)
            .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
            .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Supporting Models



// MARK: - Supporting Views

struct InsightRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
                Image(systemName: icon)
                .font(.title3)
                    .foregroundColor(color)
                .frame(width: 24, height: 24)
                
                Text(title)
                .font(.subheadline)
                    .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Additional Views for Navigation

struct AllActivityView: View {
    var body: some View {
        Text("All Activities")
            .navigationTitle("All Activities")
    }
}

// MARK: - Blood Oxygen Detail View
struct BloodOxygenDetailView: View {
    let healthMetrics: HealthMetrics?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Blood Oxygen")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let metrics = healthMetrics, metrics.bloodOxygen > 0 {
                        Text("\(String(format: "%.0f", metrics.bloodOxygen))%")
                            .font(.title)
                            .foregroundColor(.blue)
                    } else {
                        Text("No data available")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Info Card
                VStack(alignment: .leading, spacing: 16) {
                    Text("About Blood Oxygen")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Blood oxygen saturation measures the percentage of oxygen in your blood. Normal levels are typically between 95-100%.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ranges:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Below 90%: Critical")
                                .font(.caption)
                        }
                        
                        HStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("90-95%: Low")
                                .font(.caption)
                        }
                        
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("95-100%: Normal")
                                .font(.caption)
                        }
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
            .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                Spacer()
        }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Respiratory Rate Detail View
struct RespiratoryRateDetailView: View {
    let healthMetrics: HealthMetrics?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Respiratory Rate")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let metrics = healthMetrics, metrics.respiratoryRate > 0 {
                        Text("\(String(format: "%.0f", metrics.respiratoryRate)) bpm")
                            .font(.title)
                            .foregroundColor(.cyan)
                    } else {
                        Text("No data available")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Info Card
                VStack(alignment: .leading, spacing: 16) {
                    Text("About Respiratory Rate")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Respiratory rate measures how many breaths you take per minute. Normal resting rates are typically between 12-20 breaths per minute.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ranges:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Below 12: Low")
                                .font(.caption)
                        }
                        
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("12-20: Normal")
                                .font(.caption)
                        }
                        
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Above 20: High")
                                .font(.caption)
                        }
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                Spacer()
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Enhanced Heart Rate Components

struct StatusIndicator: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct EnhancedHeartRateChartView: View {
    let readings: [HeartRateReading]
    let timeRange: HeartRateDetailView.TimeRange
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with zones
                HeartRateZoneBackground(geometry: geometry)
                
                // Heart rate line
                if !readings.isEmpty {
                    EnhancedHeartRateLineShape(readings: readings, geometry: geometry)
                        .stroke(Color.red, lineWidth: 3)
                    
                    // Average line
                    if readings.count > 1 {
                        AverageHeartRateLine(readings: readings, geometry: geometry)
                            .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                    
                    // Data points
                    ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
                        HeartRateDataPoint(reading: reading, index: index, total: readings.count, geometry: geometry)
                    }
                }
                
                // Y-axis labels
                VStack {
                    ForEach(0..<5) { i in
                        HStack {
                            Text("\(200 - i * 40)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        if i < 4 { Spacer() }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }
}

struct HeartRateZoneBackground: View {
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.red.opacity(0.1))
                .frame(height: geometry.size.height * 0.2)
            
            Rectangle()
                .fill(Color.orange.opacity(0.1))
                .frame(height: geometry.size.height * 0.2)
            
            Rectangle()
                .fill(Color.yellow.opacity(0.1))
                .frame(height: geometry.size.height * 0.2)
            
            Rectangle()
                .fill(Color.green.opacity(0.1))
                .frame(height: geometry.size.height * 0.2)
            
            Rectangle()
                .fill(Color.blue.opacity(0.1))
                .frame(height: geometry.size.height * 0.2)
        }
    }
}

struct EnhancedHeartRateLineShape: Shape {
    let readings: [HeartRateReading]
    let geometry: GeometryProxy
    
    func path(in rect: CGRect) -> Path {
        guard !readings.isEmpty else { return Path() }
        
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        for (index, reading) in readings.enumerated() {
            let x = width * CGFloat(index) / CGFloat(max(readings.count - 1, 1))
            let normalizedHR = CGFloat(Int(reading.heartRate) - 60) / CGFloat(140) // 60-200 range
            let y = height * (1 - max(0, min(1, normalizedHR)))
            
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}

struct AverageHeartRateLine: Shape {
    let readings: [HeartRateReading]
    let geometry: GeometryProxy
    
    func path(in rect: CGRect) -> Path {
        guard !readings.isEmpty else { return Path() }
        
        let averageHR = readings.reduce(0) { $0 + Int($1.heartRate) } / readings.count
        let normalizedHR = CGFloat(averageHR - 60) / CGFloat(140)
        let y = rect.height * (1 - max(0, min(1, normalizedHR)))
        
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: rect.width, y: y))
        
        return path
    }
}

struct HeartRateDataPoint: View {
    let reading: HeartRateReading
    let index: Int
    let total: Int
    let geometry: GeometryProxy
    
    var body: some View {
        let x = geometry.size.width * CGFloat(index) / CGFloat(max(total - 1, 1))
        let normalizedHR = CGFloat(Int(reading.heartRate) - 60) / CGFloat(140)
        let y = geometry.size.height * (1 - max(0, min(1, normalizedHR)))
        
        Circle()
            .fill(contextColor(for: reading.context))
            .frame(width: 6, height: 6)
            .position(x: x, y: y)
    }
    
    private func contextColor(for context: String?) -> Color {
        switch context {
        case "resting": return .green
        case "active": return .blue
        case "elevated": return .orange
        case "workout": return .red
        default: return .gray
        }
    }
}

struct HeartRateZoneData {
    let zone: String
    let range: String
    let percentage: Double
    let color: Color
    let timeSpent: Int
    let description: String
}

struct EnhancedHeartRateZoneRow: View {
    let zone: String
    let range: String
    let percentage: Double
    let color: Color
    let timeSpent: Int
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Zone color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 8, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(zone)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(String(format: "%.1f%%", percentage))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(color)
                }
                
                HStack {
                    Text(range)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(timeSpent) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct RestingHRTrendCard: View {
    let title: String
    let value: Int
    let trend: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .bottom, spacing: 4) {
                Text("\(value)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text("bpm")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 2)
            }
            
            if trend != 0 {
                HStack(spacing: 4) {
                    Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption2)
                        .foregroundColor(trend > 0 ? .red : .green)
                    
                    Text(String(format: "%.1f%%", abs(trend)))
                        .font(.caption2)
                        .foregroundColor(trend > 0 ? .red : .green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TrainingInsightRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.vertical, 4)
    }
}

struct ComparisonRow: View {
    let title: String
    let value: String
    let comparison: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            
            Text(comparison)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

struct AnalyticsCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct HeartRateRecommendation {
    let id: String
    let icon: String
    let title: String
    let description: String
    let priority: Priority
    let color: Color
    
    enum Priority {
        case high, medium, low
    }
}

struct RecommendationCard: View {
    let icon: String
    let title: String
    let description: String
    let priority: HeartRateRecommendation.Priority
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    priorityBadge
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(color.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var priorityBadge: some View {
        Text(priorityText)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(6)
    }
    
    private var priorityText: String {
        switch priority {
        case .high: return "HIGH"
        case .medium: return "MED"
        case .low: return "LOW"
        }
    }
}

struct HeartRateTrendsView: View {
    let healthMetrics: [HealthMetrics]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("30-Day Heart Rate Trends")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Trend chart would go here
                    VStack {
                        Text("Historical trends chart")
                        Text("Coming soon...")
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HR Trends")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

#Preview {
    HealthDashboardView()
        .environmentObject(HealthKitService(context: PersistenceController.preview.container.viewContext))
        .environmentObject(AIService(context: PersistenceController.preview.container.viewContext, apiKey: ""))
        .environmentObject(AnalyticsService(context: PersistenceController.preview.container.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 


