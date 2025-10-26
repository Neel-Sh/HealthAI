import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutLog
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with workout type and date
                    headerSection
                    
                    // Key metrics in a clean grid
                    keyMetricsSection
                    
                    // Performance insights (only if data available)
                    if hasPerformanceData {
                        performanceSection
                    }
                    
                    // Heart rate analysis (only if available)
                    if workout.avgHeartRate > 0 {
                        heartRateAnalysisSection
                    }
                    
                    // Training zones and intensity
                    if workout.avgHeartRate > 0 {
                        trainingZoneSection
                    }
                    
                    // Workout insights
                    workoutInsightsSection
                    
                    // Recovery and effort
                    if workout.perceivedExertion > 0 || workout.avgHeartRate > 0 {
                        recoveryEffortSection
                    }
                    
                    // Notes section (if any)
                    if let notes = workout.notes, !notes.isEmpty {
                        notesSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Workout Details")
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
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Workout icon
            Image(systemName: workout.workoutTypeIcon)
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .frame(width: 80, height: 80)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(20)
            
            // Workout type and date
            VStack(spacing: 4) {
                Text(workout.workoutType.capitalized)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(workout.timestamp.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Key Metrics Section
    
    private var keyMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                
                // Duration - always available
                WorkoutMetricTile(
                    title: "Duration",
                    value: workout.formattedDuration,
                    icon: "timer",
                    color: .green
                )
                
                // Distance - if available
                if workout.distance > 0 {
                    WorkoutMetricTile(
                        title: "Distance",
                        value: workout.formattedDistance,
                        icon: "location",
                        color: .blue
                    )
                }
                
                // Calories - if available
                if workout.calories > 0 {
                    WorkoutMetricTile(
                        title: "Calories",
                        value: String(format: "%.0f", workout.calories),
                        icon: "flame.fill",
                        color: .orange
                    )
                }
                
                // Pace - if available and makes sense
                if workout.pace > 0 && workout.distance > 0 {
                    WorkoutMetricTile(
                        title: "Avg Pace",
                        value: workout.formattedPace,
                        icon: "speedometer",
                        color: .purple
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Elevation gain
                if workout.elevation > 0 {
                    PerformanceRow(
                        title: "Elevation Gain",
                        value: String(format: "%.0f m", workout.elevation),
                        icon: "mountain.2",
                        color: .brown
                    )
                }
                
                // Cadence
                if workout.cadence > 0 {
                    PerformanceRow(
                        title: "Cadence",
                        value: String(format: "%.0f spm", workout.cadence),
                        icon: "metronome",
                        color: .indigo
                    )
                }
                
                // VO2 Max
                if workout.vo2Max > 0 {
                    PerformanceRow(
                        title: "VO₂ Max",
                        value: String(format: "%.1f ml/kg/min", workout.vo2Max),
                        icon: "lungs",
                        color: .teal
                    )
                }
                
                // Power output
                if workout.powerOutput > 0 {
                    PerformanceRow(
                        title: "Average Power",
                        value: String(format: "%.0f W", workout.powerOutput),
                        icon: "bolt",
                        color: .yellow
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Heart Rate Analysis Section
    
    private var heartRateAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Heart Rate Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Heart rate metrics
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                HeartRateMetric(
                    title: "Average",
                    value: "\(workout.avgHeartRate)",
                    unit: "bpm",
                    color: .red
                )
                
                if workout.maxHeartRate > 0 {
                    HeartRateMetric(
                        title: "Maximum",
                        value: "\(workout.maxHeartRate)",
                        unit: "bpm",
                        color: .orange
                    )
                }
                
                HeartRateMetric(
                    title: "% of Max",
                    value: String(format: "%.0f", heartRatePercentage),
                    unit: "%",
                    color: .blue
                )
            }
            
            // Heart rate reserve and intensity
            VStack(spacing: 8) {
                HStack {
                    Text("Heart Rate Reserve")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(String(format: "%.0f%%", heartRateReservePercentage))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                ProgressBar(
                    value: heartRateReservePercentage / 100,
                    color: .blue,
                    backgroundColor: Color(.systemGray5)
                )
                .frame(height: 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Training Zone Section
    
    private var trainingZoneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Zone")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                // Zone indicator
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(heartRateZoneColor)
                            .frame(width: 16, height: 16)
                        
                        Text(heartRateZoneName)
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    Text(zoneDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Zone range
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Zone Range")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(zoneRange)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            // Training effect
            VStack(spacing: 8) {
                HStack {
                    Text("Training Effect")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(trainingEffect)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(trainingEffectColor)
                }
                
                Text(trainingEffectDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Workout Insights Section
    
    private var workoutInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workout Insights")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Calories per minute
                WorkoutInsightRow(
                    icon: "flame.fill",
                    title: "Calories per Minute",
                    value: String(format: "%.1f kcal/min", caloriesPerMinute),
                    color: .orange
                )
                
                // Distance per minute (if applicable)
                if workout.distance > 0 {
                    WorkoutInsightRow(
                        icon: "speedometer",
                        title: "Average Speed",
                        value: String(format: "%.1f km/h", averageSpeed),
                        color: .blue
                    )
                }
                
                // Workout intensity
                WorkoutInsightRow(
                    icon: "bolt.fill",
                    title: "Workout Intensity",
                    value: workoutIntensity,
                    color: intensityColor
                )
                
                // Estimated recovery time
                WorkoutInsightRow(
                    icon: "clock.fill",
                    title: "Estimated Recovery",
                    value: estimatedRecoveryTime,
                    color: .green
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Recovery & Effort Section
    
    private var recoveryEffortSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Effort & Recovery")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                // Perceived effort (if available)
                if workout.perceivedExertion > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Perceived Effort")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(workout.perceivedExertion)/10")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        
                        // Effort scale visualization
                        HStack(spacing: 4) {
                            ForEach(1...10, id: \.self) { level in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(level <= workout.perceivedExertion ? Color.orange : Color(.systemGray5))
                                    .frame(height: 8)
                            }
                        }
                        
                        Text(effortDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Recovery recommendation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Recommendation")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 8) {
                        Image(systemName: recoveryIcon)
                            .foregroundColor(recoveryColor)
                        
                        Text(recoveryRecommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(workout.notes ?? "")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Computed Properties
    
    private var hasPerformanceData: Bool {
        workout.elevation > 0 || workout.cadence > 0 || workout.vo2Max > 0 || workout.powerOutput > 0
    }
    
    // Heart Rate Calculations
    private let estimatedMaxHR: Double = 190.0 // Should come from user profile (220 - age)
    private let restingHR: Double = 60.0 // Should come from user profile
    
    private var heartRatePercentage: Double {
        (Double(workout.avgHeartRate) / estimatedMaxHR) * 100
    }
    
    private var heartRateReservePercentage: Double {
        let hrReserve = estimatedMaxHR - restingHR
        let workingHR = Double(workout.avgHeartRate) - restingHR
        return (workingHR / hrReserve) * 100
    }
    
    private var heartRateZoneName: String {
        let percentage = heartRatePercentage / 100
        
        switch percentage {
        case 0..<0.6: return "Zone 1 - Recovery"
        case 0.6..<0.7: return "Zone 2 - Fat Burn"
        case 0.7..<0.8: return "Zone 3 - Aerobic"
        case 0.8..<0.9: return "Zone 4 - Threshold"
        default: return "Zone 5 - VO₂ Max"
        }
    }
    
    private var heartRateZoneColor: Color {
        let percentage = heartRatePercentage / 100
        
        switch percentage {
        case 0..<0.6: return .gray
        case 0.6..<0.7: return .green
        case 0.7..<0.8: return .yellow
        case 0.8..<0.9: return .orange
        default: return .red
        }
    }
    
    private var zoneDescription: String {
        let percentage = heartRatePercentage / 100
        
        switch percentage {
        case 0..<0.6: return "Active recovery, very light intensity"
        case 0.6..<0.7: return "Fat burning, aerobic base building"
        case 0.7..<0.8: return "Aerobic fitness, comfortable pace"
        case 0.8..<0.9: return "Lactate threshold, comfortably hard"
        default: return "VO₂ max, very hard intensity"
        }
    }
    
    private var zoneRange: String {
        let percentage = heartRatePercentage / 100
        let lowerBound: Double
        let upperBound: Double
        
        switch percentage {
        case 0..<0.6:
            lowerBound = 0.5
            upperBound = 0.6
        case 0.6..<0.7:
            lowerBound = 0.6
            upperBound = 0.7
        case 0.7..<0.8:
            lowerBound = 0.7
            upperBound = 0.8
        case 0.8..<0.9:
            lowerBound = 0.8
            upperBound = 0.9
        default:
            lowerBound = 0.9
            upperBound = 1.0
        }
        
        let lower = Int(estimatedMaxHR * lowerBound)
        let upper = Int(estimatedMaxHR * upperBound)
        return "\(lower)-\(upper) bpm"
    }
    
    // Training Effect Calculations
    private var trainingEffect: String {
        let intensity = heartRateReservePercentage / 100
        let duration = workout.duration / 3600.0 // Convert to hours
        let effect = intensity * duration * 2.5
        
        switch effect {
        case 0..<1.0: return "1.0 - Maintaining"
        case 1.0..<2.0: return "2.0 - Base Building"
        case 2.0..<3.0: return "3.0 - Improving"
        case 3.0..<4.0: return "4.0 - Highly Improving"
        default: return "5.0 - Overreaching"
        }
    }
    
    private var trainingEffectColor: Color {
        let intensity = heartRateReservePercentage / 100
        let duration = workout.duration / 3600.0
        let effect = intensity * duration * 2.5
        
        switch effect {
        case 0..<1.0: return .blue
        case 1.0..<2.0: return .green
        case 2.0..<3.0: return .orange
        case 3.0..<4.0: return .red
        default: return .purple
        }
    }
    
    private var trainingEffectDescription: String {
        let intensity = heartRateReservePercentage / 100
        let duration = workout.duration / 3600.0
        let effect = intensity * duration * 2.5
        
        switch effect {
        case 0..<1.0: return "Light session maintaining current fitness"
        case 1.0..<2.0: return "Building aerobic base and endurance"
        case 2.0..<3.0: return "Improving aerobic capacity"
        case 3.0..<4.0: return "Highly beneficial for fitness gains"
        default: return "Very intense - ensure adequate recovery"
        }
    }
    
    // Workout Insights
    private var caloriesPerMinute: Double {
        guard workout.duration > 0 else { return 0 }
        return workout.calories / (workout.duration / 60.0)
    }
    
    private var averageSpeed: Double {
        guard workout.duration > 0 && workout.distance > 0 else { return 0 }
        return (workout.distance / (workout.duration / 3600.0))
    }
    
    private var workoutIntensity: String {
        let percentage = heartRatePercentage
        
        switch percentage {
        case 0..<50: return "Very Light"
        case 50..<60: return "Light"
        case 60..<70: return "Moderate"
        case 70..<80: return "Hard"
        case 80..<90: return "Very Hard"
        default: return "Maximum"
        }
    }
    
    private var intensityColor: Color {
        let percentage = heartRatePercentage
        
        switch percentage {
        case 0..<50: return .gray
        case 50..<60: return .green
        case 60..<70: return .blue
        case 70..<80: return .yellow
        case 80..<90: return .orange
        default: return .red
        }
    }
    
    private var estimatedRecoveryTime: String {
        let intensity = heartRatePercentage / 100
        let duration = workout.duration / 3600.0
        let recoveryScore = intensity * duration * 24 // Hours
        
        switch recoveryScore {
        case 0..<12: return "6-12 hours"
        case 12..<24: return "12-24 hours"
        case 24..<48: return "1-2 days"
        case 48..<72: return "2-3 days"
        default: return "3+ days"
        }
    }
    
    // Effort and Recovery
    private var effortDescription: String {
        switch workout.perceivedExertion {
        case 1...2: return "Very easy, could maintain for hours"
        case 3...4: return "Easy, comfortable conversational pace"
        case 5...6: return "Moderate, some effort required"
        case 7...8: return "Hard, difficult to maintain conversation"
        case 9...10: return "Very hard, maximum sustainable effort"
        default: return "Effort level not recorded"
        }
    }
    
    private var recoveryRecommendation: String {
        let hrIntensity = heartRatePercentage
        let effort = workout.perceivedExertion
        let duration = workout.duration / 60.0 // minutes
        
        if hrIntensity > 85 || effort >= 8 || duration > 90 {
            return "High intensity session. Take 1-2 easy days, focus on sleep and nutrition."
        } else if hrIntensity > 70 || effort >= 6 || duration > 60 {
            return "Moderate session. Light activity tomorrow or rest day recommended."
        } else {
            return "Light session. You can train again tomorrow with moderate intensity."
        }
    }
    
    private var recoveryIcon: String {
        let hrIntensity = heartRatePercentage
        let effort = workout.perceivedExertion
        
        if hrIntensity > 85 || effort >= 8 {
            return "bed.double.fill"
        } else if hrIntensity > 70 || effort >= 6 {
            return "figure.walk"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    private var recoveryColor: Color {
        let hrIntensity = heartRatePercentage
        let effort = workout.perceivedExertion
        
        if hrIntensity > 85 || effort >= 8 {
            return .red
        } else if hrIntensity > 70 || effort >= 6 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Supporting Views

struct PerformanceRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
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
        .padding(.vertical, 4)
    }
}

struct HeartRateMetric: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ProgressBar: View {
    let value: Double // 0.0 to 1.0
    let color: Color
    let backgroundColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(backgroundColor)
                    .cornerRadius(4)
                
                Rectangle()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
                    .cornerRadius(4)
            }
        }
    }
}

struct WorkoutInsightRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
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
        .padding(.vertical, 6)
    }
}

struct WorkoutMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let sampleWorkout = WorkoutLog(context: context)
    sampleWorkout.id = UUID()
    sampleWorkout.workoutType = "Running"
    sampleWorkout.duration = 2400 // 40 minutes
    sampleWorkout.distance = 5.2
    sampleWorkout.calories = 420
    sampleWorkout.avgHeartRate = 155
    sampleWorkout.maxHeartRate = 172
    sampleWorkout.timestamp = Date()
    
    return WorkoutDetailView(workout: sampleWorkout)
}