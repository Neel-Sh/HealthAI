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
        case .autoCalculated: return 1.2 // Base multiplier, active calories added separately
        }
    }
}

// MARK: - Global Helper Functions for BMR and Maintenance Calories

// Helper function for BMR calculation using Mifflin-St Jeor formula (more accurate)
func calculateBMR(weight: Double, height: Double, age: Double, gender: String) -> Double {
    if gender.lowercased() == "male" {
        // Mifflin-St Jeor for men: BMR = 10 × weight(kg) + 6.25 × height(cm) - 5 × age(years) + 5
        return 10 * weight + 6.25 * height - 5 * age + 5
    } else {
        // Mifflin-St Jeor for women: BMR = 10 × weight(kg) + 6.25 × height(cm) - 5 × age(years) - 161
        return 10 * weight + 6.25 * height - 5 * age - 161
    }
}

// Calculate maintenance calories with realistic activity levels
func calculateMaintenanceCalories(bmr: Double, activityLevel: ActivityLevel, activeCalories: Double = 0) -> Double {
    switch activityLevel {
    case .sedentary:
        // For sedentary, use BMR * 1.2 (no additional exercise)
        return bmr * 1.2
    case .lightlyActive:
        // For lightly active, use BMR * 1.375 (includes light exercise 1-3 days/week)
        return bmr * 1.375
    case .moderatelyActive:
        // For moderately active, use BMR * 1.55 (includes moderate exercise 3-5 days/week)
        return bmr * 1.55
    case .veryActive:
        // For very active, use BMR * 1.725 (includes hard exercise 6-7 days/week)
        return bmr * 1.725
    case .extraActive:
        // For extra active, use BMR * 1.9 (includes very hard exercise + physical job)
        return bmr * 1.9
    case .autoCalculated:
        // For auto-calculated, use BMR + actual measured active calories to avoid double-counting
        return bmr * 1.2 + activeCalories // Use sedentary base + measured active calories
    }
}

