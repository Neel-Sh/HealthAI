import Foundation
import CoreData
import HealthKit
import Combine

// MARK: - Advanced Running Analytics Service
/// Professional-grade running analytics that rivals Strava & Nike Run Club
/// Pulls deep metrics from Apple Health including biomechanics, power, and running dynamics
@MainActor
class AdvancedRunningService: ObservableObject {
    static let shared = AdvancedRunningService()
    
    private let healthStore = HKHealthStore()
    private var viewContext: NSManagedObjectContext?
    private var healthKitService: HealthKitService?
    
    // Reference to the shared user profile for accurate health data
    private var userProfile: UserProfileManager { UserProfileManager.shared }
    
    // MARK: - Published Properties
    @Published var currentRun: AdvancedRunData?
    @Published var recentRuns: [AdvancedRunData] = []
    @Published var weeklyAnalytics: WeeklyRunningAnalytics?
    @Published var monthlyAnalytics: MonthlyRunningAnalytics?
    @Published var fitnessProfile: RunnerFitnessProfile?
    @Published var trainingLoad: TrainingLoadAnalysis?
    @Published var racePredictor: RacePredictions?
    @Published var personalBests: [PersonalBest] = []
    @Published var runningFormScore: RunningFormAnalysis?
    @Published var latestFormMetrics: RunningFormMetrics?
    @Published var isLoading = false
    
    // Computed properties that use the centralized UserProfileManager
    var maxHeartRate: Int {
        get { userProfile.maxHeartRate }
        set { userProfile.setManualMaxHR(newValue) }
    }
    
    var restingHeartRate: Int {
        get { userProfile.restingHeartRate ?? 60 }
        set { userProfile.setManualRestingHR(newValue) }
    }
    
    var vo2Max: Double {
        get { userProfile.vo2Max ?? 45.0 }
        set { userProfile.setManualVO2Max(newValue) }
    }
    
    var weight: Double {
        get { userProfile.weight ?? 70.0 }
        set { userProfile.setManualWeight(newValue) }
    }
    
    var height: Double {
        get { userProfile.height ?? 175.0 }
        set { userProfile.setManualHeight(newValue) }
    }
    
    var weeklyGoalKm: Double {
        get { userProfile.weeklyRunningGoalKm }
        set { userProfile.setWeeklyRunningGoal(newValue) }
    }
    
    private init() {
        // Settings are now loaded from UserProfileManager
        print("📊 AdvancedRunningService initialized with UserProfileManager")
    }
    
    func configure(with context: NSManagedObjectContext, healthKitService: HealthKitService) {
        self.viewContext = context
        self.healthKitService = healthKitService
        
        Task {
            // Ensure user profile is synced first for accurate calculations
            await UserProfileManager.shared.syncFromHealthKit()
            await refreshAllData()
        }
    }
    
