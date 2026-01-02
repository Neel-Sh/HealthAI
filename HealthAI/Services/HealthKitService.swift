import Foundation
import HealthKit
import CoreData
import CoreLocation

@MainActor
class HealthKitService: ObservableObject {
    private let healthStore = HKHealthStore()
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var lastSyncDate: Date?
    private var isSyncing = false
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        self.backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        self.backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        Task { 
            await checkAuthorizationStatus()
            // Sync user profile data on init
            await UserProfileManager.shared.syncFromHealthKit()
        }
        setupBackgroundSync()
    }
    
    // MARK: - Authorization
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { 
            print("❌ HealthKit is not available on this device")
            return 
        }
        
        print("🔑 Requesting HealthKit authorization...")
        
        var typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        ]

        // Workout routes (maps)
        // Note: some SDKs define HKSeriesTypeIdentifier as String (no `.workoutRoute` static),
        // so we use the global identifier constant.
        if let routeType = HKObjectType.seriesType(forIdentifier: HKWorkoutRouteTypeIdentifier) {
            typesToRead.insert(routeType)
        }
        
        // Add running metrics if available on this OS/device
        if let type = HKObjectType.quantityType(forIdentifier: .runningStrideLength) { typesToRead.insert(type) }
        if let type = HKObjectType.quantityType(forIdentifier: .runningGroundContactTime) { typesToRead.insert(type) }
        if let type = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation) { typesToRead.insert(type) }
        if let type = HKObjectType.quantityType(forIdentifier: .runningPower) { typesToRead.insert(type) }
        if let type = HKObjectType.quantityType(forIdentifier: .runningSpeed) { typesToRead.insert(type) }
        
        // Extended running dynamics + related metrics (added by raw identifier so we can gracefully support older/newer SDKs)
        let extraQuantityTypeRawIDs: [String] = [
            "HKQuantityTypeIdentifierRunningCadence",
            "HKQuantityTypeIdentifierRunningStepLength",
            "HKQuantityTypeIdentifierRunningVerticalRatio",
            "HKQuantityTypeIdentifierRunningAsymmetryPercentage",
            "HKQuantityTypeIdentifierRunningGroundContactTimeBalance",
            // Often shown as “double support time” in Fitness. This is a walking metric but can be present for runs on some devices.
            "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage"
        ]
        
        for raw in extraQuantityTypeRawIDs {
            let id = HKQuantityTypeIdentifier(rawValue: raw)
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                typesToRead.insert(type)
            }
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            print("✅ HealthKit authorization request completed")
            
            // Give the system time to update authorization status
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            await checkAuthorizationStatus()
        } catch {
            print("❌ HealthKit authorization error: \(error.localizedDescription)")
        }
    }
    
    private func checkAuthorizationStatus() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run {
                authorizationStatus = .notDetermined
                print("❌ HealthKit not available, status: notDetermined")
            }
            return
        }
        
        let types: Set = [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning)
        ]
        
        do {
            _ = try await healthStore.preferredUnits(for: types)
            await MainActor.run {
                authorizationStatus = .sharingAuthorized  // Using to indicate read authorized
                print("✅ HealthKit read authorization: GRANTED")
            }
        } catch {
            await MainActor.run {
                if let hkError = error as? HKError, hkError.code == .errorAuthorizationDenied {
                    authorizationStatus = .sharingDenied
                    print("❌ HealthKit read authorization: DENIED - user has denied access")
                } else {
                    authorizationStatus = .notDetermined
                    print("⚠️ HealthKit read authorization: NOT DETERMINED - need to request permission")
                }
            }
        }
    }

    // MARK: - Running Mobility Metrics (on-demand, not persisted)
    /// Fetch most recent quantity for a HealthKit identifier with unit
    func fetchMostRecentQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: sample.quantity.doubleValue(for: unit))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            self.healthStore.execute(query)
        }
    }

    // Convenience wrappers for running metrics
    func getLatestRunningStrideLengthMeters() async -> Double? {
        await fetchMostRecentQuantity(for: .runningStrideLength, unit: .meter())
    }

    func getLatestRunningCadenceSpm() async -> Double? {
        // HealthKit does not offer a direct running cadence quantity identifier.
        // Approximate cadence as speed / strideLength (both most recent), then convert to steps per minute.
        async let speedMps = getLatestRunningSpeedMetersPerSecond()
        async let strideMeters = getLatestRunningStrideLengthMeters()
        let (speed, stride) = await (speedMps, strideMeters)
        guard let s = speed, let l = stride, s > 0, l > 0 else { return nil }
        // Cadence (steps/min) = (meters/second) / (meters/step) * 60
        return (s / l) * 60.0
    }

    func getLatestRunningGroundContactMs() async -> Double? {
        await fetchMostRecentQuantity(for: .runningGroundContactTime, unit: .secondUnit(with: .milli))
    }

    func getLatestRunningVerticalOscillationCm() async -> Double? {
        await fetchMostRecentQuantity(for: .runningVerticalOscillation, unit: .meterUnit(with: .centi))
    }

    func getLatestRunningPowerWatts() async -> Double? {
        await fetchMostRecentQuantity(for: .runningPower, unit: .watt())
    }

    func getLatestRunningSpeedMetersPerSecond() async -> Double? {
        await fetchMostRecentQuantity(for: .runningSpeed, unit: .meter().unitDivided(by: .second()))
    }
    
    private func statusName(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .sharingDenied: return "sharingDenied"
        case .sharingAuthorized: return "sharingAuthorized"
        @unknown default: return "unknown"
        }
    }
    
    // Helper method to check if we have sufficient authorization
    func hasValidAuthorization() -> Bool {
        return authorizationStatus == .sharingAuthorized
    }
    
    // Method to force re-check authorization
    func recheckAuthorization() async {
        print("🔄 Forcing authorization re-check...")
        await checkAuthorizationStatus()
    }
    
    // Method to force refresh authorization with delay
    func refreshAuthorizationStatus() async {
        print("🔄 Refreshing authorization status...")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        await checkAuthorizationStatus()
    }
    
    // MARK: - Background Sync
    private func setupBackgroundSync() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        // Set up background sync for workouts
        let workoutType = HKObjectType.workoutType()
        let workoutQuery = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, _, error in
            if let error = error {
                print("Error in workout observer: \(error.localizedDescription)")
                return
            }
            
            print("New workout detected, syncing...")
            guard let self = self, !self.isSyncing else { return }
            Task {
                await self.syncWorkouts()
                await self.syncHealthMetrics()
            }
        }
        
        healthStore.execute(workoutQuery)
        
        // Set up background sync for health metrics
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            let stepQuery = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, _, error in
                if let error = error {
                    print("Error in step observer: \(error.localizedDescription)")
                    return
                }
                
                print("New step data detected, syncing health metrics...")
                guard let self = self, !self.isSyncing else { return }
                Task {
                    await self.syncHealthMetrics()
                }
            }
            
            healthStore.execute(stepQuery)
        }
        
        // Set up background sync for active energy (calories)
        if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let activeEnergyQuery = HKObserverQuery(sampleType: activeEnergyType, predicate: nil) { [weak self] _, _, error in
                if let error = error {
                    print("Error in active energy observer: \(error.localizedDescription)")
                    return
                }
                
                print("New active energy data detected, syncing active calories...")
                guard let self = self, !self.isSyncing else { return }
                Task {
                    await self.syncTodaysActiveCalories()
                }
            }
            
            healthStore.execute(activeEnergyQuery)
            
            // Enable background delivery for active energy
            healthStore.enableBackgroundDelivery(for: activeEnergyType, frequency: .immediate) { success, error in
                if let error = error {
                    print("Error enabling background delivery for active energy: \(error.localizedDescription)")
                } else if success {
                    print("Background delivery enabled for active energy")
                }
            }
        }
        
        // Enable background delivery for workouts
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            if let error = error {
                print("Error enabling background delivery for workouts: \(error.localizedDescription)")
            } else if success {
                print("Background delivery enabled for workouts")
            }
        }
        
        if let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) {
            let basalQuery = HKObserverQuery(sampleType: basalEnergyType, predicate: nil) { [weak self] _, _, error in
                // Similar to active energy
                Task {
                    await self?.syncTodaysBasalCalories()
                }
            }
            healthStore.execute(basalQuery)
            healthStore.enableBackgroundDelivery(for: basalEnergyType, frequency: .immediate) { _, _ in }
        }
    }
    
    // MARK: - Workout Sync
    func syncWorkouts() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await checkAuthorizationStatus()  // Add this to ensure latest status
        guard authorizationStatus == .sharingAuthorized || authorizationStatus == .notDetermined else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        let workoutType = HKObjectType.workoutType()
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: getWorkoutPredicate(),
            limit: 100,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error fetching workouts: \(error.localizedDescription)")
                Task {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
                return
            }
            
            let workouts = samples as? [HKWorkout] ?? []
            print("Fetched \(workouts.count) workouts from HealthKit")
            
            Task {
                await self.processWorkouts(workouts)
                await MainActor.run {
                    self.isLoading = false
                    self.lastSyncDate = Date()
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    // Sync all workouts from the last 7 days for quick updates
    func syncRecentWorkouts() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await checkAuthorizationStatus()  // Add this to ensure latest status
        guard authorizationStatus == .sharingAuthorized || authorizationStatus == .notDetermined else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        let workoutType = HKObjectType.workoutType()
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentPredicate = HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: Date())
        
        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: recentPredicate,
            limit: 100,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error fetching recent workouts: \(error.localizedDescription)")
                Task {
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
                return
            }
            
            let workouts = samples as? [HKWorkout] ?? []
            print("Fetched \(workouts.count) recent workouts from HealthKit")
            
            Task {
                await self.processWorkouts(workouts)
                await MainActor.run {
                    self.isLoading = false
                    self.lastSyncDate = Date()
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    private func getWorkoutPredicate() -> NSPredicate? {
        // Sync workouts from the last 90 days to get more comprehensive data
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return HKQuery.predicateForSamples(withStart: ninetyDaysAgo, end: Date())
    }
    
    private func processWorkouts(_ workouts: [HKWorkout]) async {
        // 1) Insert new workouts (fast Core Data writes)
        let uuidsNeedingEnrichment: Set<String> = await backgroundContext.perform {
            var needsEnrichment = Set<String>()
            
            for workout in workouts {
                let uuid = workout.uuid.uuidString
                
                // Check if workout already exists
                if self.workoutExistsSync(healthKitUUID: uuid, in: self.backgroundContext) {
                    // Backfill route/metrics for existing workouts if missing
                    let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
                    request.predicate = NSPredicate(format: "healthKitUUID == %@", uuid)
                    request.fetchLimit = 1
                    if let existing = (try? self.backgroundContext.fetch(request))?.first {
                        if existing.route == nil || existing.avgHeartRate == 0 || existing.maxHeartRate == 0 {
                            needsEnrichment.insert(uuid)
                        }
                    }
                    continue
                }
                
                // Create new workout log
                let workoutLog = WorkoutLog(context: self.backgroundContext)
                workoutLog.id = UUID()
                workoutLog.healthKitUUID = uuid
                workoutLog.isFromHealthKit = true
                workoutLog.timestamp = workout.startDate
                workoutLog.duration = workout.duration
                workoutLog.workoutType = self.mapWorkoutType(workout.workoutActivityType)
                
                // Distance
                if let distance = workout.totalDistance {
                    workoutLog.distance = distance.doubleValue(for: .meter()) / 1000.0 // km
                }
                
                // Calories
                if let energy = workout.totalEnergyBurned {
                    workoutLog.calories = energy.doubleValue(for: .kilocalorie())
                }
                
                // Pace (seconds per km)
                if workoutLog.distance > 0 && workoutLog.duration > 0 {
                    workoutLog.pace = workoutLog.duration / workoutLog.distance
                }
                
                needsEnrichment.insert(uuid)
            }
            
            do {
                try self.backgroundContext.save()
            } catch {
                print("Error saving workouts: \(error)")
            }
            
            return needsEnrichment
        }
        
        // 2) Enrich workouts with metrics + route (slower HealthKit reads)
        let workoutsToEnrich = workouts.filter { uuidsNeedingEnrichment.contains($0.uuid.uuidString) }
        guard !workoutsToEnrich.isEmpty else { return }
        
        var metricsByUUID: [String: WorkoutMetricsResult] = [:]
        for workout in workoutsToEnrich {
            metricsByUUID[workout.uuid.uuidString] = await fetchWorkoutMetrics(for: workout)
        }
        
        await backgroundContext.perform {
            for (uuid, result) in metricsByUUID {
                let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
                request.predicate = NSPredicate(format: "healthKitUUID == %@", uuid)
                request.fetchLimit = 1
                
                guard let workoutLog = (try? self.backgroundContext.fetch(request))?.first else { continue }
                
                if let avg = result.avgHeartRate { workoutLog.avgHeartRate = avg }
                if let max = result.maxHeartRate { workoutLog.maxHeartRate = max }
                if let elevationGain = result.elevationGain { workoutLog.elevation = elevationGain }
                if let routeData = result.routeData { workoutLog.route = routeData }
            }
            
            do {
                try self.backgroundContext.save()
            } catch {
                print("Error saving workout enrichments: \(error)")
            }
        }
    }
    
    private func workoutExistsSync(healthKitUUID: String, in context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        request.predicate = NSPredicate(format: "healthKitUUID == %@", healthKitUUID)
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            return false
        }
    }
    
    // MARK: - Workout Enrichment (route + HR stats)
    
    private struct WorkoutMetricsResult {
        let avgHeartRate: Int16?
        let maxHeartRate: Int16?
        let elevationGain: Double?
        let routeData: Data?
    }
    
    private func fetchWorkoutMetrics(for workout: HKWorkout) async -> WorkoutMetricsResult {
        async let hrStats = fetchHeartRateStats(for: workout)
        async let routePoints = fetchRoutePoints(for: workout)
        
        let (stats, points) = await (hrStats, routePoints)
        
        // Elevation gain from route altitudes (if present)
        let elevationGain = points.flatMap { computeElevationGain(from: $0) }
        
        return WorkoutMetricsResult(
            avgHeartRate: stats?.avg,
            maxHeartRate: stats?.max,
            elevationGain: elevationGain,
            routeData: RouteCoding.encode(points ?? [])
        )
    }
    
    private func fetchHeartRateStats(for workout: HKWorkout) async -> (avg: Int16, max: Int16)? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, statistics, _ in
                guard let statistics else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let unit = HKUnit.count().unitDivided(by: .minute())
                let avg = statistics.averageQuantity()?.doubleValue(for: unit)
                let max = statistics.maximumQuantity()?.doubleValue(for: unit)
                
                guard let avg, let max else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: (avg: Int16(avg.rounded()), max: Int16(max.rounded())))
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchRoutePoints(for workout: HKWorkout) async -> [RoutePoint]? {
        guard let routeType = HKObjectType.seriesType(forIdentifier: HKWorkoutRouteTypeIdentifier) as? HKSeriesType else {
            return nil
        }
        
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            healthStore.execute(query)
        }
        
        guard !routes.isEmpty else { return nil }
        
        var allPoints: [RoutePoint] = []
        for route in routes {
            let points: [RoutePoint] = await withCheckedContinuation { continuation in
                var collected: [RoutePoint] = []
                let query = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                    if let locations {
                        collected.append(contentsOf: locations.map {
                            RoutePoint(
                                latitude: $0.coordinate.latitude,
                                longitude: $0.coordinate.longitude,
                                altitudeMeters: $0.verticalAccuracy >= 0 ? $0.altitude : nil,
                                timestamp: $0.timestamp
                            )
                        })
                    }
                    if done {
                        continuation.resume(returning: collected)
                    }
                }
                healthStore.execute(query)
            }
            
            allPoints.append(contentsOf: points)
        }
        
        return allPoints.isEmpty ? nil : allPoints
    }
    
    private func computeElevationGain(from points: [RoutePoint]) -> Double? {
        let alts = points.compactMap { $0.altitudeMeters }
        guard alts.count >= 2 else { return nil }
        
        var gain: Double = 0
        for i in 1..<alts.count {
            let delta = alts[i] - alts[i - 1]
            if delta > 0 { gain += delta }
        }
        return gain
    }
    
    private func mapWorkoutType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "run"
        case .walking: return "walk"
        case .cycling: return "bike"
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .swimming: return "swim"
        case .rowing: return "row"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stairs"
        case .dance: return "dance"
        case .boxing: return "boxing"
        case .tennis: return "tennis"
        case .golf: return "golf"
        case .hiking: return "hike"
        case .snowboarding: return "snowboard"
        case .climbing: return "climb"
        case .gymnastics: return "gymnastics"
        case .martialArts: return "martial_arts"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
        case .volleyball: return "volleyball"
        case .americanFootball: return "football"
        case .baseball: return "baseball"
        case .hockey: return "hockey"
        default: return "other"
        }
    }
    
    // MARK: - Health Metrics Sync
    
    // Lightweight sync for frequent updates - only syncs most recent data
    func syncRecentHealthMetrics() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        await MainActor.run {
            isLoading = true
        }
        
        await checkAuthorizationStatus()
        guard authorizationStatus == .sharingAuthorized else { 
            await MainActor.run {
                isLoading = false
            }
            return 
        }
        
        // Sync all health vitals for real-time updates
        await syncStepCount()
        await syncActiveCalories()
        await syncActiveMinutes()
        await syncBasalCalories()
        await syncRestingHeartRate()
        await syncDetailedHeartRate() // Add detailed heart rate sync
        await syncHRV()
        await syncVO2Max()
        await syncSleepData()
        
        await MainActor.run {
            lastSyncDate = Date()
            isLoading = false
        }
    }
    
    func syncHealthMetrics() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        print("🔄 syncHealthMetrics called with authorization status: \(authorizationStatus.rawValue)")
        
        // Check authorization first
        await checkAuthorizationStatus()
        
        guard authorizationStatus == .sharingAuthorized else {
            if authorizationStatus == .notDetermined {
                print("⚠️ HealthKit authorization not determined. Please grant permission in Settings > Privacy & Security > Health > HealthAI")
            } else {
                print("❌ HealthKit access denied. Please enable in Settings > Privacy & Security > Health > HealthAI")
            }
            return
        }
        
        print("🚀 Starting health metrics sync...")
        await syncStepCount()
        await syncWorkoutCount()
        await syncDistanceWalked()
        await syncActiveCalories()
        await syncActiveMinutes()
        await syncBasalCalories()
        await syncRestingHeartRate()
        await syncDetailedHeartRate() // Add detailed heart rate sync
        await syncHRV()
        await syncVO2Max()
        await syncBloodOxygen()
        await syncRespiratoryRate()
        await syncSleepData()
        await syncBodyWeight()
        await syncBasalCalories() // Add basal calories sync
        print("✅ Health metrics sync completed")
    }
    
    private func syncWorkoutCount() async {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
        
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: today, end: tomorrow)
        
        let workoutCount = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 100,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    print("Error fetching workout count: \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                
                let workouts = samples as? [HKWorkout] ?? []
                print("Today's workout count: \(workouts.count)")
                continuation.resume(returning: workouts.count)
            }
            
            healthStore.execute(query)
        }
        
        await updateTodaysWorkoutCount(count: workoutCount)
    }
    
    private func updateTodaysWorkoutCount(count: Int) async {
        let today = Calendar.current.startOfDay(for: Date())
        
        await backgroundContext.perform {
            let healthMetrics = self.getOrCreateHealthMetricsSync(for: today, in: self.backgroundContext)
            
            print("Updating workout count: \(count) for date: \(today)")
            healthMetrics.workoutCount = Int32(count)
            healthMetrics.isFromHealthKit = true
            
            do {
                try self.backgroundContext.save()
                print("Updated today's workout count to: \(count)")
            } catch {
                print("Error saving workout count: \(error)")
            }
        }
    }
    
    private func syncActiveMinutes() async {
        guard let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        
        let activeMinutes = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: exerciseTimeType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    print("❌ Error fetching exercise time: \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }
                
                let minutes = statistics?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                print("📊 Today's exercise time: \(Int(minutes)) minutes")
                continuation.resume(returning: Int(minutes))
            }
            
            healthStore.execute(query)
        }
        
        await updateTodaysActiveMinutes(minutes: activeMinutes)
    }
    
    private func updateTodaysActiveMinutes(minutes: Int) async {
        let today = Calendar.current.startOfDay(for: Date())
        
        await backgroundContext.perform {
            let healthMetrics = self.getOrCreateHealthMetricsSync(for: today, in: self.backgroundContext)
            
            print("🏃 Updating active minutes: \(minutes) for date: \(today)")
            healthMetrics.activeMinutes = Int16(minutes)
            healthMetrics.isFromHealthKit = true
            
            do {
                try self.backgroundContext.save()
                print("✅ Updated today's active minutes to: \(minutes)")
            } catch {
                print("❌ Error saving active minutes: \(error)")
            }
        }
    }
    
    private func syncDistanceWalked() async {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        
        let distanceKm = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: distanceType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    print("Error fetching distance: \(error.localizedDescription)")
                    continuation.resume(returning: 0.0)
                    return
                }
                
                let distance = statistics?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                let distanceKm = distance / 1000.0
                print("Today's distance: \(distanceKm) km")
                continuation.resume(returning: distanceKm)
            }
            
            healthStore.execute(query)
        }
        
        await updateTodaysDistance(distance: distanceKm)
    }
    
    private func updateTodaysDistance(distance: Double) async {
        let today = Calendar.current.startOfDay(for: Date())
        
        await backgroundContext.perform {
            let healthMetrics = self.getOrCreateHealthMetricsSync(for: today, in: self.backgroundContext)
            
            print("Updating distance: \(distance) km for date: \(today)")
            healthMetrics.totalDistance = distance
            healthMetrics.isFromHealthKit = true
            
            do {
                try self.backgroundContext.save()
                print("Updated today's distance to: \(distance) km")
            } catch {
                print("Error saving distance: \(error)")
            }
        }
    }
    
    private func syncRestingHeartRate() async {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return }
        
        let last7Days = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: last7Days, end: Date())
        
        let query = HKSampleQuery(
            sampleType: restingHRType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample] else { return }
            
            Task {
                await self.processHealthMetrics(samples: samples, type: "restingHeartRate")
            }
        }
        
        healthStore.execute(query)
    }
    
    private func syncHRV() async {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        
        let last7Days = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: last7Days, end: Date())
        
        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample] else { return }
            
            Task {
                await self.processHealthMetrics(samples: samples, type: "hrv")
            }
        }
        
        healthStore.execute(query)
    }
    
    private func syncVO2Max() async {
        guard let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return }
        
        let last30Days = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: last30Days, end: Date())
        
        let query = HKSampleQuery(
            sampleType: vo2MaxType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample] else { return }
            
            Task {
                await self.processHealthMetrics(samples: samples, type: "vo2Max")
            }
        }
        
        healthStore.execute(query)
    }
    
    private func syncBloodOxygen() async {
        guard let bloodOxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        
        let last7Days = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: last7Days, end: Date())
        
        let query = HKSampleQuery(
            sampleType: bloodOxygenType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample] else { return }
            
            Task {
                await self.processHealthMetrics(samples: samples, type: "bloodOxygen")
            }
        }
        
        healthStore.execute(query)
    }
    
    private func syncRespiratoryRate() async {
        guard let respiratoryRateType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else { return }
        
        let last7Days = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: last7Days, end: Date())
        
        let query = HKSampleQuery(
            sampleType: respiratoryRateType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample] else { return }
            
            Task {
                await self.processHealthMetrics(samples: samples, type: "respiratoryRate")
            }
        }
        
        healthStore.execute(query)
    }
    
    private func syncSleepData() async {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        let last7Days = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: last7Days, end: Date())
        
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKCategorySample] else { return }
            
            Task {
                await self.processSleepData(samples: samples)
            }
        }
        
        healthStore.execute(query)
    }
    
    private func syncStepCount() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { 
            print("❌ Step count type not available")
            return 
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        print("🔍 Fetching step count from \(startOfDay) to \(now)")
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        
        let stepCount = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    print("❌ Error fetching step count: \(error.localizedDescription)")
                    continuation.resume(returning: 0.0)
                    return
                }
                
                let stepCount = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                print("📊 Today's step count from HealthKit: \(stepCount)")
                continuation.resume(returning: stepCount)
            }
            
            healthStore.execute(query)
        }
        
        await updateTodaysSteps(stepCount: stepCount)
    }
    
    private func updateTodaysSteps(stepCount: Double) async {
        let today = Calendar.current.startOfDay(for: Date())
        
        await backgroundContext.perform {
            let healthMetrics = self.getOrCreateHealthMetricsSync(for: today, in: self.backgroundContext)
            
            print("Updating steps: \(stepCount) for date: \(today)")
            print("Previous step count: \(healthMetrics.stepCount)")
            healthMetrics.stepCount = Int32(stepCount)
            healthMetrics.isFromHealthKit = true
            
            do {
                try self.backgroundContext.save()
                print("✅ Successfully updated today's step count to: \(stepCount)")
            } catch {
                print("❌ Error saving step count: \(error)")
            }
        }
    }
    
    private func syncBodyWeight() async {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        
        let last30Days = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: last30Days, end: Date())
        
        let query = HKSampleQuery(
            sampleType: weightType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample] else { return }
            
            Task {
                await self.processHealthMetrics(samples: samples, type: "bodyWeight")
            }
        }
        
        healthStore.execute(query)
    }
    
    private func syncActiveCalories() async {
        guard let activeCaloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        
        // First, sync today's active calories with high priority using the most accurate method
        await syncTodaysActiveCalories()
        
        // Then sync the last 7 days for historical data (excluding today to avoid overwriting)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let last7Days = calendar.date(byAdding: .day, value: -7, to: today) ?? Date()
        let yesterdayEnd = calendar.date(byAdding: .second, value: -1, to: today) ?? Date()
        
        // Only sync historical data (not today) to avoid overwriting accurate today's data
        let predicate = HKQuery.predicateForSamples(withStart: last7Days, end: yesterdayEnd)
        
        let query = HKSampleQuery(
            sampleType: activeCaloriesType,
            predicate: predicate,
            limit: 200, // Increased limit to get more data
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample] else { return }
            
            Task {
                await self.processHealthMetrics(samples: samples, type: "activeCalories")
            }
        }
        
        healthStore.execute(query)
    }
    
    // New method to specifically sync today's active calories
    private func syncTodaysActiveCalories() async {
        guard let activeCaloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        print("🔍 Fetching today's active calories from \(startOfDay) to \(now)")
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        
        let totalCalories = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeCaloriesType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    print("❌ Error fetching today's active calories: \(error.localizedDescription)")
                    continuation.resume(returning: 0.0)
                    return
                }
                
                let calories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                print("📊 Today's active calories from HealthKit (cumulative): \(calories)")
                continuation.resume(returning: calories)
            }
            
            healthStore.execute(query)
        }
        
        await updateTodaysActiveCalories(calories: totalCalories)
    }
    
    private func updateTodaysActiveCalories(calories: Double) async {
        let today = Calendar.current.startOfDay(for: Date())
        
        await backgroundContext.perform {
            let healthMetrics = self.getOrCreateHealthMetricsSync(for: today, in: self.backgroundContext)
            
            print("🔄 Updating active calories: \(calories) for date: \(today)")
            print("📊 Previous active calories: \(healthMetrics.activeCalories)")
            healthMetrics.activeCalories = calories
            healthMetrics.isFromHealthKit = true
            
            do {
                try self.backgroundContext.save()
                print("✅ Successfully updated today's active calories to: \(calories)")
            } catch {
                print("❌ Error saving active calories: \(error)")
            }
        }
    }
    
    // New method to fetch detailed heart rate samples throughout the day
    private func syncDetailedHeartRate() async {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { 
            print("❌ Heart rate type not available")
            return 
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        print("🔍 Fetching ALL detailed heart rate from \(startOfDay) to \(now)")
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit, // Get ALL samples for the day
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
        ) { [weak self] _, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error fetching detailed heart rate: \(error.localizedDescription)")
                return
            }
            
            let heartRateSamples = samples as? [HKQuantitySample] ?? []
            print("📊 Fetched \(heartRateSamples.count) heart rate samples from HealthKit for today")
            
            if heartRateSamples.isEmpty {
                print("⚠️ No heart rate data found for today. Make sure your Apple Watch is recording heart rate data.")
            } else {
                let hrValues = heartRateSamples.map { Int($0.quantity.doubleValue(for: .count().unitDivided(by: .minute()))) }
                print("💓 Heart rate range: \(hrValues.min() ?? 0) - \(hrValues.max() ?? 0) bpm")
            }
            
            Task {
                await self.processDetailedHeartRate(samples: heartRateSamples)
            }
        }
        
        healthStore.execute(query)
    }
    
    private func processDetailedHeartRate(samples: [HKQuantitySample]) async {
        await backgroundContext.perform {
            // Clear existing readings for today to avoid duplicates
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? Date()
            
            let deleteRequest: NSFetchRequest<HeartRateReading> = HeartRateReading.fetchRequest()
            deleteRequest.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", today as NSDate, tomorrow as NSDate)
            
            do {
                let existingReadings = try self.backgroundContext.fetch(deleteRequest)
                print("🗑️ Deleting \(existingReadings.count) existing heart rate readings for today")
                for reading in existingReadings {
                    self.backgroundContext.delete(reading)
                }
            } catch {
                print("❌ Error deleting existing heart rate readings: \(error)")
            }
            
            // Process new samples
            print("💾 Processing \(samples.count) new heart rate samples...")
            for sample in samples {
                let heartRateReading = HeartRateReading(context: self.backgroundContext)
                heartRateReading.id = UUID()
                let hrValue = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                heartRateReading.heartRate = Int16(hrValue)
                heartRateReading.timestamp = sample.startDate
                heartRateReading.isFromHealthKit = true
                
                // Determine context based on heart rate value
                let hr = Int(heartRateReading.heartRate)
                switch hr {
                case 0..<60:
                    heartRateReading.context = "resting"
                case 60..<100:
                    heartRateReading.context = "active"
                case 100..<140:
                    heartRateReading.context = "elevated"
                default:
                    heartRateReading.context = "workout"
                }
            }
            
            // Save changes
            do {
                try self.backgroundContext.save()
                print("✅ Successfully saved \(samples.count) heart rate readings to Core Data")
                
                // Verify the save
                let verifyRequest: NSFetchRequest<HeartRateReading> = HeartRateReading.fetchRequest()
                verifyRequest.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", today as NSDate, tomorrow as NSDate)
                let savedCount = try self.backgroundContext.fetch(verifyRequest).count
                print("✅ Verified: \(savedCount) heart rate readings now in Core Data for today")
            } catch {
                print("❌ Error saving heart rate readings: \(error.localizedDescription)")
                self.backgroundContext.rollback()
            }
        }
    }
    
    private func processHealthMetrics(samples: [HKQuantitySample], type: String) async {
        let calendar = Calendar.current
        let groupedSamples = Dictionary(grouping: samples) { sample in
            calendar.startOfDay(for: sample.startDate)
        }
        
        await backgroundContext.perform {
            for (date, dailySamples) in groupedSamples {
                let healthMetrics = self.getOrCreateHealthMetricsSync(for: date, in: self.backgroundContext)
                
                switch type {
                case "restingHeartRate":
                    let avgRestingHR = dailySamples.map { $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())) }.reduce(0, +) / Double(dailySamples.count)
                    healthMetrics.restingHeartRate = Int16(avgRestingHR)
                    // Recalculate recovery score when heart rate changes
                    self.calculateRecoveryScore(for: healthMetrics)
                    
                case "hrv":
                    let avgHRV = dailySamples.map { $0.quantity.doubleValue(for: .secondUnit(with: .milli)) }.reduce(0, +) / Double(dailySamples.count)
                    healthMetrics.hrv = avgHRV
                    // Recalculate recovery score when HRV changes
                    self.calculateRecoveryScore(for: healthMetrics)
                    
                case "vo2Max":
                    let avgVO2Max = dailySamples.map { $0.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))) }.reduce(0, +) / Double(dailySamples.count)
                    healthMetrics.vo2Max = avgVO2Max
                    
                case "stepCount":
                    let totalSteps = dailySamples.map { $0.quantity.doubleValue(for: .count()) }.reduce(0, +)
                    healthMetrics.stepCount = Int32(totalSteps)
                    
                case "bodyWeight":
                    let avgWeight = dailySamples.map { $0.quantity.doubleValue(for: .gramUnit(with: .kilo)) }.reduce(0, +) / Double(dailySamples.count)
                    healthMetrics.bodyWeight = avgWeight
                    
                case "activeCalories":
                    // Skip updating today's active calories to preserve accurate cumulative sum
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    let isToday = calendar.isDate(date, inSameDayAs: today)
                    
                    if isToday {
                        print("⏭️ Skipping today's active calories update - preserving accurate cumulative sum")
                        continue
                    }
                    
                    let totalCalories = dailySamples.map { $0.quantity.doubleValue(for: .kilocalorie()) }.reduce(0, +)
                    healthMetrics.activeCalories = totalCalories
                    print("📊 Updated active calories for \(date): \(totalCalories) kcal")
                    
                case "basalCalories":
                    let totalBasal = dailySamples.map { $0.quantity.doubleValue(for: .kilocalorie()) }.reduce(0, +)
                    healthMetrics.basalCalories = totalBasal
                    healthMetrics.totalCalories = healthMetrics.activeCalories + totalBasal
                    
                case "bloodOxygen":
                    let avgBloodOxygen = dailySamples.map { $0.quantity.doubleValue(for: .percent()) }.reduce(0, +) / Double(dailySamples.count)
                    healthMetrics.bloodOxygen = avgBloodOxygen * 100 // Convert to percentage
                    
                case "respiratoryRate":
                    let avgRespiratoryRate = dailySamples.map { $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())) }.reduce(0, +) / Double(dailySamples.count)
                    healthMetrics.respiratoryRate = avgRespiratoryRate
                    
                default:
                    break
                }
                
                healthMetrics.isFromHealthKit = true
            }
            
            // Save changes
            do {
                try self.backgroundContext.save()
            } catch {
                print("Error saving health metrics: \(error)")
            }
        }
    }
    
    private func processSleepData(samples: [HKCategorySample]) async {
        let calendar = Calendar.current
        let groupedSamples = Dictionary(grouping: samples) { sample in
            calendar.startOfDay(for: sample.startDate)
        }
        
        await backgroundContext.perform {
            for (date, dailySamples) in groupedSamples {
                let healthMetrics = self.getOrCreateHealthMetricsSync(for: date, in: self.backgroundContext)
                
                var totalSleepMinutes = 0.0 // Track in minutes for precision
                var deepSleepHours = 0.0
                var remSleepHours = 0.0
                var coreSleepHours = 0.0
                var unspecifiedSleepHours = 0.0
                var timeInBed = 0.0
                var awakeTime = 0.0
                
                for sample in dailySamples {
                    let durationMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0 // Convert to minutes
                    let duration = durationMinutes / 60.0 // Convert to hours
                    
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        timeInBed += duration
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        coreSleepHours += duration
                        totalSleepMinutes += durationMinutes
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deepSleepHours += duration
                        totalSleepMinutes += durationMinutes
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        remSleepHours += duration
                        totalSleepMinutes += durationMinutes
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        unspecifiedSleepHours += duration
                        totalSleepMinutes += durationMinutes
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awakeTime += duration
                    default:
                        break
                    }
                }
                
                // Convert total sleep minutes to accurate decimal hours
                let totalSleepHours = totalSleepMinutes / 60.0
                healthMetrics.sleepHours = totalSleepHours
                healthMetrics.deepSleepHours = deepSleepHours
                healthMetrics.remSleepHours = remSleepHours
                healthMetrics.timeInBed = timeInBed
                
                // Calculate sleep quality based on multiple factors
                if totalSleepHours > 0 {
                    var qualityScore = 0.0
                    
                    // Base score based on total sleep duration (0-4 points)
                    switch totalSleepHours {
                    case 7...9:
                        qualityScore += 4.0 // Optimal sleep duration
                    case 6.5..<7, 9..<10:
                        qualityScore += 3.0 // Good sleep duration
                    case 6..<6.5, 10..<11:
                        qualityScore += 2.0 // Acceptable sleep duration
                    case 5..<6, 11..<12:
                        qualityScore += 1.0 // Poor sleep duration
                    default:
                        qualityScore += 0.0 // Very poor sleep duration
                    }
                    
                    // Sleep efficiency score (0-3 points)
                    if timeInBed > 0 {
                        let efficiency = totalSleepHours / timeInBed
                        switch efficiency {
                        case 0.85...1.0:
                            qualityScore += 3.0 // Excellent efficiency
                        case 0.75..<0.85:
                            qualityScore += 2.0 // Good efficiency
                        case 0.65..<0.75:
                            qualityScore += 1.0 // Fair efficiency
                        default:
                            qualityScore += 0.0 // Poor efficiency
                        }
                    } else {
                        qualityScore += 2.0 // Default if no time in bed data
                    }
                    
                    // Core sleep percentage score (0-1.5 points)
                    let coreSleepPercentage = coreSleepHours / totalSleepHours
                    switch coreSleepPercentage {
                    case 0.45...0.60:
                        qualityScore += 1.5 // Optimal core sleep
                    case 0.35..<0.45, 0.60..<0.70:
                        qualityScore += 1.2 // Good core sleep
                    case 0.25..<0.35, 0.70..<0.80:
                        qualityScore += 0.8 // Fair core sleep
                    default:
                        qualityScore += 0.4 // Poor core sleep
                    }
                    
                    // Deep sleep percentage score (0-1.5 points)
                    let deepSleepPercentage = deepSleepHours / totalSleepHours
                    switch deepSleepPercentage {
                    case 0.15...0.25:
                        qualityScore += 1.5 // Optimal deep sleep
                    case 0.10..<0.15, 0.25..<0.30:
                        qualityScore += 1.2 // Good deep sleep
                    case 0.05..<0.10, 0.30..<0.35:
                        qualityScore += 0.8 // Fair deep sleep
                    default:
                        qualityScore += 0.4 // Poor deep sleep
                    }
                    
                    // REM sleep percentage score (0-1 points)
                    let remSleepPercentage = remSleepHours / totalSleepHours
                    switch remSleepPercentage {
                    case 0.20...0.30:
                        qualityScore += 1.0 // Optimal REM sleep
                    case 0.15..<0.20, 0.30..<0.35:
                        qualityScore += 0.75 // Good REM sleep
                    case 0.10..<0.15, 0.35..<0.40:
                        qualityScore += 0.5 // Fair REM sleep
                    default:
                        qualityScore += 0.25 // Poor REM sleep
                    }
                    
                    // Sleep continuity score based on awake time (0-1 points)
                    if timeInBed > 0 {
                        let awakePercentage = awakeTime / timeInBed
                        switch awakePercentage {
                        case 0.0...0.05:
                            qualityScore += 1.0 // Excellent continuity (≤5% awake)
                        case 0.05..<0.10:
                            qualityScore += 0.8 // Good continuity (5-10% awake)
                        case 0.10..<0.15:
                            qualityScore += 0.6 // Fair continuity (10-15% awake)
                        case 0.15..<0.20:
                            qualityScore += 0.4 // Poor continuity (15-20% awake)
                        default:
                            qualityScore += 0.2 // Very poor continuity (>20% awake)
                        }
                    } else {
                        qualityScore += 0.6 // Default if no time in bed data
                    }
                    
                    // Cap the score at 10 and ensure it's at least 1
                    let finalScore = max(1.0, min(10.0, qualityScore))
                    healthMetrics.sleepQuality = Int16(finalScore)
                    
                    // Recalculate recovery score when sleep data changes
                    self.calculateRecoveryScore(for: healthMetrics)
                    
                    print("💤 Sleep Quality Calculation:")
                    print("   Total Sleep: \(totalSleepHours)h")
                    print("   Core Sleep: \(coreSleepHours)h (\(String(format: "%.1f", coreSleepPercentage * 100))%)")
                    print("   Deep Sleep: \(deepSleepHours)h (\(String(format: "%.1f", deepSleepPercentage * 100))%)")
                    print("   REM Sleep: \(remSleepHours)h (\(String(format: "%.1f", remSleepPercentage * 100))%)")
                    print("   Awake Time: \(awakeTime)h (\(String(format: "%.1f", timeInBed > 0 ? (awakeTime / timeInBed) * 100 : 0))%)")
                    print("   Sleep Efficiency: \(String(format: "%.1f", timeInBed > 0 ? (totalSleepHours / timeInBed) * 100 : 0))%")
                    print("   Final Quality Score: \(finalScore)/10")
                }
                
                healthMetrics.isFromHealthKit = true
                
                print("💤 Sleep data for \(date): \(totalSleepHours) hours (\(Int(totalSleepMinutes)) minutes), Time in bed: \(timeInBed) hours")
            }
            
            // Save changes
            do {
                try self.backgroundContext.save()
            } catch {
                print("Error saving sleep data: \(error)")
            }
        }
    }
    
    private func syncBasalCalories() async {
        guard let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else { return }
        // First, sync today's basal calories
        await syncTodaysBasalCalories()
        // Then sync the last 7 days for historical data
        let last7Days = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: last7Days, end: Date())
        let query = HKSampleQuery(
            sampleType: basalType,
            predicate: predicate,
            limit: 200,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { [weak self] _, samples, _ in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample] else { return }
            Task {
                await self.processHealthMetrics(samples: samples, type: "basalCalories")
            }
        }
        healthStore.execute(query)
    }

    private func syncTodaysBasalCalories() async {
        guard let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else { return }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        let totalBasal = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: basalType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                let basal = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: basal)
            }
            healthStore.execute(query)
        }
        await updateTodaysBasalCalories(basal: totalBasal)
    }

    private func updateTodaysBasalCalories(basal: Double) async {
        let today = Calendar.current.startOfDay(for: Date())
        await backgroundContext.perform {
            let healthMetrics = self.getOrCreateHealthMetricsSync(for: today, in: self.backgroundContext)
            healthMetrics.basalCalories = basal
            healthMetrics.isFromHealthKit = true
            do {
                try self.backgroundContext.save()
            } catch {
                print("Error saving basal calories: \(error)")
            }
        }
    }
    
    private func getOrCreateHealthMetrics(for date: Date) async -> HealthMetrics {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        return await backgroundContext.perform {
            return self.getOrCreateHealthMetricsSync(for: startOfDay, in: self.backgroundContext)
        }
    }
    
    private func getOrCreateHealthMetricsSync(for date: Date, in context: NSManagedObjectContext) -> HealthMetrics {
        let request: NSFetchRequest<HealthMetrics> = HealthMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@", date as NSDate)
        
        do {
            let existingMetrics = try context.fetch(request)
            if let existing = existingMetrics.first {
                print("📊 Found existing health metrics for \(date) - Steps: \(existing.stepCount), Calories: \(existing.activeCalories)")
                return existing
            }
        } catch {
            print("❌ Error fetching health metrics: \(error)")
        }
        
        // Create new health metrics
        print("🆕 Creating new health metrics for \(date)")
        let healthMetrics = HealthMetrics(context: context)
        healthMetrics.id = UUID()
        healthMetrics.date = date
        healthMetrics.isFromHealthKit = false
        
        return healthMetrics
    }
    
    // MARK: - Recovery Score Calculation
    
    /// Calculate and save recovery score for a specific date
    private func calculateRecoveryScore(for metrics: HealthMetrics) {
        var score = 0.0
        
        // HRV Component (45 points) - Higher is better
        if metrics.hrv >= 60 {
            score += 45
        } else if metrics.hrv >= 40 {
            score += 35
        } else if metrics.hrv >= 25 {
            score += 25
        } else if metrics.hrv > 0 {
            score += 15
        }
        
        // Resting Heart Rate Component (35 points) - Lower within range is better
        if metrics.restingHeartRate >= 60 && metrics.restingHeartRate <= 70 {
            score += 35 // Optimal range
        } else if metrics.restingHeartRate < 60 {
            score += 30 // Athletic heart rate
        } else if metrics.restingHeartRate <= 80 {
            score += 20 // Good range
        } else if metrics.restingHeartRate > 0 {
            score += 10 // Elevated
        }
        
        // Energy Level Component (20 points) - Subjective readiness
        if metrics.energyLevel >= 7 {
            score += 20
        } else if metrics.energyLevel >= 5 {
            score += 15
        } else if metrics.energyLevel > 0 {
            score += 10
        } else {
            // If no energy level data, estimate from sleep quality
            if metrics.sleepQuality >= 8 {
                score += 18
            } else if metrics.sleepQuality >= 6 {
                score += 14
            } else if metrics.sleepQuality > 0 {
                score += 10
            } else {
                score += 12 // Default mid-range
            }
        }
        
        metrics.recoveryScore = min(score, 100)
        print("💪 Recovery Score calculated: \(metrics.recoveryScore)/100 (HRV: \(metrics.hrv), RHR: \(metrics.restingHeartRate), Energy: \(metrics.energyLevel))")
    }
    
    /// Update recovery scores for all recent metrics
    func updateRecoveryScores() async {
        await backgroundContext.perform {
            let request: NSFetchRequest<HealthMetrics> = HealthMetrics.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)]
            request.fetchLimit = 30 // Update last 30 days
            
            do {
                let metrics = try self.backgroundContext.fetch(request)
                for metric in metrics {
                    self.calculateRecoveryScore(for: metric)
                }
                
                try self.backgroundContext.save()
                print("✅ Updated recovery scores for \(metrics.count) metrics")
            } catch {
                print("❌ Error updating recovery scores: \(error)")
            }
        }
    }
    
    // MARK: - Force Refresh Methods
    
    /// Force refresh today's active calories to get the most accurate data from HealthKit
    func forceRefreshTodaysActiveCalories() async {
        print("🔄 Force refreshing today's active calories...")
        await syncTodaysActiveCalories()
    }
    
    /// Force refresh all today's key metrics
    func forceRefreshTodaysMetrics() async {
        print("🔄 Force refreshing all today's key metrics...")
        await syncTodaysActiveCalories()
        await syncTodaysBasalCalories()
        await syncStepCount()
        
        // Also sync user profile to keep age, weight, etc. accurate
        await UserProfileManager.shared.syncFromHealthKit()
    }
    
    // MARK: - Running Form Metrics (Most Recent)
    
    /// Fetch all running form metrics for display
    func getLatestRunningFormMetrics() async -> RunningFormMetrics {
        async let strideLength = getLatestRunningStrideLengthMeters()
        async let groundContact = getLatestRunningGroundContactMs()
        async let verticalOsc = getLatestRunningVerticalOscillationCm()
        async let power = getLatestRunningPowerWatts()
        async let speed = getLatestRunningSpeedMetersPerSecond()
        async let cadence = getLatestRunningCadenceSpm()
        
        let (stride, gct, vo, pwr, spd, cad) = await (strideLength, groundContact, verticalOsc, power, speed, cadence)
        
        return RunningFormMetrics(
            strideLength: stride,
            groundContactTime: gct,
            verticalOscillation: vo,
            runningPower: pwr,
            runningSpeed: spd,
            cadence: cad,
            runningCadenceHK: nil,
            stepLength: nil,
            verticalRatio: nil,
            asymmetryPercentage: nil,
            groundContactTimeBalance: nil,
            doubleSupportPercentage: nil,
            cardioRecovery1Min: nil,
            lastUpdated: Date()
        )
    }
    
    /// Fetch running form metrics from a specific workout time range
    func getRunningFormMetrics(from startDate: Date, to endDate: Date) async -> RunningFormMetrics {
        async let strideLength = fetchAverageRunningMetric(.runningStrideLength, unit: .meter(), start: startDate, end: endDate)
        async let groundContact = fetchAverageRunningMetric(.runningGroundContactTime, unit: .secondUnit(with: .milli), start: startDate, end: endDate)
        async let verticalOsc = fetchAverageRunningMetric(.runningVerticalOscillation, unit: .meterUnit(with: .centi), start: startDate, end: endDate)
        async let power = fetchAverageRunningMetric(.runningPower, unit: .watt(), start: startDate, end: endDate)
        async let speed = fetchAverageRunningMetric(.runningSpeed, unit: .meter().unitDivided(by: .second()), start: startDate, end: endDate)
        
        // Extended dynamics (best-effort)
        async let cadenceHK = fetchAverageRunningMetricRaw("HKQuantityTypeIdentifierRunningCadence", unit: HKUnit.count().unitDivided(by: .minute()), start: startDate, end: endDate)
        async let stepLength = fetchAverageRunningMetricRaw("HKQuantityTypeIdentifierRunningStepLength", unit: .meter(), start: startDate, end: endDate)
        async let verticalRatio = fetchAverageRunningMetricRaw("HKQuantityTypeIdentifierRunningVerticalRatio", unit: .percent(), start: startDate, end: endDate)
        async let asymmetry = fetchAverageRunningMetricRaw("HKQuantityTypeIdentifierRunningAsymmetryPercentage", unit: .percent(), start: startDate, end: endDate)
        async let gctBalance = fetchAverageRunningMetricRaw("HKQuantityTypeIdentifierRunningGroundContactTimeBalance", unit: .percent(), start: startDate, end: endDate)
        async let doubleSupport = fetchAverageRunningMetricRaw("HKQuantityTypeIdentifierWalkingDoubleSupportPercentage", unit: .percent(), start: startDate, end: endDate)
        async let cardioRecovery1Min = fetchHeartRateRecovery1Min(workoutEnd: endDate)
        
        let (stride, gct, vo, pwr, spd) = await (strideLength, groundContact, verticalOsc, power, speed)
        let (cadHK, stepLen, vRatio, asym, gctBal, dblSupport, hrRec1) = await (
            cadenceHK,
            stepLength,
            verticalRatio,
            asymmetry,
            gctBalance,
            doubleSupport,
            cardioRecovery1Min
        )
        
        // Calculate cadence from speed and stride if available
        var cadence: Double? = nil
        if let cadHK {
            cadence = cadHK
        } else if let s = spd, let l = stride, s > 0, l > 0 {
            cadence = (s / l) * 60.0 // steps per minute
        }
        
        return RunningFormMetrics(
            strideLength: stride,
            groundContactTime: gct,
            verticalOscillation: vo,
            runningPower: pwr,
            runningSpeed: spd,
            cadence: cadence,
            runningCadenceHK: cadHK,
            stepLength: stepLen,
            verticalRatio: vRatio,
            asymmetryPercentage: asym,
            groundContactTimeBalance: gctBal,
            doubleSupportPercentage: dblSupport,
            cardioRecovery1Min: hrRec1,
            lastUpdated: Date()
        )
    }
    
    /// Fetch average metric over a time range
    private func fetchAverageRunningMetric(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    // These metrics require Apple Watch with running dynamics support
                    // It's normal to not have this data - just return nil silently
                    continuation.resume(returning: nil)
                    return
                }
                
                if let avgQuantity = statistics?.averageQuantity() {
                    let value = avgQuantity.doubleValue(for: unit)
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchAverageRunningMetricRaw(_ rawIdentifier: String, unit: HKUnit, start: Date, end: Date) async -> Double? {
        let id = HKQuantityTypeIdentifier(rawValue: rawIdentifier)
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
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
        
        async let hrAtEnd = fetchAverageHeartRate(type: heartRateType, unit: unit, predicate: endWindowPredicate)
        async let hrAfter1 = fetchAverageHeartRate(type: heartRateType, unit: unit, predicate: recoveryPredicate)
        
        guard let endHR = await hrAtEnd, let afterHR = await hrAfter1 else { return nil }
        return max(0, endHR - afterHR)
    }
    
    private func fetchAverageHeartRate(type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
    
    /// Get running form metrics from the last 30 days of runs
    func getRecentRunningFormSummary() async -> RunningFormMetrics {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        // First, fetch recent running workouts
        let workoutType = HKObjectType.workoutType()
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let workoutPredicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date())
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutPredicate, runningPredicate])
        
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: compoundPredicate,
                limit: 20,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                let runs = samples as? [HKWorkout] ?? []
                continuation.resume(returning: runs)
            }
            healthStore.execute(query)
        }
        
        guard !workouts.isEmpty else {
            print("⚠️ No recent running workouts found for form analysis")
            return RunningFormMetrics.empty
        }
        
        print("📊 Found \(workouts.count) recent running workouts for form analysis")
        
        // Aggregate metrics from all runs
        var allStrides: [Double] = []
        var allGCT: [Double] = []
        var allVO: [Double] = []
        var allPower: [Double] = []
        var allSpeed: [Double] = []
        var allCadenceHK: [Double] = []
        var allStepLength: [Double] = []
        var allVerticalRatio: [Double] = []
        var allAsym: [Double] = []
        var allGctBalance: [Double] = []
        var allDoubleSupport: [Double] = []
        var allRecovery1: [Double] = []
        
        for workout in workouts {
            let metrics = await getRunningFormMetrics(from: workout.startDate, to: workout.endDate)
            
            if let stride = metrics.strideLength { allStrides.append(stride) }
            if let gct = metrics.groundContactTime { allGCT.append(gct) }
            if let vo = metrics.verticalOscillation { allVO.append(vo) }
            if let power = metrics.runningPower { allPower.append(power) }
            if let speed = metrics.runningSpeed { allSpeed.append(speed) }
            if let cadHK = metrics.runningCadenceHK { allCadenceHK.append(cadHK) }
            if let step = metrics.stepLength { allStepLength.append(step) }
            if let vr = metrics.verticalRatio { allVerticalRatio.append(vr) }
            if let a = metrics.asymmetryPercentage { allAsym.append(a) }
            if let b = metrics.groundContactTimeBalance { allGctBalance.append(b) }
            if let ds = metrics.doubleSupportPercentage { allDoubleSupport.append(ds) }
            if let r = metrics.cardioRecovery1Min { allRecovery1.append(r) }
        }
        
        // Calculate averages
        let avgStride = allStrides.isEmpty ? nil : allStrides.reduce(0, +) / Double(allStrides.count)
        let avgGCT = allGCT.isEmpty ? nil : allGCT.reduce(0, +) / Double(allGCT.count)
        let avgVO = allVO.isEmpty ? nil : allVO.reduce(0, +) / Double(allVO.count)
        let avgPower = allPower.isEmpty ? nil : allPower.reduce(0, +) / Double(allPower.count)
        let avgSpeed = allSpeed.isEmpty ? nil : allSpeed.reduce(0, +) / Double(allSpeed.count)
        let avgCadenceHK = allCadenceHK.isEmpty ? nil : allCadenceHK.reduce(0, +) / Double(allCadenceHK.count)
        let avgStepLength = allStepLength.isEmpty ? nil : allStepLength.reduce(0, +) / Double(allStepLength.count)
        let avgVerticalRatio = allVerticalRatio.isEmpty ? nil : allVerticalRatio.reduce(0, +) / Double(allVerticalRatio.count)
        let avgAsym = allAsym.isEmpty ? nil : allAsym.reduce(0, +) / Double(allAsym.count)
        let avgGctBalance = allGctBalance.isEmpty ? nil : allGctBalance.reduce(0, +) / Double(allGctBalance.count)
        let avgDoubleSupport = allDoubleSupport.isEmpty ? nil : allDoubleSupport.reduce(0, +) / Double(allDoubleSupport.count)
        let avgRecovery1 = allRecovery1.isEmpty ? nil : allRecovery1.reduce(0, +) / Double(allRecovery1.count)
        
        // Calculate cadence
        var avgCadence: Double? = nil
        if let cad = avgCadenceHK {
            avgCadence = cad
        } else if let stride = avgStride, let speed = avgSpeed, stride > 0 {
            avgCadence = (speed / stride) * 60.0
        }
        
        return RunningFormMetrics(
            strideLength: avgStride,
            groundContactTime: avgGCT,
            verticalOscillation: avgVO,
            runningPower: avgPower,
            runningSpeed: avgSpeed,
            cadence: avgCadence,
            runningCadenceHK: avgCadenceHK,
            stepLength: avgStepLength,
            verticalRatio: avgVerticalRatio,
            asymmetryPercentage: avgAsym,
            groundContactTimeBalance: avgGctBalance,
            doubleSupportPercentage: avgDoubleSupport,
            cardioRecovery1Min: avgRecovery1,
            lastUpdated: Date()
        )
    }
    
    // MARK: - User Profile Data
    
    /// Get user profile data from HealthKit (age, gender, height, weight)
    func getUserProfile() async -> UserProfile? {
        guard hasValidAuthorization() else { return nil }
        
        async let age = getUserAge()
        async let gender = getUserGender()
        async let height = getUserHeight()
        async let weight = getUserWeight()
        
        let profile = UserProfile(
            age: await age,
            gender: await gender,
            height: await height,
            weight: await weight
        )
        
        return profile
    }
    
    /// Get user's age from HealthKit date of birth
    private func getUserAge() async -> Double? {
        do {
            let dateOfBirthComponents = try healthStore.dateOfBirthComponents()
            guard let dateOfBirth = dateOfBirthComponents.date else { return nil }
            
            let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
            print("📊 User age from HealthKit: \(age) years")
            return Double(age)
        } catch {
            print("❌ Error fetching age from HealthKit: \(error)")
            return nil
        }
    }
    
    /// Get user's gender from HealthKit
    private func getUserGender() async -> String? {
        do {
            let biologicalSex = try healthStore.biologicalSex()
            let gender = biologicalSex.biologicalSex == .male ? "Male" : "Female"
            print("📊 User gender from HealthKit: \(gender)")
            return gender
        } catch {
            print("❌ Error fetching gender from HealthKit: \(error)")
            return nil
        }
    }
    
    /// Get user's height from HealthKit
    private func getUserHeight() async -> Double? {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else { return nil }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heightType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            if let error = error {
                print("❌ Error fetching height: \(error)")
                return
            }
            
            if let sample = samples?.first as? HKQuantitySample {
                let heightCm = sample.quantity.doubleValue(for: .meter()) * 100
                print("📊 User height from HealthKit: \(heightCm) cm")
            }
        }
        
        return await withCheckedContinuation { continuation in
            let heightQuery = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("❌ Error fetching height: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                if let sample = samples?.first as? HKQuantitySample {
                    let heightCm = sample.quantity.doubleValue(for: .meter()) * 100
                    print("📊 User height from HealthKit: \(heightCm) cm")
                    continuation.resume(returning: heightCm)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            healthStore.execute(heightQuery)
        }
    }
    
    /// Get user's most recent weight from HealthKit
    private func getUserWeight() async -> Double? {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let weightQuery = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("❌ Error fetching weight: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                if let sample = samples?.first as? HKQuantitySample {
                    let weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    print("📊 User weight from HealthKit: \(weightKg) kg")
                    continuation.resume(returning: weightKg)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            healthStore.execute(weightQuery)
        }
    }
}

