import SwiftUI
import CoreData
import PhotosUI

// MARK: - Weight Goal Type
enum WeightGoal: String, CaseIterable {
    case lose = "Lose Weight"
    case maintain = "Maintain"
    case gain = "Gain Weight"
    
    var icon: String {
        switch self {
        case .lose: return "arrow.down.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .gain: return "arrow.up.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .lose: return Color(hex: "EF4444")
        case .maintain: return Color(hex: "3B82F6")
        case .gain: return Color(hex: "10B981")
        }
    }
    
    var calorieAdjustment: Double {
        switch self {
        case .lose: return -500 // 0.5 kg/week loss
        case .maintain: return 0
        case .gain: return 300 // Lean bulk
        }
    }
}

// MARK: - Nutrition View
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
    
    // State
    @State private var showingAddMeal = false
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isAnalyzingImage = false
    @State private var showingQuickFoods = false
    @State private var mealDescription = ""
    @State private var isAnalyzingDescription = false
    @State private var showingSettings = false
    @State private var showingWeightEntry = false
    
    // User Data (persisted)
    @AppStorage("currentWeight") private var currentWeight: Double = 70.0
    @AppStorage("targetWeight") private var targetWeight: Double = 65.0
    @AppStorage("userHeight") private var userHeight: Double = 175.0
    @AppStorage("userAge") private var userAge: Double = 25.0
    @AppStorage("userGender") private var userGender: String = "Male"
    @AppStorage("weightGoalType") private var weightGoalType: String = "Lose Weight"
    @AppStorage("weeklyGoalRate") private var weeklyGoalRate: Double = 0.5 // kg per week
    
    // Premium accent colors
    private let accentColor = Color(hex: "10B981") // Green for nutrition
    private let calorieColor = Color(hex: "F59E0B")
    private let proteinColor = Color(hex: "EF4444")
    private let carbColor = Color(hex: "3B82F6")
    private let fatColor = Color(hex: "8B5CF6")
    
    private var selectedDate: Date { Date() }
    
    // MARK: - Computed Properties
    
    private var currentGoal: WeightGoal {
        WeightGoal(rawValue: weightGoalType) ?? .lose
    }
    
    private var bmr: Double {
        // Mifflin-St Jeor Equation (most accurate)
        if userGender.lowercased() == "male" {
            return (10 * currentWeight) + (6.25 * userHeight) - (5 * userAge) + 5
        } else {
            return (10 * currentWeight) + (6.25 * userHeight) - (5 * userAge) - 161
        }
    }
    
    private var activeCaloriesToday: Double {
        healthMetrics.first?.activeCalories ?? 0
    }
    
    private var tdee: Double {
        // TDEE = BMR + Active Calories (more accurate than multipliers)
        bmr + activeCaloriesToday
    }
    
    private var calorieGoal: Double {
        // Based on weekly goal rate (kg/week × 7700 cal/kg ÷ 7 days)
        let dailyDeficit = (weeklyGoalRate * 7700) / 7
        switch currentGoal {
        case .lose: return max(tdee - dailyDeficit, bmr) // Never go below BMR
        case .maintain: return tdee
        case .gain: return tdee + dailyDeficit
        }
    }
    
    private var proteinGoal: Double {
        // 1.6-2.2g per kg for muscle retention during weight loss
        currentGoal == .lose ? currentWeight * 2.0 : currentWeight * 1.8
    }
    
    private var fatGoal: Double {
        // 0.8-1g per kg for hormone health
        currentWeight * 0.9
    }
    
    private var carbGoal: Double {
        // Remaining calories from carbs
        let proteinCal = proteinGoal * 4
        let fatCal = fatGoal * 9
        let remainingCal = calorieGoal - proteinCal - fatCal
        return max(remainingCal / 4, 50) // Minimum 50g carbs
    }
    
    private var todaysLogs: [NutritionLog] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return nutritionLogs.filter { calendar.isDate($0.date, inSameDayAs: today) }
    }
    
    private var todaysNutrition: (calories: Double, protein: Double, carbs: Double, fat: Double) {
        let logs = todaysLogs
        return (
            calories: logs.reduce(0) { $0 + $1.calories },
            protein: logs.reduce(0) { $0 + $1.protein },
            carbs: logs.reduce(0) { $0 + $1.carbs },
            fat: logs.reduce(0) { $0 + $1.fat }
        )
    }
    
    private var caloriesRemaining: Double {
        calorieGoal - todaysNutrition.calories
    }
    
    private var weightToLose: Double {
        abs(currentWeight - targetWeight)
    }
    
    private var weeksToGoal: Int {
        guard weeklyGoalRate > 0 else { return 0 }
        return Int(ceil(weightToLose / weeklyGoalRate))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerSection
                        calorieRingCard
                        quickActionsRow
                        macroProgressCard
                        weightProgressCard
                        todaysMealsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .blur(radius: isAnalyzingImage ? 3 : 0)
                .disabled(isAnalyzingImage)
                
                if isAnalyzingImage {
                    AIAnalysisLoadingView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddMeal) {
                MealDescriptionSheet(
                    description: $mealDescription,
                    isAnalyzing: $isAnalyzingDescription,
                    onSubmit: { description in
                        Task { await analyzeMealDescription(description) }
                    }
                )
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage, isShown: $showingImagePicker)
            }
            .sheet(isPresented: $showingQuickFoods) {
                QuickFoodsSheet()
            }
            .sheet(isPresented: $showingSettings) {
                NutritionSettingsSheet(
                    currentWeight: $currentWeight,
                    targetWeight: $targetWeight,
                    userHeight: $userHeight,
                    userAge: $userAge,
                    userGender: $userGender,
                    weightGoalType: $weightGoalType,
                    weeklyGoalRate: $weeklyGoalRate
                )
            }
            .sheet(isPresented: $showingWeightEntry) {
                WeightEntrySheet(currentWeight: $currentWeight, targetWeight: $targetWeight)
            }
            .onChange(of: selectedImage) { newImage in
                if let image = newImage {
                    analyzeMealImage(image)
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nutrition")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                HStack(spacing: 6) {
                    Image(systemName: currentGoal.icon)
                        .font(.system(size: 12))
                        .foregroundColor(currentGoal.color)
                    
                    Text(currentGoal.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                }
            }
            
            Spacer()
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark
                                  ? Color.white.opacity(0.06)
                                  : Color.black.opacity(0.04))
                    )
            }
        }
    }
    
    // MARK: - Calorie Ring Card
    private var calorieRingCard: some View {
        let progress = min(todaysNutrition.calories / calorieGoal, 1.5)
        let isOverGoal = todaysNutrition.calories > calorieGoal
        
        return VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Calories")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text("TDEE: \(Int(tdee)) kcal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(isOverGoal ? "Over by" : "Remaining")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    
                    Text("\(Int(abs(caloriesRemaining)))")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(isOverGoal ? Color(hex: "EF4444") : accentColor)
                }
            }
            
            HStack(spacing: 28) {
                // Progress Ring
                ZStack {
                    Circle()
                        .stroke(
                            calorieColor.opacity(colorScheme == .dark ? 0.15 : 0.12),
                            lineWidth: 14
                        )
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .trim(from: 0, to: min(progress, 1.0))
                        .stroke(
                            isOverGoal
                                ? Color(hex: "EF4444")
                                : calorieColor,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 2) {
                        Text("\(Int(todaysNutrition.calories))")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        Text("/ \(Int(calorieGoal))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    }
                }
                
                // Stats Column
                VStack(alignment: .leading, spacing: 14) {
                    calorieStat(label: "Goal", value: "\(Int(calorieGoal))", color: accentColor)
                    calorieStat(label: "Eaten", value: "\(Int(todaysNutrition.calories))", color: calorieColor)
                    calorieStat(label: "Burned", value: "\(Int(activeCaloriesToday))", color: Color(hex: "EF4444"))
                    calorieStat(label: "Net", value: "\(Int(todaysNutrition.calories - activeCaloriesToday))", color: carbColor)
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func calorieStat(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                .frame(width: 50, alignment: .leading)
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
        }
    }
    
    // MARK: - Quick Actions Row
    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            quickActionButton(
                icon: "camera.fill",
                title: "Scan",
                subtitle: "AI Photo",
                color: carbColor,
                isLoading: isAnalyzingImage
            ) {
                showingImagePicker = true
            }
            
            quickActionButton(
                icon: "text.bubble.fill",
                title: "Describe",
                subtitle: "Type meal",
                color: accentColor,
                isLoading: false
            ) {
                showingAddMeal = true
            }
            
            quickActionButton(
                icon: "clock.fill",
                title: "Quick",
                subtitle: "Common",
                color: calorieColor,
                isLoading: false
            ) {
                showingQuickFoods = true
            }
        }
    }
    
    private func quickActionButton(icon: String, title: String, subtitle: String, color: Color, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 44, height: 44)
                    
                    if isLoading {
                        ProgressView()
                            .tint(color)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(color)
                    }
                }
                
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    // MARK: - Macro Progress Card
    private var macroProgressCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Macros")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            VStack(spacing: 14) {
                macroRow(
                    name: "Protein",
                    current: todaysNutrition.protein,
                    goal: proteinGoal,
                    color: proteinColor,
                    icon: "fish.fill"
                )
                
                macroRow(
                    name: "Carbs",
                    current: todaysNutrition.carbs,
                    goal: carbGoal,
                    color: carbColor,
                    icon: "leaf.fill"
                )
                
                macroRow(
                    name: "Fat",
                    current: todaysNutrition.fat,
                    goal: fatGoal,
                    color: fatColor,
                    icon: "drop.fill"
                )
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func macroRow(name: String, current: Double, goal: Double, color: Color, icon: String) -> some View {
        let progress = min(current / goal, 1.0)
        
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                
                Spacer()
                
                Text("\(Int(current))g")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Text("/ \(Int(goal))g")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.12))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
    
    // MARK: - Weight Progress Card
    private var weightProgressCard: some View {
        let progressPercent = currentGoal == .maintain ? 1.0 :
            (currentGoal == .lose
             ? (1 - (currentWeight - targetWeight) / (currentWeight - targetWeight + 0.1)) // Avoid division by zero
             : (currentWeight - targetWeight) / (targetWeight - currentWeight + 0.1))
        
        return VStack(spacing: 16) {
            HStack {
                Text("Weight Goal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Button {
                    showingWeightEntry = true
                } label: {
                    Text("Update")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            
            HStack(spacing: 20) {
                // Current Weight
                VStack(spacing: 4) {
                    Text("Current")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    
                    Text(String(format: "%.1f", currentWeight))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text("kg")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
                .frame(maxWidth: .infinity)
                
                // Arrow
                Image(systemName: currentGoal == .lose ? "arrow.right" : (currentGoal == .gain ? "arrow.right" : "equal"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(currentGoal.color)
                
                // Target Weight
                VStack(spacing: 4) {
                    Text("Target")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    
                    Text(String(format: "%.1f", targetWeight))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(currentGoal.color)
                    
                    Text("kg")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
                .frame(maxWidth: .infinity)
            }
            
            // Timeline
            if currentGoal != .maintain {
                HStack(spacing: 16) {
                    weightInfoChip(
                        icon: "arrow.down.circle",
                        label: "To go",
                        value: String(format: "%.1f kg", weightToLose)
                    )
                    
                    weightInfoChip(
                        icon: "calendar",
                        label: "ETA",
                        value: weeksToGoal > 0 ? "\(weeksToGoal) weeks" : "—"
                    )
                    
                    weightInfoChip(
                        icon: "flame.fill",
                        label: "Deficit",
                        value: "\(Int(tdee - calorieGoal)) cal"
                    )
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }
    
    private func weightInfoChip(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentColor)
            
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.04)
                      : accentColor.opacity(0.06))
        )
    }
    
    // MARK: - Today's Meals Section
    private var todaysMealsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today's Meals")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                if !todaysLogs.isEmpty {
                    Text("\(todaysLogs.count) items")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
            
            if todaysLogs.isEmpty {
                emptyMealsState
            } else {
                VStack(spacing: 10) {
                    ForEach(todaysLogs.sorted(by: { $0.date < $1.date }), id: \.id) { log in
                        MealRowCard(meal: log) {
                            deleteMeal(log)
                        }
                    }
                }
            }
        }
    }
    
    private var emptyMealsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.15) : Color(hex: "D1D5DB"))
            
            VStack(spacing: 4) {
                Text("No meals logged")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                
                Text("Scan, describe, or quick-add a meal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(cardBackground)
    }
    
    // MARK: - Helpers
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(colorScheme == .dark
                  ? Color.white.opacity(0.04)
                  : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.06)
                            : Color.black.opacity(0.03),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.03),
                radius: 8, x: 0, y: 2
            )
    }
    
    private func deleteMeal(_ meal: NutritionLog) {
        viewContext.delete(meal)
        try? viewContext.save()
    }
    
    private func analyzeMealImage(_ image: UIImage) {
        isAnalyzingImage = true
        
        Task {
            if let result = await aiService.analyzeMealImage(image) {
                await MainActor.run {
                    saveMealAnalysis(result)
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
                saveNutritionData(result)
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
    
    private func saveMealAnalysis(_ result: MealAnalysis) {
        let newLog = NutritionLog(context: viewContext)
        newLog.id = UUID()
        newLog.date = Date()
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
        newLog.isFromApp = false
        
        try? viewContext.save()
    }
    
    private func saveNutritionData(_ result: NutritionData) {
        let newLog = NutritionLog(context: viewContext)
        newLog.id = UUID()
        newLog.date = Date()
        newLog.foodName = result.foodName
        newLog.mealType = result.mealType
        newLog.calories = result.calories
        newLog.protein = result.protein
        newLog.carbs = result.carbs
        newLog.fat = result.fat
        newLog.fiber = result.fiber
        newLog.sugar = result.sugar
        newLog.sodium = result.sodium
        newLog.quantity = result.quantity
        newLog.unit = result.unit
        newLog.isFromAI = true
        newLog.isFromApp = false
        
        // Vitamins
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
        
        // Minerals
        newLog.calcium = result.calcium ?? 0
        newLog.iron = result.iron ?? 0
        newLog.magnesium = result.magnesium ?? 0
        newLog.phosphorus = result.phosphorus ?? 0
        newLog.potassium = result.potassium ?? 0
        newLog.zinc = result.zinc ?? 0
        
        try? viewContext.save()
    }
}

// MARK: - Meal Row Card
struct MealRowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let meal: NutritionLog
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "F59E0B").opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: mealIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: "F59E0B"))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.foodName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    macroLabel("P", value: meal.protein, color: Color(hex: "EF4444"))
                    macroLabel("C", value: meal.carbs, color: Color(hex: "3B82F6"))
                    macroLabel("F", value: meal.fat, color: Color(hex: "8B5CF6"))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(meal.calories))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "F59E0B"))
                
                Text("kcal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
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
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var mealIcon: String {
        switch meal.mealType.lowercased() {
        case "breakfast": return "sunrise.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.fill"
        default: return "fork.knife"
        }
    }
    
    private func macroLabel(_ letter: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(letter)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
            Text("\(Int(value))g")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
        }
    }
}

