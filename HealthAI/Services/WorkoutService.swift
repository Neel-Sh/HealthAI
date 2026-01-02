import Foundation
import SwiftUI
import Combine

// MARK: - Workout Service
@MainActor
class WorkoutService: ObservableObject {
    static let shared = WorkoutService()
    
    @Published var templates: [WorkoutTemplate] = []
    @Published var workoutHistory: [WorkoutSession] = []
    @Published var currentSession: WorkoutSession?
    @Published var personalRecords: [PersonalRecord] = []
    
    // Active workout state
    @Published var isWorkoutActive: Bool = false
    @Published var restTimerSeconds: Int = 0
    @Published var isRestTimerRunning: Bool = false
    
    private var restTimer: Timer?
    private var workoutTimer: Timer?
    
    private let templatesKey = "workoutTemplates"
    private let historyKey = "workoutHistory"
    private let personalRecordsKey = "personalRecords"
    
    init() {
        loadData()
        createDefaultTemplates()
    }
    
    // MARK: - Data Persistence
    private func loadData() {
        // Load templates
        if let data = UserDefaults.standard.data(forKey: templatesKey),
           let decoded = try? JSONDecoder().decode([WorkoutTemplate].self, from: data) {
            templates = decoded
        }
        
        // Load history
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) {
            workoutHistory = decoded
        }
        