// MARK: - User Profile Data Model
struct UserProfile {
    let age: Double?
    let gender: String?
    let height: Double?
    let weight: Double?
    
    var isComplete: Bool {
        age != nil && gender != nil && height != nil && weight != nil
    }
    
    var displayAge: String {
        if let age = age {
            return "\(Int(age)) years"
        }
        return "Unknown"
    }
    
    var displayGender: String {
        gender ?? "Unknown"
    }
    
    var displayHeight: String {
        if let height = height {
            return "\(Int(height)) cm"
        }
        return "Unknown"
    }
    
    var displayWeight: String {
        if let weight = weight {
            return String(format: "%.1f kg", weight)
        }
        return "Unknown"
    }
}

// MARK: - Running Form Metrics Model
struct RunningFormMetrics {
    let strideLength: Double? // meters
    let groundContactTime: Double? // milliseconds
    let verticalOscillation: Double? // centimeters
    let runningPower: Double? // watts
    let runningSpeed: Double? // meters per second
    let cadence: Double? // steps per minute
    
    // Extended dynamics (best-effort if HealthKit provides them)
    let runningCadenceHK: Double? // steps per minute (HealthKit)
    let stepLength: Double? // meters
    let verticalRatio: Double? // %
    let asymmetryPercentage: Double? // %
    let groundContactTimeBalance: Double? // %
    let doubleSupportPercentage: Double? // %
    let cardioRecovery1Min: Double? // bpm drop in first minute post-workout
    
