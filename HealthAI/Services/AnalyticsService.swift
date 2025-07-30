import Foundation
import CoreData

class AnalyticsService: ObservableObject {
    private let viewContext: NSManagedObjectContext
    
    @Published var isCalculating = false
    @Published var lastAnalysisDate: Date?
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
    }
    
    // MARK: - Health Analytics (Simplified for 4-tab app)
    func analyzeAndAdjustGoals() async {
        await MainActor.run {
            isCalculating = true
        }
        
        // Perform basic health data analysis
        await analyzeHealthTrends()
        
        await MainActor.run {
            isCalculating = false
            lastAnalysisDate = Date()
        }
    }
    
    private func analyzeHealthTrends() async {
        // Analyze health metrics trends
        await analyzeActivityTrends()
        await analyzeWorkoutTrends()
        await analyzeNutritionTrends()
    }
    
    private func analyzeActivityTrends() async {
        let request: NSFetchRequest<HealthMetrics> = HealthMetrics.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)]
        request.fetchLimit = 30 // Last 30 days
        
        do {
            let metrics = try viewContext.fetch(request)
            
            // Calculate average activity levels
            let avgSteps = metrics.compactMap { $0.stepCount }.reduce(0, +) / Int32(metrics.count)
            let avgCalories = metrics.compactMap { $0.activeCalories }.reduce(0, +) / Double(metrics.count)
            let avgSleep = metrics.compactMap { $0.sleepHours }.reduce(0, +) / Double(metrics.count)
            
            print("Health Trends Analysis:")
            print("Average Steps: \(avgSteps)")
            print("Average Calories Burned: \(avgCalories)")
            print("Average Sleep Hours: \(avgSleep)")
            
        } catch {
            print("Error analyzing health trends: \(error)")
        }
    }
    
    private func analyzeWorkoutTrends() async {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)]
        request.fetchLimit = 20 // Last 20 workouts
        
        do {
            let workouts = try viewContext.fetch(request)
            
            // Calculate workout frequency and performance
            let workoutFrequency = workouts.count
            let avgDuration = workouts.compactMap { $0.duration }.reduce(0, +) / Double(workouts.count)
            let avgCalories = workouts.compactMap { $0.calories }.reduce(0, +) / Double(workouts.count)
            
            print("Workout Trends Analysis:")
            print("Recent Workouts: \(workoutFrequency)")
            print("Average Duration: \(avgDuration) minutes")
            print("Average Calories per Workout: \(avgCalories)")
            
        } catch {
            print("Error analyzing workout trends: \(error)")
        }
    }
    
    private func analyzeNutritionTrends() async {
        let request: NSFetchRequest<NutritionLog> = NutritionLog.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \NutritionLog.date, ascending: false)]
        request.fetchLimit = 14 // Last 14 days
        
        do {
            let nutritionLogs = try viewContext.fetch(request)
            
            // Calculate nutrition averages
            let avgCalories = nutritionLogs.compactMap { $0.calories }.reduce(0, +) / Double(nutritionLogs.count)
            let avgProtein = nutritionLogs.compactMap { $0.protein }.reduce(0, +) / Double(nutritionLogs.count)
            let avgCarbs = nutritionLogs.compactMap { $0.carbs }.reduce(0, +) / Double(nutritionLogs.count)
            let avgFat = nutritionLogs.compactMap { $0.fat }.reduce(0, +) / Double(nutritionLogs.count)
            
            print("Nutrition Trends Analysis:")
            print("Average Daily Calories: \(avgCalories)")
            print("Average Protein: \(avgProtein)g")
            print("Average Carbs: \(avgCarbs)g")
            print("Average Fat: \(avgFat)g")
            
        } catch {
            print("Error analyzing nutrition trends: \(error)")
        }
    }
    
    // MARK: - Health Insights
    func generateHealthInsights() async -> [HealthInsight] {
        var insights: [HealthInsight] = []
        
        // Activity insights
        if let activityInsight = await generateActivityInsight() {
            insights.append(activityInsight)
        }
        
        // Workout insights
        if let workoutInsight = await generateWorkoutInsight() {
            insights.append(workoutInsight)
        }
        
        // Nutrition insights
        if let nutritionInsight = await generateNutritionInsight() {
            insights.append(nutritionInsight)
        }
        
        return insights
    }
    
    private func generateActivityInsight() async -> HealthInsight? {
        // Generate activity-based insights
        return HealthInsight(
            title: "Activity Level",
            description: "Your activity levels have been consistent this week",
            category: "Activity",
            recommendation: "Try to increase daily steps by 500 for better health benefits"
        )
    }
    
    private func generateWorkoutInsight() async -> HealthInsight? {
        // Generate workout-based insights
        return HealthInsight(
            title: "Workout Frequency",
            description: "You've been maintaining a good workout schedule",
            category: "Fitness",
            recommendation: "Consider adding variety to your workout routine"
        )
    }
    
    private func generateNutritionInsight() async -> HealthInsight? {
        // Generate nutrition-based insights
        return HealthInsight(
            title: "Nutrition Balance",
            description: "Your protein intake is on track",
            category: "Nutrition",
            recommendation: "Focus on increasing vegetable intake for better micronutrients"
        )
    }
}

// MARK: - Health Insight Model
struct HealthInsight {
    let title: String
    let description: String
    let category: String
    let recommendation: String
} 