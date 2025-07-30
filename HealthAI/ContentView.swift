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
    @StateObject private var healthKitService: HealthKitService
    @StateObject private var aiService: AIService
    @StateObject private var analyticsService: AnalyticsService
    
    @State private var selectedTab = 0
    @State private var showingHealthKitAuth = false
    @State private var showingAddWorkout = false
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        _healthKitService = StateObject(wrappedValue: HealthKitService(context: context))
        _aiService = StateObject(wrappedValue: AIService(context: context, apiKey: "")) // Configure with actual API key
        _analyticsService = StateObject(wrappedValue: AnalyticsService(context: context))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Health Dashboard Tab
            HealthDashboardView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Dashboard")
                }
                .tag(0)
            
            // Nutrition Tab
            NutritionView()
                .tabItem {
                    Image(systemName: "fork.knife")
                    Text("Nutrition")
                }
                .tag(1)
            
            // AI Chat Tab
            AIChatView()
                .tabItem {
                    Image(systemName: "brain.head.profile")
                    Text("AI Coach")
                }
                .tag(2)
            
            // Settings Tab
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(3)
        }
        .environmentObject(healthKitService)
        .environmentObject(aiService)
        .environmentObject(analyticsService)
        .environment(\.managedObjectContext, viewContext)
        .onAppear {
            requestHealthKitPermission()
            startPeriodicTasks()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Refresh authorization status when app becomes active (e.g., returning from Settings)
            Task {
                await healthKitService.refreshAuthorizationStatus()
            }
        }
    }
    
    private func requestHealthKitPermission() {
        Task {
            await healthKitService.requestAuthorization()
            // Give authorization time to process
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            // Force refresh the authorization status
            await healthKitService.refreshAuthorizationStatus()
            // Then try sync again
            await startPeriodicTasks()
        }
    }
    
    private func startPeriodicTasks() {
        Task {
            print("Starting HealthKit sync...")
            await healthKitService.syncRecentWorkouts()
            await healthKitService.syncHealthMetrics()
            // Goal analysis removed for simplified app
            print("HealthKit sync completed")
        }
    }
}

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
