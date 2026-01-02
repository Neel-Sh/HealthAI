import Foundation
import HealthKit
import Combine

/// Centralized manager for user profile data that synchronizes with HealthKit
/// This ensures age, weight, height, and derived values (like max heart rate) are accurate across the app
@MainActor
class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    
    private let healthStore = HKHealthStore()
    
    // MARK: - Published Properties (Observable across the app)
    
    // User characteristics from HealthKit
    @Published var age: Int?
    @Published var biologicalSex: HKBiologicalSex = .notSet
    @Published var height: Double? // in cm
    @Published var weight: Double? // in kg
    @Published var dateOfBirth: Date?
    
    // Health metrics from HealthKit
    @Published var restingHeartRate: Int?
    @Published var vo2Max: Double?
    
    // Derived values
    @Published var maxHeartRate: Int = 190
    @Published var bmi: Double?
    @Published var heartRateReserve: Int?
    
    // Sync status
    @Published var lastSyncDate: Date?
    @Published var isLoaded: Bool = false
    
    // User defaults for manual overrides
    private let defaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let manualMaxHR = "userProfile_manualMaxHR"
        static let manualRestingHR = "userProfile_manualRestingHR"
        static let manualVO2Max = "userProfile_manualVO2Max"
        static let manualWeight = "userProfile_manualWeight"
        static let manualHeight = "userProfile_manualHeight"
        static let manualAge = "userProfile_manualAge"
        static let weeklyGoalKm = "userProfile_weeklyGoalKm"
        static let stepGoal = "userProfile_stepGoal"
        static let calorieGoal = "userProfile_calorieGoal"
        static let sleepGoal = "userProfile_sleepGoal"
    }
    
    // MARK: - Goals
    @Published var weeklyRunningGoalKm: Double = 30.0
    @Published var dailyStepGoal: Int = 10000
    @Published var dailyCalorieGoal: Double = 500.0
    @Published var sleepGoalHours: Double = 8.0
    
    private init() {
        loadCachedValues()
    }
    
    // MARK: - Load Cached Values from UserDefaults
    private func loadCachedValues() {
        // Load manual overrides if set
        if let manualAge = defaults.object(forKey: Keys.manualAge) as? Int, manualAge > 0 {
            self.age = manualAge
            self.maxHeartRate = calculateMaxHeartRate(age: manualAge)
        }
        
        if let manualWeight = defaults.object(forKey: Keys.manualWeight) as? Double, manualWeight > 0 {
            self.weight = manualWeight
        }
        
        if let manualHeight = defaults.object(forKey: Keys.manualHeight) as? Double, manualHeight > 0 {
            self.height = manualHeight
        }
        
        if let manualMaxHR = defaults.object(forKey: Keys.manualMaxHR) as? Int, manualMaxHR > 0 {
            self.maxHeartRate = manualMaxHR
        }
        
        if let manualRestingHR = defaults.object(forKey: Keys.manualRestingHR) as? Int, manualRestingHR > 0 {
            self.restingHeartRate = manualRestingHR
        }
        
        if let manualVO2Max = defaults.object(forKey: Keys.manualVO2Max) as? Double, manualVO2Max > 0 {
            self.vo2Max = manualVO2Max
        }
        
        // Load goals
        if let weeklyGoal = defaults.object(forKey: Keys.weeklyGoalKm) as? Double, weeklyGoal > 0 {
            self.weeklyRunningGoalKm = weeklyGoal
        }
        
        if let stepGoal = defaults.object(forKey: Keys.stepGoal) as? Int, stepGoal > 0 {
            self.dailyStepGoal = stepGoal
        }
        
        if let calorieGoal = defaults.object(forKey: Keys.calorieGoal) as? Double, calorieGoal > 0 {
            self.dailyCalorieGoal = calorieGoal
        }
        
        if let sleepGoal = defaults.object(forKey: Keys.sleepGoal) as? Double, sleepGoal > 0 {
            self.sleepGoalHours = sleepGoal
        }
        
        // Calculate BMI if we have height and weight
        updateDerivedValues()
    }
    
    // MARK: - Sync from HealthKit
    
    /// Sync all user profile data from HealthKit
    @MainActor
    func syncFromHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("⚠️ HealthKit not available for profile sync")
            isLoaded = true
            return
        }
        
        print("🔄 Syncing user profile from HealthKit...")
        
        // Fetch all profile data in parallel
        async let fetchedAge = fetchAge()
        async let fetchedSex = fetchBiologicalSex()
        async let fetchedHeight = fetchHeight()
        async let fetchedWeight = fetchWeight()
        async let fetchedRestingHR = fetchRestingHeartRate()
        async let fetchedVO2Max = fetchVO2Max()
        
        let (ageResult, sexResult, heightResult, weightResult, restingHRResult, vo2MaxResult) = await (
            fetchedAge, fetchedSex, fetchedHeight, fetchedWeight, fetchedRestingHR, fetchedVO2Max
        )
        
        // Update published properties if we got data from HealthKit
        // Only update if we don't have a manual override
        
        if let newAge = ageResult, defaults.object(forKey: Keys.manualAge) == nil {
            self.age = newAge
            self.maxHeartRate = calculateMaxHeartRate(age: newAge)
            print("📊 Age from HealthKit: \(newAge) → Max HR: \(self.maxHeartRate)")
        }
        
        if sexResult != .notSet {
            self.biologicalSex = sexResult
            print("📊 Biological Sex from HealthKit: \(sexResult.rawValue)")
        }
        
        if let newHeight = heightResult, defaults.object(forKey: Keys.manualHeight) == nil {
            self.height = newHeight
            print("📊 Height from HealthKit: \(newHeight) cm")
        }
        
        if let newWeight = weightResult, defaults.object(forKey: Keys.manualWeight) == nil {
            self.weight = newWeight
            print("📊 Weight from HealthKit: \(newWeight) kg")
        }
        
        if let newRestingHR = restingHRResult, defaults.object(forKey: Keys.manualRestingHR) == nil {
            self.restingHeartRate = newRestingHR
            print("📊 Resting HR from HealthKit: \(newRestingHR) bpm")
        }
        
        if let newVO2Max = vo2MaxResult, defaults.object(forKey: Keys.manualVO2Max) == nil {
            self.vo2Max = newVO2Max
            print("📊 VO2 Max from HealthKit: \(newVO2Max) ml/kg/min")
        }
        
        updateDerivedValues()
        lastSyncDate = Date()
        isLoaded = true
        
        print("✅ User profile sync complete")
    }
    
    // MARK: - HealthKit Fetch Methods
    
    private func fetchAge() async -> Int? {
        do {
            let components = try healthStore.dateOfBirthComponents()
            guard let dob = components.date else { return nil }
            // dateOfBirth update is handled in syncFromHealthKit on MainActor
            let ageComponents = Calendar.current.dateComponents([.year], from: dob, to: Date())
            return ageComponents.year
        } catch {
            print("❌ Error fetching age: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func fetchBiologicalSex() async -> HKBiologicalSex {
        do {
            let sex = try healthStore.biologicalSex()
            return sex.biologicalSex
        } catch {
            print("❌ Error fetching biological sex: \(error.localizedDescription)")
            return .notSet
        }
    }
    
    private func fetchHeight() async -> Double? {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else { return nil }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    let heightCm = sample.quantity.doubleValue(for: .meter()) * 100
                    continuation.resume(returning: heightCm)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchWeight() async -> Double? {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    let weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    continuation.resume(returning: weightKg)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchRestingHeartRate() async -> Int? {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        
        // Get the most recent resting heart rate from the last 7 days
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: Date())
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingHRType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    let hr = Int(sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())))
                    continuation.resume(returning: hr)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchVO2Max() async -> Double? {
        guard let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: vo2MaxType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    // VO2 Max is measured in mL/(kg·min)
                    let vo2Max = sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())))
                    continuation.resume(returning: vo2Max)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Derived Value Calculations
    
    private func updateDerivedValues() {
        // Calculate BMI
        if let height = height, let weight = weight, height > 0 {
            let heightMeters = height / 100
            self.bmi = weight / (heightMeters * heightMeters)
        }
        
        // Calculate heart rate reserve
        if let restingHR = restingHeartRate {
            self.heartRateReserve = maxHeartRate - restingHR
        }
        
        // Update max heart rate from age if not manually set
        if let age = age, defaults.object(forKey: Keys.manualMaxHR) == nil {
            self.maxHeartRate = calculateMaxHeartRate(age: age)
        }
    }
    
    /// Calculate max heart rate using the Tanaka formula (more accurate than 220-age)
    /// Formula: 208 - (0.7 × age)
    func calculateMaxHeartRate(age: Int) -> Int {
        let maxHR = 208 - Int(0.7 * Double(age))
        return max(150, min(220, maxHR)) // Clamp to reasonable range
    }
    
    // MARK: - Heart Rate Zone Calculations
    
    /// Get heart rate zone boundaries based on user's profile
    func getHeartRateZones() -> HeartRateZoneBoundaries {
        let restingHR = restingHeartRate ?? 60
        let maxHR = maxHeartRate
        let reserve = maxHR - restingHR
        
        // Using Karvonen method (Heart Rate Reserve)
        return HeartRateZoneBoundaries(
            zone1Max: restingHR + Int(Double(reserve) * 0.50), // Recovery: 50% HRR
            zone2Max: restingHR + Int(Double(reserve) * 0.60), // Easy: 60% HRR
            zone3Max: restingHR + Int(Double(reserve) * 0.70), // Aerobic: 70% HRR
            zone4Max: restingHR + Int(Double(reserve) * 0.80), // Threshold: 80% HRR
            zone5Max: restingHR + Int(Double(reserve) * 0.90), // VO2 Max: 90% HRR
            maxHR: maxHR
        )
    }
    
    // MARK: - Manual Settings
    
    func setManualAge(_ age: Int) {
        self.age = age
        defaults.set(age, forKey: Keys.manualAge)
        self.maxHeartRate = calculateMaxHeartRate(age: age)
        updateDerivedValues()
    }
    
    func setManualWeight(_ weight: Double) {
        self.weight = weight
        defaults.set(weight, forKey: Keys.manualWeight)
        updateDerivedValues()
    }
    
    func setManualHeight(_ height: Double) {
        self.height = height
        defaults.set(height, forKey: Keys.manualHeight)
        updateDerivedValues()
    }
    
    func setManualMaxHR(_ maxHR: Int) {
        self.maxHeartRate = maxHR
        defaults.set(maxHR, forKey: Keys.manualMaxHR)
        updateDerivedValues()
    }
    
    func setManualRestingHR(_ restingHR: Int) {
        self.restingHeartRate = restingHR
        defaults.set(restingHR, forKey: Keys.manualRestingHR)
        updateDerivedValues()
    }
    
    func setManualVO2Max(_ vo2Max: Double) {
        self.vo2Max = vo2Max
        defaults.set(vo2Max, forKey: Keys.manualVO2Max)
    }
    
    func setWeeklyRunningGoal(_ km: Double) {
        self.weeklyRunningGoalKm = km
        defaults.set(km, forKey: Keys.weeklyGoalKm)
    }
    
    func setDailyStepGoal(_ steps: Int) {
        self.dailyStepGoal = steps
        defaults.set(steps, forKey: Keys.stepGoal)
    }
    
    func setDailyCalorieGoal(_ calories: Double) {
        self.dailyCalorieGoal = calories
        defaults.set(calories, forKey: Keys.calorieGoal)
    }
    
    func setSleepGoal(_ hours: Double) {
        self.sleepGoalHours = hours
        defaults.set(hours, forKey: Keys.sleepGoal)
    }
    
    /// Clear manual overrides and resync from HealthKit
    func clearManualOverrides() async {
        defaults.removeObject(forKey: Keys.manualAge)
        defaults.removeObject(forKey: Keys.manualMaxHR)
        defaults.removeObject(forKey: Keys.manualRestingHR)
        defaults.removeObject(forKey: Keys.manualVO2Max)
        defaults.removeObject(forKey: Keys.manualWeight)
        defaults.removeObject(forKey: Keys.manualHeight)
        
        await syncFromHealthKit()
    }
    
    // MARK: - Display Helpers
    
    var displayAge: String {
        if let age = age {
            return "\(age) years"
        }
        return "Not set"
    }
    
    var displayWeight: String {
        if let weight = weight {
            return String(format: "%.1f kg", weight)
        }
        return "Not set"
    }
    
    var displayHeight: String {
        if let height = height {
            let feet = Int(height / 30.48)
            let inches = Int((height / 2.54).truncatingRemainder(dividingBy: 12))
            return "\(Int(height)) cm (\(feet)'\(inches)\")"
        }
        return "Not set"
    }
    
    var displayBMI: String {
        if let bmi = bmi {
            return String(format: "%.1f", bmi)
        }
        return "N/A"
    }
    
    var bmiCategory: String {
        guard let bmi = bmi else { return "Unknown" }
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }
    
    var genderString: String {
        switch biologicalSex {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        default: return "Not set"
        }
    }
    
    var isProfileComplete: Bool {
        return age != nil && height != nil && weight != nil
    }
}

