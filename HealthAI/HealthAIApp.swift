//
//  HealthAIApp.swift
//  HealthAI
//
//  Created by Neel Sharma on 7/17/25.
//

import SwiftUI
import CoreData
import UserNotifications

@main
struct HealthAIApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var notificationService = NotificationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    Task {
                        await notificationService.requestAuthorization()
                        await notificationService.scheduleDefaultDailyReminders()
                    }
                }
        }
    }
}
