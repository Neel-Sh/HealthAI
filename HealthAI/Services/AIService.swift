import Foundation
import CoreData
import UIKit

class AIService: ObservableObject {
    private let viewContext: NSManagedObjectContext
    private let openAIAPIKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    @Published var isLoading = false
    @Published var lastResponse: String?
    @Published var errorMessage: String?
    
    init(context: NSManagedObjectContext, apiKey: String? = nil) {
        self.viewContext = context
        
        // Try to get API key from multiple sources
        if let providedKey = apiKey, !providedKey.isEmpty {
            self.openAIAPIKey = providedKey
        } else if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            self.openAIAPIKey = envKey
        } else if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, !bundleKey.isEmpty {
            self.openAIAPIKey = bundleKey
        } else {
            self.openAIAPIKey = ""
            print("⚠️ OpenAI API key not found. Please set it in Info.plist or environment variable.")
        }
    }
    
    // MARK: - Recovery Tips
    func getRecoveryTips(for workout: WorkoutLog) async -> String? {
        let prompt = """
        Based on this workout, provide 3-4 concise recovery tips:
        
        Workout: \(workout.workoutType) | Distance: \(workout.distance)km | Duration: \(workout.formattedDuration)
        Avg HR: \(workout.avgHeartRate)bpm | Effort: \(workout.perceivedExertion)/10
        
        Provide specific, actionable recovery advice focusing on:
        • Immediate post-workout (next 2 hours)
        • Nutrition and hydration
        • Sleep optimization
        • When to train next
        
        Keep response under 100 words, use bullet points.
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a recovery specialist. Provide concise, practical recovery advice. Use bullet points and keep responses under 100 words.")
    }
    
    // MARK: - Running Insights
    func generateRunningInsights(runs: [WorkoutLog]) async -> String? {
        let totalDistance = runs.reduce(0) { $0 + $1.distance }
        let totalTime = runs.reduce(0) { $0 + $1.duration }
        let averagePace = totalDistance > 0 ? totalTime / totalDistance : 0
        let totalRuns = runs.count
        
        let recentRuns = runs.prefix(3).map { run in
            "\(run.timestamp.formatted(date: .abbreviated, time: .omitted)): \(String(format: "%.1f", run.distance))km, \(formatDuration(run.duration)), \(formatPace(run.pace))"
        }.joined(separator: "\n")
        
        let prompt = """
        Analyze my running performance and provide concise insights:
        
        📊 Summary: \(totalRuns) runs | \(String(format: "%.1f", totalDistance))km total | Avg pace: \(formatPace(averagePace))
        
        🏃‍♂️ Recent Runs:
        \(recentRuns)
        
        Provide:
        • Key performance trends
        • 2-3 specific training recommendations
        • One goal for next week
        • One injury prevention tip
        
        Keep response under 120 words, use bullet points.
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a running coach. Provide concise, actionable running insights. Use bullet points and keep responses under 120 words.")
    }

    // MARK: - Running Coach (Data-Aware)
    struct RunningMobilitySnapshot {
        let strideLengthMeters: Double?
        let cadenceSpm: Double?
        let groundContactMs: Double?
        let verticalOscillationCm: Double?
        let powerWatts: Double?
        let speedMps: Double?
    }

    /// Create a highly personalized running coach response that references concrete user data
    func getRunningCoachResponse(
        message: String,
        runs: [WorkoutLog],
        healthMetrics: [HealthMetrics],
        mobility: RunningMobilitySnapshot,
        history: [ChatMessage] = []
    ) async -> String? {
        // Build recent runs summary
        let totalDistance = runs.reduce(0) { $0 + $1.distance }
        let totalDuration = runs.reduce(0) { $0 + $1.duration }
        let averagePace = totalDistance > 0 ? totalDuration / totalDistance : 0
        let longest = runs.map { $0.distance }.max() ?? 0
        let bestPace = runs.map { $0.pace }.min() ?? 0

        let recentRuns = runs.prefix(6).map { run in
            "- \(run.timestamp.formatted(date: .abbreviated, time: .omitted)): \(String(format: "%.1f", run.distance)) km, Pace: \(run.formattedPace), HR: \(run.avgHeartRate > 0 ? "\\(run.avgHeartRate)bpm" : "n/a")"
        }.joined(separator: "\n")

        // Health context (today)
        let recentHealth = healthMetrics.first
        let todaySummary: String = {
            guard let h = recentHealth else { return "No health metrics available today." }
            var s = "Steps: \(h.stepCount), Active Calories: \(Int(h.activeCalories)) kcal, Sleep: \(String(format: "%.1f", h.sleepHours)) h, HRV: \(String(format: "%.1f", h.hrv)) ms, VO2 Max: \(String(format: "%.1f", h.vo2Max)) ml/kg/min"
            if h.restingHeartRate > 0 { s += ", Resting HR: \(h.restingHeartRate) bpm" }
            return s
        }()

        // Mobility snapshot
        func fmt(_ v: Double?, suffix: String, digits: Int = 0) -> String {
            guard let v = v, v > 0 else { return "n/a" }
            return digits == 0 ? String(format: "%.0f %@", v, suffix) : String(format: "%.1f %@", v, suffix)
        }
        let mobilitySummary = "Stride: \(fmt(mobility.strideLengthMeters.map { $0*100 }, suffix: "cm")) | Cadence: \(fmt(mobility.cadenceSpm, suffix: "spm")) | Ground Contact: \(fmt(mobility.groundContactMs, suffix: "ms")) | Vert. Osc.: \(fmt(mobility.verticalOscillationCm, suffix: "cm", digits: 1)) | Power: \(fmt(mobility.powerWatts, suffix: "W")) | Speed: \(fmt(mobility.speedMps, suffix: "m/s"))"

        // Conversation history (brief)
        let lastTurns = history.suffix(4).map { msg in
            (msg.isUser ? "User" : "Coach") + ": " + msg.content
        }.joined(separator: "\n")

        // Determine intent (very simple heuristic)
        let lower = message.lowercased()
        let intent: String = {
            if lower.contains("form") || lower.contains("stride") || lower.contains("cadence") { return "form" }
            if lower.contains("pace") || lower.contains("speed") { return "pace" }
            if lower.contains("race") { return "race" }
            if lower.contains("recover") || lower.contains("rest") { return "recovery" }
            if lower.contains("plan") || lower.contains("week") || lower.contains("schedule") { return "plan" }
            return "general"
        }()

        let prompt = """
        You are my AI Running Coach. Use ONLY the user's real data below to answer the question.

        Coaching Intent: \(intent)
        User Question: \(message)

        DATA YOU MUST USE:
        • Today: \(todaySummary)
        • Weekly Summary: \(String(format: "%.1f", totalDistance)) km in \(formatDuration(totalDuration)), longest \(String(format: "%.1f", longest)) km, avg pace \(formatPace(averagePace))
        • Recent Runs (last \(min(6, runs.count))):
        \(recentRuns)
        • Running Form Snapshot: \(mobilitySummary)

        Conversation Context (last turns):
        \(lastTurns)

        Answer Requirements:
        - Be specific to THESE numbers; quote actual values (pace, cadence, stride, HR, etc.).
        - If form intent, analyze stride length, cadence, ground contact, vertical oscillation. Provide 2-3 tailored form cues.
        - If pace intent, discuss realistic targets based on recent paces; give split suggestions.
        - If plan intent, give a 1-week plan with 3-4 sessions aligned to current fitness.
        - If race intent, give pacing and strategy with km-by-km guidance.
        - If recovery intent, give concrete tips tied to HRV/sleep/resting HR and workload.
        - Avoid repeating the same generic tips; vary based on the data.
        - Keep to ~120 words using bullet points where helpful.
        """

        return await sendChatRequest(
            prompt: prompt,
            systemMessage: "You are a data-driven running coach. You must reference the exact user data provided (mobility metrics, runs, and health) and tailor advice precisely. Avoid generic repetition."
        )
    }
    
    // MARK: - Health Insights Chat
    func getHealthInsights(message: String, healthMetrics: [HealthMetrics], workouts: [WorkoutLog], nutritionLogs: [NutritionLog], heartRateReadings: [HeartRateReading]) async -> String? {
        // Get the most recent data (last 30 days for comprehensive analysis)
        let recentHealthMetrics = Array(healthMetrics.prefix(30))
        let recentWorkouts = Array(workouts.prefix(20))
        let recentNutritionLogs = Array(nutritionLogs.prefix(100)) // More nutrition data for detailed analysis
        let recentHeartRateReadings = Array(heartRateReadings.prefix(200))
        
        let healthSummary = generateComprehensiveHealthSummary(
            healthMetrics: recentHealthMetrics, 
            workouts: recentWorkouts, 
            nutritionLogs: recentNutritionLogs, 
            heartRateReadings: recentHeartRateReadings
        )
        
        let prompt = """
        User Question: \(message)
        
        You are my personal AI health coach with complete access to my health data. Based on the comprehensive data below, provide a personalized response:
        
        \(healthSummary)
        
        Response Guidelines:
        - Be personal and specific to MY data patterns
        - Reference specific meals, workouts, or health metrics when relevant
        - Provide actionable recommendations based on my current trends
        - Keep response under 200 words but be thorough
        - Use bullet points for clarity
        - Be encouraging but honest about areas for improvement
        - Connect different health aspects (nutrition, sleep, exercise, recovery)
        - Address the user's specific question while providing broader context
        
        Format your response with:
        1. Personal acknowledgment of my current situation
        2. Specific insights from my data patterns
        3. Tailored recommendations for improvement
        4. Motivation based on my progress
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a comprehensive personal health coach with deep knowledge of nutrition, exercise physiology, sleep science, and wellness. You have complete access to the user's health data including detailed nutrition logs with specific meals (breakfast, lunch, dinner, snacks), workout history, sleep patterns, heart rate data, and all health metrics. Provide personalized, data-driven advice that connects all aspects of their health. Be encouraging, specific, and actionable. Always reference specific data points when relevant.")
    }
    
    // MARK: - Nutrition-Specific Insights
    func getNutritionInsights(message: String, nutritionLogs: [NutritionLog], healthMetrics: [HealthMetrics]) async -> String? {
        let recentNutritionLogs = Array(nutritionLogs.prefix(50))
        let recentHealthMetrics = Array(healthMetrics.prefix(7))
        
        let nutritionSummary = generateDetailedNutritionSummary(nutritionLogs: recentNutritionLogs, healthMetrics: recentHealthMetrics)
        
        let prompt = """
        User Question: \(message)
        
        You are my personal nutrition coach with complete access to my detailed nutrition data. Based on the comprehensive nutrition analysis below, provide a personalized response:
        
        \(nutritionSummary)
        
        Response Guidelines:
        - Be specific about my eating patterns and meal choices
        - Reference specific foods I've eaten and meal timing
        - Provide actionable nutrition recommendations
        - Keep response under 150 words
        - Use bullet points for clarity
        - Connect nutrition to my health goals and metrics
        - Be encouraging but honest about areas for improvement
        
        Format your response with:
        1. Assessment of my current nutrition patterns
        2. Specific insights from my meal data
        3. Tailored nutrition recommendations
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a registered dietitian and nutrition coach with complete access to the user's detailed nutrition logs including specific meals, timing, macronutrients, and eating patterns. Provide personalized, evidence-based nutrition advice that references their actual food choices and eating habits.")
    }
    
    private func generateComprehensiveHealthSummary(healthMetrics: [HealthMetrics], workouts: [WorkoutLog], nutritionLogs: [NutritionLog], heartRateReadings: [HeartRateReading]) -> String {
        var summary = "COMPREHENSIVE HEALTH PROFILE:\n\n"
        
        // Current Health Status
        if let recent = healthMetrics.first {
            summary += "📊 Current Health Status:\n"
            summary += "• Steps: \(recent.stepCount) | Active Calories: \(Int(recent.activeCalories)) | Distance: \(String(format: "%.1f", recent.totalDistance))km\n"
            summary += "• Active Minutes: \(recent.activeMinutes) min | Workouts: \(recent.workoutCount)\n"
            summary += "• Sleep: \(formatSleepTime(recent.sleepHours)) (Quality: \(recent.sleepQuality)/10)\n"
            if recent.deepSleepHours > 0 || recent.remSleepHours > 0 {
                summary += "• Deep Sleep: \(formatSleepTime(recent.deepSleepHours)) | REM: \(formatSleepTime(recent.remSleepHours))\n"
                if recent.timeInBed > 0 {
                    let efficiency = (recent.sleepHours / recent.timeInBed) * 100
                    summary += "• Sleep Efficiency: \(String(format: "%.1f", efficiency))%\n"
                }
            }
            summary += "• Heart Rate: \(recent.restingHeartRate) bpm (resting) | HRV: \(String(format: "%.1f", recent.hrv)) ms\n"
            summary += "• VO2 Max: \(String(format: "%.1f", recent.vo2Max)) ml/kg/min\n"
            
            if recent.bloodOxygen > 0 {
                summary += "• Blood O2: \(String(format: "%.0f", recent.bloodOxygen))%"
                if recent.respiratoryRate > 0 {
                    summary += " | Respiratory Rate: \(String(format: "%.0f", recent.respiratoryRate)) bpm"
                }
                summary += "\n"
            }
            
            if recent.recoveryScore > 0 {
                summary += "• Recovery Score: \(String(format: "%.0f", recent.recoveryScore))/100\n"
            }
            if recent.readinessScore > 0 {
                summary += "• Readiness Score: \(String(format: "%.0f", recent.readinessScore))/100\n"
            }
            if recent.bodyWeight > 0 {
                summary += "• Weight: \(String(format: "%.1f", recent.bodyWeight)) kg"
                if recent.bodyFatPercentage > 0 {
                    summary += " | Body Fat: \(String(format: "%.1f", recent.bodyFatPercentage))%"
                }
                summary += "\n"
            }
            if recent.stressLevel > 0 {
                summary += "• Stress Level: \(recent.stressLevel)/10 | Energy Level: \(recent.energyLevel)/10\n"
            }
            summary += "\n"
        }
        
        // Heart Rate Patterns
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todaysHR = heartRateReadings.filter { $0.timestamp >= todayStart }
        
        if !todaysHR.isEmpty {
            let avgHR = todaysHR.reduce(0) { result, reading in result + Int(reading.heartRate) } / todaysHR.count
            let maxHR = todaysHR.map { reading in Int(reading.heartRate) }.max() ?? 0
            let minHR = todaysHR.map { reading in Int(reading.heartRate) }.min() ?? 0
            
            summary += "❤️ Today's Heart Rate Pattern:\n"
            summary += "• Range: \(minHR)-\(maxHR) bpm | Average: \(avgHR) bpm\n"
            summary += "• Readings: \(todaysHR.count) samples throughout the day\n\n"
        }
        
        // Comprehensive Nutrition Analysis
        let todaysNutrition = nutritionLogs.filter { Calendar.current.isDate($0.date, inSameDayAs: Date()) }
        let last7DaysNutrition = nutritionLogs.filter { 
            Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.contains($0.date) ?? false 
        }
        
        summary += "🍎 DETAILED NUTRITION ANALYSIS:\n"
        
        if !todaysNutrition.isEmpty {
            let todayCalories = todaysNutrition.reduce(0.0) { $0 + $1.calories }
            let todayProtein = todaysNutrition.reduce(0.0) { $0 + $1.protein }
            let todayCarbs = todaysNutrition.reduce(0.0) { $0 + $1.carbs }
            let todayFat = todaysNutrition.reduce(0.0) { $0 + $1.fat }
            let todayFiber = todaysNutrition.reduce(0.0) { $0 + $1.fiber }
            let todayWater = todaysNutrition.reduce(0.0) { $0 + $1.waterIntake }
            
            summary += "• Today's Intake: \(Int(todayCalories)) cal | P: \(String(format: "%.1f", todayProtein))g | C: \(String(format: "%.1f", todayCarbs))g | F: \(String(format: "%.1f", todayFat))g\n"
            summary += "• Fiber: \(String(format: "%.1f", todayFiber))g | Water: \(String(format: "%.1f", todayWater/1000))L\n"
            
            // Meal breakdown
            let mealTypes = ["breakfast", "lunch", "dinner", "snack"]
            for mealType in mealTypes {
                let meals = todaysNutrition.filter { $0.mealType == mealType }
                if !meals.isEmpty {
                    let mealCalories = meals.reduce(0.0) { $0 + $1.calories }
                    let mealFoods = meals.map { $0.foodName }.joined(separator: ", ")
                    summary += "• \(mealType.capitalized): \(Int(mealCalories)) cal - \(mealFoods)\n"
                }
            }
            summary += "\n"
        }
        
        if !last7DaysNutrition.isEmpty {
            let avgCalories = last7DaysNutrition.reduce(0.0) { $0 + $1.calories } / 7.0
            let avgProtein = last7DaysNutrition.reduce(0.0) { $0 + $1.protein } / 7.0
            let avgCarbs = last7DaysNutrition.reduce(0.0) { $0 + $1.carbs } / 7.0
            let avgFat = last7DaysNutrition.reduce(0.0) { $0 + $1.fat } / 7.0
            
            summary += "• Weekly Averages: \(Int(avgCalories)) cal/day | P: \(String(format: "%.1f", avgProtein))g | C: \(String(format: "%.1f", avgCarbs))g | F: \(String(format: "%.1f", avgFat))g\n"
            
            // Macro percentages
            let totalMacros = avgProtein + avgCarbs + avgFat
            if totalMacros > 0 {
                let proteinPercent = Int((avgProtein / totalMacros) * 100)
                let carbPercent = Int((avgCarbs / totalMacros) * 100)
                let fatPercent = Int((avgFat / totalMacros) * 100)
                summary += "• Macro Split: P: \(proteinPercent)% | C: \(carbPercent)% | F: \(fatPercent)%\n"
            }
            summary += "\n"
        }
        
        // Recent Workouts with detailed analysis
        let recentWorkouts = workouts.prefix(5)
        if !recentWorkouts.isEmpty {
            summary += "🏃‍♂️ RECENT WORKOUT ANALYSIS:\n"
            for workout in recentWorkouts {
                summary += "• \(workout.workoutType.capitalized): \(String(format: "%.1f", workout.distance))km, \(formatDuration(workout.duration))"
                if workout.avgHeartRate > 0 {
                    summary += ", Avg HR: \(workout.avgHeartRate)bpm"
                }
                if workout.maxHeartRate > 0 {
                    summary += ", Max HR: \(workout.maxHeartRate)bpm"
                }
                if workout.perceivedExertion > 0 {
                    summary += ", Effort: \(workout.perceivedExertion)/10"
                }
                if workout.calories > 0 {
                    summary += ", \(Int(workout.calories)) cal"
                }
                summary += " (\(workout.timestamp.formatted(date: .abbreviated, time: .omitted)))\n"
            }
            summary += "\n"
        }
        
        // Weekly Trends
        let weeklyMetrics = healthMetrics.filter { 
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear)
        }
        
        if weeklyMetrics.count > 1 {
            let avgSteps = weeklyMetrics.reduce(0) { $0 + $1.stepCount } / Int32(weeklyMetrics.count)
            let avgCalories = weeklyMetrics.reduce(0.0) { $0 + $1.activeCalories } / Double(weeklyMetrics.count)
            let avgSleep = weeklyMetrics.reduce(0.0) { $0 + $1.sleepHours } / Double(weeklyMetrics.count)
            let avgHRV = weeklyMetrics.reduce(0.0) { $0 + $1.hrv } / Double(weeklyMetrics.count)
            let avgSleepQuality = weeklyMetrics.reduce(0) { $0 + $1.sleepQuality } / Int16(weeklyMetrics.count)
            
            summary += "📈 WEEKLY TRENDS:\n"
            summary += "• Daily Averages: \(avgSteps) steps | \(Int(avgCalories)) active calories\n"
            summary += "• Sleep: \(formatSleepTime(avgSleep))/night (Quality: \(avgSleepQuality)/10)\n"
            summary += "• HRV: \(String(format: "%.1f", avgHRV)) ms\n\n"
        }
        
        return summary
    }
    
    private func generateDetailedNutritionSummary(nutritionLogs: [NutritionLog], healthMetrics: [HealthMetrics]) -> String {
        var summary = "DETAILED NUTRITION ANALYSIS:\n\n"
        
        // Today's nutrition
        let todaysNutrition = nutritionLogs.filter { Calendar.current.isDate($0.date, inSameDayAs: Date()) }
        
        if !todaysNutrition.isEmpty {
            summary += "📊 TODAY'S NUTRITION:\n"
            let todayCalories = todaysNutrition.reduce(0.0) { $0 + $1.calories }
            let todayProtein = todaysNutrition.reduce(0.0) { $0 + $1.protein }
            let todayCarbs = todaysNutrition.reduce(0.0) { $0 + $1.carbs }
            let todayFat = todaysNutrition.reduce(0.0) { $0 + $1.fat }
            let todayFiber = todaysNutrition.reduce(0.0) { $0 + $1.fiber }
            let todayWater = todaysNutrition.reduce(0.0) { $0 + $1.waterIntake }
            
            summary += "• Total: \(Int(todayCalories)) cal | P: \(String(format: "%.1f", todayProtein))g | C: \(String(format: "%.1f", todayCarbs))g | F: \(String(format: "%.1f", todayFat))g\n"
            summary += "• Fiber: \(String(format: "%.1f", todayFiber))g | Water: \(String(format: "%.1f", todayWater/1000))L\n\n"
            
            // Detailed meal breakdown
            let mealTypes = ["breakfast", "lunch", "dinner", "snack"]
            for mealType in mealTypes {
                let meals = todaysNutrition.filter { $0.mealType == mealType }
                if !meals.isEmpty {
                    summary += "• \(mealType.capitalized):\n"
                    for meal in meals {
                        let timeString = meal.date.formatted(date: .omitted, time: .shortened)
                        summary += "  - \(meal.foodName) (\(timeString)): \(Int(meal.calories)) cal, P: \(String(format: "%.1f", meal.protein))g, C: \(String(format: "%.1f", meal.carbs))g, F: \(String(format: "%.1f", meal.fat))g\n"
                    }
                }
            }
            summary += "\n"
        }
        
        // Weekly nutrition patterns
        let last7DaysNutrition = nutritionLogs.filter { 
            Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.contains($0.date) ?? false 
        }
        
        if !last7DaysNutrition.isEmpty {
            summary += "📈 WEEKLY NUTRITION PATTERNS:\n"
            let avgCalories = last7DaysNutrition.reduce(0.0) { $0 + $1.calories } / 7.0
            let avgProtein = last7DaysNutrition.reduce(0.0) { $0 + $1.protein } / 7.0
            let avgCarbs = last7DaysNutrition.reduce(0.0) { $0 + $1.carbs } / 7.0
            let avgFat = last7DaysNutrition.reduce(0.0) { $0 + $1.fat } / 7.0
            
            summary += "• Daily Averages: \(Int(avgCalories)) cal | P: \(String(format: "%.1f", avgProtein))g | C: \(String(format: "%.1f", avgCarbs))g | F: \(String(format: "%.1f", avgFat))g\n"
            
            // Macro percentages
            let totalMacros = avgProtein + avgCarbs + avgFat
            if totalMacros > 0 {
                let proteinPercent = Int((avgProtein / totalMacros) * 100)
                let carbPercent = Int((avgCarbs / totalMacros) * 100)
                let fatPercent = Int((avgFat / totalMacros) * 100)
                summary += "• Macro Distribution: Protein \(proteinPercent)% | Carbs \(carbPercent)% | Fat \(fatPercent)%\n"
            }
            
            // Meal frequency analysis
            let breakfastMeals = last7DaysNutrition.filter { $0.mealType == "breakfast" }.count
            let lunchMeals = last7DaysNutrition.filter { $0.mealType == "lunch" }.count
            let dinnerMeals = last7DaysNutrition.filter { $0.mealType == "dinner" }.count
            let snackMeals = last7DaysNutrition.filter { $0.mealType == "snack" }.count
            
            summary += "• Meal Frequency: Breakfast \(breakfastMeals)/7 | Lunch \(lunchMeals)/7 | Dinner \(dinnerMeals)/7 | Snacks \(snackMeals)/7\n"
            
            // Most common foods
            let foodFrequency = Dictionary(grouping: last7DaysNutrition, by: { $0.foodName })
            let topFoods = foodFrequency.sorted { $0.value.count > $1.value.count }.prefix(5)
            if !topFoods.isEmpty {
                summary += "• Most Frequent Foods: "
                summary += topFoods.map { "\($0.key) (\($0.value.count)x)" }.joined(separator: ", ")
                summary += "\n"
            }
            summary += "\n"
        }
        
        // Health correlation
        if let recentHealth = healthMetrics.first {
            summary += "🔗 HEALTH CORRELATION:\n"
            summary += "• Current Weight: \(String(format: "%.1f", recentHealth.bodyWeight))kg\n"
            summary += "• Energy Level: \(recentHealth.energyLevel)/10\n"
            summary += "• Sleep Quality: \(recentHealth.sleepQuality)/10\n"
            summary += "• Active Calories: \(Int(recentHealth.activeCalories))\n\n"
        }
        
        return summary
    }
    
    // Helper function to format sleep time
    private func formatSleepTime(_ totalHours: Double) -> String {
        guard totalHours > 0 else { return "0h" }
        
        let hours = Int(totalHours)
        let minutes = Int((totalHours - Double(hours)) * 60)
        
        if hours == 0 {
            return "\(minutes)m"
        } else if minutes == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }
    
    // MARK: - Helper Methods
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatPace(_ pace: Double) -> String {
        if pace == 0 { return "0:00" }
        let minutes = Int(pace / 60)
        let seconds = Int(pace.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Training Plan Generation (Simplified for health companion app)
    func generateGeneralTrainingPlan(workoutType: String, fitnessLevel: String) async -> String? {
        let prompt = """
        Generate a concise weekly training plan for:
        
        Workout Type: \(workoutType) | Fitness Level: \(fitnessLevel)
        
        Provide:
        • Weekly structure (3-4 workouts)
        • Specific workout types and intensities
        • Progression strategy
        • Recovery recommendations
        
        Keep response under 150 words, use bullet points.
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a fitness coach. Provide concise, practical training plans. Use bullet points and keep responses under 150 words.")
    }
    
    // MARK: - Nutrition Advice
    func getNutritionAdvice(targetCalories: Double, targetProtein: Double, workoutType: String, intensity: String) async -> String? {
        let prompt = """
        Provide personalized nutrition advice for:
        
        Target Calories: \(targetCalories) kcal
        Target Protein: \(targetProtein) g
        Today's Workout: \(workoutType)
        Intensity: \(intensity)
        
        Please provide:
        - Pre-workout meal suggestions (timing and foods)
        - Post-workout recovery nutrition
        - Daily meal timing recommendations
        - Hydration strategy
        - Specific food recommendations with portions
        
        Consider both performance and recovery needs.
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a certified sports nutritionist specializing in endurance athletics.")
    }
    
    // MARK: - Workout Analysis (Simplified for health companion app)
    func analyzeWorkoutProgress(recentWorkouts: [WorkoutLog]) async -> String? {
        let workoutSummary = recentWorkouts.map { workout in
            "\(workout.workoutType): \(workout.distance)km in \(workout.duration/60) minutes"
        }.joined(separator: "\n")
        
        let prompt = """
        Analyze the following workout progress and provide recommendations:
        
        Recent Workouts (last 7 days):
        \(workoutSummary)
        
        Please analyze:
        - Overall performance trends
        - Training consistency
        - Areas for improvement
        - Recovery recommendations
        
        Provide actionable insights and suggestions.
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a fitness coach who analyzes performance trends.")
    }
    
    // MARK: - Predictive Analytics
    func predictPersonalRecord(for workoutType: String, recentWorkouts: [WorkoutLog]) async -> PRPrediction? {
        let workoutData = recentWorkouts.filter { $0.workoutType == workoutType }
            .prefix(10)
            .map { workout in
                "Date: \(workout.timestamp.formatted(date: .abbreviated, time: .omitted)), Distance: \(workout.distance)km, Time: \(workout.formattedDuration), Pace: \(workout.formattedPace)"
            }.joined(separator: "\n")
        
        let prompt = """
        Analyze the following workout progression and predict when a personal record might be achieved:
        
        Workout Type: \(workoutType)
        Recent Workouts:
        \(workoutData)
        
        Please analyze:
        - Current fitness trend (improving/declining/stable)
        - Estimated current best performance for common distances (5K, 10K, half-marathon)
        - Predicted timeline for PR attempts
        - Confidence level of predictions
        - Recommended strategy for PR attempt
        
        Focus on realistic predictions based on current fitness trends.
        """
        
        guard let response = await sendChatRequest(prompt: prompt, systemMessage: "You are a performance analyst specializing in running metrics and predictive modeling.") else {
            return nil
        }
        
        return parsePRPrediction(response)
    }
    
    // MARK: - Meal Planning
    func generateMealPlan(targetCalories: Double, targetProtein: Double, dietaryRestrictions: [String], preferences: [String]) async -> String? {
        let restrictionsText = dietaryRestrictions.isEmpty ? "None" : dietaryRestrictions.joined(separator: ", ")
        let preferencesText = preferences.isEmpty ? "None" : preferences.joined(separator: ", ")
        
        let prompt = """
        Generate a daily meal plan with the following requirements:
        
        Target Calories: \(targetCalories) kcal
        Target Protein: \(targetProtein) g
        Dietary Restrictions: \(restrictionsText)
        Preferences: \(preferencesText)
        
        Please provide:
        - Breakfast, lunch, dinner, and 2 snacks
        - Specific portion sizes
        - Calorie and protein content for each meal
        - Preparation time estimates
        - Shopping list summary
        
        Focus on whole foods and balanced nutrition for an active lifestyle.
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a registered dietitian specializing in sports nutrition and meal planning.")
    }
    
    // MARK: - Coaching Insights
    func getCoachingInsights(healthMetrics: HealthMetrics, recentWorkouts: [WorkoutLog]) async -> String? {
        let workoutSummary = recentWorkouts.prefix(5).map { workout in
            "\(workout.workoutType): \(workout.distance)km, HR: \(workout.avgHeartRate)bpm, Effort: \(workout.perceivedExertion)/10"
        }.joined(separator: "\n")
        
        let prompt = """
        Provide coaching insights based on the following data:
        
        Health Metrics:
        - Resting Heart Rate: \(healthMetrics.restingHeartRate) bpm
        - HRV: \(healthMetrics.hrv) ms
        - Sleep: \(healthMetrics.sleepHours) hours (Quality: \(healthMetrics.sleepQuality)/10)
        - Recovery Score: \(healthMetrics.recoveryScore)/100
        - Stress Level: \(healthMetrics.stressLevel)/10
        
        Recent Workouts:
        \(workoutSummary)
        
        Please provide:
        - Assessment of current recovery status
        - Training recommendations for the next 3-5 days
        - Areas of concern or improvement
        - Lifestyle recommendations
        - Signs to watch for (overtraining, etc.)
        
        Be specific and actionable in your recommendations.
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are an experienced endurance coach with expertise in heart rate training and recovery monitoring.")
    }
    
    // MARK: - Private Methods
    private func sendChatRequest(prompt: String, systemMessage: String) async -> String? {
        guard !openAIAPIKey.isEmpty else {
            print("OpenAI API key not configured")
            return nil
        }
        
        let messages = [
            ["role": "system", "content": systemMessage],
            ["role": "user", "content": prompt]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "max_tokens": 1500,
            "temperature": 0.7
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: baseURL) else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                
                await MainActor.run {
                    self.isLoading = false
                    self.lastResponse = content
                }
                
                return content
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Error: \(error.localizedDescription)"
            }
        }
        
        return nil
    }
    
    // parseGoalAnalysis method removed for simplified health companion app
    
    private func parsePRPrediction(_ response: String) -> PRPrediction {
        // Simple parsing - in a real app, you'd use more sophisticated parsing
        let isImproving = response.lowercased().contains("improving") || response.lowercased().contains("progress")
        let daysToRecord = isImproving ? 14 : 30 // Estimate based on trend
        
        return PRPrediction(
            predictedDate: Calendar.current.date(byAdding: .day, value: daysToRecord, to: Date()) ?? Date(),
            confidence: 0.75,
            recommendedStrategy: response,
            estimatedImprovement: isImproving ? 0.05 : 0.02 // 5% or 2% improvement
        )
    }
    
    // MARK: - Meal Image Analysis
    func analyzeMealImage(_ image: UIImage) async -> MealAnalysis? {
        guard !openAIAPIKey.isEmpty else {
            print("OpenAI API key not configured")
            return nil
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to data")
            return nil
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let prompt = """
        Analyze this meal image and provide comprehensive nutritional information including vitamins and minerals. Please respond with ONLY a JSON object in this exact format:
        
        {
            "foodName": "Brief description of the main food items",
            "mealType": "breakfast/lunch/dinner/snack",
            "description": "Detailed description of what you see",
            "calories": 0,
            "protein": 0,
            "carbs": 0,
            "fat": 0,
            "confidence": 0.0,
            "fiber": 0,
            "sugar": 0,
            "sodium": 0,
            "vitaminA": 0,
            "vitaminC": 0,
            "vitaminD": 0,
            "vitaminE": 0,
            "vitaminK": 0,
            "vitaminB1": 0,
            "vitaminB2": 0,
            "vitaminB3": 0,
            "vitaminB6": 0,
            "vitaminB12": 0,
            "folate": 0,
            "calcium": 0,
            "iron": 0,
            "magnesium": 0,
            "phosphorus": 0,
            "potassium": 0,
            "zinc": 0
        }
        
        Instructions:
        - Identify all visible food items in the image
        - Estimate portion sizes based on visual cues
        - Provide realistic nutritional estimates for the entire meal including micronutrients
        - Set confidence between 0.0-1.0 based on how clearly you can identify the foods
        - For mealType, determine based on typical foods and time context
        - Be conservative with estimates if uncertain
        - Include cooking methods in your analysis (fried, grilled, etc.)
        - Estimate vitamins and minerals based on the food types identified
        - Use nutritional database knowledge for micronutrient content
        """
        
        let messages = [
            [
                "role": "system",
                "content": "You are a professional nutritionist and food analyst. You can accurately identify foods and estimate their nutritional content from images. Always respond with valid JSON only."
            ],
            [
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": prompt
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(base64Image)"
                        ]
                    ]
                ]
            ]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "max_tokens": 1000,
            "temperature": 0.3
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: baseURL) else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                
                await MainActor.run {
                    self.isLoading = false
                    self.lastResponse = content
                }
                
                return parseMealAnalysis(content)
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Error analyzing image: \(error.localizedDescription)"
            }
        }
        
        return nil
    }
    
    private func parseMealAnalysis(_ jsonString: String) -> MealAnalysis? {
        // Clean up the JSON string - remove any markdown formatting
        let cleanedString = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedString.data(using: .utf8) else {
            print("Failed to convert JSON string to data")
            return nil
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let foodName = json["foodName"] as? String ?? "Unknown Food"
                let mealType = json["mealType"] as? String ?? "snack"
                let description = json["description"] as? String ?? "AI-analyzed meal"
                let calories = json["calories"] as? Double ?? 0.0
                let protein = json["protein"] as? Double ?? 0.0
                let carbs = json["carbs"] as? Double ?? 0.0
                let fat = json["fat"] as? Double ?? 0.0
                let confidence = json["confidence"] as? Double ?? 0.5
                
                // Parse additional nutrients
                let fiber = json["fiber"] as? Double
                let sugar = json["sugar"] as? Double
                let sodium = json["sodium"] as? Double
                
                // Parse vitamins
                let vitaminA = json["vitaminA"] as? Double
                let vitaminC = json["vitaminC"] as? Double
                let vitaminD = json["vitaminD"] as? Double
                let vitaminE = json["vitaminE"] as? Double
                let vitaminK = json["vitaminK"] as? Double
                let vitaminB1 = json["vitaminB1"] as? Double
                let vitaminB2 = json["vitaminB2"] as? Double
                let vitaminB3 = json["vitaminB3"] as? Double
                let vitaminB6 = json["vitaminB6"] as? Double
                let vitaminB12 = json["vitaminB12"] as? Double
                let folate = json["folate"] as? Double
                
                // Parse minerals
                let calcium = json["calcium"] as? Double
                let iron = json["iron"] as? Double
                let magnesium = json["magnesium"] as? Double
                let phosphorus = json["phosphorus"] as? Double
                let potassium = json["potassium"] as? Double
                let zinc = json["zinc"] as? Double
                
                return MealAnalysis(
                    foodName: foodName,
                    mealType: mealType,
                    description: description,
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    confidence: confidence,
                    fiber: fiber,
                    sugar: sugar,
                    sodium: sodium,
                    vitaminA: vitaminA,
                    vitaminC: vitaminC,
                    vitaminD: vitaminD,
                    vitaminE: vitaminE,
                    vitaminK: vitaminK,
                    vitaminB1: vitaminB1,
                    vitaminB2: vitaminB2,
                    vitaminB3: vitaminB3,
                    vitaminB6: vitaminB6,
                    vitaminB12: vitaminB12,
                    folate: folate,
                    calcium: calcium,
                    iron: iron,
                    magnesium: magnesium,
                    phosphorus: phosphorus,
                    potassium: potassium,
                    zinc: zinc
                )
            }
        } catch {
            print("Error parsing meal analysis JSON: \(error)")
            
            // Fallback: try to extract basic info if JSON parsing fails
            let lines = cleanedString.components(separatedBy: .newlines)
            var foodName = "Unknown Food"
            var calories = 0.0
            
            // Simple text parsing as fallback
            for line in lines {
                if line.lowercased().contains("food") && !foodName.contains("Unknown") {
                    foodName = line.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if line.lowercased().contains("calorie") {
                    let numbers = line.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Double($0) }
                    if let cal = numbers.first {
                        calories = cal
                    }
                }
            }
            
            return MealAnalysis(
                foodName: foodName,
                mealType: "snack",
                description: "AI-analyzed meal (simplified parsing)",
                calories: calories,
                protein: calories * 0.15 / 4, // Rough estimate: 15% protein
                carbs: calories * 0.55 / 4,   // Rough estimate: 55% carbs
                fat: calories * 0.30 / 9,     // Rough estimate: 30% fat
                confidence: 0.3,
                fiber: nil,
                sugar: nil,
                sodium: nil,
                vitaminA: nil,
                vitaminC: nil,
                vitaminD: nil,
                vitaminE: nil,
                vitaminK: nil,
                vitaminB1: nil,
                vitaminB2: nil,
                vitaminB3: nil,
                vitaminB6: nil,
                vitaminB12: nil,
                folate: nil,
                calcium: nil,
                iron: nil,
                magnesium: nil,
                phosphorus: nil,
                potassium: nil,
                zinc: nil
            )
        }
        
        return nil
    }
    
    // MARK: - Enhanced Nutrition Chat
    func getNutritionChatResponse(_ message: String, nutritionLogs: [NutritionLog]) async -> String? {
        let prompt = """
        User Question: \(message)
        
        Please provide a concise, helpful response about nutrition. Keep it:
        - Short (2-3 sentences max)
        - Practical and actionable
        - Encouraging and friendly
        - Focused on the specific question asked
        
        Avoid long explanations or lists. Give direct, useful advice.
        """
        
        return await sendChatRequest(prompt: prompt, systemMessage: "You are a friendly nutritionist who gives concise, practical advice. Keep responses short, helpful, and encouraging. Focus on simple, actionable tips rather than long explanations.")
    }
    
    private func generateNutritionSummary(nutritionLogs: [NutritionLog]) -> String {
        var summary = "RECENT NUTRITION DATA:\n\n"
        
        if !nutritionLogs.isEmpty {
            let totalCalories = nutritionLogs.reduce(0.0) { $0 + $1.calories }
            let totalProtein = nutritionLogs.reduce(0.0) { $0 + $1.protein }
            let totalCarbs = nutritionLogs.reduce(0.0) { $0 + $1.carbs }
            let totalFat = nutritionLogs.reduce(0.0) { $0 + $1.fat }
            let totalWater = nutritionLogs.reduce(0.0) { $0 + $1.waterIntake }
            
            let avgCalories = totalCalories / Double(nutritionLogs.count)
            let avgProtein = totalProtein / Double(nutritionLogs.count)
            let avgCarbs = totalCarbs / Double(nutritionLogs.count)
            let avgFat = totalFat / Double(nutritionLogs.count)
            let avgWater = totalWater / Double(nutritionLogs.count)
            
            summary += "Daily Averages (last \(nutritionLogs.count) days):\n"
            summary += "- Calories: \(Int(avgCalories)) kcal\n"
            summary += "- Protein: \(String(format: "%.1f", avgProtein)) g\n"
            summary += "- Carbs: \(String(format: "%.1f", avgCarbs)) g\n"
            summary += "- Fat: \(String(format: "%.1f", avgFat)) g\n"
            summary += "- Water: \(String(format: "%.1f", avgWater)) L\n\n"
            
            // Meal patterns
            let mealTypes = nutritionLogs.map { $0.mealType }
            let mealCounts = Dictionary(grouping: mealTypes, by: { $0 }).mapValues { $0.count }
            
            summary += "Meal Patterns:\n"
            for (mealType, count) in mealCounts.sorted(by: { $0.value > $1.value }) {
                summary += "- \(mealType.capitalized): \(count) meals\n"
            }
            summary += "\n"
            
            // Recent meals
            summary += "Recent Meals:\n"
            for log in nutritionLogs.prefix(5) {
                summary += "- \(log.foodName) (\(log.mealType)): \(Int(log.calories)) kcal"
                if log.isFromAI {
                    summary += " [AI analyzed]"
                }
                summary += "\n"
            }
        } else {
            summary += "No recent nutrition data available.\n"
        }
        
        return summary
    }
    
    // MARK: - Food Description Analysis
    func analyzeFoodDescription(_ description: String) async -> NutritionData? {
        let prompt = """
        Analyze this food description and provide comprehensive nutritional information including vitamins and minerals:
        
        Description: "\(description)"
        
        Please provide the nutritional information in this exact JSON format:
        {
            "foodName": "estimated food name",
            "calories": number,
            "protein": number,
            "carbs": number,
            "fat": number,
            "fiber": number,
            "sugar": number,
            "sodium": number,
            "quantity": number,
            "unit": "estimated unit (grams, cups, pieces, etc.)",
            "mealType": "breakfast/lunch/dinner/snack",
            "vitaminA": number_in_mcg,
            "vitaminC": number_in_mg,
            "vitaminD": number_in_mcg,
            "vitaminE": number_in_mg,
            "vitaminK": number_in_mcg,
            "vitaminB1": number_in_mg,
            "vitaminB2": number_in_mg,
            "vitaminB3": number_in_mg,
            "vitaminB6": number_in_mg,
            "vitaminB12": number_in_mcg,
            "folate": number_in_mcg,
            "calcium": number_in_mg,
            "iron": number_in_mg,
            "magnesium": number_in_mg,
            "phosphorus": number_in_mg,
            "potassium": number_in_mg,
            "zinc": number_in_mg
        }
        
        Make reasonable estimates based on typical serving sizes and nutritional databases. Include vitamin and mineral content typical for the foods described. If multiple foods are mentioned, combine them into totals. Use 0 for nutrients that are not significant in the food.
        """
        
        let response = await sendChatRequest(prompt: prompt, systemMessage: "You are a nutrition expert. Analyze food descriptions and provide accurate nutritional estimates. Always respond with valid JSON only, no additional text.")
        
        guard let jsonString = response else { return nil }
        
        // Parse JSON response
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let nutritionData = try JSONDecoder().decode(NutritionData.self, from: jsonData)
            return nutritionData
        } catch {
            print("Error parsing nutrition JSON: \(error)")
            return nil
        }
    }
    
    // MARK: - Caloric Deficit Analysis
    func calculateCaloricDeficit(dailyCalories: Double, currentWeight: Double, targetWeight: Double, age: Double, height: Double, gender: String, basalCalories: Double, activeCalories: Double) async -> CaloricDeficitData? {
        
        // Calculate BMR
        let bmr = calculateBMR(weight: currentWeight, height: height, age: age, gender: gender)
        
        // Calculate actual TDEE from real data
        let actualTDEE = basalCalories + activeCalories
        
        // Determine activity level automatically
        let activityMultiplier = actualTDEE / bmr
        let activityLevel = determineActivityLevel(multiplier: activityMultiplier)
        
        let prompt = """
        Calculate caloric deficit information:
        
        Daily Calories Consumed: \(dailyCalories)
        Current Weight: \(currentWeight) kg
        Target Weight: \(targetWeight) kg
        Age: \(age) years
        Height: \(height) cm
        Gender: \(gender)
        
        Calculated BMR: \(bmr) kcal
        Actual TDEE: \(actualTDEE) kcal (from real data)
        Activity Level: \(activityLevel) (automatically calculated)
        
        Please provide analysis in this JSON format:
        {
            "bmr": \(bmr),
            "tdee": \(actualTDEE),
            "recommendedCalories": number,
            "currentDeficit": \(actualTDEE - dailyCalories),
            "weeklyWeightLoss": number,
            "status": "deficit/surplus/maintenance",
            "recommendation": "brief advice"
        }
        
        Base the recommendation on the actual calorie burn data provided.
        """
        
        let response = await sendChatRequest(prompt: prompt, systemMessage: "You are a nutrition and fitness expert. Calculate accurate caloric deficit information using the provided real calorie burn data. Always respond with valid JSON only.")
        
        guard let jsonString = response else { return nil }
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        
        do {
            let deficitData = try JSONDecoder().decode(CaloricDeficitData.self, from: jsonData)
            return deficitData
        } catch {
            print("Error parsing caloric deficit JSON: \(error)")
            return nil
        }
    }
    
    // Helper method to calculate BMR using Mifflin-St Jeor formula (more accurate)
    private func calculateBMR(weight: Double, height: Double, age: Double, gender: String) -> Double {
        if gender.lowercased() == "male" {
            // Mifflin-St Jeor for men: BMR = 10 × weight(kg) + 6.25 × height(cm) - 5 × age(years) + 5
            return 10 * weight + 6.25 * height - 5 * age + 5
        } else {
            // Mifflin-St Jeor for women: BMR = 10 × weight(kg) + 6.25 × height(cm) - 5 × age(years) - 161
            return 10 * weight + 6.25 * height - 5 * age - 161
        }
    }
    
    // Helper method to determine activity level from multiplier using realistic ranges
    private func determineActivityLevel(multiplier: Double) -> String {
        switch multiplier {
        case 0..<1.3: return "Sedentary (1.2x)"
        case 1.3..<1.45: return "Lightly Active (1.375x)"
        case 1.45..<1.65: return "Moderately Active (1.55x)"
        case 1.65..<1.85: return "Very Active (1.725x)"
        default: return "Extra Active (1.9x)"
        }
    }
}

// MARK: - Data Models
struct FitnessLevel {
    let level: String // "beginner", "intermediate", "advanced"
    let weeklyMileage: Double
    let recentPace: Double
    let vo2Max: Double?
    
    var description: String {
        var desc = "\(level.capitalized) level"
        if weeklyMileage > 0 {
            desc += ", \(weeklyMileage) km/week"
        }
        if recentPace > 0 {
            desc += ", recent pace: \(Int(recentPace/60)):\(String(format: "%02d", Int(recentPace.truncatingRemainder(dividingBy: 60))))/km"
        }
        return desc
    }
}

// GoalAnalysis struct removed for simplified health companion app

struct PRPrediction {
    let predictedDate: Date
    let confidence: Double
    let recommendedStrategy: String
    let estimatedImprovement: Double // Percentage improvement
} 

struct MealAnalysis {
    let foodName: String
    let mealType: String
    let description: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let confidence: Double
    
    // Additional nutrients
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?
    
    // Vitamins
    let vitaminA: Double?
    let vitaminC: Double?
    let vitaminD: Double?
    let vitaminE: Double?
    let vitaminK: Double?
    let vitaminB1: Double?
    let vitaminB2: Double?
    let vitaminB3: Double?
    let vitaminB6: Double?
    let vitaminB12: Double?
    let folate: Double?
    
    // Minerals
    let calcium: Double?
    let iron: Double?
    let magnesium: Double?
    let phosphorus: Double?
    let potassium: Double?
    let zinc: Double?
} 

// MARK: - Data Structures
struct NutritionData: Codable {
    let foodName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodium: Double
    let quantity: Double
    let unit: String
    let mealType: String
    
    // Vitamins
    let vitaminA: Double?
    let vitaminC: Double?
    let vitaminD: Double?
    let vitaminE: Double?
    let vitaminK: Double?
    let vitaminB1: Double?
    let vitaminB2: Double?
    let vitaminB3: Double?
    let vitaminB6: Double?
    let vitaminB12: Double?
    let folate: Double?
    
    // Minerals
    let calcium: Double?
    let iron: Double?
    let magnesium: Double?
    let phosphorus: Double?
    let potassium: Double?
    let zinc: Double?
}

struct CaloricDeficitData: Codable {
    let bmr: Double
    let tdee: Double
    let recommendedCalories: Double
    let currentDeficit: Double
    let weeklyWeightLoss: Double
    let status: String
    let recommendation: String
}

struct WeeklyHealthSummary {
    let averageSteps: Double
    let totalActiveMinutes: Double
    let averageSleepQuality: Double
    let stepsTrend: Double
    let sleepQualityTrend: Double
    let activeMinutesTrend: Double
} 
