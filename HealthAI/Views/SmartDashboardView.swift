import SwiftUI
import CoreData
import Combine

struct SmartDashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var healthKitService: HealthKitService
    @ObservedObject private var userProfile = UserProfileManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        predicate: NSPredicate(format: "date >= %@", Calendar.current.startOfDay(for: Date()) as NSDate),
        animation: .default)
    private var todaysMetrics: FetchedResults<HealthMetrics>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        animation: .default)
    private var allMetrics: FetchedResults<HealthMetrics>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)],
        animation: .default)
    private var workouts: FetchedResults<WorkoutLog>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HeartRateReading.timestamp, ascending: false)],
        animation: .default)
    private var heartRateReadings: FetchedResults<HeartRateReading>
    
    // Customization - persisted
    @AppStorage("showActivityCard") private var showActivityCard = true
    @AppStorage("showSleepCard") private var showSleepCard = true
    @AppStorage("showHeartCard") private var showHeartCard = true
    @AppStorage("showVitalsCard") private var showVitalsCard = true
    @AppStorage("showWeeklyCard") private var showWeeklyCard = true
    
    @State private var showingCustomization = false
    @State private var showingSleepDetail = false
    @State private var showingVitalsDetail = false
    @State private var refreshTrigger = false
    @State private var isLoading = false
    @State private var lastRefreshTime = Date()
    @State private var refreshTimer: Timer?
    
    // Navigation state for metric detail views (atomic to avoid blank destination)
    private struct MetricDestination: Identifiable, Hashable {
        let id: UUID
        let kind: HealthMetricDetailView.MetricKind
        let context: HealthMetricDetailView.MetricContext
        
        init(kind: HealthMetricDetailView.MetricKind, context: HealthMetricDetailView.MetricContext, id: UUID = UUID()) {
            self.id = id
            self.kind = kind
            self.context = context
        }
        
        static func == (lhs: MetricDestination, rhs: MetricDestination) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    @State private var metricDestination: MetricDestination?
    
    // New detail sheets
    @State private var showingHealthScoreDetail = false
    @State private var showingActivityDetail = false
    @State private var showingBatteryDetail = false
    @State private var showingStressDetail = false
    @State private var selectedWorkout: WorkoutLog?
    
    private var metrics: HealthMetrics? { todaysMetrics.first }
    
    // Overall health score calculation
    private var overallHealthScore: Int {
        calculateOverallScore()
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerSection
                        overallScoreCard
                        
                        if showActivityCard { activityCard }
                        if showSleepCard { sleepCard }
                        if showHeartCard { enhancedHeartCard }
                        if showVitalsCard { enhancedVitalsCard }
                        if showWeeklyCard { weeklyOverviewCard }
                        
                        recentWorkoutsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $metricDestination) { dest in
                HealthMetricDetailView(kind: dest.kind, context: dest.context)
            }
            .refreshable { await refreshData() }
            .task { await setupDashboard() }
            .onDisappear { stopAutoRefresh() }
            .onChange(of: scenePhase) { handleScenePhaseChange($0) }
            .sheet(isPresented: $showingCustomization) {
                DashboardCustomizationSheet(
                    showActivityCard: $showActivityCard,
                    showSleepCard: $showSleepCard,
                    showHeartCard: $showHeartCard,
                    showVitalsCard: $showVitalsCard,
                    showWeeklyCard: $showWeeklyCard
                )
            }
            .sheet(isPresented: $showingSleepDetail) {
                SleepDetailSheet(metrics: metrics, allMetrics: Array(allMetrics))
            }
            .sheet(isPresented: $showingVitalsDetail) {
                VitalsDetailSheet(metrics: metrics, allMetrics: Array(allMetrics))
            }
            .sheet(isPresented: $showingHealthScoreDetail) {
                HealthScoreDetailSheet(
                    overallScore: overallHealthScore,
                    activityScore: activityScore,
                    sleepScore: sleepScore,
                    heartScore: heartScore,
                    recoveryScore: recoveryScore,
                    metrics: metrics,
                    allMetrics: Array(allMetrics)
                )
            }
            .sheet(isPresented: $showingActivityDetail) {
                ActivityDetailSheet(
                    metrics: metrics,
                    allMetrics: Array(allMetrics),
                    workouts: Array(workouts)
                )
            }
            .sheet(item: $selectedWorkout) { workout in
                EnhancedWorkoutDetailSheet(workout: workout, allMetrics: Array(allMetrics))
            }
            .sheet(isPresented: $showingBatteryDetail) {
                BatteryDetailSheet(
                    batteryLevel: dailyBatteryLevel,
                    metrics: metrics,
                    allMetrics: Array(allMetrics)
                )
            }
            .sheet(isPresented: $showingStressDetail) {
                StressDetailSheet(
                    stressLevel: stressLevel,
                    metrics: metrics,
                    allMetrics: Array(allMetrics)
                )
            }
        }
    }
    
    private func refreshData() async {
        isLoading = true
        await healthKitService.forceRefreshTodaysMetrics()
        await healthKitService.syncRecentWorkouts()
        await healthKitService.updateRecoveryScores()
        lastRefreshTime = Date()
        refreshTrigger.toggle()
        isLoading = false
    }
    
    private func setupDashboard() async {
        await healthKitService.refreshAuthorizationStatus()
        await refreshData()
        startAutoRefresh()
    }
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { await refreshData() }
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
                if Date().timeIntervalSince(lastRefreshTime) > 30 {
                    await refreshData()
                }
            }
            startAutoRefresh()
        case .background:
            stopAutoRefresh()
        default:
            break
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                HStack(spacing: 6) {
                    Text(dateString)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                // Refresh button
                Button {
                    Task { await refreshData() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                }
                .disabled(isLoading)
                
                // Customize button
                Button { showingCustomization = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                }
            }
        }
    }
    
    // MARK: - Overall Score Card
    private var overallScoreCard: some View {
        let score = overallHealthScore
        let (label, color) = scoreLabel(score)
        
        return Button { showingHealthScoreDetail = true } label: {
            VStack(spacing: 16) {
                HStack {
                    Text("Health Score")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(color.opacity(0.12))
                            .clipShape(Capsule())
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    }
                }
                
                HStack(spacing: 24) {
                    // Main Score Ring
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.15), lineWidth: 14)
                            .frame(width: 100, height: 100)
                        
                        Circle()
                            .trim(from: 0, to: Double(score) / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 0) {
                            Text("\(score)")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                            
                            Text("/ 100")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                        }
                    }
                    
                    // Score Breakdown
                    VStack(alignment: .leading, spacing: 10) {
                        scoreBreakdownRow("Activity", icon: "figure.walk", score: activityScore, color: Color(hex: "FF6B6B"))
                        scoreBreakdownRow("Sleep", icon: "moon.fill", score: sleepScore, color: Color(hex: "8B5CF6"))
                        scoreBreakdownRow("Heart", icon: "heart.fill", score: heartScore, color: Color(hex: "EF4444"))
                        scoreBreakdownRow("Recovery", icon: "arrow.counterclockwise", score: recoveryScore, color: Color(hex: "10B981"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Daily Battery & Stress Level Section
                HStack(spacing: 12) {
                    // Daily Battery Card (tappable)
                    Button { showingBatteryDetail = true } label: {
                        dailyBatteryCard
                    }
                    .buttonStyle(.plain)
                    
                    // Stress Level Card (tappable)
                    Button { showingStressDetail = true } label: {
                        stressLevelCard
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [color.opacity(0.12), color.opacity(0.04)]
                                : [color.opacity(0.08), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(color.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func scoreBreakdownRow(_ label: String, icon: String, score: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
            
            Spacer()
            
            Text("\(score)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            // Mini bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(width: 40, height: 4)
        }
    }
    
    // MARK: - Daily Battery
    private var dailyBatteryLevel: Int {
        // Calculate battery based on energy level from metrics, time of day, and activity
        let baseEnergy = Int(metrics?.energyLevel ?? 0)
        
        // If we have energy data from HealthKit/metrics, use it
        if baseEnergy > 0 {
            return baseEnergy * 10 // Convert 1-10 to percentage
        }
        
        // Otherwise estimate based on time of day, sleep, and activity
        let hour = Calendar.current.component(.hour, from: Date())
        let sleepHours = metrics?.sleepHours ?? 7
        let activeCalories = metrics?.activeCalories ?? 0
        let steps = Int(metrics?.stepCount ?? 0)
        
        // Start with sleep quality bonus
        var battery = min(100, Int(sleepHours / 8.0 * 100))
        
        // Deplete based on time awake (assuming wake up around 7am)
        let hoursAwake = max(0, hour - 7)
        let depletionPerHour = 4 // Natural depletion
        battery -= hoursAwake * depletionPerHour
        
        // Additional depletion from activity
        let activityDepletion = Int(activeCalories / 50) + (steps / 2000)
        battery -= activityDepletion
        
        // Recovery boost from good HRV
        if let hrv = metrics?.hrv, hrv > 50 {
            battery += 10
        }
        
        return max(5, min(100, battery))
    }
    
    private var batteryColor: Color {
        switch dailyBatteryLevel {
        case 70...100: return Color(hex: "10B981") // Green - charged
        case 40...69: return Color(hex: "F59E0B")  // Amber - moderate
        case 20...39: return Color(hex: "F97316")  // Orange - low
        default: return Color(hex: "EF4444")       // Red - critical
        }
    }
    
    private var batteryLabel: String {
        switch dailyBatteryLevel {
        case 80...100: return "Fully Charged"
        case 60...79: return "Good Energy"
        case 40...59: return "Moderate"
        case 20...39: return "Low Energy"
        default: return "Recharge"
        }
    }
    
    private var dailyBatteryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(batteryColor)
                Text("Daily Battery")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "6B6B6B"))
            }
            
            // Battery Visualization
            HStack(spacing: 8) {
                // Battery Icon with fill level
                ZStack(alignment: .leading) {
                    // Battery outline
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(batteryColor.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 36, height: 18)
                    
                    // Battery fill
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [batteryColor, batteryColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, 32 * CGFloat(dailyBatteryLevel) / 100), height: 12)
                        .padding(.leading, 2)
                    
                    // Battery cap
                    RoundedRectangle(cornerRadius: 1)
                        .fill(batteryColor.opacity(0.4))
                        .frame(width: 3, height: 8)
                        .offset(x: 37)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(dailyBatteryLevel)%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text(batteryLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(batteryColor)
                }
            }
            
            // Depletion indicator
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(batteryColor.opacity(0.15))
                        .frame(height: 6)
                    
                    // Fill with gradient
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [batteryColor, batteryColor.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(dailyBatteryLevel) / 100, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [batteryColor.opacity(0.12), batteryColor.opacity(0.04)]
                            : [batteryColor.opacity(0.08), Color.white.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(batteryColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Stress Level
    private var stressLevel: Int {
        // Get stress from metrics if available
        let metricStress = Int(metrics?.stressLevel ?? 0)
        
        if metricStress > 0 {
            return metricStress * 10 // Convert 1-10 to percentage
        }
        
        // Estimate stress from HRV and heart rate
        let hrv = metrics?.hrv ?? 0
        let restingHR = Int(metrics?.restingHeartRate ?? 0)
        let sleepHours = metrics?.sleepHours ?? 7
        
        var estimatedStress = 30 // Base stress level
        
        // Lower HRV = higher stress
        if hrv > 0 {
            if hrv < 25 { estimatedStress += 40 }
            else if hrv < 40 { estimatedStress += 25 }
            else if hrv < 50 { estimatedStress += 10 }
            else { estimatedStress -= 10 }
        }
        
        // Higher resting HR = higher stress
        if restingHR > 0 {
            if restingHR > 80 { estimatedStress += 20 }
            else if restingHR > 70 { estimatedStress += 10 }
            else if restingHR < 60 { estimatedStress -= 10 }
        }
        
        // Poor sleep = higher stress
        if sleepHours < 6 { estimatedStress += 15 }
        else if sleepHours > 7 { estimatedStress -= 10 }
        
        return max(0, min(100, estimatedStress))
    }
    
    private var stressColor: Color {
        switch stressLevel {
        case 0...25: return Color(hex: "10B981")   // Green - calm
        case 26...50: return Color(hex: "3B82F6")  // Blue - low stress
        case 51...70: return Color(hex: "F59E0B")  // Amber - moderate
        case 71...85: return Color(hex: "F97316")  // Orange - elevated
        default: return Color(hex: "EF4444")       // Red - high
        }
    }
    
    private var stressLabel: String {
        switch stressLevel {
        case 0...25: return "Calm"
        case 26...50: return "Relaxed"
        case 51...70: return "Moderate"
        case 71...85: return "Elevated"
        default: return "High"
        }
    }
    
    private var stressIcon: String {
        switch stressLevel {
        case 0...25: return "leaf.fill"
        case 26...50: return "wind"
        case 51...70: return "cloud.fill"
        case 71...85: return "cloud.bolt.fill"
        default: return "bolt.horizontal.fill"
        }
    }
    
    private var stressLevelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(stressColor)
                Text("Stress Level")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "6B6B6B"))
            }
            
            // Stress Gauge
            HStack(spacing: 10) {
                // Mini arc gauge
                ZStack {
                    // Background arc
                    Circle()
                        .trim(from: 0.25, to: 0.75)
                        .stroke(
                            stressColor.opacity(0.15),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(90))
                    
                    // Progress arc
                    Circle()
                        .trim(from: 0.25, to: 0.25 + (0.5 * CGFloat(stressLevel) / 100))
                        .stroke(
                            AngularGradient(
                                colors: [stressColor.opacity(0.6), stressColor],
                                center: .center,
                                startAngle: .degrees(180),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(90))
                    
                    // Center icon
                    Image(systemName: stressIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(stressColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(stressLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text("\(stressLevel)% stress")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(stressColor)
                }
            }
            
            // Stress level bar with gradient zones
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Multi-color track showing zones
                    HStack(spacing: 0) {
                        Color(hex: "10B981").opacity(0.3)
                            .frame(width: geo.size.width * 0.25)
                        Color(hex: "3B82F6").opacity(0.3)
                            .frame(width: geo.size.width * 0.25)
                        Color(hex: "F59E0B").opacity(0.3)
                            .frame(width: geo.size.width * 0.25)
                        Color(hex: "EF4444").opacity(0.3)
                            .frame(width: geo.size.width * 0.25)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    
                    // Position indicator
                    Circle()
                        .fill(stressColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: stressColor.opacity(0.5), radius: 3, x: 0, y: 0)
                        .offset(x: max(0, min(geo.size.width - 10, geo.size.width * CGFloat(stressLevel) / 100 - 5)))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [stressColor.opacity(0.12), stressColor.opacity(0.04)]
                            : [stressColor.opacity(0.08), Color.white.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(stressColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Activity Card (tappable)
    private var activityCard: some View {
        let steps = Int(metrics?.stepCount ?? 0)
        let calories = Int(metrics?.activeCalories ?? 0)
        let distance = metrics?.totalDistance ?? 0
        let activeMinutes = Int(metrics?.activeMinutes ?? 0)
        
        // Use goals from centralized UserProfileManager
        let stepGoal = userProfile.dailyStepGoal
        let calorieGoal = Int(userProfile.dailyCalorieGoal)
        let distanceGoal = 5.0
        let activeMinuteGoal = 30
        
        return Button { showingActivityDetail = true } label: {
            VStack(spacing: 18) {
                HStack {
                    Text("Activity")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Today")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
                
                HStack(spacing: 16) {
                    activityRing(progress: Double(steps) / Double(stepGoal), value: formatNumber(steps), label: "Steps", color: Color(hex: "FF6B6B"))
                    
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            activityStat(icon: "flame.fill", value: "\(calories)", unit: "kcal", progress: Double(calories) / Double(calorieGoal), color: Color(hex: "F59E0B"))
                            activityStat(icon: "figure.walk", value: String(format: "%.1f", distance), unit: "km", progress: distance / distanceGoal, color: Color(hex: "10B981"))
                        }
                        HStack(spacing: 12) {
                            activityStat(icon: "clock.fill", value: "\(activeMinutes)", unit: "min", progress: Double(activeMinutes) / Double(activeMinuteGoal), color: Color(hex: "3B82F6"))
                            activityStat(icon: "figure.run", value: "\(metrics?.workoutCount ?? 0)", unit: "workouts", progress: Double(metrics?.workoutCount ?? 0) / 2.0, color: Color(hex: "8B5CF6"))
                        }
                    }
                }
            }
            .padding(20)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }
    
    private func activityRing(progress: Double, value: String, label: String, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(colorScheme == .dark ? 0.15 : 0.12), lineWidth: 12)
                .frame(width: 110, height: 110)
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
    }
    
    private func activityStat(icon: String, value: String, unit: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * min(progress, 1.0), height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(colorScheme == .dark ? 0.08 : 0.06)))
    }
    
    // MARK: - Enhanced Sleep Card
    private var sleepCard: some View {
        let sleepHours = metrics?.sleepHours ?? 0
        let deepSleep = metrics?.deepSleepHours ?? 0
        let remSleep = metrics?.remSleepHours ?? 0
        let timeInBed = metrics?.timeInBed ?? 0
        let score = calculateSleepScore(totalSleep: sleepHours, deepSleep: deepSleep, remSleep: remSleep, timeInBed: timeInBed)
        let lightSleep = max(0, sleepHours - deepSleep - remSleep)
        let efficiency = timeInBed > 0 ? (sleepHours / timeInBed) * 100 : 0
        
        return Button { showingSleepDetail = true } label: {
            VStack(spacing: 18) {
                HStack {
                    Text("Sleep")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    Spacer()
                    HStack(spacing: 4) {
                        Text("See Details")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "8B5CF6"))
                }
                
                if sleepHours > 0 {
                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .stroke(Color(hex: "8B5CF6").opacity(0.15), lineWidth: 10)
                                .frame(width: 90, height: 90)
                            Circle()
                                .trim(from: 0, to: Double(score) / 100)
                                .stroke(sleepScoreColor(score), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .frame(width: 90, height: 90)
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(score)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                                Text("Score")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            sleepRow(label: "Total", value: formatHours(sleepHours), color: sleepHours >= 7 ? Color(hex: "10B981") : Color(hex: "F59E0B"))
                            sleepRow(label: "Deep", value: formatHours(deepSleep), color: Color(hex: "3B82F6"))
                            sleepRow(label: "REM", value: formatHours(remSleep), color: Color(hex: "8B5CF6"))
                            sleepRow(label: "Efficiency", value: "\(Int(efficiency))%", color: efficiency >= 85 ? Color(hex: "10B981") : Color(hex: "F59E0B"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Sleep stages bar
                    sleepStagesBar(deep: deepSleep, rem: remSleep, light: lightSleep, total: sleepHours)
                } else {
                    emptyStateView(icon: "moon.zzz.fill", title: "No sleep data", subtitle: "Sync from Apple Watch")
                }
            }
            .padding(20)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }
    
    private func sleepRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
    }
    
    private func sleepStagesBar(deep: Double, rem: Double, light: Double, total: Double) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if deep > 0 {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: "3B82F6")).frame(width: geo.size.width * (deep / total))
                }
                if rem > 0 {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: "8B5CF6")).frame(width: geo.size.width * (rem / total))
                }
                if light > 0 {
                    RoundedRectangle(cornerRadius: 4).fill(Color(hex: "06B6D4")).frame(width: geo.size.width * (light / total))
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    // MARK: - Heart Card (Basic - kept for compatibility)
    private var heartCard: some View {
        let restingHR = Int(metrics?.restingHeartRate ?? 0)
        let hrv = Int(metrics?.hrv ?? 0)
        
        return VStack(spacing: 18) {
            HStack {
                Text("Heart")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
            }
            
            if restingHR > 0 || hrv > 0 {
                HStack(spacing: 12) {
                    heartMetricCard(icon: "heart.fill", title: "Resting HR", value: restingHR > 0 ? "\(restingHR)" : "—", unit: "bpm", status: heartRateStatus(restingHR), color: Color(hex: "EF4444"))
                    heartMetricCard(icon: "waveform.path.ecg", title: "HRV", value: hrv > 0 ? "\(hrv)" : "—", unit: "ms", status: hrvStatus(hrv), color: Color(hex: "8B5CF6"))
                }
            } else {
                emptyStateView(icon: "heart.fill", title: "No heart data", subtitle: "Wear Apple Watch to track")
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    // MARK: - Enhanced Heart Card with Live HR and Trends
    private var enhancedHeartCard: some View {
        let restingHR = Int(metrics?.restingHeartRate ?? 0)
        let hrv = Int(metrics?.hrv ?? 0)
        let liveHR = latestHeartRateReading ?? restingHR
        
        return VStack(spacing: 18) {
            HStack {
                Text("Heart")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                
                // Live indicator
                if latestHeartRateReading != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "EF4444"))
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "EF4444"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "EF4444").opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            
            if restingHR > 0 || hrv > 0 || liveHR > 0 {
                // Live HR Card (tappable)
                Button {
                    presentDetail(kind: .heartRate, context: liveHeartRateContext)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bolt.heart.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(hex: "F472B6"))
                            Text("Live Heart Rate")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                        }
                        
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text("\(liveHR)")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                            Text("bpm")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                            
                            Spacer()
                            
                            // Mini sparkline
                            if !heartRateDayHistory.isEmpty {
                                SparklineChart(
                                    data: heartRateDayHistory.suffix(20).map { $0 },
                                    lineColor: Color(hex: "F472B6"),
                                    fillGradient: LinearGradient(
                                        colors: [Color(hex: "F472B6").opacity(0.2), Color(hex: "F472B6").opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 80, height: 30)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "F472B6").opacity(colorScheme == .dark ? 0.1 : 0.06))
                    )
                }
                .buttonStyle(.plain)
                
                // Resting HR and HRV row
                HStack(spacing: 12) {
                    Button {
                        presentDetail(kind: .heartRate, context: heartRateContext)
                    } label: {
                        heartMetricCardEnhanced(
                            icon: "heart.fill",
                            title: "Resting HR",
                            value: restingHR > 0 ? "\(restingHR)" : "—",
                            unit: "bpm",
                            status: heartRateStatus(restingHR),
                            color: Color(hex: "EF4444"),
                            trend: heartRateTrend,
                            history: heartRateHistory
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        presentDetail(kind: .hrv, context: hrvContext)
                    } label: {
                        heartMetricCardEnhanced(
                            icon: "waveform.path.ecg",
                            title: "HRV",
                            value: hrv > 0 ? "\(hrv)" : "—",
                            unit: "ms",
                            status: hrvStatus(hrv),
                            color: Color(hex: "8B5CF6"),
                            trend: hrvTrend,
                            history: hrvHistory
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                emptyStateView(icon: "heart.fill", title: "No heart data", subtitle: "Wear Apple Watch to track")
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func heartMetricCardEnhanced(icon: String, title: String, value: String, unit: String, status: String, color: Color, trend: Double, history: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(color)
                Spacer()
                if trend != 0 {
                    trendBadge(trend: trend)
                }
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Text(unit).font(.system(size: 11, weight: .medium)).foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            if !history.isEmpty {
                SparklineChart(
                    data: history,
                    lineColor: color,
                    fillGradient: LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 24)
            }
            
            HStack {
                Text(title).font(.system(size: 10, weight: .medium)).foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                Spacer()
                Text(status)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(statusColor(status))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.04) : color.opacity(0.04)))
    }
    
    private func trendBadge(trend: Double) -> some View {
        let direction = trend > 0 ? "arrow.up.right" : "arrow.down.right"
        let trendColor = trend > 0 ? Color(hex: "34D399") : Color(hex: "EF4444")
        
        return HStack(spacing: 3) {
            Image(systemName: direction)
                .font(.system(size: 8, weight: .bold))
            Text(String(format: "%.0f%%", abs(trend)))
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(trendColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(trendColor.opacity(colorScheme == .dark ? 0.15 : 0.1)))
    }
    
    private func heartMetricCard(icon: String, title: String, value: String, unit: String, status: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(color)
                Spacer()
                Text(status)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(statusColor(status))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.12))
                    .clipShape(Capsule())
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 26, weight: .bold)).foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Text(unit).font(.system(size: 12, weight: .medium)).foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.04) : color.opacity(0.04)))
    }
    
    // MARK: - Vitals Card (Apple Watch metrics only)
    private var vitalsCard: some View {
        let bloodOxygen = Int(metrics?.bloodOxygen ?? 0)
        let respiratoryRate = metrics?.respiratoryRate ?? 0
        let vo2Max = metrics?.vo2Max ?? 0
        let recovery = metrics?.recoveryScore ?? 0
        
        return Button { showingVitalsDetail = true } label: {
            VStack(spacing: 18) {
                HStack {
                    Text("Vitals")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    Spacer()
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "3B82F6"))
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    vitalMiniCard(icon: "lungs.fill", value: bloodOxygen > 0 ? "\(bloodOxygen)%" : "—", label: "SpO₂", color: Color(hex: "3B82F6"))
                    vitalMiniCard(icon: "wind", value: respiratoryRate > 0 ? "\(Int(respiratoryRate))" : "—", label: "Resp", color: Color(hex: "06B6D4"))
                    vitalMiniCard(icon: "bolt.heart.fill", value: vo2Max > 0 ? String(format: "%.0f", vo2Max) : "—", label: "VO₂ Max", color: Color(hex: "10B981"))
                }
            }
            .padding(20)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Enhanced Vitals Card with Trends
    private var enhancedVitalsCard: some View {
        let bloodOxygen = Int(metrics?.bloodOxygen ?? 0)
        let respiratoryRate = metrics?.respiratoryRate ?? 0
        let vo2Max = metrics?.vo2Max ?? 0
        let recovery = metrics?.recoveryScore ?? 0
        
        return VStack(spacing: 18) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    Text("Vitals")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                }
                Spacer()
                Button {
                    showingVitalsDetail = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Details")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "3B82F6"))
                }
            }
            
            // Recovery Score Card
            Button {
                presentDetail(kind: .hrv, context: recoveryContext)
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(recoveryColor.opacity(0.15), lineWidth: 8)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: Double(Int(recovery)) / 100)
                            .stroke(recoveryColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(recovery))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery Score")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        Text(recoveryStatus)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(recoveryColor)
                    }
                    
                    Spacer()
                    
                    if !recoveryHistory.isEmpty {
                        SparklineChart(
                            data: recoveryHistory,
                            lineColor: recoveryColor,
                            fillGradient: LinearGradient(
                                colors: [recoveryColor.opacity(0.2), recoveryColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 60, height: 28)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(recoveryColor.opacity(colorScheme == .dark ? 0.08 : 0.05))
                )
            }
            .buttonStyle(.plain)
            
            // Vitals Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button {
                    presentDetail(kind: .bloodOxygen, context: bloodOxygenContext)
                } label: {
                    vitalCardEnhanced(
                        icon: "drop.fill",
                        title: "Blood Oxygen",
                        value: bloodOxygen > 0 ? "\(bloodOxygen)" : "—",
                        unit: "%",
                        status: bloodOxygenStatus,
                        color: Color(hex: "3B82F6"),
                        history: bloodOxygenHistory
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    presentDetail(kind: .respiratoryRate, context: respiratoryContext)
                } label: {
                    vitalCardEnhanced(
                        icon: "wind",
                        title: "Respiratory",
                        value: respiratoryRate > 0 ? "\(Int(respiratoryRate))" : "—",
                        unit: "rpm",
                        status: respiratoryStatus,
                        color: Color(hex: "06B6D4"),
                        history: respiratoryHistory
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    presentDetail(kind: .vo2Max, context: vo2Context)
                } label: {
                    vitalCardEnhanced(
                        icon: "lungs.fill",
                        title: "VO₂ Max",
                        value: vo2Max > 0 ? String(format: "%.0f", vo2Max) : "—",
                        unit: "ml/kg/min",
                        status: vo2MaxStatus,
                        color: Color(hex: "10B981"),
                        history: vo2History
                    )
                }
                .buttonStyle(.plain)
                
                // Total Calories Card
                let totalCal = Int(metrics?.totalCalories ?? 0)
                vitalCardEnhanced(
                    icon: "flame.fill",
                    title: "Total Calories",
                    value: totalCal > 0 ? "\(totalCal)" : "—",
                    unit: "kcal",
                    status: totalCal >= 2000 ? "Good" : "Low",
                    color: Color(hex: "F59E0B"),
                    history: totalCaloriesHistory
                )
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func vitalCardEnhanced(icon: String, title: String, value: String, unit: String, status: String, color: Color, history: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                Text(status)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(statusColor(status))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(statusColor(status).opacity(0.12))
                    .clipShape(Capsule())
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Text(unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            if !history.isEmpty {
                SparklineChart(
                    data: history,
                    lineColor: color,
                    fillGradient: LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 20)
            }
            
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : color.opacity(0.04))
        )
    }
    
    // MARK: - Recent Workouts Card
    private var recentWorkoutsCard: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
            }
            
            if workouts.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "figure.walk.circle")
                        .font(.system(size: 24))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No workouts yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                        Text("Start a workout to track your progress")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    }
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(workouts.prefix(3).enumerated()), id: \.element.id) { index, workout in
                        Button {
                            selectedWorkout = workout
                        } label: {
                            workoutRowContent(workout, showDivider: index < min(workouts.count - 1, 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func workoutRowContent(_ workout: WorkoutLog, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(workoutColor(workout.workoutType).opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: workoutIcon(workout.workoutType))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(workoutColor(workout.workoutType))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.workoutType.capitalized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    Text(relativeTimeString(workout.timestamp))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f km", workout.distance))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    Text("\(Int(workout.calories)) kcal")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
            }
            .padding(.vertical, 12)
            
            if showDivider {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .frame(height: 1)
                    .padding(.leading, 54)
            }
        }
    }
    
    private func workoutIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "run", "running": return "figure.run"
        case "walk", "walking": return "figure.walk"
        case "bike", "cycling": return "bicycle"
        case "strength", "weight": return "dumbbell.fill"
        case "swim", "swimming": return "figure.pool.swim"
        case "yoga": return "figure.yoga"
        default: return "figure.mixed.cardio"
        }
    }
    
    private func workoutColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "run", "running": return Color(hex: "E07A5F")
        case "walk", "walking": return Color(hex: "10B981")
        case "bike", "cycling": return Color(hex: "3B82F6")
        case "strength", "weight": return Color(hex: "8B5CF6")
        case "swim", "swimming": return Color(hex: "06B6D4")
        case "yoga": return Color(hex: "F472B6")
        default: return Color(hex: "6B7280")
        }
    }
    
    private func relativeTimeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func vitalMiniCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(colorScheme == .dark ? 0.1 : 0.06)))
    }
    
    // MARK: - Weekly Overview Card
    private var weeklyOverviewCard: some View {
        let last7Days = getLast7DaysMetrics()
        
        return VStack(spacing: 18) {
            HStack {
                Text("This Week")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
            }
            
            HStack(spacing: 16) {
                weeklyStatCard(title: "Avg Steps", value: formatNumber(averageSteps(last7Days)), trend: stepsTrend(last7Days), icon: "figure.walk")
                weeklyStatCard(title: "Avg Sleep", value: formatHours(averageSleep(last7Days)), trend: sleepTrend(last7Days), icon: "moon.fill")
                weeklyStatCard(title: "Avg HR", value: "\(averageRestingHR(last7Days))", trend: hrTrend(last7Days), icon: "heart.fill")
            }
            
            if !last7Days.isEmpty { dailyActivityBars(last7Days) }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func weeklyStatCard(title: String, value: String, trend: (direction: String, percent: Int), icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(Color(hex: "E07A5F"))
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            if trend.percent != 0 {
                HStack(spacing: 2) {
                    Image(systemName: trend.direction == "up" ? "arrow.up" : "arrow.down").font(.system(size: 8, weight: .bold))
                    Text("\(abs(trend.percent))%").font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(trend.direction == "up" ? Color(hex: "10B981") : Color(hex: "EF4444"))
            }
            Text(title).font(.system(size: 10, weight: .medium)).foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color(hex: "E07A5F").opacity(0.04)))
    }
    
    private func dailyActivityBars(_ metrics: [HealthMetrics]) -> some View {
        let maxSteps = max(metrics.map { Int($0.stepCount) }.max() ?? userProfile.dailyStepGoal, userProfile.dailyStepGoal)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(metrics.reversed(), id: \.id) { metric in
                let steps = Int(metric.stepCount)
                let height = maxSteps > 0 ? CGFloat(steps) / CGFloat(maxSteps) * 60 : 0
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isToday(metric.date) ? Color(hex: "E07A5F") : Color(hex: "E07A5F").opacity(0.4))
                        .frame(height: max(height, 4))
                    Text(dayAbbreviation(metric.date))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isToday(metric.date) ? (colorScheme == .dark ? .white : Color(hex: "1A1A1A")) : (colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF")))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80)
    }
    
    // MARK: - Helpers
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04), lineWidth: 1))
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
    
    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            Text(subtitle).font(.system(size: 12, weight: .regular)).foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    // MARK: - Score Calculations
    
    private var activityScore: Int {
        let steps = Int(metrics?.stepCount ?? 0)
        let activeMin = Int(metrics?.activeMinutes ?? 0)
        let stepGoal = Double(userProfile.dailyStepGoal)
        let stepScore = min(Double(steps) / stepGoal * 50, 50)
        let activeScore = min(Double(activeMin) / 30.0 * 50, 50)
        return Int(stepScore + activeScore)
    }
    
    private var sleepScore: Int {
        let hours = metrics?.sleepHours ?? 0
        let deep = metrics?.deepSleepHours ?? 0
        let rem = metrics?.remSleepHours ?? 0
        let inBed = metrics?.timeInBed ?? 0
        return calculateSleepScore(totalSleep: hours, deepSleep: deep, remSleep: rem, timeInBed: inBed)
    }
    
    private var heartScore: Int {
        let hr = Int(metrics?.restingHeartRate ?? 0)
        let hrv = Int(metrics?.hrv ?? 0)
        guard hr > 0 || hrv > 0 else { return 50 }
        
        var score = 50.0
        if hr > 0 {
            if hr <= 60 { score += 25 }
            else if hr <= 70 { score += 20 }
            else if hr <= 80 { score += 10 }
        }
        if hrv > 0 {
            if hrv >= 50 { score += 25 }
            else if hrv >= 30 { score += 15 }
            else { score += 5 }
        }
        return min(Int(score), 100)
    }
    
    private var recoveryScore: Int {
        let recovery = metrics?.recoveryScore ?? 0
        if recovery > 0 { return Int(recovery) }
        // Fallback: estimate from HRV + sleep
        let hrvPart = min(Double(metrics?.hrv ?? 0) / 50.0 * 50, 50)
        let sleepPart = min((metrics?.sleepHours ?? 0) / 8.0 * 50, 50)
        return Int(hrvPart + sleepPart)
    }
    
    private func calculateOverallScore() -> Int {
        let weights = [0.25, 0.30, 0.25, 0.20] // Activity, Sleep, Heart, Recovery
        let scores = [Double(activityScore), Double(sleepScore), Double(heartScore), Double(recoveryScore)]
        let weighted = zip(weights, scores).map { $0 * $1 }.reduce(0, +)
        return Int(weighted)
    }
    
    private func scoreLabel(_ score: Int) -> (String, Color) {
        switch score {
        case 85...100: return ("Excellent", Color(hex: "10B981"))
        case 70...84: return ("Good", Color(hex: "3B82F6"))
        case 50...69: return ("Fair", Color(hex: "F59E0B"))
        default: return ("Needs Attention", Color(hex: "EF4444"))
        }
    }
    
    private func calculateSleepScore(totalSleep: Double, deepSleep: Double, remSleep: Double, timeInBed: Double) -> Int {
        guard totalSleep > 0 else { return 0 }
        let durationScore: Double = totalSleep >= 7 && totalSleep <= 9 ? 40 : (totalSleep >= 6 ? 30 : 15)
        let deepPercent = (deepSleep / totalSleep) * 100
        let deepScore: Double = deepPercent >= 15 && deepPercent <= 25 ? 25 : (deepPercent >= 10 ? 18 : 10)
        let remPercent = (remSleep / totalSleep) * 100
        let remScore: Double = remPercent >= 20 && remPercent <= 25 ? 20 : (remPercent >= 15 ? 15 : 8)
        let efficiency = timeInBed > 0 ? (totalSleep / timeInBed) * 100 : 85
        let efficiencyScore: Double = efficiency >= 90 ? 15 : (efficiency >= 85 ? 12 : 8)
        return min(100, Int(durationScore + deepScore + remScore + efficiencyScore))
    }
    
    private func sleepScoreColor(_ score: Int) -> Color {
        switch score { case 85...100: return Color(hex: "10B981"); case 70...84: return Color(hex: "3B82F6"); case 50...69: return Color(hex: "F59E0B"); default: return Color(hex: "EF4444") }
    }
    
    private func heartRateStatus(_ hr: Int) -> String {
        guard hr > 0 else { return "—" }
        switch hr { case 40...60: return "Athletic"; case 61...80: return "Normal"; case 81...100: return "Elevated"; default: return "High" }
    }
    
    private func hrvStatus(_ hrv: Int) -> String {
        guard hrv > 0 else { return "—" }
        switch hrv { case 50...: return "Excellent"; case 30...49: return "Good"; case 20...29: return "Fair"; default: return "Low" }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "excellent", "athletic", "normal", "good": return Color(hex: "10B981")
        case "fair", "elevated": return Color(hex: "F59E0B")
        default: return Color(hex: "EF4444")
        }
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour { case 5..<12: return "Good Morning"; case 12..<17: return "Good Afternoon"; case 17..<22: return "Good Evening"; default: return "Good Night" }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
    
    private func formatNumber(_ number: Int) -> String {
        number >= 1000 ? String(format: "%.1fk", Double(number) / 1000.0) : "\(number)"
    }
    
    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }
    
    private func getLast7DaysMetrics() -> [HealthMetrics] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        return allMetrics.filter { calendar.startOfDay(for: $0.date) >= weekAgo && calendar.startOfDay(for: $0.date) <= today }
    }
    
    private func averageSteps(_ m: [HealthMetrics]) -> Int { m.isEmpty ? 0 : m.reduce(0) { $0 + Int($1.stepCount) } / m.count }
    private func averageSleep(_ m: [HealthMetrics]) -> Double { m.isEmpty ? 0 : m.reduce(0.0) { $0 + $1.sleepHours } / Double(m.count) }
    private func averageRestingHR(_ m: [HealthMetrics]) -> Int { let v = m.filter { $0.restingHeartRate > 0 }; return v.isEmpty ? 0 : v.reduce(0) { $0 + Int($1.restingHeartRate) } / v.count }
    
    private func stepsTrend(_ m: [HealthMetrics]) -> (String, Int) {
        guard m.count >= 2 else { return ("", 0) }
        let recent = m.prefix(3).reduce(0) { $0 + Int($1.stepCount) } / 3
        let older = m.suffix(3).reduce(0) { $0 + Int($1.stepCount) } / 3
        guard older > 0 else { return ("up", 0) }
        let change = ((recent - older) * 100) / older
        return (change >= 0 ? "up" : "down", abs(change))
    }
    
    private func sleepTrend(_ m: [HealthMetrics]) -> (String, Int) {
        guard m.count >= 2 else { return ("", 0) }
        let recent = m.prefix(3).reduce(0.0) { $0 + $1.sleepHours } / 3.0
        let older = m.suffix(3).reduce(0.0) { $0 + $1.sleepHours } / 3.0
        guard older > 0 else { return ("up", 0) }
        let change = Int(((recent - older) / older) * 100)
        return (change >= 0 ? "up" : "down", abs(change))
    }
    
    private func hrTrend(_ m: [HealthMetrics]) -> (String, Int) {
        let vr = m.prefix(3).filter { $0.restingHeartRate > 0 }
        let vo = m.suffix(3).filter { $0.restingHeartRate > 0 }
        guard !vr.isEmpty, !vo.isEmpty else { return ("", 0) }
        let recent = vr.reduce(0) { $0 + Int($1.restingHeartRate) } / vr.count
        let older = vo.reduce(0) { $0 + Int($1.restingHeartRate) } / vo.count
        guard older > 0 else { return ("", 0) }
        let change = ((recent - older) * 100) / older
        return (change <= 0 ? "up" : "down", abs(change))
    }
    
    private func dayAbbreviation(_ date: Date) -> String { String(DateFormatter().weekdaySymbols[Calendar.current.component(.weekday, from: date) - 1].prefix(1)) }
    private func isToday(_ date: Date) -> Bool { Calendar.current.isDateInToday(date) }
    
    // MARK: - History & Trend Calculations
    
    private func getMetrics(daysAgo: Int) -> HealthMetrics? {
        let targetDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let startOfDay = Calendar.current.startOfDay(for: targetDate)
        return allMetrics.first { Calendar.current.isDate($0.date, inSameDayAs: startOfDay) }
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
    
    private func percentTrend(of values: [Double], invert: Bool = false) -> Double {
        guard let last = values.last, let previous = values.dropLast().last, previous != 0 else { return 0 }
        let change = ((last - previous) / previous) * 100
        return invert ? -change : change
    }
    
    // History arrays
    private var heartRateHistory: [Double] { history(for: \HealthMetrics.restingHeartRate, days: 14) }
    private var hrvHistory: [Double] { history(for: \HealthMetrics.hrv, days: 14) }
    private var vo2History: [Double] { history(for: \HealthMetrics.vo2Max, days: 14) }
    private var bloodOxygenHistory: [Double] { history(for: \HealthMetrics.bloodOxygen, days: 14) }
    private var respiratoryHistory: [Double] { history(for: \HealthMetrics.respiratoryRate, days: 14) }
    private var recoveryHistory: [Double] { history(for: \HealthMetrics.recoveryScore, days: 14) }
    private var totalCaloriesHistory: [Double] { history(for: \HealthMetrics.totalCalories, days: 14) }
    
    // Trend percentages
    private var heartRateTrend: Double { percentTrend(of: heartRateHistory) }
    private var hrvTrend: Double { percentTrend(of: hrvHistory) }
    private var vo2MaxTrend: Double { percentTrend(of: vo2History) }
    private var bloodOxygenTrend: Double { percentTrend(of: bloodOxygenHistory) }
    private var respiratoryTrend: Double { percentTrend(of: respiratoryHistory) }
    private var recoveryTrend: Double { percentTrend(of: recoveryHistory) }
    
    // Live Heart Rate
    private var latestHeartRateReading: Int? {
        guard let first = heartRateReadings.first else { return nil }
        return Int(first.heartRate)
    }
    
    private var heartRateDayHistory: [Double] {
        let readings = Array(heartRateReadings.prefix(200)).reversed()
        let values = readings.map { Double($0.heartRate) }
        return values.isEmpty ? [Double(metrics?.restingHeartRate ?? 0)] : Array(values)
    }
    
    // Status Indicators
    private var vo2MaxStatus: String {
        guard let vo2 = metrics?.vo2Max, vo2 > 0 else { return "No data" }
        switch vo2 {
        case 0..<35: return "Poor"
        case 35..<42: return "Average"
        case 42..<50: return "Good"
        case 50..<60: return "Excellent"
        default: return "Superior"
        }
    }
    
    private var bloodOxygenStatus: String {
        guard let saturation = metrics?.bloodOxygen, saturation > 0 else { return "No data" }
        if saturation >= 98 { return "Optimal" }
        if saturation >= 95 { return "Healthy" }
        if saturation >= 92 { return "Watch" }
        return "Low"
    }
    
    private var respiratoryStatus: String {
        guard let rate = metrics?.respiratoryRate, rate > 0 else { return "No data" }
        if rate < 12 { return "Below" }
        if rate <= 20 { return "Stable" }
        return "Elevated"
    }
    
    private var recoveryStatus: String {
        guard let score = metrics?.recoveryScore else { return "No data" }
        if score >= 80 { return "Ready" }
        if score >= 60 { return "Solid" }
        return "Recovering"
    }
    
    private var recoveryColor: Color {
        guard let score = metrics?.recoveryScore else { return Color(hex: "6B7280") }
        if score >= 80 { return Color(hex: "10B981") }
        if score >= 60 { return Color(hex: "F59E0B") }
        return Color(hex: "EF4444")
    }
    
    // MARK: - Detail Contexts
    
    private func presentDetail(kind: HealthMetricDetailView.MetricKind, context: HealthMetricDetailView.MetricContext) {
        // Set as one value so navigation never fires with missing context (prevents black screen on first tap)
        metricDestination = MetricDestination(kind: kind, context: context)
    }
    
    private func dailyMetrics(for keyPath: KeyPath<HealthMetrics, Double>, unit: String) -> [HealthMetricDetailView.DailyMetric] {
        (0..<7).compactMap { day -> HealthMetricDetailView.DailyMetric? in
            guard let m = getMetrics(daysAgo: day) else { return nil }
            let value = m[keyPath: keyPath]
            let previous = getMetrics(daysAgo: day + 1)?[keyPath: keyPath] ?? 0
            let delta: Double? = previous > 0 ? ((value - previous) / previous) * 100 : nil
            let date = Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date()
            return HealthMetricDetailView.DailyMetric(date: date, value: unit.isEmpty ? String(format: "%.1f", value) : String(format: "%.1f %@", value, unit), delta: delta)
        }.reversed()
    }
    
    private func dailyMetrics(for keyPath: KeyPath<HealthMetrics, Int16>, unit: String) -> [HealthMetricDetailView.DailyMetric] {
        (0..<7).compactMap { day -> HealthMetricDetailView.DailyMetric? in
            guard let m = getMetrics(daysAgo: day) else { return nil }
            let value = Double(m[keyPath: keyPath])
            let previous = Double(getMetrics(daysAgo: day + 1)?[keyPath: keyPath] ?? 0)
            let delta: Double? = previous > 0 ? ((value - previous) / previous) * 100 : nil
            let date = Calendar.current.date(byAdding: .day, value: -day, to: Date()) ?? Date()
            return HealthMetricDetailView.DailyMetric(date: date, value: unit.isEmpty ? String(format: "%.0f", value) : String(format: "%.0f %@", value, unit), delta: delta)
        }.reversed()
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
    
    private var heartRateContext: HealthMetricDetailView.MetricContext {
        let latest = metrics?.restingHeartRate ?? 0
        return HealthMetricDetailView.MetricContext(
            title: "Resting Heart Rate",
            primaryValue: "\(latest)",
            unit: "bpm",
            description: "Resting heart rate reflects cardiovascular fitness and recovery status.",
            trends: heartRateHistory,
            weeklyAverage: String(format: "Weekly avg • %.1f bpm", average(of: heartRateHistory)),
            dailyValues: dailyMetrics(for: \HealthMetrics.restingHeartRate, unit: "bpm"),
            guidance: ["Stay hydrated and well rested to keep RHR in optimal ranges.", "Consider active recovery days when RHR trends high."],
            systemIcon: "heart.fill",
            tint: .red,
            annotations: annotations(for: heartRateHistory, unit: "bpm")
        )
    }
    
    private var liveHeartRateContext: HealthMetricDetailView.MetricContext {
        let latest = latestHeartRateReading ?? Int(metrics?.restingHeartRate ?? 0)
        return HealthMetricDetailView.MetricContext(
            title: "Heart Rate Today",
            primaryValue: "\(latest)",
            unit: "bpm",
            description: "Heart rate trend across the day.",
            trends: heartRateDayHistory,
            weeklyAverage: String(format: "Avg • %.0f bpm", average(of: heartRateDayHistory)),
            dailyValues: [],
            guidance: ["Aerobic zones build endurance", "Include recovery between intervals"],
            systemIcon: "bolt.heart.fill",
            tint: .pink,
            annotations: []
        )
    }
    
    private var hrvContext: HealthMetricDetailView.MetricContext {
        let value = Int(metrics?.hrv ?? 0)
        return HealthMetricDetailView.MetricContext(
            title: "Heart Rate Variability",
            primaryValue: "\(value)",
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
        let value = String(format: "%.1f", metrics?.vo2Max ?? 0)
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
        let value = String(format: "%.0f", metrics?.bloodOxygen ?? 0)
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
        let value = String(format: "%.0f", metrics?.respiratoryRate ?? 0)
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
    
    private var recoveryContext: HealthMetricDetailView.MetricContext {
        let value = String(format: "%.0f", metrics?.recoveryScore ?? 0)
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
}

// MARK: - Customization Sheet
struct DashboardCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var showActivityCard: Bool
    @Binding var showSleepCard: Bool
    @Binding var showHeartCard: Bool
    @Binding var showVitalsCard: Bool
    @Binding var showWeeklyCard: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                List {
                    Section("Visible Cards") {
                        toggleRow("Activity", icon: "figure.walk", color: Color(hex: "FF6B6B"), isOn: $showActivityCard)
                        toggleRow("Sleep", icon: "moon.fill", color: Color(hex: "8B5CF6"), isOn: $showSleepCard)
                        toggleRow("Heart", icon: "heart.fill", color: Color(hex: "EF4444"), isOn: $showHeartCard)
                        toggleRow("Vitals", icon: "lungs.fill", color: Color(hex: "3B82F6"), isOn: $showVitalsCard)
                        toggleRow("Weekly Overview", icon: "chart.bar.fill", color: Color(hex: "E07A5F"), isOn: $showWeeklyCard)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Customize Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: "10B981"))
                }
            }
        }
    }
    
    private func toggleRow(_ title: String, icon: String, color: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
            }
        }
        .tint(Color(hex: "10B981"))
    }
}

