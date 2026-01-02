//
//  ContentView.swift
//  HealthAI
//
//  Created by Neel Sharma on 7/17/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var healthKitService: HealthKitService
    @StateObject private var aiService: AIService
    @StateObject private var analyticsService: AnalyticsService
    @StateObject private var workoutService = WorkoutService.shared
    @StateObject private var exerciseDatabase = ExerciseDatabase.shared
    @StateObject private var smartCoach = SmartCoachService.shared
    @StateObject private var userProfile = UserProfileManager.shared
    
    @State private var selectedTab = 0
    @State private var showingHealthKitAuth = false
    @State private var showingAddWorkout = false
    
    // Premium accent color
    private let accentColor = Color(hex: "E07A5F")
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _healthKitService = StateObject(wrappedValue: HealthKitService(context: context))
        _aiService = StateObject(wrappedValue: AIService(context: context, apiKey: nil))
        _analyticsService = StateObject(wrappedValue: AnalyticsService(context: context))
        
        // Configure tab bar with refined appearance
        configureTabBarAppearance()
    }
    
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        // Premium dark background
        appearance.backgroundColor = UIColor(Color(hex: "0A0A0B"))
        
        // Remove separator line for cleaner look
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()
        
        // Inactive state - subtle gray
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(white: 0.45, alpha: 1.0),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        
        // Active state - warm coral accent
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(Color(hex: "E07A5F")),
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(white: 0.45, alpha: 1.0)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color(hex: "E07A5F"))
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes
        
        // Compact layout (landscape)
        appearance.compactInlineLayoutAppearance.normal.iconColor = UIColor(white: 0.45, alpha: 1.0)
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.compactInlineLayoutAppearance.selected.iconColor = UIColor(Color(hex: "E07A5F"))
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = selectedAttributes
        
        // Inline layout
        appearance.inlineLayoutAppearance.normal.iconColor = UIColor(white: 0.45, alpha: 1.0)
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.inlineLayoutAppearance.selected.iconColor = UIColor(Color(hex: "E07A5F"))
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = selectedAttributes
        
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(white: 0.45, alpha: 1.0)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Smart Dashboard (Primary - The Connected Hub)
            SmartDashboardView()
                .tabItem {
                    Label("Today", systemImage: "square.grid.2x2")
                }
                .tag(0)
            
            // Workout Tab
            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(1)
            
            // Running Tab
            RunningView()
                .tabItem {
                    Label("Running", systemImage: "figure.run")
                }
                .tag(2)
            
            // Nutrition Tab
            NutritionView()
                .tabItem {
                    Label("Nutrition", systemImage: "leaf")
                }
                .tag(3)
            
            // Profile/Settings Tab
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(4)
        }
        .tint(accentColor)
        .environmentObject(healthKitService)
        .environmentObject(aiService)
        .environmentObject(analyticsService)
        .environmentObject(workoutService)
        .environmentObject(exerciseDatabase)
        .environmentObject(smartCoach)
        .environmentObject(userProfile)
        .environment(\.managedObjectContext, viewContext)
        .onAppear {
            requestHealthKitPermission()
            startPeriodicTasks()
            smartCoach.configure(with: viewContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await healthKitService.refreshAuthorizationStatus()
                smartCoach.refreshAllData()
            }
        }
    }
    
    private func requestHealthKitPermission() {
        Task {
            await healthKitService.requestAuthorization()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await healthKitService.refreshAuthorizationStatus()
            await startPeriodicTasks()
        }
    }
    
    private func startPeriodicTasks() {
        Task {
            print("Starting HealthKit sync...")
            // Sync user profile first for accurate age-based calculations
            await UserProfileManager.shared.syncFromHealthKit()
            await healthKitService.syncRecentWorkouts()
            await healthKitService.syncHealthMetrics()
            print("HealthKit sync completed")
            print("📊 User Profile: Age=\(UserProfileManager.shared.age ?? 0), MaxHR=\(UserProfileManager.shared.maxHeartRate), Weight=\(UserProfileManager.shared.weight ?? 0)kg")
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
