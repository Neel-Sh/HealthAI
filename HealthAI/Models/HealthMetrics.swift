import Foundation
import CoreData

@objc(HealthMetrics)
public class HealthMetrics: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var restingHeartRate: Int16
    @NSManaged public var hrv: Double // Heart Rate Variability
    @NSManaged public var vo2Max: Double
    @NSManaged public var sleepHours: Double
    @NSManaged public var sleepQuality: Int16 // 1-10 scale
    @NSManaged public var deepSleepHours: Double
    @NSManaged public var remSleepHours: Double
    @NSManaged public var timeInBed: Double // Total time in bed for sleep efficiency calculation
    @NSManaged public var bloodOxygen: Double // Blood oxygen saturation percentage
    @NSManaged public var respiratoryRate: Double // Breaths per minute
    @NSManaged public var bodyWeight: Double
    @NSManaged public var bodyFatPercentage: Double
    @NSManaged public var hydrationLevel: Double // liters
    @NSManaged public var stressLevel: Int16 // 1-10 scale
    @NSManaged public var energyLevel: Int16 // 1-10 scale
    @NSManaged public var recoveryScore: Double // 0-100
    @NSManaged public var readinessScore: Double // 0-100
    @NSManaged public var stepCount: Int32
    @NSManaged public var activeCalories: Double
    @NSManaged public var totalCalories: Double
    @NSManaged public var totalDistance: Double
    @NSManaged public var activeMinutes: Int16
    @NSManaged public var workoutCount: Int32
    @NSManaged public var isFromHealthKit: Bool
    @NSManaged public var basalCalories: Double
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
        self.date = Date()
        self.restingHeartRate = 0
        self.hrv = 0.0
        self.vo2Max = 0.0
        self.sleepHours = 0.0
        self.sleepQuality = 0
        self.deepSleepHours = 0.0
        self.remSleepHours = 0.0
        self.timeInBed = 0.0
        self.bloodOxygen = 0.0
        self.respiratoryRate = 0.0
        self.bodyWeight = 0.0
        self.bodyFatPercentage = 0.0
        self.hydrationLevel = 0.0
        self.stressLevel = 0
        self.energyLevel = 0
        self.recoveryScore = 0.0
        self.readinessScore = 0.0
        self.stepCount = 0
        self.activeCalories = 0.0
        self.totalCalories = 0.0
        self.totalDistance = 0.0
        self.activeMinutes = 0
        self.workoutCount = 0
        self.isFromHealthKit = false
        self.basalCalories = 0.0
    }
}

// New model for detailed heart rate readings throughout the day
@objc(HeartRateReading)
public class HeartRateReading: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var heartRate: Int16
    @NSManaged public var timestamp: Date
    @NSManaged public var isFromHealthKit: Bool
    @NSManaged public var context: String? // "resting", "workout", "active", "recovery"
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
        self.timestamp = Date()
        self.heartRate = 0
        self.isFromHealthKit = false
        self.context = "active"
    }
}

extension HealthMetrics {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<HealthMetrics> {
        return NSFetchRequest<HealthMetrics>(entityName: "HealthMetrics")
    }
}

extension HeartRateReading {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<HeartRateReading> {
        return NSFetchRequest<HeartRateReading>(entityName: "HeartRateReading")
    }
}

extension HealthMetrics: Identifiable {
    // Remove the objectID override - NSManagedObject already provides this
}

// MARK: - Computed Properties
extension HealthMetrics {
    var recoveryStatus: String {
        switch recoveryScore {
        case 80...100: return "Excellent"
        case 60...79: return "Good"
        case 40...59: return "Fair"
        case 20...39: return "Poor"
        default: return "Critical"
        }
    }
    
    var recoveryColor: String {
        switch recoveryScore {
        case 80...100: return "green"
        case 60...79: return "blue"
        case 40...59: return "yellow"
        case 20...39: return "orange"
        default: return "red"
        }
    }
    
    var sleepQualityText: String {
        switch sleepQuality {
        case 8...10: return "Excellent"
        case 6...7: return "Good"
        case 4...5: return "Fair"
        case 2...3: return "Poor"
        default: return "Very Poor"
        }
    }
} 