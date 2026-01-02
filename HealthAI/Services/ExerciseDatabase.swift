import Foundation
import SwiftUI
import Combine

// MARK: - Exercise Database Service
@MainActor
class ExerciseDatabase: ObservableObject {
    static let shared = ExerciseDatabase()
    
    @Published var exercises: [Exercise] = []
    @Published var favoriteExerciseIds: Set<UUID> = []
    @Published var recentExerciseIds: [UUID] = []
    
    private let favoritesKey = "favoriteExercises"
    private let recentsKey = "recentExercises"
    
    init() {
        loadExercises()
        loadFavorites()
        loadRecents()
    }
    
    // MARK: - Loading
    private func loadExercises() {
        exercises = Self.allExercises
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            favoriteExerciseIds = ids
        }
    }
    
    private func loadRecents() {
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            recentExerciseIds = ids
        }
    }
    
    // MARK: - Saving
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoriteExerciseIds) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
    
    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentExerciseIds) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
    
    // MARK: - Public Methods
    func toggleFavorite(_ exercise: Exercise) {
        if favoriteExerciseIds.contains(exercise.id) {
            favoriteExerciseIds.remove(exercise.id)
        } else {
            favoriteExerciseIds.insert(exercise.id)
        }
        saveFavorites()
    }
    
    func isFavorite(_ exercise: Exercise) -> Bool {
        favoriteExerciseIds.contains(exercise.id)
    }
    
    func addToRecent(_ exercise: Exercise) {
        recentExerciseIds.removeAll { $0 == exercise.id }
        recentExerciseIds.insert(exercise.id, at: 0)
        if recentExerciseIds.count > 20 {
            recentExerciseIds = Array(recentExerciseIds.prefix(20))
        }
        saveRecents()
    }
    
    func getExercise(by id: UUID) -> Exercise? {
        exercises.first { $0.id == id }
    }
    
    // MARK: - Filtering
    func exercises(for muscles: [MuscleGroup]) -> [Exercise] {
        exercises.filter { exercise in
            !Set(exercise.primaryMuscles).isDisjoint(with: Set(muscles))
        }
    }
    
    func exercises(for equipment: [Equipment]) -> [Exercise] {
        exercises.filter { exercise in
            !Set(exercise.equipment).isDisjoint(with: Set(equipment))
        }
    }
    
    func exercises(for splitType: WorkoutSplitType) -> [Exercise] {
        exercises(for: splitType.targetMuscles)
    }
    
    func search(_ query: String) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        let lowercased = query.lowercased()
        return exercises.filter { exercise in
            exercise.name.lowercased().contains(lowercased) ||
            exercise.primaryMuscles.contains { $0.rawValue.lowercased().contains(lowercased) } ||
            exercise.equipment.contains { $0.rawValue.lowercased().contains(lowercased) }
        }
    }
    
    var favoriteExercises: [Exercise] {
        exercises.filter { favoriteExerciseIds.contains($0.id) }
    }
    
    var recentExercises: [Exercise] {
        recentExerciseIds.compactMap { id in
            exercises.first { $0.id == id }
        }
    }
    
    // MARK: - Exercise Database
    static let allExercises: [Exercise] = [
        // MARK: - Chest Exercises
        Exercise(
            name: "Barbell Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .shoulders],
            equipment: [.barbell, .bench],
            difficulty: .intermediate,
            exerciseType: .compound,
            instructions: [
                "Lie flat on a bench with feet firmly on the ground",
                "Grip the bar slightly wider than shoulder-width",
                "Unrack the bar and lower it to mid-chest",
                "Press the bar up until arms are fully extended",
                "Keep your back slightly arched and shoulder blades retracted"
            ],
            tips: [
                "Drive through your heels for stability",
                "Keep elbows at 45-degree angle",
                "Touch your chest without bouncing"
            ]
        ),
        Exercise(
            name: "Incline Dumbbell Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.shoulders, .triceps],
            equipment: [.dumbbell, .inclineBench],
            difficulty: .intermediate,
            instructions: [
                "Set bench to 30-45 degree incline",
                "Hold dumbbells at shoulder level",
                "Press up and together at the top",
                "Lower with control to shoulder level"
            ],
            tips: [
                "Don't flare elbows excessively",
                "Squeeze chest at the top"
            ]
        ),
        Exercise(
            name: "Dumbbell Fly",
            primaryMuscles: [.chest],
            equipment: [.dumbbell, .bench],
            difficulty: .beginner,
            exerciseType: .isolation,
            instructions: [
                "Lie on bench with dumbbells above chest",
                "Lower weights in an arc to the sides",
                "Keep slight bend in elbows throughout",
                "Bring weights back together at the top"
            ]
        ),
        Exercise(
            name: "Cable Crossover",
            primaryMuscles: [.chest],
            equipment: [.cable],
            difficulty: .beginner,
            exerciseType: .isolation,
            instructions: [
                "Set cables to high position",
                "Step forward with arms extended",
                "Bring hands together in front of chest",
                "Squeeze chest and return with control"
            ]
        ),
        Exercise(
            name: "Push-Ups",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .shoulders, .abs],
            equipment: [.bodyweight],
            difficulty: .beginner,
            exerciseType: .compound
        ),
        Exercise(
            name: "Decline Bench Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .shoulders],
            equipment: [.barbell, .declineBench],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Machine Chest Press",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .shoulders],
            equipment: [.machine],
            difficulty: .beginner
        ),
        Exercise(
            name: "Dips (Chest Focus)",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .shoulders],
            equipment: [.dipStation, .bodyweight],
            difficulty: .intermediate,
            instructions: [
                "Lean forward at 30-45 degrees",
                "Lower until you feel a stretch in chest",
                "Push up to starting position"
            ]
        ),
        
        // MARK: - Back Exercises
        Exercise(
            name: "Barbell Row",
            primaryMuscles: [.back, .lats],
            secondaryMuscles: [.biceps, .rearDelts],
            equipment: [.barbell],
            difficulty: .intermediate,
            exerciseType: .compound,
            instructions: [
                "Bend at hips, keeping back straight",
                "Grip bar slightly wider than shoulders",
                "Pull bar to lower chest",
                "Squeeze shoulder blades together at top",
                "Lower with control"
            ]
        ),
        Exercise(
            name: "Pull-Ups",
            primaryMuscles: [.lats, .back],
            secondaryMuscles: [.biceps, .rearDelts],
            equipment: [.pullupBar, .bodyweight],
            difficulty: .intermediate,
            exerciseType: .compound
        ),
        Exercise(
            name: "Lat Pulldown",
            primaryMuscles: [.lats],
            secondaryMuscles: [.biceps, .rearDelts],
            equipment: [.cable, .machine],
            difficulty: .beginner
        ),
        Exercise(
            name: "Seated Cable Row",
            primaryMuscles: [.back],
            secondaryMuscles: [.biceps, .lats],
            equipment: [.cable],
            difficulty: .beginner
        ),
        Exercise(
            name: "Dumbbell Row",
            primaryMuscles: [.back, .lats],
            secondaryMuscles: [.biceps],
            equipment: [.dumbbell, .bench],
            difficulty: .beginner
        ),
        Exercise(
            name: "T-Bar Row",
            primaryMuscles: [.back],
            secondaryMuscles: [.biceps, .lats],
            equipment: [.barbell, .machine],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Deadlift",
            primaryMuscles: [.back, .hamstrings, .glutes],
            secondaryMuscles: [.quads, .forearms, .traps],
            equipment: [.barbell],
            difficulty: .advanced,
            exerciseType: .compound,
            instructions: [
                "Stand with feet hip-width apart",
                "Grip bar just outside legs",
                "Keep chest up and back flat",
                "Drive through heels and extend hips",
                "Lock out at the top"
            ]
        ),
        Exercise(
            name: "Face Pulls",
            primaryMuscles: [.rearDelts],
            secondaryMuscles: [.traps, .back],
            equipment: [.cable],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Chin-Ups",
            primaryMuscles: [.lats, .biceps],
            secondaryMuscles: [.back],
            equipment: [.pullupBar, .bodyweight],
            difficulty: .intermediate
        ),
        
        // MARK: - Shoulder Exercises
        Exercise(
            name: "Overhead Press",
            primaryMuscles: [.shoulders],
            secondaryMuscles: [.triceps, .traps],
            equipment: [.barbell],
            difficulty: .intermediate,
            exerciseType: .compound
        ),
        Exercise(
            name: "Dumbbell Shoulder Press",
            primaryMuscles: [.shoulders],
            secondaryMuscles: [.triceps],
            equipment: [.dumbbell],
            difficulty: .beginner
        ),
        Exercise(
            name: "Lateral Raises",
            primaryMuscles: [.shoulders],
            equipment: [.dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Front Raises",
            primaryMuscles: [.shoulders],
            equipment: [.dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Reverse Fly",
            primaryMuscles: [.rearDelts],
            secondaryMuscles: [.traps],
            equipment: [.dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Arnold Press",
            primaryMuscles: [.shoulders],
            secondaryMuscles: [.triceps],
            equipment: [.dumbbell],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Upright Row",
            primaryMuscles: [.shoulders, .traps],
            equipment: [.barbell, .dumbbell],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Cable Lateral Raise",
            primaryMuscles: [.shoulders],
            equipment: [.cable],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Machine Shoulder Press",
            primaryMuscles: [.shoulders],
            secondaryMuscles: [.triceps],
            equipment: [.machine],
            difficulty: .beginner
        ),
        
        // MARK: - Arm Exercises (Biceps)
        Exercise(
            name: "Barbell Curl",
            primaryMuscles: [.biceps],
            secondaryMuscles: [.forearms],
            equipment: [.barbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Dumbbell Curl",
            primaryMuscles: [.biceps],
            equipment: [.dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Hammer Curl",
            primaryMuscles: [.biceps, .forearms],
            equipment: [.dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Preacher Curl",
            primaryMuscles: [.biceps],
            equipment: [.ezBar, .dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Incline Dumbbell Curl",
            primaryMuscles: [.biceps],
            equipment: [.dumbbell, .inclineBench],
            difficulty: .intermediate,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Cable Curl",
            primaryMuscles: [.biceps],
            equipment: [.cable],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Concentration Curl",
            primaryMuscles: [.biceps],
            equipment: [.dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        
        // MARK: - Arm Exercises (Triceps)
        Exercise(
            name: "Tricep Pushdown",
            primaryMuscles: [.triceps],
            equipment: [.cable],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Skull Crushers",
            primaryMuscles: [.triceps],
            equipment: [.ezBar, .barbell],
            difficulty: .intermediate,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Overhead Tricep Extension",
            primaryMuscles: [.triceps],
            equipment: [.dumbbell, .cable],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Tricep Dips",
            primaryMuscles: [.triceps],
            secondaryMuscles: [.chest, .shoulders],
            equipment: [.dipStation, .bodyweight],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Close Grip Bench Press",
            primaryMuscles: [.triceps],
            secondaryMuscles: [.chest, .shoulders],
            equipment: [.barbell, .bench],
            difficulty: .intermediate,
            exerciseType: .compound
        ),
        Exercise(
            name: "Tricep Kickback",
            primaryMuscles: [.triceps],
            equipment: [.dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        
        // MARK: - Leg Exercises
        Exercise(
            name: "Barbell Squat",
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings, .lowerBack, .abs],
            equipment: [.barbell],
            difficulty: .intermediate,
            exerciseType: .compound,
            instructions: [
                "Position bar on upper back",
                "Stand with feet shoulder-width apart",
                "Descend until thighs are parallel",
                "Drive through heels to stand"
            ]
        ),
        Exercise(
            name: "Leg Press",
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            equipment: [.machine],
            difficulty: .beginner
        ),
        Exercise(
            name: "Romanian Deadlift",
            primaryMuscles: [.hamstrings, .glutes],
            secondaryMuscles: [.lowerBack],
            equipment: [.barbell, .dumbbell],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Leg Curl",
            primaryMuscles: [.hamstrings],
            equipment: [.machine],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Leg Extension",
            primaryMuscles: [.quads],
            equipment: [.machine],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Bulgarian Split Squat",
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            equipment: [.dumbbell, .bodyweight],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Lunges",
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            equipment: [.dumbbell, .bodyweight],
            difficulty: .beginner
        ),
        Exercise(
            name: "Hack Squat",
            primaryMuscles: [.quads],
            secondaryMuscles: [.glutes],
            equipment: [.machine],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Hip Thrust",
            primaryMuscles: [.glutes],
            secondaryMuscles: [.hamstrings],
            equipment: [.barbell, .bench],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Goblet Squat",
            primaryMuscles: [.quads, .glutes],
            equipment: [.dumbbell, .kettlebell],
            difficulty: .beginner
        ),
        Exercise(
            name: "Front Squat",
            primaryMuscles: [.quads],
            secondaryMuscles: [.glutes, .abs],
            equipment: [.barbell],
            difficulty: .advanced
        ),
        Exercise(
            name: "Sumo Deadlift",
            primaryMuscles: [.glutes, .hamstrings],
            secondaryMuscles: [.quads, .back, .adductors],
            equipment: [.barbell],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Good Mornings",
            primaryMuscles: [.hamstrings, .lowerBack],
            secondaryMuscles: [.glutes],
            equipment: [.barbell],
            difficulty: .intermediate
        ),
        
        // MARK: - Calf Exercises
        Exercise(
            name: "Standing Calf Raise",
            primaryMuscles: [.calves],
            equipment: [.machine, .dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Seated Calf Raise",
            primaryMuscles: [.calves],
            equipment: [.machine],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        
        // MARK: - Core Exercises
        Exercise(
            name: "Plank",
            primaryMuscles: [.abs],
            secondaryMuscles: [.obliques, .lowerBack],
            equipment: [.bodyweight],
            difficulty: .beginner
        ),
        Exercise(
            name: "Hanging Leg Raise",
            primaryMuscles: [.abs, .hipFlexors],
            equipment: [.pullupBar],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Cable Crunch",
            primaryMuscles: [.abs],
            equipment: [.cable],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Russian Twist",
            primaryMuscles: [.obliques],
            secondaryMuscles: [.abs],
            equipment: [.bodyweight, .medicineBall],
            difficulty: .beginner
        ),
        Exercise(
            name: "Ab Wheel Rollout",
            primaryMuscles: [.abs],
            secondaryMuscles: [.lowerBack, .shoulders],
            equipment: [.bodyweight],
            difficulty: .intermediate
        ),
        Exercise(
            name: "Dead Bug",
            primaryMuscles: [.abs],
            secondaryMuscles: [.hipFlexors],
            equipment: [.bodyweight],
            difficulty: .beginner
        ),
        Exercise(
            name: "Mountain Climbers",
            primaryMuscles: [.abs],
            secondaryMuscles: [.shoulders, .quads],
            equipment: [.bodyweight],
            difficulty: .beginner,
            exerciseType: .cardio
        ),
        
        // MARK: - Trap Exercises
        Exercise(
            name: "Barbell Shrugs",
            primaryMuscles: [.traps],
            equipment: [.barbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Dumbbell Shrugs",
            primaryMuscles: [.traps],
            equipment: [.dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        
        // MARK: - Forearm Exercises
        Exercise(
            name: "Wrist Curls",
            primaryMuscles: [.forearms],
            equipment: [.barbell, .dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Reverse Wrist Curls",
            primaryMuscles: [.forearms],
            equipment: [.barbell, .dumbbell],
            difficulty: .beginner,
            exerciseType: .isolation
        ),
        Exercise(
            name: "Farmer's Walk",
            primaryMuscles: [.forearms, .traps],
            secondaryMuscles: [.abs],
            equipment: [.dumbbell, .kettlebell],
            difficulty: .intermediate
        )
    ]
}

// MARK: - Suggested Workout Templates
extension ExerciseDatabase {
    func generateWorkoutTemplate(for splitType: WorkoutSplitType, difficulty: ExerciseDifficulty = .intermediate) -> WorkoutTemplate {
        let relevantExercises = exercises(for: splitType).filter { $0.difficulty == difficulty || $0.difficulty == .beginner }
        
        var selectedExercises: [WorkoutExercise] = []
        var order = 0
        
        // Select exercises based on split type
        switch splitType {
        case .push:
            selectedExercises = selectExercisesForPush(from: relevantExercises, order: &order)
        case .pull:
            selectedExercises = selectExercisesForPull(from: relevantExercises, order: &order)
        case .legs:
            selectedExercises = selectExercisesForLegs(from: relevantExercises, order: &order)
        case .upper:
            selectedExercises = selectExercisesForUpper(from: relevantExercises, order: &order)
        case .lower:
            selectedExercises = selectExercisesForLegs(from: relevantExercises, order: &order)
        case .fullBody:
            selectedExercises = selectExercisesForFullBody(from: exercises, order: &order)
        default:
            selectedExercises = selectExercisesForPush(from: relevantExercises, order: &order)
        }
        
        return WorkoutTemplate(
            name: "\(splitType.rawValue) Day",
            splitType: splitType,
            exercises: selectedExercises,
            estimatedDuration: TimeInterval(selectedExercises.count * 10 * 60), // 10 min per exercise
            difficulty: difficulty,
            isAIGenerated: false
        )
    }
    
    private func selectExercisesForPush(from exercises: [Exercise], order: inout Int) -> [WorkoutExercise] {
        var result: [WorkoutExercise] = []
        
        // Compound chest
        if let bench = exercises.first(where: { $0.name.contains("Bench Press") && $0.equipment.contains(.barbell) }) {
            result.append(WorkoutExercise(exercise: bench, targetSets: 4, targetReps: 6...10, restSeconds: 180, order: order))
            order += 1
        }
        
        // Incline
        if let incline = exercises.first(where: { $0.name.contains("Incline") && $0.name.contains("Press") }) {
            result.append(WorkoutExercise(exercise: incline, targetSets: 3, targetReps: 8...12, restSeconds: 120, order: order))
            order += 1
        }
        
        // Shoulder press
        if let ohp = exercises.first(where: { $0.name.contains("Overhead Press") || $0.name.contains("Shoulder Press") }) {
            result.append(WorkoutExercise(exercise: ohp, targetSets: 3, targetReps: 8...12, restSeconds: 120, order: order))
            order += 1
        }
        
        // Lateral raises
        if let laterals = exercises.first(where: { $0.name.contains("Lateral Raise") }) {
            result.append(WorkoutExercise(exercise: laterals, targetSets: 3, targetReps: 12...15, restSeconds: 60, order: order))
            order += 1
        }
        
        // Triceps
        if let triceps = exercises.first(where: { $0.name.contains("Tricep") }) {
            result.append(WorkoutExercise(exercise: triceps, targetSets: 3, targetReps: 10...15, restSeconds: 60, order: order))
            order += 1
        }
        
        return result
    }
    
    private func selectExercisesForPull(from exercises: [Exercise], order: inout Int) -> [WorkoutExercise] {
        var result: [WorkoutExercise] = []
        
        // Compound back
        if let rows = exercises.first(where: { $0.name.contains("Barbell Row") }) {
            result.append(WorkoutExercise(exercise: rows, targetSets: 4, targetReps: 6...10, restSeconds: 180, order: order))
            order += 1
        }
        
        // Lat pulldown or pullups
        if let pulldown = exercises.first(where: { $0.name.contains("Pulldown") || $0.name.contains("Pull-Up") }) {
            result.append(WorkoutExercise(exercise: pulldown, targetSets: 3, targetReps: 8...12, restSeconds: 120, order: order))
            order += 1
        }
        
        // Cable row
        if let cableRow = exercises.first(where: { $0.name.contains("Cable Row") || $0.name.contains("Dumbbell Row") }) {
            result.append(WorkoutExercise(exercise: cableRow, targetSets: 3, targetReps: 10...12, restSeconds: 90, order: order))
            order += 1
        }
        
        // Face pulls
        if let facePulls = exercises.first(where: { $0.name.contains("Face Pull") }) {
            result.append(WorkoutExercise(exercise: facePulls, targetSets: 3, targetReps: 15...20, restSeconds: 60, order: order))
            order += 1
        }
        
        // Biceps
        if let curls = exercises.first(where: { $0.name.contains("Curl") }) {
            result.append(WorkoutExercise(exercise: curls, targetSets: 3, targetReps: 10...12, restSeconds: 60, order: order))
            order += 1
        }
        
        return result
    }
    
    private func selectExercisesForLegs(from exercises: [Exercise], order: inout Int) -> [WorkoutExercise] {
        var result: [WorkoutExercise] = []
        
        // Squat
        if let squat = exercises.first(where: { $0.name.contains("Squat") && $0.equipment.contains(.barbell) }) {
            result.append(WorkoutExercise(exercise: squat, targetSets: 4, targetReps: 6...10, restSeconds: 180, order: order))
            order += 1
        }
        
        // RDL
        if let rdl = exercises.first(where: { $0.name.contains("Romanian") }) {
            result.append(WorkoutExercise(exercise: rdl, targetSets: 3, targetReps: 8...12, restSeconds: 120, order: order))
            order += 1
        }
        
        // Leg press
        if let legPress = exercises.first(where: { $0.name.contains("Leg Press") }) {
            result.append(WorkoutExercise(exercise: legPress, targetSets: 3, targetReps: 10...15, restSeconds: 120, order: order))
            order += 1
        }
        
        // Leg curl
        if let legCurl = exercises.first(where: { $0.name.contains("Leg Curl") }) {
            result.append(WorkoutExercise(exercise: legCurl, targetSets: 3, targetReps: 10...15, restSeconds: 60, order: order))
            order += 1
        }
        
        // Calf raise
        if let calves = exercises.first(where: { $0.name.contains("Calf") }) {
            result.append(WorkoutExercise(exercise: calves, targetSets: 4, targetReps: 12...20, restSeconds: 60, order: order))
            order += 1
        }
        
        return result
    }
    
    private func selectExercisesForUpper(from exercises: [Exercise], order: inout Int) -> [WorkoutExercise] {
        var push = selectExercisesForPush(from: exercises, order: &order)
        let pull = selectExercisesForPull(from: exercises, order: &order)
        push.append(contentsOf: pull)
        return Array(push.prefix(8)) // Limit to 8 exercises
    }
    
    private func selectExercisesForFullBody(from exercises: [Exercise], order: inout Int) -> [WorkoutExercise] {
        var result: [WorkoutExercise] = []
        
        // One compound per major movement
        if let squat = exercises.first(where: { $0.name.contains("Squat") && $0.equipment.contains(.barbell) }) {
            result.append(WorkoutExercise(exercise: squat, targetSets: 3, targetReps: 8...10, restSeconds: 180, order: order))
            order += 1
        }
        
        if let bench = exercises.first(where: { $0.name.contains("Bench Press") && $0.equipment.contains(.barbell) }) {
            result.append(WorkoutExercise(exercise: bench, targetSets: 3, targetReps: 8...10, restSeconds: 120, order: order))
            order += 1
        }
        
        if let row = exercises.first(where: { $0.name.contains("Barbell Row") }) {
            result.append(WorkoutExercise(exercise: row, targetSets: 3, targetReps: 8...10, restSeconds: 120, order: order))
            order += 1
        }
        
        if let ohp = exercises.first(where: { $0.name.contains("Overhead Press") }) {
            result.append(WorkoutExercise(exercise: ohp, targetSets: 3, targetReps: 8...10, restSeconds: 120, order: order))
            order += 1
        }
        
        if let rdl = exercises.first(where: { $0.name.contains("Romanian") }) {
            result.append(WorkoutExercise(exercise: rdl, targetSets: 3, targetReps: 10...12, restSeconds: 120, order: order))
            order += 1
        }
        
        return result
    }
}

