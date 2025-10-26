import SwiftUI
import CoreData
import PhotosUI

// MARK: - Activity Level Enum
enum ActivityLevel: String, CaseIterable {
    case sedentary = "Sedentary"
    case lightlyActive = "Lightly Active"
    case moderatelyActive = "Moderately Active"
    case veryActive = "Very Active"
    case extraActive = "Extra Active"
    case autoCalculated = "Auto-calculated"
    
    var description: String {
        switch self {
        case .sedentary:
            return "Little/no exercise"
        case .lightlyActive:
            return "Light exercise 1-3 days/week"
        case .moderatelyActive:
            return "Moderate exercise 3-5 days/week"
        case .veryActive:
            return "Hard exercise 6-7 days/week"
        case .extraActive:
            return "Very hard exercise + physical job"
        case .autoCalculated:
            return "Based on your actual activity data"
        }
    }
    
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .lightlyActive: return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive: return 1.725
        case .extraActive: return 1.9
        case .autoCalculated: return 1.2
        }
    }
}

// MARK: - Global Helper Functions for BMR and Maintenance Calories

func calculateBMR(weight: Double, height: Double, age: Double, gender: String) -> Double {
    if gender.lowercased() == "male" {
        return 10 * weight + 6.25 * height - 5 * age + 5
    } else {
        return 10 * weight + 6.25 * height - 5 * age - 161
    }
}

func calculateMaintenanceCalories(bmr: Double, activityLevel: ActivityLevel, activeCalories: Double = 0) -> Double {
    switch activityLevel {
    case .sedentary:
        return bmr * 1.2
    case .lightlyActive:
        return bmr * 1.375
    case .moderatelyActive:
        return bmr * 1.55
    case .veryActive:
        return bmr * 1.725
    case .extraActive:
        return bmr * 1.9
    case .autoCalculated:
        return bmr * 1.2 + activeCalories
    }
}

func determineActivityLevel(activeCalories: Double, workoutDays: Int) -> ActivityLevel {
    let dailyActiveCalories = activeCalories
    
    switch (dailyActiveCalories, workoutDays) {
    case (0..<200, 0...1):
        return .sedentary
    case (200..<400, 1...3):
        return .lightlyActive
    case (400..<600, 3...5):
        return .moderatelyActive
    case (600..<800, 5...7):
        return .veryActive
    case (800..., 6...):
        return .extraActive
    default:
        if dailyActiveCalories >= 400 {
            return .moderatelyActive
        } else if dailyActiveCalories >= 200 {
            return .lightlyActive
        } else {
            return .sedentary
        }
    }
}