// MARK: - AI Analysis Loading View
struct AIAnalysisLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color(hex: "10B981").opacity(0.2), lineWidth: 4)
                        .frame(width: 48, height: 48)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color(hex: "10B981"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                }
                
                Text("Analyzing meal...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("AI is estimating nutrition")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(colorScheme == .dark ? Color(hex: "1C1C1E") : Color.white)
            )
        }
    }
}

// MARK: - Meal Description Sheet
struct MealDescriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var description: String
    @Binding var isAnalyzing: Bool
    let onSubmit: (String) -> Void
    
    private let accentColor = Color(hex: "10B981")
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe your meal")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        Text("Include portions for better accuracy (e.g., \"2 eggs, 1 slice toast with butter\")")
                            .font(.system(size: 13))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    TextEditor(text: $description)
                        .frame(height: 160)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(colorScheme == .dark
                                      ? Color.white.opacity(0.06)
                                      : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.1)
                                        : Color.black.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                    
                    Button {
                        onSubmit(description)
                    } label: {
                        HStack(spacing: 8) {
                            if isAnalyzing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isAnalyzing ? "Analyzing..." : "Analyze Meal")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(description.isEmpty || isAnalyzing ? Color.gray : accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(description.isEmpty || isAnalyzing)
                    
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                }
            }
        }
    }
}

