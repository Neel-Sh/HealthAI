import SwiftUI
import CoreData
import Charts
import Combine

// MARK: - Professional Running Dashboard
struct RunningView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var advancedService = AdvancedRunningService.shared
    @StateObject private var runningService = RunningService.shared
    @StateObject private var featuresService = RunningFeaturesService.shared
    @EnvironmentObject var healthKitService: HealthKitService
    
    @State private var selectedTab: RunningTab = .overview
    @State private var showingSettings = false
    @State private var showingRunDetail: AdvancedRunData?
    @State private var showingGoalEditor = false
    @State private var showingAddShoe = false
    @State private var showingMatchedRuns: MatchedRunComparison?
    @State private var shoePendingDeletion: RunningShoe?
    
    // Premium color palette
    private let accentColor = Color(hex: "10B981")
    private let secondaryAccent = Color(hex: "3B82F6")
    private let warningColor = Color(hex: "F59E0B")
    private let dangerColor = Color(hex: "EF4444")
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header
                        headerSection
                        
                        // Tab Selector
                        tabSelector
                            .padding(.top, 8)
                        
                        // Content based on selected tab
                        tabContent
                            .padding(.top, 20)
                    }
                    .padding(.bottom, 120)
                }
                
                // Loading overlay
                if advancedService.isLoading {
                    loadingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                RunningSettingsSheet(service: advancedService)
            }
            .sheet(item: $showingRunDetail) { run in
                AdvancedRunDetailView(run: run, service: advancedService, featuresService: featuresService)
            }
            .onAppear {
                advancedService.configure(with: viewContext, healthKitService: healthKitService)
                runningService.configure(with: viewContext)
                featuresService.configure(with: viewContext)
            }
            // Refresh running analytics as soon as HealthKit finishes syncing so users don't need to tab-switch.
            .onReceive(healthKitService.$lastSyncDate.compactMap { $0 }) { _ in
                Task {
                    await advancedService.refreshAllData()
                    await featuresService.refreshShoesAfterSync()
                }
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                .ignoresSafeArea()
            
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    accentColor.opacity(colorScheme == .dark ? 0.08 : 0.04),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 16) {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Running")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                    if let profile = advancedService.fitnessProfile {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                        .font(.system(size: 12))
                                .foregroundColor(Color(hex: profile.fitnessLevel.color))
                            
                            Text(profile.fitnessLevel.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: profile.fitnessLevel.color))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color(hex: profile.fitnessLevel.color).opacity(0.15))
                        )
                    }
                }
                
                Spacer()
                
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Training Status Card
            if let load = advancedService.trainingLoad {
                trainingStatusCard(load)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    private func trainingStatusCard(_ load: TrainingLoadAnalysis) -> some View {
        HStack(spacing: 16) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(Color(hex: load.status.color).opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: statusIcon(for: load.status))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: load.status.color))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(load.status.rawValue)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(hex: load.status.color))
                
                Text("AC Ratio: \(String(format: "%.2f", load.acuteChronicRatio))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
            }
            
            Spacer()
            
            // Weekly load bar
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(load.acuteLoad)) TSS")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text("This Week")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "9CA3AF"))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: load.status.color).opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func statusIcon(for status: TrainingStatus) -> String {
        switch status {
        case .undertraining: return "arrow.down.circle"
        case .optimal: return "checkmark.circle"
        case .overreaching: return "exclamationmark.triangle"
        case .overtraining: return "xmark.circle"
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RunningTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func tabButton(_ tab: RunningTab) -> some View {
            Button {
            withAnimation(.spring(response: 0.3)) {
                selectedTab = tab
            }
            } label: {
                HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(selectedTab == tab ? .white : (colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B")))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
                .background(
                    Capsule()
                    .fill(selectedTab == tab ? accentColor : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.white))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Tab Content
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .progress:
            progressTab
        case .training:
            trainingTabCombined
        case .challenges:
            challengesTabCombined
        case .gear:
            shoesTab
        }
    }
    
    // MARK: - Overview Tab
    private var overviewTab: some View {
        VStack(spacing: 20) {
            // Streak badge (compact)
            compactStreakBadge
            
            // Weekly Progress
            weeklyProgressSection
            
            // Quick Stats Grid
            quickStatsGrid
            
            // Weekly Activity Heatmap
            WeeklyHeatmapCalendar(runDates: advancedService.recentRuns.map { $0.date })
            
            // Route Heatmap Preview
            if let heatmap = featuresService.routeHeatmap, !heatmap.coordinates.isEmpty {
                routeHeatmapPreview(heatmap)
            }
            
            // Recent Runs
            recentRunsSection
        }
        .padding(.horizontal, 20)
    }
    
    private var compactStreakBadge: some View {
        HStack(spacing: 14) {
            // Flame icon with animation
            ZStack {
                Circle()
                    .fill(Color(hex: "F59E0B").opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: featuresService.runningStreak.streakStatus.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color(hex: featuresService.runningStreak.streakStatus.color))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(featuresService.runningStreak.currentStreak)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text("day streak")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                if featuresService.runningStreak.isStreakAtRisk {
                    Text("Run today to keep it going!")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(warningColor)
                } else if featuresService.runningStreak.currentStreak > 0 {
                    Text("Personal best: \(featuresService.runningStreak.longestStreak) days")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
            
            Spacer()
            
            // View all button
            Button {
                withAnimation { selectedTab = .challenges }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "D1D5DB"))
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func routeHeatmapPreview(_ heatmap: RouteHeatmapData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(secondaryAccent)
                
                Text("Your Running Map")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text("\(heatmap.totalRuns) runs")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(secondaryAccent)
            }
            
            RouteHeatmapView(heatmapData: heatmap)
                .frame(height: 200)
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private var weeklyProgressSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("This Week")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                if let analytics = advancedService.weeklyAnalytics {
                    let progress = min(analytics.weeklyGoalProgress, 1.0)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accentColor)
                }
            }
            
            if let analytics = advancedService.weeklyAnalytics {
                HStack(spacing: 20) {
                // Progress Ring
                ZStack {
                    Circle()
                            .stroke(accentColor.opacity(0.15), lineWidth: 10)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                            .trim(from: 0, to: min(analytics.weeklyGoalProgress, 1.0))
                        .stroke(
                                AngularGradient(
                                    colors: [accentColor, accentColor.opacity(0.6), accentColor],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 2) {
                            Text(String(format: "%.1f", analytics.totalDistance))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        Text("km")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "9CA3AF"))
                    }
                }
                
                    // Stats column
                VStack(alignment: .leading, spacing: 12) {
                        weeklyStatRow(icon: "figure.run", label: "Runs", value: "\(analytics.totalRuns)")
                        weeklyStatRow(icon: "clock.fill", label: "Time", value: analytics.formattedDuration)
                        weeklyStatRow(icon: "speedometer", label: "Avg Pace", value: "\(analytics.formattedPace) /km")
                        weeklyStatRow(icon: "heart.fill", label: "Avg HR", value: "\(analytics.averageHeartRate) bpm")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Daily bar chart
                dailyDistanceChart(analytics.dailyDistances)
            } else {
                emptyWeekState
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func weeklyStatRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accentColor)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
    }
    
    private func dailyDistanceChart(_ distances: [Double]) -> some View {
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        let maxDistance = distances.max() ?? 1
        
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            index < distances.count && distances[index] > 0
                                ? accentColor
                                : (colorScheme == .dark ? Color.white.opacity(0.1) : Color(hex: "E5E7EB"))
                        )
                        .frame(
                            width: 28,
                            height: max(4, CGFloat(index < distances.count ? distances[index] / maxDistance : 0) * 50)
                        )
                    
                    Text(days[index])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }
    
    private var emptyWeekState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
            
            Text("No runs this week")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .padding(.vertical, 24)
    }
    
    private var quickStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let analytics = advancedService.weeklyAnalytics {
            quickStatCard(
                title: "Longest Run",
                    value: String(format: "%.1f", analytics.longestRun),
                unit: "km",
                icon: "arrow.up.right",
                color: secondaryAccent
            )
            
            quickStatCard(
                title: "Best Pace",
                    value: formatPace(analytics.fastestPace),
                unit: "/km",
                icon: "bolt.fill",
                    color: warningColor
                )
                
                quickStatCard(
                    title: "Elevation",
                    value: String(format: "%.0f", analytics.totalElevation),
                    unit: "m",
                    icon: "mountain.2.fill",
                    color: Color(hex: "8B5CF6")
                )
                
                quickStatCard(
                    title: "Calories",
                    value: String(format: "%.0f", analytics.totalCalories),
                    unit: "kcal",
                    icon: "flame.fill",
                    color: dangerColor
                )
            }
        }
    }
    
    private func quickStatCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }
    
    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Runs")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                if advancedService.recentRuns.count > 5 {
                    Text("See All")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(accentColor)
                }
            }
            
            if advancedService.recentRuns.isEmpty {
                emptyRunsState
            } else {
                VStack(spacing: 10) {
                    ForEach(advancedService.recentRuns.prefix(5)) { run in
                        runRowCard(run)
                    }
                }
            }
        }
    }
    
    private func runRowCard(_ run: AdvancedRunData) -> some View {
        Button {
            showingRunDetail = run
        } label: {
            HStack(spacing: 14) {
                // Effort indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: run.effortLevel.color).opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: run.effortLevel.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: run.effortLevel.color))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(run.formattedDistance)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        Text(run.effortLevel.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: run.effortLevel.color))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
        .background(
                                Capsule()
                                    .fill(Color(hex: run.effortLevel.color).opacity(0.15))
                            )
                    }
                    
                    HStack(spacing: 8) {
                        Text(run.formattedDuration)
                        Text("•")
                        Text("\(run.formattedPace) /km")
                        if run.avgHeartRate > 0 {
                            Text("•")
                            Text("\(run.avgHeartRate) bpm")
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatRelativeDate(run.date))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    
                    if run.trainingStress > 0 {
                        Text("\(Int(run.trainingStress)) TSS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(warningColor)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "D1D5DB"))
            }
            .padding(14)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }
    
    private var emptyRunsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
            
            VStack(spacing: 4) {
                Text("No runs yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                
                Text("Your runs from Apple Watch will appear here")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(cardBackground)
    }
    
    // MARK: - Challenges & Streaks Tab (Nike Run Club Style)
    private var challengesTab: some View {
        VStack(spacing: 20) {
            // Streak Card
            streakCard
            
            // Active Challenges
            activeChallengesSection
            
            // Weather for Running
            if let weather = featuresService.currentWeather {
                weatherCard(weather)
            }
            
            // Completed Challenges
            if !featuresService.completedChallenges.isEmpty {
                completedChallengesSection
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var streakCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Running Streak")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                    
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(featuresService.runningStreak.currentStreak)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: featuresService.runningStreak.streakStatus.color))
                        
                        Text("days")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "9CA3AF"))
                    }
                }
                
                Spacer()
                
                // Flame animation
                ZStack {
                    Circle()
                        .fill(Color(hex: "F59E0B").opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: featuresService.runningStreak.streakStatus.icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(Color(hex: featuresService.runningStreak.streakStatus.color))
                }
            }
            
            // Streak stats row
            HStack(spacing: 0) {
                streakStatItem(label: "Longest", value: "\(featuresService.runningStreak.longestStreak)", icon: "crown.fill")
                Divider().frame(height: 30)
                streakStatItem(label: "Weekly", value: "\(featuresService.runningStreak.weeklyStreak)w", icon: "calendar")
                Divider().frame(height: 30)
                streakStatItem(label: "Status", value: featuresService.runningStreak.streakStatus == .active ? "Active" : "At Risk", icon: featuresService.runningStreak.isStreakAtRisk ? "exclamationmark.triangle" : "checkmark.circle")
            }
            
            // Streak freeze button (if at risk)
            if featuresService.runningStreak.isStreakAtRisk && featuresService.runningStreak.streakFreezeAvailable {
                Button {
                    featuresService.useStreakFreeze()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "snowflake")
                        Text("Use Streak Freeze")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(secondaryAccent)
                    )
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func streakStatItem(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(warningColor)
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundColor(accentColor)
                Text("Active Challenges")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text("\(featuresService.activeChallenges.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accentColor))
            }
            
            if featuresService.activeChallenges.isEmpty {
                emptyChallengesState
            } else {
                ForEach(featuresService.activeChallenges) { challenge in
                    challengeCard(challenge)
                }
            }
        }
    }
    
    private func challengeCard(_ challenge: RunningChallenge) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                // Challenge icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: challenge.color).opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: challenge.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: challenge.color))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text(challenge.description)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(challenge.daysRemaining)d")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(challenge.daysRemaining <= 2 ? dangerColor : secondaryAccent)
                    
                    Text("left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
            
            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: challenge.color).opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: challenge.color), Color(hex: challenge.color).opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(challenge.progressPercentage / 100, 1), height: 8)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    Text(String(format: "%.1f / %.0f %@", challenge.progress, challenge.target, challenge.type == .distance ? "km" : (challenge.type == .duration ? "min" : "")))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text("\(challenge.participants.formatted())")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: challenge.color).opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var emptyChallengesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.badge.ellipsis")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
            
            Text("Join a challenge to start competing!")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    private var completedChallengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completed")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(featuresService.completedChallenges.prefix(5)) { challenge in
                        completedChallengeChip(challenge)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func completedChallengeChip(_ challenge: RunningChallenge) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(accentColor)
            Text(challenge.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(accentColor.opacity(0.12))
        )
    }
    
    private func weatherCard(_ weather: WeatherCondition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: weather.condition.icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: weather.condition.color))
                
                Text("Running Conditions")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text(weather.runningCondition.level)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: weather.runningCondition.color))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(hex: weather.runningCondition.color).opacity(0.15))
                    )
            }
            
            HStack(spacing: 0) {
                weatherStatItem(icon: "thermometer", label: "Temp", value: String(format: "%.0f°", weather.temperature))
                Divider().frame(height: 30)
                weatherStatItem(icon: "humidity.fill", label: "Humidity", value: "\(Int(weather.humidity))%")
                Divider().frame(height: 30)
                weatherStatItem(icon: "wind", label: "Wind", value: String(format: "%.0f km/h", weather.windSpeed))
                Divider().frame(height: 30)
                weatherStatItem(icon: "sun.max.fill", label: "UV", value: "\(weather.uvIndex)")
            }
            
            if let air = weather.airQuality {
                HStack(spacing: 8) {
                    Image(systemName: "aqi.medium")
                        .foregroundColor(Color(hex: air.level.color))
                    Text("Air Quality: \(air.level.rawValue)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func weatherStatItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(secondaryAccent)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Progress Tab (Combined: Trends + Records + Analytics)
    private var progressTab: some View {
        VStack(spacing: 20) {
            // Race Predictions (from Analytics)
            if let predictions = advancedService.racePredictor {
                racePredictionsCard(predictions)
            }
            
            // Personal Records (from Records)
            personalRecordsSection
            
            // Trends content
            trendsSection
            
            // Monthly Summary (from Analytics)
            if let monthly = advancedService.monthlyAnalytics {
                monthlySummaryCard(monthly)
            }
            
            // Training Load Details (from Analytics)
            if let load = advancedService.trainingLoad {
                trainingLoadDetailsCard(load)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(warningColor)
                Text("Personal Records")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            if !advancedService.personalBests.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(advancedService.personalBests.prefix(4)) { pr in
                        personalBestCard(pr)
                    }
                }
            } else {
                Text("Complete more runs to see your personal records")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func personalBestCard(_ pr: PersonalBest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(warningColor)
                
                Text(pr.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.formattedTime)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                // Show actual distance if it differs from target
                if let actualDist = pr.actualDistance, abs(actualDist - pr.distance) > 0.1 {
                    Text("from \(String(format: "%.2f", actualDist)) km run")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                }
            }
            
            Text(pr.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color(hex: "F9FAFB"))
        )
    }
    
    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(accentColor)
                Text("This Week")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            if let analytics = advancedService.weeklyAnalytics {
                VStack(spacing: 12) {
                    statRow(label: "Total Distance", value: String(format: "%.1f km", analytics.totalDistance))
                    statRow(label: "Avg Pace", value: analytics.formattedPace)
                    statRow(label: "Total Duration", value: analytics.formattedDuration)
                    statRow(label: "Total Runs", value: "\(analytics.totalRuns)")
                    if analytics.averageHeartRate > 0 {
                        statRow(label: "Avg Heart Rate", value: "\(analytics.averageHeartRate) bpm")
                    }
                }
            } else {
                Text("No data for this week yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
    }
    
    // MARK: - Training Tab (Combined: Training + Recovery + Form)
    private var trainingTabCombined: some View {
        VStack(spacing: 20) {
            // Readiness Score
            readinessScoreCard
            
            // Recovery Status (from Recovery)
            if let advice = featuresService.recoveryAdvice {
                recoveryStatusCard(advice)
                
                // Suggested Workout
                if let workout = advice.suggestedWorkout {
                    suggestedWorkoutCard(workout)
                }
            }
            
            // Running Form Summary (from Form)
            runningFormSummaryCard
            
            // Heart Rate Zones
            heartRateZonesCompact
        }
        .padding(.horizontal, 20)
    }
    
    private var runningFormSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(secondaryAccent)
                Text("Running Form")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            if let form = advancedService.runningFormScore {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    formMetricTile(label: "Cadence", value: String(format: "%.0f", form.cadence), unit: "spm", rating: form.cadenceRating)
                    formMetricTile(label: "Stride", value: String(format: "%.2f", form.strideLength), unit: "m", rating: form.strideLengthRating)
                    formMetricTile(label: "Ground Time", value: String(format: "%.0f", form.groundContactTime), unit: "ms", rating: form.groundContactRating)
                    formMetricTile(label: "Vertical Osc", value: String(format: "%.1f", form.verticalOscillation), unit: "cm", rating: form.verticalOscillationRating)
                }
            } else {
                Text("Record more runs with Apple Watch to see form analysis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func formMetricTile(label: String, value: String, unit: String, rating: MetricRating) -> some View {
        let score = ratingToScore(rating)
        return VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            // Score indicator
            HStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color(hex: "E5E7EB"))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: rating.color))
                            .frame(width: geometry.size.width * score)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color(hex: "F9FAFB"))
        )
    }
    
    private func ratingToScore(_ rating: MetricRating) -> Double {
        switch rating {
        case .excellent: return 1.0
        case .good: return 0.75
        case .average: return 0.5
        case .needsWork: return 0.25
        }
    }
    
    private var heartRateZonesCompact: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(dangerColor)
                Text("Heart Rate Zones")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            let zones = HeartRateZone.defaultZones
            VStack(spacing: 8) {
                ForEach(zones, id: \.name) { zone in
                    HStack {
                        Circle()
                            .fill(Color(hex: zone.color))
                            .frame(width: 8, height: 8)
                        Text(zone.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                        Spacer()
                        Text("\(zone.minHR)-\(zone.maxHR) bpm")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    // MARK: - Challenges Tab (Combined: Challenges + Achievements)
    private var challengesTabCombined: some View {
        VStack(spacing: 20) {
            // Streak Card (from Challenges)
            streakCard
            
            // Achievement Points Summary (from Achievements)
            achievementPointsCard
            
            // Active Challenges (from Challenges)
            activeChallengesSection
            
            // Recent Achievements (from Achievements)
            if !featuresService.recentAchievements.isEmpty {
                recentAchievementsSection
            }
            
            // Weather for Running (from Challenges)
            if let weather = featuresService.currentWeather {
                weatherCard(weather)
            }
            
            // All Badges (from Achievements)
            allBadgesSection
            
            // Completed Challenges (from Challenges)
            if !featuresService.completedChallenges.isEmpty {
                completedChallengesSection
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var allBadgesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(warningColor)
                Text("All Badges")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                let unlockedCount = featuresService.achievements.filter { $0.isUnlocked }.count
                Text("\(unlockedCount)/\(featuresService.achievements.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(featuresService.achievements.sorted { $0.isUnlocked && !$1.isUnlocked }) { achievement in
                    achievementBadgeCompact(achievement)
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func achievementBadgeCompact(_ achievement: RunningAchievement) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? Color(hex: achievement.tier.color).opacity(0.2) : (colorScheme == .dark ? Color.white.opacity(0.05) : Color(hex: "F3F4F6")))
                    .frame(width: 44, height: 44)
                
                Image(systemName: achievement.icon)
                    .font(.system(size: 18))
                    .foregroundColor(achievement.isUnlocked ? Color(hex: achievement.tier.color) : (colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB")))
                
                if !achievement.isUnlocked {
                    Circle()
                        .trim(from: 0, to: achievement.progress)
                        .stroke(secondaryAccent.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                }
            }
            
            Text(achievement.name)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(achievement.isUnlocked ? (colorScheme == .dark ? .white : Color(hex: "1A1A1A")) : (colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF")))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Shoes Tab
    private var shoesTab: some View {
        VStack(spacing: 20) {
            // Add shoe button
            addShoeButton
            
            // Shoe list
            if featuresService.shoes.isEmpty {
                emptyShoesState
            } else {
                ForEach(featuresService.shoes) { shoe in
                    shoeCard(shoe)
                        .contextMenu {
                            Button {
                                featuresService.setDefaultShoe(shoe)
                            } label: {
                                Label("Set as Default", systemImage: "checkmark.seal.fill")
                            }
                            
                            if shoe.isRetired {
                                Button {
                                    featuresService.unretireShoe(shoe)
                                } label: {
                                    Label("Unretire", systemImage: "arrow.uturn.left")
                                }
                            } else {
                                Button {
                                    featuresService.retireShoe(shoe)
                                } label: {
                                    Label("Retire", systemImage: "archivebox.fill")
                                }
                            }
                            
                            Button(role: .destructive) {
                                shoePendingDeletion = shoe
                            } label: {
                                Label("Delete Shoe", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showingAddShoe) {
            AddShoeSheet(service: featuresService)
        }
        .alert("Delete Shoe?", isPresented: Binding(
            get: { shoePendingDeletion != nil },
            set: { if !$0 { shoePendingDeletion = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let shoe = shoePendingDeletion {
                    featuresService.deleteShoe(shoe)
                }
                shoePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { shoePendingDeletion = nil }
        } message: {
            Text("This will remove the shoe and unassign it from any runs.")
        }
    }
    
    private var addShoeButton: some View {
        Button {
            showingAddShoe = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Add Running Shoe")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor)
            )
        }
    }
    
    private func shoeCard(_ shoe: RunningShoe) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                // Shoe icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: shoe.color).opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "shoe.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color(hex: shoe.color))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(shoe.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        if shoe.isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(accentColor))
                        }
                    }
                    
                    Text("\(shoe.brand) \(shoe.model)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
                
                // Wear status
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: shoe.wearStatus.icon)
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: shoe.wearStatus.color))
                    
                    Text(shoe.wearStatus.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: shoe.wearStatus.color))
                }
            }
            
            // Mileage progress
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color(hex: "E5E7EB"))
                            .frame(height: 12)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: shoe.wearStatus.color),
                                        Color(hex: shoe.wearStatus.color).opacity(0.7)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(shoe.wearPercentage / 100, 1), height: 12)
                    }
                }
                .frame(height: 12)
                
                HStack {
                    Text(String(format: "%.1f km logged", shoe.totalMileage))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Spacer()
                    
                    Text(String(format: "%.0f km remaining", shoe.remainingMileage))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: shoe.wearStatus.color))
                }
            }
            
            // Shoe stats
            HStack(spacing: 0) {
                shoeStatItem(label: "Runs", value: "\(shoe.runs.count)", icon: "figure.run")
                Divider().frame(height: 24)
                shoeStatItem(label: "Age", value: shoeAge(shoe.purchaseDate), icon: "calendar")
                Divider().frame(height: 24)
                shoeStatItem(label: "Target", value: "\(Int(shoe.targetMileage)) km", icon: "flag.fill")
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func shoeStatItem(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(secondaryAccent)
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func shoeAge(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 30 { return "\(days)d" }
        if days < 365 { return "\(days / 30)mo" }
        return "\(days / 365)yr"
    }
    
    private var emptyShoesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shoe.2")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
            
            VStack(spacing: 4) {
                Text("No shoes tracked")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                
                Text("Add your running shoes to track mileage")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(cardBackground)
    }
    
    // MARK: - Recovery Tab
    private var recoveryTab: some View {
        VStack(spacing: 20) {
            // Readiness Score
            readinessScoreCard
            
            // Recovery Status
            if let advice = featuresService.recoveryAdvice {
                recoveryStatusCard(advice)
                
                // Suggested Workout
                if let workout = advice.suggestedWorkout {
                    suggestedWorkoutCard(workout)
                }
                
                // Recovery Tips
                recoveryTipsCard(advice.recoveryTips)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var readinessScoreCard: some View {
        VStack(spacing: 20) {
            Text("Recovery Readiness")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            ZStack {
                // Background circle
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "EF4444").opacity(0.3),
                                Color(hex: "F59E0B").opacity(0.3),
                                Color(hex: "10B981").opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 16
                    )
                    .frame(width: 160, height: 160)
                
                // Progress arc
                Circle()
                    .trim(from: 0, to: featuresService.readinessScore / 100)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(hex: featuresService.recoveryAdvice?.status.color ?? "10B981"),
                                Color(hex: featuresService.recoveryAdvice?.status.color ?? "10B981").opacity(0.6)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(Int(featuresService.readinessScore))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text(featuresService.recoveryAdvice?.status.rawValue ?? "Calculating...")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: featuresService.recoveryAdvice?.status.color ?? "6B7280"))
                }
            }
            
            // Quick metrics
            if let advice = featuresService.recoveryAdvice {
                HStack(spacing: 20) {
                    if let hrv = advice.hrv {
                        recoveryMetricItem(icon: "waveform.path.ecg", label: "HRV", value: String(format: "%.0f ms", hrv))
                    }
                    if let rhr = advice.restingHR {
                        recoveryMetricItem(icon: "heart.fill", label: "RHR", value: "\(rhr) bpm")
                    }
                    recoveryMetricItem(icon: "battery.50", label: "Fatigue", value: advice.fatigueLevel.rawValue)
                }
            }
        }
        .padding(24)
        .background(cardBackground)
    }
    
    private func recoveryMetricItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(secondaryAccent)
            
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func recoveryStatusCard(_ advice: RecoveryAdvice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: advice.status.icon)
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: advice.status.color))
                
                Text("Recommendation")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            Text(advice.recommendation)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : Color(hex: "4B5563"))
                .lineSpacing(4)
            
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                
                Text("Full recovery: \(advice.estimatedFullRecovery.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func suggestedWorkoutCard(_ workout: RecoveryAdvice.SuggestedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(accentColor)
                Text("Suggested Today")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.type)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(accentColor)
                    
                    Text("\(workout.duration) min • \(workout.intensity)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(accentColor)
            }
            
            Text(workout.description)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func recoveryTipsCard(_ tips: [RecoveryAdvice.RecoveryTip]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recovery Tips")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            ForEach(tips.sorted(by: { $0.priority.rawValue < $1.priority.rawValue })) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.icon)
                        .font(.system(size: 14))
                        .foregroundColor(tip.priority == .high ? warningColor : secondaryAccent)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        Text(tip.description)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    // MARK: - Trends Tab
    private var trendsTab: some View {
        VStack(spacing: 20) {
            // Timeframe picker
            trendTimeframePicker
            
            // Trend cards
            ForEach(featuresService.runTrends) { trend in
                trendCard(trend)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var trendTimeframePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RunTrend.TrendTimeframe.allCases, id: \.self) { timeframe in
                    Button {
                        withAnimation {
                            featuresService.selectedTrendTimeframe = timeframe
                        }
                    } label: {
                        Text(timeframe.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(featuresService.selectedTrendTimeframe == timeframe ? .white : (colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B")))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(featuresService.selectedTrendTimeframe == timeframe ? secondaryAccent : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.white))
                            )
                    }
                }
            }
        }
    }
    
    private func trendCard(_ trend: RunTrend) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: trend.metric.icon)
                    .font(.system(size: 14))
                    .foregroundColor(secondaryAccent)
                
                Text(trend.metric.rawValue)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: trend.trend.icon)
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.1f%%", abs(trend.percentageChange)))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: trend.trend.color))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(hex: trend.trend.color).opacity(0.15))
                )
            }
            
            // Mini sparkline chart
            if !trend.dataPoints.isEmpty {
                trendSparkline(trend)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    Text(formatTrendValue(trend.currentValue, metric: trend.metric))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text("Average")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    Text(formatTrendValue(trend.averageValue, metric: trend.metric))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Previous")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    Text(formatTrendValue(trend.previousValue, metric: trend.metric))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "9CA3AF"))
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }
    
    private func trendSparkline(_ trend: RunTrend) -> some View {
        GeometryReader { geometry in
            let data = trend.dataPoints.map { $0.value }
            let maxValue = data.max() ?? 1
            let minValue = data.min() ?? 0
            let range = maxValue - minValue > 0 ? maxValue - minValue : 1
            
            Path { path in
                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) / CGFloat(max(data.count - 1, 1)) * geometry.size.width
                    let y = (1 - CGFloat((value - minValue) / range)) * geometry.size.height
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                LinearGradient(
                    colors: [secondaryAccent, secondaryAccent.opacity(0.5)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 50)
    }
    
    private func formatTrendValue(_ value: Double, metric: RunTrend.TrendMetric) -> String {
        switch metric {
        case .distance:
            return String(format: "%.1f km", value)
        case .pace:
            let minutes = Int(value) / 60
            let seconds = Int(value) % 60
            return String(format: "%d:%02d /km", minutes, seconds)
        case .duration:
            return String(format: "%.0f min", value)
        case .heartRate:
            return String(format: "%.0f bpm", value)
        case .cadence:
            return String(format: "%.0f spm", value)
        case .elevation:
            return String(format: "%.0f m", value)
        case .trainingLoad:
            return String(format: "%.0f", value)
        case .vo2Max:
            return String(format: "%.1f", value)
        }
    }
    
    // MARK: - Achievements Tab
    private var achievementsTab: some View {
        VStack(spacing: 20) {
            // Points summary
            achievementPointsCard
            
            // Recent achievements
            if !featuresService.recentAchievements.isEmpty {
                recentAchievementsSection
            }
            
            // Achievement categories
            ForEach(RunningAchievement.AchievementCategory.allCases, id: \.self) { category in
                achievementCategorySection(category)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var achievementPointsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Total Points")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                
                Text("\(featuresService.totalPoints.formatted())")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(warningColor)
            }
            
            Spacer()
            
            // Badge count
            VStack(alignment: .trailing, spacing: 6) {
                let unlockedCount = featuresService.achievements.filter { $0.isUnlocked }.count
                
                Text("\(unlockedCount)/\(featuresService.achievements.count)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text("Badges Earned")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            warningColor.opacity(colorScheme == .dark ? 0.15 : 0.1),
                            colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(warningColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var recentAchievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(warningColor)
                Text("Recently Earned")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(featuresService.recentAchievements) { achievement in
                        recentAchievementCard(achievement)
                    }
                }
            }
        }
    }
    
    private func recentAchievementCard(_ achievement: RunningAchievement) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: achievement.tier.color).opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: achievement.icon)
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: achievement.tier.color))
            }
            
            Text(achievement.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                .lineLimit(1)
            
            Text("+\(achievement.points)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(warningColor)
        }
        .frame(width: 90)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func achievementCategorySection(_ category: RunningAchievement.AchievementCategory) -> some View {
        let categoryAchievements = featuresService.achievements.filter { $0.category == category }
        guard !categoryAchievements.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(secondaryAccent)
                    Text(category.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Spacer()
                    
                    let earned = categoryAchievements.filter { $0.isUnlocked }.count
                    Text("\(earned)/\(categoryAchievements.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(categoryAchievements) { achievement in
                        achievementBadge(achievement)
                    }
                }
            }
            .padding(18)
            .background(cardBackground)
        )
    }
    
    private func achievementBadge(_ achievement: RunningAchievement) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? Color(hex: achievement.tier.color).opacity(0.2) : (colorScheme == .dark ? Color.white.opacity(0.05) : Color(hex: "F3F4F6")))
                    .frame(width: 50, height: 50)
                
                Image(systemName: achievement.icon)
                    .font(.system(size: 20))
                    .foregroundColor(achievement.isUnlocked ? Color(hex: achievement.tier.color) : (colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB")))
                
                if !achievement.isUnlocked {
                    // Progress ring
                    Circle()
                        .trim(from: 0, to: achievement.progress)
                        .stroke(secondaryAccent.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))
                }
            }
            
            Text(achievement.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(achievement.isUnlocked ? (colorScheme == .dark ? .white : Color(hex: "1A1A1A")) : (colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF")))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Analytics Tab
    private var analyticsTab: some View {
        VStack(spacing: 20) {
            // Race Predictions
            if let predictions = advancedService.racePredictor {
                racePredictionsCard(predictions)
            }
            
            // Monthly Summary
            if let monthly = advancedService.monthlyAnalytics {
                monthlySummaryCard(monthly)
            }
            
            // Training Load Details
            if let load = advancedService.trainingLoad {
                trainingLoadDetailsCard(load)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func racePredictionsCard(_ predictions: RacePredictions) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(warningColor)
                
                Text("Race Predictions")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text("\(Int(predictions.confidence))% confidence")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                racePredictionItem(distance: "5K", time: predictions.formattedTime(predictions.fiveK))
                racePredictionItem(distance: "10K", time: predictions.formattedTime(predictions.tenK))
                racePredictionItem(distance: "Half", time: predictions.formattedTime(predictions.halfMarathon))
                racePredictionItem(distance: "Marathon", time: predictions.formattedTime(predictions.marathon))
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func racePredictionItem(distance: String, time: String) -> some View {
        VStack(spacing: 6) {
            Text(distance)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            
            Text(time)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color(hex: "F3F4F6"))
        )
    }
    
    private func monthlySummaryCard(_ monthly: MonthlyRunningAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This Month")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: monthly.distanceTrend >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    
                    Text("\(String(format: "%.0f", abs(monthly.distanceTrend)))%")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(monthly.distanceTrend >= 0 ? accentColor : dangerColor)
            }
            
            HStack(spacing: 20) {
                monthlyStatItem(label: "Distance", value: String(format: "%.1f km", monthly.totalDistance))
                monthlyStatItem(label: "Runs", value: "\(monthly.totalRuns)")
                monthlyStatItem(label: "Time", value: monthly.formattedDuration)
            }
            
            // Weekly breakdown chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Weekly Breakdown")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                
                weeklyBreakdownBars(monthly.weeklyTotals)
            }
            
            // Consistency score
            HStack {
                Text("Consistency Score")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text("\(Int(monthly.consistencyScore))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accentColor)
                    
                    Image(systemName: consistencyIcon(monthly.consistencyScore))
                        .font(.system(size: 12))
                        .foregroundColor(accentColor)
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func monthlyStatItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func weeklyBreakdownBars(_ weeklyTotals: [Double]) -> some View {
        let maxWeekly = weeklyTotals.max() ?? 1
        
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<min(5, weeklyTotals.count), id: \.self) { index in
                VStack(spacing: 4) {
                    Text(String(format: "%.0f", weeklyTotals[index]))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentColor.opacity(weeklyTotals[index] > 0 ? 1 : 0.2))
                        .frame(height: max(4, CGFloat(weeklyTotals[index] / maxWeekly) * 40))
                    
                    Text("W\(index + 1)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func consistencyIcon(_ score: Double) -> String {
        switch score {
        case 80...100: return "checkmark.seal.fill"
        case 60..<80: return "star.fill"
        case 40..<60: return "hand.thumbsup.fill"
        default: return "arrow.up.circle"
        }
    }
    
    private func trainingLoadDetailsCard(_ load: TrainingLoadAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Load Analysis")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            // Load metrics
            HStack(spacing: 16) {
                loadMetricItem(label: "Acute (7d)", value: Int(load.acuteLoad), color: dangerColor)
                loadMetricItem(label: "Chronic (28d)", value: Int(load.chronicLoad), color: secondaryAccent)
                loadMetricItem(label: "Balance", value: Int(load.trainingBalance), color: accentColor, showSign: true)
            }
            
            // AC Ratio gauge
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Acute:Chronic Ratio")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                    
                    Spacer()
                    
                    Text(String(format: "%.2f", load.acuteChronicRatio))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: load.status.color))
                }
                
                // Ratio gauge
                acRatioGauge(ratio: load.acuteChronicRatio)
            }
            
            // Recommendation
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(warningColor)
                
                Text(load.recommendation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(warningColor.opacity(0.1))
            )
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func loadMetricItem(label: String, value: Int, color: Color, showSign: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(showSign && value >= 0 ? "+\(value)" : "\(value)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func acRatioGauge(ratio: Double) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let position = min(max(ratio / 2.0, 0), 1) * width
            
            ZStack(alignment: .leading) {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color(hex: "3B82F6"), // Undertraining
                        Color(hex: "10B981"), // Optimal
                        Color(hex: "F59E0B"), // Overreaching
                        Color(hex: "EF4444")  // Overtraining
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 8)
                .cornerRadius(4)
                
                // Optimal zone indicator
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: width * 0.25, height: 12)
                    .offset(x: width * 0.4)
                
                // Current position indicator
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: position - 8)
            }
        }
        .frame(height: 16)
    }
    
    // MARK: - Training Tab
    private var trainingTab: some View {
        VStack(spacing: 20) {
            // Fitness Profile
            if let profile = advancedService.fitnessProfile {
                fitnessProfileCard(profile)
            }
            
            // Training Plan
            trainingPlanSection
        }
        .padding(.horizontal, 20)
    }
    
    private func fitnessProfileCard(_ profile: RunnerFitnessProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Fitness Profile")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text(profile.fitnessLevel.rawValue)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: profile.fitnessLevel.color))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(hex: profile.fitnessLevel.color).opacity(0.15))
                    )
            }
            
            HStack(spacing: 20) {
                profileMetric(label: "VO₂ Max", value: String(format: "%.1f", profile.vo2MaxEstimate), unit: "ml/kg/min")
                profileMetric(label: "Running Age", value: "\(profile.runningAge)", unit: "years")
                profileMetric(label: "Longest Run", value: String(format: "%.1f", profile.longestRunEver), unit: "km")
            }
            
            // Strengths
            if !profile.strengths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Strengths")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    
                    HStack(spacing: 8) {
                        ForEach(profile.strengths, id: \.self) { strength in
                            Text(strength.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(accentColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(accentColor.opacity(0.12))
                                )
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func profileMetric(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var trainingPlanSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This Week's Plan")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Button {
                    showingGoalEditor = true
                } label: {
                    Text("Customize")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(accentColor)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(runningService.weeklyPlan) { plannedRun in
                        trainingDayCard(plannedRun)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func trainingDayCard(_ run: PlannedRun) -> some View {
        let runTypeColor = Color(hex: run.type.color)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(run.day.prefix(3)))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                
                Spacer()
                
                if run.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(accentColor)
                        .font(.system(size: 14))
                }
            }
            
            Text(run.type.rawValue)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(runTypeColor)
            
            Text(run.description)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                .lineLimit(2)
            
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text("\(run.duration) min")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .padding(14)
        .frame(width: 120)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(runTypeColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Records Tab
    private var recordsTab: some View {
        VStack(spacing: 20) {
            // Personal Bests
            personalBestsSection
        }
        .padding(.horizontal, 20)
    }
    
    private var personalBestsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(warningColor)
                
                Text("Personal Bests")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            if advancedService.personalBests.isEmpty {
                emptyPRsState
            } else {
                VStack(spacing: 10) {
                    ForEach(advancedService.personalBests) { pr in
                        prRowCard(pr)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func prRowCard(_ pr: PersonalBest) -> some View {
            HStack(spacing: 14) {
                ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(warningColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16))
                    .foregroundColor(warningColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                Text(pr.displayName)
                    .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                Text(pr.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                Text(pr.formattedTime)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor)
                
                Text("\(pr.formattedPace) /km")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
        .padding(12)
            .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color(hex: "F9FAFB"))
        )
    }
    
    private var emptyPRsState: some View {
                HStack(spacing: 14) {
                    Image(systemName: "trophy")
                        .font(.system(size: 20))
                .foregroundColor(warningColor.opacity(0.5))
                    
                    Text("Complete more runs to earn PRs!")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Running Form Tab
    private var runningFormTab: some View {
        VStack(spacing: 20) {
            // Show latest form metrics from HealthKit
            if let latestMetrics = advancedService.latestFormMetrics, latestMetrics.hasData {
                latestFormMetricsCard(latestMetrics)
            }
            
            // Show form analysis and score
            if let formAnalysis = advancedService.runningFormScore {
                runningFormAnalysisCard(formAnalysis)
            } else if advancedService.latestFormMetrics == nil || !(advancedService.latestFormMetrics?.hasData ?? false) {
                noFormDataCard
            }
        }
        .padding(.horizontal, 20)
        .onAppear {
            // Refresh form data when tab appears
            Task {
                await advancedService.refreshAllData()
            }
        }
    }
    
    private func latestFormMetricsCard(_ metrics: RunningFormMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(secondaryAccent)
                
                Text("Latest Running Metrics")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text("from Apple Health")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let stride = metrics.strideLength {
                    formMetricCard(icon: "ruler", label: "Stride", value: String(format: "%.2f m", stride), color: secondaryAccent)
                }
                if let gct = metrics.groundContactTime {
                    formMetricCard(icon: "timer", label: "Ground Contact", value: String(format: "%.0f ms", gct), color: accentColor)
                }
                if let vo = metrics.verticalOscillation {
                    formMetricCard(icon: "arrow.up.arrow.down", label: "Vert. Osc.", value: String(format: "%.1f cm", vo), color: warningColor)
                }
                if let cadence = metrics.cadence {
                    formMetricCard(icon: "metronome", label: "Cadence", value: String(format: "%.0f spm", cadence), color: Color(hex: "8B5CF6"))
                }
                if let power = metrics.runningPower {
                    formMetricCard(icon: "bolt.fill", label: "Power", value: String(format: "%.0f W", power), color: dangerColor)
                }
                if let speed = metrics.runningSpeed {
                    let paceSecondsPerKm = speed > 0 ? 1000.0 / speed : 0
                    let minutes = Int(paceSecondsPerKm) / 60
                    let seconds = Int(paceSecondsPerKm) % 60
                    formMetricCard(icon: "speedometer", label: "Pace", value: String(format: "%d:%02d /km", minutes, seconds), color: accentColor)
                }
                
                if let stepLen = metrics.stepLength {
                    formMetricCard(icon: "shoeprints.fill", label: "Step Length", value: String(format: "%.2f m", stepLen), color: secondaryAccent)
                }
                
                if let vRatio = metrics.verticalRatio {
                    formMetricCard(icon: "chart.bar.fill", label: "Vertical Ratio", value: String(format: "%.1f%%", vRatio), color: warningColor)
                }
                
                if let asym = metrics.asymmetryPercentage {
                    formMetricCard(icon: "arrow.left.and.right", label: "Asymmetry", value: String(format: "%.1f%%", asym), color: dangerColor)
                }
                
                if let gctBal = metrics.groundContactTimeBalance {
                    formMetricCard(icon: "figure.walk", label: "GCT Balance", value: String(format: "%.1f%%", gctBal), color: accentColor)
                }
                
                if let ds = metrics.doubleSupportPercentage {
                    formMetricCard(icon: "figure.walk.motion", label: "Double Support", value: String(format: "%.1f%%", ds), color: Color(hex: "8B5CF6"))
                }
                
                if let recovery = metrics.cardioRecovery1Min {
                    formMetricCard(icon: "heart.slash.fill", label: "Recovery (1m)", value: String(format: "%.0f bpm", recovery), color: dangerColor)
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func formMetricCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color(hex: "F9FAFB"))
        )
    }
    
    private func runningFormAnalysisCard(_ analysis: RunningFormAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Overall Score
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Running Form Score")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text("Based on Apple Watch data")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(0.15), lineWidth: 6)
                        .frame(width: 70, height: 70)
                    
                    Circle()
                        .trim(from: 0, to: analysis.overallScore / 100)
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(analysis.overallScore))")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                }
            }
            
            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color(hex: "E5E7EB"))
            
            // Metrics
            VStack(spacing: 14) {
                formMetricRow(
                    icon: "ruler",
                    label: "Stride Length",
                    value: String(format: "%.2f m", analysis.strideLength),
                    rating: analysis.strideLengthRating
                )
                
                formMetricRow(
                    icon: "timer",
                    label: "Ground Contact",
                    value: String(format: "%.0f ms", analysis.groundContactTime),
                    rating: analysis.groundContactRating
                )
                
                formMetricRow(
                    icon: "arrow.up.arrow.down",
                    label: "Vertical Oscillation",
                    value: String(format: "%.1f cm", analysis.verticalOscillation),
                    rating: analysis.verticalOscillationRating
                )
                
                formMetricRow(
                    icon: "metronome",
                    label: "Cadence",
                    value: String(format: "%.0f spm", analysis.cadence),
                    rating: analysis.cadenceRating
                )
            }
            
            // Improvement suggestions
            if !analysis.improvements.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Areas for Improvement")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
                    ForEach(analysis.improvements, id: \.self) { improvement in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 12))
                                .foregroundColor(warningColor)
                            
                            Text(improvement)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                        }
                    }
        }
        .padding(14)
        .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(warningColor.opacity(0.08))
                )
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func formMetricRow(icon: String, label: String, value: String, rating: MetricRating) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(secondaryAccent)
                    .frame(width: 24)
                
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(rating.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: rating.color))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(hex: rating.color).opacity(0.15))
                )
        }
    }
    
    private var noFormDataCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
            
            VStack(spacing: 8) {
                Text("No Running Dynamics Data")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "374151"))
                
                Text("Complete outdoor runs with your Apple Watch to collect running form data")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B7280"))
                    .multilineTextAlignment(.center)
            }
            
            // Requirements list
            VStack(alignment: .leading, spacing: 10) {
                requirementRow(icon: "applewatch", text: "Apple Watch Series 4 or later", isMet: true)
                requirementRow(icon: "location.fill", text: "Outdoor running workout", isMet: true)
                requirementRow(icon: "figure.run", text: "Complete at least one run", isMet: false)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color(hex: "F3F4F6"))
            )
            
            // Refresh button
            Button {
                Task {
                    await advancedService.refreshAllData()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Refresh Data")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(accentColor)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(cardBackground)
    }
    
    private func requirementRow(icon: String, text: String, isMet: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isMet ? accentColor : (colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF")))
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
            
            Spacer()
            
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isMet ? accentColor : (colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB")))
        }
    }
    
    // MARK: - Helpers
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04),
                            lineWidth: 1
                        )
                )
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.04),
                radius: 12, x: 0, y: 4
            )
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(accentColor)
                
                Text("Loading analytics...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
    }
    
    private func formatPace(_ pace: Double) -> String {
        guard pace > 0 else { return "--:--" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
}

// MARK: - Tab Enum
enum RunningTab: String, CaseIterable {
    case overview = "Overview"
    case progress = "Progress"
    case training = "Training"
    case challenges = "Challenges"
    case gear = "Gear"
    
    var icon: String {
        switch self {
        case .overview: return "chart.bar.fill"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .training: return "figure.run.motion"
        case .challenges: return "flame.fill"
        case .gear: return "shoe.fill"
        }
    }
}

// MARK: - Settings Sheet
struct RunningSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var service: AdvancedRunningService
    @ObservedObject var userProfile = UserProfileManager.shared
    
    @State private var maxHR: Double
    @State private var restingHR: Double
    @State private var vo2Max: Double
    @State private var weight: Double
    @State private var height: Double
    @State private var weeklyGoal: Double
    
    private let accentColor = Color(hex: "10B981")
    private let secondaryColor = Color(hex: "3B82F6")
    
    init(service: AdvancedRunningService) {
        self.service = service
        _maxHR = State(initialValue: Double(service.maxHeartRate))
        _restingHR = State(initialValue: Double(service.restingHeartRate))
        _vo2Max = State(initialValue: service.vo2Max)
        _weight = State(initialValue: service.weight)
        _height = State(initialValue: service.height)
        _weeklyGoal = State(initialValue: service.weeklyGoalKm)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Summary from HealthKit
                        profileSummarySection
                        
                        // Heart Rate Settings
                        settingsSection(title: "Heart Rate Zones") {
                            sliderSetting(label: "Max Heart Rate", value: $maxHR, range: 150...220, unit: "bpm", info: maxHRInfo)
                            sliderSetting(label: "Resting Heart Rate", value: $restingHR, range: 40...100, unit: "bpm", info: restingHRInfo)
                        }
                        
                        // Body Metrics
                        settingsSection(title: "Body Metrics") {
                            sliderSetting(label: "Weight", value: $weight, range: 40...150, unit: "kg", info: nil)
                            sliderSetting(label: "Height", value: $height, range: 140...220, unit: "cm", info: nil)
                            sliderSetting(label: "VO₂ Max Estimate", value: $vo2Max, range: 20...80, unit: "ml/kg/min", info: vo2MaxInfo)
                        }
                        
                        // Training Goals
                        settingsSection(title: "Training Goals") {
                            sliderSetting(label: "Weekly Distance Goal", value: $weeklyGoal, range: 5...150, unit: "km", info: nil)
                        }
                        
                        // Sync button
                        syncFromHealthKitButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Running Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        service.updateSettings(
                            maxHR: Int(maxHR),
                            restingHR: Int(restingHR),
                            vo2: vo2Max,
                            weight: weight,
                            height: height,
                            weeklyGoal: weeklyGoal
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                }
            }
        }
    }
    
    // MARK: - Profile Summary
    private var profileSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(secondaryColor)
                
                Text("Your Profile")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                if userProfile.isLoaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("Synced from Health")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(accentColor)
                }
            }
            
            HStack(spacing: 16) {
                profileItem(label: "Age", value: userProfile.displayAge, icon: "calendar")
                profileItem(label: "Gender", value: userProfile.genderString, icon: "person")
                profileItem(label: "BMI", value: userProfile.displayBMI, icon: "chart.bar")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func profileItem(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(secondaryColor)
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Info Texts
    private var maxHRInfo: String? {
        if let age = userProfile.age {
            return "Calculated from age: 208 - (0.7 × \(age)) = \(userProfile.maxHeartRate) bpm"
        }
        return "Set your age in Apple Health for automatic calculation"
    }
    
    private var restingHRInfo: String? {
        if userProfile.restingHeartRate != nil {
            return "From Apple Watch measurements"
        }
        return nil
    }
    
    private var vo2MaxInfo: String? {
        if userProfile.vo2Max != nil {
            return "Estimated from your recent runs"
        }
        return nil
    }
    
    // MARK: - Sync Button
    private var syncFromHealthKitButton: some View {
        Button {
            Task {
                await service.resyncFromHealthKit()
                // Update local state
                maxHR = Double(service.maxHeartRate)
                restingHR = Double(service.restingHeartRate)
                vo2Max = service.vo2Max
                weight = service.weight
                height = service.height
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sync from Apple Health")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(secondaryColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(secondaryColor.opacity(0.5), lineWidth: 1)
            )
        }
    }
    
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 20) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            )
        }
    }
    
    private func sliderSetting(label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, info: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                
                Spacer()
                
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accentColor)
            }
            
            Slider(value: value, in: range, step: 1)
                .tint(accentColor)
            
            if let info = info {
                Text(info)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
        }
    }
}

