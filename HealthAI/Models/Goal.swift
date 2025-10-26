import Foundation
import CoreData

@objc(Goal)
public class Goal: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var goalDescription: String
    @NSManaged public var targetValue: Double
    @NSManaged public var currentValue: Double
    @NSManaged public var unit: String
    @NSManaged public var category: String // "fitness", "nutrition", "health"
    @NSManaged public var targetDate: Date
    @NSManaged public var createdDate: Date
    @NSManaged public var isCompleted: Bool
    @NSManaged public var isActive: Bool
    @NSManaged public var priority: Int16 // 1-5 scale
    @NSManaged public var reminderEnabled: Bool
    @NSManaged public var reminderTime: Date?
    @NSManaged public var notes: String?
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
        self.createdDate = Date()
        self.targetDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        self.currentValue = 0.0
        self.targetValue = 0.0
        self.isCompleted = false
        self.isActive = true
        self.priority = 3
        self.reminderEnabled = false
    }
}

extension Goal {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Goal> {
        return NSFetchRequest<Goal>(entityName: "Goal")
    }
}

extension Goal: Identifiable {
    // NSManagedObject already provides objectID
}

// MARK: - Computed Properties
extension Goal {
    var progressPercentage: Double {
        guard targetValue > 0 else { return 0 }
        return min(currentValue / targetValue * 100, 100)
    }
    
    var isOverdue: Bool {
        return !isCompleted && targetDate < Date()
    }
    
    var daysRemaining: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: targetDate)
        return components.day ?? 0
    }
    
    var categoryIcon: String {
        switch category {
        case "fitness": return "figure.run"
        case "nutrition": return "fork.knife"
        case "health": return "heart.fill"
        default: return "target"
        }
    }
    
    var categoryColor: String {
        switch category {
        case "fitness": return "blue"
        case "nutrition": return "green"
        case "health": return "red"
        default: return "gray"
        }
    }
    
    var statusText: String {
        if isCompleted {
            return "Completed"
        } else if isOverdue {
            return "Overdue"
        } else {
            return "In Progress"
        }
    }
}