// Determine activity level based on active calories and workout frequency
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
    @EnvironmentObject var aiService: AIService
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NutritionLog.date, ascending: false)],
        animation: .default)
    private var nutritionLogs: FetchedResults<NutritionLog>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        animation: .default)
    private var healthMetrics: FetchedResults<HealthMetrics>
    
    @State private var showingAddMeal = false
    @State private var showingNutritionChat = false
    @State private var showingWaterTracking = false
    @State private var selectedDate = Date()
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isAnalyzingImage = false
    @State private var showingQuickFoods = false
    @State private var mealDescription = ""
    @State private var isAnalyzingDescription = false
    @State private var caloricDeficitData: CaloricDeficitData?
    @State private var targetWeight: Double = 70.0 // Default target weight
    @State private var mealToDelete: NutritionLog?
    @State private var showingDeleteConfirmation = false
    @State private var showingDeficitDetails = false
    @State private var selectedNutrient: NutrientInfo? = nil
    @State private var showingNutrientDetail = false
    
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
            water: (logs.reduce(0) { $0 + $1.waterIntake } / 1000.0) * 4.2 // Convert ml to L, then to cups
        )
    }
    
    var todaysVitamins: (vitaminA: Double, vitaminC: Double, vitaminD: Double, vitaminE: Double, vitaminK: Double, vitaminB1: Double, vitaminB2: Double, vitaminB3: Double, vitaminB6: Double, vitaminB12: Double, folate: Double) {
        let logs = todaysLogs
        return (
            vitaminA: logs.reduce(0) { $0 + $1.vitaminA },
            vitaminC: logs.reduce(0) { $0 + $1.vitaminC },
            vitaminD: logs.reduce(0) { $0 + $1.vitaminD },
            vitaminE: logs.reduce(0) { $0 + $1.vitaminE },
            vitaminK: logs.reduce(0) { $0 + $1.vitaminK },
            vitaminB1: logs.reduce(0) { $0 + $1.vitaminB1 },
            vitaminB2: logs.reduce(0) { $0 + $1.vitaminB2 },
            vitaminB3: logs.reduce(0) { $0 + $1.vitaminB3 },
            vitaminB6: logs.reduce(0) { $0 + $1.vitaminB6 },
            vitaminB12: logs.reduce(0) { $0 + $1.vitaminB12 },
            folate: logs.reduce(0) { $0 + $1.folate }
        )
    }
    
    var todaysMinerals: (calcium: Double, iron: Double, magnesium: Double, phosphorus: Double, potassium: Double, zinc: Double, sodium: Double) {
        let logs = todaysLogs
        return (
            calcium: logs.reduce(0) { $0 + $1.calcium },
            iron: logs.reduce(0) { $0 + $1.iron },
            magnesium: logs.reduce(0) { $0 + $1.magnesium },
            phosphorus: logs.reduce(0) { $0 + $1.phosphorus },
            potassium: logs.reduce(0) { $0 + $1.potassium },
            zinc: logs.reduce(0) { $0 + $1.zinc },
            sodium: logs.reduce(0) { $0 + $1.sodium }
        )
    }
    
    var body: some View {
        NavigationView {
            ZStack {
            ScrollView {
                    LazyVStack(spacing: 28) {
                        // Header with date and greeting
                        headerSection
                        
                        // Quick add meal buttons
                        quickAddSection
                        
                        // Water logging section
                        waterLoggingSection
                        
                        // Today's nutrition overview
                        nutritionOverviewCard
                        
                        // Macro breakdown with modern charts
                        macroBreakdownCard
                        
                        // Fiber tracking
                        fiberCard
                        
                        // Combined Vitamins & Minerals tracking
                        nutrientsCard
                        
                        // Caloric deficit tracking
                        caloricDeficitCard
                        
                        // Weekly calorie graph
                        weeklyCalorieGraphCard
                        
                        // Today's meals
                        todaysMealsSection
                        
                        // AI insights
                        aiInsightsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("")
                .navigationBarHidden(true)
                .blur(radius: isAnalyzingImage ? 3 : 0)
                .disabled(isAnalyzingImage)
                
                // AI Analysis Loading Overlay
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
            .sheet(isPresented: $showingNutritionChat) {
                NutritionChatView()
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
            .sheet(isPresented: $showingNutrientDetail) {
                if let nutrient = selectedNutrient {
                    NutrientDetailView(nutrient: nutrient)
                }
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
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.title)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(nutritionStatusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fontWeight(.regular)
            }
            
            Spacer()
            
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(CompactDatePickerStyle())
        }
    }
    
    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Log Meal")
                .font(.headline)
                .fontWeight(.medium)
            
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
                    title: "Describe Meal",
                    subtitle: "AI Analysis",
                    icon: "text.bubble.fill",
                    color: .green,
                    isLoading: false
                ) {
                    showingAddMeal = true
                }
                
                QuickAddButton(
                    title: "Quick Log",
                    subtitle: "Common foods",
                    icon: "clock.fill",
                    color: .orange,
                    isLoading: false
                ) {
                    showingQuickFoods = true
                }
            }
        }
    }
    
    private var waterLoggingSection: some View {
        Button(action: {
            showingWaterTracking = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Water Intake")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    let waterIntake = todaysNutrition.water
                    let percentage = min((waterIntake / 8.0) * 100, 100)
                    Text("\(String(format: "%.1f", waterIntake))/8 cups (\(String(format: "%.0f", percentage))%)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            
            Spacer()
                
                // Mini progress circle
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                        .frame(width: 40, height: 40)
                    
                    Circle()
                        .trim(from: 0, to: min(todaysNutrition.water / 8.0, 1.0))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: "drop.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(Color(.systemBackground))
        .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    
    private var nutritionOverviewCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Today")
                .font(.headline)
                .fontWeight(.medium)
                
                Spacer()
                
                Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            let nutrition = todaysNutrition
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 16) {
                NutritionOverviewMetric(
                    title: "Calories",
                    value: String(format: "%.0f", nutrition.calories),
                    unit: "kcal",
                    goal: 2000,
                    progress: nutrition.calories / 2000.0,
                    color: .orange
                )
                
                NutritionOverviewMetric(
                    title: "Protein",
                    value: String(format: "%.0f", nutrition.protein),
                    unit: "g",
                    goal: 120,
                    progress: nutrition.protein / 120.0,
                    color: .red
                )
                
                NutritionOverviewMetric(
                    title: "Fiber",
                    value: String(format: "%.1f", nutrition.fiber),
                    unit: "g",
                    goal: 25,
                    progress: nutrition.fiber / 25.0,
                    color: .green
                )
                
                NutritionOverviewMetric(
                    title: "Water",
                    value: String(format: "%.1f", nutrition.water),
                    unit: "cups",
                    goal: 8,
                    progress: nutrition.water / 8.0,
                    color: .blue
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private var macroBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Macros")
                .font(.headline)
                .fontWeight(.medium)
            
            let nutrition = todaysNutrition
            let totalMacros = nutrition.protein + nutrition.carbs + nutrition.fat
            
            if totalMacros > 0 {
                HStack(spacing: 20) {
                    // Circular macro chart
                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 8)
                            .frame(width: 120, height: 120)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(nutrition.protein / totalMacros))
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                        
                        Circle()
                            .trim(from: CGFloat(nutrition.protein / totalMacros), 
                                  to: CGFloat((nutrition.protein + nutrition.carbs) / totalMacros))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                        
                        Circle()
                            .trim(from: CGFloat((nutrition.protein + nutrition.carbs) / totalMacros), to: 1)
                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 2) {
                            Text("\(Int(nutrition.calories))")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("kcal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        MacroLegendItem(
                            color: .red,
                        title: "Protein",
                        value: nutrition.protein,
                            percentage: (nutrition.protein / totalMacros) * 100
                    )
                    
                        MacroLegendItem(
                            color: .blue,
                        title: "Carbs",
                        value: nutrition.carbs,
                            percentage: (nutrition.carbs / totalMacros) * 100
                    )
                    
                        MacroLegendItem(
                            color: .yellow,
                        title: "Fat",
                        value: nutrition.fat,
                            percentage: (nutrition.fat / totalMacros) * 100
                        )
                    }
                }
            } else {
                EmptyMacroState()
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Fiber Card
    private var fiberCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "leaf.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                Text("Fiber")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Goal: 25g")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            let nutrition = todaysNutrition
            let fiberGoal: Double = 25
            let fiberProgress = nutrition.fiber / fiberGoal
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(String(format: "%.1f", nutrition.fiber))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("g")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)
                    
                    Spacer()
                    
                    Text(String(format: "%.0f%%", fiberProgress * 100))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                ProgressView(value: min(fiberProgress, 1.0))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .scaleEffect(x: 1, y: 1.5)
                
                Text("Supports digestive health and helps maintain stable blood sugar")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Combined Nutrients Card
    private var nutrientsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                
                Text("Vitamins & Minerals")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Daily Values")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            let vitamins = todaysVitamins
            let minerals = todaysMinerals
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                // Vitamins
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.vitaminC,
                    value: vitamins.vitaminC,
                    onTap: { selectedNutrient = NutrientInfo.vitaminC; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.vitaminD,
                    value: vitamins.vitaminD,
                    onTap: { selectedNutrient = NutrientInfo.vitaminD; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.vitaminA,
                    value: vitamins.vitaminA,
                    onTap: { selectedNutrient = NutrientInfo.vitaminA; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.vitaminE,
                    value: vitamins.vitaminE,
                    onTap: { selectedNutrient = NutrientInfo.vitaminE; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.vitaminB12,
                    value: vitamins.vitaminB12,
                    onTap: { selectedNutrient = NutrientInfo.vitaminB12; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.folate,
                    value: vitamins.folate,
                    onTap: { selectedNutrient = NutrientInfo.folate; showingNutrientDetail = true }
                )
                
                // Minerals
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.calcium,
                    value: minerals.calcium,
                    onTap: { selectedNutrient = NutrientInfo.calcium; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.iron,
                    value: minerals.iron,
                    onTap: { selectedNutrient = NutrientInfo.iron; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.magnesium,
                    value: minerals.magnesium,
                    onTap: { selectedNutrient = NutrientInfo.magnesium; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.potassium,
                    value: minerals.potassium,
                    onTap: { selectedNutrient = NutrientInfo.potassium; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.zinc,
                    value: minerals.zinc,
                    onTap: { selectedNutrient = NutrientInfo.zinc; showingNutrientDetail = true }
                )
                
                ClickableVitaminMineralItem(
                    nutrient: NutrientInfo.sodium,
                    value: minerals.sodium,
                    onTap: { selectedNutrient = NutrientInfo.sodium; showingNutrientDetail = true }
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private var caloricDeficitCard: some View {
        NavigationLink(destination: CaloricDeficitDetailView(
            healthMetrics: healthMetrics.first,
            todaysCalories: todaysNutrition.calories,
            targetWeight: $targetWeight,
            activityLevel: .constant("Auto-calculated")
        )) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundColor(.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calorie Deficit")
                    .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Track your progress")
                            .font(.caption)
                    .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Quick deficit summary
                let currentCalories = todaysNutrition.calories
                let currentWeight = healthMetrics.first?.bodyWeight ?? 70.0
                let activeCalories = healthMetrics.first?.activeCalories ?? 0.0
                // Use improved BMR calculation (assuming 30 years old for now)
                let bmr = calculateBMR(weight: currentWeight, height: 175, age: 30, gender: "Male")
                let maintenanceCalories = calculateMaintenanceCalories(bmr: bmr, activityLevel: .autoCalculated, activeCalories: activeCalories)
                let deficit = maintenanceCalories - currentCalories
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Eaten")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f", currentCalories))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Maintenance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f", maintenanceCalories))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deficit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f", deficit))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(deficit > 0 ? .orange : .red)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
                    .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    

    
    private var weeklyCalorieGraphCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Weekly")
                .font(.headline)
                .fontWeight(.medium)
            
                Spacer()
                
                let weeklyData = getWeeklyCalorieData()
                let avgCalories = weeklyData.reduce(0) { $0 + $1.calories } / Double(weeklyData.count)
                
                Text("Avg: \(String(format: "%.0f", avgCalories)) kcal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Enhanced weekly calorie bar chart
            let weeklyData = getWeeklyCalorieData()
            let maxCalories = weeklyData.map { $0.calories }.max() ?? 2000
            let targetCalories = 2000.0
            
            VStack(spacing: 16) {
                // Chart
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(weeklyData, id: \.day) { dayData in
                        VStack(spacing: 6) {
                            // Bar with target line
                            ZStack(alignment: .bottom) {
                                // Background bar
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(width: 35, height: 100)
                                    .cornerRadius(6)
                                
                                // Actual calories bar
                                Rectangle()
                                    .fill(dayData.calories > targetCalories ? Color.red.opacity(0.7) : Color.green.opacity(0.7))
                                    .frame(width: 35, height: CGFloat(min(dayData.calories / maxCalories * 100, 100)))
                                    .cornerRadius(6)
                                
                                // Target line
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: 35, height: 2)
                                    .offset(y: -CGFloat(targetCalories / maxCalories * 100))
                            }
                            .frame(height: 100)
                            
                            // Calorie amount
                            Text(String(format: "%.0f", dayData.calories))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            // Day label
                            Text(dayData.day)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Legend
                HStack(spacing: 20) {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.green.opacity(0.7))
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)
                        Text("Under target")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.red.opacity(0.7))
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)
                        Text("Over target")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 2)
                        Text("Target (2000)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private func getWeeklyCalorieData() -> [DayCalorieData] {
        let calendar = Calendar.current
        let today = Date()
        var weeklyData: [DayCalorieData] = []
        
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: today) ?? today
            let dayStart = calendar.startOfDay(for: date)
            let dayLogs = nutritionLogs.filter { calendar.isDate($0.date, inSameDayAs: dayStart) }
            let totalCalories = dayLogs.reduce(0) { $0 + $1.calories }
            
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "E"
            let dayName = dayFormatter.string(from: date)
            
            weeklyData.append(DayCalorieData(day: dayName, calories: totalCalories))
        }
        
        return weeklyData.reversed() // Show oldest to newest
    }
    
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
                }
            }
            
            if todaysLogs.isEmpty {
                EmptyMealsState()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(todaysLogs.sorted(by: { $0.date < $1.date }), id: \.id) { log in
                        ModernMealCard(nutritionLog: log, onDelete: {
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
    
    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            let nutrition = todaysNutrition
            
            VStack(spacing: 12) {
                AIInsightCard(
                    icon: "flame.fill",
                    title: "Calorie Balance",
                    insight: generateCalorieInsight(calories: nutrition.calories),
                    color: .orange
                )
                
                AIInsightCard(
                    icon: "chart.pie.fill",
                    title: "Macro Balance",
                    insight: generateMacroInsight(protein: nutrition.protein, carbs: nutrition.carbs, fat: nutrition.fat),
                    color: .blue
                )
                
                AIInsightCard(
                    icon: "drop.fill",
                    title: "Hydration",
                    insight: generateHydrationInsight(water: nutrition.water),
                    color: .cyan
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
    
    private var nutritionStatusText: String {
        let nutrition = todaysNutrition
        let calorieProgress = nutrition.calories / 2000.0
        
        switch calorieProgress {
        case 0..<0.3: return "Start your day with a nutritious meal 🍳"
        case 0.3..<0.6: return "You're on track with your nutrition goals 💪"
        case 0.6..<0.9: return "Great progress! Keep up the healthy eating 🥗"
        case 0.9..<1.2: return "Perfect! You're meeting your nutrition targets 🎯"
        default: return "You've exceeded your calorie goal for today 📊"
        }
    }
    
    // MARK: - AI Insight Generators
    
    private func generateCalorieInsight(calories: Double) -> String {
        let targetCalories = 2000.0
        let percentage = (calories / targetCalories) * 100
        
        switch percentage {
        case 0..<50: return "You're significantly under your calorie target. Consider adding nutrient-dense foods."
        case 50..<80: return "You're below your calorie target. A healthy snack or larger portions might help."
        case 80..<120: return "Great job! You're on track with your calorie intake for the day."
        case 120..<150: return "You're slightly over your target. Consider lighter options for remaining meals."
        default: return "You've exceeded your calorie target. Focus on portion control and lighter foods."
        }
    }
    
    private func generateMacroInsight(protein: Double, carbs: Double, fat: Double) -> String {
        let totalMacros = protein + carbs + fat
        guard totalMacros > 0 else { return "Start logging meals to see macro insights!" }
        
        let proteinPercent = (protein / totalMacros) * 100
        let carbsPercent = (carbs / totalMacros) * 100
        let fatPercent = (fat / totalMacros) * 100
        
        if proteinPercent < 15 {
            return "Consider adding more protein sources like lean meats, eggs, or legumes."
        } else if carbsPercent > 60 {
            return "Your carb intake is high. Try incorporating more vegetables and proteins."
        } else if fatPercent < 20 {
            return "Add healthy fats like avocados, nuts, or olive oil to your meals."
        } else {
            return "Your macro balance looks good! Keep up the balanced eating."
        }
    }
    
    private func generateHydrationInsight(water: Double) -> String {
        let targetWater = 2.5
        let percentage = (water / targetWater) * 100
        
        switch percentage {
        case 0..<30: return "You need more water! Aim for at least 8 glasses throughout the day."
        case 30..<70: return "Good progress on hydration. Keep drinking water regularly."
        case 70..<100: return "Almost there! A few more glasses will hit your hydration goal."
        default: return "Excellent hydration! You're meeting your daily water needs."
        }
    }
    
    // MARK: - Image Analysis
    
    private func analyzeMealImage(_ image: UIImage) {
        isAnalyzingImage = true

        Task {
            if let analysis = await aiService.analyzeMealImage(image) {
                await MainActor.run {
                    createNutritionLogFromAnalysis(analysis)
                    isAnalyzingImage = false
                    selectedImage = nil
                    print("Image analysis completed successfully")
                }
            } else {
                await MainActor.run {
                    isAnalyzingImage = false
                    print("Image analysis failed")
                }
            }
        }
    }
    
    private func analyzeMealDescription(_ description: String) async {
        isAnalyzingDescription = true
        
        guard let nutritionData = await aiService.analyzeFoodDescription(description) else {
            await MainActor.run {
                isAnalyzingDescription = false
            }
            return
        }
        
        await MainActor.run {
            // Create a new nutrition log entry
            let newLog = NutritionLog(context: viewContext)
            newLog.foodName = nutritionData.foodName
            newLog.calories = nutritionData.calories
            newLog.protein = nutritionData.protein
            newLog.carbs = nutritionData.carbs
            newLog.fat = nutritionData.fat
            newLog.fiber = nutritionData.fiber
            newLog.sugar = nutritionData.sugar
            newLog.sodium = nutritionData.sodium
            
            // Add vitamins
            newLog.vitaminA = nutritionData.vitaminA ?? 0.0
            newLog.vitaminC = nutritionData.vitaminC ?? 0.0
            newLog.vitaminD = nutritionData.vitaminD ?? 0.0
            newLog.vitaminE = nutritionData.vitaminE ?? 0.0
            newLog.vitaminK = nutritionData.vitaminK ?? 0.0
            newLog.vitaminB1 = nutritionData.vitaminB1 ?? 0.0
            newLog.vitaminB2 = nutritionData.vitaminB2 ?? 0.0
            newLog.vitaminB3 = nutritionData.vitaminB3 ?? 0.0
            newLog.vitaminB6 = nutritionData.vitaminB6 ?? 0.0
            newLog.vitaminB12 = nutritionData.vitaminB12 ?? 0.0
            newLog.folate = nutritionData.folate ?? 0.0
            
            // Add minerals
            newLog.calcium = nutritionData.calcium ?? 0.0
            newLog.iron = nutritionData.iron ?? 0.0
            newLog.magnesium = nutritionData.magnesium ?? 0.0
            newLog.phosphorus = nutritionData.phosphorus ?? 0.0
            newLog.potassium = nutritionData.potassium ?? 0.0
            newLog.zinc = nutritionData.zinc ?? 0.0
            
            newLog.quantity = nutritionData.quantity
            newLog.unit = nutritionData.unit
            newLog.mealType = nutritionData.mealType
            newLog.date = selectedDate
            newLog.isFromAI = true
            
            do {
                try viewContext.save()
                print("Meal saved successfully")
            } catch {
                print("Error saving meal: \(error)")
            }
            
            isAnalyzingDescription = false
            showingAddMeal = false
            mealDescription = ""
        }
    }
    
    private func createNutritionLogFromAnalysis(_ analysis: MealAnalysis) {
        let nutritionLog = NutritionLog(context: viewContext)
        nutritionLog.id = UUID()
        nutritionLog.foodName = analysis.foodName
        nutritionLog.mealType = analysis.mealType
        nutritionLog.date = selectedDate
        nutritionLog.calories = analysis.calories
        nutritionLog.protein = analysis.protein
        nutritionLog.carbs = analysis.carbs
        nutritionLog.fat = analysis.fat
        nutritionLog.quantity = 1.0
        nutritionLog.unit = "serving"
        nutritionLog.fiber = analysis.fiber ?? 0.0
        nutritionLog.sugar = analysis.sugar ?? 0.0
        nutritionLog.sodium = analysis.sodium ?? 0.0
        nutritionLog.waterIntake = 0.0
        
        // Add vitamins from analysis
        nutritionLog.vitaminA = analysis.vitaminA ?? 0.0
        nutritionLog.vitaminC = analysis.vitaminC ?? 0.0
        nutritionLog.vitaminD = analysis.vitaminD ?? 0.0
        nutritionLog.vitaminE = analysis.vitaminE ?? 0.0
        nutritionLog.vitaminK = analysis.vitaminK ?? 0.0
        nutritionLog.vitaminB1 = analysis.vitaminB1 ?? 0.0
        nutritionLog.vitaminB2 = analysis.vitaminB2 ?? 0.0
        nutritionLog.vitaminB3 = analysis.vitaminB3 ?? 0.0
        nutritionLog.vitaminB6 = analysis.vitaminB6 ?? 0.0
        nutritionLog.vitaminB12 = analysis.vitaminB12 ?? 0.0
        nutritionLog.folate = analysis.folate ?? 0.0
        
        // Add minerals from analysis
        nutritionLog.calcium = analysis.calcium ?? 0.0
        nutritionLog.iron = analysis.iron ?? 0.0
        nutritionLog.magnesium = analysis.magnesium ?? 0.0
        nutritionLog.phosphorus = analysis.phosphorus ?? 0.0
        nutritionLog.potassium = analysis.potassium ?? 0.0
        nutritionLog.zinc = analysis.zinc ?? 0.0
        
        nutritionLog.notes = analysis.description
        nutritionLog.isFromApp = true
        nutritionLog.isFromAI = true
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving AI-analyzed meal: \(error)")
        }
    }
    
    private func deleteMeal(_ log: NutritionLog) {
        mealToDelete = log
        showingDeleteConfirmation = true
    }
    
    private func confirmDelete() {
        if let log = mealToDelete {
            viewContext.delete(log)
            do {
                try viewContext.save()
                print("Meal deleted successfully")
            } catch {
                print("Error deleting meal: \(error)")
            }
            mealToDelete = nil
            showingDeleteConfirmation = false
        }
    }
    
    private func cancelDelete() {
        mealToDelete = nil
        showingDeleteConfirmation = false
    }
}

// MARK: - Supporting Views

struct QuickAddButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 24, height: 24)
                } else {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                }
            
                VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                
                    Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
        .cornerRadius(12)
            .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading)
    }
}

struct NutritionOverviewMetric: View {
    let title: String
    let value: String
    let unit: String
    let goal: Double
    let progress: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            HStack(alignment: .bottom, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 2)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: min(progress, 1.0))
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                    .scaleEffect(x: 1, y: 0.8)
                
                Text("Goal: \(Int(goal))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacroLegendItem: View {
    let color: Color
    let title: String
    let value: Double
    let percentage: Double
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                .foregroundColor(.primary)
                
                Spacer()
                
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0fg", value))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(String(format: "%.0f%%", percentage))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct EmptyMacroState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            VStack(spacing: 4) {
                Text("No macro data yet")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Start logging meals to see your macro breakdown")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct EmptyMealsState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            VStack(spacing: 4) {
                Text("No meals logged today")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Scan a meal or add manually to get started")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 1)
    }
}