struct NutritionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject var healthKitService: HealthKitService
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NutritionLog.date, ascending: false)],
        animation: .default)
    private var nutritionLogs: FetchedResults<NutritionLog>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        animation: .default)
    private var healthMetrics: FetchedResults<HealthMetrics>
    
    @State private var showingAddMeal = false
    @State private var showingWaterTracking = false
    @State private var selectedDate = Date()
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isAnalyzingImage = false
    @State private var showingQuickFoods = false
    @State private var mealDescription = ""
    @State private var isAnalyzingDescription = false
    @State private var targetWeight: Double = 70.0
    @State private var mealToDelete: NutritionLog?
    @State private var showingDeleteConfirmation = false
    @State private var userProfile: UserProfile?
    @State private var showingDeficitDetail = false
    @State private var targetDailyDeficit: Double = 450
    @State private var calorieGoal: Double = 1650
    @State private var showingEditGoals = false
    @State private var maintenanceCalories: Double = 2050
    
    // Default values if no profile data is available
    private let defaultHeight: Double = 175.0
    private let defaultAge: Double = 30.0
    private let defaultGender: String = "Male"
    private let defaultWeight: Double = 70.0
    
    private var effectiveWeight: Double {
        userProfile?.weight ?? defaultWeight
    }
    
    private var effectiveAge: Double {
        userProfile?.age ?? defaultAge
    }
    
    private var effectiveHeight: Double {
        userProfile?.height ?? defaultHeight
    }
    
    private var effectiveGender: String {
        userProfile?.gender ?? defaultGender
    }
    
    var todaysLogs: [NutritionLog] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: selectedDate)
        return nutritionLogs.filter { calendar.isDate($0.date, inSameDayAs: today) }
    }
    
    var todaysNutrition: (calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, water: Double) {
        let logs = todaysLogs
        return (
            calories: logs.reduce(0) { $0 + $1.calories },
            protein: logs.reduce(0) { $0 + $1.protein },
            carbs: logs.reduce(0) { $0 + $1.carbs },
            fat: logs.reduce(0) { $0 + $1.fat },
            fiber: logs.reduce(0) { $0 + $1.fiber },
            water: (logs.reduce(0) { $0 + $1.waterIntake } / 1000.0) * 4.2
        )
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.05, green: 0.05, blue: 0.08), Color.black]
                        : [Color(red: 0.96, green: 0.97, blue: 0.99), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 20) {
                        headerSection
                        quickAddSection
                        weightLossProgressCard
                        dailyNutritionCard
                        macroBreakdownCard
                        todaysMealsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .navigationTitle("")
                .navigationBarHidden(true)
                .blur(radius: isAnalyzingImage ? 3 : 0)
                .disabled(isAnalyzingImage)
                
                if isAnalyzingImage {
                    AIAnalysisLoadingView()
                }
            }
            .sheet(isPresented: $showingAddMeal) {
                MealDescriptionView(
                    description: $mealDescription,
                    isAnalyzing: $isAnalyzingDescription,
                    onSubmit: { description in
                        Task {
                            await analyzeMealDescription(description)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingWaterTracking) {
                WaterTrackingView()
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage, isShown: $showingImagePicker)
            }
            .sheet(isPresented: $showingQuickFoods) {
                QuickFoodsView()
            }
            .sheet(isPresented: $showingDeficitDetail) {
                DeficitDetailView(
                    targetDeficit: $targetDailyDeficit,
                    currentWeight: effectiveWeight,
                    targetWeight: $targetWeight,
                    bmr: calculateBMR(weight: effectiveWeight, height: effectiveHeight, age: effectiveAge, gender: effectiveGender),
                    maintenanceCalories: {
                        let activeCalories = healthMetrics.first?.activeCalories ?? 0.0
                        let bmr = calculateBMR(weight: effectiveWeight, height: effectiveHeight, age: effectiveAge, gender: effectiveGender)
                        return calculateMaintenanceCalories(bmr: bmr, activityLevel: .autoCalculated, activeCalories: activeCalories)
                    }()
                )
            }
            .sheet(isPresented: $showingEditGoals) {
                EditGoalsSheet(calorieGoal: $calorieGoal, targetDeficit: $targetDailyDeficit, maintenanceCalories: $maintenanceCalories)
            }
            .onChange(of: selectedImage) { newImage in
                if let image = newImage {
                    analyzeMealImage(image)
                }
            }
            .confirmationDialog("Delete Meal", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    confirmDelete()
                }
                Button("Cancel", role: .cancel) {
                    cancelDelete()
                }
            } message: {
                Text("Are you sure you want to delete this meal? This action cannot be undone.")
            }
        }
        .onAppear {
            loadUserProfile()
            // Ensure view context is properly configured
            viewContext.automaticallyMergesChangesFromParent = true
            viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
        .refreshable {
            // Pull to refresh functionality
            loadUserProfile()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nutrition")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(nutritionStatusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(CompactDatePickerStyle())
        }
        .padding(.top, 8)
    }
    
    // MARK: - Quick Add Section
    private var quickAddSection: some View {
            HStack(spacing: 12) {
                QuickAddButton(
                    title: "Scan Meal",
                    subtitle: "AI Analysis",
                    icon: "camera.fill",
                    color: .blue,
                    isLoading: isAnalyzingImage
                ) {
                    showingImagePicker = true
                }
                
                QuickAddButton(
                title: "Describe",
                subtitle: "Type meal",
                    icon: "text.bubble.fill",
                    color: .green,
                    isLoading: false
                ) {
                    showingAddMeal = true
                }
                
                QuickAddButton(
                    title: "Quick Log",
                subtitle: "Favorites",
                    icon: "clock.fill",
                    color: .orange,
                    isLoading: false
                ) {
                    showingQuickFoods = true
            }
        }
    }
    
    // MARK: - Weight Loss Progress Card
    private var weightLossProgressCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 20)
            
            VStack(spacing: 18) {
                // Header with Edit Button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weight Loss Tracker")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Track your calorie goals and progress")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { showingEditGoals = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                            Text("Edit")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // Calculate values
                let currentCalories = todaysNutrition.calories
                let activeCalories = healthMetrics.first?.activeCalories ?? 0.0
                let bmr = calculateBMR(weight: effectiveWeight, height: effectiveHeight, age: effectiveAge, gender: effectiveGender)
                let calculatedMaintenance = calculateMaintenanceCalories(bmr: bmr, activityLevel: .autoCalculated, activeCalories: activeCalories)
                let actualMaintenance = max(calculatedMaintenance, maintenanceCalories)
                let actualDeficit = actualMaintenance - currentCalories
                let caloriesRemaining = calorieGoal - currentCalories
                let weeklyDeficit = getWeeklyDeficit()
                let weeklyProjectedLossKg = max(0, (weeklyDeficit * 7) / 7700.0)
                
                // Goal Intake Row
                WeightLossRow(
                    label: "Goal Intake",
                    value: String(format: "%.0f", calorieGoal),
                    unit: "kcal",
                    description: "How much to eat per day",
                    color: .blue,
                    icon: "target"
                )
                
                // Calories Eaten Row
                WeightLossRow(
                    label: "Calories Eaten",
                    value: String(format: "%.0f", currentCalories),
                    unit: "kcal",
                    description: "Your total food today",
                    color: .orange,
                    icon: "fork.knife"
                )
                
                // Remaining Row
                WeightLossRow(
                    label: "Remaining",
                    value: String(format: "%.0f", abs(caloriesRemaining)),
                    unit: caloriesRemaining >= 0 ? "kcal left" : "kcal over",
                    description: caloriesRemaining >= 0 ? "What's left in your goal" : "You've exceeded your goal",
                    color: caloriesRemaining >= 0 ? .green : .red,
                    icon: caloriesRemaining >= 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                
                Divider()
                
                // Maintenance Calories Row
                WeightLossRow(
                    label: "Maintenance",
                    value: String(format: "%.0f", actualMaintenance),
                    unit: "kcal/day",
                    description: "What your body burns daily",
                    color: .gray,
                    icon: "flame.fill"
                )
                
                // Target Deficit Row
                WeightLossRow(
                    label: "Target Deficit",
                    value: String(format: "−%.0f", targetDailyDeficit),
                    unit: "kcal/day",
                    description: "Planned deficit from maintenance",
                    color: .purple,
                    icon: "chart.line.downtrend.xyaxis"
                )
                
                // Actual Deficit Today Row
                WeightLossRow(
                    label: "Actual Deficit",
                    value: String(format: "%.0f", max(actualDeficit, 0)),
                    unit: "kcal today",
                    description: "Your real deficit based on intake",
                    color: actualDeficit >= targetDailyDeficit ? .green : .orange,
                    icon: actualDeficit >= targetDailyDeficit ? "checkmark.seal.fill" : "info.circle.fill"
                )
                
                Divider()
                
                // Projected Loss Row
                WeightLossRow(
                    label: "Projected Loss",
                    value: String(format: "~%.1f", weeklyProjectedLossKg),
                    unit: "kg/week",
                    description: "Based on 7-day average deficit",
                    color: .mint,
                    icon: "scalemass.fill"
                )
            }
            .padding(20)
        }
    }

    // MARK: - Daily Nutrition Card
    private var dailyNutritionCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 20)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Today's Summary")
                .font(.headline)
                    .fontWeight(.semibold)
            
            let nutrition = todaysNutrition
                let proteinGoal = 150.0
                let fiberGoal = 25.0
                let carbsGoal = 250.0
                let fatGoal = 70.0
            
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    NutritionMetricTile(
                    title: "Calories",
                    value: String(format: "%.0f", nutrition.calories),
                        goal: String(format: "%.0f", calorieGoal),
                    unit: "kcal",
                        progress: nutrition.calories / calorieGoal,
                    color: .orange
                )
                
                    NutritionMetricTile(
                    title: "Protein",
                    value: String(format: "%.0f", nutrition.protein),
                        goal: String(format: "%.0f", proteinGoal),
                    unit: "g",
                        progress: nutrition.protein / proteinGoal,
                    color: .red
                )
                
                    NutritionMetricTile(
                        title: "Carbs",
                        value: String(format: "%.0f", nutrition.carbs),
                        goal: String(format: "%.0f", carbsGoal),
                    unit: "g",
                        progress: nutrition.carbs / carbsGoal,
                    color: .blue
                )
                    
                    NutritionMetricTile(
                        title: "Fat",
                        value: String(format: "%.0f", nutrition.fat),
                        goal: String(format: "%.0f", fatGoal),
                        unit: "g",
                        progress: nutrition.fat / fatGoal,
                        color: .yellow
                    )
                
                    NutritionMetricTile(
                    title: "Fiber",
                    value: String(format: "%.1f", nutrition.fiber),
                        goal: String(format: "%.0f", fiberGoal),
                    unit: "g",
                        progress: nutrition.fiber / fiberGoal,
                    color: .green
                )
                
                    Button(action: {
                        showingWaterTracking = true
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue.opacity(0.08))
            
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                                    Image(systemName: "drop.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                Spacer()
                                }
                                
                                Text(String(format: "%.1f", nutrition.water))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                                Text("Water (8 cups)")
                            .font(.caption)
                    .foregroundColor(.secondary)
                    }
                            .padding(14)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
        }
    }
    
    // MARK: - Macro Breakdown Card
    private var macroBreakdownCard: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 20)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Macros")
                .font(.headline)
                    .fontWeight(.semibold)
                
                let nutrition = todaysNutrition
                let proteinCalories = nutrition.protein * 4
                let carbCalories = nutrition.carbs * 4
                let fatCalories = nutrition.fat * 9
                let totalCalories = max(proteinCalories + carbCalories + fatCalories, 1)
                
                VStack(spacing: 12) {
                    MacroProgressRow(title: "Protein", value: nutrition.protein, unit: "g", percent: proteinCalories / totalCalories, color: .red)
                    MacroProgressRow(title: "Carbs", value: nutrition.carbs, unit: "g", percent: carbCalories / totalCalories, color: .blue)
                    MacroProgressRow(title: "Fat", value: nutrition.fat, unit: "g", percent: fatCalories / totalCalories, color: .yellow)
            }
        }
        .padding(20)
        }
    }
    
    // MARK: - Today's Meals Section
    private var todaysMealsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Meals")
                .font(.headline)
                .fontWeight(.semibold)
            
                Spacer()
                
                if !todaysLogs.isEmpty {
                    Text("\(todaysLogs.count) meals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            if todaysLogs.isEmpty {
                ZStack {
                    GlassCardBackground(cornerRadius: 20)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No meals logged today")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Start by scanning or describing a meal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(todaysLogs.sorted(by: { $0.date < $1.date }), id: \.id) { log in
                        MealCard(nutritionLog: log, onDelete: {
                            deleteMeal(log)
                        })
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteMeal(log)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var nutritionStatusText: String {
            let nutrition = todaysNutrition
        let calorieGoal = 2000.0
        let progress = nutrition.calories / calorieGoal
        
        switch progress {
        case 0..<0.3:
            return "Let's fuel your day 🍳"
        case 0.3..<0.7:
            return "Great progress! 💪"
        case 0.7..<1.0:
            return "Almost at your goal 🎯"
        case 1.0..<1.2:
            return "Goal reached! 🎉"
        default:
            return "Over your goal today 📊"
        }
    }
    
    private func getWeeklyDeficit() -> Double {
        let calendar = Calendar.current
        var totalDeficit = 0.0
        var daysWithData = 0
        
        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dayLogs = nutritionLogs.filter { calendar.isDate($0.date, inSameDayAs: dayStart) }
            
            if !dayLogs.isEmpty {
                let dayCalories = dayLogs.reduce(0) { $0 + $1.calories }
                let activeCalories = healthMetrics.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) })?.activeCalories ?? 0.0
                let bmr = calculateBMR(weight: effectiveWeight, height: effectiveHeight, age: effectiveAge, gender: effectiveGender)
                let maintenance = calculateMaintenanceCalories(bmr: bmr, activityLevel: .autoCalculated, activeCalories: activeCalories)
                totalDeficit += (maintenance - dayCalories)
                daysWithData += 1
            }
        }
        
        return daysWithData > 0 ? totalDeficit / Double(daysWithData) : 0
    }
    
    private func loadUserProfile() {
        Task {
            userProfile = await healthKitService.getUserProfile()
        }
    }
    
    private func deleteMeal(_ meal: NutritionLog) {
        mealToDelete = meal
        showingDeleteConfirmation = true
    }
    
    private func confirmDelete() {
        guard let meal = mealToDelete else { return }
        viewContext.delete(meal)
        
        do {
            try viewContext.save()
            print("✅ Nutrition log deleted successfully")
        } catch {
            print("❌ Error deleting meal: \(error.localizedDescription)")
            viewContext.rollback()
        }
        
        mealToDelete = nil
    }
    
    private func cancelDelete() {
        mealToDelete = nil
    }
    
    private func analyzeMealImage(_ image: UIImage) {
        isAnalyzingImage = true

        Task {
            if let result = await aiService.analyzeMealImage(image) {
                await MainActor.run {
                    let newLog = NutritionLog(context: viewContext)
                    newLog.id = UUID()
                    newLog.date = selectedDate
                    newLog.foodName = result.foodName
                    newLog.mealType = result.mealType
                    newLog.calories = result.calories
                    newLog.protein = result.protein
                    newLog.carbs = result.carbs
                    newLog.fat = result.fat
                    newLog.fiber = result.fiber ?? 0
                    newLog.sugar = result.sugar ?? 0
                    newLog.sodium = result.sodium ?? 0
                    newLog.unit = "serving"
                    newLog.quantity = 1.0
                    newLog.isFromAI = true
                    
                    // Set vitamins
                    newLog.vitaminA = result.vitaminA ?? 0
                    newLog.vitaminC = result.vitaminC ?? 0
                    newLog.vitaminD = result.vitaminD ?? 0
                    newLog.vitaminE = result.vitaminE ?? 0
                    newLog.vitaminK = result.vitaminK ?? 0
                    newLog.vitaminB1 = result.vitaminB1 ?? 0
                    newLog.vitaminB2 = result.vitaminB2 ?? 0
                    newLog.vitaminB3 = result.vitaminB3 ?? 0
                    newLog.vitaminB6 = result.vitaminB6 ?? 0
                    newLog.vitaminB12 = result.vitaminB12 ?? 0
                    newLog.folate = result.folate ?? 0
                    
                    // Set minerals
                    newLog.calcium = result.calcium ?? 0
                    newLog.iron = result.iron ?? 0
                    newLog.magnesium = result.magnesium ?? 0
                    newLog.phosphorus = result.phosphorus ?? 0
                    newLog.potassium = result.potassium ?? 0
                    newLog.zinc = result.zinc ?? 0
                    
                    do {
                        try viewContext.save()
                        print("✅ Nutrition log saved successfully via image analysis for date: \(selectedDate)")
                        // Force refresh the view context to show new data
                        viewContext.refreshAllObjects()
                    } catch {
                        print("❌ Error saving nutrition log: \(error.localizedDescription)")
                        viewContext.rollback()
                    }
                    isAnalyzingImage = false
                    selectedImage = nil
                }
            } else {
                await MainActor.run {
                    isAnalyzingImage = false
                    selectedImage = nil
                }
            }
        }
    }
    
    private func analyzeMealDescription(_ description: String) async {
        isAnalyzingDescription = true
        
        if let result = await aiService.analyzeFoodDescription(description) {
            await MainActor.run {
            let newLog = NutritionLog(context: viewContext)
                newLog.id = UUID()
            newLog.date = selectedDate
                newLog.foodName = result.foodName
                newLog.mealType = result.mealType
                newLog.calories = result.calories
                newLog.protein = result.protein
                newLog.carbs = result.carbs
                newLog.fat = result.fat
                newLog.fiber = result.fiber
                newLog.sugar = result.sugar
                newLog.sodium = result.sodium
                newLog.unit = "serving"
                newLog.quantity = 1.0
            newLog.isFromAI = true
            
                // Set vitamins
                newLog.vitaminA = result.vitaminA ?? 0
                newLog.vitaminC = result.vitaminC ?? 0
                newLog.vitaminD = result.vitaminD ?? 0
                newLog.vitaminE = result.vitaminE ?? 0
                newLog.vitaminK = result.vitaminK ?? 0
                newLog.vitaminB1 = result.vitaminB1 ?? 0
                newLog.vitaminB2 = result.vitaminB2 ?? 0
                newLog.vitaminB3 = result.vitaminB3 ?? 0
                newLog.vitaminB6 = result.vitaminB6 ?? 0
                newLog.vitaminB12 = result.vitaminB12 ?? 0
                newLog.folate = result.folate ?? 0
                
                // Set minerals
                newLog.calcium = result.calcium ?? 0
                newLog.iron = result.iron ?? 0
                newLog.magnesium = result.magnesium ?? 0
                newLog.phosphorus = result.phosphorus ?? 0
                newLog.potassium = result.potassium ?? 0
                newLog.zinc = result.zinc ?? 0
                
                do {
                    try viewContext.save()
                    print("✅ Nutrition log saved successfully via text description for date: \(selectedDate)")
                    // Force refresh the view context to show new data
                    viewContext.refreshAllObjects()
                } catch {
                    print("❌ Error saving nutrition log: \(error.localizedDescription)")
                    viewContext.rollback()
                }
            isAnalyzingDescription = false
            mealDescription = ""
                showingAddMeal = false
            }
        } else {
            await MainActor.run {
                isAnalyzingDescription = false
            }
        }
    }
}

