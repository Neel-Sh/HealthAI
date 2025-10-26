import Foundation
import CoreData

@objc(Achievement)
public class Achievement: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var achievementDescription: String
    @NSManaged public var iconName: String
    @NSManaged public var category: String
    @NSManaged public var earnedDate: Date?
    @NSManaged public var isEarned: Bool
    @NSManaged public var points: Int16
    @NSManaged public var rarity: String
    @NSManaged public var progress: Double
    @NSManaged public var currentValue: Double
    @NSManaged public var targetValue: Double
    @NSManaged public var isRepeatable: Bool
    @NSManaged public var timesEarned: Int16
    @NSManaged public var nextMilestone: Double
    @NSManaged public var lastResetDate: Date?
    @NSManaged public var shareableText: String?
    @NSManaged public var unit: String
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
        self.isEarned = false
        self.points = 0
        self.progress = 0.0
        self.currentValue = 0.0
        self.targetValue = 0.0
        self.isRepeatable = false
        self.timesEarned = 0
        self.nextMilestone = 0.0
        self.rarity = "common"
        self.unit = ""
    }
}

extension Achievement {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Achievement> {
        return NSFetchRequest<Achievement>(entityName: "Achievement")
    }
}

extension Achievement: Identifiable {
    // NSManagedObject already provides objectID
}

// MARK: - Computed Properties
extension Achievement {
    var progressPercentage: Double {
        return min(progress * 100, 100)
    }
    
    var rarityColor: String {
        switch rarity {
        case "common": return "gray"
        case "rare": return "blue"
        case "epic": return "purple"
        case "legendary": return "orange"
        default: return "gray"
        }
    }
    
    var categoryIcon: String {
        switch category {
        case "fitness": return "figure.run"
        case "nutrition": return "fork.knife"
        case "health": return "heart.fill"
        case "milestone": return "star.fill"
        default: return "trophy.fill"
        }
    }
    
    var displayTitle: String {
        return isEarned ? title : "???"
    }
    
    var displayDescription: String {
        return isEarned ? achievementDescription : "Keep working to unlock this achievement!"
    }
    
    var formattedEarnedDate: String {
        guard let date = earnedDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Achievement Types
extension Achievement {
    static let predefinedAchievements: [(title: String, description: String, icon: String, category: String, rarity: String, points: Int16)] = [
        ("First Steps", "Complete your first workout", "figure.walk", "fitness", "common", 10),
        ("Marathon Ready", "Run a total of 42.2 km", "figure.run", "fitness", "epic", 100),
        ("Consistency King", "Work out 7 days in a row", "calendar", "fitness", "rare", 50),
        ("Early Bird", "Complete a workout before 7 AM", "sunrise.fill", "fitness", "common", 20),
        ("Healthy Eater", "Log 30 days of nutrition", "fork.knife", "nutrition", "rare", 75),
        ("Hydration Hero", "Drink 8 glasses of water in a day", "drop.fill", "nutrition", "common", 15),
        ("Heart Strong", "Maintain target heart rate for 30 minutes", "heart.fill", "health", "rare", 60),
        ("Sleep Champion", "Get 8+ hours of sleep for 5 nights", "bed.double.fill", "health", "common", 25),
        ("Century Club", "Burn 100 active calories in a day", "flame.fill", "fitness", "common", 30),
        ("Distance Destroyer", "Walk/run 10km in a single workout", "location.fill", "fitness", "rare", 40)
    ]
}
