import Foundation
import SwiftUI

// MARK: - Muscle Groups
enum MuscleGroup: String, CaseIterable, Codable, Identifiable {
    // Upper Body - Push
    case chest = "Chest"
    case shoulders = "Shoulders"
    case triceps = "Triceps"
    
    // Upper Body - Pull
    case back = "Back"
    case lats = "Lats"
    case biceps = "Biceps"
    case rearDelts = "Rear Delts"
    case traps = "Traps"
    
    // Core
    case abs = "Abs"
    case obliques = "Obliques"
    case lowerBack = "Lower Back"
    
    // Lower Body
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case hipFlexors = "Hip Flexors"
    case adductors = "Adductors"
    
    // Arms
    case forearms = "Forearms"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .shoulders: return "figure.arms.open"
        case .triceps: return "figure.boxing"
        case .back, .lats: return "figure.rowing"
        case .biceps: return "figure.strengthtraining.functional"
        case .rearDelts: return "figure.martial.arts"
        case .traps: return "figure.climbing"
        case .abs, .obliques: return "figure.core.training"
        case .lowerBack: return "figure.flexibility"
        case .quads, .hamstrings: return "figure.run"
        case .glutes: return "figure.step.training"
        case .calves: return "figure.stairs"
        case .hipFlexors, .adductors: return "figure.cooldown"
        case .forearms: return "hand.raised.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .chest: return .red
        case .shoulders: return .orange
        case .triceps: return .yellow
        case .back, .lats: return .blue
        case .biceps: return .purple
        case .rearDelts: return .pink
        case .traps: return .cyan
        case .abs, .obliques: return .green
        case .lowerBack: return .mint
        case .quads: return .indigo
        case .hamstrings: return .brown
        case .glutes: return .pink
        case .calves: return .teal
        case .hipFlexors, .adductors: return .gray
        case .forearms: return .orange
        }
    }
    
    var category: MuscleCategory {
        switch self {
        case .chest, .shoulders, .triceps:
            return .push
        case .back, .lats, .biceps, .rearDelts, .traps, .forearms:
            return .pull
        case .quads, .hamstrings, .glutes, .calves, .hipFlexors, .adductors:
            return .legs
        case .abs, .obliques, .lowerBack:
            return .core
        }
    }
}

enum MuscleCategory: String, CaseIterable, Codable {
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case core = "Core"
    
    var muscles: [MuscleGroup] {
        MuscleGroup.allCases.filter { $0.category == self }
    }
    
    var color: Color {
        switch self {
        case .push: return .red
        case .pull: return .blue
        case .legs: return .purple
        case .core: return .green
        }
    }
}

// MARK: - Equipment
enum Equipment: String, CaseIterable, Codable, Identifiable {
    case barbell = "Barbell"
    case dumbbell = "Dumbbell"
    case cable = "Cable"
    case machine = "Machine"
    case bodyweight = "Bodyweight"
    case kettlebell = "Kettlebell"
    case resistanceBand = "Resistance Band"
    case ezBar = "EZ Bar"
    case smithMachine = "Smith Machine"
    case trapBar = "Trap Bar"
    case pullupBar = "Pull-up Bar"
    case dipStation = "Dip Station"
    case bench = "Bench"
    case inclineBench = "Incline Bench"
    case declineBench = "Decline Bench"
    case box = "Box/Platform"
    case medicineBall = "Medicine Ball"
    case foam = "Foam Roller"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .barbell, .ezBar, .trapBar: return "line.horizontal.3"
        case .dumbbell: return "dumbbell.fill"
        case .cable: return "arrow.up.and.down"
        case .machine: return "gearshape.fill"
        case .bodyweight: return "figure.stand"
        case .kettlebell: return "drop.fill"
        case .resistanceBand: return "circle.dotted"
        case .smithMachine: return "square.grid.3x3.topleft.filled"
        case .pullupBar: return "rectangle.and.arrow.up.right.and.arrow.down.left"
        case .dipStation: return "arrow.down.to.line"
        case .bench, .inclineBench, .declineBench: return "bed.double.fill"
        case .box: return "square.fill"
        case .medicineBall: return "circle.fill"
        case .foam: return "capsule.fill"
        }
    }
}

// MARK: - Exercise Difficulty
enum ExerciseDifficulty: String, CaseIterable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    
    var color: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

// MARK: - Exercise Type
enum ExerciseType: String, CaseIterable, Codable {
    case compound = "Compound"
    case isolation = "Isolation"
    case cardio = "Cardio"
    case flexibility = "Flexibility"
    case plyometric = "Plyometric"
}