        // Load PRs
        if let data = UserDefaults.standard.data(forKey: personalRecordsKey),
           let decoded = try? JSONDecoder().decode([PersonalRecord].self, from: data) {
            personalRecords = decoded
        }
    }
    
    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: templatesKey)
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(workoutHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    private func savePersonalRecords() {
        if let data = try? JSONEncoder().encode(personalRecords) {
            UserDefaults.standard.set(data, forKey: personalRecordsKey)
        }
    }
    
    private func createDefaultTemplates() {
        guard templates.isEmpty else { return }
        
        let database = ExerciseDatabase.shared
        
        // Create default PPL templates
        templates = [
            database.generateWorkoutTemplate(for: .push),
            database.generateWorkoutTemplate(for: .pull),
            database.generateWorkoutTemplate(for: .legs),
            database.generateWorkoutTemplate(for: .upper),
            database.generateWorkoutTemplate(for: .lower),
            database.generateWorkoutTemplate(for: .fullBody)
        ]
        
        saveTemplates()
    }
    
    // MARK: - Template Management
    func addTemplate(_ template: WorkoutTemplate) {
        templates.append(template)
        saveTemplates()
    }
    
    func updateTemplate(_ template: WorkoutTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
            saveTemplates()
        }
    }
    
    func deleteTemplate(_ template: WorkoutTemplate) {
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }
    
    // MARK: - Workout Session Management
    func startWorkout(from template: WorkoutTemplate) {
        let session = WorkoutSession(
            templateId: template.id,
            name: template.name,
            splitType: template.splitType,
            exercises: template.exercises.map { exercise in
                var newExercise = exercise
                // Pre-populate sets based on target
                newExercise.sets = (0..<exercise.targetSets).map { _ in WorkoutSet() }
                return newExercise
            }
        )
        
        currentSession = session
        isWorkoutActive = true
        
        // Update template usage
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].lastUsed = Date()
            saveTemplates()
        }
    }
    
    func startEmptyWorkout(splitType: WorkoutSplitType = .custom, name: String = "Quick Workout") {
        let session = WorkoutSession(
            name: name,
            splitType: splitType,
            exercises: []
        )
        
        currentSession = session
        isWorkoutActive = true
    }
    
    func addExerciseToSession(_ exercise: Exercise) {
        guard var session = currentSession else { return }
        
        let workoutExercise = WorkoutExercise(
            exercise: exercise,
            sets: [WorkoutSet(), WorkoutSet(), WorkoutSet()], // 3 empty sets by default
            order: session.exercises.count
        )
        
        session.exercises.append(workoutExercise)
        currentSession = session
        
        // Track as recent
        ExerciseDatabase.shared.addToRecent(exercise)
    }
    
    func removeExerciseFromSession(_ exerciseId: UUID) {
        guard var session = currentSession else { return }
        session.exercises.removeAll { $0.id == exerciseId }
        currentSession = session
    }
    
    func updateSet(exerciseId: UUID, setIndex: Int, weight: Double? = nil, reps: Int? = nil, isCompleted: Bool? = nil, rpe: Int? = nil) {
        guard var session = currentSession,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }),
              setIndex < session.exercises[exerciseIndex].sets.count else { return }
        
        if let weight = weight {
            session.exercises[exerciseIndex].sets[setIndex].weight = weight
        }
        if let reps = reps {
            session.exercises[exerciseIndex].sets[setIndex].reps = reps
        }
        if let isCompleted = isCompleted {
            session.exercises[exerciseIndex].sets[setIndex].isCompleted = isCompleted
            session.exercises[exerciseIndex].sets[setIndex].timestamp = Date()
        }
        if let rpe = rpe {
            session.exercises[exerciseIndex].sets[setIndex].rpe = rpe
        }
        
        currentSession = session
    }
    
    func addSetToExercise(_ exerciseId: UUID) {
        guard var session = currentSession,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        
        // Copy previous set values if available
        var newSet = WorkoutSet()
        if let lastSet = session.exercises[exerciseIndex].sets.last {
            newSet.weight = lastSet.weight
        }
        
        session.exercises[exerciseIndex].sets.append(newSet)
        currentSession = session
    }
    
    func removeSetFromExercise(_ exerciseId: UUID, setIndex: Int) {
        guard var session = currentSession,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseId }),
              setIndex < session.exercises[exerciseIndex].sets.count else { return }
        
        session.exercises[exerciseIndex].sets.remove(at: setIndex)
        currentSession = session
    }
    
    func cancelWorkout() {
        currentSession = nil
        isWorkoutActive = false
        stopRestTimer()
    }
    
    func finishWorkout(feeling: Int? = nil, notes: String? = nil) {
        guard var session = currentSession else { return }
        
        session.endTime = Date()
        session.isCompleted = true
        session.feeling = feeling
        session.notes = notes
        
        // Calculate total calories (rough estimate)
        let duration = session.duration
        let sets = session.totalSets
        session.calories = Double(sets) * 5 + (duration / 60) * 3 // Rough estimate
        
        // Check for PRs
        checkForPersonalRecords(session: session)
        
        // Add to history
        workoutHistory.insert(session, at: 0)
        
        // Update template completion count
        if let templateId = session.templateId,
           let index = templates.firstIndex(where: { $0.id == templateId }) {
            templates[index].timesCompleted += 1
            saveTemplates()
        }
        
        // Save and reset
        saveHistory()
        currentSession = nil
        isWorkoutActive = false
        stopRestTimer()
    }
    
    // MARK: - Rest Timer
    func startRestTimer(seconds: Int) {
        restTimerSeconds = seconds
        isRestTimerRunning = true
        
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.restTimerSeconds > 0 {
                self.restTimerSeconds -= 1
            } else {
                self.stopRestTimer()
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
    
    func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isRestTimerRunning = false
        restTimerSeconds = 0
    }
    
    func addTimeToRestTimer(_ seconds: Int) {
        restTimerSeconds += seconds
    }
    
    // MARK: - Personal Records
    private func checkForPersonalRecords(session: WorkoutSession) {
        for exercise in session.exercises {
            guard let topSet = exercise.topSet, topSet.weight > 0, topSet.reps > 0 else { continue }
            
            // Check weight PR
            let currentWeightPR = personalRecords.first {
                $0.exerciseId == exercise.exercise.id && $0.type == .weight
            }
            
            if currentWeightPR == nil || topSet.weight > currentWeightPR!.value {
                let newPR = PersonalRecord(
                    id: UUID(),
                    exerciseId: exercise.exercise.id,
                    exerciseName: exercise.exercise.name,
                    type: .weight,
                    value: topSet.weight,
                    reps: topSet.reps,
                    date: Date(),
                    previousValue: currentWeightPR?.value
                )
                
                // Remove old PR for same exercise/type
                personalRecords.removeAll {
                    $0.exerciseId == exercise.exercise.id && $0.type == .weight
                }
                personalRecords.append(newPR)
            }
            
            // Check estimated 1RM
            let estimated1RM = calculate1RM(weight: topSet.weight, reps: topSet.reps)
            let current1RMPR = personalRecords.first {
                $0.exerciseId == exercise.exercise.id && $0.type == .estimated1RM
            }
            
            if current1RMPR == nil || estimated1RM > current1RMPR!.value {
                let newPR = PersonalRecord(
                    id: UUID(),
                    exerciseId: exercise.exercise.id,
                    exerciseName: exercise.exercise.name,
                    type: .estimated1RM,
                    value: estimated1RM,
                    reps: 1,
                    date: Date(),
                    previousValue: current1RMPR?.value
                )
                
                personalRecords.removeAll {
                    $0.exerciseId == exercise.exercise.id && $0.type == .estimated1RM
                }
                personalRecords.append(newPR)
            }
        }
        
        savePersonalRecords()
    }
    
    private func calculate1RM(weight: Double, reps: Int) -> Double {
        // Brzycki formula
        guard reps > 0 && reps <= 12 else { return weight }
        return weight * (36 / (37 - Double(reps)))
    }
    
    // MARK: - Statistics
    func totalWorkoutsThisWeek() -> Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workoutHistory.filter { $0.startTime >= weekAgo }.count
    }
    
    func totalVolumeThisWeek() -> Double {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workoutHistory.filter { $0.startTime >= weekAgo }.reduce(0) { $0 + $1.totalVolume }
    }
    
    func workoutsForMuscle(_ muscle: MuscleGroup) -> [WorkoutSession] {
        workoutHistory.filter { session in
            session.musclesWorked.contains(muscle)
        }
    }
    
    func lastWorkoutForMuscle(_ muscle: MuscleGroup) -> WorkoutSession? {
        workoutsForMuscle(muscle).first
    }
    
    func daysSinceLastWorkout(for muscle: MuscleGroup) -> Int? {
        guard let lastWorkout = lastWorkoutForMuscle(muscle) else { return nil }
        return Calendar.current.dateComponents([.day], from: lastWorkout.startTime, to: Date()).day
    }
    
    func weeklyMuscleVolume() -> [MuscleGroup: Double] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentWorkouts = workoutHistory.filter { $0.startTime >= weekAgo }
        
        var volumeByMuscle: [MuscleGroup: Double] = [:]
        
        for workout in recentWorkouts {
            for exercise in workout.exercises {
                for muscle in exercise.exercise.primaryMuscles {
                    volumeByMuscle[muscle, default: 0] += exercise.totalVolume
                }
            }
        }
        
        return volumeByMuscle
    }
    
    func getHistoryForExercise(_ exerciseId: UUID) -> [(date: Date, weight: Double, reps: Int)] {
        var history: [(date: Date, weight: Double, reps: Int)] = []
        
        for session in workoutHistory {
            for exercise in session.exercises where exercise.exercise.id == exerciseId {
                if let topSet = exercise.topSet {
                    history.append((session.startTime, topSet.weight, topSet.reps))
                }
            }
        }
        
        return history.sorted { $0.date > $1.date }
    }
    
    func getPRForExercise(_ exerciseId: UUID, type: PersonalRecord.PRType = .weight) -> PersonalRecord? {
        personalRecords.first { $0.exerciseId == exerciseId && $0.type == type }
    }
}

