import SwiftUI
import CoreData
import HealthKit

// MARK: - Modern Settings Page
struct ProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var healthKitService: HealthKitService
    @StateObject private var smartCoach = SmartCoachService.shared
    @StateObject private var advancedRunning = AdvancedRunningService.shared
    @StateObject private var notificationService = NotificationService()
    @ObservedObject private var userProfile = UserProfileManager.shared
    
    // Profile (fallback to local storage if HealthKit not available)
    @AppStorage("userName") private var userName = ""
    
    // Goals & Targets - sync with UserProfileManager
    @AppStorage("dailyProteinGoal") private var dailyProteinGoal = 150
    @AppStorage("dailyWaterGoal") private var dailyWaterGoal = 2.5
    
    // Preferences
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("useMetricUnits") private var useMetricUnits = true
    
    // State
    @State private var showingEditProfile = false
    @State private var showingGoalsEditor = false
    @State private var showingRunningSettings = false
    @State private var showingClearDataAlert = false
    @State private var isSyncing = false
    @State private var showingSyncSuccess = false
    
    // Premium colors
    private let accentColor = Color(hex: "6366F1") // Indigo
    private let successColor = Color(hex: "10B981")
    private let warningColor = Color(hex: "F59E0B")
    private let dangerColor = Color(hex: "EF4444")
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Profile Card
                        profileCard
                        
                        // Quick Actions
                        quickActionsSection
                        
                        // Goals Section
                        goalsSection
                        
                        // Health Data Section
                        healthDataSection
                        
                        // Preferences Section
                        preferencesSection
                        
                        // Data Management Section
                        dataManagementSection
                        
                        // About Section
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingEditProfile) {
                EditProfileSheet(
                    userName: $userName,
                    healthKitService: healthKitService
                )
            }
            .sheet(isPresented: $showingGoalsEditor) {
                GoalsEditorSheet(
                    proteinGoal: $dailyProteinGoal,
                    waterGoal: $dailyWaterGoal,
                    smartCoach: smartCoach
                )
            }
            .sheet(isPresented: $showingRunningSettings) {
                RunningSettingsSheet(service: advancedRunning)
            }
            .alert("Clear All Data", isPresented: $showingClearDataAlert) {
                Button("Clear", role: .destructive) { clearAllData() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all your health data from the app. This action cannot be undone.")
            }
            .overlay {
                if showingSyncSuccess {
                    syncSuccessToast
                }
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                .ignoresSafeArea()
            
            // Subtle gradient accent
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
    
    // MARK: - Profile Card
    private var profileCard: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                // Data source badge
                if userProfile.isLoaded {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                        Text("Health Synced")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(successColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(successColor.opacity(0.12))
                    )
                }
            }
            
            // Profile Info
            HStack(spacing: 16) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: accentColor.opacity(0.3), radius: 12, x: 0, y: 6)
                    
                    Text(userName.isEmpty ? "?" : String(userName.prefix(1)).uppercased())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(userName.isEmpty ? "Your Name" : userName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    HStack(spacing: 12) {
                        if let weight = userProfile.weight {
                            profileStat(value: "\(Int(weight))", unit: "kg")
                        }
                        if let height = userProfile.height {
                            profileStat(value: "\(Int(height))", unit: "cm")
                        }
                        if let age = userProfile.age {
                            profileStat(value: "\(age)", unit: "yrs")
                        }
                    }
                    
                    // Max HR from age
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(dangerColor)
                        Text("Max HR: \(userProfile.maxHeartRate) bpm")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    }
                }
                
                Spacer()
                
                Button {
                    showingEditProfile = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accentColor)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        )
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func profileStat(value: String, unit: String) -> some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "9CA3AF"))
        }
    }
    
    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            quickActionButton(
                icon: "target",
                title: "Goals",
                color: successColor
            ) {
                showingGoalsEditor = true
            }
            
            quickActionButton(
                icon: "figure.run",
                title: "Running",
                color: Color(hex: "10B981")
            ) {
                showingRunningSettings = true
            }
            
            quickActionButton(
                icon: "arrow.clockwise",
                title: "Sync",
                color: Color(hex: "3B82F6")
            ) {
                Task { await syncHealthData() }
            }
        }
    }
    
    private func quickActionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Goals Section
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Daily Goals", icon: "target", color: successColor)
            
            VStack(spacing: 0) {
                goalRow(icon: "figure.walk", label: "Steps", value: "\(userProfile.dailyStepGoal.formatted())", color: successColor, showDivider: true)
                goalRow(icon: "flame.fill", label: "Active Calories", value: "\(Int(userProfile.dailyCalorieGoal)) kcal", color: warningColor, showDivider: true)
                goalRow(icon: "leaf.fill", label: "Protein", value: "\(dailyProteinGoal)g", color: Color(hex: "34D399"), showDivider: true)
                goalRow(icon: "drop.fill", label: "Water", value: String(format: "%.1fL", dailyWaterGoal), color: Color(hex: "3B82F6"), showDivider: true)
                goalRow(icon: "moon.zzz.fill", label: "Sleep", value: String(format: "%.1fh", userProfile.sleepGoalHours), color: Color(hex: "8B5CF6"), showDivider: false)
            }
            .background(cardBackground)
            
            Button {
                showingGoalsEditor = true
            } label: {
                HStack {
                    Text("Edit Goals")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(accentColor)
            }
            .padding(.top, 4)
        }
    }
    
    private func goalRow(icon: String, label: String, value: String, color: Color, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 28)
                
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                
                Spacer()
                
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            if showDivider {
                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .padding(.leading, 56)
            }
        }
    }
    
    // MARK: - Health Data Section
    private var healthDataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Health Data", icon: "heart.fill", color: dangerColor)
            
            VStack(spacing: 10) {
                // HealthKit Status
                settingsRow(
                    icon: "heart.fill",
                    iconColor: dangerColor,
                    title: "Apple Health",
                    subtitle: healthKitService.authorizationStatus == .sharingAuthorized ? "Connected" : "Not Connected",
                    subtitleColor: healthKitService.authorizationStatus == .sharingAuthorized ? successColor : warningColor
                ) {
                    if healthKitService.authorizationStatus != .sharingAuthorized {
                        Button {
                            Task { await healthKitService.requestAuthorization() }
                        } label: {
                            Text("Connect")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(accentColor)
                                .cornerRadius(8)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(successColor)
                            .font(.system(size: 20))
                    }
                }
                
                // Last Sync
                if let lastSync = healthKitService.lastSyncDate {
                    settingsRow(
                        icon: "clock.fill",
                        iconColor: Color(hex: "3B82F6"),
                        title: "Last Synced",
                        subtitle: lastSync.formatted(date: .abbreviated, time: .shortened),
                        subtitleColor: colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B")
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }
    
    // MARK: - Preferences Section
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Preferences", icon: "slider.horizontal.3", color: accentColor)
            
            VStack(spacing: 0) {
                // Notifications
                toggleRow(
                    icon: "bell.fill",
                    iconColor: warningColor,
                    title: "Notifications",
                    subtitle: "Reminders & alerts",
                    isOn: $notificationsEnabled,
                    showDivider: true
                )
                
                // Haptic Feedback
                toggleRow(
                    icon: "waveform",
                    iconColor: Color(hex: "8B5CF6"),
                    title: "Haptic Feedback",
                    subtitle: "Vibrations & touch feedback",
                    isOn: $hapticFeedback,
                    showDivider: true
                )
                
                // Units
                toggleRow(
                    icon: "ruler",
                    iconColor: Color(hex: "3B82F6"),
                    title: "Metric Units",
                    subtitle: useMetricUnits ? "kg, cm, km" : "lb, ft, mi",
                    isOn: $useMetricUnits,
                    showDivider: false
                )
            }
            .background(cardBackground)
        }
    }
    
    private func toggleRow(icon: String, iconColor: Color, title: String, subtitle: String, isOn: Binding<Bool>, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "9CA3AF"))
                }
                
                Spacer()
                
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if showDivider {
                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .padding(.leading, 68)
            }
        }
    }
    
    // MARK: - Data Management Section
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Data Management", icon: "externaldrive.fill", color: Color(hex: "6B7280"))
            
            VStack(spacing: 10) {
                // Sync Now
                Button {
                    Task { await syncHealthData() }
                } label: {
                    settingsRowContent(
                        icon: "arrow.clockwise",
                        iconColor: Color(hex: "3B82F6"),
                        title: "Sync Health Data",
                        subtitle: isSyncing ? "Syncing..." : "Update with latest data"
                    ) {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                
                // Export Data
                Button {
                    // Export functionality
                } label: {
                    settingsRowContent(
                        icon: "square.and.arrow.up",
                        iconColor: successColor,
                        title: "Export Data",
                        subtitle: "Download your health data"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    }
                }
                .buttonStyle(.plain)
                
                // Clear Data
                Button {
                    showingClearDataAlert = true
                } label: {
                    settingsRowContent(
                        icon: "trash.fill",
                        iconColor: dangerColor,
                        title: "Clear All Data",
                        subtitle: "Delete all stored data"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "About", icon: "info.circle.fill", color: Color(hex: "6B7280"))
            
            VStack(spacing: 10) {
                // Version
                settingsRow(
                    icon: "app.badge.fill",
                    iconColor: accentColor,
                    title: "Version",
                    subtitle: "1.0.0 (Build 1)",
                    subtitleColor: colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B")
                ) {
                    EmptyView()
                }
                
                // Privacy Policy
                Button {
                    if let url = URL(string: "https://apple.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    settingsRowContent(
                        icon: "lock.shield.fill",
                        iconColor: successColor,
                        title: "Privacy Policy",
                        subtitle: "How we protect your data"
                    ) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    }
                }
                .buttonStyle(.plain)
                
                // Terms of Service
                Button {
                    if let url = URL(string: "https://apple.com/legal") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    settingsRowContent(
                        icon: "doc.text.fill",
                        iconColor: Color(hex: "3B82F6"),
                        title: "Terms of Service",
                        subtitle: "Usage terms and conditions"
                    ) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    }
                }
                .buttonStyle(.plain)
                
                // Rate App
                Button {
                    // Rate app functionality
                } label: {
                    settingsRowContent(
                        icon: "star.fill",
                        iconColor: warningColor,
                        title: "Rate HealthAI",
                        subtitle: "Help us improve"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Footer
            VStack(spacing: 8) {
                Text("Made with ❤️ for your health")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                
                Text("© 2024 HealthAI")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        }
    }
    
    // MARK: - Helper Views
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
    }
    
    private func settingsRow<Trailing: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        subtitleColor: Color,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        settingsRowContent(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle, trailing: trailing)
    }
    
    private func settingsRowContent<Trailing: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "9CA3AF"))
            }
            
            Spacer()
            
            trailing()
        }
        .padding(14)
        .background(cardBackground)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.03),
                radius: 10, x: 0, y: 4
            )
    }
    
    private var syncSuccessToast: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(successColor)
                
                Text("Sync Complete")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color(hex: "1F2937"))
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Actions
    private func syncHealthData() async {
        await MainActor.run { isSyncing = true }
        
        // Sync user profile first to get accurate age, weight, etc.
        await UserProfileManager.shared.syncFromHealthKit()
        await healthKitService.syncHealthMetrics()
        await healthKitService.syncRecentWorkouts()
        
        await MainActor.run {
            isSyncing = false
            withAnimation(.spring()) {
                showingSyncSuccess = true
            }
        }
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        await MainActor.run {
            withAnimation(.spring()) {
                showingSyncSuccess = false
            }
        }
    }
    
    private func clearAllData() {
        let context = PersistenceController.shared.container.viewContext
        let entityNames = ["HealthMetrics", "WorkoutLog", "NutritionLog", "HeartRateReading", "Goal", "Achievement"]
        
        for entityName in entityNames {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try? context.execute(deleteRequest)
        }
        
        try? context.save()
    }
}