    // MARK: - Main Data Refresh
    @MainActor
    func refreshAllData() async {
        isLoading = true
        defer { isLoading = false }
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchRecentRuns() }
            group.addTask { await self.calculateWeeklyAnalytics() }
            group.addTask { await self.calculateMonthlyAnalytics() }
            group.addTask { await self.calculateTrainingLoad() }
            group.addTask { await self.calculateFitnessProfile() }
            group.addTask { await self.calculateRacePredictions() }
            group.addTask { await self.fetchPersonalBests() }
            group.addTask { await self.analyzeRunningForm() }
        }
    }
    
    // MARK: - Fetch Recent Runs with Advanced Metrics
    private func fetchRecentRuns() async {
        guard let context = viewContext else { return }
        
        let fetchRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        fetchRequest.predicate = NSPredicate(format: "workoutType CONTAINS[c] %@ AND timestamp >= %@", "run", ninetyDaysAgo as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)]
        
        do {
            let runs = try await context.perform {
                try context.fetch(fetchRequest)
            }
            
            var advancedRuns: [AdvancedRunData] = []
            for run in runs {
                let advancedData = await buildAdvancedRunData(from: run)
                advancedRuns.append(advancedData)
            }
            
            await MainActor.run {
                self.recentRuns = advancedRuns
            }
        } catch {
            print("Error fetching runs: \(error)")
        }
    }
    
    // MARK: - Build Advanced Run Data
    private func buildAdvancedRunData(from workout: WorkoutLog) async -> AdvancedRunData {
        let startDate = workout.timestamp
        let endDate = startDate.addingTimeInterval(workout.duration)
        let routePoints = RouteCoding.decode(workout.route)
        
        // Fetch running dynamics from HealthKit
        async let strideLength = fetchAverageMetric(.runningStrideLength, start: startDate, end: endDate)
        async let groundContactTime = fetchAverageMetric(.runningGroundContactTime, start: startDate, end: endDate)
        async let verticalOscillation = fetchAverageMetric(.runningVerticalOscillation, start: startDate, end: endDate)
        async let runningPower = fetchAverageMetric(.runningPower, start: startDate, end: endDate)
        async let runningSpeed = fetchAverageMetric(.runningSpeed, start: startDate, end: endDate)
        
        // Extended dynamics (best-effort: only returns values if the OS/device provides these samples)
        async let runningCadenceHK = fetchAverageMetric(rawIdentifier: "HKQuantityTypeIdentifierRunningCadence", start: startDate, end: endDate)
        async let stepLength = fetchAverageMetric(rawIdentifier: "HKQuantityTypeIdentifierRunningStepLength", start: startDate, end: endDate)
        async let verticalRatio = fetchAverageMetric(rawIdentifier: "HKQuantityTypeIdentifierRunningVerticalRatio", start: startDate, end: endDate)
        async let asymmetry = fetchAverageMetric(rawIdentifier: "HKQuantityTypeIdentifierRunningAsymmetryPercentage", start: startDate, end: endDate)
        async let gctBalance = fetchAverageMetric(rawIdentifier: "HKQuantityTypeIdentifierRunningGroundContactTimeBalance", start: startDate, end: endDate)
        async let doubleSupport = fetchAverageMetric(rawIdentifier: "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", start: startDate, end: endDate)
        
        // Cardio recovery (computed from HR samples around the end of the workout)
        async let cardioRecovery1Min = fetchHeartRateRecovery1Min(workoutEnd: endDate)
        
        // Fetch heart rate data
        async let heartRateData = fetchHeartRateData(start: startDate, end: endDate)
        async let hrZones = calculateHeartRateZones(start: startDate, end: endDate)
        
        // Fetch elevation data
        async let elevationData = fetchElevationData(for: workout)
        
        // Calculate splits
        let splits = await calculateSplits(for: workout)
        
        let (stride, gct, vo, power, speed) = await (strideLength, groundContactTime, verticalOscillation, runningPower, runningSpeed)
        let (cadenceHK, stepLen, vRatio, asym, gctBal, dblSupport, hrRec1) = await (
            runningCadenceHK,
            stepLength,
            verticalRatio,
            asymmetry,
            gctBalance,
            doubleSupport,
            cardioRecovery1Min
        )
        let hrData = await heartRateData
        let zones = await hrZones
        let elevation = await elevationData
        
        // Calculate cadence from stride and speed
        var cadence: Double = 0
        if let s = speed, let sl = stride, sl > 0 {
            cadence = (s / sl) * 60.0 // steps per minute
        }
        
        // Calculate running economy
        let runningEconomy = calculateRunningEconomy(
            speed: speed ?? 0,
            heartRate: hrData.average,
            power: power
        )
        
        // Calculate training stress score (TSS-like)
        let trainingStress = calculateTrainingStress(
            duration: workout.duration,
            averageHR: hrData.average,
            distance: workout.distance
        )
        
        // Determine effort level
        let effortLevel = determineEffortLevel(averageHR: hrData.average, pace: workout.pace)
        
        return AdvancedRunData(
            id: workout.id ?? UUID(),
            date: workout.timestamp,
            distance: workout.distance,
            duration: workout.duration,
            pace: workout.pace,
            calories: workout.calories,
            
            // Route (Map)
            routePoints: routePoints,
            
            // Heart Rate Metrics
            avgHeartRate: hrData.average,
            maxHeartRate: hrData.max,
            minHeartRate: hrData.min,
            heartRateZones: zones,
            heartRateVariability: hrData.variability,
            
            // Running Dynamics
            strideLength: stride,
            groundContactTime: gct,
            verticalOscillation: vo,
            cadence: cadence > 0 ? cadence : nil,
            runningPower: power,
            runningSpeed: speed,
            runningCadenceHK: cadenceHK,
            stepLength: stepLen,
            verticalRatio: vRatio,
            asymmetryPercentage: asym,
            groundContactTimeBalance: gctBal,
            doubleSupportPercentage: dblSupport,
            cardioRecovery1Min: hrRec1,
            
            // Elevation
            elevationGain: elevation.gain,
            elevationLoss: elevation.loss,
            maxAltitude: elevation.max,
            minAltitude: elevation.min,
            
            // Splits
            splits: splits,
            
            // Analytics
            runningEconomy: runningEconomy,
            trainingStress: trainingStress,
            effortLevel: effortLevel,
            aerobicEffect: calculateAerobicEffect(duration: workout.duration, avgHR: hrData.average),
            anaerobicEffect: calculateAnaerobicEffect(zones: zones)
        )
    }
    
    // MARK: - HealthKit Metric Fetching
    private func fetchAverageMetric(_ identifier: HKQuantityTypeIdentifier, start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                guard let statistics = statistics else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let unit = self.unitForIdentifier(identifier)
                let value = statistics.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
    
    private func unitForIdentifier(_ identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        case .runningStrideLength:
            return .meter()
        case .runningGroundContactTime:
            return .secondUnit(with: .milli)
        case .runningVerticalOscillation:
            return .meterUnit(with: .centi)
        case .runningPower:
            return .watt()
        case .runningSpeed:
            return .meter().unitDivided(by: .second())
        default:
            return .count()
        }
    }

    private func unitForRawIdentifier(_ raw: String) -> HKUnit {
        switch raw {
        case "HKQuantityTypeIdentifierRunningCadence":
            return HKUnit.count().unitDivided(by: .minute())
        case "HKQuantityTypeIdentifierRunningStepLength":
            return .meter()
        case "HKQuantityTypeIdentifierRunningVerticalRatio",
             "HKQuantityTypeIdentifierRunningAsymmetryPercentage",
             "HKQuantityTypeIdentifierRunningGroundContactTimeBalance",
             "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage":
            return .percent()
        default:
            return .count()
        }
    }
    
    private func fetchAverageMetric(rawIdentifier: String, start: Date, end: Date) async -> Double? {
        let id = HKQuantityTypeIdentifier(rawValue: rawIdentifier)
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let unit = unitForRawIdentifier(rawIdentifier)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let value = statistics?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchHeartRateRecovery1Min(workoutEnd: Date) async -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        
        let endWindowStart = workoutEnd.addingTimeInterval(-30)
        let endWindowPredicate = HKQuery.predicateForSamples(withStart: endWindowStart, end: workoutEnd)
        
        let afterEnd = workoutEnd.addingTimeInterval(60)
        let recoveryPredicate = HKQuery.predicateForSamples(withStart: workoutEnd, end: afterEnd)
        
        async let hrAtEnd = fetchAverageQuantity(type: heartRateType, unit: unit, predicate: endWindowPredicate)
        async let hrAfter1Min = fetchAverageQuantity(type: heartRateType, unit: unit, predicate: recoveryPredicate)
        
        guard let endHR = await hrAtEnd, let afterHR = await hrAfter1Min else { return nil }
        return max(0, endHR - afterHR)
    }
    
    private func fetchAverageQuantity(type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Heart Rate Analysis
    private func fetchHeartRateData(start: Date, end: Date) async -> (average: Int, max: Int, min: Int, variability: Double) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (0, 0, 0, 0)
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: (0, 0, 0, 0))
                    return
                }
                
                let hrValues = samples.map { Int($0.quantity.doubleValue(for: .count().unitDivided(by: .minute()))) }
                let avg = hrValues.reduce(0, +) / hrValues.count
                let max = hrValues.max() ?? 0
                let min = hrValues.min() ?? 0
                
                // Calculate HRV (simplified RMSSD approximation)
                var variability: Double = 0
                if hrValues.count > 1 {
                    var sumSquaredDiffs: Double = 0
                    for i in 1..<hrValues.count {
                        let diff = Double(hrValues[i] - hrValues[i-1])
                        sumSquaredDiffs += diff * diff
                    }
                    variability = sqrt(sumSquaredDiffs / Double(hrValues.count - 1))
                }
                
                continuation.resume(returning: (avg, max, min, variability))
            }
            healthStore.execute(query)
        }
    }
    
    private func calculateHeartRateZones(start: Date, end: Date) async -> [HeartRateZone] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return HeartRateZone.defaultZones
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { [self] _, samples, error in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: HeartRateZone.defaultZones)
                    return
                }
                
                // Calculate zone boundaries based on max HR
                let zone1Max = Double(maxHeartRate) * 0.60
                let zone2Max = Double(maxHeartRate) * 0.70
                let zone3Max = Double(maxHeartRate) * 0.80
                let zone4Max = Double(maxHeartRate) * 0.90
                
                var zoneDurations: [Int: TimeInterval] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
                
                for i in 0..<samples.count {
                    let hr = samples[i].quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                    let duration: TimeInterval
                    
                    if i < samples.count - 1 {
                        duration = samples[i + 1].startDate.timeIntervalSince(samples[i].startDate)
                    } else {
                        duration = 5 // Assume 5 seconds for last sample
                    }
                    
                    let zone: Int
                    switch hr {
                    case ..<zone1Max: zone = 1
                    case zone1Max..<zone2Max: zone = 2
                    case zone2Max..<zone3Max: zone = 3
                    case zone3Max..<zone4Max: zone = 4
                    default: zone = 5
                    }
                    
                    zoneDurations[zone, default: 0] += duration
                }
                
                let totalDuration = zoneDurations.values.reduce(0, +)
                
                let zones: [HeartRateZone] = [
                    HeartRateZone(zone: 1, name: "Recovery", minHR: Int(Double(self.restingHeartRate)), maxHR: Int(zone1Max), duration: zoneDurations[1] ?? 0, percentage: totalDuration > 0 ? (zoneDurations[1] ?? 0) / totalDuration * 100 : 0, color: "6EE7B7"),
                    HeartRateZone(zone: 2, name: "Aerobic Base", minHR: Int(zone1Max), maxHR: Int(zone2Max), duration: zoneDurations[2] ?? 0, percentage: totalDuration > 0 ? (zoneDurations[2] ?? 0) / totalDuration * 100 : 0, color: "34D399"),
                    HeartRateZone(zone: 3, name: "Tempo", minHR: Int(zone2Max), maxHR: Int(zone3Max), duration: zoneDurations[3] ?? 0, percentage: totalDuration > 0 ? (zoneDurations[3] ?? 0) / totalDuration * 100 : 0, color: "FBBF24"),
                    HeartRateZone(zone: 4, name: "Threshold", minHR: Int(zone3Max), maxHR: Int(zone4Max), duration: zoneDurations[4] ?? 0, percentage: totalDuration > 0 ? (zoneDurations[4] ?? 0) / totalDuration * 100 : 0, color: "F97316"),
                    HeartRateZone(zone: 5, name: "VO2 Max", minHR: Int(zone4Max), maxHR: self.maxHeartRate, duration: zoneDurations[5] ?? 0, percentage: totalDuration > 0 ? (zoneDurations[5] ?? 0) / totalDuration * 100 : 0, color: "EF4444")
                ]
                
                continuation.resume(returning: zones)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Elevation Data
    private func fetchElevationData(for workout: WorkoutLog) async -> (gain: Double, loss: Double, max: Double, min: Double) {
        // TODO: Implement route-based elevation tracking
        // For now, return stored values or estimates
        return (workout.elevation, 0, 0, 0)
    }
    
    // MARK: - Split Calculations
    private func calculateSplits(for workout: WorkoutLog) async -> [RunSplit] {
        guard workout.distance > 0, workout.duration > 0 else { return [] }
        
        let distanceKm = workout.distance
        let totalSplits = Int(ceil(distanceKm))
        var splits: [RunSplit] = []
        
        let avgPace = workout.duration / distanceKm // seconds per km
        
        for i in 1...totalSplits {
            let isPartialSplit = Double(i) > distanceKm
            let splitDistance = isPartialSplit ? (distanceKm - Double(i - 1)) : 1.0
            
            // Add some realistic variation
            let variation = Double.random(in: -0.05...0.05)
            let splitPace = avgPace * (1 + variation)
            let splitDuration = splitPace * splitDistance
            
            // Estimate elevation for this km (would be more accurate with route data)
            let elevationGain = Double.random(in: 0...15)
            let elevationLoss = Double.random(in: 0...10)
            
            // Estimate cadence
            let cadence = Int.random(in: 165...180)
            
            splits.append(RunSplit(
                kilometer: i,
                duration: splitDuration,
                pace: splitPace,
                heartRate: Int(Double(workout.avgHeartRate) + Double.random(in: -5...5)),
                cadence: cadence,
                elevationGain: elevationGain,
                elevationLoss: elevationLoss,
                isPartialSplit: isPartialSplit,
                partialDistance: isPartialSplit ? splitDistance : nil
            ))
        }
        
        return splits
    }
    
    // MARK: - Analytics Calculations
    private func calculateRunningEconomy(speed: Double, heartRate: Int, power: Double?) -> Double {
        // Running Economy = Power / Speed (watts per m/s)
        // Lower is better - indicates less energy to maintain speed
        guard speed > 0 else { return 0 }
        
        if let power = power, power > 0 {
            return power / speed // watts per m/s
        }
        
        // Estimate from heart rate if no power data
        // Higher HR at same speed = worse economy
        let hrFactor = Double(heartRate) / Double(maxHeartRate)
        return hrFactor * 100 / speed
    }
    
    private func calculateTrainingStress(duration: Double, averageHR: Int, distance: Double) -> Double {
        // Simplified Training Stress Score calculation
        // Based on duration, intensity (HR), and distance
        guard duration > 0, averageHR > 0 else { return 0 }
        
        let intensity = Double(averageHR - restingHeartRate) / Double(maxHeartRate - restingHeartRate)
        let normalizedIntensity = max(0, min(1, intensity))
        
        // TSS = (duration in hours) * (intensity factor)^2 * 100
        let durationHours = duration / 3600
        let tss = durationHours * pow(normalizedIntensity, 2) * 100
        
        return min(tss, 300) // Cap at 300
    }
    
    private func determineEffortLevel(averageHR: Int, pace: Double) -> EffortLevel {
        let hrPercentage = Double(averageHR) / Double(maxHeartRate)
        
        switch hrPercentage {
        case ..<0.60: return .recovery
        case 0.60..<0.70: return .easy
        case 0.70..<0.80: return .moderate
        case 0.80..<0.90: return .tempo
        case 0.90..<0.95: return .threshold
        default: return .maxEffort
        }
    }
    
    private func calculateAerobicEffect(duration: Double, avgHR: Int) -> Double {
        // Aerobic Training Effect (1.0 - 5.0 scale)
        let hrIntensity = Double(avgHR) / Double(maxHeartRate)
        let durationMinutes = duration / 60
        
        var effect = 1.0
        
        // Duration factor
        if durationMinutes >= 30 {
            effect += min(1.5, durationMinutes / 60)
        }
        
        // Intensity factor
        if hrIntensity >= 0.65 && hrIntensity <= 0.85 {
            effect += 1.5 // Optimal aerobic zone
        } else if hrIntensity > 0.85 {
            effect += 1.0 // Too intense for pure aerobic
        }
        
        return min(5.0, effect)
    }
    
    private func calculateAnaerobicEffect(zones: [HeartRateZone]) -> Double {
        // Anaerobic Training Effect (1.0 - 5.0 scale)
        let zone4Percentage = zones.first(where: { $0.zone == 4 })?.percentage ?? 0
        let zone5Percentage = zones.first(where: { $0.zone == 5 })?.percentage ?? 0
        
        let anaerobicTime = zone4Percentage + zone5Percentage
        
        switch anaerobicTime {
        case ..<5: return 1.0
        case 5..<15: return 2.0
        case 15..<25: return 3.0
        case 25..<40: return 4.0
        default: return 5.0
        }
    }
    
    // MARK: - Weekly Analytics
    private func calculateWeeklyAnalytics() async {
        let weekRuns = recentRuns.filter {
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear)
        }
        
        guard !weekRuns.isEmpty else {
            await MainActor.run {
                self.weeklyAnalytics = nil
            }
            return
        }
        
        let totalDistance = weekRuns.reduce(0) { $0 + $1.distance }
        let totalDuration = weekRuns.reduce(0) { $0 + $1.duration }
        let totalCalories = weekRuns.reduce(0) { $0 + $1.calories }
        let totalElevation = weekRuns.reduce(0) { $0 + $1.elevationGain }
        let avgPace = totalDistance > 0 ? totalDuration / totalDistance : 0
        let avgHR = weekRuns.compactMap { $0.avgHeartRate > 0 ? $0.avgHeartRate : nil }.reduce(0, +) / max(1, weekRuns.count)
        let totalTSS = weekRuns.reduce(0) { $0 + $1.trainingStress }
        
        // Calculate daily distances
        var dailyDistances: [Double] = Array(repeating: 0, count: 7)
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        
        for run in weekRuns {
            let dayIndex = calendar.dateComponents([.day], from: startOfWeek, to: run.date).day ?? 0
            if dayIndex >= 0 && dayIndex < 7 {
                dailyDistances[dayIndex] += run.distance
            }
        }
        
        // Workout type distribution
        var workoutTypeDistribution: [EffortLevel: Int] = [:]
        for run in weekRuns {
            workoutTypeDistribution[run.effortLevel, default: 0] += 1
        }
        
        let analytics = WeeklyRunningAnalytics(
            totalRuns: weekRuns.count,
            totalDistance: totalDistance,
            totalDuration: totalDuration,
            totalCalories: totalCalories,
            totalElevation: totalElevation,
            averagePace: avgPace,
            averageHeartRate: avgHR,
            longestRun: weekRuns.max(by: { $0.distance < $1.distance })?.distance ?? 0,
            fastestPace: weekRuns.filter { $0.pace > 0 }.min(by: { $0.pace < $1.pace })?.pace ?? 0,
            trainingStressTotal: totalTSS,
            dailyDistances: dailyDistances,
            workoutTypeDistribution: workoutTypeDistribution,
            weeklyGoalProgress: totalDistance / weeklyGoalKm
        )
        
        await MainActor.run {
            self.weeklyAnalytics = analytics
        }
    }
    
    // MARK: - Monthly Analytics
    private func calculateMonthlyAnalytics() async {
        let monthRuns = recentRuns.filter {
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month)
        }
        
        guard !monthRuns.isEmpty else {
            await MainActor.run {
                self.monthlyAnalytics = nil
            }
            return
        }
        
        let totalDistance = monthRuns.reduce(0) { $0 + $1.distance }
        let totalDuration = monthRuns.reduce(0) { $0 + $1.duration }
        let totalCalories = monthRuns.reduce(0) { $0 + $1.calories }
        let avgPace = totalDistance > 0 ? totalDuration / totalDistance : 0
        
        // Calculate weekly breakdown
        var weeklyTotals: [Double] = Array(repeating: 0, count: 5)
        let calendar = Calendar.current
        
        for run in monthRuns {
            let weekOfMonth = calendar.component(.weekOfMonth, from: run.date) - 1
            if weekOfMonth >= 0 && weekOfMonth < 5 {
                weeklyTotals[weekOfMonth] += run.distance
            }
        }
        
        // Calculate trend (comparing to previous month)
        let previousMonthRuns = recentRuns.filter {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return calendar.isDate($0.date, equalTo: previousMonth, toGranularity: .month)
        }
        let previousDistance = previousMonthRuns.reduce(0) { $0 + $1.distance }
        let distanceTrend = previousDistance > 0 ? ((totalDistance - previousDistance) / previousDistance) * 100 : 0
        
        let analytics = MonthlyRunningAnalytics(
            totalRuns: monthRuns.count,
            totalDistance: totalDistance,
            totalDuration: totalDuration,
            totalCalories: totalCalories,
            averagePace: avgPace,
            weeklyTotals: weeklyTotals,
            distanceTrend: distanceTrend,
            consistencyScore: calculateConsistencyScore(runs: monthRuns)
        )
        
        await MainActor.run {
            self.monthlyAnalytics = analytics
        }
    }
    
    private func calculateConsistencyScore(runs: [AdvancedRunData]) -> Double {
        // Calculate how consistently the user runs throughout the period
        let calendar = Calendar.current
        var daysWithRuns = Set<Int>()
        
        for run in runs {
            let day = calendar.ordinality(of: .day, in: .month, for: run.date) ?? 0
            daysWithRuns.insert(day)
        }
        
        let daysInMonth = calendar.range(of: .day, in: .month, for: Date())?.count ?? 30
        let runDaysPerWeek = Double(daysWithRuns.count) / Double(daysInMonth) * 7
        
        // Ideal is 4-5 days per week
        if runDaysPerWeek >= 4 && runDaysPerWeek <= 5 {
            return 100
        } else if runDaysPerWeek >= 3 && runDaysPerWeek <= 6 {
            return 80
        } else if runDaysPerWeek >= 2 {
            return 60
        }
        return 40
    }
    
    // MARK: - Training Load Analysis
    private func calculateTrainingLoad() async {
        let calendar = Calendar.current
        let now = Date()
        
        let last7DaysRuns = recentRuns.filter {
            $0.date >= calendar.date(byAdding: .day, value: -7, to: now) ?? now
        }
        let last28DaysRuns = recentRuns.filter {
            $0.date >= calendar.date(byAdding: .day, value: -28, to: now) ?? now
        }
        
        // Calculate Acute Training Load (ATL) - sum of last 7 days
        let acuteLoad = last7DaysRuns.reduce(0) { $0 + $1.trainingStress }
        
        // Calculate Chronic Training Load (CTL) more accurately
        // CTL should be weekly average over 28 days, but we need to handle new users
        // who don't have 4 weeks of data yet
        let totalChronicStress = last28DaysRuns.reduce(0) { $0 + $1.trainingStress }
        
        // Calculate how many weeks of data we actually have
        let oldestRunDate = last28DaysRuns.min(by: { $0.date < $1.date })?.date ?? now
        let daysWithData = max(1, calendar.dateComponents([.day], from: oldestRunDate, to: now).day ?? 1)
        let weeksWithData = max(1.0, Double(daysWithData) / 7.0)
        
        // For users with less than 4 weeks of data, use actual weeks instead of dividing by 4
        // This prevents artificially low chronic load for new users
        let effectiveWeeks = min(4.0, weeksWithData)
        let chronicLoad = totalChronicStress / effectiveWeeks
        
        // Training Stress Balance = Fitness - Fatigue
        let trainingBalance = chronicLoad - acuteLoad
        
        // Acute:Chronic Workload Ratio (ACWR)
        // Handle edge cases:
        // 1. No chronic load data yet - can't calculate meaningful ACWR
        // 2. Very new users (< 2 weeks of data) - be conservative
        let acwr: Double
        let status: TrainingStatus
        
        if last28DaysRuns.isEmpty {
            // No data at all
            acwr = 0
            status = .undertraining
        } else if chronicLoad < 5 {
            // Very low chronic load (new user or returning from break)
            // Don't flag as overtraining just because they did one workout
            acwr = chronicLoad > 0 ? min(acuteLoad / chronicLoad, 2.0) : 1.0
            if last7DaysRuns.count <= 2 {
                // 1-2 runs in a week for a new user is fine
                status = .optimal
            } else {
                status = acwr > 1.5 ? .overreaching : .optimal
            }
        } else if weeksWithData < 2 {
            // Less than 2 weeks of data - be conservative with assessment
            acwr = chronicLoad > 0 ? acuteLoad / chronicLoad : 1.0
            // For new users ramping up, don't immediately flag overtraining
            if acwr > 1.5 && last7DaysRuns.count <= 3 {
                status = .overreaching
            } else {
                switch acwr {
                case ..<0.8: status = .undertraining
                case 0.8..<1.5: status = .optimal
                default: status = .overreaching
                }
            }
        } else {
            // Normal calculation for users with sufficient data (2+ weeks)
            acwr = acuteLoad / chronicLoad
            switch acwr {
            case ..<0.8: status = .undertraining
            case 0.8..<1.3: status = .optimal
            case 1.3..<1.5: status = .overreaching
            default: status = .overtraining
            }
        }
        
        let analysis = TrainingLoadAnalysis(
            acuteLoad: acuteLoad,
            chronicLoad: chronicLoad,
            trainingBalance: trainingBalance,
            acuteChronicRatio: acwr,
            status: status,
            recommendation: generateTrainingRecommendation(ratio: acwr, status: status, weeksOfData: weeksWithData)
        )
        
        await MainActor.run {
            self.trainingLoad = analysis
        }
    }
    
    private func generateTrainingRecommendation(ratio: Double, status: TrainingStatus, weeksOfData: Double = 4.0) -> String {
        // Provide context-aware recommendations based on data availability
        if weeksOfData < 2 {
            switch status {
            case .undertraining:
                return "Getting started! Keep building consistency with regular runs to establish your baseline."
            case .optimal:
                return "Great start! Keep up the consistent training as you build your fitness base."
            case .overreaching:
                return "Good effort! Consider spacing out your runs as you build endurance."
            case .overtraining:
                return "Take it easy as you're just getting started. Build up gradually to prevent injury."
            }
        }
        
        switch status {
        case .undertraining:
            return "Your training load is low. Consider increasing intensity or volume gradually to maintain fitness gains."
        case .optimal:
            return "Great job! Your training load is in the optimal zone. Keep up the balanced approach."
        case .overreaching:
            return "You're training hard! Consider adding recovery days to prevent overtraining."
        case .overtraining:
            return "Warning: High injury risk. Reduce training intensity and prioritize rest and recovery."
        }
    }
    
    // MARK: - Fitness Profile
    private func calculateFitnessProfile() async {
        guard !recentRuns.isEmpty else { return }
        
        // Calculate running age based on performance
        let bestPace = recentRuns.filter { $0.distance >= 5 }.min(by: { $0.pace < $1.pace })?.pace ?? 0
        
        // Estimate running age from pace (simplified)
        let runningAge: Int
        switch bestPace {
        case ..<240: runningAge = 25 // Elite
        case 240..<300: runningAge = 30
        case 300..<360: runningAge = 35
        case 360..<420: runningAge = 40
        case 420..<480: runningAge = 45
        default: runningAge = 50
        }
        
        // Calculate strengths
        var strengths: [RunnerStrength] = []
        
        let avgDistance = recentRuns.reduce(0) { $0 + $1.distance } / Double(recentRuns.count)
        if avgDistance >= 10 {
            strengths.append(.endurance)
        }
        
        if bestPace < 300 {
            strengths.append(.speed)
        }
        
        let avgCadence = recentRuns.compactMap { $0.cadence }.reduce(0, +) / max(1, Double(recentRuns.count))
        if avgCadence >= 175 {
            strengths.append(.cadence)
        }
        
        let profile = RunnerFitnessProfile(
            vo2MaxEstimate: vo2Max,
            runningAge: runningAge,
            fitnessLevel: determineFitnessLevel(),
            strengths: strengths,
            weeklyMileage: weeklyAnalytics?.totalDistance ?? 0,
            longestRunEver: recentRuns.max(by: { $0.distance < $1.distance })?.distance ?? 0
        )
        
        await MainActor.run {
            self.fitnessProfile = profile
        }
    }
    
    private func determineFitnessLevel() -> RunningFitnessLevel {
        let weeklyDistance = weeklyAnalytics?.totalDistance ?? 0
        
        switch weeklyDistance {
        case ..<10: return .beginner
        case 10..<25: return .intermediate
        case 25..<50: return .advanced
        case 50..<80: return .competitive
        default: return .elite
        }
    }
    
    // MARK: - Race Predictions
    private func calculateRacePredictions() async {
        // Use best recent 5K or 10K to predict race times
        let recentBestRuns = recentRuns.filter { $0.distance >= 5 }.sorted { $0.pace < $1.pace }
        
        guard let bestRun = recentBestRuns.first else { return }
        
        // Riegel's Formula: T2 = T1 × (D2/D1)^1.06
        let baseTime = bestRun.duration
        let baseDistance = bestRun.distance
        
        func predictTime(for distance: Double) -> Double {
            return baseTime * pow(distance / baseDistance, 1.06)
        }
        
        let predictions = RacePredictions(
            oneK: predictTime(for: 1),
            fiveK: predictTime(for: 5),
            tenK: predictTime(for: 10),
            halfMarathon: predictTime(for: 21.0975),
            marathon: predictTime(for: 42.195),
            basedOnDistance: baseDistance,
            basedOnTime: baseTime,
            confidence: calculatePredictionConfidence()
        )
        
        await MainActor.run {
            self.racePredictor = predictions
        }
    }
    
    private func calculatePredictionConfidence() -> Double {
        // Confidence based on number of recent runs and consistency
        let runCount = min(recentRuns.count, 20)
        return Double(runCount) / 20 * 100
    }
    
    // MARK: - Personal Bests
    private func fetchPersonalBests() async {
        var bests: [PersonalBest] = []
        
        // Standard race distances - added 2K for beginners
        let distances: [(String, Double)] = [
            ("1K", 1.0), ("2K", 2.0), ("5K", 5.0), ("10K", 10.0), ("Half Marathon", 21.0975), ("Marathon", 42.195)
        ]
        
        for (name, targetDistance) in distances {
            // Find runs that are close to the target distance (within ±10%)
            // This ensures we're showing actual PRs, not estimated times
            let minDistance = targetDistance * 0.90
            let maxDistance = targetDistance * 1.10
            
            let qualifyingRuns = recentRuns.filter { 
                $0.distance >= minDistance && $0.distance <= maxDistance 
            }
            
            if let fastest = qualifyingRuns.min(by: { $0.duration < $1.duration }) {
                // For runs that are exactly or close to the target, show actual time
                bests.append(PersonalBest(
                    distance: targetDistance,
                    distanceName: name,
                    time: fastest.duration,
                    pace: fastest.pace,
                    date: fastest.date,
                    heartRate: fastest.avgHeartRate,
                    actualDistance: fastest.distance
                ))
            } else {
                // If no runs within ±10%, check for longer runs and estimate split time
                let longerRuns = recentRuns.filter { $0.distance >= targetDistance }
                if let bestRun = longerRuns.min(by: { $0.pace < $1.pace }) {
                    // Estimate time for target distance using the best pace
                    // Using Riegel's formula: T2 = T1 × (D2/D1)^1.06
                    let estimatedTime = bestRun.duration * pow(targetDistance / bestRun.distance, 1.06)
                    let estimatedPace = estimatedTime / targetDistance
                    
                    bests.append(PersonalBest(
                        distance: targetDistance,
                        distanceName: name,
                        time: estimatedTime,
                        pace: estimatedPace,
                        date: bestRun.date,
                        heartRate: bestRun.avgHeartRate,
                        actualDistance: bestRun.distance,
                        isEstimated: true
                    ))
                }
            }
        }
        
        // Add longest run
        if let longest = recentRuns.max(by: { $0.distance < $1.distance }) {
            bests.append(PersonalBest(
                distance: longest.distance,
                distanceName: "Longest Run",
                time: longest.duration,
                pace: longest.pace,
                date: longest.date,
                heartRate: longest.avgHeartRate,
                actualDistance: longest.distance
            ))
        }
        
        await MainActor.run {
            self.personalBests = bests
        }
    }
    
    // MARK: - Running Form Analysis
    private func analyzeRunningForm() async {
        print("📊 Analyzing running form...")
        
        // First, try to fetch fresh running form metrics from HealthKit
        if let healthService = healthKitService {
            let freshMetrics = await healthService.getRecentRunningFormSummary()
            
            await MainActor.run {
                self.latestFormMetrics = freshMetrics
            }
            
            if freshMetrics.hasData {
                print("✅ Got running form data from HealthKit")
                await processFormMetrics(freshMetrics)
                return
            }
        }
        
        // Fallback: analyze from recent runs with dynamics data
        let runsWithDynamics = recentRuns.filter {
            $0.strideLength != nil || $0.groundContactTime != nil || $0.verticalOscillation != nil
        }
        
        if runsWithDynamics.isEmpty {
            print("⚠️ No running dynamics data available")
            return
        }
        
        print("📊 Analyzing \(runsWithDynamics.count) runs with dynamics data")
        
        let avgStride = runsWithDynamics.compactMap { $0.strideLength }.reduce(0, +) / max(1, Double(runsWithDynamics.count))
        let avgGCT = runsWithDynamics.compactMap { $0.groundContactTime }.reduce(0, +) / max(1, Double(runsWithDynamics.count))
        let avgVO = runsWithDynamics.compactMap { $0.verticalOscillation }.reduce(0, +) / max(1, Double(runsWithDynamics.count))
        let avgCadence = runsWithDynamics.compactMap { $0.cadence }.reduce(0, +) / max(1, Double(runsWithDynamics.count))
        
        let metrics = RunningFormMetrics(
            strideLength: avgStride > 0 ? avgStride : nil,
            groundContactTime: avgGCT > 0 ? avgGCT : nil,
            verticalOscillation: avgVO > 0 ? avgVO : nil,
            runningPower: nil,
            runningSpeed: nil,
            cadence: avgCadence > 0 ? avgCadence : nil,
            runningCadenceHK: nil,
            stepLength: nil,
            verticalRatio: nil,
            asymmetryPercentage: nil,
            groundContactTimeBalance: nil,
            doubleSupportPercentage: nil,
            cardioRecovery1Min: nil,
            lastUpdated: Date()
        )
        
        await MainActor.run {
            self.latestFormMetrics = metrics
        }
        
        await processFormMetrics(metrics)
    }
    
    private func processFormMetrics(_ metrics: RunningFormMetrics) async {
        let avgStride = metrics.strideLength ?? 0
        let avgGCT = metrics.groundContactTime ?? 0
        let avgVO = metrics.verticalOscillation ?? 0
        let avgCadence = metrics.cadence ?? 0
        
        // Calculate form score (0-100)
        var score = 50.0
        
        // Cadence scoring (ideal: 175-185 spm)
        if avgCadence >= 175 && avgCadence <= 185 {
            score += 15
        } else if avgCadence >= 165 && avgCadence < 175 {
            score += 10
        } else if avgCadence > 185 && avgCadence <= 195 {
            score += 10
        } else if avgCadence >= 155 {
            score += 5
        }
        
        // Ground contact time scoring (lower is better, ideal: <200ms)
        if avgGCT > 0 {
            if avgGCT < 200 {
                score += 15
            } else if avgGCT < 250 {
                score += 10
            } else if avgGCT < 300 {
                score += 5
            }
        }
        
        // Vertical oscillation scoring (lower is better, ideal: <8cm)
        if avgVO > 0 {
            if avgVO < 8 {
                score += 15
            } else if avgVO < 10 {
                score += 10
            } else if avgVO < 12 {
                score += 5
            }
        }
        
        // Stride length efficiency (based on height, ideal: 0.4-0.5 * height in meters)
        let idealStride = height / 100 * 0.45
        if avgStride > 0 && abs(avgStride - idealStride) < 0.1 {
            score += 5
        }
        
        let analysis = RunningFormAnalysis(
            overallScore: min(100, score),
            strideLength: avgStride > 0 ? avgStride : 0,
            strideLengthRating: avgStride > 0 ? rateMetric(avgStride, ideal: idealStride, tolerance: 0.15) : .average,
            groundContactTime: avgGCT > 0 ? avgGCT : 0,
            groundContactRating: avgGCT > 0 ? rateMetricInverse(avgGCT, ideal: 200, tolerance: 50) : .average,
            verticalOscillation: avgVO > 0 ? avgVO : 0,
            verticalOscillationRating: avgVO > 0 ? rateMetricInverse(avgVO, ideal: 8, tolerance: 3) : .average,
            cadence: avgCadence > 0 ? avgCadence : 0,
            cadenceRating: avgCadence > 0 ? rateMetric(avgCadence, ideal: 180, tolerance: 10) : .average,
            improvements: generateFormImprovements(cadence: avgCadence, gct: avgGCT, vo: avgVO)
        )
        
        await MainActor.run {
            self.runningFormScore = analysis
            print("✅ Running form analysis complete: Score \(Int(score))/100")
        }
    }
    
    private func rateMetric(_ value: Double, ideal: Double, tolerance: Double) -> MetricRating {
        let diff = abs(value - ideal)
        if diff < tolerance * 0.5 { return .excellent }
        if diff < tolerance { return .good }
        if diff < tolerance * 1.5 { return .average }
        return .needsWork
    }
    
    private func rateMetricInverse(_ value: Double, ideal: Double, tolerance: Double) -> MetricRating {
        if value < ideal { return .excellent }
        if value < ideal + tolerance * 0.5 { return .good }
        if value < ideal + tolerance { return .average }
        return .needsWork
    }
    
    private func generateFormImprovements(cadence: Double, gct: Double, vo: Double) -> [String] {
        var improvements: [String] = []
        
        if cadence < 170 {
            improvements.append("Increase cadence with shorter, quicker steps")
        }
        if gct > 280 {
            improvements.append("Focus on quick ground contact - imagine running on hot coals")
        }
        if vo > 10 {
            improvements.append("Reduce vertical bounce - run more horizontal")
        }
        
        return improvements
    }
    
    // MARK: - Settings
    /// Update settings - now uses UserProfileManager for centralized data
    func updateSettings(maxHR: Int? = nil, restingHR: Int? = nil, vo2: Double? = nil, weight: Double? = nil, height: Double? = nil, weeklyGoal: Double? = nil) {
        if let maxHR = maxHR { userProfile.setManualMaxHR(maxHR) }
        if let restingHR = restingHR { userProfile.setManualRestingHR(restingHR) }
        if let vo2 = vo2 { userProfile.setManualVO2Max(vo2) }
        if let weight = weight { userProfile.setManualWeight(weight) }
        if let height = height { userProfile.setManualHeight(height) }
        if let weeklyGoal = weeklyGoal { userProfile.setWeeklyRunningGoal(weeklyGoal) }
        
        // Refresh data with new settings
        Task {
            await refreshAllData()
        }
    }
    
    /// Re-sync all settings from HealthKit (clears manual overrides)
    func resyncFromHealthKit() async {
        await userProfile.clearManualOverrides()
        await refreshAllData()
    }
    
    /// Get current user age from profile
    var userAge: Int? {
        userProfile.age
    }
    
    /// Get heart rate zones calculated from user profile
    var heartRateZones: HeartRateZoneBoundaries {
        userProfile.getHeartRateZones()
    }
}

