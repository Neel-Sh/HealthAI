import Foundation
import CoreData

@objc(NutritionLog)
public class NutritionLog: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var mealType: String // "breakfast", "lunch", "dinner", "snack"
    @NSManaged public var foodName: String
    @NSManaged public var quantity: Double
    @NSManaged public var unit: String // "grams", "cups", "pieces", etc.
    @NSManaged public var calories: Double
    @NSManaged public var protein: Double // grams
    @NSManaged public var carbs: Double // grams
    @NSManaged public var fat: Double // grams
    @NSManaged public var fiber: Double // grams
    @NSManaged public var sugar: Double // grams
    @NSManaged public var sodium: Double // mg
    @NSManaged public var waterIntake: Double // ml
    
    // Vitamins (mcg or mg)
    @NSManaged public var vitaminA: Double // mcg
    @NSManaged public var vitaminC: Double // mg
    @NSManaged public var vitaminD: Double // mcg
    @NSManaged public var vitaminE: Double // mg
    @NSManaged public var vitaminK: Double // mcg
    @NSManaged public var vitaminB1: Double // mg (Thiamin)
    @NSManaged public var vitaminB2: Double // mg (Riboflavin)
    @NSManaged public var vitaminB3: Double // mg (Niacin)
    @NSManaged public var vitaminB6: Double // mg
    @NSManaged public var vitaminB12: Double // mcg
    @NSManaged public var folate: Double // mcg
    
    // Minerals (mg)
    @NSManaged public var calcium: Double // mg
    @NSManaged public var iron: Double // mg
    @NSManaged public var magnesium: Double // mg
    @NSManaged public var phosphorus: Double // mg
    @NSManaged public var potassium: Double // mg
    @NSManaged public var zinc: Double // mg
    
    @NSManaged public var notes: String?
    @NSManaged public var isFromApp: Bool
    @NSManaged public var isFromAI: Bool
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
        self.date = Date()
        self.quantity = 0.0
        self.calories = 0.0
        self.protein = 0.0
        self.carbs = 0.0
        self.fat = 0.0
        self.fiber = 0.0
        self.sugar = 0.0
        self.sodium = 0.0
        self.waterIntake = 0.0
        
        // Initialize vitamins
        self.vitaminA = 0.0
        self.vitaminC = 0.0
        self.vitaminD = 0.0
        self.vitaminE = 0.0
        self.vitaminK = 0.0
        self.vitaminB1 = 0.0
        self.vitaminB2 = 0.0
        self.vitaminB3 = 0.0
        self.vitaminB6 = 0.0
        self.vitaminB12 = 0.0
        self.folate = 0.0
        
        // Initialize minerals
        self.calcium = 0.0
        self.iron = 0.0
        self.magnesium = 0.0
        self.phosphorus = 0.0
        self.potassium = 0.0
        self.zinc = 0.0
        
        self.isFromApp = true
        self.isFromAI = false
    }
}

extension NutritionLog {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<NutritionLog> {
        return NSFetchRequest<NutritionLog>(entityName: "NutritionLog")
    }
}

extension NutritionLog: Identifiable {
    // Remove the objectID override - NSManagedObject already provides this
}

@objc(MealPlan)
public class MealPlan: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var planDescription: String
    @NSManaged public var startDate: Date
    @NSManaged public var endDate: Date
    @NSManaged public var targetCalories: Double
    @NSManaged public var targetProtein: Double
    @NSManaged public var targetCarbs: Double
    @NSManaged public var targetFat: Double
    @NSManaged public var isActive: Bool
    @NSManaged public var createdDate: Date
    @NSManaged public var dietaryRestrictions: String? // JSON array
    @NSManaged public var goals: String? // JSON array: "weight_loss", "muscle_gain", "endurance", etc.
    @NSManaged public var meals: NSSet? // PlannedMeal relationship
    
    override public func awakeFromInsert() {
        super.awakeFromInsert()
        self.id = UUID()
        self.createdDate = Date()
        self.isActive = false
        self.targetCalories = 0.0
        self.targetProtein = 0.0
        self.targetCarbs = 0.0
        self.targetFat = 0.0
    }
}

extension MealPlan {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MealPlan> {
        return NSFetchRequest<MealPlan>(entityName: "MealPlan")
    }
}

extension MealPlan: Identifiable {
    // Remove the objectID override - NSManagedObject already provides this
}

@objc(PlannedMeal)
public class PlannedMeal: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var mealPlanID: UUID
    @NSManaged public var date: Date
    @NSManaged public var mealType: String
    @NSManaged public var recipeName: String
    @NSManaged public var ingredients: String // JSON array
    @NSManaged public var instructions: String
    @NSManaged public var prepTime: Int16 // minutes
    @NSManaged public var cookTime: Int16 // minutes
    @NSManaged public var servings: Int16
    @NSManaged public var calories: Double
    @NSManaged public var protein: Double
    @NSManaged public var carbs: Double
    @NSManaged public var fat: Double
    @NSManaged public var isCompleted: Bool
    @NSManaged public var rating: Int16 // 1-5 stars
    @NSManaged public var notes: String?
}

extension PlannedMeal {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PlannedMeal> {
        return NSFetchRequest<PlannedMeal>(entityName: "PlannedMeal")
    }
}

extension PlannedMeal: Identifiable {
    public override var objectID: NSManagedObjectID {
        return self.objectID
    }
}

// MARK: - Computed Properties
extension NutritionLog {
    var mealIcon: String {
        switch mealType {
        case "breakfast": return "sun.rise"
        case "lunch": return "sun.max"
        case "dinner": return "sun.set"
        case "snack": return "leaf"
        default: return "fork.knife"
        }
    }
    
    var macroBreakdown: String {
        let totalMacros = protein + carbs + fat
        guard totalMacros > 0 else { return "N/A" }
        
        let proteinPercent = Int((protein / totalMacros) * 100)
        let carbPercent = Int((carbs / totalMacros) * 100)
        let fatPercent = Int((fat / totalMacros) * 100)
        
        return "P: \(proteinPercent)% | C: \(carbPercent)% | F: \(fatPercent)%"
    }
} 