// MARK: - Sleep Detail Sheet
struct SleepDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let metrics: HealthMetrics?
    let allMetrics: [HealthMetrics]
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Last Night Summary
                        if let m = metrics, m.sleepHours > 0 {
                            lastNightCard(m)
                            sleepStagesCard(m)
                            sleepQualityCard(m)
                        }
                        
                        // 7-Day Sleep Trend
                        weeklyTrendCard
                        
                        // Tips
                        sleepTipsCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Sleep Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "8B5CF6"))
                }
            }
        }
    }
    
    private func lastNightCard(_ m: HealthMetrics) -> some View {
        let efficiency = m.timeInBed > 0 ? (m.sleepHours / m.timeInBed) * 100 : 0
        
        return VStack(spacing: 16) {
            Text("Last Night")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 24) {
                VStack {
                    Text(String(format: "%.1f", m.sleepHours))
                        .font(.system(size: 40, weight: .bold))
                    Text("hours").font(.system(size: 13)).foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Time in Bed", value: String(format: "%.1fh", m.timeInBed))
                    detailRow("Efficiency", value: String(format: "%.0f%%", efficiency))
                    detailRow("Quality", value: "\(m.sleepQuality)/10")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func sleepStagesCard(_ m: HealthMetrics) -> some View {
        let deep = m.deepSleepHours
        let rem = m.remSleepHours
        let light = max(0, m.sleepHours - deep - rem)
        let total = m.sleepHours
        
        return VStack(spacing: 16) {
            Text("Sleep Stages")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                stageCircle("Deep", hours: deep, percent: total > 0 ? deep/total*100 : 0, color: Color(hex: "3B82F6"))
                stageCircle("REM", hours: rem, percent: total > 0 ? rem/total*100 : 0, color: Color(hex: "8B5CF6"))
                stageCircle("Light", hours: light, percent: total > 0 ? light/total*100 : 0, color: Color(hex: "06B6D4"))
            }
            
            // Ideal ranges
            VStack(alignment: .leading, spacing: 6) {
                Text("Ideal Ranges").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                Text("• Deep: 15-25% (restorative)").font(.system(size: 11)).foregroundColor(.secondary)
                Text("• REM: 20-25% (memory & learning)").font(.system(size: 11)).foregroundColor(.secondary)
                Text("• Light: 50-60% (transition)").font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func stageCircle(_ label: String, hours: Double, percent: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 6).frame(width: 60, height: 60)
                Circle().trim(from: 0, to: percent / 100).stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round)).frame(width: 60, height: 60).rotationEffect(.degrees(-90))
                Text("\(Int(percent))%").font(.system(size: 14, weight: .bold))
            }
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
            Text(String(format: "%.1fh", hours)).font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func sleepQualityCard(_ m: HealthMetrics) -> some View {
        VStack(spacing: 16) {
            Text("Quality Factors")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                qualityRow("Duration", value: m.sleepHours, ideal: 7.5, unit: "h", good: m.sleepHours >= 7)
                qualityRow("Deep Sleep", value: m.deepSleepHours, ideal: m.sleepHours * 0.2, unit: "h", good: m.deepSleepHours >= m.sleepHours * 0.15)
                qualityRow("REM Sleep", value: m.remSleepHours, ideal: m.sleepHours * 0.22, unit: "h", good: m.remSleepHours >= m.sleepHours * 0.18)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func qualityRow(_ label: String, value: Double, ideal: Double, unit: String, good: Bool) -> some View {
        HStack {
            Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(good ? Color(hex: "10B981") : Color(hex: "F59E0B"))
            Text(label).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(String(format: "%.1f%@", value, unit)).font(.system(size: 14, weight: .bold))
            Text("/ \(String(format: "%.1f%@", ideal, unit))").font(.system(size: 12)).foregroundColor(.secondary)
        }
    }
    
    private var weeklyTrendCard: some View {
        let last7 = Array(allMetrics.prefix(7))
        
        return VStack(spacing: 16) {
            Text("7-Day Trend")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(last7.reversed(), id: \.id) { m in
                    VStack(spacing: 4) {
                        let height = CGFloat(m.sleepHours / 10 * 80)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(m.sleepHours >= 7 ? Color(hex: "8B5CF6") : Color(hex: "8B5CF6").opacity(0.4))
                            .frame(height: max(height, 4))
                        Text(dayAbbr(m.date)).font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
            
            let avg = last7.isEmpty ? 0 : last7.reduce(0.0) { $0 + $1.sleepHours } / Double(last7.count)
            Text("Avg: \(String(format: "%.1f", avg)) hours/night")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private var sleepTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Improve Your Sleep")
                .font(.system(size: 17, weight: .bold))
            
            tipRow("🌙", "Keep consistent sleep/wake times")
            tipRow("📵", "Avoid screens 1 hour before bed")
            tipRow("🌡️", "Keep room cool (65-68°F / 18-20°C)")
            tipRow("☕", "No caffeine after 2 PM")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func tipRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(emoji)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
        }
    }
    
    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold))
        }
    }
    
    private func dayAbbr(_ date: Date) -> String { String(DateFormatter().weekdaySymbols[Calendar.current.component(.weekday, from: date) - 1].prefix(1)) }
}

// MARK: - Vitals Detail Sheet (Apple Watch metrics only)
struct VitalsDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let metrics: HealthMetrics?
    let allMetrics: [HealthMetrics]
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Data source note
                        HStack(spacing: 8) {
                            Image(systemName: "applewatch")
                                .font(.system(size: 14))
                            Text("Data from Apple Watch")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if let m = metrics {
                            heartSection(m)
                            respiratorySection(m)
                            fitnessSection(m)
                        }
                        
                        weeklyVitalsTrend
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Vitals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "3B82F6"))
                }
            }
        }
    }
    
    private func heartSection(_ m: HealthMetrics) -> some View {
        VStack(spacing: 16) {
            sectionHeader("Heart", icon: "heart.fill", color: Color(hex: "EF4444"))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                vitalDetailCard("Resting HR", value: m.restingHeartRate > 0 ? "\(m.restingHeartRate)" : "—", unit: "bpm", range: "40-100", ideal: "< 70")
                vitalDetailCard("HRV", value: m.hrv > 0 ? "\(Int(m.hrv))" : "—", unit: "ms", range: "20-100+", ideal: "> 40")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func respiratorySection(_ m: HealthMetrics) -> some View {
        VStack(spacing: 16) {
            sectionHeader("Respiratory", icon: "lungs.fill", color: Color(hex: "3B82F6"))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                vitalDetailCard("Blood Oxygen", value: m.bloodOxygen > 0 ? "\(Int(m.bloodOxygen))" : "—", unit: "%", range: "95-100", ideal: "> 95")
                vitalDetailCard("Resp Rate", value: m.respiratoryRate > 0 ? "\(Int(m.respiratoryRate))" : "—", unit: "br/min", range: "12-20", ideal: "12-18")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func fitnessSection(_ m: HealthMetrics) -> some View {
        VStack(spacing: 16) {
            sectionHeader("Cardio Fitness", icon: "bolt.heart.fill", color: Color(hex: "10B981"))
            
            vitalDetailCard("VO₂ Max", value: m.vo2Max > 0 ? String(format: "%.1f", m.vo2Max) : "—", unit: "ml/kg/min", range: "30-60+", ideal: "> 40")
            
            // VO2 Max explanation
            VStack(alignment: .leading, spacing: 8) {
                Text("What is VO₂ Max?")
                    .font(.system(size: 13, weight: .semibold))
                Text("Your VO₂ Max estimates how much oxygen your body can use during exercise. Higher values indicate better cardiovascular fitness.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    fitnessLevelRow("Low", range: "< 30", color: Color(hex: "EF4444"))
                    fitnessLevelRow("Below Avg", range: "30-37", color: Color(hex: "F59E0B"))
                    fitnessLevelRow("Average", range: "38-45", color: Color(hex: "3B82F6"))
                    fitnessLevelRow("Above Avg", range: "46-52", color: Color(hex: "10B981"))
                    fitnessLevelRow("High", range: "> 52", color: Color(hex: "8B5CF6"))
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func fitnessLevelRow(_ level: String, range: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(level).font(.system(size: 11, weight: .medium))
            Spacer()
            Text(range).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
    
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(color)
            Text(title).font(.system(size: 17, weight: .bold))
            Spacer()
        }
    }
    
    private func vitalDetailCard(_ title: String, value: String, unit: String, range: String, ideal: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 22, weight: .bold))
                Text(unit).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text("Range: \(range)").font(.system(size: 10)).foregroundColor(.secondary)
            Text("Ideal: \(ideal)").font(.system(size: 10)).foregroundColor(Color(hex: "10B981"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)))
    }
    
    private var weeklyVitalsTrend: some View {
        let last7 = Array(allMetrics.prefix(7))
        let avgHR = last7.filter { $0.restingHeartRate > 0 }.isEmpty ? 0 : last7.filter { $0.restingHeartRate > 0 }.reduce(0) { $0 + Int($1.restingHeartRate) } / last7.filter { $0.restingHeartRate > 0 }.count
        let avgHRV = last7.filter { $0.hrv > 0 }.isEmpty ? 0.0 : last7.filter { $0.hrv > 0 }.reduce(0.0) { $0 + $1.hrv } / Double(last7.filter { $0.hrv > 0 }.count)
        
        return VStack(spacing: 16) {
            Text("7-Day Averages")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                avgCard("Resting HR", value: "\(avgHR)", unit: "bpm", color: Color(hex: "EF4444"))
                avgCard("HRV", value: String(format: "%.0f", avgHRV), unit: "ms", color: Color(hex: "8B5CF6"))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func avgCard(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundColor(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 20, weight: .bold))
                Text(unit).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.1)))
    }
}

// MARK: - Health Score Detail Sheet
struct HealthScoreDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let overallScore: Int
    let activityScore: Int
    let sleepScore: Int
    let heartScore: Int
    let recoveryScore: Int
    let metrics: HealthMetrics?
    let allMetrics: [HealthMetrics]
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Hero Score Card
                        heroScoreCard
                        
                        // Energy & Wellness Section
                        energyWellnessSection
                        
                        // Score Breakdown
                        scoreBreakdownSection
                        
                        // Weekly Trend
                        weeklyScoreTrend
                        
                        // Score Factors
                        scoreFactorsSection
                        
                        // Recommendations
                        recommendationsSection
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Health Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(scoreColor)
                }
            }
        }
    }
    
    private var scoreColor: Color {
        switch overallScore {
        case 85...100: return Color(hex: "10B981")
        case 70...84: return Color(hex: "3B82F6")
        case 50...69: return Color(hex: "F59E0B")
        default: return Color(hex: "EF4444")
        }
    }
    
    private var scoreLabel: String {
        switch overallScore {
        case 85...100: return "Excellent"
        case 70...84: return "Good"
        case 50...69: return "Fair"
        default: return "Needs Attention"
        }
    }
    
    private var heroScoreCard: some View {
        VStack(spacing: 20) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 20)
                    .frame(width: 160, height: 160)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: Double(overallScore) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [scoreColor.opacity(0.7), scoreColor],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(overallScore)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    Text("out of 100")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
            }
            
            VStack(spacing: 6) {
                Text(scoreLabel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(scoreColor)
                
                Text(scoreMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [scoreColor.opacity(0.15), scoreColor.opacity(0.05)]
                            : [scoreColor.opacity(0.1), Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(scoreColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var scoreMessage: String {
        switch overallScore {
        case 85...100: return "Outstanding! Your health metrics are exceptional today."
        case 70...84: return "You're doing well. Keep maintaining your healthy habits."
        case 50...69: return "Room for improvement. Focus on sleep and activity."
        default: return "Take it easy today. Prioritize rest and recovery."
        }
    }
    
    // MARK: - Energy & Wellness Section
    private var energyWellnessSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Energy & Wellness")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            HStack(spacing: 14) {
                // Daily Battery Card
                detailBatteryCard
                
                // Stress Level Card
                detailStressCard
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private var detailBatteryLevel: Int {
        let baseEnergy = Int(metrics?.energyLevel ?? 0)
        if baseEnergy > 0 { return baseEnergy * 10 }
        
        let hour = Calendar.current.component(.hour, from: Date())
        let sleepHours = metrics?.sleepHours ?? 7
        let activeCalories = metrics?.activeCalories ?? 0
        let steps = Int(metrics?.stepCount ?? 0)
        
        var battery = min(100, Int(sleepHours / 8.0 * 100))
        let hoursAwake = max(0, hour - 7)
        battery -= hoursAwake * 4
        battery -= Int(activeCalories / 50) + (steps / 2000)
        if let hrv = metrics?.hrv, hrv > 50 { battery += 10 }
        
        return max(5, min(100, battery))
    }
    
    private var detailBatteryColor: Color {
        switch detailBatteryLevel {
        case 70...100: return Color(hex: "10B981")
        case 40...69: return Color(hex: "F59E0B")
        case 20...39: return Color(hex: "F97316")
        default: return Color(hex: "EF4444")
        }
    }
    
    private var detailBatteryLabel: String {
        switch detailBatteryLevel {
        case 80...100: return "Fully Charged"
        case 60...79: return "Good Energy"
        case 40...59: return "Moderate"
        case 20...39: return "Low Energy"
        default: return "Recharge Needed"
        }
    }
    
    private var detailBatteryCard: some View {
        VStack(spacing: 16) {
            // Battery visualization
            ZStack {
                // Outer glow
                Circle()
                    .fill(detailBatteryColor.opacity(0.15))
                    .frame(width: 90, height: 90)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: CGFloat(detailBatteryLevel) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [detailBatteryColor.opacity(0.5), detailBatteryColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                
                // Center content
                VStack(spacing: 2) {
                    Image(systemName: batteryIconForLevel(detailBatteryLevel))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(detailBatteryColor)
                    Text("\(detailBatteryLevel)%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                }
            }
            
            VStack(spacing: 4) {
                Text("Daily Battery")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text(detailBatteryLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(detailBatteryColor)
            }
            
            // Time estimate
            VStack(spacing: 2) {
                Text(estimatedBatteryTime)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(detailBatteryColor.opacity(colorScheme == .dark ? 0.1 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(detailBatteryColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func batteryIconForLevel(_ level: Int) -> String {
        switch level {
        case 75...100: return "battery.100"
        case 50...74: return "battery.75"
        case 25...49: return "battery.50"
        default: return "battery.25"
        }
    }
    
    private var estimatedBatteryTime: String {
        let remainingHours = (detailBatteryLevel * 16) / 100 // Assuming 16 active hours
        if remainingHours > 8 {
            return "~\(remainingHours)h until recharge"
        } else if remainingHours > 4 {
            return "~\(remainingHours)h of energy left"
        } else {
            return "Consider resting soon"
        }
    }
    
    private var detailStressLevel: Int {
        let metricStress = Int(metrics?.stressLevel ?? 0)
        if metricStress > 0 { return metricStress * 10 }
        
        let hrv = metrics?.hrv ?? 0
        let restingHR = Int(metrics?.restingHeartRate ?? 0)
        let sleepHours = metrics?.sleepHours ?? 7
        
        var estimatedStress = 30
        if hrv > 0 {
            if hrv < 25 { estimatedStress += 40 }
            else if hrv < 40 { estimatedStress += 25 }
            else if hrv < 50 { estimatedStress += 10 }
            else { estimatedStress -= 10 }
        }
        if restingHR > 0 {
            if restingHR > 80 { estimatedStress += 20 }
            else if restingHR > 70 { estimatedStress += 10 }
            else if restingHR < 60 { estimatedStress -= 10 }
        }
        if sleepHours < 6 { estimatedStress += 15 }
        else if sleepHours > 7 { estimatedStress -= 10 }
        
        return max(0, min(100, estimatedStress))
    }
    
    private var detailStressColor: Color {
        switch detailStressLevel {
        case 0...25: return Color(hex: "10B981")
        case 26...50: return Color(hex: "3B82F6")
        case 51...70: return Color(hex: "F59E0B")
        case 71...85: return Color(hex: "F97316")
        default: return Color(hex: "EF4444")
        }
    }
    
    private var detailStressLabel: String {
        switch detailStressLevel {
        case 0...25: return "Very Calm"
        case 26...50: return "Relaxed"
        case 51...70: return "Moderate"
        case 71...85: return "Elevated"
        default: return "High Stress"
        }
    }
    
    private var detailStressIcon: String {
        switch detailStressLevel {
        case 0...25: return "leaf.fill"
        case 26...50: return "wind"
        case 51...70: return "cloud.fill"
        case 71...85: return "cloud.bolt.fill"
        default: return "bolt.horizontal.fill"
        }
    }
    
    private var detailStressCard: some View {
        VStack(spacing: 16) {
            // Stress gauge
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "10B981").opacity(0.3),
                                Color(hex: "3B82F6").opacity(0.3),
                                Color(hex: "F59E0B").opacity(0.3),
                                Color(hex: "EF4444").opacity(0.3)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(90))
                
                // Progress indicator
                Circle()
                    .trim(from: 0.15, to: 0.15 + (0.7 * CGFloat(detailStressLevel) / 100))
                    .stroke(
                        detailStressColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(90))
                
                // Center icon
                VStack(spacing: 2) {
                    Image(systemName: detailStressIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(detailStressColor)
                    Text("\(detailStressLevel)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                }
            }
            .frame(width: 90, height: 90)
            
            VStack(spacing: 4) {
                Text("Stress Level")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text(detailStressLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(detailStressColor)
            }
            
            // Insight text
            Text(stressInsight)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(detailStressColor.opacity(colorScheme == .dark ? 0.1 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(detailStressColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var stressInsight: String {
        switch detailStressLevel {
        case 0...25: return "Great balance today"
        case 26...50: return "Body is well-regulated"
        case 51...70: return "Take some deep breaths"
        case 71...85: return "Consider a break"
        default: return "Prioritize relaxation"
        }
    }
    
    private var scoreBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Score Breakdown")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 12) {
                scoreDetailRow("Activity", score: activityScore, icon: "figure.walk", color: Color(hex: "FF6B6B"), description: activityDescription)
                scoreDetailRow("Sleep", score: sleepScore, icon: "moon.fill", color: Color(hex: "8B5CF6"), description: sleepDescription)
                scoreDetailRow("Heart Health", score: heartScore, icon: "heart.fill", color: Color(hex: "EF4444"), description: heartDescription)
                scoreDetailRow("Recovery", score: recoveryScore, icon: "arrow.counterclockwise", color: Color(hex: "10B981"), description: recoveryDescription)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func scoreDetailRow(_ label: String, score: Int, icon: String, color: Color, description: String) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    Text(description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(color)
                    Text("/100")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score) / 100, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)))
    }
    
    private var activityDescription: String {
        if activityScore >= 80 { return "Excellent movement today" }
        if activityScore >= 60 { return "Good activity level" }
        return "More movement recommended"
    }
    
    private var sleepDescription: String {
        if sleepScore >= 80 { return "Great sleep quality" }
        if sleepScore >= 60 { return "Decent rest" }
        return "Sleep needs attention"
    }
    
    private var heartDescription: String {
        if heartScore >= 80 { return "Strong cardiovascular health" }
        if heartScore >= 60 { return "Heart metrics looking good" }
        return "Monitor heart health"
    }
    
    private var recoveryDescription: String {
        if recoveryScore >= 80 { return "Ready for intense activity" }
        if recoveryScore >= 60 { return "Moderate readiness" }
        return "Focus on recovery today"
    }
    
    private var weeklyScoreTrend: some View {
        let last7 = Array(allMetrics.prefix(7))
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("7-Day Trend")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            // Bar chart
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(last7.reversed().indices, id: \.self) { index in
                    let m = last7.reversed()[index]
                    let dayScore = calculateDayScore(m)
                    let isToday = Calendar.current.isDateInToday(m.date)
                    
                    VStack(spacing: 6) {
                        Text("\(dayScore)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isToday ? scoreColor : (colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B")))
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isToday ? scoreColor : scoreColor.opacity(0.4))
                            .frame(height: max(CGFloat(dayScore) * 0.8, 8))
                        
                        Text(dayAbbr(m.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isToday ? (colorScheme == .dark ? .white : Color(hex: "1A1A1A")) : (colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF")))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)
            
            // Weekly average
            let avgScore = last7.isEmpty ? 0 : last7.map { calculateDayScore($0) }.reduce(0, +) / last7.count
            HStack {
                Text("Weekly Average")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                Spacer()
                Text("\(avgScore)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(scoreColor)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func calculateDayScore(_ m: HealthMetrics) -> Int {
        let stepGoal = Double(UserProfileManager.shared.dailyStepGoal)
        let activity = min(Double(m.stepCount) / stepGoal * 50, 50) + min(Double(m.activeMinutes) / 30.0 * 50, 50)
        let sleep = calculateSleepScore(m)
        let heart = calculateHeartScore(m)
        let recovery = calculateRecoveryScore(m)
        
        let weights = [0.25, 0.30, 0.25, 0.20]
        let scores = [activity, Double(sleep), Double(heart), Double(recovery)]
        return Int(zip(weights, scores).map { $0 * $1 }.reduce(0, +))
    }
    
    private func calculateSleepScore(_ m: HealthMetrics) -> Int {
        guard m.sleepHours > 0 else { return 0 }
        let durationScore: Double = m.sleepHours >= 7 && m.sleepHours <= 9 ? 40 : (m.sleepHours >= 6 ? 30 : 15)
        let deepPercent = (m.deepSleepHours / m.sleepHours) * 100
        let deepScore: Double = deepPercent >= 15 && deepPercent <= 25 ? 25 : (deepPercent >= 10 ? 18 : 10)
        let remPercent = (m.remSleepHours / m.sleepHours) * 100
        let remScore: Double = remPercent >= 20 && remPercent <= 25 ? 20 : (remPercent >= 15 ? 15 : 8)
        let efficiency = m.timeInBed > 0 ? (m.sleepHours / m.timeInBed) * 100 : 85
        let efficiencyScore: Double = efficiency >= 90 ? 15 : (efficiency >= 85 ? 12 : 8)
        return min(100, Int(durationScore + deepScore + remScore + efficiencyScore))
    }
    
    private func calculateHeartScore(_ m: HealthMetrics) -> Int {
        let hr = Int(m.restingHeartRate)
        let hrv = Int(m.hrv)
        guard hr > 0 || hrv > 0 else { return 50 }
        
        var score = 50.0
        if hr > 0 {
            if hr <= 60 { score += 25 }
            else if hr <= 70 { score += 20 }
            else if hr <= 80 { score += 10 }
        }
        if hrv > 0 {
            if hrv >= 50 { score += 25 }
            else if hrv >= 30 { score += 15 }
            else { score += 5 }
        }
        return min(Int(score), 100)
    }
    
    private func calculateRecoveryScore(_ m: HealthMetrics) -> Int {
        if m.recoveryScore > 0 { return Int(m.recoveryScore) }
        let hrvPart = min(m.hrv / 50.0 * 50, 50)
        let sleepPart = min(m.sleepHours / 8.0 * 50, 50)
        return Int(hrvPart + sleepPart)
    }
    
    private func dayAbbr(_ date: Date) -> String {
        String(DateFormatter().weekdaySymbols[Calendar.current.component(.weekday, from: date) - 1].prefix(1))
    }
    
    private var scoreFactorsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What Affects Your Score")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 10) {
                factorRow("Steps & Active Minutes", weight: "25%", icon: "figure.walk", color: Color(hex: "FF6B6B"))
                factorRow("Sleep Duration & Quality", weight: "30%", icon: "moon.fill", color: Color(hex: "8B5CF6"))
                factorRow("Resting HR & HRV", weight: "25%", icon: "heart.fill", color: Color(hex: "EF4444"))
                factorRow("Recovery & Readiness", weight: "20%", icon: "arrow.counterclockwise", color: Color(hex: "10B981"))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func factorRow(_ title: String, weight: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Spacer()
            
            Text(weight)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }
    
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recommendations")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 12) {
                ForEach(recommendations, id: \.self) { rec in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(scoreColor)
                        
                        Text(rec)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : Color(hex: "4B5563"))
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private var recommendations: [String] {
        var recs: [String] = []
        
        if activityScore < 70 {
            recs.append("Try adding a 15-minute walk to boost your activity score")
        }
        if sleepScore < 70 {
            recs.append("Aim for 7-8 hours of sleep with consistent bed/wake times")
        }
        if heartScore < 70 {
            recs.append("Regular cardio exercise can improve heart health metrics")
        }
        if recoveryScore < 70 {
            recs.append("Consider stress-reduction activities like meditation")
        }
        
        if recs.isEmpty {
            recs.append("Keep up the great work! Maintain your healthy habits")
            recs.append("Stay hydrated and continue your balanced routine")
        }
        
        return recs
    }
}

// MARK: - Activity Detail Sheet
struct ActivityDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var userProfile = UserProfileManager.shared
    
    let metrics: HealthMetrics?
    let allMetrics: [HealthMetrics]
    let workouts: [WorkoutLog]
    
    @State private var selectedWorkout: WorkoutLog?
    
    private var todaysWorkouts: [WorkoutLog] {
        workouts.filter { Calendar.current.isDateInToday($0.timestamp) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Today's Summary
                        todaySummaryCard
                        
                        // Activity Rings
                        activityRingsCard
                        
                        // Today's Workouts
                        todaysWorkoutsCard
                        
                        // Hourly Activity
                        hourlyActivityCard
                        
                        // Weekly Comparison
                        weeklyComparisonCard
                        
                        // Achievements
                        achievementsCard
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(Color(hex: "FF6B6B"))
                }
            }
            .sheet(item: $selectedWorkout) { workout in
                EnhancedWorkoutDetailSheet(workout: workout, allMetrics: allMetrics)
            }
        }
    }
    
    // MARK: - Today's Workouts Card
    private var todaysWorkoutsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.mixed.cardio")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "10B981"))
                Text("Today's Workouts")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                if !todaysWorkouts.isEmpty {
                    Text("\(todaysWorkouts.count)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: "10B981"))
                        .clipShape(Capsule())
                }
            }
            
            if todaysWorkouts.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
                    
                    Text("No workouts yet today")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    
                    Text("Start moving to see your activity here")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(todaysWorkouts) { workout in
                        Button {
                            selectedWorkout = workout
                        } label: {
                            workoutListRow(workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func workoutListRow(_ workout: WorkoutLog) -> some View {
        HStack(spacing: 14) {
            // Workout icon
            ZStack {
                Circle()
                    .fill(workoutColor(for: workout).opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: workoutIcon(for: workout))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(workoutColor(for: workout))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutType.capitalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text(workout.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            Spacer()
            
            // Quick stats
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatDuration(workout.duration))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                HStack(spacing: 8) {
                    if workout.distance > 0 {
                        Label(String(format: "%.2f km", workout.distance), systemImage: "location.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    Label("\(Int(workout.calories)) cal", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "D1D5DB"))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(workoutColor(for: workout).opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
    }
    
    private func workoutColor(for workout: WorkoutLog) -> Color {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("run"): return Color(hex: "E07A5F")
        case let t where t.contains("walk"): return Color(hex: "10B981")
        case let t where t.contains("bike") || t.contains("cycl"): return Color(hex: "3B82F6")
        case let t where t.contains("strength") || t.contains("weight"): return Color(hex: "8B5CF6")
        case let t where t.contains("swim"): return Color(hex: "06B6D4")
        case let t where t.contains("yoga"): return Color(hex: "F472B6")
        case let t where t.contains("hiit"): return Color(hex: "EF4444")
        default: return Color(hex: "6B7280")
        }
    }
    
    private func workoutIcon(for workout: WorkoutLog) -> String {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("run"): return "figure.run"
        case let t where t.contains("walk"): return "figure.walk"
        case let t where t.contains("bike") || t.contains("cycl"): return "bicycle"
        case let t where t.contains("strength") || t.contains("weight"): return "dumbbell.fill"
        case let t where t.contains("swim"): return "figure.pool.swim"
        case let t where t.contains("yoga"): return "figure.yoga"
        case let t where t.contains("hiit"): return "flame.fill"
        default: return "figure.mixed.cardio"
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var todaySummaryCard: some View {
        let steps = Int(metrics?.stepCount ?? 0)
        let calories = Int(metrics?.activeCalories ?? 0)
        let distance = metrics?.totalDistance ?? 0
        let activeMin = Int(metrics?.activeMinutes ?? 0)
        
        return VStack(spacing: 20) {
            Text("Today's Activity")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                activityMetricCard("Steps", value: formatNumber(steps), goal: formatNumber(UserProfileManager.shared.dailyStepGoal), progress: Double(steps) / Double(UserProfileManager.shared.dailyStepGoal), icon: "shoeprints.fill", color: Color(hex: "FF6B6B"))
                activityMetricCard("Calories", value: "\(calories)", goal: "\(Int(UserProfileManager.shared.dailyCalorieGoal))", progress: Double(calories) / UserProfileManager.shared.dailyCalorieGoal, icon: "flame.fill", color: Color(hex: "F59E0B"))
                activityMetricCard("Distance", value: String(format: "%.1f km", distance), goal: "5.0 km", progress: distance / 5.0, icon: "map.fill", color: Color(hex: "10B981"))
                activityMetricCard("Active Min", value: "\(activeMin)", goal: "30 min", progress: Double(activeMin) / 30.0, icon: "clock.fill", color: Color(hex: "3B82F6"))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func activityMetricCard(_ title: String, value: String, goal: String, progress: Double, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                Text(progress >= 1 ? "✓" : "")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "10B981"))
            }
            
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text("Goal: \(goal)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(progress, 1.0), height: 6)
                }
            }
            .frame(height: 6)
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(colorScheme == .dark ? 0.1 : 0.06)))
    }
    
    private var activityRingsCard: some View {
        let steps = Int(metrics?.stepCount ?? 0)
        let calories = Int(metrics?.activeCalories ?? 0)
        let activeMin = Int(metrics?.activeMinutes ?? 0)
        
        return VStack(spacing: 20) {
            Text("Activity Rings")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 24) {
                // Triple ring
                ZStack {
                    // Move ring (calories)
                    Circle()
                        .stroke(Color(hex: "FF6B6B").opacity(0.2), lineWidth: 14)
                        .frame(width: 120, height: 120)
                    Circle()
                        .trim(from: 0, to: min(Double(calories) / 500.0, 1.0))
                        .stroke(Color(hex: "FF6B6B"), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                    
                    // Exercise ring (active minutes)
                    Circle()
                        .stroke(Color(hex: "34D399").opacity(0.2), lineWidth: 14)
                        .frame(width: 90, height: 90)
                    Circle()
                        .trim(from: 0, to: min(Double(activeMin) / 30.0, 1.0))
                        .stroke(Color(hex: "34D399"), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                    
                    // Stand ring (steps)
                    Circle()
                        .stroke(Color(hex: "60A5FA").opacity(0.2), lineWidth: 14)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: min(Double(steps) / Double(UserProfileManager.shared.dailyStepGoal), 1.0))
                        .stroke(Color(hex: "60A5FA"), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                }
                
                // Legend
                VStack(alignment: .leading, spacing: 12) {
                    ringLegendRow("Move", value: "\(calories)/500 kcal", color: Color(hex: "FF6B6B"))
                    ringLegendRow("Exercise", value: "\(activeMin)/30 min", color: Color(hex: "34D399"))
                    ringLegendRow("Steps", value: "\(steps)/10k", color: Color(hex: "60A5FA"))
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func ringLegendRow(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
    }
    
    private var hourlyActivityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity by Hour")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            // Simulated hourly data (would be real data from HealthKit)
            let hours = ["6a", "8a", "10a", "12p", "2p", "4p", "6p", "8p"]
            let values: [Double] = [500, 800, 1200, 600, 2000, 1500, 800, 400]
            let maxVal = values.max() ?? 1
            
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<hours.count, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "FF6B6B"))
                            .frame(height: CGFloat(values[i] / maxVal) * 60)
                        Text(hours[i])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private var weeklyComparisonCard: some View {
        let last7 = Array(allMetrics.prefix(7))
        let avgSteps = last7.isEmpty ? 0 : last7.reduce(0) { $0 + Int($1.stepCount) } / last7.count
        let avgCal = last7.isEmpty ? 0 : Int(last7.reduce(0.0) { $0 + $1.activeCalories } / Double(last7.count))
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Summary")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            HStack(spacing: 16) {
                weeklyStatCard("Avg Steps", value: formatNumber(avgSteps), color: Color(hex: "FF6B6B"))
                weeklyStatCard("Avg Calories", value: "\(avgCal)", color: Color(hex: "F59E0B"))
            }
            
            // Daily bars
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(last7.reversed(), id: \.id) { m in
                    let isToday = Calendar.current.isDateInToday(m.date)
                    let height = max(CGFloat(m.stepCount) / CGFloat(UserProfileManager.shared.dailyStepGoal) * 50, 4)
                    
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isToday ? Color(hex: "FF6B6B") : Color(hex: "FF6B6B").opacity(0.4))
                            .frame(height: height)
                        Text(dayAbbr(m.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(isToday ? (colorScheme == .dark ? .white : Color(hex: "1A1A1A")) : (colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF")))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 70)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func weeklyStatCard(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(colorScheme == .dark ? 0.1 : 0.06)))
    }
    
    private var achievementsCard: some View {
        let steps = Int(metrics?.stepCount ?? 0)
        let stepGoal = userProfile.dailyStepGoal
        let calorieGoal = userProfile.dailyCalorieGoal
        let goalsMet = [
            steps >= stepGoal,
            (metrics?.activeCalories ?? 0) >= calorieGoal,
            (metrics?.activeMinutes ?? 0) >= 30,
            workouts.filter { Calendar.current.isDateInToday($0.timestamp) }.count > 0
        ].filter { $0 }.count
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Achievements")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                Text("\(goalsMet)/4")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "F59E0B"))
            }
            
            VStack(spacing: 10) {
                achievementRow("\(formatNumber(stepGoal)) Steps", achieved: steps >= stepGoal, icon: "shoeprints.fill")
                achievementRow("\(Int(calorieGoal)) Calorie Goal", achieved: (metrics?.activeCalories ?? 0) >= calorieGoal, icon: "flame.fill")
                achievementRow("30 Active Minutes", achieved: (metrics?.activeMinutes ?? 0) >= 30, icon: "clock.fill")
                achievementRow("Completed Workout", achieved: workouts.filter { Calendar.current.isDateInToday($0.timestamp) }.count > 0, icon: "checkmark.circle.fill")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func achievementRow(_ title: String, achieved: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: achieved ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(achieved ? Color(hex: "10B981") : (colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB")))
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(achieved ? (colorScheme == .dark ? .white : Color(hex: "1A1A1A")) : (colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF")))
                .strikethrough(!achieved ? false : false)
            
            Spacer()
            
            if achieved {
                Text("✓")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "10B981"))
            }
        }
        .padding(.vertical, 6)
    }
    
    private func formatNumber(_ number: Int) -> String {
        number >= 1000 ? String(format: "%.1fk", Double(number) / 1000.0) : "\(number)"
    }
    
    private func dayAbbr(_ date: Date) -> String {
        String(DateFormatter().weekdaySymbols[Calendar.current.component(.weekday, from: date) - 1].prefix(1))
    }
}

// MARK: - Workout Detail Sheet with Map
struct WorkoutDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let workout: WorkoutLog
    let allMetrics: [HealthMetrics]
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Route Map (if available)
                        routeMapCard
                        
                        // Workout Summary
                        workoutSummaryCard
                        
                        // Key Metrics
                        keyMetricsCard
                        
                        // Heart Rate Analysis
                        if workout.avgHeartRate > 0 {
                            heartRateCard
                        }
                        
                        // Performance Stats
                        performanceCard
                        
                        // Training Zones
                        if workout.avgHeartRate > 0 {
                            trainingZonesCard
                        }
                        
                        // Splits (for runs/walks)
                        if workout.distance > 0 && isRunOrWalk {
                            splitsCard
                        }
                        
                        // Recovery Recommendation
                        recoveryCard
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(workoutColor)
                }
            }
        }
    }
    
    private var isRunOrWalk: Bool {
        let type = workout.workoutType.lowercased()
        return type.contains("run") || type.contains("walk")
    }
    
    private var workoutColor: Color {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("run"): return Color(hex: "E07A5F")
        case let t where t.contains("walk"): return Color(hex: "10B981")
        case let t where t.contains("bike") || t.contains("cycl"): return Color(hex: "3B82F6")
        case let t where t.contains("strength") || t.contains("weight"): return Color(hex: "8B5CF6")
        case let t where t.contains("swim"): return Color(hex: "06B6D4")
        case let t where t.contains("yoga"): return Color(hex: "F472B6")
        default: return Color(hex: "6B7280")
        }
    }
    
    private var workoutIcon: String {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("run"): return "figure.run"
        case let t where t.contains("walk"): return "figure.walk"
        case let t where t.contains("bike") || t.contains("cycl"): return "bicycle"
        case let t where t.contains("strength") || t.contains("weight"): return "dumbbell.fill"
        case let t where t.contains("swim"): return "figure.pool.swim"
        case let t where t.contains("yoga"): return "figure.yoga"
        default: return "figure.mixed.cardio"
        }
    }
    
    // MARK: - Route Map Card
    private var routeMapCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(workoutColor)
                Text("Route")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
            }
            
            let routePoints = RouteCoding.decode(workout.route)
            
            if !routePoints.isEmpty {
                RouteMapView(points: routePoints, strokeColor: workoutColor)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(workoutColor.opacity(colorScheme == .dark ? 0.35 : 0.2), lineWidth: 1)
                    )
            } else {
                // No route data
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                        .frame(height: 160)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
                        
                        Text("No Route Available")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                        
                        Text("GPS tracking wasn't enabled for this workout")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    // MARK: - Workout Summary Card
    private var workoutSummaryCard: some View {
        VStack(spacing: 16) {
            // Workout icon and type
            ZStack {
                Circle()
                    .fill(workoutColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: workoutIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(workoutColor)
            }
            
            VStack(spacing: 6) {
                Text(workout.workoutType.capitalized)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text(workout.timestamp.formatted(date: .complete, time: .shortened))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
            
            // Quick stats
            HStack(spacing: 24) {
                quickStat("Duration", value: formattedDuration)
                if workout.distance > 0 {
                    quickStat("Distance", value: String(format: "%.2f km", workout.distance))
                }
                quickStat("Calories", value: "\(Int(workout.calories))")
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [workoutColor.opacity(0.15), workoutColor.opacity(0.05)]
                            : [workoutColor.opacity(0.1), Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(workoutColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func quickStat(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
    }
    
    private var formattedDuration: String {
        let hours = Int(workout.duration) / 3600
        let minutes = Int(workout.duration) % 3600 / 60
        let seconds = Int(workout.duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Key Metrics Card
    private var keyMetricsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Metrics")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if workout.pace > 0 && isRunOrWalk {
                    metricTile("Avg Pace", value: formattedPace, icon: "speedometer", color: Color(hex: "8B5CF6"))
                }
                if workout.elevation > 0 {
                    metricTile("Elevation", value: String(format: "%.0f m", workout.elevation), icon: "mountain.2.fill", color: Color(hex: "F59E0B"))
                }
                if workout.cadence > 0 {
                    metricTile("Cadence", value: String(format: "%.0f spm", workout.cadence), icon: "metronome.fill", color: Color(hex: "06B6D4"))
                }
                if workout.powerOutput > 0 {
                    metricTile("Power", value: String(format: "%.0f W", workout.powerOutput), icon: "bolt.fill", color: Color(hex: "F472B6"))
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func metricTile(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(colorScheme == .dark ? 0.1 : 0.06)))
    }
    
    private var formattedPace: String {
        let paceMinutes = Int(workout.pace) / 60
        let paceSeconds = Int(workout.pace) % 60
        return String(format: "%d:%02d /km", paceMinutes, paceSeconds)
    }
    
    // MARK: - Heart Rate Card
    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(Color(hex: "EF4444"))
                Text("Heart Rate")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
            }
            
            HStack(spacing: 16) {
                heartRateMetric("Average", value: "\(workout.avgHeartRate)", color: Color(hex: "EF4444"))
                if workout.maxHeartRate > 0 {
                    heartRateMetric("Maximum", value: "\(workout.maxHeartRate)", color: Color(hex: "F59E0B"))
                }
                heartRateMetric("% of Max", value: String(format: "%.0f%%", heartRatePercentage), color: Color(hex: "3B82F6"))
            }
            
            // HR Zone bar
            VStack(alignment: .leading, spacing: 8) {
                Text("Heart Rate Zone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { zone in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(zone <= currentZone ? zoneColor(zone) : Color.gray.opacity(0.2))
                            .frame(height: 8)
                    }
                }
                
                Text(zoneName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(zoneColor(currentZone))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func heartRateMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(color)
                if !title.contains("%") {
                    Text("bpm")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.1)))
    }
    
    private var heartRatePercentage: Double {
        let maxHR = 190.0 // Estimate, should come from user profile
        return (Double(workout.avgHeartRate) / maxHR) * 100
    }
    
    private var currentZone: Int {
        let percentage = heartRatePercentage / 100
        switch percentage {
        case 0..<0.6: return 1
        case 0.6..<0.7: return 2
        case 0.7..<0.8: return 3
        case 0.8..<0.9: return 4
        default: return 5
        }
    }
    
    private var zoneName: String {
        switch currentZone {
        case 1: return "Zone 1 - Recovery"
        case 2: return "Zone 2 - Fat Burn"
        case 3: return "Zone 3 - Aerobic"
        case 4: return "Zone 4 - Threshold"
        default: return "Zone 5 - VO₂ Max"
        }
    }
    
    private func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(hex: "6B7280")
        case 2: return Color(hex: "10B981")
        case 3: return Color(hex: "F59E0B")
        case 4: return Color(hex: "EF4444")
        default: return Color(hex: "DC2626")
        }
    }
    
    // MARK: - Performance Card
    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Analysis")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 12) {
                performanceRow("Calories per Minute", value: String(format: "%.1f kcal/min", caloriesPerMinute), icon: "flame.fill", color: Color(hex: "F59E0B"))
                
                if workout.distance > 0 {
                    performanceRow("Average Speed", value: String(format: "%.1f km/h", averageSpeed), icon: "speedometer", color: Color(hex: "3B82F6"))
                }
                
                performanceRow("Workout Intensity", value: intensityLabel, icon: "bolt.fill", color: intensityColor)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func performanceRow(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.vertical, 8)
    }
    
    private var caloriesPerMinute: Double {
        guard workout.duration > 0 else { return 0 }
        return workout.calories / (workout.duration / 60.0)
    }
    
    private var averageSpeed: Double {
        guard workout.duration > 0 && workout.distance > 0 else { return 0 }
        return workout.distance / (workout.duration / 3600.0)
    }
    
    private var intensityLabel: String {
        let percentage = heartRatePercentage
        switch percentage {
        case 0..<50: return "Very Light"
        case 50..<60: return "Light"
        case 60..<70: return "Moderate"
        case 70..<80: return "Hard"
        case 80..<90: return "Very Hard"
        default: return "Maximum"
        }
    }
    
    private var intensityColor: Color {
        let percentage = heartRatePercentage
        switch percentage {
        case 0..<50: return Color(hex: "6B7280")
        case 50..<60: return Color(hex: "10B981")
        case 60..<70: return Color(hex: "3B82F6")
        case 70..<80: return Color(hex: "F59E0B")
        case 80..<90: return Color(hex: "EF4444")
        default: return Color(hex: "DC2626")
        }
    }
    
    // MARK: - Training Zones Card
    private var trainingZonesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Zones")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 8) {
                zoneRow(1, "Recovery", range: "< 60%", description: "Active recovery, very light")
                zoneRow(2, "Fat Burn", range: "60-70%", description: "Aerobic base building")
                zoneRow(3, "Aerobic", range: "70-80%", description: "Cardio fitness improvement")
                zoneRow(4, "Threshold", range: "80-90%", description: "Lactate threshold training")
                zoneRow(5, "VO₂ Max", range: "> 90%", description: "Maximum effort")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func zoneRow(_ zone: Int, _ name: String, range: String, description: String) -> some View {
        let isCurrentZone = zone == currentZone
        
        return HStack(spacing: 12) {
            Circle()
                .fill(zoneColor(zone))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isCurrentZone ? 2 : 0)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.system(size: 13, weight: isCurrentZone ? .bold : .medium))
                        .foregroundColor(isCurrentZone ? zoneColor(zone) : (colorScheme == .dark ? .white : Color(hex: "1A1A1A")))
                    
                    if isCurrentZone {
                        Text("CURRENT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(zoneColor(zone))
                            .clipShape(Capsule())
                    }
                }
                Text(description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            Spacer()
            
            Text(range)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrentZone ? zoneColor(zone).opacity(0.1) : Color.clear)
        )
    }
    
    // MARK: - Splits Card
    private var splitsCard: some View {
        let kmCount = Int(workout.distance)
        let avgPaceSeconds = workout.pace
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Splits")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            if kmCount > 0 {
                VStack(spacing: 0) {
                    ForEach(1...min(kmCount, 10), id: \.self) { km in
                        splitRow(km: km, pace: generatePaceVariation(avgPaceSeconds), isLast: km == min(kmCount, 10))
                    }
                    
                    if kmCount > 10 {
                        HStack {
                            Text("... and \(kmCount - 10) more kilometers")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                        }
                        .padding(.top, 8)
                    }
                }
            } else {
                Text("Distance too short for splits")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func splitRow(km: Int, pace: Double, isLast: Bool) -> some View {
        let paceMin = Int(pace) / 60
        let paceSec = Int(pace) % 60
        let avgPaceMin = Int(workout.pace) / 60
        let avgPaceSec = Int(workout.pace) % 60
        let diff = pace - workout.pace
        let isFaster = diff < 0
        
        return VStack(spacing: 0) {
            HStack {
                Text("Km \(km)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    .frame(width: 50, alignment: .leading)
                
                Spacer()
                
                Text(String(format: "%d:%02d", paceMin, paceSec))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isFaster ? Color(hex: "10B981") : Color(hex: "EF4444"))
                
                HStack(spacing: 2) {
                    Image(systemName: isFaster ? "arrow.down" : "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                    Text(String(format: "%+.0fs", diff))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isFaster ? Color(hex: "10B981") : Color(hex: "EF4444"))
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, 10)
            
            if !isLast {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .frame(height: 1)
            }
        }
    }
    
    private func generatePaceVariation(_ avgPace: Double) -> Double {
        // Generate realistic pace variations around the average
        let variation = Double.random(in: -15...15)
        return avgPace + variation
    }
    
    // MARK: - Recovery Card
    private var recoveryCard: some View {
        let estimatedRecovery = calculateRecoveryTime()
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(Color(hex: "8B5CF6"))
                Text("Recovery")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Estimated Recovery Time")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                    Spacer()
                    Text(estimatedRecovery)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "8B5CF6"))
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Tips")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    ForEach(recoveryTips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "10B981"))
                            Text(tip)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func calculateRecoveryTime() -> String {
        let intensity = heartRatePercentage / 100
        let duration = workout.duration / 3600.0
        let recoveryScore = intensity * duration * 24
        
        switch recoveryScore {
        case 0..<12: return "6-12 hours"
        case 12..<24: return "12-24 hours"
        case 24..<48: return "1-2 days"
        case 48..<72: return "2-3 days"
        default: return "3+ days"
        }
    }
    
    private var recoveryTips: [String] {
        var tips: [String] = []
        
        if heartRatePercentage > 80 {
            tips.append("High intensity - prioritize rest and sleep tonight")
            tips.append("Light stretching or yoga can aid recovery")
        } else if heartRatePercentage > 60 {
            tips.append("Moderate effort - light activity tomorrow is fine")
            tips.append("Stay hydrated throughout the day")
        } else {
            tips.append("Light session - you can train again tomorrow")
            tips.append("Great for active recovery days")
        }
        
        tips.append("Consume protein within 30 minutes post-workout")
        
        return tips
    }
}

// MARK: - Enhanced Workout Detail Sheet with Immersive Map
struct EnhancedWorkoutDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let workout: WorkoutLog
    let allMetrics: [HealthMetrics]
    
    @State private var showFullHeartRate = false
    @State private var selectedTab = 0
    
    private var routePoints: [RoutePoint] {
        RouteCoding.decode(workout.route)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Immersive background
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Immersive Map Hero (blends with background)
                            immersiveMapSection
                            
                            // Workout Summary Overlay
                            workoutSummaryOverlay
                                .padding(.top, -60)
                                .zIndex(1)
                            
                            VStack(spacing: 20) {
                                // Key Metrics Grid
                                keyMetricsGrid
                                
                                // Heart Rate Section
                                if workout.avgHeartRate > 0 {
                                    heartRateSection
                                }
                                
                                // AI Insights Card
                                aiInsightsCard
                                
                                // Performance Analysis
                                performanceAnalysisCard
                                
                                // Training Zones
                                if workout.avgHeartRate > 0 {
                                    trainingZonesCard
                                }
                                
                                // Splits (for runs/walks)
                                if workout.distance > 0 && isRunOrWalk {
                                    splitsCard
                                }
                                
                                // Recovery Section
                                recoveryCard
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                        // Prevent accidental horizontal scrolling by locking content width to the viewport
                        .frame(width: geo.size.width, alignment: .center)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(workoutColor)
                }
            }
        }
    }
    
    // MARK: - Immersive Map Section
    private var immersiveMapSection: some View {
        ZStack(alignment: .top) {
            if !routePoints.isEmpty {
                RouteMapView(points: routePoints, strokeColor: workoutColor)
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)
                    .mask(
                        LinearGradient(
                            colors: [.black, .black, .black.opacity(0.8), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        // Route info overlay
                        VStack {
                            Spacer()
                            HStack {
                                // Start marker
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("Start")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                
                                Spacer()
                                
                                // Distance badge
                                Text(String(format: "%.2f km", workout.distance))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(workoutColor.opacity(0.9), in: Capsule())
                                
                                Spacer()
                                
                                // End marker
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("Finish")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 80)
                        }
                    )
                    .clipped()
            } else {
                // No route - gradient header
                LinearGradient(
                    colors: [workoutColor.opacity(0.3), workoutColor.opacity(0.1), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Workout Summary Overlay
    private var workoutSummaryOverlay: some View {
        VStack(spacing: 16) {
            // Workout icon
            ZStack {
                Circle()
                    .fill(workoutColor.opacity(colorScheme == .dark ? 0.2 : 0.15))
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(workoutColor.opacity(0.3), lineWidth: 2)
                    .frame(width: 72, height: 72)
                Image(systemName: workoutIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(workoutColor)
            }
            
            VStack(spacing: 6) {
                Text(workout.workoutType.capitalized)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text(workout.timestamp.formatted(date: .complete, time: .shortened))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            
            // Quick stats row
            HStack(spacing: 32) {
                quickStatItem(formattedDuration, label: "Duration")
                if workout.distance > 0 {
                    quickStatItem(String(format: "%.2f km", workout.distance), label: "Distance")
                }
                quickStatItem("\(Int(workout.calories))", label: "Calories")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colorScheme == .dark ? Color(hex: "141416") : Color.white)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
        )
        .padding(.horizontal, 20)
    }
    
    private func quickStatItem(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
    }
    
    // MARK: - Key Metrics Grid
    private var keyMetricsGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Metrics")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if workout.pace > 0 && isRunOrWalk {
                    metricTile("Avg Pace", value: formattedPace, icon: "speedometer", color: Color(hex: "8B5CF6"))
                }
                if workout.elevation > 0 {
                    metricTile("Elevation", value: String(format: "%.0f m", workout.elevation), icon: "mountain.2.fill", color: Color(hex: "F59E0B"))
                }
                if workout.avgHeartRate > 0 {
                    metricTile("Avg HR", value: "\(workout.avgHeartRate) bpm", icon: "heart.fill", color: Color(hex: "EF4444"))
                }
                if workout.maxHeartRate > 0 {
                    metricTile("Max HR", value: "\(workout.maxHeartRate) bpm", icon: "heart.fill", color: Color(hex: "F97316"))
                }
                if workout.cadence > 0 {
                    metricTile("Cadence", value: String(format: "%.0f spm", workout.cadence), icon: "metronome.fill", color: Color(hex: "06B6D4"))
                }
                if workout.powerOutput > 0 {
                    metricTile("Power", value: String(format: "%.0f W", workout.powerOutput), icon: "bolt.fill", color: Color(hex: "F472B6"))
                }
                // Calories per minute
                metricTile("Cal/min", value: String(format: "%.1f", caloriesPerMinute), icon: "flame.fill", color: Color(hex: "F59E0B"))
                // Average speed
                if workout.distance > 0 {
                    metricTile("Avg Speed", value: String(format: "%.1f km/h", averageSpeed), icon: "gauge.with.needle.fill", color: Color(hex: "3B82F6"))
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func metricTile(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(colorScheme == .dark ? 0.1 : 0.06)))
    }
    
    // MARK: - Heart Rate Section with Graph
    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(Color(hex: "EF4444"))
                Text("Heart Rate")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                
                Button {
                    showFullHeartRate.toggle()
                } label: {
                    Text(showFullHeartRate ? "Less" : "More")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "EF4444"))
                }
            }
            
            // Heart rate stats
            HStack(spacing: 12) {
                hrStatBox("Average", value: "\(workout.avgHeartRate)", unit: "bpm", color: Color(hex: "EF4444"))
                if workout.maxHeartRate > 0 {
                    hrStatBox("Maximum", value: "\(workout.maxHeartRate)", unit: "bpm", color: Color(hex: "F59E0B"))
                }
                hrStatBox("Zone", value: "Z\(currentZone)", unit: zoneName.components(separatedBy: " - ").last ?? "", color: zoneColor(currentZone))
            }
            
            // Heart Rate Graph
            heartRateGraph
                .frame(height: showFullHeartRate ? 180 : 100)
                .animation(.easeInOut, value: showFullHeartRate)
            
            // Zone indicator bar
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { zone in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(zone <= currentZone ? zoneColor(zone) : Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .overlay(
                            zone == currentZone ?
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white, lineWidth: 1)
                            : nil
                        )
                }
            }
            
            Text(zoneName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(zoneColor(currentZone))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func hrStatBox(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.1)))
    }
    
    // Simulated heart rate graph
    private var heartRateGraph: some View {
        GeometryReader { geo in
            let points = generateHeartRatePoints(count: 30, width: geo.size.width, height: geo.size.height)
            
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(hex: "EF4444").opacity(0.2), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(heartRatePath(points: points, height: geo.size.height, closed: true))
                
                // Line
                heartRatePath(points: points, height: geo.size.height, closed: false)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "EF4444"), Color(hex: "F97316")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                
                // Avg HR line
                let avgY = geo.size.height * (1 - (Double(workout.avgHeartRate) - 60) / 140)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: avgY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: avgY))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundColor(Color(hex: "EF4444").opacity(0.5))
            }
        }
    }
    
    private func generateHeartRatePoints(count: Int, width: CGFloat, height: CGFloat) -> [CGPoint] {
        let baseHR = Double(workout.avgHeartRate)
        let variation = Double(workout.maxHeartRate - workout.avgHeartRate)
        var points: [CGPoint] = []
        
        for i in 0..<count {
            let x = width * CGFloat(i) / CGFloat(count - 1)
            let randomVariation = Double.random(in: -variation...variation) * 0.7
            let hr = baseHR + randomVariation
            let normalizedHR = (hr - 60) / 140 // Normalize to 60-200 bpm range
            let y = height * (1 - normalizedHR)
            points.append(CGPoint(x: x, y: max(0, min(height, y))))
        }
        return points
    }
    
    private func heartRatePath(points: [CGPoint], height: CGFloat, closed: Bool) -> Path {
        Path { path in
            guard points.count > 1 else { return }
            
            path.move(to: points[0])
            for i in 1..<points.count {
                let p0 = points[max(0, i - 2)]
                let p1 = points[i - 1]
                let p2 = points[i]
                let p3 = points[min(points.count - 1, i + 1)]
                
                let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
            
            if closed {
                path.addLine(to: CGPoint(x: points.last!.x, y: height))
                path.addLine(to: CGPoint(x: points.first!.x, y: height))
                path.closeSubpath()
            }
        }
    }
    
    // MARK: - AI Insights Card
    private var aiInsightsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "8B5CF6"))
                Text("AI Insights")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                Text("Powered by AI")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "8B5CF6").opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "8B5CF6").opacity(0.1), in: Capsule())
            }
            
            VStack(alignment: .leading, spacing: 14) {
                ForEach(generateAIInsights(), id: \.self) { insight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(insight.color)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                            Text(insight.description)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(hex: "8B5CF6").opacity(0.12), Color.white.opacity(0.05)]
                            : [Color(hex: "8B5CF6").opacity(0.06), Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: "8B5CF6").opacity(0.2), lineWidth: 1)
        )
    }
    
    private struct AIInsight: Hashable {
        let icon: String
        let title: String
        let description: String
        let color: Color
    }
    
    private func generateAIInsights() -> [AIInsight] {
        var insights: [AIInsight] = []
        
        // Pace insight
        if isRunOrWalk && workout.pace > 0 {
            let paceMin = Int(workout.pace) / 60
            if paceMin < 6 {
                insights.append(AIInsight(
                    icon: "flame.fill",
                    title: "Excellent Pace!",
                    description: "You're running at a competitive pace. This is great for building aerobic capacity and speed.",
                    color: Color(hex: "EF4444")
                ))
            } else if paceMin < 8 {
                insights.append(AIInsight(
                    icon: "heart.fill",
                    title: "Solid Training Pace",
                    description: "This pace is ideal for base building. You're improving cardiovascular fitness efficiently.",
                    color: Color(hex: "10B981")
                ))
            } else {
                insights.append(AIInsight(
                    icon: "leaf.fill",
                    title: "Easy Effort Zone",
                    description: "Great for recovery runs. This effort level promotes fat burning and builds endurance foundation.",
                    color: Color(hex: "3B82F6")
                ))
            }
        }
        
        // Heart rate insight
        if workout.avgHeartRate > 0 {
            let hrZone = currentZone
            if hrZone >= 4 {
                insights.append(AIInsight(
                    icon: "bolt.fill",
                    title: "High Intensity Training",
                    description: "You spent significant time in Zone \(hrZone). This improves VO₂ max but requires 24-48h recovery.",
                    color: Color(hex: "F59E0B")
                ))
            } else if hrZone == 2 || hrZone == 3 {
                insights.append(AIInsight(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Optimal Training Zone",
                    description: "Zone \(hrZone) training builds aerobic efficiency. Ideal for sustainable fitness gains.",
                    color: Color(hex: "10B981")
                ))
            }
        }
        
        // Duration insight
        if workout.duration > 1800 { // > 30 min
            insights.append(AIInsight(
                icon: "clock.fill",
                title: "Extended Session",
                description: "Great job completing a \(Int(workout.duration / 60))-minute workout. Consistency like this builds lasting fitness.",
                color: Color(hex: "8B5CF6")
            ))
        }
        
        // Calories insight
        let caloriesPerHour = workout.calories / (workout.duration / 3600.0)
        if caloriesPerHour > 400 {
            insights.append(AIInsight(
                icon: "flame.fill",
                title: "High Calorie Burn",
                description: "Burning \(Int(caloriesPerHour)) cal/hr is excellent. This session significantly contributes to your daily energy expenditure.",
                color: Color(hex: "F97316")
            ))
        }
        
        return insights
    }
    
    // MARK: - Performance Analysis Card
    private var performanceAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Analysis")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 12) {
                performanceRow("Calories per Minute", value: String(format: "%.1f kcal/min", caloriesPerMinute), icon: "flame.fill", color: Color(hex: "F59E0B"))
                
                if workout.distance > 0 {
                    performanceRow("Average Speed", value: String(format: "%.1f km/h", averageSpeed), icon: "speedometer", color: Color(hex: "3B82F6"))
                }
                
                performanceRow("Workout Intensity", value: intensityLabel, icon: "bolt.fill", color: intensityColor)
                
                if workout.avgHeartRate > 0 {
                    performanceRow("% of Max HR", value: String(format: "%.0f%%", heartRatePercentage), icon: "heart.fill", color: Color(hex: "EF4444"))
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func performanceRow(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Training Zones Card
    private var trainingZonesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Zones")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 8) {
                zoneRow(1, "Recovery", range: "< 60%", description: "Active recovery, very light")
                zoneRow(2, "Fat Burn", range: "60-70%", description: "Aerobic base building")
                zoneRow(3, "Aerobic", range: "70-80%", description: "Cardio fitness improvement")
                zoneRow(4, "Threshold", range: "80-90%", description: "Lactate threshold training")
                zoneRow(5, "VO₂ Max", range: "> 90%", description: "Maximum effort")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func zoneRow(_ zone: Int, _ name: String, range: String, description: String) -> some View {
        let isCurrentZone = zone == currentZone
        
        return HStack(spacing: 12) {
            Circle()
                .fill(zoneColor(zone))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isCurrentZone ? 2 : 0)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.system(size: 13, weight: isCurrentZone ? .bold : .medium))
                        .foregroundColor(isCurrentZone ? zoneColor(zone) : (colorScheme == .dark ? .white : Color(hex: "1A1A1A")))
                    
                    if isCurrentZone {
                        Text("CURRENT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(zoneColor(zone))
                            .clipShape(Capsule())
                    }
                }
                Text(description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            Spacer()
            
            Text(range)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrentZone ? zoneColor(zone).opacity(0.1) : Color.clear)
        )
    }
    
    // MARK: - Splits Card
    private var splitsCard: some View {
        let kmCount = Int(workout.distance)
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Splits")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            if kmCount > 0 {
                VStack(spacing: 0) {
                    ForEach(1...min(kmCount, 10), id: \.self) { km in
                        splitRow(km: km, pace: generatePaceVariation(workout.pace), isLast: km == min(kmCount, 10))
                    }
                }
            } else {
                Text("Distance too short for splits")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func splitRow(km: Int, pace: Double, isLast: Bool) -> some View {
        let paceMin = Int(pace) / 60
        let paceSec = Int(pace) % 60
        let diff = pace - workout.pace
        let isFaster = diff < 0
        
        return VStack(spacing: 0) {
            HStack {
                Text("Km \(km)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    .frame(width: 50, alignment: .leading)
                
                Spacer()
                
                Text(String(format: "%d:%02d", paceMin, paceSec))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isFaster ? Color(hex: "10B981") : Color(hex: "EF4444"))
                
                HStack(spacing: 2) {
                    Image(systemName: isFaster ? "arrow.down" : "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                    Text(String(format: "%+.0fs", diff))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isFaster ? Color(hex: "10B981") : Color(hex: "EF4444"))
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, 10)
            
            if !isLast {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .frame(height: 1)
            }
        }
    }
    
    private func generatePaceVariation(_ avgPace: Double) -> Double {
        Double.random(in: -15...15) + avgPace
    }
    
    // MARK: - Recovery Card
    private var recoveryCard: some View {
        let estimatedRecovery = calculateRecoveryTime()
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(Color(hex: "8B5CF6"))
                Text("Recovery")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Estimated Recovery Time")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                    Spacer()
                    Text(estimatedRecovery)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "8B5CF6"))
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Tips")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    ForEach(recoveryTips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "10B981"))
                            Text(tip)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func calculateRecoveryTime() -> String {
        let intensity = heartRatePercentage / 100
        let duration = workout.duration / 3600.0
        let recoveryScore = intensity * duration * 24
        
        switch recoveryScore {
        case 0..<12: return "6-12 hours"
        case 12..<24: return "12-24 hours"
        case 24..<48: return "1-2 days"
        case 48..<72: return "2-3 days"
        default: return "3+ days"
        }
    }
    
    private var recoveryTips: [String] {
        var tips: [String] = []
        
        if heartRatePercentage > 80 {
            tips.append("High intensity - prioritize rest and sleep tonight")
            tips.append("Light stretching or yoga can aid recovery")
        } else if heartRatePercentage > 60 {
            tips.append("Moderate effort - light activity tomorrow is fine")
            tips.append("Stay hydrated throughout the day")
        } else {
            tips.append("Light session - you can train again tomorrow")
            tips.append("Great for active recovery days")
        }
        
        tips.append("Consume protein within 30 minutes post-workout")
        
        return tips
    }
    
    // MARK: - Helper Properties
    private var isRunOrWalk: Bool {
        let type = workout.workoutType.lowercased()
        return type.contains("run") || type.contains("walk")
    }
    
    private var workoutColor: Color {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("run"): return Color(hex: "E07A5F")
        case let t where t.contains("walk"): return Color(hex: "10B981")
        case let t where t.contains("bike") || t.contains("cycl"): return Color(hex: "3B82F6")
        case let t where t.contains("strength") || t.contains("weight"): return Color(hex: "8B5CF6")
        case let t where t.contains("swim"): return Color(hex: "06B6D4")
        case let t where t.contains("yoga"): return Color(hex: "F472B6")
        default: return Color(hex: "6B7280")
        }
    }
    
    private var workoutIcon: String {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("run"): return "figure.run"
        case let t where t.contains("walk"): return "figure.walk"
        case let t where t.contains("bike") || t.contains("cycl"): return "bicycle"
        case let t where t.contains("strength") || t.contains("weight"): return "dumbbell.fill"
        case let t where t.contains("swim"): return "figure.pool.swim"
        case let t where t.contains("yoga"): return "figure.yoga"
        default: return "figure.mixed.cardio"
        }
    }
    
    private var formattedDuration: String {
        let hours = Int(workout.duration) / 3600
        let minutes = Int(workout.duration) % 3600 / 60
        let seconds = Int(workout.duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var formattedPace: String {
        let paceMinutes = Int(workout.pace) / 60
        let paceSeconds = Int(workout.pace) % 60
        return String(format: "%d:%02d /km", paceMinutes, paceSeconds)
    }
    
    private var caloriesPerMinute: Double {
        guard workout.duration > 0 else { return 0 }
        return workout.calories / (workout.duration / 60.0)
    }
    
    private var averageSpeed: Double {
        guard workout.duration > 0 && workout.distance > 0 else { return 0 }
        return workout.distance / (workout.duration / 3600.0)
    }
    
    private var heartRatePercentage: Double {
        let maxHR = 190.0
        return (Double(workout.avgHeartRate) / maxHR) * 100
    }
    
    private var currentZone: Int {
        let percentage = heartRatePercentage / 100
        switch percentage {
        case 0..<0.6: return 1
        case 0.6..<0.7: return 2
        case 0.7..<0.8: return 3
        case 0.8..<0.9: return 4
        default: return 5
        }
    }
    
    private var zoneName: String {
        switch currentZone {
        case 1: return "Zone 1 - Recovery"
        case 2: return "Zone 2 - Fat Burn"
        case 3: return "Zone 3 - Aerobic"
        case 4: return "Zone 4 - Threshold"
        default: return "Zone 5 - VO₂ Max"
        }
    }
    
    private func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(hex: "6B7280")
        case 2: return Color(hex: "10B981")
        case 3: return Color(hex: "F59E0B")
        case 4: return Color(hex: "EF4444")
        default: return Color(hex: "DC2626")
        }
    }
    
    private var intensityLabel: String {
        let percentage = heartRatePercentage
        switch percentage {
        case 0..<50: return "Very Light"
        case 50..<60: return "Light"
        case 60..<70: return "Moderate"
        case 70..<80: return "Hard"
        case 80..<90: return "Very Hard"
        default: return "Maximum"
        }
    }
    
    private var intensityColor: Color {
        let percentage = heartRatePercentage
        switch percentage {
        case 0..<50: return Color(hex: "6B7280")
        case 50..<60: return Color(hex: "10B981")
        case 60..<70: return Color(hex: "3B82F6")
        case 70..<80: return Color(hex: "F59E0B")
        case 80..<90: return Color(hex: "EF4444")
        default: return Color(hex: "DC2626")
        }
    }
}

// MARK: - Battery Detail Sheet
struct BatteryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let batteryLevel: Int
    let metrics: HealthMetrics?
    let allMetrics: [HealthMetrics]
    
    // Interactive chart state
    @State private var selectedBarIndex: Int? = nil
    @State private var isDragging = false
    
    private var batteryColor: Color {
        switch batteryLevel {
        case 70...100: return Color(hex: "10B981")
        case 40...69: return Color(hex: "F59E0B")
        case 20...39: return Color(hex: "F97316")
        default: return Color(hex: "EF4444")
        }
    }
    
    private var batteryLabel: String {
        switch batteryLevel {
        case 80...100: return "Fully Charged"
        case 60...79: return "Good Energy"
        case 40...59: return "Moderate"
        case 20...39: return "Low Energy"
        default: return "Need Recharge"
        }
    }
    
    // Generate hourly battery data for the day
    private var hourlyBatteryData: [(hour: Int, level: Int, label: String)] {
        let sleepHours = metrics?.sleepHours ?? 7
        let activeCalories = metrics?.activeCalories ?? 0
        let steps = Int(metrics?.stepCount ?? 0)
        let hrv = metrics?.hrv ?? 50
        let currentHour = Calendar.current.component(.hour, from: Date())
        
        var data: [(hour: Int, level: Int, label: String)] = []
        
        // Generate data from 6 AM to current hour
        for hour in 6...min(currentHour, 23) {
            var battery = min(100, Int(sleepHours / 8.0 * 100))
            
            // Morning boost (6-8 AM)
            if hour <= 8 {
                battery = min(100, battery + 5)
            }
            
            // Deplete based on time awake
            let hoursAwake = max(0, hour - 7)
            battery -= hoursAwake * 4
            
            // Mid-day dip (2-4 PM)
            if hour >= 14 && hour <= 16 {
                battery -= 8
            }
            
            // Activity depletion scales with time of day
            let hourFraction = Double(hour - 6) / 16.0
            let activityDepletion = Int(Double(activeCalories) * hourFraction / 50) + Int(Double(steps) * hourFraction / 2000)
            battery -= activityDepletion
            
            // HRV recovery boost
            if hrv > 50 {
                battery += 5
            }
            
            battery = max(5, min(100, battery))
            
            let label: String
            switch battery {
            case 80...100: label = "Peak"
            case 60...79: label = "Good"
            case 40...59: label = "Moderate"
            case 20...39: label = "Low"
            default: label = "Critical"
            }
            
            data.append((hour: hour, level: battery, label: label))
        }
        
        return data
    }
    
    private func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 70...100: return Color(hex: "10B981")
        case 40...69: return Color(hex: "F59E0B")
        case 20...39: return Color(hex: "F97316")
        default: return Color(hex: "EF4444")
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Current Status Card
                        currentStatusCard
                        
                        // Hourly Chart
                        hourlyChartCard
                        
                        // Energy Insights
                        insightsCard
                        
                        // Tips Card
                        tipsCard
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Energy Battery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(batteryColor)
                }
            }
        }
    }
    
    private var currentStatusCard: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Current Energy")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                Text(batteryLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(batteryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(batteryColor.opacity(0.15))
                    )
            }
            
            HStack(spacing: 24) {
                // Large battery visualization
                ZStack {
                    // Battery outline
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(batteryColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 80, height: 44)
                    
                    // Battery fill
                    HStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [batteryColor, batteryColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, 72 * CGFloat(batteryLevel) / 100), height: 36)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .frame(width: 80, height: 44)
                    
                    // Battery cap
                    RoundedRectangle(cornerRadius: 2)
                        .fill(batteryColor.opacity(0.5))
                        .frame(width: 6, height: 18)
                        .offset(x: 44)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(batteryLevel)%")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text(estimatedRemaining)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
            }
            
            // Progress bar with zone colors
            GeometryReader { geo in
                let safeWidth = max(0, geo.size.width)
                ZStack(alignment: .leading) {
                    // Zone background
                    HStack(spacing: 0) {
                        Color(hex: "EF4444").opacity(0.2)
                            .frame(width: safeWidth * 0.2)
                        Color(hex: "F97316").opacity(0.2)
                            .frame(width: safeWidth * 0.2)
                        Color(hex: "F59E0B").opacity(0.2)
                            .frame(width: safeWidth * 0.3)
                        Color(hex: "10B981").opacity(0.2)
                            .frame(width: safeWidth * 0.3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // Current level indicator
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [batteryColor, batteryColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, safeWidth * CGFloat(batteryLevel) / 100))
                }
            }
            .frame(height: 12)
            
            // Zone labels
            HStack {
                Text("Critical").font(.system(size: 9)).foregroundColor(Color(hex: "EF4444"))
                Spacer()
                Text("Low").font(.system(size: 9)).foregroundColor(Color(hex: "F97316"))
                Spacer()
                Text("Moderate").font(.system(size: 9)).foregroundColor(Color(hex: "F59E0B"))
                Spacer()
                Text("Good").font(.system(size: 9)).foregroundColor(Color(hex: "10B981"))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private var estimatedRemaining: String {
        let remainingHours = (batteryLevel * 16) / 100
        if remainingHours > 8 {
            return "~\(remainingHours)h of energy left"
        } else if remainingHours > 4 {
            return "Consider taking a break soon"
        } else {
            return "Recharge recommended"
        }
    }
    
    private var hourlyChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Energy Timeline")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                Text("Touch to explore")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            if hourlyBatteryData.isEmpty {
                Text("Data will appear as the day progresses")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                // Selected value tooltip
                if let idx = selectedBarIndex, idx < hourlyBatteryData.count {
                    let data = hourlyBatteryData[idx]
                    HStack(spacing: 12) {
                        Circle()
                            .fill(colorForLevel(data.level))
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatHourFull(data.hour))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                            Text("\(data.level)% • \(data.label)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorForLevel(data.level))
                        }
                        Spacer()
                        Text(batteryStatusText(data.level))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorForLevel(data.level).opacity(colorScheme == .dark ? 0.15 : 0.1))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                // Chart area
                VStack(spacing: 8) {
                    // Y-axis labels
                    HStack {
                        Text("100%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)
                        Spacer()
                    }
                    
                    // Interactive Chart
                    GeometryReader { geo in
                        let chartWidth = max(0, geo.size.width - 40)
                        let dataCount = max(1, hourlyBatteryData.count)
                        let spacing: CGFloat = min(6, chartWidth / CGFloat(dataCount) / 3)
                        let barWidth = max(4, (chartWidth - CGFloat(dataCount - 1) * spacing) / CGFloat(dataCount))
                        let totalBarArea = barWidth + spacing
                        
                        ZStack(alignment: .bottomLeading) {
                            // Grid lines
                            ForEach([25, 50, 75], id: \.self) { line in
                                Rectangle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15))
                                    .frame(height: 1)
                                    .offset(y: -max(0, geo.size.height) * CGFloat(line) / 100)
                            }
                            
                            // Bars
                            HStack(alignment: .bottom, spacing: spacing) {
                                ForEach(Array(hourlyBatteryData.enumerated()), id: \.offset) { index, data in
                                    VStack(spacing: 4) {
                                        // Bar
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(
                                                LinearGradient(
                                                    colors: [colorForLevel(data.level), colorForLevel(data.level).opacity(0.6)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                            .frame(width: barWidth, height: max(4, geo.size.height * CGFloat(data.level) / 100))
                                            .opacity(selectedBarIndex == nil || selectedBarIndex == index ? 1 : 0.4)
                                            .scaleEffect(selectedBarIndex == index ? 1.05 : 1.0, anchor: .bottom)
                                    }
                                }
                            }
                            .padding(.leading, 35)
                            
                            // Selection indicator line
                            if let idx = selectedBarIndex, idx < hourlyBatteryData.count {
                                let xPos = 35 + CGFloat(idx) * totalBarArea + barWidth / 2
                                Rectangle()
                                    .fill(colorForLevel(hourlyBatteryData[idx].level))
                                    .frame(width: 2)
                                    .position(x: xPos, y: geo.size.height / 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let x = location.x - 35
                            if x >= 0 && dataCount > 0 {
                                let index = Int(x / totalBarArea)
                                if index >= 0 && index < hourlyBatteryData.count {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        selectedBarIndex = index
                                    }
                                    // Auto-dismiss after 3 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            selectedBarIndex = nil
                                        }
                                    }
                                }
                            }
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                                .onChanged { value in
                                    // Only respond to mostly horizontal drags
                                    let horizontalDistance = abs(value.translation.width)
                                    let verticalDistance = abs(value.translation.height)
                                    
                                    if horizontalDistance > verticalDistance {
                                        isDragging = true
                                        let x = value.location.x - 35
                                        if x >= 0 && dataCount > 0 {
                                            let index = Int(x / totalBarArea)
                                            if index >= 0 && index < hourlyBatteryData.count {
                                                withAnimation(.easeOut(duration: 0.1)) {
                                                    selectedBarIndex = index
                                                }
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    // Keep selection visible for a moment then fade
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        if !isDragging {
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                selectedBarIndex = nil
                                            }
                                        }
                                    }
                                }
                        )
                    }
                    .frame(height: 140)
                    
                    // Y-axis labels (bottom)
                    HStack {
                        Text("0%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)
                        Spacer()
                    }
                    
                    // X-axis labels (fixed widths to prevent horizontal panning)
                    GeometryReader { geo in
                        let count = max(1, hourlyBatteryData.count)
                        let availableWidth = max(0, geo.size.width - 30)
                        let cellWidth = availableWidth / CGFloat(count)
                        
                        HStack(spacing: 0) {
                            Spacer().frame(width: 30)
                            ForEach(Array(hourlyBatteryData.enumerated()), id: \.offset) { index, data in
                                Text(formatHour(data.hour))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(selectedBarIndex == index ? colorForLevel(data.level) : .secondary)
                                    .fontWeight(selectedBarIndex == index ? .bold : .medium)
                                    .frame(width: cellWidth, alignment: .center)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 12)
                }
                
                // Legend
                HStack(spacing: 16) {
                    legendItem("Peak", color: Color(hex: "10B981"))
                    legendItem("Good", color: Color(hex: "F59E0B"))
                    legendItem("Low", color: Color(hex: "F97316"))
                    legendItem("Critical", color: Color(hex: "EF4444"))
                }
                .padding(.top, 8)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func batteryStatusText(_ level: Int) -> String {
        switch level {
        case 80...100: return "Fully charged"
        case 60...79: return "Good reserves"
        case 40...59: return "Consider rest"
        case 20...39: return "Take a break"
        default: return "Recharge needed"
        }
    }
    
    private func formatHourFull(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:00 a"
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return formatHour(hour)
    }
    
    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == 0 || hour == 12 {
            return hour == 0 ? "12a" : "12p"
        }
        return hour < 12 ? "\(hour)a" : "\(hour - 12)p"
    }
    
    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Energy Insights")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 12) {
                insightRow(
                    icon: "moon.fill",
                    title: "Sleep Foundation",
                    value: String(format: "%.1f hrs", metrics?.sleepHours ?? 0),
                    detail: (metrics?.sleepHours ?? 0) >= 7 ? "Good recovery" : "Consider more rest",
                    color: (metrics?.sleepHours ?? 0) >= 7 ? Color(hex: "10B981") : Color(hex: "F59E0B")
                )
                
                insightRow(
                    icon: "flame.fill",
                    title: "Energy Spent",
                    value: "\(Int(metrics?.activeCalories ?? 0)) kcal",
                    detail: "Activity depletes battery",
                    color: Color(hex: "FF6B6B")
                )
                
                insightRow(
                    icon: "heart.fill",
                    title: "Recovery Capacity",
                    value: String(format: "%.0f ms", metrics?.hrv ?? 0),
                    detail: (metrics?.hrv ?? 0) > 50 ? "Good HRV" : "Monitor stress",
                    color: (metrics?.hrv ?? 0) > 50 ? Color(hex: "10B981") : Color(hex: "F59E0B")
                )
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func insightRow(icon: String, title: String, value: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(color)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color(hex: "F8F8FA")))
    }
    
    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recharge Tips")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(alignment: .leading, spacing: 10) {
                tipRow("☀️", "Morning sunlight boosts energy")
                tipRow("💧", "Stay hydrated throughout the day")
                tipRow("🚶", "Short walks help maintain energy")
                tipRow("😴", "Power naps (10-20 min) recharge effectively")
                tipRow("🥗", "Balanced meals prevent energy crashes")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func tipRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 16))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
        }
    }
}

// MARK: - Stress Detail Sheet
struct StressDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let stressLevel: Int
    let metrics: HealthMetrics?
    let allMetrics: [HealthMetrics]
    
    // Interactive chart state
    @State private var selectedPointIndex: Int? = nil
    @State private var isDragging = false
    
    private var stressColor: Color {
        switch stressLevel {
        case 0...25: return Color(hex: "10B981")
        case 26...50: return Color(hex: "3B82F6")
        case 51...70: return Color(hex: "F59E0B")
        case 71...85: return Color(hex: "F97316")
        default: return Color(hex: "EF4444")
        }
    }
    
    private var stressLabel: String {
        switch stressLevel {
        case 0...25: return "Calm"
        case 26...50: return "Relaxed"
        case 51...70: return "Moderate"
        case 71...85: return "Elevated"
        default: return "High Stress"
        }
    }
    
    private var stressIcon: String {
        switch stressLevel {
        case 0...25: return "leaf.fill"
        case 26...50: return "wind"
        case 51...70: return "cloud.fill"
        case 71...85: return "cloud.bolt.fill"
        default: return "bolt.horizontal.fill"
        }
    }
    
    // Generate hourly stress data for the day
    private var hourlyStressData: [(hour: Int, level: Int, label: String)] {
        let hrv = metrics?.hrv ?? 50
        let restingHR = Int(metrics?.restingHeartRate ?? 65)
        let sleepHours = metrics?.sleepHours ?? 7
        let currentHour = Calendar.current.component(.hour, from: Date())
        
        var data: [(hour: Int, level: Int, label: String)] = []
        
        // Generate data from 6 AM to current hour
        for hour in 6...min(currentHour, 23) {
            var stress = 30 // Base stress
            
            // Morning cortisol spike (natural)
            if hour >= 6 && hour <= 9 {
                stress += 15
            }
            
            // Work hours stress (9 AM - 5 PM)
            if hour >= 9 && hour <= 17 {
                stress += Int.random(in: 10...25)
            }
            
            // Mid-afternoon peak
            if hour >= 14 && hour <= 16 {
                stress += 10
            }
            
            // Evening wind-down
            if hour >= 18 {
                stress -= (hour - 17) * 5
            }
            
            // HRV influence
            if hrv > 0 {
                if hrv < 25 { stress += 25 }
                else if hrv < 40 { stress += 15 }
                else if hrv < 50 { stress += 5 }
                else { stress -= 10 }
            }
            
            // Resting HR influence
            if restingHR > 80 { stress += 10 }
            else if restingHR < 60 { stress -= 5 }
            
            // Sleep debt influence
            if sleepHours < 6 { stress += 15 }
            else if sleepHours > 7 { stress -= 5 }
            
            stress = max(5, min(100, stress))
            
            let label: String
            switch stress {
            case 0...25: label = "Calm"
            case 26...50: label = "Relaxed"
            case 51...70: label = "Moderate"
            case 71...85: label = "Elevated"
            default: label = "High"
            }
            
            data.append((hour: hour, level: stress, label: label))
        }
        
        return data
    }
    
    private func colorForStress(_ level: Int) -> Color {
        switch level {
        case 0...25: return Color(hex: "10B981")
        case 26...50: return Color(hex: "3B82F6")
        case 51...70: return Color(hex: "F59E0B")
        case 71...85: return Color(hex: "F97316")
        default: return Color(hex: "EF4444")
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA")).ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Current Status Card
                        currentStatusCard
                        
                        // Hourly Chart
                        hourlyChartCard
                        
                        // Stress Factors
                        stressFactorsCard
                        
                        // Management Tips
                        managementTipsCard
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Stress Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(stressColor)
                }
            }
        }
    }
    
    private var currentStatusCard: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Current Stress Level")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                Text(stressLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(stressColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(stressColor.opacity(0.15))
                    )
            }
            
            HStack(spacing: 24) {
                // Stress gauge
                ZStack {
                    // Background arc
                    Circle()
                        .trim(from: 0.2, to: 0.8)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "10B981").opacity(0.3), Color(hex: "EF4444").opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(90))
                    
                    // Progress arc
                    Circle()
                        .trim(from: 0.2, to: 0.2 + (0.6 * CGFloat(stressLevel) / 100))
                        .stroke(
                            stressColor,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(90))
                    
                    VStack(spacing: 2) {
                        Image(systemName: stressIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(stressColor)
                        Text("\(stressLevel)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(stressDescription)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : Color(hex: "4B5563"))
                        .lineSpacing(4)
                }
                
                Spacer()
            }
            
            // Stress level bar with zone colors
            GeometryReader { geo in
                let safeWidth = max(0, geo.size.width)
                ZStack(alignment: .leading) {
                    // Zone background
                    HStack(spacing: 0) {
                        Color(hex: "10B981").opacity(0.3)
                            .frame(width: safeWidth * 0.25)
                        Color(hex: "3B82F6").opacity(0.3)
                            .frame(width: safeWidth * 0.25)
                        Color(hex: "F59E0B").opacity(0.3)
                            .frame(width: safeWidth * 0.25)
                        Color(hex: "EF4444").opacity(0.3)
                            .frame(width: safeWidth * 0.25)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // Current position indicator
                    Circle()
                        .fill(stressColor)
                        .frame(width: 16, height: 16)
                        .shadow(color: stressColor.opacity(0.5), radius: 4, x: 0, y: 0)
                        .offset(x: max(8, min(safeWidth - 8, safeWidth * CGFloat(stressLevel) / 100 - 8)))
                }
            }
            .frame(height: 12)
            
            // Zone labels
            HStack {
                Text("Calm").font(.system(size: 9)).foregroundColor(Color(hex: "10B981"))
                Spacer()
                Text("Relaxed").font(.system(size: 9)).foregroundColor(Color(hex: "3B82F6"))
                Spacer()
                Text("Moderate").font(.system(size: 9)).foregroundColor(Color(hex: "F59E0B"))
                Spacer()
                Text("High").font(.system(size: 9)).foregroundColor(Color(hex: "EF4444"))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private var stressDescription: String {
        switch stressLevel {
        case 0...25:
            return "Your body shows signs of deep relaxation. Great time for creative work or recovery."
        case 26...50:
            return "You're in a healthy baseline state. Normal alertness without strain."
        case 51...70:
            return "Moderate stress detected. Consider taking short breaks to maintain balance."
        case 71...85:
            return "Elevated stress levels. Your body needs rest and recovery time."
        default:
            return "High stress alert. Prioritize relaxation techniques and rest."
        }
    }
    
    private var hourlyChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Stress Timeline")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Spacer()
                Text("Touch to explore")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            if hourlyStressData.isEmpty {
                Text("Data will appear as the day progresses")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                // Selected value tooltip
                if let idx = selectedPointIndex, idx < hourlyStressData.count {
                    let data = hourlyStressData[idx]
                    HStack(spacing: 12) {
                        Image(systemName: stressIconFor(data.level))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorForStress(data.level))
                            .frame(width: 32, height: 32)
                            .background(colorForStress(data.level).opacity(0.15))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatHourFull(data.hour))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                            Text("\(data.level)% stress • \(data.label)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorForStress(data.level))
                        }
                        Spacer()
                        Text(stressAdviceFor(data.level))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorForStress(data.level).opacity(colorScheme == .dark ? 0.15 : 0.1))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                // Chart area with line graph
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        let chartWidth = max(1, geo.size.width - 40)
                        let chartHeight = max(1, geo.size.height)
                        let dataCount = max(1, hourlyStressData.count)
                        let pointSpacing = chartWidth / CGFloat(max(dataCount - 1, 1))
                        
                        ZStack {
                            // Grid lines
                            ForEach([25, 50, 75], id: \.self) { line in
                                HStack {
                                    Text("\(line)")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 25, alignment: .trailing)
                                    Rectangle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15))
                                        .frame(height: 1)
                                }
                                .offset(y: chartHeight * (1 - CGFloat(line) / 100) - chartHeight / 2)
                            }
                            
                            // Area fill
                            Path { path in
                                guard !hourlyStressData.isEmpty, chartHeight > 0, chartWidth > 0 else { return }
                                
                                path.move(to: CGPoint(x: 35, y: chartHeight))
                                
                                for (index, data) in hourlyStressData.enumerated() {
                                    let x = 35 + CGFloat(index) * pointSpacing
                                    let y = max(0, chartHeight * (1 - CGFloat(data.level) / 100))
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                                
                                if !hourlyStressData.isEmpty {
                                    let lastX = 35 + CGFloat(hourlyStressData.count - 1) * pointSpacing
                                    path.addLine(to: CGPoint(x: lastX, y: chartHeight))
                                }
                                path.closeSubpath()
                            }
                            .fill(
                                LinearGradient(
                                    colors: [stressColor.opacity(0.3), stressColor.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            
                            // Line
                            Path { path in
                                guard !hourlyStressData.isEmpty, chartHeight > 0, chartWidth > 0 else { return }
                                
                                for (index, data) in hourlyStressData.enumerated() {
                                    let x = 35 + CGFloat(index) * pointSpacing
                                    let y = max(0, chartHeight * (1 - CGFloat(data.level) / 100))
                                    
                                    if index == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(
                                LinearGradient(
                                    colors: [stressColor, stressColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                            
                            // Data points
                            ForEach(Array(hourlyStressData.enumerated()), id: \.offset) { index, data in
                                let x = 35 + CGFloat(index) * pointSpacing
                                let y = max(0, min(chartHeight, chartHeight * (1 - CGFloat(data.level) / 100)))
                                
                                Circle()
                                    .fill(colorForStress(data.level))
                                    .frame(width: selectedPointIndex == index ? 14 : 8, height: selectedPointIndex == index ? 14 : 8)
                                    .shadow(color: colorForStress(data.level).opacity(0.5), radius: selectedPointIndex == index ? 4 : 2, x: 0, y: 0)
                                    .position(x: x, y: y)
                                    .opacity(selectedPointIndex == nil || selectedPointIndex == index ? 1 : 0.4)
                            }
                            
                            // Selection indicator line
                            if let idx = selectedPointIndex, idx < hourlyStressData.count {
                                let x = 35 + CGFloat(idx) * pointSpacing
                                Rectangle()
                                    .fill(colorForStress(hourlyStressData[idx].level).opacity(0.5))
                                    .frame(width: 1)
                                    .position(x: x, y: chartHeight / 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let x = location.x - 35
                            if x >= 0 && dataCount > 1 {
                                let index = Int(round(x / pointSpacing))
                                if index >= 0 && index < hourlyStressData.count {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        selectedPointIndex = index
                                    }
                                    // Auto-dismiss after 3 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            selectedPointIndex = nil
                                        }
                                    }
                                }
                            } else if dataCount == 1 {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedPointIndex = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        selectedPointIndex = nil
                                    }
                                }
                            }
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                                .onChanged { value in
                                    // Only respond to mostly horizontal drags
                                    let horizontalDistance = abs(value.translation.width)
                                    let verticalDistance = abs(value.translation.height)
                                    
                                    if horizontalDistance > verticalDistance {
                                        isDragging = true
                                        let x = value.location.x - 35
                                        if x >= 0 && dataCount > 1 {
                                            let index = Int(round(x / pointSpacing))
                                            if index >= 0 && index < hourlyStressData.count {
                                                withAnimation(.easeOut(duration: 0.1)) {
                                                    selectedPointIndex = index
                                                }
                                            }
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    // Keep selection visible for a moment then fade
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        if !isDragging {
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                selectedPointIndex = nil
                                            }
                                        }
                                    }
                                }
                        )
                    }
                    .frame(height: 140)
                    
                    // X-axis labels (fixed widths to prevent horizontal panning)
                    GeometryReader { geo in
                        let count = max(1, hourlyStressData.count)
                        let availableWidth = max(0, geo.size.width - 35)
                        let cellWidth = availableWidth / CGFloat(count)
                        let denseLabels = hourlyStressData.count <= 8
                        
                        HStack(spacing: 0) {
                            Spacer().frame(width: 35)
                            ForEach(Array(hourlyStressData.enumerated()), id: \.offset) { index, data in
                                Group {
                                    if denseLabels || index % 2 == 0 {
                                        Text(formatHour(data.hour))
                                            .font(.system(size: 8, weight: selectedPointIndex == index ? .bold : .medium))
                                            .foregroundColor(selectedPointIndex == index ? colorForStress(data.level) : .secondary)
                                    } else {
                                        Text("")
                                    }
                                }
                                .frame(width: cellWidth, alignment: .center)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 12)
                }
                
                // Stats summary
                HStack(spacing: 20) {
                    statBox("Average", value: "\(averageStress)%", color: colorForStress(averageStress))
                    statBox("Peak", value: "\(peakStress)%", color: colorForStress(peakStress))
                    statBox("Low", value: "\(lowestStress)%", color: colorForStress(lowestStress))
                }
                .padding(.top, 12)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private var averageStress: Int {
        guard !hourlyStressData.isEmpty else { return 0 }
        return hourlyStressData.reduce(0) { $0 + $1.level } / hourlyStressData.count
    }
    
    private var peakStress: Int {
        hourlyStressData.map { $0.level }.max() ?? 0
    }
    
    private var lowestStress: Int {
        hourlyStressData.map { $0.level }.min() ?? 0
    }
    
    private func statBox(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color(hex: "F8F8FA")))
    }
    
    private func formatHour(_ hour: Int) -> String {
        if hour == 0 || hour == 12 {
            return hour == 0 ? "12a" : "12p"
        }
        return hour < 12 ? "\(hour)a" : "\(hour - 12)p"
    }
    
    private func formatHourFull(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:00 a"
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return formatHour(hour)
    }
    
    private func stressIconFor(_ level: Int) -> String {
        switch level {
        case 0...25: return "leaf.fill"
        case 26...50: return "wind"
        case 51...70: return "cloud.fill"
        case 71...85: return "cloud.bolt.fill"
        default: return "bolt.horizontal.fill"
        }
    }
    
    private func stressAdviceFor(_ level: Int) -> String {
        switch level {
        case 0...25: return "Great time for focus"
        case 26...50: return "Normal baseline"
        case 51...70: return "Take a short break"
        case 71...85: return "Rest recommended"
        default: return "Relax & breathe"
        }
    }
    
    private var stressFactorsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stress Factors")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 12) {
                factorRow(
                    icon: "heart.fill",
                    title: "Heart Rate Variability",
                    value: String(format: "%.0f ms", metrics?.hrv ?? 0),
                    impact: hrvImpact,
                    color: hrvColor
                )
                
                factorRow(
                    icon: "waveform.path.ecg",
                    title: "Resting Heart Rate",
                    value: "\(Int(metrics?.restingHeartRate ?? 0)) bpm",
                    impact: restingHRImpact,
                    color: restingHRColor
                )
                
                factorRow(
                    icon: "moon.fill",
                    title: "Sleep Quality",
                    value: String(format: "%.1f hrs", metrics?.sleepHours ?? 0),
                    impact: sleepImpact,
                    color: sleepColor
                )
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private var hrvImpact: String {
        let hrv = metrics?.hrv ?? 0
        if hrv > 50 { return "Low stress indicator" }
        else if hrv > 35 { return "Moderate stress" }
        else { return "Elevated stress signal" }
    }
    
    private var hrvColor: Color {
        let hrv = metrics?.hrv ?? 0
        if hrv > 50 { return Color(hex: "10B981") }
        else if hrv > 35 { return Color(hex: "F59E0B") }
        else { return Color(hex: "EF4444") }
    }
    
    private var restingHRImpact: String {
        let rhr = Int(metrics?.restingHeartRate ?? 0)
        if rhr < 60 { return "Excellent recovery" }
        else if rhr < 70 { return "Normal range" }
        else { return "May indicate stress" }
    }
    
    private var restingHRColor: Color {
        let rhr = Int(metrics?.restingHeartRate ?? 0)
        if rhr < 60 { return Color(hex: "10B981") }
        else if rhr < 70 { return Color(hex: "3B82F6") }
        else { return Color(hex: "F59E0B") }
    }
    
    private var sleepImpact: String {
        let sleep = metrics?.sleepHours ?? 0
        if sleep >= 7 { return "Supports recovery" }
        else if sleep >= 6 { return "Slightly low" }
        else { return "May increase stress" }
    }
    
    private var sleepColor: Color {
        let sleep = metrics?.sleepHours ?? 0
        if sleep >= 7 { return Color(hex: "10B981") }
        else if sleep >= 6 { return Color(hex: "F59E0B") }
        else { return Color(hex: "EF4444") }
    }
    
    private func factorRow(icon: String, title: String, value: String, impact: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Text(impact)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(color)
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color(hex: "F8F8FA")))
    }
    
    private var managementTipsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stress Management")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(alignment: .leading, spacing: 10) {
                tipRow("🧘", "Deep breathing: 4s in, 7s hold, 8s out")
                tipRow("🚶", "Take a 5-min walk outside")
                tipRow("💤", "Prioritize 7-8 hours of sleep")
                tipRow("📵", "Digital detox before bedtime")
                tipRow("🎵", "Listen to calming music or nature sounds")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
    }
    
    private func tipRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 16))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    SmartDashboardView()
        .environment(\.managedObjectContext, context)
        .environmentObject(HealthKitService(context: context))
}
