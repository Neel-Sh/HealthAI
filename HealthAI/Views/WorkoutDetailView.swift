import SwiftUI
import CoreData
import MapKit

struct WorkoutDetailView: View {
    let workout: WorkoutLog
    @State private var selectedMetricTab = 0
    @State private var showingNotes = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Header Card with workout overview
                headerCard
                
                // Performance Summary Cards
                performanceSummaryCards
                
                // Tabbed Metrics Section
                tabbedMetricsSection
                
                // Heart Rate Analysis (if available)
                if hasHeartRateData {
                    heartRateAnalysisCard
                }
                
                // Environmental Conditions (if available)
                if hasEnvironmentalData {
                    environmentalConditionsCard
                }
                
                // Perceived Exertion & Notes
                subjectiveDataCard
                
                // Workout Summary & Insights
                workoutInsightsCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .sheet(isPresented: $showingNotes) {
            WorkoutNotesView(workout: workout)
        }
    }
    
    // MARK: - Header Card
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: workoutIcon)
                    .font(.system(size: 32))
                    .foregroundColor(workoutColor)
                    .frame(width: 60, height: 60)
                    .background(workoutColor.opacity(0.1))
                    .cornerRadius(16)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutType.capitalized)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(workout.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if workout.isFromHealthKit {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("HealthKit")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formattedDuration)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(workoutColor)
                    
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Quick stats row
            HStack(spacing: 0) {
                if workout.distance > 0 {
                    QuickStatView(
                        title: "Distance",
                        value: String(format: "%.2f", workout.distance),
                        unit: "km",
                        color: .blue
                    )
                }
                
                if workout.calories > 0 {
                    QuickStatView(
                        title: "Calories",
                        value: "\(Int(workout.calories))",
                        unit: "cal",
                        color: .orange
                    )
                }
                
                if workout.avgHeartRate > 0 {
                    QuickStatView(
                        title: "Avg HR",
                        value: "\(workout.avgHeartRate)",
                        unit: "bpm",
                        color: .red
                    )
                }
                
                if workout.pace > 0 {
                    QuickStatView(
                        title: "Pace",
                        value: formattedPace,
                        unit: "",
                        color: .green
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Performance Summary Cards
    private var performanceSummaryCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            if workout.vo2Max > 0 {
                PerformanceMetricCard(
                    title: "VO₂ Max",
                    value: String(format: "%.1f", workout.vo2Max),
                    unit: "ml/kg/min",
                    icon: "lungs.fill",
                    color: .mint,
                    status: vo2MaxStatus
                )
            }
            
            if workout.elevation > 0 {
                PerformanceMetricCard(
                    title: "Elevation",
                    value: String(format: "%.0f", workout.elevation),
                    unit: "m",
                    icon: "mountain.2.fill",
                    color: .brown,
                    status: elevationStatus
                )
            }
            
            if workout.cadence > 0 {
                PerformanceMetricCard(
                    title: "Cadence",
                    value: String(format: "%.0f", workout.cadence),
                    unit: "spm",
                    icon: "speedometer",
                    color: .purple,
                    status: cadenceStatus
                )
            }
            
            if workout.powerOutput > 0 {
                PerformanceMetricCard(
                    title: "Power",
                    value: String(format: "%.0f", workout.powerOutput),
                    unit: "W",
                    icon: "bolt.fill",
                    color: .yellow,
                    status: powerStatus
                )
            }
        }
    }
    
    // MARK: - Tabbed Metrics Section
    private var tabbedMetricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Tab picker
            Picker("Metrics", selection: $selectedMetricTab) {
                Text("Performance").tag(0)
                Text("Physiology").tag(1)
                if hasAdvancedMetrics {
                    Text("Advanced").tag(2)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Tab content
            Group {
                switch selectedMetricTab {
                case 0:
                    performanceMetricsView
                case 1:
                    physiologyMetricsView
                case 2:
                    advancedMetricsView
                default:
                    performanceMetricsView
                }
            }
            .animation(.easeInOut(duration: 0.3), value: selectedMetricTab)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    private var performanceMetricsView: some View {
        VStack(spacing: 12) {
            if workout.distance > 0 {
                DetailedMetricRow(
                    icon: "location.fill",
                    title: "Distance",
                    value: String(format: "%.2f km", workout.distance),
                    subtitle: "Total distance covered",
                    color: .blue
                )
            }
            
            if workout.pace > 0 {
                DetailedMetricRow(
                    icon: "timer",
                    title: "Average Pace",
                    value: formattedPace,
                    subtitle: "Per kilometer",
                    color: .green
                )
            }
            
            if workout.calories > 0 {
                DetailedMetricRow(
                    icon: "flame.fill",
                    title: "Calories Burned",
                    value: "\(Int(workout.calories)) cal",
                    subtitle: "Energy expenditure",
                    color: .orange
                )
            }
            
            if workout.elevation > 0 {
                DetailedMetricRow(
                    icon: "mountain.2.fill",
                    title: "Elevation Gain",
                    value: String(format: "%.0f m", workout.elevation),
                    subtitle: "Total ascent",
                    color: .brown
                )
            }
        }
    }
    
    private var physiologyMetricsView: some View {
        VStack(spacing: 12) {
            if workout.avgHeartRate > 0 {
                DetailedMetricRow(
                    icon: "heart.fill",
                    title: "Average Heart Rate",
                    value: "\(workout.avgHeartRate) bpm",
                    subtitle: heartRateZone,
                    color: .red
                )
            }
            
            if workout.maxHeartRate > 0 {
                DetailedMetricRow(
                    icon: "heart.circle.fill",
                    title: "Maximum Heart Rate",
                    value: "\(workout.maxHeartRate) bpm",
                    subtitle: "Peak intensity",
                    color: .red
                )
            }
            
            if workout.vo2Max > 0 {
                DetailedMetricRow(
                    icon: "lungs.fill",
                    title: "VO₂ Max",
                    value: String(format: "%.1f ml/kg/min", workout.vo2Max),
                    subtitle: vo2MaxStatus,
                    color: .mint
                )
            }
            
            if workout.hrv > 0 {
                DetailedMetricRow(
                    icon: "waveform.path.ecg",
                    title: "Heart Rate Variability",
                    value: String(format: "%.1f ms", workout.hrv),
                    subtitle: hrvStatus,
                    color: .teal
                )
            }
        }
    }
    
    private var advancedMetricsView: some View {
        VStack(spacing: 12) {
            if workout.cadence > 0 {
                DetailedMetricRow(
                    icon: "speedometer",
                    title: "Cadence",
                    value: String(format: "%.0f spm", workout.cadence),
                    subtitle: cadenceStatus,
                    color: .purple
                )
            }
            
            if workout.powerOutput > 0 {
                DetailedMetricRow(
                    icon: "bolt.fill",
                    title: "Power Output",
                    value: String(format: "%.0f W", workout.powerOutput),
                    subtitle: powerStatus,
                    color: .yellow
                )
            }
            
            if let route = workout.route, !route.isEmpty {
                DetailedMetricRow(
                    icon: "map.fill",
                    title: "Route Data",
                    value: "Available",
                    subtitle: "GPS coordinates recorded",
                    color: .indigo
                )
            }
        }
    }
    
    // MARK: - Heart Rate Analysis Card
    private var heartRateAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                
                Text("Heart Rate Analysis")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Average")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(workout.avgHeartRate) bpm")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .center, spacing: 4) {
                        Text("Maximum")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(workout.maxHeartRate) bpm")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Zone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(heartRateZone)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(heartRateZoneColor.opacity(0.15))
                            .foregroundColor(heartRateZoneColor)
                            .cornerRadius(6)
                    }
                }
                
                if workout.hrv > 0 {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption)
                            .foregroundColor(.teal)
                        
                        Text("HRV: \(String(format: "%.1f", workout.hrv)) ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(hrvStatus)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.teal)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Environmental Conditions Card
    private var environmentalConditionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cloud.sun.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                
                Text("Environmental Conditions")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                if let weather = workout.weatherCondition, !weather.isEmpty {
                    DetailedMetricRow(
                        icon: weatherIcon,
                        title: "Weather",
                        value: weather.capitalized,
                        subtitle: "Conditions during workout",
                        color: .blue
                    )
                }
                
                if workout.temperature > 0 {
                    DetailedMetricRow(
                        icon: "thermometer",
                        title: "Temperature",
                        value: String(format: "%.1f°C", workout.temperature),
                        subtitle: temperatureDescription,
                        color: temperatureColor
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Subjective Data Card
    private var subjectiveDataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundColor(.purple)
                
                Text("Subjective Feedback")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                if workout.perceivedExertion > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "gauge.medium")
                                .font(.subheadline)
                                .foregroundColor(.purple)
                            
                            Text("Perceived Exertion")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(workout.perceivedExertion)/10")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                        }
                        
                        HStack(spacing: 4) {
                            ForEach(1...10, id: \.self) { level in
                                Circle()
                                    .fill(level <= workout.perceivedExertion ? Color.purple : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                            
                            Spacer()
                            
                            Text(exertionDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let notes = workout.notes, !notes.isEmpty {
                    Button(action: { showingNotes = true }) {
                        HStack {
                            Image(systemName: "note.text")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Workout Notes")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text(notes.prefix(50) + (notes.count > 50 ? "..." : ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    HStack {
                        Image(systemName: "note.text")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text("No notes recorded")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Workout Insights Card
    private var workoutInsightsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundColor(.yellow)
                
                Text("Workout Insights")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                ForEach(workoutInsights, id: \.title) { insight in
                    InsightRow(
                        icon: insight.icon,
                        title: insight.title,
                        value: insight.value,
                        color: insight.color
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
    
    // MARK: - Computed Properties
    
    private var workoutIcon: String {
        switch workout.workoutType.lowercased() {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "swim": return "figure.pool.swim"
        case "strength": return "dumbbell.fill"
        case "hiit": return "timer"
        case "yoga": return "figure.flexibility"
        case "stretch": return "figure.flexibility"
        default: return "figure.mixed.cardio"
        }
    }
    
    private var workoutColor: Color {
        switch workout.workoutType.lowercased() {
        case "run": return .orange
        case "walk": return .green
        case "bike": return .blue
        case "swim": return .cyan
        case "strength": return .red
        case "hiit": return .purple
        case "yoga": return .mint
        case "stretch": return .indigo
        default: return .gray
        }
    }
    
    private var formattedDuration: String {
        let totalSeconds = Int(workout.duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private var formattedPace: String {
        guard workout.pace > 0 else { return "0:00" }
        let totalSeconds = Int(workout.pace)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var hasHeartRateData: Bool {
        workout.avgHeartRate > 0 || workout.maxHeartRate > 0 || workout.hrv > 0
    }
    
    private var hasEnvironmentalData: Bool {
        (workout.weatherCondition != nil && !workout.weatherCondition!.isEmpty) || workout.temperature > 0
    }
    
    private var hasAdvancedMetrics: Bool {
        workout.cadence > 0 || workout.powerOutput > 0 || (workout.route != nil && !workout.route!.isEmpty)
    }
    
    // Status descriptions
    private var vo2MaxStatus: String {
        switch workout.vo2Max {
        case 0...30: return "Below Average"
        case 30...40: return "Average"
        case 40...50: return "Good"
        case 50...60: return "Excellent"
        default: return "Superior"
        }
    }
    
    private var elevationStatus: String {
        switch workout.elevation {
        case 0...50: return "Flat"
        case 50...200: return "Moderate Hills"
        case 200...500: return "Hilly"
        default: return "Mountainous"
        }
    }
    
    private var cadenceStatus: String {
        switch workout.cadence {
        case 0...160: return "Below Optimal"
        case 160...180: return "Good"
        case 180...200: return "Excellent"
        default: return "High"
        }
    }
    
    private var powerStatus: String {
        switch workout.powerOutput {
        case 0...100: return "Light"
        case 100...200: return "Moderate"
        case 200...300: return "Hard"
        default: return "Very Hard"
        }
    }
    
    private var heartRateZone: String {
        switch workout.avgHeartRate {
        case 0...120: return "Zone 1 - Active Recovery"
        case 120...140: return "Zone 2 - Aerobic"
        case 140...160: return "Zone 3 - Threshold"
        case 160...180: return "Zone 4 - VO2 Max"
        default: return "Zone 5 - Neuromuscular"
        }
    }
    
    private var heartRateZoneColor: Color {
        switch workout.avgHeartRate {
        case 0...120: return .blue
        case 120...140: return .green
        case 140...160: return .yellow
        case 160...180: return .orange
        default: return .red
        }
    }
    
    private var hrvStatus: String {
        switch workout.hrv {
        case 0...20: return "Low"
        case 20...50: return "Average"
        case 50...100: return "Good"
        default: return "Excellent"
        }
    }
    
    private var weatherIcon: String {
        guard let weather = workout.weatherCondition?.lowercased() else { return "sun.max.fill" }
        
        switch weather {
        case let w where w.contains("rain"): return "cloud.rain.fill"
        case let w where w.contains("cloud"): return "cloud.fill"
        case let w where w.contains("sun"): return "sun.max.fill"
        case let w where w.contains("snow"): return "cloud.snow.fill"
        case let w where w.contains("wind"): return "wind"
        default: return "sun.max.fill"
        }
    }
    
    private var temperatureDescription: String {
        switch workout.temperature {
        case ..<5: return "Very Cold"
        case 5..<15: return "Cold"
        case 15..<25: return "Comfortable"
        case 25..<30: return "Warm"
        default: return "Hot"
        }
    }
    
    private var temperatureColor: Color {
        switch workout.temperature {
        case ..<5: return .blue
        case 5..<15: return .cyan
        case 15..<25: return .green
        case 25..<30: return .orange
        default: return .red
        }
    }
    
    private var exertionDescription: String {
        switch workout.perceivedExertion {
        case 1...2: return "Very Easy"
        case 3...4: return "Easy"
        case 5...6: return "Moderate"
        case 7...8: return "Hard"
        case 9...10: return "Very Hard"
        default: return "Unknown"
        }
    }
    
    private var workoutInsights: [WorkoutInsight] {
        var insights: [WorkoutInsight] = []
        
        // Intensity insight
        if workout.avgHeartRate > 0 {
            let intensity = workout.avgHeartRate > 160 ? "High Intensity" : workout.avgHeartRate > 140 ? "Moderate Intensity" : "Low Intensity"
            insights.append(WorkoutInsight(
                icon: "heart.fill",
                title: "Intensity Level",
                value: intensity,
                color: heartRateZoneColor
            ))
        }
        
        // Efficiency insight
        if workout.pace > 0 && workout.distance > 0 {
            let efficiency = workout.pace < 300 ? "Excellent Pace" : workout.pace < 360 ? "Good Pace" : "Steady Pace"
            insights.append(WorkoutInsight(
                icon: "speedometer",
                title: "Pace Efficiency",
                value: efficiency,
                color: .green
            ))
        }
        
        // Calorie burn insight
        if workout.calories > 0 && workout.duration > 0 {
            let caloriesPerMinute = workout.calories / (workout.duration / 60)
            let burnRate = caloriesPerMinute > 15 ? "High Burn Rate" : caloriesPerMinute > 10 ? "Moderate Burn Rate" : "Light Burn Rate"
            insights.append(WorkoutInsight(
                icon: "flame.fill",
                title: "Calorie Burn",
                value: burnRate,
                color: .orange
            ))
        }
        
        // Effort vs Performance
        if workout.perceivedExertion > 0 && workout.avgHeartRate > 0 {
            let effort = workout.perceivedExertion > 7 ? "High Effort" : workout.perceivedExertion > 5 ? "Moderate Effort" : "Easy Effort"
            insights.append(WorkoutInsight(
                icon: "gauge.medium",
                title: "Effort Level",
                value: effort,
                color: .purple
            ))
        }
        
        return insights
    }
}

// MARK: - Supporting Views

struct QuickStatView: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 1)
                }
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PerformanceMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Spacer()
                
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 1)
    }
    
    private var statusColor: Color {
        switch status {
        case let s where s.contains("Excellent") || s.contains("Superior") || s.contains("Good"): return .green
        case let s where s.contains("Average") || s.contains("Moderate"): return .blue
        case let s where s.contains("Below") || s.contains("Low"): return .orange
        default: return .red
        }
    }
}

struct DetailedMetricRow: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.vertical, 8)
    }
}



struct WorkoutNotesView: View {
    let workout: WorkoutLog
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(workout.notes ?? "No notes available")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .navigationTitle("Workout Notes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
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

// MARK: - Data Models

struct WorkoutInsight {
    let icon: String
    let title: String
    let value: String
    let color: Color
}