// MARK: - Exercise Model
struct Exercise: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]
    let equipment: [Equipment]
    let difficulty: ExerciseDifficulty
    let exerciseType: ExerciseType
    let instructions: [String]
    let tips: [String]
    let videoURL: String?
    let thumbnailName: String?
    
    // For tracking
    var isFavorite: Bool = false
    
    init(
        id: UUID = UUID(),
        name: String,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup] = [],
        equipment: [Equipment],
        difficulty: ExerciseDifficulty = .intermediate,
        exerciseType: ExerciseType = .compound,
        instructions: [String] = [],
        tips: [String] = [],
        videoURL: String? = nil,
        thumbnailName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.difficulty = difficulty
        self.exerciseType = exerciseType
        self.instructions = instructions
        self.tips = tips
        self.videoURL = videoURL
        self.thumbnailName = thumbnailName
    }
    
    var allMuscles: [MuscleGroup] {
        primaryMuscles + secondaryMuscles
    }
    
    var primaryCategory: MuscleCategory? {
        primaryMuscles.first?.category
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Exercise, rhs: Exercise) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Workout Set
struct WorkoutSet: Identifiable, Codable {
    let id: UUID
    var weight: Double // in kg or lbs based on user preference
    var reps: Int
    var rpe: Int? // Rate of Perceived Exertion (1-10)
    var isWarmup: Bool
    var isDropSet: Bool
    var isFailure: Bool
    var restSeconds: Int?
    var notes: String?
    var timestamp: Date
    var isCompleted: Bool
    
    init(
        id: UUID = UUID(),
        weight: Double = 0,
        reps: Int = 0,
        rpe: Int? = nil,
        isWarmup: Bool = false,
        isDropSet: Bool = false,
        isFailure: Bool = false,
        restSeconds: Int? = nil,
        notes: String? = nil,
        timestamp: Date = Date(),
        isCompleted: Bool = false
    ) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.isDropSet = isDropSet
        self.isFailure = isFailure
        self.restSeconds = restSeconds
        self.notes = notes
        self.timestamp = timestamp
        self.isCompleted = isCompleted
    }
    
    var volume: Double {
        weight * Double(reps)
    }
    
    var formattedWeight: String {
        if weight == floor(weight) {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - Exercise in Workout (with sets)
struct WorkoutExercise: Identifiable, Codable {
    let id: UUID
    let exercise: Exercise
    var sets: [WorkoutSet]
    var targetSets: Int
    var targetReps: ClosedRange<Int>
    var targetRPE: Int?
    var restSeconds: Int
    var notes: String?
    var supersetGroupId: UUID? // For grouping supersets
    var order: Int
    
    init(
        id: UUID = UUID(),
        exercise: Exercise,
        sets: [WorkoutSet] = [],
        targetSets: Int = 3,
        targetReps: ClosedRange<Int> = 8...12,
        targetRPE: Int? = 8,
        restSeconds: Int = 90,
        notes: String? = nil,
        supersetGroupId: UUID? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.exercise = exercise
        self.sets = sets
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
        self.notes = notes
        self.supersetGroupId = supersetGroupId
        self.order = order
    }
    
    var completedSets: Int {
        sets.filter { $0.isCompleted && !$0.isWarmup }.count
    }
    
    var totalVolume: Double {
        sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.volume }
    }
    
    var topSet: WorkoutSet? {
        sets.filter { !$0.isWarmup }.max { $0.weight < $1.weight }
    }
    
    var isComplete: Bool {
        completedSets >= targetSets
    }
    
    mutating func addSet(_ set: WorkoutSet = WorkoutSet()) {
        var newSet = set
        // Copy weight from previous set if available
        if let lastSet = sets.last {
            newSet = WorkoutSet(
                weight: lastSet.weight,
                reps: lastSet.reps
            )
        }
        sets.append(newSet)
    }
}

// MARK: - Split Types
enum WorkoutSplitType: String, CaseIterable, Codable {
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case upper = "Upper"
    case lower = "Lower"
    case fullBody = "Full Body"
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .push: return "arrow.up.circle.fill"
        case .pull: return "arrow.down.circle.fill"
        case .legs: return "figure.run.circle.fill"
        case .upper: return "figure.arms.open"
        case .lower: return "figure.step.training"
        case .fullBody: return "figure.strengthtraining.traditional"
        case .chest: return "heart.circle.fill"
        case .back: return "arrow.uturn.backward.circle.fill"
        case .shoulders: return "figure.boxing"
        case .arms: return "figure.strengthtraining.functional"
        case .custom: return "star.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .push: return .red
        case .pull: return .blue
        case .legs: return .purple
        case .upper: return .orange
        case .lower: return .indigo
        case .fullBody: return .green
        case .chest: return .pink
        case .back: return .cyan
        case .shoulders: return .yellow
        case .arms: return .mint
        case .custom: return .gray
        }
    }
    
    var targetMuscles: [MuscleGroup] {
        switch self {
        case .push: return [.chest, .shoulders, .triceps]
        case .pull: return [.back, .lats, .biceps, .rearDelts]
        case .legs: return [.quads, .hamstrings, .glutes, .calves]
        case .upper: return [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: return [.quads, .hamstrings, .glutes, .calves, .hipFlexors]
        case .fullBody: return MuscleGroup.allCases.filter { $0.category != .core }
        case .chest: return [.chest, .triceps, .shoulders]
        case .back: return [.back, .lats, .biceps, .rearDelts]
        case .shoulders: return [.shoulders, .traps, .rearDelts]
        case .arms: return [.biceps, .triceps, .forearms]
        case .custom: return []
        }
    }
}