struct ModernMealCard: View {
    let nutritionLog: NutritionLog
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: mealIcon)
                .font(.title2)
                .foregroundColor(mealColor)
                .frame(width: 44, height: 44)
                .background(mealColor.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(nutritionLog.foodName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Text(nutritionLog.mealType == "water" ? "Water" : nutritionLog.mealType.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(mealColor.opacity(0.15))
                        .foregroundColor(mealColor)
                        .cornerRadius(6)
                }
                
                if nutritionLog.mealType == "water" {
                    HStack(spacing: 8) {
                        Text("Hydration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("0 calories")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                    Text(String(format: "%.0f kcal", nutritionLog.calories))
                            .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                            .font(.caption)
                        .foregroundColor(.secondary)
                    
                        Text("P: \(String(format: "%.0f", nutritionLog.protein))g")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("C: \(String(format: "%.0f", nutritionLog.carbs))g")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("F: \(String(format: "%.0f", nutritionLog.fat))g")
                            .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                if nutritionLog.isFromAI {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                            .foregroundColor(.purple)
                        
                        Text("AI Analyzed")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 1)
    }
    
    private var mealIcon: String {
        switch nutritionLog.mealType {
        case "breakfast": return "sunrise.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.fill"
        case "snack": return "leaf.fill"
        case "water": return "drop.fill"
        default: return "fork.knife"
        }
    }
    
    private var mealColor: Color {
        switch nutritionLog.mealType {
        case "breakfast": return .orange
        case "lunch": return .yellow
        case "dinner": return .indigo
        case "snack": return .green
        case "water": return .blue
        default: return .gray
        }
    }
}

struct AIInsightCard: View {
    let icon: String
    let title: String
    let insight: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(insight)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 1)
    }
}

struct ModernActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.1))
                    .cornerRadius(12)
                
                VStack(spacing: 2) {
                Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isShown: Bool
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        
        // Check if camera is available and supported
        if UIImagePickerController.isSourceTypeAvailable(.camera) && 
           UIImagePickerController.isCameraDeviceAvailable(.rear) {
            picker.sourceType = .camera
            picker.cameraDevice = .rear
            
            // Set camera capture mode to avoid frame issues
            picker.cameraCaptureMode = .photo
            picker.cameraFlashMode = .auto
            
            // Ensure proper video quality to avoid frame dimension issues
            picker.videoQuality = .typeMedium
        } else {
            // Fallback to photo library if camera is not available
            picker.sourceType = .photoLibrary
            print("Camera not available, using photo library")
        }
        
        picker.allowsEditing = false // Disable editing to avoid frame issues
        picker.modalPresentationStyle = .fullScreen
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.isShown = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isShown = false
        }
    }
}