// MARK: - Data Models

struct AdvancedRunData: Identifiable {
    let id: UUID
    let date: Date
    let distance: Double // km
    let duration: Double // seconds
    let pace: Double // seconds per km
    let calories: Double
    
    // Route (decoded from `WorkoutLog.route` if present)
    let routePoints: [RoutePoint]
    
    // Heart Rate
    let avgHeartRate: Int
    let maxHeartRate: Int
    let minHeartRate: Int
    let heartRateZones: [HeartRateZone]
    let heartRateVariability: Double
    
    // Running Dynamics
    let strideLength: Double? // meters
    let groundContactTime: Double? // milliseconds
    let verticalOscillation: Double? // centimeters
    let cadence: Double? // steps per minute
    let runningPower: Double? // watts
    let runningSpeed: Double? // m/s
    
    // Extended Dynamics (best-effort if HealthKit provides them)
    let runningCadenceHK: Double? // steps per minute (HealthKit)
    let stepLength: Double? // meters
    let verticalRatio: Double? // %
    let asymmetryPercentage: Double? // %
    let groundContactTimeBalance: Double? // %
    let doubleSupportPercentage: Double? // % (walking double support; sometimes present)
    let cardioRecovery1Min: Double? // bpm drop in first minute post-workout
    
    // Elevation
    let elevationGain: Double
    let elevationLoss: Double
    let maxAltitude: Double
    let minAltitude: Double
    