// MARK: - Supporting Components

struct QuickAddButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                GlassCardBackground(cornerRadius: 16)
                
                VStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                            .tint(color)
                } else {
            Image(systemName: icon)
                            .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)
                }
            
                Text(title)
                    .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                
                    Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading)
    }
}

struct NutritionMetricTile: View {
    let title: String
    let value: String
    let goal: String
    let unit: String
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.08))
            
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                    Image(systemName: progressIcon)
                        .font(.system(size: 14))
                        .foregroundColor(color)
                Spacer()
                    Text("\(Int(min(progress, 1.0) * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(color)
            }
            
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("\(title) (\(goal) \(unit))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
        }
    }
    
    private var progressIcon: String {
        switch title {
        case "Calories": return "flame.fill"
        case "Protein": return "fish.fill"
        case "Fiber": return "leaf.fill"
        default: return "circle.fill"
        }
    }
}

struct MacroRow: View {
    let color: Color
    let title: String
    let value: Double
    let percentage: Double
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 12, height: 12)
            
                Text(title)
                    .font(.subheadline)
                .foregroundColor(.secondary)
                
                Spacer()
                
            Text("\(Int(value))g")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
            Text("(\(Int(percentage))%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
        }
    }
}

struct MacroProgressRow: View {
    let title: String
    let value: Double
    let unit: String
    let percent: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            Spacer()
                Text("\(Int(value)) \(unit)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.9))
                    .frame(width: max(8, min(CGFloat(percent) * UIScreen.main.bounds.width * 0.75, UIScreen.main.bounds.width * 0.75)), height: 10)
            }
        }
    }
}

