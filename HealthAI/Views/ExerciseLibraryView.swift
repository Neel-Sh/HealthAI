import SwiftUI

enum ExerciseLibraryMode {
    case browse
    case picker
}

struct ExerciseLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var database = ExerciseDatabase.shared
    
    let mode: ExerciseLibraryMode
    var onSelect: ((Exercise) -> Void)?
    
    @State private var searchText = ""
    @State private var selectedMuscleFilter: MuscleGroup?
    @State private var selectedEquipmentFilter: Equipment?
    @State private var selectedCategory: MuscleCategory?
    @State private var showingFilters = false
    @State private var selectedExercise: Exercise?
    
    init(mode: ExerciseLibraryMode = .browse, onSelect: ((Exercise) -> Void)? = nil) {
        self.mode = mode
        self.onSelect = onSelect
    }
    
    var filteredExercises: [Exercise] {
        var results = database.exercises
        
        // Search filter
        if !searchText.isEmpty {
            results = database.search(searchText)
        }
        
        // Category filter
        if let category = selectedCategory {
            results = results.filter { exercise in
                exercise.primaryMuscles.contains { $0.category == category }
            }
        }
        
        // Muscle filter
        if let muscle = selectedMuscleFilter {
            results = results.filter { $0.primaryMuscles.contains(muscle) || $0.secondaryMuscles.contains(muscle) }
        }
        
        // Equipment filter
        if let equipment = selectedEquipmentFilter {
            results = results.filter { $0.equipment.contains(equipment) }
        }
        
        return results
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category Pills
                categoryPills
                
                // Filter Pills (when active)
                if selectedMuscleFilter != nil || selectedEquipmentFilter != nil {
                    activeFilters
                }
                
                // Exercise List
                if filteredExercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .navigationTitle(mode == .picker ? "Add Exercise" : "Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises...")
            .toolbar {
                if mode == .picker {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(
                    selectedMuscle: $selectedMuscleFilter,
                    selectedEquipment: $selectedEquipmentFilter
                )
            }
            .sheet(item: $selectedExercise) { exercise in
                ExerciseDetailSheet(exercise: exercise)
            }
        }
    }
    
    private var hasActiveFilters: Bool {
        selectedMuscleFilter != nil || selectedEquipmentFilter != nil || selectedCategory != nil
    }
    
    // MARK: - Category Pills
    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All button
                categoryPill(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                
                // Recent (in picker mode)
                if mode == .picker && !database.recentExercises.isEmpty {
                    categoryPill(title: "Recent", isSelected: false, color: .orange) {
                        // Handle recent - could use a separate state
                    }
                }
                
                // Favorites
                if !database.favoriteExercises.isEmpty {
                    categoryPill(title: "★ Favorites", isSelected: false, color: .yellow) {
                        // Could implement favorites filter
                    }
                }
                
                // Category pills
                ForEach(MuscleCategory.allCases, id: \.self) { category in
                    categoryPill(
                        title: category.rawValue,
                        isSelected: selectedCategory == category,
                        color: category.color
                    ) {
                        if selectedCategory == category {
                            selectedCategory = nil
                        } else {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }
    
    private func categoryPill(title: String, isSelected: Bool, color: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.2) : Color(.systemGray6))
                )
                .foregroundColor(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Active Filters
    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let muscle = selectedMuscleFilter {
                    filterChip(title: muscle.rawValue, color: muscle.color) {
                        selectedMuscleFilter = nil
                    }
                }
                
                if let equipment = selectedEquipmentFilter {
                    filterChip(title: equipment.rawValue, color: .blue) {
                        selectedEquipmentFilter = nil
                    }
                }
                
                Button("Clear All") {
                    selectedMuscleFilter = nil
                    selectedEquipmentFilter = nil
                    selectedCategory = nil
                }
                .font(.caption)
                .foregroundColor(.orange)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
    
    private func filterChip(title: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
    
    // MARK: - Exercise List
    private var exerciseList: some View {
        List {
            // Recent section (in picker mode)
            if mode == .picker && searchText.isEmpty && selectedCategory == nil && !database.recentExercises.isEmpty {
                Section("Recent") {
                    ForEach(database.recentExercises.prefix(5)) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
            
            // Group by muscle category if no search
            if searchText.isEmpty && selectedCategory == nil {
                ForEach(MuscleCategory.allCases, id: \.self) { category in
                    let categoryExercises = filteredExercises.filter { $0.primaryCategory == category }
                    
                    if !categoryExercises.isEmpty {
                        Section(category.rawValue) {
                            ForEach(categoryExercises) { exercise in
                                exerciseRow(exercise)
                            }
                        }
                    }
                }
            } else {
                // Flat list for search/filter results
                ForEach(filteredExercises) { exercise in
                    exerciseRow(exercise)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func exerciseRow(_ exercise: Exercise) -> some View {
        Button {
            if mode == .picker {
                onSelect?(exercise)
            } else {
                selectedExercise = exercise
            }
        } label: {
            HStack(spacing: 12) {
                // Muscle color indicator
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(exercise.primaryMuscles.first?.color ?? .gray)
                    .frame(width: 4, height: 36)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(exercise.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if database.isFavorite(exercise) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text(exercise.primaryMuscles.map { $0.rawValue }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text(exercise.equipment.first?.rawValue ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if mode == .picker {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button {
                database.toggleFavorite(exercise)
            } label: {
                Label(
                    database.isFavorite(exercise) ? "Unfavorite" : "Favorite",
                    systemImage: database.isFavorite(exercise) ? "star.slash" : "star"
                )
            }
            .tint(.yellow)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No exercises found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if hasActiveFilters {
                Button("Clear Filters") {
                    searchText = ""
                    selectedMuscleFilter = nil
                    selectedEquipmentFilter = nil
                    selectedCategory = nil
                }
                .font(.subheadline)
                .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Filter Sheet
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMuscle: MuscleGroup?
    @Binding var selectedEquipment: Equipment?
    
    var body: some View {
        NavigationStack {
            List {
                // Muscle Groups
                Section("Muscle Group") {
                    ForEach(MuscleCategory.allCases, id: \.self) { category in
                        DisclosureGroup(category.rawValue) {
                            ForEach(category.muscles, id: \.self) { muscle in
                                Button {
                                    if selectedMuscle == muscle {
                                        selectedMuscle = nil
                                    } else {
                                        selectedMuscle = muscle
                                    }
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(muscle.color)
                                            .frame(width: 12, height: 12)
                                        
                                        Text(muscle.rawValue)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if selectedMuscle == muscle {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Equipment
                Section("Equipment") {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        Button {
                            if selectedEquipment == equipment {
                                selectedEquipment = nil
                            } else {
                                selectedEquipment = equipment
                            }
                        } label: {
                            HStack {
                                Image(systemName: equipment.icon)
                                    .frame(width: 24)
                                    .foregroundColor(.secondary)
                                
                                Text(equipment.rawValue)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedEquipment == equipment {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        selectedMuscle = nil
                        selectedEquipment = nil
                    }
                    .foregroundColor(.red)
                }
                
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
    ExerciseLibraryView(mode: .browse)
}

