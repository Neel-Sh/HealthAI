import Foundation
import CoreData
import Combine

// MARK: - Running Training Plan Types
enum RunningGoal: String, CaseIterable, Codable {
    case firstRun = "Complete First Run"
    case run5K = "Run 5K"
    case run10K = "Run 10K"
    case halfMarathon = "Half Marathon"
    case marathon = "Marathon"
    case improveSpeed = "Improve Speed"
    case buildEndurance = "Build Endurance"
    case stayActive = "Stay Active"
    
    var targetDistance: Double {
        switch self {
        case .firstRun: return 1.0
        case .run5K: return 5.0
        case .run10K: return 10.0
        case .halfMarathon: return 21.1
        case .marathon: return 42.2
        case .improveSpeed, .buildEndurance, .stayActive: return 0
        }
    }
    
    var icon: String {
        switch self {
        case .firstRun: return "figure.walk"
        case .run5K: return "figure.run"
        case .run10K: return "figure.run.circle"
        case .halfMarathon: return "medal"
        case .marathon: return "trophy"
        case .improveSpeed: return "bolt.fill"
        case .buildEndurance: return "heart.fill"
        case .stayActive: return "flame.fill"
        }
    }
    
    var description: String {
        switch self {
        case .firstRun: return "Start your running journey"
        case .run5K: return "Build up to running 5 kilometers"
        case .run10K: return "Train to run 10 kilometers"
        case .halfMarathon: return "Complete a half marathon (21.1 km)"
        case .marathon: return "Complete a full marathon (42.2 km)"
        case .improveSpeed: return "Get faster with interval training"
        case .buildEndurance: return "Run longer and stronger"
        case .stayActive: return "Maintain fitness with regular runs"
        }
    }
    
    var weeklyPlan: [PlannedRun] {
        switch self {
        case .firstRun:
            return [
                PlannedRun(day: "Monday", type: .easy, duration: 20, description: "Walk/run intervals"),
                PlannedRun(day: "Wednesday", type: .easy, duration: 25, description: "Easy jog"),
                PlannedRun(day: "Saturday", type: .long, duration: 30, description: "Long walk/run")
            ]
        case .run5K:
            return [
                PlannedRun(day: "Monday", type: .easy, duration: 25, description: "Easy run"),
                PlannedRun(day: "Wednesday", type: .intervals, duration: 30, description: "5x400m intervals"),
                PlannedRun(day: "Friday", type: .easy, duration: 20, description: "Recovery run"),
                PlannedRun(day: "Sunday", type: .long, duration: 40, description: "Long run")
            ]
        case .run10K:
            return [
                PlannedRun(day: "Monday", type: .easy, duration: 30, description: "Easy run"),
                PlannedRun(day: "Tuesday", type: .tempo, duration: 35, description: "Tempo run"),
                PlannedRun(day: "Thursday", type: .intervals, duration: 40, description: "800m repeats"),
                PlannedRun(day: "Saturday", type: .easy, duration: 25, description: "Recovery run"),
                PlannedRun(day: "Sunday", type: .long, duration: 50, description: "Long run")
            ]
        case .halfMarathon, .marathon:
            return [
                PlannedRun(day: "Monday", type: .easy, duration: 40, description: "Easy run"),
                PlannedRun(day: "Tuesday", type: .intervals, duration: 45, description: "Track workout"),
                PlannedRun(day: "Wednesday", type: .easy, duration: 35, description: "Recovery run"),
                PlannedRun(day: "Thursday", type: .tempo, duration: 50, description: "Tempo run"),
                PlannedRun(day: "Saturday", type: .easy, duration: 30, description: "Shakeout run"),
                PlannedRun(day: "Sunday", type: .long, duration: 90, description: "Long run")
            ]
        case .improveSpeed:
            return [
                PlannedRun(day: "Tuesday", type: .intervals, duration: 35, description: "200m sprints"),
                PlannedRun(day: "Thursday", type: .tempo, duration: 40, description: "Threshold run"),
                PlannedRun(day: "Saturday", type: .easy, duration: 30, description: "Easy run")
            ]
        case .buildEndurance:
            return [
                PlannedRun(day: "Monday", type: .easy, duration: 35, description: "Easy run"),
                PlannedRun(day: "Wednesday", type: .easy, duration: 40, description: "Aerobic run"),
                PlannedRun(day: "Friday", type: .easy, duration: 30, description: "Recovery run"),
                PlannedRun(day: "Sunday", type: .long, duration: 60, description: "Long run")
            ]
        case .stayActive:
            return [
                PlannedRun(day: "Tuesday", type: .easy, duration: 30, description: "Easy run"),
                PlannedRun(day: "Thursday", type: .easy, duration: 30, description: "Easy run"),
                PlannedRun(day: "Sunday", type: .long, duration: 45, description: "Weekend run")
            ]
        }
    }
}

enum RunType: String, CaseIterable, Codable {
    case easy = "Easy"
    case tempo = "Tempo"
    case intervals = "Intervals"
    case long = "Long Run"
    case recovery = "Recovery"
    case race = "Race"
    