    // Splits
    let splits: [RunSplit]
    
    // Analytics
    let runningEconomy: Double
    let trainingStress: Double
    let effortLevel: EffortLevel
    let aerobicEffect: Double
    let anaerobicEffect: Double
    
    // Formatted properties
    var formattedPace: String {
        guard pace > 0 else { return "--:--" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDistance: String {
        return String(format: "%.2f km", distance)
    }
}

struct HeartRateZone: Identifiable {
    let id = UUID()
    let zone: Int
    let name: String
    let minHR: Int
    let maxHR: Int
    let duration: TimeInterval
    let percentage: Double
    let color: String
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    static var defaultZones: [HeartRateZone] {
        [
            HeartRateZone(zone: 1, name: "Recovery", minHR: 60, maxHR: 114, duration: 0, percentage: 0, color: "6EE7B7"),
            HeartRateZone(zone: 2, name: "Aerobic Base", minHR: 114, maxHR: 133, duration: 0, percentage: 0, color: "34D399"),
            HeartRateZone(zone: 3, name: "Tempo", minHR: 133, maxHR: 152, duration: 0, percentage: 0, color: "FBBF24"),
            HeartRateZone(zone: 4, name: "Threshold", minHR: 152, maxHR: 171, duration: 0, percentage: 0, color: "F97316"),
            HeartRateZone(zone: 5, name: "VO2 Max", minHR: 171, maxHR: 190, duration: 0, percentage: 0, color: "EF4444")
        ]
    }
}

struct RunSplit: Identifiable {
    let id = UUID()
    let kilometer: Int
    let duration: Double // seconds for this km
    let pace: Double // seconds per km
    let heartRate: Int
    let cadence: Int
    let elevationGain: Double
    let elevationLoss: Double
    let isPartialSplit: Bool
    let partialDistance: Double?
    
    var formattedPace: String {
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum EffortLevel: String, CaseIterable {
    case recovery = "Recovery"
    case easy = "Easy"
    case moderate = "Moderate"
    case tempo = "Tempo"
    case threshold = "Threshold"
    case maxEffort = "Max Effort"
    
    var color: String {
        switch self {
        case .recovery: return "6EE7B7"
        case .easy: return "34D399"
        case .moderate: return "FBBF24"
        case .tempo: return "F97316"
        case .threshold: return "EF4444"
        case .maxEffort: return "DC2626"
        }
    }
    
    var icon: String {
        switch self {
        case .recovery: return "bed.double.fill"
        case .easy: return "figure.walk"
        case .moderate: return "figure.run"
        case .tempo: return "flame"
        case .threshold: return "flame.fill"
        case .maxEffort: return "bolt.fill"
        }
    }
}

struct WeeklyRunningAnalytics {
    let totalRuns: Int
    let totalDistance: Double
    let totalDuration: Double
    let totalCalories: Double
    let totalElevation: Double
    let averagePace: Double
    let averageHeartRate: Int
    let longestRun: Double
    let fastestPace: Double
    let trainingStressTotal: Double
    let dailyDistances: [Double]
    let workoutTypeDistribution: [EffortLevel: Int]
    let weeklyGoalProgress: Double
    
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        return "\(hours)h \(minutes)m"
    }
    
    var formattedPace: String {
        guard averagePace > 0 else { return "--:--" }
        let minutes = Int(averagePace) / 60
        let seconds = Int(averagePace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct MonthlyRunningAnalytics {
    let totalRuns: Int
    let totalDistance: Double
    let totalDuration: Double
    let totalCalories: Double
    let averagePace: Double
    let weeklyTotals: [Double]
    let distanceTrend: Double // percentage change from previous month
    let consistencyScore: Double
    
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        return "\(hours)h \(minutes)m"
    }
}

struct TrainingLoadAnalysis {
    let acuteLoad: Double // Last 7 days
    let chronicLoad: Double // Last 28 days average
    let trainingBalance: Double // Fitness - Fatigue
    let acuteChronicRatio: Double
    let status: TrainingStatus
    let recommendation: String
}

enum TrainingStatus: String {
    case undertraining = "Undertraining"
    case optimal = "Optimal"
    case overreaching = "Overreaching"
    case overtraining = "Overtraining"
    
    var color: String {
        switch self {
        case .undertraining: return "3B82F6"
        case .optimal: return "10B981"
        case .overreaching: return "F59E0B"
        case .overtraining: return "EF4444"
        }
    }
}

struct RunnerFitnessProfile {
    let vo2MaxEstimate: Double
    let runningAge: Int
    let fitnessLevel: RunningFitnessLevel
    let strengths: [RunnerStrength]
    let weeklyMileage: Double
    let longestRunEver: Double
}

enum RunningFitnessLevel: String {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case competitive = "Competitive"
    case elite = "Elite"
    
    var color: String {
        switch self {
        case .beginner: return "6EE7B7"
        case .intermediate: return "34D399"
        case .advanced: return "3B82F6"
        case .competitive: return "8B5CF6"
        case .elite: return "F59E0B"
        }
    }
}

enum RunnerStrength: String {
    case endurance = "Endurance"
    case speed = "Speed"
    case cadence = "Cadence"
    case hills = "Hills"
    case consistency = "Consistency"
}

struct RacePredictions {
    let oneK: Double
    let fiveK: Double
    let tenK: Double
    let halfMarathon: Double
    let marathon: Double
    let basedOnDistance: Double
    let basedOnTime: Double
    let confidence: Double
    
    func formattedTime(_ time: Double) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PersonalBest: Identifiable {
    let id = UUID()
    let distance: Double
    let distanceName: String
    let time: Double
    let pace: Double
    let date: Date
    let heartRate: Int
    var actualDistance: Double? = nil // The actual distance run (may differ from target distance)
    var isEstimated: Bool = false // Whether this is an estimated time based on a longer run
    
    var formattedTime: String {
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedPace: String {
        guard pace > 0 else { return "--:--" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Display name with estimated indicator if applicable
    var displayName: String {
        if isEstimated {
            return "\(distanceName)*"
        }
        return distanceName
    }
}

struct RunningFormAnalysis {
    let overallScore: Double
    let strideLength: Double
    let strideLengthRating: MetricRating
    let groundContactTime: Double
    let groundContactRating: MetricRating
    let verticalOscillation: Double
    let verticalOscillationRating: MetricRating
    let cadence: Double
    let cadenceRating: MetricRating
    let improvements: [String]
}

enum MetricRating: String {
    case excellent = "Excellent"
    case good = "Good"
    case average = "Average"
    case needsWork = "Needs Work"
    
    var color: String {
        switch self {
        case .excellent: return "10B981"
        case .good: return "34D399"
        case .average: return "FBBF24"
        case .needsWork: return "EF4444"
        }
    }
}