// MARK: - Simplified Views (keeping existing functionality)

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var isWaterEntry = false
    @State private var foodName = ""
    @State private var mealType = "breakfast"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var waterAmount = ""
    @State private var mealDate = Date()
    
    let mealTypes = ["breakfast", "lunch", "dinner", "snack"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Entry Type") {
                    Picker("Type", selection: $isWaterEntry) {
                        Text("Food").tag(false)
                        Text("Water").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                if isWaterEntry {
                    Section("Water Details") {
                        TextField("Amount (ml)", text: $waterAmount)
                            .keyboardType(.decimalPad)
                        
                        DatePicker("Time", selection: $mealDate, displayedComponents: [.date, .hourAndMinute])
                    }
                } else {
                Section("Food Details") {
                    TextField("Food Name", text: $foodName)
                    
                    Picker("Meal Type", selection: $mealType) {
                        ForEach(mealTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    
                    DatePicker("Date", selection: $mealDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Nutrition") {
                    TextField("Calories", text: $calories)
                        .keyboardType(.decimalPad)
                    
                    TextField("Protein (g)", text: $protein)
                        .keyboardType(.decimalPad)
                    
                    TextField("Carbs (g)", text: $carbs)
                        .keyboardType(.decimalPad)
                    
                    TextField("Fat (g)", text: $fat)
                        .keyboardType(.decimalPad)
                }
                }
            }
            .navigationTitle(isWaterEntry ? "Log Water" : "Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if isWaterEntry {
                            saveWater()
                        } else {
                        saveMeal()
                    }
                    }
                    .disabled(isWaterEntry ? waterAmount.isEmpty : (foodName.isEmpty || calories.isEmpty))
                }
            }
        }
    }
    
    private func saveMeal() {
        let nutritionLog = NutritionLog(context: viewContext)
        nutritionLog.id = UUID()
        nutritionLog.foodName = foodName
        nutritionLog.mealType = mealType
        nutritionLog.date = mealDate
        nutritionLog.calories = Double(calories) ?? 0
        nutritionLog.protein = Double(protein) ?? 0
        nutritionLog.carbs = Double(carbs) ?? 0
        nutritionLog.fat = Double(fat) ?? 0
        nutritionLog.quantity = 1.0
        nutritionLog.unit = "serving"
        nutritionLog.fiber = 0.0
        nutritionLog.sugar = 0.0
        nutritionLog.sodium = 0.0
        nutritionLog.waterIntake = 0.0
        nutritionLog.isFromApp = true
        nutritionLog.isFromAI = false
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving meal: \(error)")
        }
    }
    
    private func saveWater() {
        let nutritionLog = NutritionLog(context: viewContext)
        nutritionLog.id = UUID()
        nutritionLog.mealType = "water"
        nutritionLog.date = mealDate
        nutritionLog.calories = 0
        nutritionLog.protein = 0
        nutritionLog.carbs = 0
        nutritionLog.fat = 0
        nutritionLog.fiber = 0.0
        nutritionLog.sugar = 0.0
        nutritionLog.sodium = 0.0
        nutritionLog.isFromApp = true
        nutritionLog.isFromAI = false
        
        // Store water amount properly
        let amount = Double(waterAmount) ?? 0
        nutritionLog.foodName = "Water (\(Int(amount))ml)"
        nutritionLog.quantity = amount
        nutritionLog.unit = "ml"
        nutritionLog.waterIntake = amount
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving water: \(error)")
        }
    }
}

