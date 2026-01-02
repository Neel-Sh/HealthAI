import SwiftUI

struct WorkoutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var workoutService = WorkoutService.shared
    @StateObject private var exerciseDatabase = ExerciseDatabase.shared
    
    @State private var showingTemplates = false
    @State private var showingExerciseLibrary = false
    @State private var showingActiveWorkout = false
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var showingQuickStart = false
    @State private var showingNewWorkout = false
    
    // Premium accent color
    private let accentColor = Color(hex: "E07A5F")
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Quick Actions
                        quickActionsSection
                        
                        // Weekly Stats
                        weeklyStatsSection
                        
                        // My Programs
                        programsSection
                        
                        // Recent Workouts
                        recentWorkoutsSection
                        
                        // Muscle Recovery Status
                        muscleRecoverySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingTemplates) {
                WorkoutTemplatesSheet(onSelect: { template in
                    selectedTemplate = template
                    showingTemplates = false
                    startWorkout(from: template)
                })
            }
            .sheet(isPresented: $showingExerciseLibrary) {
                ExerciseLibraryView(mode: .browse)
            }
            .sheet(isPresented: $showingQuickStart) {
                QuickStartSheet(onStart: { splitType, name in
                    showingQuickStart = false
                    workoutService.startEmptyWorkout(splitType: splitType, name: name)
                    showingActiveWorkout = true
                })
            }
            .sheet(isPresented: $showingNewWorkout) {
                WorkoutPlannerView()
            }
            .fullScreenCover(isPresented: $showingActiveWorkout) {
                ActiveWorkoutView()
                    .environmentObject(workoutService)
                    .environmentObject(exerciseDatabase)
            }
            .onChange(of: workoutService.isWorkoutActive) { isActive in
                showingActiveWorkout = isActive
            }
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingText)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text("Ready to crush it today?")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
        }
    }
    
    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(spacing: 14) {
            // Primary CTA - Start Workout
            Button {
                showingTemplates = true
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                            .frame(width: 52, height: 52)
                        
                        Image(systemName: "flame.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start Workout")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        Text("Choose from your programs")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark
                              ? Color.white.opacity(0.05)
                              : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.08)
                                        : Color.black.opacity(0.04),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: colorScheme == .dark ? .clear : .black.opacity(0.04),
                            radius: 12, x: 0, y: 4
                        )
                )
            }
            .buttonStyle(.plain)
            
            // Secondary Actions
            HStack(spacing: 12) {
                secondaryActionButton(
                    title: "Quick Start",
                    icon: "bolt.fill",
                    color: Color(hex: "3B82F6")
                ) {
                    showingQuickStart = true
                }
                
                secondaryActionButton(
                    title: "Exercises",
                    icon: "dumbbell.fill",
                    color: Color(hex: "8B5CF6")
                ) {
                    showingExerciseLibrary = true
                }
            }
        }
    }
    
    private func secondaryActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color.white.opacity(0.04)
                          : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.06)
                                    : Color.black.opacity(0.03),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Weekly Stats
    private var weeklyStatsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This Week")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            let stats = workoutService.getStats(for: 7)
            
            HStack(spacing: 12) {
                weeklyStatCard(
                    value: "\(stats.totalWorkouts)",
                    label: "Workouts",
                    icon: "figure.strengthtraining.traditional",
                    color: accentColor
                )
                
                weeklyStatCard(
                    value: stats.formattedTotalVolume,
                    label: "Volume",
                    icon: "scalemass.fill",
                    color: Color(hex: "3B82F6")
                )
                
                weeklyStatCard(
                    value: "\(stats.totalSets)",
                    label: "Sets",
                    icon: "number.circle.fill",
                    color: Color(hex: "34D399")
                )
            }
        }
    }
    
    private func weeklyStatCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            }
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.03),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Programs Section
    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("My Programs")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button {
                        showingNewWorkout = true
                    } label: {
                        Label("New", systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(accentColor)
                    }
                    
                    Button("See All") {
                        showingTemplates = true
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add New Card
                    Button {
                        showingNewWorkout = true
                    } label: {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        accentColor.opacity(0.4),
                                        style: StrokeStyle(lineWidth: 2, dash: [6])
                                    )
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(accentColor)
                            }
                            
                            Text("Create New")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(accentColor)
                        }
                        .frame(width: 120)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(accentColor.opacity(colorScheme == .dark ? 0.08 : 0.04))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    ForEach(workoutService.templates.prefix(5)) { template in
                        programCard(template)
                    }
                }
            }
        }
    }
    
    private func programCard(_ template: WorkoutTemplate) -> some View {
        Button {
            startWorkout(from: template)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: template.splitType.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(template.splitType.color)
                    
                    Spacer()
                    
                    if template.timesCompleted > 0 {
                        Text("\(template.timesCompleted)×")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        .lineLimit(1)
                    
                    Text("\(template.exercises.count) exercises")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .medium))
                    Text(template.formattedDuration)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            .padding(16)
            .frame(width: 150)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color.white.opacity(0.04)
                          : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.06)
                                    : Color.black.opacity(0.03),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Recent Workouts
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Workouts")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            if workoutService.workoutHistory.isEmpty {
                emptyRecentWorkouts
            } else {
                VStack(spacing: 10) {
                    ForEach(workoutService.workoutHistory.prefix(3)) { workout in
                        recentWorkoutRow(workout)
                    }
                }
            }
        }
    }
    
    private var emptyRecentWorkouts: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : Color(hex: "D1D5DB"))
            
            VStack(spacing: 4) {
                Text("No workouts yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                
                Text("Start your first workout to see it here")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.03),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func recentWorkoutRow(_ workout: WorkoutSession) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(workout.splitType.color.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: workout.splitType.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(workout.splitType.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                HStack(spacing: 10) {
                    Label("\(workout.exercises.count) exercises", systemImage: "dumbbell.fill")
                    Label(workout.formattedDuration, systemImage: "clock")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatRelativeDate(workout.startTime))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                
                if workout.totalVolume > 0 {
                    Text("\(Int(workout.totalVolume)) kg")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.03),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Muscle Recovery
    private var muscleRecoverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Muscle Recovery")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(MuscleCategory.allCases, id: \.self) { category in
                    muscleRecoveryCard(category)
                }
            }
        }
    }
    
    private func muscleRecoveryCard(_ category: MuscleCategory) -> some View {
        let muscles = category.muscles
        let daysSinceLastWorkout = muscles.compactMap { workoutService.daysSinceLastWorkout(for: $0) }.min()
        
        let status: (String, Color) = {
            guard let days = daysSinceLastWorkout else {
                return ("Not trained", Color(hex: "6B7280"))
            }
            switch days {
            case 0: return ("Just trained", accentColor)
            case 1: return ("Recovering", Color(hex: "F59E0B"))
            case 2: return ("Ready", Color(hex: "34D399"))
            default: return ("Ready to go!", Color(hex: "34D399"))
            }
        }()
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(category.color)
                    .frame(width: 8, height: 8)
                
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
            }
            
            HStack {
                Text(status.0)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(status.1)
                
                Spacer()
                
                if let days = daysSinceLastWorkout {
                    Text("\(days)d ago")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.03),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Helpers
    private func startWorkout(from template: WorkoutTemplate) {
        workoutService.startWorkout(from: template)
        showingActiveWorkout = true
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Workout Templates Sheet
struct WorkoutTemplatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var workoutService = WorkoutService.shared
    
    let onSelect: (WorkoutTemplate) -> Void
    private let accentColor = Color(hex: "E07A5F")
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                List {
                    ForEach(WorkoutSplitType.allCases, id: \.self) { splitType in
                        let templates = workoutService.templates.filter { $0.splitType == splitType }
                        
                        if !templates.isEmpty {
                            Section {
                                ForEach(templates) { template in
                                    Button {
                                        onSelect(template)
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(systemName: template.splitType.icon)
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(template.splitType.color)
                                                .frame(width: 28)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(template.name)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                                                
                                                Text("\(template.exercises.count) exercises • \(template.formattedDuration)")
                                                    .font(.system(size: 12, weight: .regular))
                                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                                }
                            } header: {
                                Text(splitType.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Choose Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(accentColor)
                }
            }
        }
    }
}

// MARK: - Quick Start Sheet
struct QuickStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSplit: WorkoutSplitType = .custom
    @State private var workoutName = ""
    
    let onStart: (WorkoutSplitType, String) -> Void
    private let accentColor = Color(hex: "E07A5F")
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Name Input
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workout Name")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        TextField("e.g., Morning Push", text: $workoutName)
                            .font(.system(size: 15, weight: .regular))
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(colorScheme == .dark
                                          ? Color.white.opacity(0.04)
                                          : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(
                                                colorScheme == .dark
                                                    ? Color.white.opacity(0.1)
                                                    : Color.black.opacity(0.06),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    
                    // Split Type Selection
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Workout Type")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(WorkoutSplitType.allCases, id: \.self) { split in
                                Button {
                                    selectedSplit = split
                                    if workoutName.isEmpty {
                                        workoutName = "\(split.rawValue) Day"
                                    }
                                } label: {
                                    VStack(spacing: 10) {
                                        Image(systemName: split.icon)
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(selectedSplit == split ? .white : split.color)
                                        
                                        Text(split.rawValue)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(selectedSplit == split ? .white : (colorScheme == .dark ? .white : Color(hex: "1A1A1A")))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(selectedSplit == split
                                                  ? split.color
                                                  : (colorScheme == .dark
                                                     ? Color.white.opacity(0.04)
                                                     : split.color.opacity(0.08)))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Start Button
                    Button {
                        let name = workoutName.isEmpty ? "Quick Workout" : workoutName
                        onStart(selectedSplit, name)
                    } label: {
                        Text("Start Workout")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(accentColor)
                            )
                    }
                }
                .padding(24)
            }
            .navigationTitle("Quick Start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(accentColor)
                }
            }
        }
    }
}

#Preview {
    WorkoutView()
}