    var color: String {
        switch self {
        case .easy: return "34D399"
        case .tempo: return "F59E0B"
        case .intervals: return "EF4444"
        case .long: return "3B82F6"
        case .recovery: return "8B5CF6"
        case .race: return "EC4899"
        }
    }
    
    var description: String {
        switch self {
        case .easy: return "Conversational pace, build aerobic base"
        case .tempo: return "Comfortably hard, lactate threshold"
        case .intervals: return "Fast repeats with recovery"
        case .long: return "Extended duration, build endurance"
        case .recovery: return "Very easy, active recovery"
        case .race: return "Race day effort"
        }
    }
}

struct PlannedRun: Identifiable, Codable {
    let id = UUID()
    let day: String
    let type: RunType
    let duration: Int // minutes
    let description: String
    var isCompleted: Bool = false
}

// MARK: - Running Service
class RunningService: ObservableObject {
    static let shared = RunningService()
    
    @Published var currentGoal: RunningGoal = .stayActive
    @Published var weeklyMileageGoal: Double = 20.0
    @Published var currentStreak: Int = 0
    @Published var personalRecords: [RunningPR] = []
    @Published var weeklyPlan: [PlannedRun] = []
    @Published var recentRuns: [RunSummary] = []
    @Published var thisWeekStats: WeeklyRunningStats?
    @Published var thisMonthStats: MonthlyRunningStats?
    
    private var viewContext: NSManagedObjectContext?
    
    private init() {
        loadSettings()
    }
    
    func configure(with context: NSManagedObjectContext) {
        self.viewContext = context
        refreshRunningData()
    }
    
    func refreshRunningData() {
        guard let context = viewContext else { return }
        
        // Fetch recent runs from Core Data
        let fetchRequest: NSFetchRequest<WorkoutLog> = WorkoutLog.fetchRequest()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        fetchRequest.predicate = NSPredicate(format: "workoutType CONTAINS[c] %@ AND timestamp >= %@", "run", thirtyDaysAgo as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)]
        