// MARK: - Heart Rate Zone Model

struct HeartRateZoneBoundaries {
    let zone1Max: Int // Recovery
    let zone2Max: Int // Easy
    let zone3Max: Int // Aerobic
    let zone4Max: Int // Threshold
    let zone5Max: Int // VO2 Max
    let maxHR: Int
    
    func zoneFor(heartRate: Int) -> Int {
        switch heartRate {
        case ..<zone1Max: return 1
        case zone1Max..<zone2Max: return 2
        case zone2Max..<zone3Max: return 3
        case zone3Max..<zone4Max: return 4
        case zone4Max..<zone5Max: return 5
        default: return 5
        }
    }
    
    func zoneName(for zone: Int) -> String {
        switch zone {
        case 1: return "Recovery"
        case 2: return "Easy"
        case 3: return "Aerobic"
        case 4: return "Threshold"
        case 5: return "VO2 Max"
        default: return "Unknown"
        }
    }
    
    func zoneColor(for zone: Int) -> String {
        switch zone {
        case 1: return "6EE7B7" // Light green
        case 2: return "34D399" // Green
        case 3: return "FBBF24" // Yellow
        case 4: return "F97316" // Orange
        case 5: return "EF4444" // Red
        default: return "9CA3AF" // Gray
        }
    }
}

