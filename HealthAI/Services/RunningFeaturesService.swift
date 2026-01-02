import Foundation
import CoreData
import HealthKit
import CoreLocation
import Combine
import WeatherKit

// MARK: - Running Features Service
/// Extended running features: Challenges, Shoes, Segments, Recovery, Weather, Achievements
@MainActor
class RunningFeaturesService: ObservableObject {
    static let shared = RunningFeaturesService()
    
    private var viewContext: NSManagedObjectContext?
    private let healthStore = HKHealthStore()
    private let weatherService = WeatherService.shared
    
    // MARK: - Published Properties
    
    // Challenges & Streaks
    @Published var activeChallenges: [RunningChallenge] = []
    @Published var completedChallenges: [RunningChallenge] = []
    @Published var runningStreak: RunningStreak = RunningStreak(
        currentStreak: 0,
        longestStreak: 0,
        lastRunDate: nil,
        weeklyStreak: 0,
        monthlyStreak: 0,
        streakFreezeAvailable: true,
        streakFreezeUsedDate: nil
    )
    
    // Shoes
    @Published var shoes: [RunningShoe] = []
    @Published var defaultShoe: RunningShoe?
    
    // Run → Shoe assignment (supports multiple shoes per run)
    private struct RunShoeAssignment: Codable {
        let runId: UUID
        let shoeIds: [UUID]
    }
    private var runShoeAssignments: [UUID: [UUID]] = [:]
    
    // Segments
    @Published var segments: [RunningSegment] = []
    @Published var recentSegmentEfforts: [SegmentEffort] = []
    
    // Recovery
    @Published var recoveryAdvice: RecoveryAdvice?
    @Published var readinessScore: Double = 75
    
    // Trends
    @Published var runTrends: [RunTrend] = []
    @Published var selectedTrendTimeframe: RunTrend.TrendTimeframe = .month
    
    // Achievements
    @Published var achievements: [RunningAchievement] = []
    @Published var recentAchievements: [RunningAchievement] = []
    @Published var totalPoints: Int = 0
    
    // Weather
    @Published var currentWeather: WeatherCondition?
    @Published var runWeatherHistory: [UUID: WeatherCondition] = [:]
    
    // Heatmap
    @Published var routeHeatmap: RouteHeatmapData?
    
