import Foundation
import SwiftUI
import Combine
import CoreData

// MARK: - Smart Coach Service
/// The brain of the app - connects workouts, nutrition, and health data intelligently
@MainActor
class SmartCoachService: ObservableObject {
    static let shared = SmartCoachService()
    
    // Dependencies
    private var healthContext: NSManagedObjectContext?
    private var workoutService: WorkoutService { WorkoutService.shared }
    private var exerciseDatabase: ExerciseDatabase { ExerciseDatabase.shared }
    
    // Published State
    @Published var todayReadiness: ReadinessScore = ReadinessScore()
    @Published var currentInsights: [SmartInsight] = []
    @Published var recommendedWorkout: WorkoutRecommendation?
    @Published var nutritionStatus: NutritionStatus = NutritionStatus()
    @Published var weeklyAnalysis: WeeklyAnalysis?
    @Published var muscleRecoveryMap: [MuscleGroup: MuscleRecoveryStatus] = [:]
    
    // Goals
    @Published var fitnessGoal: FitnessGoal = .buildMuscle
    @Published var targetWeight: Double = 0
    @Published var dailyCalorieTarget: Double = 2500
    @Published var dailyProteinTarget: Double = 150
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupDefaultGoals()
    }
    
    func configure(with context: NSManagedObjectContext) {
        self.healthContext = context
        refreshAllData()
    }
    
    // MARK: - Main Refresh
    func refreshAllData() {
        calculateReadinessScore()
        updateMuscleRecoveryMap()
        generateRecommendedWorkout()
        generateInsights()
        updateNutritionStatus()
        analyzeWeek()
    }
    
    private func setupDefaultGoals() {
        // Load from UserDefaults
        fitnessGoal = FitnessGoal(rawValue: UserDefaults.standard.string(forKey: "fitnessGoal") ?? "") ?? .buildMuscle
        targetWeight = UserDefaults.standard.double(forKey: "targetWeight")
        dailyCalorieTarget = UserDefaults.standard.double(forKey: "dailyCalorieTarget")
        dailyProteinTarget = UserDefaults.standard.double(forKey: "dailyProteinTarget")
        
        if dailyCalorieTarget == 0 { dailyCalorieTarget = 2500 }
        if dailyProteinTarget == 0 { dailyProteinTarget = 150 }
    }
    
    func saveGoals() {
        UserDefaults.standard.set(fitnessGoal.rawValue, forKey: "fitnessGoal")
        UserDefaults.standard.set(targetWeight, forKey: "targetWeight")
        UserDefaults.standard.set(dailyCalorieTarget, forKey: "dailyCalorieTarget")
        UserDefaults.standard.set(dailyProteinTarget, forKey: "dailyProteinTarget")
    }
    
    // MARK: - Readiness Score Calculation
    private func calculateReadinessScore() {
        guard let context = healthContext else { return }
        
        let request: NSFetchRequest<HealthMetrics> = HealthMetrics.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)]
        request.fetchLimit = 7
        
        guard let metrics = try? context.fetch(request), let today = metrics.first else {
            todayReadiness = ReadinessScore()
            return
        }
        
        var score = ReadinessScore()
        
        // Sleep Component (0-25 points)
        let sleepScore: Double = {
            let hours = today.sleepHours
            let quality = Double(today.sleepQuality)
            if hours >= 7 && hours <= 9 {
                return min(15 + (quality / 10) * 10, 25)
            } else if hours >= 6 {
                return min(10 + (quality / 10) * 8, 20)
            } else {
                return max(5, hours * 2)
            }
        }()
        score.sleepScore = sleepScore
        score.sleepDetail = formatSleepDetail(hours: today.sleepHours, quality: Int(today.sleepQuality))
        
        // Recovery Component (0-25 points) - HRV + Resting HR
        let recoveryScore: Double = {
            let hrv = today.hrv
            let restingHR = today.restingHeartRate
            
            var points: Double = 0
            
            // HRV scoring (higher is better)
            if hrv >= 60 { points += 15 }
            else if hrv >= 45 { points += 12 }
            else if hrv >= 30 { points += 8 }
            else { points += 5 }
            
            // Resting HR scoring (lower is better)
            if restingHR > 0 {
                if restingHR <= 55 { points += 10 }
                else if restingHR <= 65 { points += 8 }
                else if restingHR <= 75 { points += 5 }
                else { points += 2 }
            }
            
            return min(points, 25)
        }()
        score.recoveryScore = recoveryScore
        score.recoveryDetail = formatRecoveryDetail(hrv: today.hrv, restingHR: Int(today.restingHeartRate))
        
        // Training Load Component (0-25 points)
        let trainingScore: Double = {
            let recentWorkouts = workoutService.workoutHistory.prefix(7)
            let workoutsThisWeek = recentWorkouts.filter { 
                Calendar.current.isDate($0.startTime, equalTo: Date(), toGranularity: .weekOfYear)
            }.count
            
            // Check for overtraining or undertraining
            switch workoutsThisWeek {
            case 0: return 15 // Fresh but maybe inactive
            case 1...2: return 20 // Light week, well recovered
            case 3...4: return 25 // Optimal training frequency
            case 5: return 20 // High frequency, might need rest
            default: return 12 // Potentially overtraining
            }
        }()
        score.trainingLoadScore = trainingScore
        score.trainingDetail = formatTrainingDetail()
        
        // Nutrition Component (0-25 points)
        let nutritionScore: Double = {
            let todayNutrition = fetchTodaysNutrition()
            let proteinProgress = min(todayNutrition.protein / dailyProteinTarget, 1.0)
            let calorieProgress = todayNutrition.calories / dailyCalorieTarget
            
            var points: Double = 0
            
            // Protein is crucial for muscle building
            points += proteinProgress * 15
            
            // Calories within range
            if calorieProgress >= 0.8 && calorieProgress <= 1.2 {
                points += 10
            } else if calorieProgress >= 0.6 && calorieProgress <= 1.4 {
                points += 6
            } else {
                points += 3
            }
            
            return min(points, 25)
        }()
        score.nutritionScore = nutritionScore
        score.nutritionDetail = formatNutritionDetail()
        
        // Calculate total
        score.totalScore = Int(sleepScore + recoveryScore + trainingScore + nutritionScore)
        score.recommendation = generateReadinessRecommendation(score: score)
        
        todayReadiness = score
    }
    
    // MARK: - Muscle Recovery Map
    private func updateMuscleRecoveryMap() {
        var recoveryMap: [MuscleGroup: MuscleRecoveryStatus] = [:]
        
        for muscle in MuscleGroup.allCases {
            let status = calculateMuscleRecovery(for: muscle)
            recoveryMap[muscle] = status
        }
        
        muscleRecoveryMap = recoveryMap
    }
    
    private func calculateMuscleRecovery(for muscle: MuscleGroup) -> MuscleRecoveryStatus {
        let daysSince = workoutService.daysSinceLastWorkout(for: muscle)
        let lastVolume = getLastVolumeForMuscle(muscle)
        
        guard let days = daysSince else {
            return MuscleRecoveryStatus(
                muscle: muscle,
                recoveryPercent: 100,
                daysSinceTraining: nil,
                lastVolume: 0,
                status: .ready,
                recommendation: "No recent training - ready for work!"
            )
        }
        
        // Recovery calculation based on volume and time
        let baseRecoveryPerDay: Double = {
            switch lastVolume {
            case 0..<5000: return 40 // Light session
            case 5000..<10000: return 30 // Moderate
            case 10000..<20000: return 25 // Heavy
            default: return 20 // Very heavy
            }
        }()
        
        let recoveryPercent = min(Double(days) * baseRecoveryPerDay, 100)
        
        let status: RecoveryLevel = {
            switch recoveryPercent {
            case 0..<40: return .recovering
            case 40..<70: return .partial
            case 70..<100: return .ready
            default: return .optimal
            }
        }()
        
        let recommendation: String = {
            switch status {
            case .recovering: return "Still recovering - consider rest or light work"
            case .partial: return "Partially recovered - moderate volume OK"
            case .ready: return "Ready for training"
            case .optimal: return "Fully recovered - great time to push!"
            }
        }()
        
        return MuscleRecoveryStatus(
            muscle: muscle,
            recoveryPercent: recoveryPercent,
            daysSinceTraining: days,
            lastVolume: lastVolume,
            status: status,
            recommendation: recommendation
        )
    }
    
    private func getLastVolumeForMuscle(_ muscle: MuscleGroup) -> Double {
        for workout in workoutService.workoutHistory {
            for exercise in workout.exercises {
                if exercise.exercise.primaryMuscles.contains(muscle) {
                    return exercise.totalVolume
                }
            }
        }
        return 0
    }
    
    // MARK: - Workout Recommendation
    private func generateRecommendedWorkout() {
        // Find most recovered muscle groups
        let sortedMuscles = muscleRecoveryMap.sorted { $0.value.recoveryPercent > $1.value.recoveryPercent }
        let readyMuscles = sortedMuscles.filter { $0.value.status == .ready || $0.value.status == .optimal }
        
        // Determine best split type
        let recommendedSplit: WorkoutSplitType = {
            let readyCategories = Set(readyMuscles.map { $0.key.category })
            
            if readyCategories.contains(.push) && muscleRecoveryMap[.chest]?.status == .optimal {
                return .push
            } else if readyCategories.contains(.pull) && muscleRecoveryMap[.back]?.status == .optimal {
                return .pull
            } else if readyCategories.contains(.legs) && muscleRecoveryMap[.quads]?.status == .optimal {
                return .legs
            } else if readyCategories.count >= 2 {
                return .fullBody
            } else if readyCategories.contains(.push) {
                return .push
            } else if readyCategories.contains(.pull) {
                return .pull
            } else {
                return .legs
            }
        }()
        
        // Adjust intensity based on readiness
        let intensityLevel: IntensityLevel = {
            switch todayReadiness.totalScore {
            case 80...100: return .high
            case 60..<80: return .moderate
            case 40..<60: return .light
            default: return .recovery
            }
        }()
        
        // Generate reasoning
        let reasoning: [String] = {
            var reasons: [String] = []
            
            if todayReadiness.sleepScore >= 20 {
                reasons.append("Great sleep recovery (\(String(format: "%.1f", todayReadiness.sleepScore))/25)")
            } else if todayReadiness.sleepScore < 15 {
                reasons.append("Sleep could be better - adjust intensity")
            }
            
            let readyMuscleNames = readyMuscles.prefix(3).map { $0.key.rawValue }
            if !readyMuscleNames.isEmpty {
                reasons.append("\(readyMuscleNames.joined(separator: ", ")) fully recovered")
            }
            
            if nutritionStatus.proteinProgress >= 0.8 {
                reasons.append("Protein intake on track for gains")
            } else {
                reasons.append("Consider more protein post-workout")
            }
            
            return reasons
        }()
        
        recommendedWorkout = WorkoutRecommendation(
            splitType: recommendedSplit,
            intensity: intensityLevel,
            estimatedDuration: intensityLevel == .high ? 75 : (intensityLevel == .moderate ? 60 : 45),
            targetMuscles: recommendedSplit.targetMuscles,
            reasoning: reasoning,
            template: workoutService.templates.first { $0.splitType == recommendedSplit }
        )
    }
    
    // MARK: - Smart Insights
    private func generateInsights() {
        var insights: [SmartInsight] = []
        
        // Recovery insight
        if todayReadiness.totalScore >= 85 {
            insights.append(SmartInsight(
                type: .positive,
                category: .recovery,
                title: "Peak Performance Day",
                message: "Your recovery metrics are excellent. This is a great day to push for PRs!",
                actionLabel: "Start Intense Workout",
                priority: 1
            ))
        } else if todayReadiness.totalScore < 50 {
            insights.append(SmartInsight(
                type: .warning,
                category: .recovery,
                title: "Recovery Needed",
                message: "Your body needs more rest. Consider a light session or active recovery.",
                actionLabel: "View Recovery Tips",
                priority: 1
            ))
        }
        
        // Muscle imbalance insight
        let pushVolume = weeklyVolumeFor(category: .push)
        let pullVolume = weeklyVolumeFor(category: .pull)
        if pushVolume > 0 && pullVolume > 0 {
            let ratio = pushVolume / pullVolume
            if ratio > 1.5 {
                insights.append(SmartInsight(
                    type: .warning,
                    category: .training,
                    title: "Push/Pull Imbalance",
                    message: "You've been doing \(Int(ratio))x more push than pull volume. Add more back work for balance.",
                    actionLabel: "Start Pull Workout",
                    priority: 2
                ))
            }
        }
        
        // Nutrition insights
        if nutritionStatus.proteinProgress < 0.5 && Calendar.current.component(.hour, from: Date()) > 14 {
            insights.append(SmartInsight(
                type: .warning,
                category: .nutrition,
                title: "Protein Behind Schedule",
                message: "You're at \(Int(nutritionStatus.proteinProgress * 100))% of your protein goal. Have a protein-rich meal soon!",
                actionLabel: "Log High-Protein Meal",
                priority: 1
            ))
        }
        
        // Streak insight
        let workoutsThisWeek = workoutService.totalWorkoutsThisWeek()
        if workoutsThisWeek >= 4 {
            insights.append(SmartInsight(
                type: .positive,
                category: .training,
                title: "Consistency Champion",
                message: "You've hit \(workoutsThisWeek) workouts this week! Keep up the amazing work.",
                actionLabel: nil,
                priority: 3
            ))
        }
        
        // Neglected muscle groups
        let neglectedMuscles = muscleRecoveryMap.filter { $0.value.daysSinceTraining ?? 0 > 7 }
        if !neglectedMuscles.isEmpty {
            let muscleNames = neglectedMuscles.prefix(2).map { $0.key.rawValue }.joined(separator: " and ")
            insights.append(SmartInsight(
                type: .info,
                category: .training,
                title: "Time for \(muscleNames)",
                message: "It's been over a week since you trained these muscles. Consider adding them to your next workout.",
                actionLabel: "Add to Workout",
                priority: 2
            ))
        }
        
        // Pre-workout nutrition
        if let nextWorkout = recommendedWorkout, nutritionStatus.todayCalories < 500 {
            insights.append(SmartInsight(
                type: .info,
                category: .nutrition,
                title: "Pre-Workout Fuel",
                message: "Have some carbs and protein 1-2 hours before your \(nextWorkout.splitType.rawValue) workout for better performance.",
                actionLabel: "Meal Suggestions",
                priority: 2
            ))
        }
        
        // Sort by priority
        currentInsights = insights.sorted { $0.priority < $1.priority }
    }
    
    private func weeklyVolumeFor(category: MuscleCategory) -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var volume: Double = 0
        
        for workout in workoutService.workoutHistory.filter({ $0.startTime >= weekAgo }) {
            for exercise in workout.exercises {
                if exercise.exercise.primaryCategory == category {
                    volume += exercise.totalVolume
                }
            }
        }
        
        return volume
    }
    
    // MARK: - Nutrition Status
    private func updateNutritionStatus() {
        let todayNutrition = fetchTodaysNutrition()
        
        nutritionStatus = NutritionStatus(
            todayCalories: todayNutrition.calories,
            todayProtein: todayNutrition.protein,
            todayCarbs: todayNutrition.carbs,
            todayFat: todayNutrition.fat,
            calorieTarget: dailyCalorieTarget,
            proteinTarget: dailyProteinTarget,
            calorieProgress: dailyCalorieTarget > 0 ? todayNutrition.calories / dailyCalorieTarget : 0,
            proteinProgress: dailyProteinTarget > 0 ? todayNutrition.protein / dailyProteinTarget : 0,
            isTrainingDay: hasWorkoutToday(),
            preWorkoutMealLogged: hasPreWorkoutMeal(),
            postWorkoutMealLogged: hasPostWorkoutMeal()
        )
    }
    
    private func fetchTodaysNutrition() -> (calories: Double, protein: Double, carbs: Double, fat: Double) {
        guard let context = healthContext else { return (0, 0, 0, 0) }
        
        let request: NSFetchRequest<NutritionLog> = NutritionLog.fetchRequest()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        request.predicate = NSPredicate(format: "date >= %@", startOfDay as NSDate)
        
        guard let logs = try? context.fetch(request) else { return (0, 0, 0, 0) }
        
        let calories = logs.reduce(0) { $0 + $1.calories }
        let protein = logs.reduce(0) { $0 + $1.protein }
        let carbs = logs.reduce(0) { $0 + $1.carbs }
        let fat = logs.reduce(0) { $0 + $1.fat }
        
        return (calories, protein, carbs, fat)
    }
    
    private func hasWorkoutToday() -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return workoutService.workoutHistory.contains { 
            $0.startTime >= startOfDay && $0.isCompleted
        }
    }
    
    private func hasPreWorkoutMeal() -> Bool {
        // Check if there's a meal logged 1-3 hours before any workout today
        guard let context = healthContext else { return false }
        
        let request: NSFetchRequest<NutritionLog> = NutritionLog.fetchRequest()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        request.predicate = NSPredicate(format: "date >= %@", startOfDay as NSDate)
        
        guard let logs = try? context.fetch(request), !logs.isEmpty else { return false }
        
        // For now, just check if they've eaten before afternoon
        let morningMeals = logs.filter { 
            Calendar.current.component(.hour, from: $0.date) < 12
        }
        return !morningMeals.isEmpty
    }
    
    private func hasPostWorkoutMeal() -> Bool {
        guard hasWorkoutToday(), let context = healthContext else { return false }
        
        let todaysWorkout = workoutService.workoutHistory.first {
            Calendar.current.isDateInToday($0.startTime) && $0.isCompleted
        }
        
        guard let workout = todaysWorkout else { return false }
        
        let request: NSFetchRequest<NutritionLog> = NutritionLog.fetchRequest()
        let cutoffDate = (workout.endTime ?? workout.startTime) as NSDate
        request.predicate = NSPredicate(format: "date >= %@", cutoffDate)
        
        guard let logs = try? context.fetch(request) else { return false }
        
        // Check if any meal with good protein was logged after workout
        return logs.contains { $0.protein >= 20 }
    }
    
    // MARK: - Weekly Analysis
    private func analyzeWeek() {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekWorkouts = workoutService.workoutHistory.filter { $0.startTime >= weekAgo }
        
        // Calculate volume by muscle category
        var volumeByCategory: [MuscleCategory: Double] = [:]
        for category in MuscleCategory.allCases {
            volumeByCategory[category] = weeklyVolumeFor(category: category)
        }
        
        // Find strengths and weaknesses
        let sorted = volumeByCategory.sorted { $0.value > $1.value }
        let strongest = sorted.first?.key
        let weakest = sorted.last?.key
        
        // Consistency score
        let uniqueDays = Set(weekWorkouts.map { Calendar.current.startOfDay(for: $0.startTime) }).count
        let consistencyScore = min(Double(uniqueDays) / 5.0, 1.0) * 100
        
        weeklyAnalysis = WeeklyAnalysis(
            totalWorkouts: weekWorkouts.count,
            totalVolume: weekWorkouts.reduce(0) { $0 + $1.totalVolume },
            totalDuration: weekWorkouts.reduce(0) { $0 + $1.duration },
            volumeByCategory: volumeByCategory,
            strongestCategory: strongest,
            weakestCategory: weakest,
            consistencyScore: consistencyScore,
            avgWorkoutDuration: weekWorkouts.isEmpty ? 0 : weekWorkouts.reduce(0) { $0 + $1.duration } / Double(weekWorkouts.count)
        )
    }
    
    // MARK: - Helper Formatters
    private func formatSleepDetail(hours: Double, quality: Int) -> String {
        "\(String(format: "%.1f", hours))h sleep, \(quality)/10 quality"
    }
    
    private func formatRecoveryDetail(hrv: Double, restingHR: Int) -> String {
        "HRV: \(Int(hrv))ms, Resting HR: \(restingHR)bpm"
    }
    
    private func formatTrainingDetail() -> String {
        let workoutsThisWeek = workoutService.totalWorkoutsThisWeek()
        return "\(workoutsThisWeek) workouts this week"
    }
    
    private func formatNutritionDetail() -> String {
        let proteinPercent = Int(nutritionStatus.proteinProgress * 100)
        return "\(proteinPercent)% of protein goal"
    }
    
    private func generateReadinessRecommendation(score: ReadinessScore) -> String {
        switch score.totalScore {
        case 85...100:
            return "You're at peak performance. Push hard today!"
        case 70..<85:
            return "Good readiness. Normal training is perfect."
        case 55..<70:
            return "Moderate readiness. Consider lighter intensity."
        case 40..<55:
            return "Recovery needed. Light workout or active rest."
        default:
            return "Take a rest day. Focus on sleep and nutrition."
        }
    }
    
    // MARK: - Workout Nutrition Recommendations
    func getPreWorkoutMealSuggestion() -> MealSuggestion {
        let workout = recommendedWorkout?.splitType ?? .push
        let intensity = recommendedWorkout?.intensity ?? .moderate
        
        let carbsNeeded: String = {
            switch intensity {
            case .high: return "60-80g carbs"
            case .moderate: return "40-60g carbs"
            case .light, .recovery: return "20-40g carbs"
            }
        }()
        
        return MealSuggestion(
            title: "Pre-Workout Meal",
            timing: "1-2 hours before \(workout.rawValue)",
            macros: "\(carbsNeeded), 20-30g protein, low fat",
            examples: [
                "Oatmeal with banana and protein powder",
                "Rice cakes with peanut butter and honey",
                "Greek yogurt with berries and granola",
                "Chicken breast with rice"
            ],
            reason: "Carbs fuel your workout, protein starts muscle protein synthesis"
        )
    }
    
    func getPostWorkoutMealSuggestion() -> MealSuggestion {
        let workout = recommendedWorkout?.splitType ?? .push
        let volumeDone = workoutService.currentSession?.totalVolume ?? 0
        
        let proteinNeeded: String = {
            if volumeDone > 15000 { return "40-50g protein" }
            else if volumeDone > 8000 { return "30-40g protein" }
            else { return "25-30g protein" }
        }()
        
        return MealSuggestion(
            title: "Post-Workout Meal",
            timing: "Within 2 hours after training",
            macros: "\(proteinNeeded), 40-60g carbs, moderate fat OK",
            examples: [
                "Protein shake with banana",
                "Grilled chicken with sweet potato",
                "Salmon with rice and vegetables",
                "Eggs with toast and avocado"
            ],
            reason: "Fast protein + carbs maximize muscle recovery and glycogen replenishment"
        )
    }
    
    // MARK: - AI Context Builder
    func buildAIContext() -> String {
        """
        USER FITNESS PROFILE:
        
        Goal: \(fitnessGoal.rawValue)
        Daily Targets: \(Int(dailyCalorieTarget)) kcal, \(Int(dailyProteinTarget))g protein
        
        TODAY'S READINESS: \(todayReadiness.totalScore)/100
        - Sleep: \(todayReadiness.sleepDetail)
        - Recovery: \(todayReadiness.recoveryDetail)
        - Training Load: \(todayReadiness.trainingDetail)
        - Nutrition: \(todayReadiness.nutritionDetail)
        
        MUSCLE RECOVERY STATUS:
        \(muscleRecoveryMap.map { "- \($0.key.rawValue): \(Int($0.value.recoveryPercent))% (\($0.value.status.rawValue))" }.joined(separator: "\n"))
        
        WEEKLY STATS:
        - Workouts: \(weeklyAnalysis?.totalWorkouts ?? 0)
        - Total Volume: \(Int(weeklyAnalysis?.totalVolume ?? 0)) kg
        - Consistency: \(Int(weeklyAnalysis?.consistencyScore ?? 0))%
        
        TODAY'S NUTRITION:
        - Calories: \(Int(nutritionStatus.todayCalories))/\(Int(dailyCalorieTarget)) kcal
        - Protein: \(Int(nutritionStatus.todayProtein))/\(Int(dailyProteinTarget))g
        - Training Day: \(nutritionStatus.isTrainingDay ? "Yes" : "No")
        
        RECENT WORKOUTS:
        \(workoutService.workoutHistory.prefix(5).map { "- \($0.name): \(Int($0.totalVolume))kg volume, \($0.formattedDuration)" }.joined(separator: "\n"))
        
        PERSONAL RECORDS:
        \(workoutService.personalRecords.prefix(5).map { "- \($0.exerciseName): \($0.value)kg" }.joined(separator: "\n"))
        """
    }
}

