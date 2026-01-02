import SwiftUI

struct WorkoutPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var workoutService = WorkoutService.shared
    @StateObject private var exerciseDatabase = ExerciseDatabase.shared
    @EnvironmentObject var aiService: AIService
    
    @State private var planName = ""
    @State private var selectedSplit: WorkoutSplitType = .push
    @State private var exercises: [WorkoutExercise] = []
    @State private var showingExercisePicker = false
    @State private var showingAIGenerator = false
    @State private var isGeneratingPlan = false
    
    var editingTemplate: WorkoutTemplate?
    
    init(editingTemplate: WorkoutTemplate? = nil) {
        self.editingTemplate = editingTemplate
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Plan Info Section
                        planInfoSection
                        
                        // AI Generator Button
                        aiGeneratorButton
                        
                        // Exercises Section
                        exercisesSection
                        
                        // Add Exercise Button
                        addExerciseButton
                    }
                    .padding(20)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle(editingTemplate == nil ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .fontWeight(.semibold)
                    .disabled(planName.isEmpty || exercises.isEmpty)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExerciseLibraryView(mode: .picker) { exercise in
                    addExercise(exercise)
                    showingExercisePicker = false
                }
            }
            .sheet(isPresented: $showingAIGenerator) {
                AIWorkoutGeneratorSheet(
                    splitType: selectedSplit,
                    onGenerate: { generatedExercises in
                        exercises = generatedExercises
                        showingAIGenerator = false
                    }
                )
                .environmentObject(aiService)
            }
            .onAppear {
                if let template = editingTemplate {
                    planName = template.name
                    selectedSplit = template.splitType
                    exercises = template.exercises
                }
            }
        }
    }
    
    // MARK: - Plan Info Section
    private var planInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Workout Name")
                    .font(.headline)
                
                TextField("e.g., Push Day A", text: $planName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Split Type
            VStack(alignment: .leading, spacing: 12) {
                Text("Workout Type")
                    .font(.headline)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(WorkoutSplitType.allCases, id: \.self) { split in
                            Button {
                                selectedSplit = split
                                if planName.isEmpty {
                                    planName = "\(split.rawValue) Day"
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: split.icon)
                                        .font(.caption)
                                    Text(split.rawValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(selectedSplit == split ? split.color : split.color.opacity(0.15))
                                )
                                .foregroundColor(selectedSplit == split ? .white : split.color)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - AI Generator Button
    private var aiGeneratorButton: some View {
        Button {
            showingAIGenerator = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generate with AI")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Let AI build your perfect workout")
                        .font(.caption)
                        .opacity(0.8)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundColor(.white)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [.purple, .pink],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Exercises Section
    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Exercises")
                    .font(.headline)
                
                Spacer()
                
                Text("\(exercises.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if exercises.isEmpty {
                emptyExercisesState
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseRow(exercise, index: index)
                    }
                    .onMove { from, to in
                        exercises.move(fromOffsets: from, toOffset: to)
                        reorderExercises()
                    }
                }
            }
        }
    }
    
    private var emptyExercisesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No exercises added")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Add exercises manually or use AI to generate")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func exerciseRow(_ exercise: WorkoutExercise, index: Int) -> some View {
        HStack(spacing: 12) {
            // Drag Handle
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Order Number
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(exercise.exercise.primaryMuscles.first?.color ?? .gray)
                .clipShape(Circle())
            
            // Exercise Info
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.exercise.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text("\(exercise.targetSets) sets")
                    Text("•")
                    Text("\(exercise.targetReps.lowerBound)-\(exercise.targetReps.upperBound) reps")
                    Text("•")
                    Text("\(exercise.restSeconds)s rest")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Edit/Remove Buttons
            HStack(spacing: 8) {
                Button {
                    // Edit sets/reps
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button {
                    removeExercise(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Add Exercise Button
    private var addExerciseButton: some View {
        Button {
            showingExercisePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                
                Text("Add Exercise")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.05))
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    private func addExercise(_ exercise: Exercise) {
        let workoutExercise = WorkoutExercise(
            exercise: exercise,
            targetSets: 3,
            targetReps: 8...12,
            targetRPE: 8,
            restSeconds: 90,
            order: exercises.count
        )
        exercises.append(workoutExercise)
    }
    
    private func removeExercise(at index: Int) {
        exercises.remove(at: index)
        reorderExercises()
    }
    
    private func reorderExercises() {
        for i in exercises.indices {
            exercises[i] = WorkoutExercise(
                id: exercises[i].id,
                exercise: exercises[i].exercise,
                sets: exercises[i].sets,
                targetSets: exercises[i].targetSets,
                targetReps: exercises[i].targetReps,
                targetRPE: exercises[i].targetRPE,
                restSeconds: exercises[i].restSeconds,
                notes: exercises[i].notes,
                supersetGroupId: exercises[i].supersetGroupId,
                order: i
            )
        }
    }
    
    private func saveTemplate() {
        let template = WorkoutTemplate(
            id: editingTemplate?.id ?? UUID(),
            name: planName,
            splitType: selectedSplit,
            exercises: exercises,
            estimatedDuration: TimeInterval(exercises.count * 10 * 60),
            difficulty: .intermediate,
            createdAt: editingTemplate?.createdAt ?? Date(),
            timesCompleted: editingTemplate?.timesCompleted ?? 0,
            isAIGenerated: false
        )
        
        if editingTemplate != nil {
            workoutService.updateTemplate(template)
        } else {
            workoutService.addTemplate(template)
        }
        
        dismiss()
    }
}

// MARK: - AI Workout Generator Sheet
struct AIWorkoutGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var aiService: AIService
    
    let splitType: WorkoutSplitType
    let onGenerate: ([WorkoutExercise]) -> Void
    
    @State private var selectedGoal: GymGoal = .buildMuscle
    @State private var fitnessLevel: ExerciseDifficulty = .intermediate
    @State private var sessionDuration: Int = 60
    @State private var selectedEquipment: Set<Equipment> = [.barbell, .dumbbell, .cable, .machine]
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Goal Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Training Goal")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(GymGoal.allCases, id: \.self) { goal in
                                Button {
                                    selectedGoal = goal
                                } label: {
                                    Text(goal.rawValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(selectedGoal == goal ? Color.orange : Color(.systemGray6))
                                        )
                                        .foregroundColor(selectedGoal == goal ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Fitness Level
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fitness Level")
                            .font(.headline)
                        
                        HStack(spacing: 10) {
                            ForEach(ExerciseDifficulty.allCases, id: \.self) { level in
                                Button {
                                    fitnessLevel = level
                                } label: {
                                    Text(level.rawValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(fitnessLevel == level ? level.color : Color(.systemGray6))
                                        )
                                        .foregroundColor(fitnessLevel == level ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Session Duration
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Session Duration")
                                .font(.headline)
                            Spacer()
                            Text("\(sessionDuration) min")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: Binding(
                            get: { Double(sessionDuration) },
                            set: { sessionDuration = Int($0) }
                        ), in: 30...120, step: 15)
                        .tint(.orange)
                    }
                    
                    // Equipment
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Available Equipment")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(Equipment.allCases.prefix(12), id: \.self) { equipment in
                                Button {
                                    if selectedEquipment.contains(equipment) {
                                        selectedEquipment.remove(equipment)
                                    } else {
                                        selectedEquipment.insert(equipment)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: equipment.icon)
                                            .font(.caption2)
                                        Text(equipment.rawValue)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selectedEquipment.contains(equipment) ? Color.blue.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(selectedEquipment.contains(equipment) ? .blue : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Spacer(minLength: 20)
                    
                    // Generate Button
                    Button {
                        generateWorkout()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Generating...")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Generate Workout")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isGenerating || selectedEquipment.isEmpty)
                }
                .padding(24)
            }
            .navigationTitle("AI Workout Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func generateWorkout() {
        isGenerating = true
        errorMessage = nil
        
        Task {
            let preferences = GymPreferences(
                focusMuscles: splitType.targetMuscles,
                sessionDurationMinutes: sessionDuration,
                preferCompounds: true,
                includeSupersets: false
            )
            
            if let plan = await aiService.generateWorkoutPlan(
                goal: selectedGoal,
                daysPerWeek: 1,
                fitnessLevel: fitnessLevel,
                availableEquipment: Array(selectedEquipment),
                preferences: preferences
            ) {
                // Convert generated exercises to WorkoutExercise
                let workoutExercises = convertToWorkoutExercises(from: plan)
                
                await MainActor.run {
                    isGenerating = false
                    if workoutExercises.isEmpty {
                        errorMessage = "Could not generate exercises. Please try again."
                    } else {
                        onGenerate(workoutExercises)
                    }
                }
            } else {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = "Failed to generate workout. Please check your connection and try again."
                }
            }
        }
    }
    
    private func convertToWorkoutExercises(from plan: GeneratedWorkoutPlan) -> [WorkoutExercise] {
        guard let firstDay = plan.days.first else { return [] }
        
        var workoutExercises: [WorkoutExercise] = []
        let database = ExerciseDatabase.shared
        
        for (index, genExercise) in firstDay.exercises.enumerated() {
            // Try to find matching exercise in database
            let exercise: Exercise
            if let found = database.exercises.first(where: { 
                $0.name.lowercased().contains(genExercise.name.lowercased()) ||
                genExercise.name.lowercased().contains($0.name.lowercased())
            }) {
                exercise = found
            } else {
                // Create a basic exercise if not found
                exercise = Exercise(
                    name: genExercise.name,
                    primaryMuscles: splitType.targetMuscles.prefix(2).map { $0 },
                    equipment: Array(selectedEquipment.prefix(2))
                )
            }
            
            let workoutExercise = WorkoutExercise(
                exercise: exercise,
                targetSets: genExercise.sets,
                targetReps: genExercise.repsMin...genExercise.repsMax,
                targetRPE: 8,
                restSeconds: genExercise.restSeconds,
                notes: genExercise.notes,
                order: index
            )
            
            workoutExercises.append(workoutExercise)
        }
        
        return workoutExercises
    }
}

#Preview {
    WorkoutPlannerView()
        .environmentObject(AIService(context: PersistenceController.preview.container.viewContext))
}

