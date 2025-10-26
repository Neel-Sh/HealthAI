import Foundation
import CoreData

// Note: This is a specialized extension of WorkoutLog for running-specific data
// RunLog extends WorkoutLog with running-specific computed properties and methods

extension WorkoutLog {
    // Running-specific computed properties
    var isRunning: Bool {
        return workoutType.lowercased().contains("run")
    }
    
    var pacePerKm: String {
        guard distance > 0 && duration > 0 else { return "N/A" }
        let paceInSeconds = duration / distance
        let minutes = Int(paceInSeconds) / 60
        let seconds = Int(paceInSeconds) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
    
    var pacePerMile: String {
        guard distance > 0 && duration > 0 else { return "N/A" }
        let distanceInMiles = distance * 0.621371
        let paceInSeconds = duration / distanceInMiles
        let minutes = Int(paceInSeconds) / 60
        let seconds = Int(paceInSeconds) % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
    
    var speedKmh: Double {
        guard duration > 0 else { return 0.0 }
        return (distance / (duration / 3600))
    }
    
    var speedMph: Double {
        return speedKmh * 0.621371
    }
    
    var runningEffort: String {
        switch perceivedExertion {
        case 1...2: return "Very Easy"
        case 3...4: return "Easy"
        case 5...6: return "Moderate"
        case 7...8: return "Hard"
        case 9...10: return "Very Hard"
        default: return "Unknown"
        }
    }
    
    var heartRateZone: String {
        guard avgHeartRate > 0 else { return "Unknown" }
        
        // Rough heart rate zones (would be better with user's max HR)
        switch avgHeartRate {
        case 0...100: return "Recovery"
        case 101...120: return "Aerobic Base"
        case 121...140: return "Aerobic"
        case 141...160: return "Lactate Threshold"
        case 161...180: return "VO2 Max"
        default: return "Neuromuscular"
        }
    }
    
    var caloriesPerKm: Double {
        guard distance > 0 else { return 0.0 }
        return calories / distance
    }
    
    var runningGrade: String {
        let paceScore = calculatePaceScore()
        let distanceScore = calculateDistanceScore()
        let effortScore = Double(perceivedExertion) / 10.0
        
        let overallScore = (paceScore + distanceScore + effortScore) / 3.0
        
        switch overallScore {
        case 0.8...1.0: return "A+"
        case 0.7...0.79: return "A"
        case 0.6...0.69: return "B+"
        case 0.5...0.59: return "B"
        case 0.4...0.49: return "C+"
        case 0.3...0.39: return "C"
        default: return "D"
        }
    }
    
    private func calculatePaceScore() -> Double {
        guard distance > 0 && duration > 0 else { return 0.0 }
        let paceInSeconds = duration / distance
        
        // Scoring based on typical running paces (arbitrary but reasonable)
        switch paceInSeconds {
        case 0...240: return 1.0 // Sub-4 minute/km (very fast)
        case 241...300: return 0.9 // 4-5 minute/km (fast)
        case 301...360: return 0.8 // 5-6 minute/km (good)
        case 361...420: return 0.7 // 6-7 minute/km (moderate)
        case 421...480: return 0.6 // 7-8 minute/km (easy)
        default: return 0.5 // 8+ minute/km (very easy)
        }
    }
    
    private func calculateDistanceScore() -> Double {
        switch distance {
        case 10...: return 1.0 // 10km+
        case 7...9.99: return 0.9 // 7-10km
        case 5...6.99: return 0.8 // 5-7km
        case 3...4.99: return 0.7 // 3-5km
        case 1...2.99: return 0.6 // 1-3km
        default: return 0.5 // Under 1km
        }
    }
}

// MARK: - Running Statistics Helper
struct RunningStats {
    static func calculateWeeklyStats(from workouts: [WorkoutLog]) -> WeeklyRunningStats {
        let runningWorkouts = workouts.filter { $0.isRunning }
        let totalDistance = runningWorkouts.reduce(0) { $0 + $1.distance }
        let totalDuration = runningWorkouts.reduce(0) { $0 + $1.duration }
        let totalCalories = runningWorkouts.reduce(0) { $0 + $1.calories }
        let averagePace = totalDistance > 0 ? totalDuration / totalDistance : 0
        
        return WeeklyRunningStats(
            totalRuns: runningWorkouts.count,
            totalDistance: totalDistance,
            totalDuration: totalDuration,
            totalCalories: totalCalories,
            averagePace: averagePace,
            longestRun: runningWorkouts.max(by: { $0.distance < $1.distance })?.distance ?? 0
        )
    }
}

struct WeeklyRunningStats {
    let totalRuns: Int
    let totalDistance: Double
    let totalDuration: Double
    let totalCalories: Double
    let averagePace: Double
    let longestRun: Double
    
    var averagePaceFormatted: String {
        guard averagePace > 0 else { return "N/A" }
        let minutes = Int(averagePace) / 60
        let seconds = Int(averagePace) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
    
    var formattedTotalDistance: String {
        return String(format: "%.1f km", totalDistance)
    }
    
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}