    let lastUpdated: Date
    
    var hasData: Bool {
        strideLength != nil ||
            groundContactTime != nil ||
            verticalOscillation != nil ||
            runningPower != nil ||
            cadence != nil ||
            runningCadenceHK != nil ||
            stepLength != nil ||
            verticalRatio != nil ||
            asymmetryPercentage != nil ||
            groundContactTimeBalance != nil ||
            doubleSupportPercentage != nil ||
            cardioRecovery1Min != nil
    }
    
    static var empty: RunningFormMetrics {
        RunningFormMetrics(
            strideLength: nil,
            groundContactTime: nil,
            verticalOscillation: nil,
            runningPower: nil,
            runningSpeed: nil,
            cadence: nil,
            runningCadenceHK: nil,
            stepLength: nil,
            verticalRatio: nil,
            asymmetryPercentage: nil,
            groundContactTimeBalance: nil,
            doubleSupportPercentage: nil,
            cardioRecovery1Min: nil,
            lastUpdated: Date()
        )
    }
    
    // Formatted display strings
    var formattedStrideLength: String {
        if let stride = strideLength {
            return String(format: "%.2f m", stride)
        }
        return "N/A"
    }
    
    var formattedGroundContactTime: String {
        if let gct = groundContactTime {
            return String(format: "%.0f ms", gct)
        }
        return "N/A"
    }
    
    var formattedVerticalOscillation: String {
        if let vo = verticalOscillation {
            return String(format: "%.1f cm", vo)
        }
        return "N/A"
    }
    
    var formattedPower: String {
        if let power = runningPower {
            return String(format: "%.0f W", power)
        }
        return "N/A"
    }
    
    var formattedCadence: String {
        if let cadence = cadence {
            return String(format: "%.0f spm", cadence)
        }
        return "N/A"
    }
    
    var formattedSpeed: String {
        if let speed = runningSpeed {
            // Convert m/s to min/km pace
            if speed > 0 {
                let paceSecondsPerKm = 1000.0 / speed
                let minutes = Int(paceSecondsPerKm) / 60
                let seconds = Int(paceSecondsPerKm) % 60
                return String(format: "%d:%02d /km", minutes, seconds)
            }
        }
        return "N/A"
    }
}