// MARK: - Quick Foods Sheet
struct QuickFoodsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    
    let commonFoods: [(name: String, calories: Double, protein: Double, carbs: Double, fat: Double)] = [
        ("Banana (medium)", 105, 1.3, 27, 0.4),
        ("Apple (medium)", 95, 0.5, 25, 0.3),
        ("Greek Yogurt (1 cup)", 130, 20, 9, 0),
        ("Chicken Breast (100g)", 165, 31, 0, 3.6),
        ("Salmon (100g)", 206, 22, 0, 13),
        ("Brown Rice (1 cup)", 215, 5, 45, 1.8),
        ("Eggs (2 large)", 140, 12, 1, 10),
        ("Oatmeal (1 cup cooked)", 166, 6, 28, 3.6),
        ("Almonds (28g)", 164, 6, 6, 14),
        ("Avocado (half)", 120, 1.5, 6, 11),
        ("Protein Shake", 150, 25, 5, 2),
        ("Toast with Peanut Butter", 280, 10, 30, 14),
    ]
    
    private let accentColor = Color(hex: "10B981")
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(commonFoods, id: \.name) { food in
                            Button {
                                addFood(food)
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(food.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                                        
                                        HStack(spacing: 8) {
                                            Text("P: \(Int(food.protein))g")
                                            Text("C: \(Int(food.carbs))g")
                                            Text("F: \(Int(food.fat))g")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(Int(food.calories)) cal")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(hex: "F59E0B"))
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(colorScheme == .dark
                                              ? Color.white.opacity(0.04)
                                              : Color.white)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(accentColor)
                }
            }
        }
    }
    
    private func addFood(_ food: (name: String, calories: Double, protein: Double, carbs: Double, fat: Double)) {
        let newLog = NutritionLog(context: viewContext)
        newLog.id = UUID()
        newLog.date = Date()
        newLog.foodName = food.name
        newLog.mealType = "snack"
        newLog.calories = food.calories
        newLog.protein = food.protein
        newLog.carbs = food.carbs
        newLog.fat = food.fat
        newLog.unit = "serving"
        newLog.quantity = 1.0
        
        try? viewContext.save()
        dismiss()
    }
}