struct MealCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let nutritionLog: NutritionLog
    let onDelete: () -> Void
    
    var body: some View {
        ZStack {
            GlassCardBackground(cornerRadius: 16)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                    Text(nutritionLog.foodName)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text(nutritionLog.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(nutritionLog.calories))")
                            .font(.title3)
                            .fontWeight(.bold)
                    .foregroundColor(.orange)
                        Text("calories")
                            .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                HStack(spacing: 16) {
                    MacroChip(icon: "fish.fill", value: "\(Int(nutritionLog.protein))g", color: .red)
                    MacroChip(icon: "circle.grid.2x2.fill", value: "\(Int(nutritionLog.carbs))g", color: .blue)
                    MacroChip(icon: "drop.fill", value: "\(Int(nutritionLog.fat))g", color: .yellow)
                    
                    if nutritionLog.fiber > 0 {
                        MacroChip(icon: "leaf.circle.fill", value: "\(Int(nutritionLog.fiber))g", color: .green)
                    }
                }
            }
            .padding(16)
        }
    }
}

struct MacroChip: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(value)
                        .font(.caption)
                        .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - AI Analysis Loading View
struct KPIBlock: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - AI Analysis Loading View
struct AIAnalysisLoadingView: View {
    @State private var animationAmount: CGFloat = 1
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                    Text("Analyzing your meal...")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("AI is identifying nutrients")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
            )
            .scaleEffect(animationAmount)
        .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    animationAmount = 1.05
                }
            }
        }
    }
}