// MARK: - Supporting Data Models

struct ReadinessScore {
    var totalScore: Int = 0
    var sleepScore: Double = 0
    var recoveryScore: Double = 0
    var trainingLoadScore: Double = 0
    var nutritionScore: Double = 0
    
    var sleepDetail: String = "No data"
    var recoveryDetail: String = "No data"
    var trainingDetail: String = "No data"
    var nutritionDetail: String = "No data"
    var recommendation: String = "Start tracking to get personalized recommendations"
    
    var color: Color {
        switch totalScore {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
    
    var emoji: String {
        switch totalScore {
        case 85...100: return "🔥"
        case 70..<85: return "💪"
        case 55..<70: return "👍"
        case 40..<55: return "😴"
        default: return "🛌"
        }
    }
}

struct MuscleRecoveryStatus {
    let muscle: MuscleGroup
    let recoveryPercent: Double
    let daysSinceTraining: Int?
    let lastVolume: Double
    let status: RecoveryLevel
    let recommendation: String
}

enum RecoveryLevel: String {
    case recovering = "Recovering"
    case partial = "Partial"
    case ready = "Ready"
    case optimal = "Optimal"
    
    var color: Color {
        switch self {
        case .recovering: return .red
        case .partial: return .orange
        case .ready: return .green
        case .optimal: return .mint
        }
    }
}

struct WorkoutRecommendation {
    let splitType: WorkoutSplitType
    let intensity: IntensityLevel
    let estimatedDuration: Int // minutes
    let targetMuscles: [MuscleGroup]
    let reasoning: [String]
    let template: WorkoutTemplate?
}

enum IntensityLevel: String {
    case high = "High Intensity"
    case moderate = "Moderate"
    case light = "Light"
    case recovery = "Active Recovery"
    
    var color: Color {
        switch self {
        case .high: return .red
        case .moderate: return .orange
        case .light: return .green
        case .recovery: return .blue
        }
    }
}

struct SmartInsight: Identifiable {
    let id = UUID()
    let type: InsightType
    let category: InsightCategory
    let title: String
    let message: String
    let actionLabel: String?
    let priority: Int
    
    enum InsightType {
        case positive, warning, info
        
        var color: Color {
            switch self {
            case .positive: return .green
            case .warning: return .orange
            case .info: return .blue
            }
        }
        
        var icon: String {
            switch self {
            case .positive: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    enum InsightCategory {
        case recovery, training, nutrition, progress
    }
}

struct NutritionStatus {
    var todayCalories: Double = 0
    var todayProtein: Double = 0
    var todayCarbs: Double = 0
    var todayFat: Double = 0
    var calorieTarget: Double = 0
    var proteinTarget: Double = 0
    var calorieProgress: Double = 0
    var proteinProgress: Double = 0
    var isTrainingDay: Bool = false
    var preWorkoutMealLogged: Bool = false
    var postWorkoutMealLogged: Bool = false
}

struct WeeklyAnalysis {
    let totalWorkouts: Int
    let totalVolume: Double
    let totalDuration: TimeInterval
    let volumeByCategory: [MuscleCategory: Double]
    let strongestCategory: MuscleCategory?
    let weakestCategory: MuscleCategory?
    let consistencyScore: Double
    let avgWorkoutDuration: TimeInterval
    
    var formattedTotalVolume: String {
        if totalVolume >= 1000 {
            return String(format: "%.1fk kg", totalVolume / 1000)
        }
        return "\(Int(totalVolume)) kg"
    }
}

struct MealSuggestion {
    let title: String
    let timing: String
    let macros: String
    let examples: [String]
    let reason: String
}

enum FitnessGoal: String, CaseIterable, Codable {
    case buildMuscle = "Build Muscle"
    case loseFat = "Lose Fat"
    case recomposition = "Body Recomposition"
    case strength = "Build Strength"
    case endurance = "Improve Endurance"
    case maintenance = "Maintain"
    
    var calorieAdjustment: Double {
        switch self {
        case .buildMuscle: return 1.15 // +15% surplus
        case .loseFat: return 0.80 // -20% deficit
        case .recomposition: return 1.0 // maintenance
        case .strength: return 1.10 // +10%
        case .endurance: return 1.05 // +5%
        case .maintenance: return 1.0
        }
    }
    
    var proteinMultiplier: Double {
        switch self {
        case .buildMuscle: return 2.0 // 2g per kg
        case .loseFat: return 2.2 // Higher to preserve muscle
        case .recomposition: return 2.0
        case .strength: return 1.8
        case .endurance: return 1.6
        case .maintenance: return 1.6
        }
    }
}