// MARK: - Workout Summary Stats
struct WorkoutStats {
    let totalWorkouts: Int
    let totalVolume: Double
    let totalSets: Int
    let totalDuration: TimeInterval
    let avgDuration: TimeInterval
    let mostFrequentSplit: WorkoutSplitType?
    let muscleBalance: [MuscleCategory: Double]
    
    var formattedTotalVolume: String {
        if totalVolume >= 1000 {
            return String(format: "%.1fk kg", totalVolume / 1000)
        }
        return "\(Int(totalVolume)) kg"
    }
    
    var formattedAvgDuration: String {
        let minutes = Int(avgDuration / 60)
        return "\(minutes) min"
    }
}

extension WorkoutService {
    func getStats(for period: Int = 7) -> WorkoutStats {
        let cutoff = Calendar.current.date(byAdding: .day, value: -period, to: Date()) ?? Date()
        let recentWorkouts = workoutHistory.filter { $0.startTime >= cutoff }
        
        let totalVolume = recentWorkouts.reduce(0) { $0 + $1.totalVolume }
        let totalSets = recentWorkouts.reduce(0) { $0 + $1.totalSets }
        let totalDuration = recentWorkouts.reduce(0) { $0 + $1.duration }
        let avgDuration = recentWorkouts.isEmpty ? 0 : totalDuration / Double(recentWorkouts.count)
        
        // Find most frequent split
        let splitCounts = Dictionary(grouping: recentWorkouts, by: { $0.splitType })
        let mostFrequent = splitCounts.max { $0.value.count < $1.value.count }?.key
        
        // Calculate muscle balance
        var categoryVolume: [MuscleCategory: Double] = [:]
        for workout in recentWorkouts {
            for exercise in workout.exercises {
                if let category = exercise.exercise.primaryCategory {
                    categoryVolume[category, default: 0] += exercise.totalVolume
                }
            }
        }
        
        // Normalize to percentages
        let totalCategoryVolume = categoryVolume.values.reduce(0, +)
        var muscleBalance: [MuscleCategory: Double] = [:]
        if totalCategoryVolume > 0 {
            for (category, volume) in categoryVolume {
                muscleBalance[category] = (volume / totalCategoryVolume) * 100
            }
        }
        
        return WorkoutStats(
            totalWorkouts: recentWorkouts.count,
            totalVolume: totalVolume,
            totalSets: totalSets,
            totalDuration: totalDuration,
            avgDuration: avgDuration,
            mostFrequentSplit: mostFrequent,
            muscleBalance: muscleBalance
        )
    }
}

