//
//  HealthAIApp.swift
//  HealthAI
//
//  Created by Neel Sharma on 7/17/25.
//

import SwiftUI
import CoreData

@main
struct HealthAIApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
