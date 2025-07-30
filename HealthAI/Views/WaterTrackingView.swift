import SwiftUI
import CoreData

struct WaterTrackingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDate = Date()
    @State private var todaysWaterIntake: Double = 0.0
    
    private let waterGoal: Double = 8.0 // 8 cups
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with goal progress
                    VStack(spacing: 16) {
                        Text("Water Intake")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Stay hydrated throughout the day")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Large progress circle
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.2), lineWidth: 12)
                                .frame(width: 120, height: 120)
                            
                            Circle()
                                .trim(from: 0, to: min(todaysWaterIntake / waterGoal, 1.0))
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .frame(width: 120, height: 120)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.5), value: todaysWaterIntake)
                            
                            VStack(spacing: 4) {
                                Text("\(String(format: "%.1f", todaysWaterIntake))")
                                    .font(.title)
                                    .fontWeight(.bold)
                                
                                Text("of \(String(format: "%.0f", waterGoal)) cups")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Progress percentage
                        let percentage = min((todaysWaterIntake / waterGoal) * 100, 100)
                        Text("\(String(format: "%.0f", percentage))% of daily goal")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 20)
                    
                    // Quick add buttons
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Add")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            WaterButton(amount: 0.5, unit: "cup", isLarge: true) {
                                logWater(cups: 0.5)
                            }
                            
                            WaterButton(amount: 1, unit: "cup", isLarge: true) {
                                logWater(cups: 1)
                            }
                            
                            WaterButton(amount: 2, unit: "cups", isLarge: true) {
                                logWater(cups: 2)
                            }
                            
                            WaterButton(amount: 4, unit: "cups", isLarge: true) {
                                logWater(cups: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Today's water log
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Today's Water Log")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if todaysWaterLogs.isEmpty {
                            Text("No water logged today")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(todaysWaterLogs, id: \.self) { log in
                                HStack {
                                    Image(systemName: "drop.fill")
                                        .foregroundColor(.blue)
                                    
                                    Text("\(String(format: "%.1f", log.quantity)) \(log.unit ?? "cups")")
                                        .font(.subheadline)
                                    
                                    Spacer()
                                    
                                    Text(log.date.formatted(date: .omitted, time: .shortened) ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Tips section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hydration Tips")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HydrationTip(icon: "clock", text: "Drink water first thing in the morning")
                            HydrationTip(icon: "figure.walk", text: "Carry a water bottle with you")
                            HydrationTip(icon: "bell", text: "Set reminders to drink water regularly")
                            HydrationTip(icon: "fork.knife", text: "Drink water before and after meals")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            calculateTodaysWaterIntake()
        }
    }
    
    // MARK: - Data Fetching
    
    private var todaysWaterLogs: [NutritionLog] {
        let request: NSFetchRequest<NutritionLog> = NutritionLog.fetchRequest()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        request.predicate = NSPredicate(format: "date >= %@ AND date < %@ AND mealType == %@", 
                                      startOfDay as NSDate, endOfDay as NSDate, "water")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \NutritionLog.date, ascending: false)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching water logs: \(error)")
            return []
        }
    }
    
    private func calculateTodaysWaterIntake() {
        let waterLogs = todaysWaterLogs
        todaysWaterIntake = waterLogs.reduce(0) { sum, log in
            sum + log.quantity
        }
    }
    
    private func logWater(cups: Double) {
        let waterLog = NutritionLog(context: viewContext)
        waterLog.foodName = "Water"
        waterLog.mealType = "water"
        waterLog.date = selectedDate
        waterLog.waterIntake = cups * 236.588 // Convert cups to ml (1 cup = 236.588 ml)
        waterLog.calories = 0
        waterLog.protein = 0
        waterLog.carbs = 0
        waterLog.fat = 0
        waterLog.fiber = 0
        waterLog.sugar = 0
        waterLog.sodium = 0
        waterLog.quantity = cups
        waterLog.unit = "cups"
        waterLog.isFromApp = true
        
        do {
            try viewContext.save()
            calculateTodaysWaterIntake()
            print("Water logged successfully: \(cups) cups")
        } catch {
            print("Error logging water: \(error)")
        }
    }
}

struct HydrationTip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct WaterButton: View {
    let amount: Double
    let unit: String
    let isLarge: Bool
    let action: () -> Void
    
    init(amount: Double, unit: String, isLarge: Bool = false, action: @escaping () -> Void) {
        self.amount = amount
        self.unit = unit
        self.isLarge = isLarge
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(isLarge ? .title2 : .body)
                    .foregroundColor(.blue)
                
                Text(amount == floor(amount) ? "\(Int(amount))" : "\(amount, specifier: "%.1f")")
                    .font(isLarge ? .headline : .subheadline)
                    .fontWeight(.semibold)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: isLarge ? 80 : 60)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    WaterTrackingView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 