// MARK: - Workout Template (Plan)
struct WorkoutTemplate: Identifiable, Codable {
    let id: UUID
    var name: String
    var splitType: WorkoutSplitType
    var exercises: [WorkoutExercise]
    var estimatedDuration: TimeInterval // in seconds
    var difficulty: ExerciseDifficulty
    var notes: String?
    var createdAt: Date
    var lastUsed: Date?
    var timesCompleted: Int
    var isAIGenerated: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        splitType: WorkoutSplitType,
        exercises: [WorkoutExercise] = [],
        estimatedDuration: TimeInterval = 3600, // 1 hour default
        difficulty: ExerciseDifficulty = .intermediate,
        notes: String? = nil,
        createdAt: Date = Date(),
        lastUsed: Date? = nil,
        timesCompleted: Int = 0,
        isAIGenerated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.splitType = splitType
        self.exercises = exercises
        self.estimatedDuration = estimatedDuration
        self.difficulty = difficulty
        self.notes = notes
        self.createdAt = createdAt
        self.lastUsed = lastUsed
        self.timesCompleted = timesCompleted
        self.isAIGenerated = isAIGenerated
    }
    
    var targetMuscles: [MuscleGroup] {
        Array(Set(exercises.flatMap { $0.exercise.primaryMuscles }))
    }
    
    var formattedDuration: String {
        let minutes = Int(estimatedDuration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes) min"
    }
}

// MARK: - Active Workout Session
struct WorkoutSession: Identifiable, Codable {
    let id: UUID
    var templateId: UUID?
    var name: String
    var splitType: WorkoutSplitType
    var exercises: [WorkoutExercise]
    var startTime: Date
    var endTime: Date?
    var notes: String?
    var feeling: Int? // 1-5 how they felt
    var calories: Double?
    var isCompleted: Bool
    
    init(
        id: UUID = UUID(),
        templateId: UUID? = nil,
        name: String,
        splitType: WorkoutSplitType,
        exercises: [WorkoutExercise] = [],
        startTime: Date = Date(),
        endTime: Date? = nil,
        notes: String? = nil,
        feeling: Int? = nil,
        calories: Double? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.splitType = splitType
        self.exercises = exercises
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.feeling = feeling
        self.calories = calories
        self.isCompleted = isCompleted
    }
    
    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
    
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var totalVolume: Double {
        exercises.reduce(0) { $0 + $1.totalVolume }
    }
    
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.completedSets }
    }
    
    var completedExercises: Int {
        exercises.filter { $0.isComplete }.count
    }
    
    var musclesWorked: [MuscleGroup] {
        Array(Set(exercises.flatMap { $0.exercise.primaryMuscles }))
    }
}

// MARK: - Personal Record
struct PersonalRecord: Identifiable, Codable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    let type: PRType
    let value: Double
    let reps: Int?
    let date: Date
    let previousValue: Double?
    
    enum PRType: String, Codable {
        case weight = "Weight"
        case volume = "Volume"
        case reps = "Reps"
        case estimated1RM = "Estimated 1RM"
    }
    
    var improvement: Double? {
        guard let previous = previousValue else { return nil }
        return ((value - previous) / previous) * 100
    }
}