    // Matched Runs
    @Published var matchedRunComparisons: [MatchedRunComparison] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadSavedData()
    }
    
    func configure(with context: NSManagedObjectContext) {
        self.viewContext = context
        
        Task {
            await refreshAllFeatures()
        }
    }
    
    // MARK: - Main Refresh
    func refreshAllFeatures() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadChallenges() }
            group.addTask { await self.calculateStreak() }
            group.addTask { await self.loadShoes() }
            group.addTask { await self.loadAchievements() }
            group.addTask { await self.calculateRecoveryAdvice() }
            group.addTask { await self.calculateRunTrends() }
            group.addTask { await self.generateRouteHeatmap() }
            group.addTask { await self.fetchCurrentWeather() }
        }
    }
    
    /// Lightweight refresh when new workouts are synced.
    func refreshShoesAfterSync() async {
        await loadShoes()
    }
    
    // MARK: - Challenges
    private func loadChallenges() async {
        // Load saved challenges from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "runningChallenges"),
           let saved = try? JSONDecoder().decode([RunningChallenge].self, from: data) {
            await MainActor.run {
                self.activeChallenges = saved.filter { !$0.isCompleted && $0.isActive }
                self.completedChallenges = saved.filter { $0.isCompleted }
            }
        } else {
            // Initialize with default challenges
            await MainActor.run {
                self.activeChallenges = RunningChallenge.defaultChallenges
            }
        }
        
        // Update challenge progress
        await updateChallengeProgress()
    }
    
    private func updateChallengeProgress() async {
        guard let context = viewContext else { return }
        
        let fetchRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        let calendar = Calendar.current
        
        do {
            let allRuns = try await context.perform {
                try context.fetch(fetchRequest)
            }.filter { $0.workoutType.lowercased().contains("run") }
            
            var updatedChallenges: [RunningChallenge] = []
            
            for var challenge in activeChallenges {
                let relevantRuns = allRuns.filter {
                    $0.timestamp >= challenge.startDate && $0.timestamp <= challenge.endDate
                }
                
                switch challenge.type {
                case .distance:
                    challenge.progress = relevantRuns.reduce(0) { $0 + $1.distance }
                case .frequency:
                    challenge.progress = Double(relevantRuns.count)
                case .duration:
                    challenge.progress = relevantRuns.reduce(0) { $0 + $1.duration } / 60
                case .streak:
                    // Count consecutive days
                    var streak = 0
                    var checkDate = calendar.startOfDay(for: challenge.startDate)
                    while checkDate <= challenge.endDate && checkDate <= Date() {
                        if relevantRuns.contains(where: { calendar.isDate($0.timestamp, inSameDayAs: checkDate) }) {
                            streak += 1
                        } else {
                            break
                        }
                        checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate) ?? checkDate
                    }
                    challenge.progress = Double(streak)
                case .elevation:
                    challenge.progress = relevantRuns.reduce(0) { $0 + $1.elevation }
                case .speed:
                    let fastRuns = relevantRuns.filter { $0.pace > 0 && $0.pace < 300 } // < 5:00/km
                    challenge.progress = Double(fastRuns.count)
                case .community:
                    challenge.progress = relevantRuns.reduce(0) { $0 + $1.distance }
                }
                
                challenge.isCompleted = challenge.progress >= challenge.target
                updatedChallenges.append(challenge)
            }
            
            await MainActor.run {
                self.activeChallenges = updatedChallenges.filter { !$0.isCompleted }
                self.completedChallenges.append(contentsOf: updatedChallenges.filter { $0.isCompleted })
            }
            
            saveChallenges()
        } catch {
            print("Error updating challenges: \(error)")
        }
    }
    
    private func saveChallenges() {
        let allChallenges = activeChallenges + completedChallenges
        if let data = try? JSONEncoder().encode(allChallenges) {
            UserDefaults.standard.set(data, forKey: "runningChallenges")
        }
    }
    
    func joinChallenge(_ challenge: RunningChallenge) {
        var newChallenge = challenge
        newChallenge.progress = 0
        activeChallenges.append(newChallenge)
        saveChallenges()
    }
    
    // MARK: - Streak Calculation
    private func calculateStreak() async {
        guard let context = viewContext else { return }
        
        let fetchRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)]
        
        do {
            let runs = try await context.perform {
                try context.fetch(fetchRequest)
            }.filter { $0.workoutType.lowercased().contains("run") }
            
            guard !runs.isEmpty else { return }
            
            let calendar = Calendar.current
            var currentStreak = 0
            var longestStreak = 0
            var tempStreak = 0
            var checkDate = calendar.startOfDay(for: Date())
            var lastRunDate: Date?
            
            // Calculate current streak
            while true {
                let hasRun = runs.contains { calendar.isDate($0.timestamp, inSameDayAs: checkDate) }
                
                if hasRun {
                    currentStreak += 1
                    if lastRunDate == nil {
                        lastRunDate = runs.first { calendar.isDate($0.timestamp, inSameDayAs: checkDate) }?.timestamp
                    }
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                } else if currentStreak == 0 {
                    // Allow one day gap at the start
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
                    if !runs.contains(where: { calendar.isDate($0.timestamp, inSameDayAs: checkDate) }) {
                        break
                    }
                } else {
                    break
                }
            }
            
            // Calculate longest streak ever
            var runDates = Set<Date>()
            for run in runs {
                runDates.insert(calendar.startOfDay(for: run.timestamp))
            }
            
            let sortedDates = runDates.sorted()
            for date in sortedDates {
                let previousDay = calendar.date(byAdding: .day, value: -1, to: date)!
                if runDates.contains(previousDay) {
                    tempStreak += 1
                } else {
                    tempStreak = 1
                }
                longestStreak = max(longestStreak, tempStreak)
            }
            
            // Weekly streak (weeks with 3+ runs)
            var weeklyStreak = 0
            var weekCheckDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
            
            for _ in 0..<52 {
                let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekCheckDate)!
                let weekRuns = runs.filter { $0.timestamp >= weekCheckDate && $0.timestamp <= weekEnd }
                if weekRuns.count >= 3 {
                    weeklyStreak += 1
                } else {
                    break
                }
                weekCheckDate = calendar.date(byAdding: .day, value: -7, to: weekCheckDate)!
            }
            
            await MainActor.run {
                self.runningStreak = RunningStreak(
                    currentStreak: currentStreak,
                    longestStreak: longestStreak,
                    lastRunDate: lastRunDate,
                    weeklyStreak: weeklyStreak,
                    monthlyStreak: 0, // TODO: Calculate monthly streak
                    streakFreezeAvailable: self.runningStreak.streakFreezeAvailable,
                    streakFreezeUsedDate: self.runningStreak.streakFreezeUsedDate
                )
            }
        } catch {
            print("Error calculating streak: \(error)")
        }
    }
    
    func useStreakFreeze() {
        guard runningStreak.streakFreezeAvailable else { return }
        runningStreak.streakFreezeAvailable = false
        runningStreak.streakFreezeUsedDate = Date()
        // Keep current streak intact
    }
    
    // MARK: - Shoe Tracking
    private func loadShoes() async {
        loadRunShoeAssignments()
        if let data = UserDefaults.standard.data(forKey: "runningShoes"),
           let saved = try? JSONDecoder().decode([RunningShoe].self, from: data) {
            await MainActor.run {
                self.shoes = saved
                self.defaultShoe = saved.first(where: { $0.isDefault })
            }
        } else {
            // Create example shoe if none exist
            let exampleShoe = RunningShoe.example
            await MainActor.run {
                self.shoes = [exampleShoe]
                self.defaultShoe = exampleShoe
            }
            saveShoes()
        }
        
        await updateShoeMileage()
    }
    
    private func updateShoeMileage() async {
        guard let context = viewContext else { return }
        
        // Update mileage per shoe based on run→shoe assignments.
        // If a run has no assignment yet, we auto-assign it to either:
        // - the only active shoe (if there's exactly one), or
        // - the default shoe (if available and active).
        let fetchRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        
        do {
            let runs = try await context.perform {
                try context.fetch(fetchRequest)
            }.filter { $0.workoutType.lowercased().contains("run") }
            
            var didAutoAssign = false
            let activeShoes = shoes.filter { !$0.isRetired }
            let defaultActiveShoeId: UUID? = {
                guard let def = defaultShoe, activeShoes.contains(where: { $0.id == def.id }) else { return nil }
                return def.id
            }()
            let autoShoeId: UUID? = activeShoes.count == 1 ? activeShoes.first?.id : defaultActiveShoeId
            
            // Auto-assign unassigned runs to autoShoeId to keep mileage updating automatically
            for run in runs {
                let runId = run.id
                let existing = runShoeAssignments[runId] ?? []
                if existing.isEmpty, let autoShoeId {
                    runShoeAssignments[runId] = [autoShoeId]
                    didAutoAssign = true
                }
            }
            if didAutoAssign { saveRunShoeAssignments() }
            
            // Aggregate mileage per shoe based on assignments
            var mileageByShoe: [UUID: Double] = [:]
            var runsByShoe: [UUID: [UUID]] = [:]
            for run in runs {
                let runId = run.id
                let assignedShoeIds = runShoeAssignments[runId] ?? []
                for sid in assignedShoeIds {
                    mileageByShoe[sid, default: 0] += run.distance
                    runsByShoe[sid, default: []].append(runId)
                }
            }
            
            // Update each shoe's totals
            for idx in shoes.indices {
                var shoe = shoes[idx]
                let shoeRunMileage = mileageByShoe[shoe.id] ?? 0
                shoe.totalMileage = shoe.initialMileage + shoeRunMileage
                shoe.runs = runsByShoe[shoe.id] ?? []
                shoes[idx] = shoe
            }
            
            defaultShoe = shoes.first(where: { $0.isDefault })
            saveShoes()
        } catch {
            print("Error updating shoe mileage: \(error)")
        }
    }
    
    func addShoe(_ shoe: RunningShoe) {
        var newShoe = shoe
        if shoes.isEmpty {
            newShoe.isDefault = true
        }
        shoes.append(newShoe)
        saveShoes()
    }
    
    func updateShoe(_ shoe: RunningShoe) {
        if let index = shoes.firstIndex(where: { $0.id == shoe.id }) {
            shoes[index] = shoe
            if shoe.isDefault {
                defaultShoe = shoe
            }
            saveShoes()
        }
    }
    
    func setDefaultShoe(_ shoe: RunningShoe) {
        for i in 0..<shoes.count {
            shoes[i].isDefault = shoes[i].id == shoe.id
        }
        defaultShoe = shoe
        saveShoes()
    }
    
    func retireShoe(_ shoe: RunningShoe) {
        if let index = shoes.firstIndex(where: { $0.id == shoe.id }) {
            shoes[index].isRetired = true
            shoes[index].isDefault = false
            saveShoes()
        }
    }
    
    func unretireShoe(_ shoe: RunningShoe) {
        if let index = shoes.firstIndex(where: { $0.id == shoe.id }) {
            shoes[index].isRetired = false
            saveShoes()
        }
    }
    
    func deleteShoe(_ shoe: RunningShoe) {
        // Remove shoe
        shoes.removeAll { $0.id == shoe.id }
        
        // Remove from assignments
        for (runId, shoeIds) in runShoeAssignments {
            let filtered = shoeIds.filter { $0 != shoe.id }
            if filtered.isEmpty {
                runShoeAssignments[runId] = nil
            } else {
                runShoeAssignments[runId] = filtered
            }
        }
        saveRunShoeAssignments()
        
        // Maintain a valid default shoe
        if defaultShoe?.id == shoe.id {
            for i in shoes.indices { shoes[i].isDefault = false }
            if let firstActiveIndex = shoes.firstIndex(where: { !$0.isRetired }) {
                shoes[firstActiveIndex].isDefault = true
                defaultShoe = shoes[firstActiveIndex]
            } else {
                defaultShoe = nil
            }
        } else {
            defaultShoe = shoes.first(where: { $0.isDefault })
        }
        
        saveShoes()
        
        Task { await updateShoeMileage() }
    }
    
    func shoeIds(for runId: UUID) -> [UUID] {
        runShoeAssignments[runId] ?? []
    }
    
    func setShoes(for runId: UUID, shoeIds: [UUID]) {
        let cleaned = Array(Set(shoeIds))
        if cleaned.isEmpty {
            runShoeAssignments[runId] = nil
        } else {
            runShoeAssignments[runId] = cleaned
        }
        saveRunShoeAssignments()
        Task { await updateShoeMileage() }
    }
    
    private func saveShoes() {
        if let data = try? JSONEncoder().encode(shoes) {
            UserDefaults.standard.set(data, forKey: "runningShoes")
        }
    }
    
    private func loadRunShoeAssignments() {
        guard runShoeAssignments.isEmpty else { return } // avoid repeated decode
        if let data = UserDefaults.standard.data(forKey: "runShoeAssignments"),
           let saved = try? JSONDecoder().decode([RunShoeAssignment].self, from: data) {
            var dict: [UUID: [UUID]] = [:]
            for s in saved { dict[s.runId] = s.shoeIds }
            runShoeAssignments = dict
        }
    }
    
    private func saveRunShoeAssignments() {
        let encoded = runShoeAssignments.map { RunShoeAssignment(runId: $0.key, shoeIds: $0.value) }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: "runShoeAssignments")
        }
    }
    
    // MARK: - Recovery Advisor
    private func calculateRecoveryAdvice() async {
        // Get recent training load
        let recentRuns = AdvancedRunningService.shared.recentRuns
        let last48HoursRuns = recentRuns.filter {
            $0.date >= Date().addingTimeInterval(-48 * 3600)
        }
        let last7DaysRuns = recentRuns.filter {
            $0.date >= Date().addingTimeInterval(-7 * 24 * 3600)
        }
        
        // Calculate training stress from recent runs
        let recentTSS = last48HoursRuns.reduce(0) { $0 + $1.trainingStress }
        let weeklyTSS = last7DaysRuns.reduce(0) { $0 + $1.trainingStress }
        
        // Fetch HRV and resting HR from HealthKit
        async let hrvValue = fetchLatestHRV()
        async let restingHRValue = fetchRestingHR()
        
        let hrv = await hrvValue
        let restingHR = await restingHRValue
        
        // Calculate readiness score (0-100)
        var readiness = 80.0
        
        // Adjust based on recent training load
        if recentTSS > 100 {
            readiness -= 20
        } else if recentTSS > 50 {
            readiness -= 10
        }
        
        // Adjust based on HRV (if available)
        if let hrv = hrv {
            if hrv > 60 { readiness += 5 }
            else if hrv < 30 { readiness -= 15 }
        }
        
        // Adjust based on resting HR
        if let rhr = restingHR {
            if rhr > 75 { readiness -= 10 } // Elevated RHR indicates fatigue
        }
        
        let status: RecoveryAdvice.RecoveryStatus
        let fatigueLevel: RecoveryAdvice.FatigueLevel
        let recommendation: String
        var suggestedWorkout: RecoveryAdvice.SuggestedWorkout?
        
        switch readiness {
        case 85...100:
            status = .fullyRecovered
            fatigueLevel = .none
            recommendation = "You're fully recovered and ready for any workout! Consider a challenging session like intervals or a tempo run."
            suggestedWorkout = RecoveryAdvice.SuggestedWorkout(type: "Intervals", duration: 45, intensity: "High", description: "6x800m at 5K pace with 400m jog recovery")
        case 70..<85:
            status = .recovered
            fatigueLevel = .low
            recommendation = "Good recovery status. You can handle a moderate to hard workout today."
            suggestedWorkout = RecoveryAdvice.SuggestedWorkout(type: "Tempo Run", duration: 40, intensity: "Moderate-High", description: "20 minutes at threshold pace")
        case 55..<70:
            status = .recovering
            fatigueLevel = .moderate
            recommendation = "Still recovering from recent efforts. An easy run or cross-training would be ideal."
            suggestedWorkout = RecoveryAdvice.SuggestedWorkout(type: "Easy Run", duration: 30, intensity: "Low", description: "Conversational pace, focus on form")
        case 40..<55:
            status = .fatigued
            fatigueLevel = .high
            recommendation = "Your body needs rest. Consider a rest day or very light activity."
            suggestedWorkout = RecoveryAdvice.SuggestedWorkout(type: "Active Recovery", duration: 20, intensity: "Very Low", description: "Light walk or gentle yoga")
        default:
            status = .overreached
            fatigueLevel = .severe
            recommendation = "Warning: Signs of overtraining. Take 1-2 complete rest days before resuming training."
            suggestedWorkout = nil
        }
        
        let tips: [RecoveryAdvice.RecoveryTip] = [
            RecoveryAdvice.RecoveryTip(icon: "bed.double.fill", title: "Prioritize Sleep", description: "Aim for 7-9 hours of quality sleep tonight", priority: .high),
            RecoveryAdvice.RecoveryTip(icon: "drop.fill", title: "Stay Hydrated", description: "Drink water consistently throughout the day", priority: .high),
            RecoveryAdvice.RecoveryTip(icon: "fork.knife", title: "Fuel Recovery", description: "Eat protein and carbs within 30 min of running", priority: .medium),
            RecoveryAdvice.RecoveryTip(icon: "figure.roll", title: "Foam Roll", description: "10 minutes of foam rolling on major muscle groups", priority: .low)
        ]
        
        let estimatedRecovery = Calendar.current.date(byAdding: .hour, value: Int((100 - readiness) / 3), to: Date()) ?? Date()
        
        await MainActor.run {
            self.readinessScore = max(0, min(100, readiness))
            self.recoveryAdvice = RecoveryAdvice(
                status: status,
                readinessScore: readiness,
                hrv: hrv,
                restingHR: restingHR,
                sleepQuality: nil,
                fatigueLevel: fatigueLevel,
                recommendation: recommendation,
                suggestedWorkout: suggestedWorkout,
                recoveryTips: tips,
                estimatedFullRecovery: estimatedRecovery
            )
        }
    }
    
    private func fetchLatestHRV() async -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-24 * 3600),
            end: Date()
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrvType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let value = statistics?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchRestingHR() async -> Int? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-24 * 3600),
            end: Date()
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let value = statistics?.averageQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
                continuation.resume(returning: value != nil ? Int(value!) : nil)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Run Trends
    private func calculateRunTrends() async {
        let runs = AdvancedRunningService.shared.recentRuns
        guard !runs.isEmpty else { return }
        
        let calendar = Calendar.current
        var trends: [RunTrend] = []
        
        for metric in RunTrend.TrendMetric.allCases {
            var dataPoints: [TrendDataPoint] = []
            
            // Group runs by week
            let groupedRuns = Dictionary(grouping: runs) { run -> Date in
                calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: run.date))!
            }
            
            for (weekStart, weekRuns) in groupedRuns.sorted(by: { $0.key < $1.key }) {
                let value: Double
                switch metric {
                case .distance:
                    value = weekRuns.reduce(0) { $0 + $1.distance }
                case .pace:
                    let totalDistance = weekRuns.reduce(0) { $0 + $1.distance }
                    let totalDuration = weekRuns.reduce(0) { $0 + $1.duration }
                    value = totalDistance > 0 ? totalDuration / totalDistance : 0
                case .duration:
                    value = weekRuns.reduce(0) { $0 + $1.duration } / 60
                case .heartRate:
                    let validRuns = weekRuns.filter { $0.avgHeartRate > 0 }
                    value = validRuns.isEmpty ? 0 : Double(validRuns.reduce(0) { $0 + $1.avgHeartRate }) / Double(validRuns.count)
                case .cadence:
                    let validRuns = weekRuns.compactMap { $0.cadence }
                    value = validRuns.isEmpty ? 0 : validRuns.reduce(0, +) / Double(validRuns.count)
                case .elevation:
                    value = weekRuns.reduce(0) { $0 + $1.elevationGain }
                case .trainingLoad:
                    value = weekRuns.reduce(0) { $0 + $1.trainingStress }
                case .vo2Max:
                    value = AdvancedRunningService.shared.vo2Max
                }
                
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                dataPoints.append(TrendDataPoint(date: weekStart, value: value, label: formatter.string(from: weekStart)))
            }
            
            guard dataPoints.count >= 2 else { continue }
            
            let currentValue = dataPoints.last?.value ?? 0
            let previousValue = dataPoints.dropLast().last?.value ?? currentValue
            let averageValue = dataPoints.reduce(0) { $0 + $1.value } / Double(dataPoints.count)
            let percentageChange = previousValue > 0 ? ((currentValue - previousValue) / previousValue) * 100 : 0
            
            let direction: RunTrend.TrendDirection
            if metric == .pace {
                // For pace, lower is better
                direction = percentageChange < -2 ? .improving : (percentageChange > 2 ? .declining : .stable)
            } else {
                direction = percentageChange > 2 ? .improving : (percentageChange < -2 ? .declining : .stable)
            }
            
            trends.append(RunTrend(
                metric: metric,
                timeframe: selectedTrendTimeframe,
                dataPoints: dataPoints,
                currentValue: currentValue,
                previousValue: previousValue,
                averageValue: averageValue,
                trend: direction,
                percentageChange: percentageChange
            ))
        }
        
        await MainActor.run {
            self.runTrends = trends
        }
    }
    
    // MARK: - Achievements
    private func loadAchievements() async {
        if let data = UserDefaults.standard.data(forKey: "runningAchievements"),
           let saved = try? JSONDecoder().decode([RunningAchievement].self, from: data) {
            await MainActor.run {
                self.achievements = saved
            }
        } else {
            await MainActor.run {
                self.achievements = RunningAchievement.defaultAchievements
            }
        }
        
        await updateAchievementProgress()
    }
    
    private func updateAchievementProgress() async {
        guard let context = viewContext else { return }
        
        let fetchRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        
        do {
            let allRuns = try await context.perform {
                try context.fetch(fetchRequest)
            }.filter { $0.workoutType.lowercased().contains("run") }
            
            let totalDistance = allRuns.reduce(0) { $0 + $1.distance }
            let longestRun = allRuns.max(by: { $0.distance < $1.distance })?.distance ?? 0
            let totalRuns = allRuns.count
            let fastestPace = allRuns.filter { $0.pace > 0 }.min(by: { $0.pace < $1.pace })?.pace ?? 999
            
            var updatedAchievements: [RunningAchievement] = []
            var newlyUnlocked: [RunningAchievement] = []
            
            for var achievement in achievements {
                var newProgress = achievement.requirement.currentValue
                
                switch achievement.requirement.type {
                case .totalDistance:
                    newProgress = totalDistance
                case .singleRunDistance:
                    newProgress = longestRun
                case .totalRuns:
                    newProgress = Double(totalRuns)
                case .consecutiveDays:
                    newProgress = Double(runningStreak.currentStreak)
                case .paceBelowThreshold:
                    newProgress = fastestPace < achievement.requirement.value ? 1 : 0
                case .monthlyDistance:
                    let thisMonth = allRuns.filter {
                        Calendar.current.isDate($0.timestamp, equalTo: Date(), toGranularity: .month)
                    }
                    newProgress = thisMonth.reduce(0) { $0 + $1.distance }
                case .weeklyRuns:
                    let thisWeek = allRuns.filter {
                        Calendar.current.isDate($0.timestamp, equalTo: Date(), toGranularity: .weekOfYear)
                    }
                    newProgress = Double(thisWeek.count)
                case .challengesCompleted:
                    newProgress = Double(completedChallenges.count)
                }
                
                let wasUnlocked = achievement.isUnlocked
                achievement.progress = min(newProgress / achievement.requirement.value, 1.0)
                achievement.isUnlocked = newProgress >= achievement.requirement.value
                
                if achievement.isUnlocked && !wasUnlocked {
                    achievement.unlockedDate = Date()
                    newlyUnlocked.append(achievement)
                }
                
                updatedAchievements.append(achievement)
            }
            
            await MainActor.run {
                self.achievements = updatedAchievements
                self.recentAchievements = newlyUnlocked
                self.totalPoints = updatedAchievements.filter { $0.isUnlocked }.reduce(0) { $0 + $1.points }
            }
            
            saveAchievements()
        } catch {
            print("Error updating achievements: \(error)")
        }
    }
    
    private func saveAchievements() {
        if let data = try? JSONEncoder().encode(achievements) {
            UserDefaults.standard.set(data, forKey: "runningAchievements")
        }
    }
    
    // MARK: - Weather Integration
    private func fetchCurrentWeather() async {
        // For now, create simulated weather - WeatherKit requires entitlements
        // In production, you'd use WeatherKit or a weather API
        
        let conditions: [WeatherCondition.WeatherType] = [.sunny, .partlyCloudy, .cloudy]
        let randomCondition = conditions.randomElement() ?? .sunny
        
        let weather = WeatherCondition(
            id: UUID(),
            temperature: Double.random(in: 15...25),
            feelsLike: Double.random(in: 14...26),
            humidity: Double.random(in: 40...70),
            windSpeed: Double.random(in: 5...15),
            windDirection: ["N", "NE", "E", "SE", "S", "SW", "W", "NW"].randomElement() ?? "N",
            condition: randomCondition,
            uvIndex: Int.random(in: 2...7),
            airQuality: WeatherCondition.AirQuality(index: 42, level: .good),
            sunrise: Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: Date()),
            sunset: Calendar.current.date(bySettingHour: 19, minute: 45, second: 0, of: Date())
        )
        
        await MainActor.run {
            self.currentWeather = weather
        }
    }
    
    // MARK: - Route Heatmap
    private func generateRouteHeatmap() async {
        let runs = AdvancedRunningService.shared.recentRuns
        
        var allPoints: [RouteHeatmapData.HeatmapPoint] = []
        var minLat = 90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0
        
        // Count frequency of coordinates (simplified grid)
        var coordinateFrequency: [String: Int] = [:]
        
        for run in runs {
            for point in run.routePoints {
                // Round to 4 decimal places for grouping (~11m accuracy)
                let key = String(format: "%.4f,%.4f", point.latitude, point.longitude)
                coordinateFrequency[key, default: 0] += 1
                
                minLat = min(minLat, point.latitude)
                maxLat = max(maxLat, point.latitude)
                minLon = min(minLon, point.longitude)
                maxLon = max(maxLon, point.longitude)
            }
        }
        
        let maxFrequency = coordinateFrequency.values.max() ?? 1
        
        for (key, count) in coordinateFrequency {
            let components = key.split(separator: ",")
            if components.count == 2,
               let lat = Double(components[0]),
               let lon = Double(components[1]) {
                allPoints.append(RouteHeatmapData.HeatmapPoint(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    intensity: Double(count) / Double(maxFrequency),
                    runCount: count
                ))
            }
        }
        
        guard !allPoints.isEmpty else { return }
        
        let heatmap = RouteHeatmapData(
            coordinates: allPoints,
            bounds: RouteHeatmapData.MapBounds(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon),
            totalRuns: runs.count,
            mostFrequentRoute: nil
        )
        
        await MainActor.run {
            self.routeHeatmap = heatmap
        }
    }
    
    // MARK: - Matched Runs
    func findMatchedRuns(for run: AdvancedRunData) async -> MatchedRunComparison? {
        let runs = AdvancedRunningService.shared.recentRuns.filter { $0.id != run.id }
        
        // Find runs with similar distance (±10%)
        let similarRuns = runs.filter {
            let diff = abs($0.distance - run.distance) / run.distance
            return diff < 0.10
        }
        
        guard !similarRuns.isEmpty else { return nil }
        
        var improvements: [MatchedRunComparison.ImprovementMetric] = []
        let avgPreviousPace = similarRuns.reduce(0) { $0 + $1.pace } / Double(similarRuns.count)
        let paceImprovement = avgPreviousPace - run.pace
        
        improvements.append(MatchedRunComparison.ImprovementMetric(
            metric: "Pace",
            improvement: paceImprovement,
            unit: "sec/km",
            isPositive: paceImprovement > 0
        ))
        
        if run.avgHeartRate > 0 {
            let avgPreviousHR = similarRuns.filter { $0.avgHeartRate > 0 }.reduce(0) { $0 + $1.avgHeartRate } / max(1, similarRuns.filter { $0.avgHeartRate > 0 }.count)
            let hrImprovement = Double(avgPreviousHR - run.avgHeartRate)
            improvements.append(MatchedRunComparison.ImprovementMetric(
                metric: "Heart Rate",
                improvement: hrImprovement,
                unit: "bpm",
                isPositive: hrImprovement > 0 // Lower HR at same effort is better
            ))
        }
        
        return MatchedRunComparison(
            baseRun: run,
            comparisonRuns: Array(similarRuns.prefix(5)),
            routeSimilarity: 75, // Would need route comparison algorithm
            distanceDifference: 0,
            timeDifference: run.duration - (similarRuns.first?.duration ?? run.duration),
            paceDifference: paceImprovement,
            improvements: improvements
        )
    }
    
    // MARK: - Persistence
    private func loadSavedData() {
        loadRunShoeAssignments()
        // Load streak
        if let data = UserDefaults.standard.data(forKey: "runningStreak"),
           let saved = try? JSONDecoder().decode(RunningStreak.self, from: data) {
            runningStreak = saved
        }
        
        // Load total points
        totalPoints = UserDefaults.standard.integer(forKey: "runningTotalPoints")
    }
}