// MARK: - Meal Description View
struct MealDescriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var description: String
    @Binding var isAnalyzing: Bool
    let onSubmit: (String) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                        Text("Describe your meal")
                            .font(.headline)
                        Text("Be specific about portion sizes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    TextEditor(text: $description)
                        .frame(height: 200)
                        .padding(12)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                
                Button(action: {
                        onSubmit(description)
                }) {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                    .tint(.white)
                        }
                        Text(isAnalyzing ? "Analyzing..." : "Analyze Meal")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                        .background(description.isEmpty ? Color.secondary : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(description.isEmpty || isAnalyzing)
                    
                    Spacer()
            }
                .padding()
            }
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Quick Foods View
struct QuickFoodsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let commonFoods: [(name: String, calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double)] = [
        ("Banana (medium)", 105, 1.3, 27, 0.4, 3.1),
        ("Apple (medium)", 95, 0.5, 25, 0.3, 4.4),
        ("Greek Yogurt (1 cup)", 130, 20, 9, 0, 0),
        ("Chicken Breast (100g)", 165, 31, 0, 3.6, 0),
        ("Brown Rice (1 cup cooked)", 215, 5, 45, 1.8, 3.5),
        ("Salmon (100g)", 206, 22, 0, 13, 0),
        ("Eggs (2 large)", 140, 12, 1, 10, 0),
        ("Oatmeal (1 cup cooked)", 166, 6, 28, 3.6, 4),
        ("Almonds (28g)", 164, 6, 6, 14, 3.5),
        ("Avocado (half)", 120, 1.5, 6, 11, 5),
    ]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(commonFoods, id: \.name) { food in
                    Button(action: {
                        addFood(food)
                    }) {
                VStack(alignment: .leading, spacing: 8) {
                            Text(food.name)
                                    .font(.headline)
                            
                            HStack(spacing: 16) {
                                Text("\(Int(food.calories)) cal")
                            .font(.caption)
                        .foregroundColor(.secondary)
                                Text("P: \(Int(food.protein))g")
                                    .font(.caption)
                                .foregroundColor(.secondary)
                                Text("C: \(Int(food.carbs))g")
                                    .font(.caption)
                                .foregroundColor(.secondary)
                                Text("F: \(Int(food.fat))g")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Quick Foods")
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addFood(_ food: (name: String, calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double)) {
        let newLog = NutritionLog(context: viewContext)
        newLog.id = UUID()
        newLog.date = Date()
        newLog.foodName = food.name
        newLog.mealType = "snack"
        newLog.calories = food.calories
        newLog.protein = food.protein
        newLog.carbs = food.carbs
        newLog.fat = food.fat
        newLog.fiber = food.fiber
        newLog.unit = "serving"
        newLog.quantity = 1.0
        newLog.isFromAI = false
        
        do {
            try viewContext.save()
            print("✅ Quick food '\(food.name)' saved successfully for date: \(Date())")
            // Force refresh the view context to show new data
            viewContext.refreshAllObjects()
        } catch {
            print("❌ Error saving quick food: \(error.localizedDescription)")
            viewContext.rollback()
        }
        dismiss()
    }
}

// MARK: - Supporting Structs
struct DayCalorieData {
    let day: String
    let calories: Double
}

// MARK: - Deficit Detail View
struct DeficitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var targetDeficit: Double
    let currentWeight: Double
    @Binding var targetWeight: Double
    let bmr: Double
    let maintenanceCalories: Double
    
    private var weeklyWeightLossKg: Double {
        (targetDeficit * 7) / 7700.0 // ~7700 kcal per kg
    }
    
    private var weeksToGoal: Int {
        let weightToLose = max(currentWeight - targetWeight, 0)
        guard weeklyWeightLossKg > 0 else { return 0 }
        return Int(ceil(weightToLose / weeklyWeightLossKg))
    }
    
    private var deficitSafety: (label: String, color: Color, note: String) {
        if targetDeficit < 250 { return ("Minimal", .green, "Very sustainable; slower progress") }
        if targetDeficit < 500 { return ("Safe", .green, "Recommended for steady loss") }
        if targetDeficit < 750 { return ("Moderate", .orange, "Can work for short periods") }
        if targetDeficit < 1000 { return ("Aggressive", .orange, "Monitor energy & recovery") }
        return ("Too High", .red, "Risk of fatigue and muscle loss")
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.05, green: 0.05, blue: 0.08), Color.black]
                        : [Color(red: 0.96, green: 0.97, blue: 0.99), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Target deficit
                        ZStack { GlassCardBackground(cornerRadius: 20)
                            VStack(spacing: 16) {
                    HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Daily Calorie Deficit")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text("Adjust to fit your lifestyle")
                                            .font(.caption)
                            .foregroundColor(.secondary)
                                    }
                            Spacer()
                                }
                                
                                Text("\(Int(targetDeficit)) cal/day")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(deficitSafety.color)
                                
                                Slider(value: $targetDeficit, in: 0...1200, step: 50)
                                    .tint(deficitSafety.color)
                                HStack { Text("0").font(.caption).foregroundColor(.secondary); Spacer(); Text("1200").font(.caption).foregroundColor(.secondary) }
                            }
                            .padding(20)
                        }
                        
                        // Safety & summary
                        ZStack { GlassCardBackground(cornerRadius: 20)
                            VStack(spacing: 14) {
                    HStack {
                                    Image(systemName: deficitSafety.label == "Too High" ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                                        .foregroundColor(deficitSafety.color)
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Safety: \(deficitSafety.label)")
                        .font(.headline)
                        .fontWeight(.semibold)
                                        Text(deficitSafety.note)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                        Spacer()
                                }
                                Divider()
                                VStack(spacing: 10) {
                                    InfoRow(icon: "flame.fill", title: "Recommended Intake", value: "\(Int(maintenanceCalories - targetDeficit)) cal", color: .orange)
                                    InfoRow(icon: "scalemass.fill", title: "Weekly Loss", value: String(format: "%.2f kg", weeklyWeightLossKg), color: .blue)
                                    InfoRow(icon: "calendar", title: "Est. Time to Goal", value: weeksToGoal > 0 ? "\(weeksToGoal) weeks" : "Set target weight", color: .purple)
                    }
                }
                .padding(20)
                        }
                        
                        // Target weight
                        ZStack { GlassCardBackground(cornerRadius: 20)
                            VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                        Text("Target Weight")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text("Adjust your goal below")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                                    Spacer()
                                }
                                HStack(spacing: 24) {
                                    VStack(spacing: 6) {
                                        Text("Current").font(.caption).foregroundColor(.secondary)
                                        Text(String(format: "%.1f", currentWeight)).font(.title2).fontWeight(.bold)
                                        Text("kg").font(.caption2).foregroundColor(.secondary)
                                    }.frame(maxWidth: .infinity)
                                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                                    VStack(spacing: 6) {
                                        Text("Target").font(.caption).foregroundColor(.secondary)
                                        TextField("Target", value: $targetWeight, format: .number)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .multilineTextAlignment(.center)
                                            .keyboardType(.decimalPad)
                                        Text("kg").font(.caption2).foregroundColor(.secondary)
                                    }.frame(maxWidth: .infinity)
                                }
                            }
                            .padding(20)
                        }
                        
                        // Recommendations
                        ZStack { GlassCardBackground(cornerRadius: 20)
                            VStack(alignment: .leading, spacing: 12) {
                        HStack {
                                    Image(systemName: "lightbulb.fill").foregroundColor(.yellow)
                                    Text("Recommendations").font(.headline).fontWeight(.semibold)
                                    Spacer()
                                }
                                RecommendationRow(icon: "checkmark.circle.fill", text: "Aim for 0.5–1.0 kg/week for sustainability", color: .green)
                                RecommendationRow(icon: "checkmark.circle.fill", text: "Don't eat below your BMR (\(Int(bmr)) cal)", color: .green)
                                RecommendationRow(icon: "checkmark.circle.fill", text: "Protein 1.6–2.2 g/kg body weight", color: .green)
                                RecommendationRow(icon: "exclamationmark.triangle.fill", text: "Track weekly averages; daily intake can vary", color: .orange)
                                if targetDeficit > 750 {
                                    RecommendationRow(icon: "exclamationmark.triangle.fill", text: "Large deficits may increase fatigue and muscle loss", color: .red)
                    }
                }
                .padding(20)
                        }
            }
            .padding(20)
        }
            }
            .navigationTitle("Weight Loss Insights")
        .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