// MARK: - Nutrition Settings Sheet
struct NutritionSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var currentWeight: Double
    @Binding var targetWeight: Double
    @Binding var userHeight: Double
    @Binding var userAge: Double
    @Binding var userGender: String
    @Binding var weightGoalType: String
    @Binding var weeklyGoalRate: Double
    
    private let accentColor = Color(hex: "10B981")
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Goal Type
                        settingsCard(title: "Goal Type") {
                            Picker("Goal", selection: $weightGoalType) {
                                ForEach(WeightGoal.allCases, id: \.rawValue) { goal in
                                    Text(goal.rawValue).tag(goal.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Weekly Rate
                        settingsCard(title: "Weekly Goal") {
                            VStack(spacing: 12) {
                                Text(String(format: "%.1f kg/week", weeklyGoalRate))
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(accentColor)
                                
                                Slider(value: $weeklyGoalRate, in: 0.25...1.0, step: 0.25)
                                    .tint(accentColor)
                                
                                HStack {
                                    Text("0.25 kg").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("1.0 kg").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // Body Stats
                        settingsCard(title: "Body Stats") {
                            VStack(spacing: 16) {
                                statsRow(label: "Height (cm)", value: $userHeight, range: 140...220)
                                statsRow(label: "Age", value: $userAge, range: 16...80)
                                
                                HStack {
                                    Text("Gender")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                                    
                                    Spacer()
                                    
                                    Picker("Gender", selection: $userGender) {
                                        Text("Male").tag("Male")
                                        Text("Female").tag("Female")
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 160)
                                }
                            }
                        }
                        
                        // Weight
                        settingsCard(title: "Weight") {
                            VStack(spacing: 16) {
                                statsRow(label: "Current (kg)", value: $currentWeight, range: 40...200)
                                statsRow(label: "Target (kg)", value: $targetWeight, range: 40...200)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Nutrition Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(accentColor)
                }
            }
        }
    }
    
    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.white)
        )
    }
    
    private func statsRow(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    if value.wrappedValue > range.lowerBound {
                        value.wrappedValue -= 1
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(accentColor)
                }
                
                Text(String(format: "%.0f", value.wrappedValue))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    .frame(width: 50)
                
                Button {
                    if value.wrappedValue < range.upperBound {
                        value.wrappedValue += 1
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(accentColor)
                }
            }
        }
    }
}

// MARK: - Weight Entry Sheet
struct WeightEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var currentWeight: Double
    @Binding var targetWeight: Double
    @State private var newWeight: String = ""
    
    private let accentColor = Color(hex: "10B981")
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                VStack(spacing: 32) {
                    VStack(spacing: 8) {
                        Text("Log Today's Weight")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                        
                        Text("Track your progress regularly for best results")
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    }
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        TextField("", text: $newWeight)
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(accentColor)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 140)
                        
                        Text("kg")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    }
                    
                    Text("Previous: \(String(format: "%.1f", currentWeight)) kg")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    
                    Button {
                        if let weight = Double(newWeight), weight > 0 {
                            currentWeight = weight
                        }
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(Double(newWeight) == nil)
                    
                    Spacer()
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                }
            }
            .onAppear {
                newWeight = String(format: "%.1f", currentWeight)
            }
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

#Preview {
    let context = PersistenceController.preview.container.viewContext
    NutritionView()
        .environment(\.managedObjectContext, context)
        .environmentObject(AIService(context: context, apiKey: nil))
        .environmentObject(HealthKitService(context: context))
}