// MARK: - Advanced Run Detail View
struct AdvancedRunDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let run: AdvancedRunData
    let service: AdvancedRunningService
    @ObservedObject var featuresService: RunningFeaturesService
    
    @State private var selectedDetailTab: DetailTab = .summary
    @State private var showingShoePicker = false
    @State private var selectedShoeIds: Set<UUID> = []
    
    private let accentColor = Color(hex: "10B981")
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Hero Section
                        heroSection
                        
                        // Tab Selector
                        detailTabSelector
                        
                        // Tab Content
                        detailTabContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Run Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(accentColor)
                }
            }
        }
        .onAppear {
            selectedShoeIds = Set(featuresService.shoeIds(for: run.id))
        }
        .sheet(isPresented: $showingShoePicker) {
            RunShoePickerSheet(
                runId: run.id,
                shoes: featuresService.shoes.filter { !$0.isRetired },
                selectedShoeIds: $selectedShoeIds
            ) { ids in
                featuresService.setShoes(for: run.id, shoeIds: ids)
            }
        }
    }
    
    private var heroSection: some View {
                        VStack(spacing: 16) {
            // Distance
                            Text(run.formattedDistance)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                            
            // Date & Effort
            HStack(spacing: 12) {
                            Text(run.date.formatted(date: .complete, time: .shortened))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                
                Text(run.effortLevel.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: run.effortLevel.color))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(hex: run.effortLevel.color).opacity(0.15))
                    )
            }
            
            // Key Stats
            HStack(spacing: 0) {
                heroStat(label: "Duration", value: run.formattedDuration)
                Divider()
                    .frame(height: 40)
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color(hex: "E5E7EB"))
                heroStat(label: "Pace", value: "\(run.formattedPace) /km")
                Divider()
                    .frame(height: 40)
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color(hex: "E5E7EB"))
                heroStat(label: "Avg HR", value: "\(run.avgHeartRate) bpm")
            }
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            )
                        }
                        .padding(.top, 20)
    }
    
    private func heroStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var detailTabSelector: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedDetailTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selectedDetailTab == tab ? accentColor : (colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B")))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedDetailTab == tab
                                ? accentColor.opacity(0.1)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    @ViewBuilder
    private var detailTabContent: some View {
        switch selectedDetailTab {
        case .summary:
            summaryContent
        case .heartRate:
            heartRateContent
        case .splits:
            splitsContent
        case .dynamics:
            dynamicsContent
        }
    }
    
    private var summaryContent: some View {
        VStack(spacing: 16) {
            // Route map (if available)
            if !run.routePoints.isEmpty {
                routeMapCard
            }
            
            shoesUsedCard
            
            // Training Effect
            trainingEffectCard
            
            // All Stats Grid
            allStatsGrid
        }
    }
    
    private var shoesUsedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shoe.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
                
                Text("Shoes Used")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Button {
                    showingShoePicker = true
                } label: {
                    Text("Edit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                .disabled(featuresService.shoes.filter { !$0.isRetired }.isEmpty)
            }
            
            let activeShoes = featuresService.shoes.filter { !$0.isRetired }
            let selected = activeShoes.filter { selectedShoeIds.contains($0.id) }
            
            if activeShoes.isEmpty {
                Text("Add shoes in the Shoes tab to track mileage automatically.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            } else if selected.isEmpty {
                Text("No shoes selected — mileage will go to your default shoe.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(selected) { shoe in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: shoe.color))
                                .frame(width: 8, height: 8)
                            Text(shoe.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(hex: shoe.color).opacity(0.15))
                        )
                    }
                }
                
                Text("This run’s \(String(format: "%.2f", run.distance)) km will be added to the selected shoe(s).")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private var routeMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
                
                Text("Route")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
            }
            
            RouteMapView(points: run.routePoints, strokeColor: accentColor)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private var trainingEffectCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Effect")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            HStack(spacing: 20) {
                effectCircle(label: "Aerobic", value: run.aerobicEffect, color: Color(hex: "3B82F6"))
                effectCircle(label: "Anaerobic", value: run.anaerobicEffect, color: Color(hex: "EF4444"))
                
                VStack(alignment: .leading, spacing: 8) {
                    trainingEffectRow(label: "Training Stress", value: String(format: "%.0f TSS", run.trainingStress))
                    trainingEffectRow(label: "Running Economy", value: String(format: "%.1f", run.runningEconomy))
                    trainingEffectRow(label: "Calories", value: "\(Int(run.calories)) kcal")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func effectCircle(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 6)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: value / 5)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                Text(String(format: "%.1f", value))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
    }
    
    private func trainingEffectRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
    }
    
    private var allStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statGridItem(icon: "heart.fill", label: "Max HR", value: "\(run.maxHeartRate) bpm", color: Color(hex: "EF4444"))
            statGridItem(icon: "heart", label: "Min HR", value: "\(run.minHeartRate) bpm", color: Color(hex: "10B981"))
            statGridItem(icon: "mountain.2.fill", label: "Elevation", value: String(format: "%.0f m", run.elevationGain), color: Color(hex: "8B5CF6"))
            statGridItem(icon: "waveform.path.ecg", label: "HRV", value: String(format: "%.1f ms", run.heartRateVariability), color: Color(hex: "F59E0B"))
        }
    }
    
    private func statGridItem(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            
            Text(value)
                    .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private var heartRateContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Heart Rate Zones")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            ForEach(run.heartRateZones) { zone in
                hrZoneRow(zone)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func hrZoneRow(_ zone: HeartRateZone) -> some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(hex: zone.color))
                    .frame(width: 10, height: 10)
                
                Text("Zone \(zone.zone): \(zone.name)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text(zone.formattedDuration)
                .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                
                Text("\(Int(zone.percentage))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: zone.color))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: zone.color).opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: zone.color))
                        .frame(width: geometry.size.width * zone.percentage / 100, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
    
    private var splitsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Kilometer Splits")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            if run.splits.isEmpty {
                Text("No split data available")
                    .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            } else {
                ForEach(run.splits) { split in
                    splitRow(split)
        }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func splitRow(_ split: RunSplit) -> some View {
        HStack {
            Text(split.isPartialSplit ? String(format: "%.2f km", split.partialDistance ?? 0) : "KM \(split.kilometer)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                .frame(width: 60, alignment: .leading)
            
            Text(split.formattedPace)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(accentColor)
            
            Spacer()
            
            HStack(spacing: 12) {
                Label("\(split.heartRate)", systemImage: "heart.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                
                Label("\(split.cadence)", systemImage: "metronome")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
        }
        .padding(.vertical, 8)
    }
    
    private var dynamicsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Running Dynamics")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            if let stride = run.strideLength {
                dynamicsRow(icon: "ruler", label: "Stride Length", value: String(format: "%.2f m", stride))
            }
            
            if let gct = run.groundContactTime {
                dynamicsRow(icon: "timer", label: "Ground Contact Time", value: String(format: "%.0f ms", gct))
            }
            
            if let vo = run.verticalOscillation {
                dynamicsRow(icon: "arrow.up.arrow.down", label: "Vertical Oscillation", value: String(format: "%.1f cm", vo))
            }
            
            if let cadence = run.cadence {
                dynamicsRow(icon: "metronome", label: "Cadence", value: String(format: "%.0f spm", cadence))
            }
            
            if let cadenceHK = run.runningCadenceHK, run.cadence == nil {
                dynamicsRow(icon: "metronome", label: "Cadence", value: String(format: "%.0f spm", cadenceHK))
            }
            
            if let stepLen = run.stepLength {
                dynamicsRow(icon: "shoeprints.fill", label: "Step Length", value: String(format: "%.2f m", stepLen))
            }
            
            if let vRatio = run.verticalRatio {
                dynamicsRow(icon: "chart.bar.fill", label: "Vertical Ratio", value: String(format: "%.1f%%", vRatio))
            }
            
            if let asym = run.asymmetryPercentage {
                dynamicsRow(icon: "arrow.left.and.right", label: "Asymmetry", value: String(format: "%.1f%%", asym))
            }
            
            if let balance = run.groundContactTimeBalance {
                dynamicsRow(icon: "figure.walk", label: "GCT Balance", value: String(format: "%.1f%%", balance))
            }
            
            if let ds = run.doubleSupportPercentage {
                dynamicsRow(icon: "figure.walk.motion", label: "Double Support", value: String(format: "%.1f%%", ds))
            }
            
            if let recovery = run.cardioRecovery1Min {
                dynamicsRow(icon: "heart.slash.fill", label: "Cardio Recovery (1m)", value: String(format: "%.0f bpm", recovery))
            }
            
            if let power = run.runningPower {
                dynamicsRow(icon: "bolt.fill", label: "Running Power", value: String(format: "%.0f W", power))
            }
            
            let hasAnyDynamics = run.strideLength != nil ||
                run.groundContactTime != nil ||
                run.verticalOscillation != nil ||
                run.cadence != nil ||
                run.runningPower != nil ||
                run.runningCadenceHK != nil ||
                run.stepLength != nil ||
                run.verticalRatio != nil ||
                run.asymmetryPercentage != nil ||
                run.groundContactTimeBalance != nil ||
                run.doubleSupportPercentage != nil
            
            if !hasAnyDynamics {
                Text("No running dynamics data available. Apple Watch Series 4+ required.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
            }
        }
        .padding(20)
        .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func dynamicsRow(icon: String, label: String, value: String) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "3B82F6"))
                    .frame(width: 24)
                
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Run Shoe Picker
struct RunShoePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let runId: UUID
    let shoes: [RunningShoe]
    @Binding var selectedShoeIds: Set<UUID>
    let onSave: ([UUID]) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                List {
                    Section {
                        ForEach(shoes) { shoe in
                            Button {
                                toggle(shoe.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(hex: shoe.color))
                                        .frame(width: 10, height: 10)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shoe.name)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("\(shoe.brand) \(shoe.model)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedShoeIds.contains(shoe.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color(hex: "10B981"))
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary.opacity(0.6))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Select shoe(s) for this run")
                    } footer: {
                        Text("If you select multiple shoes, the full run distance will be added to each shoe.")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Shoes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Array(selectedShoeIds))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func toggle(_ id: UUID) {
        if selectedShoeIds.contains(id) {
            selectedShoeIds.remove(id)
        } else {
            selectedShoeIds.insert(id)
        }
    }
}

// MARK: - Simple Flow Layout for Chips
/// A lightweight wrapping layout for small "chip" views.
/// Usage:
/// `FlowLayout(spacing: 8) { ... }`
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? CGFloat.greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                usedWidth = max(usedWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        
        usedWidth = max(usedWidth, x > 0 ? x - spacing : 0)
        let finalWidth = proposal.width ?? usedWidth
        return CGSize(width: finalWidth, height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

enum DetailTab: String, CaseIterable {
    case summary = "Summary"
    case heartRate = "HR Zones"
    case splits = "Splits"
    case dynamics = "Dynamics"
}

// MARK: - Add Shoe Sheet
struct AddShoeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var service: RunningFeaturesService
    
    @State private var name = ""
    @State private var brand = ""
    @State private var model = ""
    @State private var purchaseDate = Date()
    @State private var initialMileage: Double = 0
    @State private var targetMileage: Double = 800
    @State private var selectedColor = "3B82F6"
    @State private var notes = ""
    
    private let colors = ["3B82F6", "10B981", "8B5CF6", "F59E0B", "EF4444", "EC4899", "6366F1", "14B8A6"]
    private let accentColor = Color(hex: "10B981")
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Shoe Preview
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(hex: selectedColor).opacity(0.15))
                                .frame(height: 120)
                            
                            Image(systemName: "shoe.fill")
                                .font(.system(size: 48))
                                .foregroundColor(Color(hex: selectedColor))
                        }
                        
                        // Basic Info
                        VStack(spacing: 16) {
                            formField(label: "Shoe Name", placeholder: "e.g., Daily Trainer", text: $name)
                            formField(label: "Brand", placeholder: "e.g., Nike", text: $brand)
                            formField(label: "Model", placeholder: "e.g., Pegasus 40", text: $model)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                        )
                        
                        // Color Picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Color")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                            
                            HStack(spacing: 12) {
                                ForEach(colors, id: \.self) { color in
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                        )
                                        .shadow(color: selectedColor == color ? Color(hex: color).opacity(0.5) : .clear, radius: 4)
                                        .onTapGesture {
                                            withAnimation { selectedColor = color }
                                        }
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                        )
                        
                        // Mileage Settings
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Initial Mileage (km)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                                
                                HStack {
                                    Slider(value: $initialMileage, in: 0...500, step: 10)
                                        .tint(accentColor)
                                    
                                    Text("\(Int(initialMileage)) km")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(accentColor)
                                        .frame(width: 60)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Target Mileage (km)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                                
                                HStack {
                                    Slider(value: $targetMileage, in: 400...1200, step: 50)
                                        .tint(accentColor)
                                    
                                    Text("\(Int(targetMileage)) km")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(accentColor)
                                        .frame(width: 60)
                                }
                            }
                            
                            DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                        )
                        
                        // Notes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes (optional)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                            
                            TextField("e.g., Great for easy runs", text: $notes)
                                .font(.system(size: 14))
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color(hex: "F3F4F6"))
                                )
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                        )
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Running Shoe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveShoe()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                    .disabled(name.isEmpty || brand.isEmpty)
                }
            }
        }
    }
    
    private func formField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
            
            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color(hex: "F3F4F6"))
                )
        }
    }
    
    private func saveShoe() {
        let shoe = RunningShoe(
            id: UUID(),
            name: name,
            brand: brand,
            model: model,
            purchaseDate: purchaseDate,
            initialMileage: initialMileage,
            totalMileage: initialMileage,
            targetMileage: targetMileage,
            color: selectedColor,
            isDefault: service.shoes.isEmpty,
            isRetired: false,
            notes: notes,
            imageData: nil,
            runs: []
        )
        service.addShoe(shoe)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    RunningView()
        .environment(\.managedObjectContext, context)
        .environmentObject(HealthKitService(context: context))
}
