import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var exerciseDatabase: ExerciseDatabase
    
    @State private var showingExercisePicker = false
    @State private var showingFinishConfirmation = false
    @State private var showingCancelConfirmation = false
    @State private var workoutFeeling: Int = 3
    @State private var workoutNotes = ""
    @State private var expandedExerciseId: UUID?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Timer Header
                    workoutHeader
                    
                    // Rest Timer (if active)
                    if workoutService.isRestTimerRunning {
                        restTimerBar
                    }
                    
                    // Exercise List
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            if let session = workoutService.currentSession {
                                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                                    ExerciseCard(
                                        exercise: exercise,
                                        exerciseIndex: index,
                                        isExpanded: expandedExerciseId == exercise.id,
                                        onToggleExpand: {
                                            withAnimation(.spring(response: 0.3)) {
                                                if expandedExerciseId == exercise.id {
                                                    expandedExerciseId = nil
                                                } else {
                                                    expandedExerciseId = exercise.id
                                                }
                                            }
                                        }
                                    )
                                    .environmentObject(workoutService)
                                }
                            }
                            
                            // Add Exercise Button
                            addExerciseButton
                        }
                        .padding(20)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCancelConfirmation = true
                    }
                    .foregroundColor(.red)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") {
                        showingFinishConfirmation = true
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExerciseLibraryView(mode: .picker) { exercise in
                    workoutService.addExerciseToSession(exercise)
                    showingExercisePicker = false
                }
            }
            .alert("Cancel Workout?", isPresented: $showingCancelConfirmation) {
                Button("Continue Workout", role: .cancel) { }
                Button("Discard", role: .destructive) {
                    workoutService.cancelWorkout()
                    dismiss()
                }
            } message: {
                Text("Your progress will be lost.")
            }
            .sheet(isPresented: $showingFinishConfirmation) {
                finishWorkoutSheet
            }
        }
    }
    
    // MARK: - Workout Header
    private var workoutHeader: some View {
        VStack(spacing: 12) {
            if let session = workoutService.currentSession {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name)
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            Label(session.formattedDuration, systemImage: "clock")
                            Label("\(session.totalSets) sets", systemImage: "number")
                            if session.totalVolume > 0 {
                                Label("\(Int(session.totalVolume)) kg", systemImage: "scalemass.fill")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Split Type Badge
                    HStack(spacing: 4) {
                        Image(systemName: session.splitType.icon)
                        Text(session.splitType.rawValue)
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(session.splitType.color.opacity(0.15))
                    )
                    .foregroundColor(session.splitType.color)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Rest Timer Bar
    private var restTimerBar: some View {
        HStack(spacing: 16) {
            Text("Rest")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(formatTime(workoutService.restTimerSeconds))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    workoutService.addTimeToRestTimer(15)
                } label: {
                    Text("+15s")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
                
                Button {
                    workoutService.stopRestTimer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - Add Exercise Button
    private var addExerciseButton: some View {
        Button {
            showingExercisePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                
                Text("Add Exercise")
                    .font(.headline)
            }
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.3), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.orange.opacity(0.05))
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Finish Workout Sheet
    private var finishWorkoutSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Summary
                if let session = workoutService.currentSession {
                    VStack(spacing: 16) {
                        Text("Workout Complete! 🎉")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 24) {
                            VStack {
                                Text(session.formattedDuration)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack {
                                Text("\(session.totalSets)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("Sets")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack {
                                Text("\(Int(session.totalVolume)) kg")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("Volume")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    }
                }
                
                // How did it feel?
                VStack(alignment: .leading, spacing: 12) {
                    Text("How did it feel?")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { rating in
                            Button {
                                workoutFeeling = rating
                            } label: {
                                VStack(spacing: 4) {
                                    Text(feelingEmoji(rating))
                                        .font(.title)
                                    Text(feelingText(rating))
                                        .font(.caption2)
                                        .foregroundColor(workoutFeeling == rating ? .orange : .secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(workoutFeeling == rating ? Color.orange.opacity(0.15) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes (optional)")
                        .font(.headline)
                    
                    TextField("How was your workout?", text: $workoutNotes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                }
                
                Spacer()
                
                // Save Button
                Button {
                    workoutService.finishWorkout(feeling: workoutFeeling, notes: workoutNotes.isEmpty ? nil : workoutNotes)
                    showingFinishConfirmation = false
                    dismiss()
                } label: {
                    Text("Save Workout")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.orange)
                        )
                }
            }
            .padding(24)
            .navigationTitle("Finish Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        showingFinishConfirmation = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func feelingEmoji(_ rating: Int) -> String {
        switch rating {
        case 1: return "😫"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "😊"
        case 5: return "🔥"
        default: return "😐"
        }
    }
    
    private func feelingText(_ rating: Int) -> String {
        switch rating {
        case 1: return "Rough"
        case 2: return "Meh"
        case 3: return "OK"
        case 4: return "Good"
        case 5: return "Great"
        default: return "OK"
        }
    }
}

// MARK: - Exercise Card
struct ExerciseCard: View {
    let exercise: WorkoutExercise
    let exerciseIndex: Int
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    
    @EnvironmentObject var workoutService: WorkoutService
    @State private var showingExerciseInfo = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    // Muscle Color Indicator
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(exercise.exercise.primaryMuscles.first?.color ?? .gray)
                        .frame(width: 4, height: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.exercise.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 8) {
                            Text(exercise.exercise.primaryMuscles.map { $0.rawValue }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let topSet = exercise.topSet {
                                Text("• \(topSet.formattedWeight) × \(topSet.reps)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Progress Indicator
                    HStack(spacing: 4) {
                        Text("\(exercise.completedSets)/\(exercise.targetSets)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(exercise.isComplete ? .green : .secondary)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded Content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                VStack(spacing: 12) {
                    // Set Headers
                    HStack {
                        Text("SET")
                            .frame(width: 40)
                        Text("PREVIOUS")
                            .frame(maxWidth: .infinity)
                        Text("KG")
                            .frame(width: 70)
                        Text("REPS")
                            .frame(width: 60)
                        Text("")
                            .frame(width: 44)
                    }
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    // Sets
                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { setIndex, set in
                        SetRow(
                            set: set,
                            setIndex: setIndex,
                            exerciseId: exercise.id,
                            previousSet: getPreviousSet(for: exercise.exercise, setIndex: setIndex)
                        )
                        .environmentObject(workoutService)
                    }
                    
                    // Add Set Button
                    Button {
                        workoutService.addSetToExercise(exercise.id)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Set")
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    
                    // Exercise Actions
                    HStack(spacing: 16) {
                        Button {
                            showingExerciseInfo = true
                        } label: {
                            Label("Info", systemImage: "info.circle")
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        Button {
                            workoutService.removeExerciseFromSession(exercise.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .sheet(isPresented: $showingExerciseInfo) {
            ExerciseDetailSheet(exercise: exercise.exercise)
        }
    }
    
    private func getPreviousSet(for exercise: Exercise, setIndex: Int) -> WorkoutSet? {
        let history = workoutService.getHistoryForExercise(exercise.id)
        guard history.count > setIndex else { return nil }
        let prev = history[setIndex]
        return WorkoutSet(weight: prev.weight, reps: prev.reps, isCompleted: true)
    }
}

// MARK: - Set Row
struct SetRow: View {
    let set: WorkoutSet
    let setIndex: Int
    let exerciseId: UUID
    let previousSet: WorkoutSet?
    
    @EnvironmentObject var workoutService: WorkoutService
    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @FocusState private var focusedField: Field?
    
    enum Field {
        case weight, reps
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Set Number
            Text("\(setIndex + 1)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(set.isWarmup ? .yellow : (set.isCompleted ? .green : .primary))
                .frame(width: 40)
            
            // Previous
            if let prev = previousSet {
                Text("\(prev.formattedWeight) × \(prev.reps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
            
            // Weight Input
            TextField("0", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 70)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .focused($focusedField, equals: .weight)
                .onChange(of: weightText) { newValue in
                    if let weight = Double(newValue) {
                        workoutService.updateSet(exerciseId: exerciseId, setIndex: setIndex, weight: weight)
                    }
                }
            
            // Reps Input
            TextField("0", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 60)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .focused($focusedField, equals: .reps)
                .onChange(of: repsText) { newValue in
                    if let reps = Int(newValue) {
                        workoutService.updateSet(exerciseId: exerciseId, setIndex: setIndex, reps: reps)
                    }
                }
            
            // Complete Button
            Button {
                let isCompleting = !set.isCompleted
                workoutService.updateSet(exerciseId: exerciseId, setIndex: setIndex, isCompleted: isCompleting)
                
                if isCompleting {
                    // Start rest timer
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    workoutService.startRestTimer(seconds: 90)
                }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(set.isCompleted ? .green : .secondary)
            }
            .frame(width: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onAppear {
            if set.weight > 0 {
                weightText = set.formattedWeight
            }
            if set.reps > 0 {
                repsText = "\(set.reps)"
            }
        }
    }
}

// MARK: - Exercise Detail Sheet
struct ExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ForEach(exercise.primaryMuscles, id: \.self) { muscle in
                                Text(muscle.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(muscle.color.opacity(0.15))
                                    .foregroundColor(muscle.color)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Text(exercise.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 16) {
                            Label(exercise.difficulty.rawValue, systemImage: "chart.bar.fill")
                            Label(exercise.exerciseType.rawValue, systemImage: "tag.fill")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Equipment
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Equipment")
                            .font(.headline)
                        
                        HStack {
                            ForEach(exercise.equipment, id: \.self) { equip in
                                Label(equip.rawValue, systemImage: equip.icon)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray6))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    
                    // Muscles
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Muscles Worked")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if !exercise.primaryMuscles.isEmpty {
                                HStack {
                                    Text("Primary:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ForEach(exercise.primaryMuscles, id: \.self) { muscle in
                                        Text(muscle.rawValue)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                }
                            }
                            
                            if !exercise.secondaryMuscles.isEmpty {
                                HStack {
                                    Text("Secondary:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ForEach(exercise.secondaryMuscles, id: \.self) { muscle in
                                        Text(muscle.rawValue)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Instructions
                    if !exercise.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Instructions")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, instruction in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .frame(width: 24, height: 24)
                                            .background(Color.orange)
                                            .clipShape(Circle())
                                        
                                        Text(instruction)
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Tips
                    if !exercise.tips.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tips")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(exercise.tips, id: \.self) { tip in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                        
                                        Text(tip)
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Exercise Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ActiveWorkoutView()
        .environmentObject(WorkoutService.shared)
        .environmentObject(ExerciseDatabase.shared)
}