        do {
            let runs = try context.fetch(fetchRequest)
            
            DispatchQueue.main.async {
                self.recentRuns = runs.map { RunSummary(from: $0) }
                self.calculateWeeklyStats(from: runs)
                self.calculateMonthlyStats(from: runs)
                self.updateStreak(from: runs)
                self.checkForPRs(from: runs)
            }
        } catch {
            print("Error fetching runs: \(error)")
        }
    }
    
    private func calculateWeeklyStats(from runs: [WorkoutLog]) {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weeklyRuns = runs.filter { $0.timestamp >= weekAgo }
        
        thisWeekStats = WeeklyRunningStats(
            totalRuns: weeklyRuns.count,
            totalDistance: weeklyRuns.reduce(0) { $0 + $1.distance },
            totalDuration: weeklyRuns.reduce(0) { $0 + $1.duration },
            totalCalories: weeklyRuns.reduce(0) { $0 + $1.calories },
            averagePace: calculateAveragePace(from: weeklyRuns),
            longestRun: weeklyRuns.max(by: { $0.distance < $1.distance })?.distance ?? 0
        )
    }
    
    private func calculateMonthlyStats(from runs: [WorkoutLog]) {
        let calendar = Calendar.current
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let monthlyRuns = runs.filter { $0.timestamp >= monthAgo }
        
        thisMonthStats = MonthlyRunningStats(
            totalRuns: monthlyRuns.count,
            totalDistance: monthlyRuns.reduce(0) { $0 + $1.distance },
            totalDuration: monthlyRuns.reduce(0) { $0 + $1.duration },
            totalCalories: monthlyRuns.reduce(0) { $0 + $1.calories },
            averagePace: calculateAveragePace(from: monthlyRuns),
            longestRun: monthlyRuns.max(by: { $0.distance < $1.distance })?.distance ?? 0,
            fastestPace: monthlyRuns.filter { $0.pace > 0 }.min(by: { $0.pace < $1.pace })?.pace ?? 0
        )
    }
    
    private func calculateAveragePace(from runs: [WorkoutLog]) -> Double {
        let validRuns = runs.filter { $0.distance > 0 && $0.duration > 0 }
        guard !validRuns.isEmpty else { return 0 }
        
        let totalDistance = validRuns.reduce(0) { $0 + $1.distance }
        let totalDuration = validRuns.reduce(0) { $0 + $1.duration }
        
        return totalDistance > 0 ? totalDuration / totalDistance : 0
    }
    
    private func updateStreak(from runs: [WorkoutLog]) {
        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: Date())
        
        let calendar = Calendar.current
        while true {
            let hasRun = runs.contains { run in
                calendar.isDate(run.timestamp, inSameDayAs: checkDate)
            }
            
            if hasRun {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }
        
        currentStreak = streak
    }
    
    private func checkForPRs(from runs: [WorkoutLog]) {
        // Check for distance PRs - added 2K for beginners
        let distances: [Double] = [1.0, 2.0, 5.0, 10.0, 21.1, 42.2]
        var prs: [RunningPR] = []
        
        for targetDistance in distances {
            // Find runs within ±10% of target distance for accurate PRs
            let minDistance = targetDistance * 0.90
            let maxDistance = targetDistance * 1.10
            
            let qualifyingRuns = runs.filter { 
                $0.distance >= minDistance && $0.distance <= maxDistance 
            }
            
            if let fastest = qualifyingRuns.min(by: { $0.duration < $1.duration }) {
                prs.append(RunningPR(
                    distance: targetDistance,
                    time: fastest.duration,
                    date: fastest.timestamp,
                    pace: fastest.pace,
                    actualDistance: fastest.distance
                ))
            } else {
                // Check for longer runs and estimate split time
                let longerRuns = runs.filter { $0.distance >= targetDistance }
                if let bestRun = longerRuns.min(by: { $0.pace < $1.pace }) {
                    // Estimate time using Riegel's formula
                    let estimatedTime = bestRun.duration * pow(targetDistance / bestRun.distance, 1.06)
                    let estimatedPace = estimatedTime / targetDistance
                    
                    prs.append(RunningPR(
                        distance: targetDistance,
                        time: estimatedTime,
                        date: bestRun.timestamp,
                        pace: estimatedPace,
                        actualDistance: bestRun.distance,
                        isEstimated: true
                    ))
                }
            }
        }
        
        personalRecords = prs
    }
    
    func setGoal(_ goal: RunningGoal) {
        currentGoal = goal
        weeklyPlan = goal.weeklyPlan
        saveSettings()
    }
    
    func setWeeklyMileageGoal(_ miles: Double) {
        weeklyMileageGoal = miles
        saveSettings()
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(currentGoal.rawValue, forKey: "runningGoal")
        UserDefaults.standard.set(weeklyMileageGoal, forKey: "weeklyMileageGoal")
    }
    
    private func loadSettings() {
        if let goalString = UserDefaults.standard.string(forKey: "runningGoal"),
           let goal = RunningGoal(rawValue: goalString) {
            currentGoal = goal
            weeklyPlan = goal.weeklyPlan
        }
        weeklyMileageGoal = UserDefaults.standard.double(forKey: "weeklyMileageGoal")
        if weeklyMileageGoal == 0 {
            weeklyMileageGoal = 20.0
        }
    }
    
    // MARK: - Pace Helpers
    static func formatPace(_ paceInSecondsPerKm: Double) -> String {
        guard paceInSecondsPerKm > 0 else { return "--:--" }
        let minutes = Int(paceInSecondsPerKm) / 60
        let seconds = Int(paceInSecondsPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    static func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    static func formatDistance(_ km: Double) -> String {
        if km >= 1 {
            return String(format: "%.2f km", km)
        } else {
            return String(format: "%.0f m", km * 1000)
        }
    }
}

// MARK: - Supporting Types
struct RunSummary: Identifiable {
    let id: UUID
    let date: Date
    let distance: Double
    let duration: Double
    let pace: Double
    let calories: Double
    let avgHeartRate: Int16
    
    init(from workoutLog: WorkoutLog) {
        self.id = workoutLog.id ?? UUID()
        self.date = workoutLog.timestamp
        self.distance = workoutLog.distance
        self.duration = workoutLog.duration
        self.pace = workoutLog.pace
        self.calories = workoutLog.calories
        self.avgHeartRate = workoutLog.avgHeartRate
    }
    
    var formattedPace: String {
        RunningService.formatPace(pace)
    }
    
    var formattedDuration: String {
        RunningService.formatDuration(duration)
    }
    
    var formattedDistance: String {
        RunningService.formatDistance(distance)
    }
}

struct RunningPR: Identifiable {
    let id = UUID()
    let distance: Double
    let time: Double
    let date: Date
    let pace: Double
    var actualDistance: Double? = nil // The actual distance run
    var isEstimated: Bool = false // Whether time is estimated from a longer run
    
    var distanceLabel: String {
        let label: String
        switch distance {
        case 1.0: label = "1K"
        case 2.0: label = "2K"
        case 5.0: label = "5K"
        case 10.0: label = "10K"
        case 21.1: label = "Half Marathon"
        case 42.2: label = "Marathon"
        default: label = String(format: "%.1f km", distance)
        }
        return isEstimated ? "\(label)*" : label
    }
    
    var formattedTime: String {
        RunningService.formatDuration(time)
    }
    
    var formattedPace: String {
        RunningService.formatPace(pace)
    }
}

struct MonthlyRunningStats {
    let totalRuns: Int
    let totalDistance: Double
    let totalDuration: Double
    let totalCalories: Double
    let averagePace: Double
    let longestRun: Double
    let fastestPace: Double
    
    var formattedDistance: String {
        String(format: "%.1f km", totalDistance)
    }
    
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        return "\(hours)h \(minutes)m"
    }
    
    var formattedAvgPace: String {
        RunningService.formatPace(averagePace)
    }
}

