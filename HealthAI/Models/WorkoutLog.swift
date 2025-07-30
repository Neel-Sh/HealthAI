import Foundation
import CoreData
import HealthKit

@objc(WorkoutLog)
public class WorkoutLog: NSManagedObject {
    @NSManaged public var id: UUID // Change `id` type to UUID for compatibility
    @NSManaged public var workoutType: String // "run", "walk", "bike", "stretch", "strength"
    @NSManaged public var distance: Double
    @NSManaged public var duration: Double
    @NSManaged public var calories: Double
    @NSManaged public var avgHeartRate: Int16
    @NSManaged public var maxHeartRate: Int16
    @NSManaged public var timestamp: Date
    @NSManaged public var route: Data? // Store route coordinates
    @NSManaged public var pace: Double
    @NSManaged public var elevation: Double
    @NSManaged public var vo2Max: Double
    @NSManaged public var hrv: Double // Heart Rate Variability
    @NSManaged public var cadence: Double
    @NSManaged public var powerOutput: Double
    @NSManaged public var perceivedExertion: Int16 // 1-10 scale
    @NSManaged public var weatherCondition: String?
    @NSManaged public var temperature: Double
    @NSManaged public var notes: String?
    @NSManaged public var isFromHealthKit: Bool
    @NSManaged public var healthKitUUID: String?
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
        self.timestamp = Date()
        self.distance = 0.0
        self.duration = 0.0
        self.calories = 0.0
        self.avgHeartRate = 0
        self.maxHeartRate = 0
        self.pace = 0.0
        self.elevation = 0.0
        self.vo2Max = 0.0
        self.hrv = 0.0
        self.cadence = 0.0
        self.powerOutput = 0.0
        self.perceivedExertion = 0
        self.temperature = 0.0
        self.isFromHealthKit = false
    }
}

extension WorkoutLog {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WorkoutLog> {
        return NSFetchRequest<WorkoutLog>(entityName: "WorkoutLog")
    }
}

extension WorkoutLog: Identifiable {
    // Remove the objectID override - NSManagedObject already provides this
}

// MARK: - Computed Properties
extension WorkoutLog {
    var formattedDistance: String {
        return String(format: "%.2f km", distance)
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedPace: String {
        let paceMinutes = Int(pace) / 60
        let paceSeconds = Int(pace) % 60
        return String(format: "%d:%02d /km", paceMinutes, paceSeconds)
    }
    
    var workoutTypeIcon: String {
        switch workoutType {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "stretch": return "figure.flexibility"
        case "strength": return "dumbbell"
        default: return "heart"
        }
    }
    
    var idString: String {
        id.uuidString
    }
}