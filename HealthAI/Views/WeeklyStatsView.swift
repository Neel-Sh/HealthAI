import SwiftUI
import CoreData

struct WeeklyStatsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var healthKitService: HealthKitService
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        animation: .default)
    private var healthMetrics: FetchedResults<HealthMetrics>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)],
        animation: .default)
    private var workouts: FetchedResults<WorkoutLog>
    
    @State private var selectedWeekOffset = 0 // 0 = current week, -1 = last week, etc.
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Week selector
                    weekSelector
                    
                    // Overview cards
                    overviewSection
                    
                    // Activity chart
                    activityChartSection
                    
                    // Detailed stats
                    detailedStatsSection
                    
                    // Workouts this week
                    workoutsSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weekly Stats")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    // MARK: - Week Selector
    
    private var weekSelector: some View {
        HStack(spacing: 16) {
            Button(action: { selectedWeekOffset -= 1 }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .disabled(selectedWeekOffset <= -4) // Limit to 4 weeks back
            
            Spacer()
            
            VStack(spacing: 4) {
                Text(weekTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(weekDateRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { selectedWeekOffset += 1 }) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .disabled(selectedWeekOffset >= 0) // Can't go into future
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Overview Section
    
    private var overviewSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Total Steps",
                value: String(format: "%.0f", weeklyStats.totalSteps),
                icon: "figure.walk",
                color: .blue,
                change: weeklyStats.stepsChange
            )
            
            StatCard(
                title: "Active Minutes",
                value: String(format: "%.0f", weeklyStats.totalActiveMinutes),
                icon: "timer",
                color: .green,
                change: weeklyStats.activeMinutesChange
            )
            
            StatCard(
                title: "Calories Burned",
                value: String(format: "%.0f", weeklyStats.totalCalories),
                icon: "flame.fill",
                color: .orange,
                change: weeklyStats.caloriesChange
            )
            
            StatCard(
                title: "Workouts",
                value: "\(weeklyStats.totalWorkouts)",
                icon: "dumbbell.fill",
                color: .purple,
                change: weeklyStats.workoutsChange
            )
        }
    }
    
    // MARK: - Activity Chart Section
    
    private var activityChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Activity")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Simple bar chart
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7) { dayIndex in
                    let dayStats = getDayStats(dayOffset: dayIndex)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: 32, height: max(4, CGFloat(dayStats.steps / 500))) // Scale steps
                            .animation(.easeInOut, value: dayStats.steps)
                        
                        Text(dayName(dayOffset: dayIndex))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 120)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Detailed Stats Section
    
    private var detailedStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Health Metrics")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                DetailedStatRow(
                    title: "Average Heart Rate",
                    value: String(format: "%.0f bpm", weeklyStats.averageHeartRate),
                    icon: "heart.fill",
                    color: .red
                )
                
                DetailedStatRow(
                    title: "Average Sleep",
                    value: String(format: "%.1f hours", weeklyStats.averageSleep),
                    icon: "bed.double.fill",
                    color: .indigo
                )
                
                DetailedStatRow(
                    title: "Total Distance",
                    value: String(format: "%.1f km", weeklyStats.totalDistance),
                    icon: "location.fill",
                    color: .teal
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Workouts Section
    
    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This Week's Workouts")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(thisWeekWorkouts.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
            
            if thisWeekWorkouts.isEmpty {
                Text("No workouts this week")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(thisWeekWorkouts, id: \.id) { workout in
                        WorkoutSummaryRow(workout: workout)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    
    private var weekTitle: String {
        switch selectedWeekOffset {
        case 0: return "This Week"
        case -1: return "Last Week"
        default: return "\(-selectedWeekOffset) Weeks Ago"
        }
    }
    
    private var weekDateRange: String {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let targetWeekStart = calendar.date(byAdding: .weekOfYear, value: selectedWeekOffset, to: weekStart) ?? weekStart
        let targetWeekEnd = calendar.date(byAdding: .day, value: 6, to: targetWeekStart) ?? targetWeekStart
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        return "\(formatter.string(from: targetWeekStart)) - \(formatter.string(from: targetWeekEnd))"
    }
    
    private var weeklyStats: WeeklyStatsData {
        calculateWeeklyStats()
    }
    
    private var thisWeekWorkouts: [WorkoutLog] {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let targetWeekStart = calendar.date(byAdding: .weekOfYear, value: selectedWeekOffset, to: weekStart) ?? weekStart
        let targetWeekEnd = calendar.date(byAdding: .day, value: 7, to: targetWeekStart) ?? targetWeekStart
        
        return workouts.filter { workout in
            workout.timestamp >= targetWeekStart && workout.timestamp < targetWeekEnd
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateWeeklyStats() -> WeeklyStatsData {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let targetWeekStart = calendar.date(byAdding: .weekOfYear, value: selectedWeekOffset, to: weekStart) ?? weekStart
        let targetWeekEnd = calendar.date(byAdding: .day, value: 7, to: targetWeekStart) ?? targetWeekStart
        
        let weekMetrics = healthMetrics.filter { metric in
            metric.date >= targetWeekStart && metric.date < targetWeekEnd
        }
        
        let weekWorkouts = thisWeekWorkouts
        
        return WeeklyStatsData(
            totalSteps: weekMetrics.reduce(0) { $0 + Double($1.stepCount) },
            totalActiveMinutes: weekMetrics.reduce(0) { $0 + Double($1.activeMinutes) },
            totalCalories: weekMetrics.reduce(0) { $0 + $1.activeCalories },
            totalWorkouts: weekWorkouts.count,
            averageHeartRate: weekMetrics.isEmpty ? 0 : weekMetrics.reduce(0) { $0 + Double($1.restingHeartRate) } / Double(weekMetrics.count),
            averageSleep: weekMetrics.isEmpty ? 0 : weekMetrics.reduce(0) { $0 + $1.sleepHours } / Double(weekMetrics.count),
            totalDistance: weekWorkouts.reduce(0) { $0 + $1.distance },
            stepsChange: 0, // Would need previous week data
            activeMinutesChange: 0,
            caloriesChange: 0,
            workoutsChange: 0
        )
    }
    
    private func getDayStats(dayOffset: Int) -> DayStatsData {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let targetWeekStart = calendar.date(byAdding: .weekOfYear, value: selectedWeekOffset, to: weekStart) ?? weekStart
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: targetWeekStart) ?? targetWeekStart
        
        let dayMetrics = healthMetrics.first { metric in
            calendar.isDate(metric.date, inSameDayAs: targetDay)
        }
        
        return DayStatsData(
            steps: Double(dayMetrics?.stepCount ?? 0),
            activeMinutes: Double(dayMetrics?.activeMinutes ?? 0),
            calories: dayMetrics?.activeCalories ?? 0
        )
    }
    
    private func dayName(dayOffset: Int) -> String {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let targetWeekStart = calendar.date(byAdding: .weekOfYear, value: selectedWeekOffset, to: weekStart) ?? weekStart
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: targetWeekStart) ?? targetWeekStart
        
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: targetDay)
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let change: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
                if change != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption)
                        Text(String(format: "%.0f%%", abs(change)))
                            .font(.caption)
                    }
                    .foregroundColor(change > 0 ? .green : .red)
                }
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

struct DetailedStatRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

struct WorkoutSummaryRow: View {
    let workout: WorkoutLog
    
    var body: some View {
        HStack {
            Image(systemName: workout.workoutTypeIcon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.workoutType.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(workout.timestamp.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(workout.formattedDistance)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(workout.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Data Models

struct WeeklyStatsData {
    let totalSteps: Double
    let totalActiveMinutes: Double
    let totalCalories: Double
    let totalWorkouts: Int
    let averageHeartRate: Double
    let averageSleep: Double
    let totalDistance: Double
    let stepsChange: Double
    let activeMinutesChange: Double
    let caloriesChange: Double
    let workoutsChange: Double
}

struct DayStatsData {
    let steps: Double
    let activeMinutes: Double
    let calories: Double
}

#Preview {
    WeeklyStatsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(HealthKitService(context: PersistenceController.preview.container.viewContext))
}