struct RecommendationRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
                            HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                                        .font(.caption)
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Weight Loss Row Component
struct WeightLossRow: View {
    let label: String
    let value: String
    let unit: String
    let description: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Edit Goals Sheet
struct EditGoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var calorieGoal: Double
    @Binding var targetDeficit: Double
    @Binding var maintenanceCalories: Double
    
    private var deficitSafety: (label: String, color: Color, note: String) {
        if targetDeficit < 250 { return ("Minimal", .green, "Very sustainable; slower progress") }
        if targetDeficit < 500 { return ("Safe", .green, "Recommended for steady loss") }
        if targetDeficit < 750 { return ("Moderate", .orange, "Can work for short periods") }
        if targetDeficit < 1000 { return ("Aggressive", .orange, "Monitor energy & recovery") }
        return ("Too High", .red, "Risk of fatigue and muscle loss")
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.05, green: 0.05, blue: 0.08), Color.black]
                        : [Color(red: 0.96, green: 0.97, blue: 0.99), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Maintenance Calories
                        ZStack {
                            GlassCardBackground(cornerRadius: 20)
                            
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Maintenance Calories")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text("What your body burns daily (~2,000–2,100 for you)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                
                                Text("\(Int(maintenanceCalories)) kcal")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundColor(.gray)
                                
                                Slider(value: $maintenanceCalories, in: 1500...3500, step: 50)
                                    .tint(.gray)
                                
                                HStack {
                                    Text("1500").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("3500").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(20)
                        }
                        
                        // Daily Calorie Goal
                        ZStack {
                            GlassCardBackground(cornerRadius: 20)
                            
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Daily Calorie Goal")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text("How many calories to eat per day (~1,600–1,700 for you)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                
                                Text("\(Int(calorieGoal)) kcal")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundColor(.blue)
                                
                                Slider(value: $calorieGoal, in: 1000...3000, step: 50)
                                    .tint(.blue)
                                
                                HStack {
                                    Text("1000").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("3000").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(20)
                        }
                        
                        // Target Deficit
                        ZStack {
                            GlassCardBackground(cornerRadius: 20)
                            
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Daily Calorie Deficit")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        Text("Target deficit (~400–500 for you)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                
                                Text("−\(Int(targetDeficit)) kcal/day")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundColor(deficitSafety.color)
                                
                                Slider(value: $targetDeficit, in: 0...1200, step: 50)
                                    .tint(deficitSafety.color)
                                
                                HStack {
                                    Text("0").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("1200").font(.caption).foregroundColor(.secondary)
                                }
                                
                                // Safety indicator
                                HStack(spacing: 8) {
                                    Image(systemName: deficitSafety.label == "Too High" ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                                        .foregroundColor(deficitSafety.color)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Safety: \(deficitSafety.label)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(deficitSafety.note)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(deficitSafety.color.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .padding(20)
                        }
                        
                        // Quick info
                        ZStack {
                            GlassCardBackground(cornerRadius: 20)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                    Text("Quick Tips")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    TipRow(text: "Aim for 0.5–1.0 kg/week for sustainable loss")
                                    TipRow(text: "Weekly loss = (Deficit × 7) ÷ 7700 kcal/kg")
                                    TipRow(text: "Track weekly averages; daily intake can vary")
                                    TipRow(text: "Adjust goals based on your energy levels")
                                }
                            }
                            .padding(20)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isShown: Bool
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(image: $image, isShown: $isShown)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var image: UIImage?
        @Binding var isShown: Bool
        
        init(image: Binding<UIImage?>, isShown: Binding<Bool>) {
            _image = image
            _isShown = isShown
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                image = uiImage
            }
            isShown = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isShown = false
        }
    }
}