struct NutritionChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var aiService: AIService
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var messages: [ChatMessage] = []
    @State private var currentMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text("AI Nutritionist")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Ask me anything about nutrition")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear") {
                        messages.removeAll()
                        addInitialMessage()
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .overlay(
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
                
                // Messages
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                                ModernChatBubble(message: message)
                                    .id(message.id)
                        }
                        
                        if isLoading {
                                ModernTypingIndicator()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .background(Color(.systemGroupedBackground))
                    .onChange(of: messages.count) { _ in
                        if let lastMessage = messages.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input Area
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 0.5)
                    
                    HStack(spacing: 12) {
                    TextField("Ask about nutrition...", text: $currentMessage, axis: .vertical)
                            .focused($isTextFieldFocused)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(.systemGray6))
                            )
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundColor(currentMessage.isEmpty ? .gray : .blue)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(currentMessage.isEmpty ? Color.clear : Color.blue.opacity(0.1))
                                )
                    }
                    .disabled(currentMessage.isEmpty || isLoading)
                }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                addInitialMessage()
            }
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
    }
    
    private func addInitialMessage() {
        if messages.isEmpty {
            let welcomeMessage = ChatMessage(
                id: UUID(),
                content: "Hi! I'm your AI nutritionist. Ask me about meal planning, nutrition tips, or any diet questions!",
                isUser: false,
                timestamp: Date()
            )
            messages.append(welcomeMessage)
        }
    }
    
    private func sendMessage() {
        guard !currentMessage.isEmpty else { return }
        
        let userMessage = ChatMessage(
            id: UUID(),
            content: currentMessage,
            isUser: true,
            timestamp: Date()
        )
        messages.append(userMessage)
        
        let messageText = currentMessage
        currentMessage = ""
        isLoading = true
        isTextFieldFocused = false
        
        Task {
            // Use a more specific nutrition chat method with shorter responses
            if let response = await aiService.getNutritionChatResponse(messageText, nutritionLogs: []) {
                await MainActor.run {
                    let aiMessage = ChatMessage(
                        id: UUID(),
                        content: response,
                        isUser: false,
                        timestamp: Date()
                    )
                    messages.append(aiMessage)
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    let errorMessage = ChatMessage(
                        id: UUID(),
                        content: "Sorry, I couldn't process that. Please try again!",
                        isUser: false,
                        timestamp: Date()
                    )
                    messages.append(errorMessage)
                    isLoading = false
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                Text(message.content)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .frame(maxWidth: 280, alignment: .trailing)
            } else {
                Text(message.content)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .frame(maxWidth: 280, alignment: .leading)
                Spacer()
            }
        }
    }
}

// MARK: - Quick Foods View

struct QuickFoodsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let quickFoods = [
        QuickFood(name: "Banana", calories: 105, protein: 1.3, carbs: 27, fat: 0.4, emoji: "🍌"),
        QuickFood(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, emoji: "🍎"),
        QuickFood(name: "Greek Yogurt", calories: 150, protein: 20, carbs: 6, fat: 4, emoji: "🥛"),
        QuickFood(name: "Oatmeal", calories: 150, protein: 5, carbs: 27, fat: 3, emoji: "🥣"),
        QuickFood(name: "Chicken Breast", calories: 165, protein: 31, carbs: 0, fat: 3.6, emoji: "🍗"),
        QuickFood(name: "Salmon", calories: 206, protein: 22, carbs: 0, fat: 12, emoji: "🐟"),
        QuickFood(name: "Avocado", calories: 320, protein: 4, carbs: 17, fat: 29, emoji: "🥑"),
        QuickFood(name: "Almonds (1oz)", calories: 164, protein: 6, carbs: 6, fat: 14, emoji: "🥜"),
        QuickFood(name: "Egg", calories: 70, protein: 6, carbs: 0.6, fat: 5, emoji: "🥚"),
        QuickFood(name: "Brown Rice", calories: 216, protein: 5, carbs: 45, fat: 1.8, emoji: "🍚"),
        QuickFood(name: "Broccoli", calories: 55, protein: 4, carbs: 11, fat: 0.4, emoji: "🥦"),
        QuickFood(name: "Sweet Potato", calories: 112, protein: 2, carbs: 26, fat: 0.1, emoji: "🍠"),
        QuickFood(name: "Protein Shake", calories: 120, protein: 25, carbs: 3, fat: 1, emoji: "🥤"),
        QuickFood(name: "Peanut Butter", calories: 190, protein: 8, carbs: 8, fat: 16, emoji: "🥜"),
        QuickFood(name: "Whole Wheat Bread", calories: 80, protein: 4, carbs: 14, fat: 1.1, emoji: "🍞"),
        QuickFood(name: "Cottage Cheese", calories: 98, protein: 11, carbs: 4, fat: 4.3, emoji: "🧀")
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(quickFoods, id: \.name) { food in
                        QuickFoodCard(food: food) {
                            addQuickFood(food)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Quick Foods")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addQuickFood(_ food: QuickFood) {
        let newLog = NutritionLog(context: viewContext)
        newLog.id = UUID()
        newLog.date = Date()
        newLog.foodName = food.name
        newLog.calories = food.calories
        newLog.protein = food.protein
        newLog.carbs = food.carbs
        newLog.fat = food.fat
        newLog.quantity = 1.0
        newLog.unit = "serving"
        newLog.fiber = 0.0
        newLog.sugar = 0.0
        newLog.sodium = 0.0
        newLog.waterIntake = 0.0
        newLog.isFromApp = true
        newLog.isFromAI = false
        
        // Determine meal type based on current time
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:
            newLog.mealType = "breakfast"
        case 11..<15:
            newLog.mealType = "lunch"
        case 15..<18:
            newLog.mealType = "snack"
        case 18..<23:
            newLog.mealType = "dinner"
        default:
            newLog.mealType = "snack"
        }
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving quick food: \(error)")
        }
    }
}

struct QuickFoodCard: View {
    let food: QuickFood
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                    Text(food.emoji)
                        .font(.title2)
                                    Spacer()
                    Text("\(Int(food.calories)) cal")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                Text(food.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 12) {
                    MacroTag(label: "P", value: food.protein, color: .red)
                    MacroTag(label: "C", value: food.carbs, color: .orange)
                    MacroTag(label: "F", value: food.fat, color: .purple)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MacroTag: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(String(format: "%.0f", value))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }
}

struct QuickFood {
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let emoji: String
}