// MARK: - Edit Profile Sheet
struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var userProfile = UserProfileManager.shared
    
    @Binding var userName: String
    
    let healthKitService: HealthKitService
    
    @State private var isLoadingFromHealthKit = false
    @State private var localWeight: Double
    @State private var localHeight: Double
    @State private var localAge: Int
    @State private var localMaxHR: Int
    @State private var localRestingHR: Int
    
    private let accentColor = Color(hex: "6366F1")
    private let successColor = Color(hex: "10B981")
    private let dangerColor = Color(hex: "EF4444")
    
    init(userName: Binding<String>, healthKitService: HealthKitService) {
        self._userName = userName
        self.healthKitService = healthKitService
        
        let profile = UserProfileManager.shared
        _localWeight = State(initialValue: profile.weight ?? 70.0)
        _localHeight = State(initialValue: profile.height ?? 175.0)
        _localAge = State(initialValue: profile.age ?? 25)
        _localMaxHR = State(initialValue: profile.maxHeartRate)
        _localRestingHR = State(initialValue: profile.restingHeartRate ?? 60)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Name
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Name")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                            
                            TextField("Your Name", text: $userName)
                                .font(.system(size: 16, weight: .medium))
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                                )
                        }
                        
                        // Body Metrics
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Body Metrics")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                                
                                Spacer()
                                
                                Button {
                                    Task { await loadFromHealthKit() }
                                } label: {
                                    HStack(spacing: 4) {
                                        if isLoadingFromHealthKit {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        }
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 10))
                                        Text("Sync from Health")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(dangerColor)
                                }
                                .disabled(isLoadingFromHealthKit)
                            }
                            
                            VStack(spacing: 12) {
                                metricRow(label: "Weight", value: $localWeight, unit: "kg", range: 30...200)
                                metricRow(label: "Height", value: $localHeight, unit: "cm", range: 100...250)
                                
                                HStack {
                                    Text("Age")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                                    
                                    Spacer()
                                    
                                    Stepper("\(localAge) years", value: $localAge, in: 13...100)
                                        .font(.system(size: 14, weight: .semibold))
                                        .onChange(of: localAge) { newAge in
                                            // Auto-calculate max HR when age changes
                                            localMaxHR = userProfile.calculateMaxHeartRate(age: newAge)
                                        }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                                )
                            }
                        }
                        
                        // Heart Rate Settings
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Heart Rate")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                                
                                Spacer()
                                
                                Text("Used for training zones")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                            }
                            
                            VStack(spacing: 12) {
                                heartRateRow(label: "Max HR", value: $localMaxHR, unit: "bpm", range: 150...220, info: "208 - (0.7 × age)")
                                heartRateRow(label: "Resting HR", value: $localRestingHR, unit: "bpm", range: 40...100, info: "From Apple Watch")
                            }
                        }
                        
                        // Gender display
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Gender")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                            
                            HStack {
                                Text(userProfile.genderString)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                                
                                Spacer()
                                
                                Text("From Apple Health")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                            )
                        }
                        
                        // BMI display
                        if localWeight > 0 && localHeight > 0 {
                            let bmi = localWeight / pow(localHeight / 100, 2)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Body Mass Index (BMI)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                                
                                HStack {
                                    Text(String(format: "%.1f", bmi))
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(bmiColor(bmi))
                                    
                                    Text(bmiCategory(bmi))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(bmiColor(bmi))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(bmiColor(bmi).opacity(0.12))
                                        )
                                    
                                    Spacer()
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                }
            }
        }
    }
    
    private func metricRow(label: String, value: Binding<Double>, unit: String, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    if value.wrappedValue > range.lowerBound {
                        value.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accentColor)
                        .frame(width: 32, height: 32)
                        .background(accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    .frame(minWidth: 70)
                
                Button {
                    if value.wrappedValue < range.upperBound {
                        value.wrappedValue += 1
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accentColor)
                        .frame(width: 32, height: 32)
                        .background(accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func heartRateRow(label: String, value: Binding<Int>, unit: String, range: ClosedRange<Int>, info: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button {
                        if value.wrappedValue > range.lowerBound {
                            value.wrappedValue -= 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(dangerColor)
                            .frame(width: 32, height: 32)
                            .background(dangerColor.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Text("\(value.wrappedValue) \(unit)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        .frame(minWidth: 70)
                    
                    Button {
                        if value.wrappedValue < range.upperBound {
                            value.wrappedValue += 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(dangerColor)
                            .frame(width: 32, height: 32)
                            .background(dangerColor.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            
            Text(info)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func bmiColor(_ bmi: Double) -> Color {
        switch bmi {
        case ..<18.5: return Color(hex: "3B82F6")
        case 18.5..<25: return successColor
        case 25..<30: return Color(hex: "F59E0B")
        default: return dangerColor
        }
    }
    
    private func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }
    
    private func loadFromHealthKit() async {
        await MainActor.run { isLoadingFromHealthKit = true }
        
        await UserProfileManager.shared.syncFromHealthKit()
        
        await MainActor.run {
            localWeight = userProfile.weight ?? localWeight
            localHeight = userProfile.height ?? localHeight
            localAge = userProfile.age ?? localAge
            localMaxHR = userProfile.maxHeartRate
            localRestingHR = userProfile.restingHeartRate ?? localRestingHR
            isLoadingFromHealthKit = false
        }
    }
    
    private func saveProfile() {
        userProfile.setManualWeight(localWeight)
        userProfile.setManualHeight(localHeight)
        userProfile.setManualAge(localAge)
        userProfile.setManualMaxHR(localMaxHR)
        userProfile.setManualRestingHR(localRestingHR)
    }
}

// MARK: - Goals Editor Sheet
struct GoalsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var userProfile = UserProfileManager.shared
    
    @Binding var proteinGoal: Int
    @Binding var waterGoal: Double
    
    @State private var localStepsGoal: Int
    @State private var localCalorieGoal: Double
    @State private var localSleepGoal: Double
    
    let smartCoach: SmartCoachService
    
    private let accentColor = Color(hex: "6366F1")
    
    init(proteinGoal: Binding<Int>, waterGoal: Binding<Double>, smartCoach: SmartCoachService) {
        self._proteinGoal = proteinGoal
        self._waterGoal = waterGoal
        self.smartCoach = smartCoach
        
        let profile = UserProfileManager.shared
        _localStepsGoal = State(initialValue: profile.dailyStepGoal)
        _localCalorieGoal = State(initialValue: profile.dailyCalorieGoal)
        _localSleepGoal = State(initialValue: profile.sleepGoalHours)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Steps
                        goalSlider(
                            icon: "figure.walk",
                            title: "Daily Steps",
                            value: Binding(
                                get: { Double(localStepsGoal) },
                                set: { localStepsGoal = Int($0) }
                            ),
                            range: 5000...25000,
                            step: 1000,
                            format: { "\(Int($0).formatted())" },
                            color: Color(hex: "10B981")
                        )
                        
                        // Active Calories
                        goalSlider(
                            icon: "flame.fill",
                            title: "Active Calories",
                            value: $localCalorieGoal,
                            range: 200...1500,
                            step: 50,
                            format: { "\(Int($0)) kcal" },
                            color: Color(hex: "F59E0B")
                        )
                        
                        // Protein
                        goalSlider(
                            icon: "leaf.fill",
                            title: "Daily Protein",
                            value: Binding(
                                get: { Double(proteinGoal) },
                                set: { proteinGoal = Int($0) }
                            ),
                            range: 50...300,
                            step: 10,
                            format: { "\(Int($0))g" },
                            color: Color(hex: "34D399")
                        )
                        
                        // Water
                        goalSlider(
                            icon: "drop.fill",
                            title: "Daily Water",
                            value: $waterGoal,
                            range: 1...5,
                            step: 0.5,
                            format: { String(format: "%.1fL", $0) },
                            color: Color(hex: "3B82F6")
                        )
                        
                        // Sleep
                        goalSlider(
                            icon: "moon.zzz.fill",
                            title: "Sleep Goal",
                            value: $localSleepGoal,
                            range: 5...10,
                            step: 0.5,
                            format: { String(format: "%.1f hours", $0) },
                            color: Color(hex: "8B5CF6")
                        )
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Save to centralized UserProfileManager
                        userProfile.setDailyStepGoal(localStepsGoal)
                        userProfile.setDailyCalorieGoal(localCalorieGoal)
                        userProfile.setSleepGoal(localSleepGoal)
                        
                        // Also update SmartCoach
                        smartCoach.dailyCalorieTarget = localCalorieGoal
                        smartCoach.dailyProteinTarget = Double(proteinGoal)
                        smartCoach.saveGoals()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(accentColor)
                }
            }
        }
    }
    
    private func goalSlider(
        icon: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: (Double) -> String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text(format(value.wrappedValue))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
            }
            
            Slider(value: value, in: range, step: step)
                .tint(color)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
}

#Preview {
    ProfileView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(HealthKitService(context: PersistenceController.preview.container.viewContext))
}
