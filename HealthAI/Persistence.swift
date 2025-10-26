//
//  Persistence.swift
//  HealthAI
//
//  Created by Neel Sharma on 7/17/25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample health metrics
        for i in 0..<7 {
            let healthMetric = HealthMetrics(context: viewContext)
            healthMetric.id = UUID()
            healthMetric.date = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            healthMetric.stepCount = Int32.random(in: 5000...15000)
            healthMetric.restingHeartRate = Int16.random(in: 60...100)
            healthMetric.activeCalories = Double.random(in: 200...800)
            healthMetric.totalDistance = Double.random(in: 1...10)
            healthMetric.sleepHours = Double.random(in: 6...9)
        }
        
        // Create sample workout logs
        for i in 0..<5 {
            let workout = WorkoutLog(context: viewContext)
            workout.id = UUID()
            workout.timestamp = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            workout.workoutType = ["Running", "Cycling", "Swimming", "Strength Training"].randomElement() ?? "Running"
            workout.duration = Double.random(in: 20...90)
            workout.calories = Double.random(in: 150...600)
            workout.distance = Double.random(in: 1...15)
        }
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "HealthAI")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Set up automatic migration options
            let storeDescription = container.persistentStoreDescriptions.first!
            storeDescription.shouldMigrateStoreAutomatically = true
            storeDescription.shouldInferMappingModelAutomatically = true
        }
        loadPersistentStore()
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Configure automatic saving
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
    }
    
    private func loadPersistentStore() {
        container.loadPersistentStores { [self] (storeDescription, error) in
            
            if let error = error as NSError? {
                // Check if this is a model incompatibility error (134140)
                if error.code == 134140 {
                    // Model incompatibility - delete the old database and try again
                    print("Core Data model incompatibility detected. Recreating database...")
                    
                    if let storeURL = storeDescription.url {
                        self.deleteStoreFiles(at: storeURL)
                        
                        // Try loading the store again (only once to avoid infinite recursion)
                        container.loadPersistentStores { (_, secondError) in
                            if let secondError = secondError {
                                print("Failed to recreate database: \(secondError)")
                                fatalError("Unresolved error after database recreation: \(secondError)")
                            } else {
                                print("Database recreated successfully")
                            }
                        }
                    } else {
                        fatalError("No store URL available for database recreation")
                    }
                } else {
                    // Other Core Data errors
                    print("Core Data error: \(error), \(error.userInfo)")
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            } else {
                print("Core Data store loaded successfully")
            }
        }
    }
    
    private func deleteStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        let storeDirectory = storeURL.deletingLastPathComponent()
        let storeName = storeURL.lastPathComponent
        
        // Delete main store file
        try? fileManager.removeItem(at: storeURL)
        
        // Delete associated files (WAL, SHM, etc.)
        let associatedFiles = [
            storeName + "-wal",
            storeName + "-shm",
            storeName + "-journal"
        ]
        
        for fileName in associatedFiles {
            let fileURL = storeDirectory.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: fileURL)
        }
        
        print("Database files deleted successfully")
    }
}