// MARK: - AI Analysis Loading View
struct AIAnalysisLoadingView: View {
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            // Clean loading card
            VStack(spacing: 20) {
                // Simple rotating AI icon
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseScale)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 32))
                        .foregroundColor(.purple)
                        .rotationEffect(.degrees(rotationAngle))
                        .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: rotationAngle)
                }
                
                VStack(spacing: 8) {
                    Text("Analyzing your meal...")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Please wait while AI identifies your food")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Simple progress indicator
                            ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                    .scaleEffect(1.2)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .padding(.horizontal, 50)
        }
        .onAppear {
            rotationAngle = 360
            pulseScale = 1.1
        }
    }
}

// MARK: - Modern Chat Components
struct ModernChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue)
                        )
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .trailing)
                    
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
                        } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundColor(.purple)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.purple.opacity(0.1))
                            )
                        
                        Text(message.content)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(.systemGray6))
                            )
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .leading)
                    }
                    
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 44)
                }
                
                Spacer()
            }
        }
    }
}

struct ModernTypingIndicator: View {
    @State private var animationPhase: Int = 0
    
    var body: some View {
        HStack {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.purple)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.purple.opacity(0.1))
                    )
                
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 8, height: 8)
                            .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                            .opacity(animationPhase == index ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: animationPhase)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                )
            }
            
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Meal Description View
struct MealDescriptionView: View {
    @Binding var description: String
    @Binding var isAnalyzing: Bool
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe Your Meal")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Tell me what you ate and I'll analyze the nutritional content using AI.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Food Description")
                    .font(.headline)
                        .fontWeight(.medium)
                    
                    TextField("e.g., Grilled chicken breast with quinoa and steamed broccoli", text: $description, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...8)
                        .disabled(isAnalyzing)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Large apple with 2 tablespoons peanut butter")
                        Text("• Chicken Caesar salad with croutons")
                        Text("• Two slices of whole wheat toast with avocado")
                        Text("• Greek yogurt with berries and granola")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    if !description.isEmpty {
                        onSubmit(description)
                    }
                }) {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isAnalyzing ? "Analyzing..." : "Analyze Meal")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(description.isEmpty || isAnalyzing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(description.isEmpty || isAnalyzing)
            }
            .padding(20)
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isAnalyzing)
                }
            }
        }
    }
}

// MARK: - Data Models
struct DayCalorieData {
    let day: String
    let calories: Double
}

// MARK: - Caloric Deficit Detail View
struct CaloricDeficitDetailView: View {
    let healthMetrics: HealthMetrics?
    let todaysCalories: Double
    @Binding var targetWeight: Double
    @Binding var activityLevel: String
    
    @State private var userProfile: UserProfile?
    @State private var isLoadingProfile = false
    
    @EnvironmentObject var healthKitService: HealthKitService
    
    // Default values if no profile data is available
    @State private var defaultHeight: Double = 175.0
    @State private var defaultAge: Double = 30.0
    @State private var defaultGender: String = "Male"
    @State private var defaultWeight: Double = 70.0
    
    private let activityLevels = [
        "Sedentary (little/no exercise)": 1.2,
        "Lightly Active (1-3 days/week)": 1.375,
        "Moderately Active (3-5 days/week)": 1.55,
        "Very Active (6-7 days/week)": 1.725,
        "Extra Active (very hard exercise + job)": 1.9,
        "Auto-calculated (based on data)": 0.0 // Special case for auto calculation
    ]
    
    var body: some View {
                    ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Caloric Deficit Analysis")
                        .font(.largeTitle)
                                .fontWeight(.bold)
                            
                    Text("Track your progress towards your weight loss goals")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Note about personal information
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        Text("Personal Information")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        NavigationLink(destination: SettingsView()) {
                            HStack(spacing: 4) {
                                Text("Edit in Settings")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Text("Age, weight, height, and gender are automatically loaded from Apple Health. You can manage this information in Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(.systemBackground))
                                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Current Status Card
                VStack(alignment: .leading, spacing: 16) {
                    Text("Today's Calorie Summary")
                                    .font(.headline)
                        .fontWeight(.semibold)
                    
                    let bmr = calculateDetailedBMR(weight: effectiveWeight, height: effectiveHeight, age: effectiveAge, gender: effectiveGender)
                    let activeCalories = healthMetrics?.activeCalories ?? 0.0
                    // Calculate maintenance calories using improved method that avoids double-counting
                    let maintenanceCalories = calculateMaintenanceCalories(bmr: bmr, activityLevel: .autoCalculated, activeCalories: activeCalories)
                    let deficit = maintenanceCalories - todaysCalories
                    
                    // Main summary cards
                    VStack(spacing: 12) {
                        // Calories consumed today
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Calories Eaten Today")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.0f kcal", todaysCalories))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                            Image(systemName: "fork.knife")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                                    .padding()
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(12)
                        
                        // Maintenance calories
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Maintenance Calories")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.0f kcal", maintenanceCalories))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                            Spacer()
                            Image(systemName: "target")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        
                        // Deficit/Surplus
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(deficit > 0 ? "Calorie Deficit" : "Calorie Surplus")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.0f kcal", abs(deficit)))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(deficit > 0 ? .orange : .red)
                            }
                            Spacer()
                            Image(systemName: deficit > 0 ? "minus.circle.fill" : "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(deficit > 0 ? .orange : .red)
                        }
                        .padding()
                        .background((deficit > 0 ? Color.orange : Color.red).opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Status message
                    VStack(alignment: .leading, spacing: 8) {
                        if deficit > 0 {
                            if deficit > 1000 {
                                Label("Very large deficit - consider eating more", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            } else if deficit > 500 {
                                Label("Good deficit for weight loss", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Label("Mild deficit - slow weight loss", systemImage: "info.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                        } else {
                            Label("Eating above maintenance - may gain weight", systemImage: "arrow.up.circle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        
                        Text("Maintenance calories = BMR (\(String(format: "%.0f", bmr))) × 1.2 (sedentary base) + Active calories (\(String(format: "%.0f", activeCalories))) (avoids double-counting)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Current Weight Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "scalemass.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                        
                        Text("Body Weight & BMI")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                    }
                    
                    let bmi = calculateBMI(weight: effectiveWeight, height: effectiveHeight)
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Weight")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(String(format: "%.1f kg", effectiveWeight))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BMI")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(String(format: "%.1f", bmi))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(bmiColor(bmi: bmi))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Category")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(bmiCategory(bmi: bmi))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(bmiColor(bmi: bmi))
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Target Weight:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f kg", targetWeight))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    
                    let weightToLose = effectiveWeight - targetWeight
                    if weightToLose > 0 {
                        HStack {
                            Text("To lose:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(String(format: "%.1f kg", weightToLose))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        
                        HStack {
                            Text("Estimated time:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // Assuming 0.5kg per week weight loss
                            let estimatedWeeks = Int(ceil(weightToLose / 0.5))
                            Text("\(estimatedWeeks) weeks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Health status indicator
                    HStack {
                        Image(systemName: healthStatusIcon(bmi: bmi))
                            .foregroundColor(bmiColor(bmi: bmi))
                        
                        Text(healthStatusText(bmi: bmi))
                            .font(.caption)
                            .foregroundColor(bmiColor(bmi: bmi))
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Target Weight Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Target Weight")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Target Weight:")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        HStack {
                            Button("-") {
                                if targetWeight > 40 {
                                    targetWeight -= 0.5
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(15)
                            
                            Text(String(format: "%.1f kg", targetWeight))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(minWidth: 60)
                            
                            Button("+") {
                                if targetWeight < 150 {
                                    targetWeight += 0.5
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(15)
                        }
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Calculation Details
                let bmr = calculateDetailedBMR(weight: effectiveWeight, height: effectiveHeight, age: effectiveAge, gender: effectiveGender)
                let activeCalories = healthMetrics?.activeCalories ?? 0.0
                let maintenanceCalories = calculateMaintenanceCalories(bmr: bmr, activityLevel: .autoCalculated, activeCalories: activeCalories)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("How it's calculated")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("BMR (Basal Metabolic Rate)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Your body's basic energy needs (Mifflin-St Jeor formula): \(String(format: "%.0f", bmr)) kcal/day")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Base Daily Activity")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("BMR × 1.2 (sedentary baseline): \(String(format: "%.0f", bmr * 1.2)) kcal/day")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "3.circle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Exercise & Active Calories")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("From workouts and activities: \(String(format: "%.0f", activeCalories)) kcal/day")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Image(systemName: "equal.circle.fill")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Maintenance Calories")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Total to maintain current weight: \(String(format: "%.0f", maintenanceCalories)) kcal/day")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deficit Calculation")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Maintenance Calories - Calories Eaten = Deficit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• 500 kcal deficit = ~1 lb weight loss per week")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• 1000 kcal deficit = ~2 lb weight loss per week")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                
                // Energy Breakdown
                VStack(alignment: .leading, spacing: 16) {
                    Text("Today's Energy Breakdown")
                        .font(.headline)
                    
                    EnergyBreakdownRow(title: "BMR (Basic Needs)", value: bmr, color: .blue)
                    EnergyBreakdownRow(title: "Base Activity (20%)", value: bmr * 0.2, color: .green)
                    EnergyBreakdownRow(title: "Measured Active Calories", value: activeCalories, color: .orange)
                    EnergyBreakdownRow(title: "Total Maintenance", value: maintenanceCalories, color: .purple)
                    
                    Divider()
                    
                    EnergyBreakdownRow(title: "Calories Eaten", value: todaysCalories, color: .red)
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Caloric Deficit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Initialize default weight from health metrics
            if let metrics = healthMetrics {
                defaultWeight = metrics.bodyWeight > 0 ? metrics.bodyWeight : 70.0
            }
            
            // Automatically load profile from HealthKit for calculations
        Task {
                await loadProfileFromHealthKit()
            }
        }
    }
    
    private func calculateDetailedBMR(weight: Double, height: Double, age: Double, gender: String) -> Double {
        // Use the same improved Mifflin-St Jeor formula
        return calculateBMR(weight: weight, height: height, age: age, gender: gender)
    }
    
    private func calculateBMI(weight: Double, height: Double) -> Double {
        guard weight > 0 && height > 0 else { return 0.0 }
        let heightInMeters = height / 100.0
        return weight / (heightInMeters * heightInMeters)
    }
    
    private func bmiCategory(bmi: Double) -> String {
        switch bmi {
        case 0...18.5: return "Underweight"
        case 18.5...24.9: return "Normal"
        case 25...29.9: return "Overweight"
        case 30...34.9: return "Obese I"
        case 35...39.9: return "Obese II"
        default: return "Obese III"
        }
    }
    
    private func bmiColor(bmi: Double) -> Color {
        switch bmi {
        case 0...18.5: return .blue
        case 18.5...24.9: return .green
        case 25...29.9: return .orange
        default: return .red
        }
    }
    
    private func healthStatusIcon(bmi: Double) -> String {
        switch bmi {
        case 18.5...24.9: return "checkmark.circle.fill"
        case 25...29.9: return "exclamationmark.triangle.fill"
        default: return "xmark.circle.fill"
        }
    }
    
    private func healthStatusText(bmi: Double) -> String {
        switch bmi {
        case 18.5...24.9: return "Healthy weight range"
        case 25...29.9: return "Consider lifestyle changes"
        case 30...: return "Monitor weight closely"
        default: return "Monitor weight closely"
        }
    }
    
    // MARK: - HealthKit Profile Loading
    
    private func loadProfileFromHealthKit() async {
        guard healthKitService.hasValidAuthorization() else {
            return
        }
        
        let profile = await healthKitService.getUserProfile()
        
                await MainActor.run {
            if let profile = profile {
                self.userProfile = profile
                print("✅ Successfully loaded profile from HealthKit for calculations")
                print("📊 Age: \(profile.displayAge), Gender: \(profile.displayGender)")
                print("📊 Height: \(profile.displayHeight), Weight: \(profile.displayWeight)")
            }
        }
    }
    
    // Use HealthKit data in calculations when available
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
}

// Add new struct
struct EnergyBreakdownRow: View {
    let title: String
    let value: Double
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(String(format: "%.0f kcal", value))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Nutrient Information Structure
struct NutrientInfo {
    let name: String
    let displayName: String
    let unit: String
    let dailyValue: Double
    let color: Color
    let benefits: [String]
    let description: String
    let foodSources: [String]
    let deficiencySymptoms: [String]
    
    // Vitamins
    static let vitaminC = NutrientInfo(
        name: "vitaminC",
        displayName: "Vitamin C",
        unit: "mg",
        dailyValue: 90,
        color: .orange,
        benefits: [
            "Powerful antioxidant protection",
            "Boosts immune system function",
            "Supports collagen production",
            "Enhances iron absorption",
            "Promotes wound healing"
        ],
        description: "Vitamin C is a water-soluble vitamin essential for immune function, collagen synthesis, and antioxidant protection.",
        foodSources: ["Citrus fruits", "Bell peppers", "Strawberries", "Broccoli", "Kiwi", "Brussels sprouts"],
        deficiencySymptoms: ["Fatigue", "Frequent infections", "Slow wound healing", "Bleeding gums", "Joint pain"]
    )
    
    static let vitaminD = NutrientInfo(
        name: "vitaminD",
        displayName: "Vitamin D",
        unit: "mcg",
        dailyValue: 20,
        color: .yellow,
        benefits: [
            "Essential for bone health",
            "Supports immune function",
            "Regulates calcium absorption",
            "May improve mood",
            "Supports muscle function"
        ],
        description: "Vitamin D is crucial for bone health, immune function, and calcium absorption. Your body produces it when exposed to sunlight.",
        foodSources: ["Fatty fish", "Egg yolks", "Fortified milk", "Fortified cereals", "Mushrooms", "Sunlight exposure"],
        deficiencySymptoms: ["Bone pain", "Muscle weakness", "Fatigue", "Depression", "Frequent infections"]
    )
    
    static let vitaminA = NutrientInfo(
        name: "vitaminA",
        displayName: "Vitamin A",
        unit: "mcg",
        dailyValue: 900,
        color: .red,
        benefits: [
            "Essential for vision health",
            "Supports immune function",
            "Promotes cell growth",
            "Maintains healthy skin",
            "Supports reproductive health"
        ],
        description: "Vitamin A is vital for vision, immune function, and cell growth. It exists in two forms: retinol and beta-carotene.",
        foodSources: ["Carrots", "Sweet potatoes", "Spinach", "Kale", "Red bell peppers", "Eggs"],
        deficiencySymptoms: ["Night blindness", "Dry skin", "Frequent infections", "Poor wound healing", "Dry eyes"]
    )
    
    static let vitaminE = NutrientInfo(
        name: "vitaminE",
        displayName: "Vitamin E",
        unit: "mg",
        dailyValue: 15,
        color: .green,
        benefits: [
            "Powerful antioxidant",
            "Protects cell membranes",
            "Supports immune function",
            "Promotes skin health",
            "May reduce inflammation"
        ],
        description: "Vitamin E is a fat-soluble antioxidant that protects cells from oxidative damage and supports immune function.",
        foodSources: ["Nuts", "Seeds", "Vegetable oils", "Leafy greens", "Avocado", "Wheat germ"],
        deficiencySymptoms: ["Muscle weakness", "Vision problems", "Immune dysfunction", "Nerve damage", "Coordination problems"]
    )
    
    static let vitaminB12 = NutrientInfo(
        name: "vitaminB12",
        displayName: "Vitamin B12",
        unit: "mcg",
        dailyValue: 2.4,
        color: .blue,
        benefits: [
            "Essential for nerve function",
            "Supports red blood cell formation",
            "Aids DNA synthesis",
            "Supports brain health",
            "Prevents megaloblastic anemia"
        ],
        description: "Vitamin B12 is crucial for nerve function, red blood cell formation, and DNA synthesis. It's primarily found in animal products.",
        foodSources: ["Fish", "Meat", "Poultry", "Eggs", "Dairy products", "Fortified cereals"],
        deficiencySymptoms: ["Fatigue", "Memory problems", "Nerve damage", "Anemia", "Depression"]
    )
    
    static let folate = NutrientInfo(
        name: "folate",
        displayName: "Folate (B9)",
        unit: "mcg",
        dailyValue: 400,
        color: .purple,
        benefits: [
            "Essential for DNA synthesis",
            "Supports red blood cell formation",
            "Crucial during pregnancy",
            "Prevents neural tube defects",
            "Supports brain function"
        ],
        description: "Folate is essential for DNA synthesis, red blood cell formation, and is particularly important during pregnancy.",
        foodSources: ["Leafy greens", "Legumes", "Fortified cereals", "Asparagus", "Citrus fruits", "Avocado"],
        deficiencySymptoms: ["Anemia", "Fatigue", "Poor concentration", "Irritability", "Birth defects (in pregnancy)"]
    )
    
    // Minerals
    static let calcium = NutrientInfo(
        name: "calcium",
        displayName: "Calcium",
        unit: "mg",
        dailyValue: 1000,
        color: .cyan,
        benefits: [
            "Essential for bone health",
            "Supports muscle function",
            "Enables nerve transmission",
            "Required for blood clotting",
            "Helps maintain healthy teeth"
        ],
        description: "Calcium is the most abundant mineral in the body, essential for strong bones and teeth, muscle function, and nerve transmission.",
        foodSources: ["Dairy products", "Leafy greens", "Sardines", "Almonds", "Fortified plant milks", "Broccoli"],
        deficiencySymptoms: ["Weak bones", "Dental problems", "Muscle cramps", "Numbness", "Osteoporosis risk"]
    )
    
    static let iron = NutrientInfo(
        name: "iron",
        displayName: "Iron",
        unit: "mg",
        dailyValue: 18,
        color: .red,
        benefits: [
            "Essential for oxygen transport",
            "Supports energy production",
            "Maintains healthy red blood cells",
            "Supports immune function",
            "Important for brain development"
        ],
        description: "Iron is essential for oxygen transport in blood and energy production. It's a key component of hemoglobin and myoglobin.",
        foodSources: ["Red meat", "Poultry", "Fish", "Lentils", "Spinach", "Fortified cereals"],
        deficiencySymptoms: ["Fatigue", "Weakness", "Pale skin", "Shortness of breath", "Cold hands and feet"]
    )
    
    static let magnesium = NutrientInfo(
        name: "magnesium",
        displayName: "Magnesium",
        unit: "mg",
        dailyValue: 400,
        color: .green,
        benefits: [
            "Supports muscle function",
            "Maintains bone health",
            "Regulates blood sugar",
            "Supports heart rhythm",
            "Essential for protein synthesis"
        ],
        description: "Magnesium is involved in over 300 enzyme reactions and is essential for muscle function, bone health, and energy metabolism.",
        foodSources: ["Nuts", "Seeds", "Whole grains", "Leafy greens", "Fish", "Dark chocolate"],
        deficiencySymptoms: ["Muscle cramps", "Fatigue", "Irregular heartbeat", "Personality changes", "Seizures"]
    )
    
    static let potassium = NutrientInfo(
        name: "potassium",
        displayName: "Potassium",
        unit: "mg",
        dailyValue: 3500,
        color: .orange,
        benefits: [
            "Regulates blood pressure",
            "Supports heart function",
            "Maintains fluid balance",
            "Essential for muscle contractions",
            "Supports nerve function"
        ],
        description: "Potassium is essential for heart function, muscle contractions, and maintaining healthy blood pressure.",
        foodSources: ["Bananas", "Potatoes", "Beans", "Spinach", "Avocado", "Orange juice"],
        deficiencySymptoms: ["Weakness", "Fatigue", "Muscle cramps", "Irregular heartbeat", "Constipation"]
    )
    
    static let zinc = NutrientInfo(
        name: "zinc",
        displayName: "Zinc",
        unit: "mg",
        dailyValue: 11,
        color: .purple,
        benefits: [
            "Supports immune function",
            "Promotes wound healing",
            "Essential for growth",
            "Supports taste and smell",
            "Required for protein synthesis"
        ],
        description: "Zinc is essential for immune function, wound healing, and proper growth and development.",
        foodSources: ["Meat", "Shellfish", "Legumes", "Seeds", "Nuts", "Dairy products"],
        deficiencySymptoms: ["Poor wound healing", "Frequent infections", "Hair loss", "Loss of taste", "Growth problems"]
    )
    
    static let sodium = NutrientInfo(
        name: "sodium",
        displayName: "Sodium",
        unit: "mg",
        dailyValue: 2300,
        color: .gray,
        benefits: [
            "Maintains fluid balance",
            "Essential for nerve function",
            "Supports muscle contractions",
            "Regulates blood pressure",
            "Aids nutrient absorption"
        ],
        description: "Sodium is essential for fluid balance and nerve function, but most people consume too much. The goal is to stay under 2,300mg daily.",
        foodSources: ["Table salt", "Processed foods", "Bread", "Pizza", "Soup", "Deli meats"],
        deficiencySymptoms: ["Muscle cramps", "Nausea", "Vomiting", "Headache", "Fatigue"]
    )
}

// MARK: - Clickable Vitamin and Mineral Item Component
struct ClickableVitaminMineralItem: View {
    let nutrient: NutrientInfo
    let value: Double
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(nutrient.color)
                        .frame(width: 8, height: 8)
                    
                    Text(nutrient.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 0)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(String(format: value < 1 ? "%.1f" : "%.0f", value))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(nutrient.color)
                        
                        Text(nutrient.unit)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    let progress = value / nutrient.dailyValue
                    ProgressView(value: min(progress, 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: nutrient.color))
                        .scaleEffect(x: 1, y: 0.5)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(nutrient.color.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(nutrient.color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Nutrient Detail View
struct NutrientDetailView: View {
    let nutrient: NutrientInfo
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(nutrient.color)
                                .frame(width: 20, height: 20)
                            
                            Text(nutrient.displayName)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                        }
                        
                        Text(nutrient.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Daily Value
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended Daily Value")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Text("\(String(format: nutrient.dailyValue < 1 ? "%.1f" : "%.0f", nutrient.dailyValue)) \(nutrient.unit)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(nutrient.color)
                            
                            Spacer()
                        }
                        .padding()
                        .background(nutrient.color.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Benefits
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Health Benefits")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        ForEach(nutrient.benefits, id: \.self) { benefit in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))
                                
                                Text(benefit)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                        }
                    }
                    
                    // Food Sources
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Best Food Sources")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                            ForEach(nutrient.foodSources, id: \.self) { source in
                                HStack {
                                    Image(systemName: "leaf.fill")
                                        .foregroundColor(nutrient.color)
                                        .font(.caption)
                                    
                                    Text(source)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Deficiency Symptoms
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Signs of Deficiency")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        ForEach(nutrient.deficiencySymptoms, id: \.self) { symptom in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 16))
                                
                                Text(symptom)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                        }
                    }
                    
                    // Special note for sodium
                    if nutrient.name == "sodium" {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Important Note")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            
                            Text("Most people consume too much sodium. The American Heart Association recommends limiting sodium to 1,500mg per day for optimal heart health, though the general guideline is under 2,300mg.")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Original Vitamin and Mineral Item Component (kept for compatibility)
struct VitaminMineralItem: View {
    let name: String
    let value: Double
    let unit: String
    let dailyValue: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text(String(format: value < 1 ? "%.1f" : "%.0f", value))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                    
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                let progress = value / dailyValue
                ProgressView(value: min(progress, 1.0))
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                    .scaleEffect(x: 1, y: 0.5)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(color.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    NutritionView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
