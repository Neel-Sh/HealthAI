import Foundation
import SwiftUI
import CoreLocation

// MARK: - Running Challenge System (Nike Run Club Style)

struct RunningChallenge: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let type: ChallengeType
    let icon: String
    let color: String
    let startDate: Date
    let endDate: Date
    let target: Double // km, runs, or minutes depending on type
    var progress: Double
    var isCompleted: Bool
    let reward: ChallengeReward?
    let participants: Int // For community challenges
    
    var progressPercentage: Double {
        min(progress / target * 100, 100)
    }
    
    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
    }
    
    var isActive: Bool {
        Date() >= startDate && Date() <= endDate
    }
    
    enum ChallengeType: String, Codable, CaseIterable {
        case distance = "Distance"
        case frequency = "Frequency"
        case duration = "Duration"
        case streak = "Streak"
        case elevation = "Elevation"
        case speed = "Speed"
        case community = "Community"
        
        var icon: String {
            switch self {
            case .distance: return "figure.run"
            case .frequency: return "calendar.badge.plus"
            case .duration: return "clock.fill"
            case .streak: return "flame.fill"
            case .elevation: return "mountain.2.fill"
            case .speed: return "bolt.fill"
            case .community: return "person.3.fill"
            }
        }
    }
    
    static var weeklyDistanceChallenge: RunningChallenge {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
        
        return RunningChallenge(
            id: UUID(),
            name: "Weekly 50K",
            description: "Run 50 kilometers this week",
            type: .distance,
            icon: "figure.run.circle.fill",
            color: "10B981",
            startDate: startOfWeek,
            endDate: endOfWeek,
            target: 50,
            progress: 0,
            isCompleted: false,
            reward: ChallengeReward(badge: "50k_warrior", points: 500),
            participants: 12458
        )
    }
}

struct ChallengeReward: Codable {
    let badge: String
    let points: Int
}

// MARK: - Running Streak

struct RunningStreak: Codable {
    var currentStreak: Int
    var longestStreak: Int
    var lastRunDate: Date?
    var weeklyStreak: Int // Weeks with at least 3 runs
    var monthlyStreak: Int // Consecutive months running
    var streakFreezeAvailable: Bool
    var streakFreezeUsedDate: Date?
    
    var isStreakAtRisk: Bool {
        guard let lastRun = lastRunDate else { return false }
        let hoursSinceLastRun = Date().timeIntervalSince(lastRun) / 3600
        return hoursSinceLastRun > 24 && hoursSinceLastRun < 48
    }
    
    var streakStatus: StreakStatus {
        guard let lastRun = lastRunDate else { return .inactive }
        let hoursSinceLastRun = Date().timeIntervalSince(lastRun) / 3600
        
        if hoursSinceLastRun < 24 { return .active }
        if hoursSinceLastRun < 48 { return .atRisk }
        return .broken
    }
    
    enum StreakStatus {
        case active, atRisk, broken, inactive
        
        var color: String {
            switch self {
            case .active: return "10B981"
            case .atRisk: return "F59E0B"
            case .broken, .inactive: return "EF4444"
            }
        }
        
        var icon: String {
            switch self {
            case .active: return "flame.fill"
            case .atRisk: return "exclamationmark.triangle.fill"
            case .broken: return "flame"
            case .inactive: return "flame"
            }
        }
    }
}

// MARK: - Segment Efforts (Strava Style)

struct RunningSegment: Identifiable, Codable {
    let id: UUID
    let name: String
    let distance: Double // km
    let startLocation: CLLocationCoordinate2D
    let endLocation: CLLocationCoordinate2D
    let elevationGain: Double
    let routePoints: [CLLocationCoordinate2D]
    let createdDate: Date
    let category: SegmentCategory
    var personalBest: SegmentEffort?
    var allEfforts: [SegmentEffort]
    var leaderboard: [LeaderboardEntry]
    
    enum SegmentCategory: String, Codable, CaseIterable {
        case flat = "Flat"
        case uphill = "Uphill"
        case downhill = "Downhill"
        case mixed = "Mixed"
        case sprint = "Sprint"
        
        var icon: String {
            switch self {
            case .flat: return "arrow.right"
            case .uphill: return "arrow.up.right"
            case .downhill: return "arrow.down.right"
            case .mixed: return "chart.line.uptrend.xyaxis"
            case .sprint: return "bolt.fill"
            }
        }
    }
}

struct SegmentEffort: Identifiable, Codable {
    let id: UUID
    let segmentId: UUID
    let date: Date
    let elapsedTime: TimeInterval // seconds
    let movingTime: TimeInterval
    let averagePace: Double // sec/km
    let averageHeartRate: Int
    let maxHeartRate: Int
    let averageCadence: Int?
    let weather: WeatherCondition?
    var rank: Int? // Position on leaderboard
    var isPersonalBest: Bool
    var prGap: TimeInterval? // How much faster/slower than PR
    
    var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedPace: String {
        let minutes = Int(averagePace) / 60
        let seconds = Int(averagePace) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}

struct LeaderboardEntry: Identifiable, Codable {
    let id: UUID
    let rank: Int
    let userName: String
    let time: TimeInterval
    let date: Date
    let isCurrentUser: Bool
}

// MARK: - Shoe Tracking

struct RunningShoe: Identifiable, Codable {
    let id: UUID
    var name: String
    var brand: String
    var model: String
    var purchaseDate: Date
    var initialMileage: Double // km added before tracking started
    var totalMileage: Double // km
    var targetMileage: Double // recommended replacement mileage
    var color: String
    var isDefault: Bool
    var isRetired: Bool
    var notes: String
    var imageData: Data?
    var runs: [UUID] // RunLog IDs
    
    var remainingMileage: Double {
        max(0, targetMileage - totalMileage)
    }
    
    var wearPercentage: Double {
        min(totalMileage / targetMileage * 100, 100)
    }
    
    var wearStatus: ShoeWearStatus {
        switch wearPercentage {
        case ..<50: return .fresh
        case 50..<75: return .good
        case 75..<90: return .worn
        default: return .replace
        }
    }
    
    enum ShoeWearStatus: String {
        case fresh = "Fresh"
        case good = "Good"
        case worn = "Worn"
        case replace = "Replace Soon"
        
        var color: String {
            switch self {
            case .fresh: return "10B981"
            case .good: return "3B82F6"
            case .worn: return "F59E0B"
            case .replace: return "EF4444"
            }
        }
        
        var icon: String {
            switch self {
            case .fresh: return "sparkles"
            case .good: return "checkmark.circle.fill"
            case .worn: return "exclamationmark.circle.fill"
            case .replace: return "xmark.circle.fill"
            }
        }
    }
    
    static var example: RunningShoe {
        RunningShoe(
            id: UUID(),
            name: "Daily Trainer",
            brand: "Nike",
            model: "Pegasus 40",
            purchaseDate: Date().addingTimeInterval(-90 * 24 * 3600),
            initialMileage: 0,
            totalMileage: 320,
            targetMileage: 800,
            color: "3B82F6",
            isDefault: true,
            isRetired: false,
            notes: "Great cushioning for easy runs",
            imageData: nil,
            runs: []
        )
    }
}

// MARK: - Recovery Advisor

struct RecoveryAdvice: Identifiable {
    let id = UUID()
    let status: RecoveryStatus
    let readinessScore: Double // 0-100
    let hrv: Double?
    let restingHR: Int?
    let sleepQuality: Double? // 0-100
    let fatigueLevel: FatigueLevel
    let recommendation: String
    let suggestedWorkout: SuggestedWorkout?
    let recoveryTips: [RecoveryTip]
    let estimatedFullRecovery: Date
    
    enum RecoveryStatus: String {
        case fullyRecovered = "Fully Recovered"
        case recovered = "Recovered"
        case recovering = "Recovering"
        case fatigued = "Fatigued"
        case overreached = "Overreached"
        
        var color: String {
            switch self {
            case .fullyRecovered: return "10B981"
            case .recovered: return "34D399"
            case .recovering: return "FBBF24"
            case .fatigued: return "F97316"
            case .overreached: return "EF4444"
            }
        }
        
        var icon: String {
            switch self {
            case .fullyRecovered: return "battery.100.bolt"
            case .recovered: return "battery.75"
            case .recovering: return "battery.50"
            case .fatigued: return "battery.25"
            case .overreached: return "battery.0"
            }
        }
    }
    
    enum FatigueLevel: String {
        case none = "None"
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
        case severe = "Severe"
    }
    
    struct SuggestedWorkout {
        let type: String
        let duration: Int // minutes
        let intensity: String
        let description: String
    }
    
    struct RecoveryTip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let description: String
        let priority: Priority
        
        enum Priority: Int {
            case high = 1, medium = 2, low = 3
        }
    }
}

// MARK: - Run Trends

struct RunTrend: Identifiable {
    let id = UUID()
    let metric: TrendMetric
    let timeframe: TrendTimeframe
    let dataPoints: [TrendDataPoint]
    let currentValue: Double
    let previousValue: Double
    let averageValue: Double
    let trend: TrendDirection
    let percentageChange: Double
    
    enum TrendMetric: String, CaseIterable {
        case distance = "Distance"
        case pace = "Pace"
        case duration = "Duration"
        case heartRate = "Heart Rate"
        case cadence = "Cadence"
        case elevation = "Elevation"
        case trainingLoad = "Training Load"
        case vo2Max = "VO₂ Max"
        
        var icon: String {
            switch self {
            case .distance: return "arrow.left.and.right"
            case .pace: return "speedometer"
            case .duration: return "clock.fill"
            case .heartRate: return "heart.fill"
            case .cadence: return "metronome"
            case .elevation: return "mountain.2.fill"
            case .trainingLoad: return "chart.bar.fill"
            case .vo2Max: return "lungs.fill"
            }
        }
        
        var unit: String {
            switch self {
            case .distance: return "km"
            case .pace: return "/km"
            case .duration: return "min"
            case .heartRate: return "bpm"
            case .cadence: return "spm"
            case .elevation: return "m"
            case .trainingLoad: return "TSS"
            case .vo2Max: return "ml/kg/min"
            }
        }
    }
    
    enum TrendTimeframe: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case quarter = "3 Months"
        case year = "Year"
        case allTime = "All Time"
    }
    
    enum TrendDirection {
        case improving, declining, stable
        
        var color: String {
            switch self {
            case .improving: return "10B981"
            case .declining: return "EF4444"
            case .stable: return "6B7280"
            }
        }
        
        var icon: String {
            switch self {
            case .improving: return "arrow.up.right"
            case .declining: return "arrow.down.right"
            case .stable: return "arrow.right"
            }
        }
    }
}

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String?
}

// MARK: - Achievements System

struct RunningAchievement: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let icon: String
    let color: String
    let category: AchievementCategory
    let tier: AchievementTier
    let requirement: AchievementRequirement
    var isUnlocked: Bool
    var unlockedDate: Date?
    var progress: Double // 0-1
    let points: Int
    
    enum AchievementCategory: String, Codable, CaseIterable {
        case distance = "Distance"
        case speed = "Speed"
        case consistency = "Consistency"
        case milestones = "Milestones"
        case challenges = "Challenges"
        case social = "Social"
        case special = "Special"
        
        var icon: String {
            switch self {
            case .distance: return "figure.run"
            case .speed: return "bolt.fill"
            case .consistency: return "calendar.badge.plus"
            case .milestones: return "flag.fill"
            case .challenges: return "trophy.fill"
            case .social: return "person.2.fill"
            case .special: return "star.fill"
            }
        }
    }
    
    enum AchievementTier: String, Codable {
        case bronze = "Bronze"
        case silver = "Silver"
        case gold = "Gold"
        case platinum = "Platinum"
        case diamond = "Diamond"
        
        var color: String {
            switch self {
            case .bronze: return "CD7F32"
            case .silver: return "C0C0C0"
            case .gold: return "FFD700"
            case .platinum: return "E5E4E2"
            case .diamond: return "B9F2FF"
            }
        }
    }
    
    struct AchievementRequirement: Codable {
        let type: RequirementType
        let value: Double
        let currentValue: Double
        
        enum RequirementType: String, Codable {
            case totalDistance = "Total Distance"
            case singleRunDistance = "Single Run Distance"
            case totalRuns = "Total Runs"
            case consecutiveDays = "Consecutive Days"
            case paceBelowThreshold = "Pace Below"
            case monthlyDistance = "Monthly Distance"
            case weeklyRuns = "Weekly Runs"
            case challengesCompleted = "Challenges Completed"
        }
    }
    
    static var firstRunAchievement: RunningAchievement {
        RunningAchievement(
            id: UUID(),
            name: "First Steps",
            description: "Complete your first run",
            icon: "figure.walk",
            color: "10B981",
            category: .milestones,
            tier: .bronze,
            requirement: AchievementRequirement(type: .totalRuns, value: 1, currentValue: 0),
            isUnlocked: false,
            unlockedDate: nil,
            progress: 0,
            points: 100
        )
    }
}

// MARK: - Weather Integration

struct WeatherCondition: Codable, Identifiable {
    let id: UUID
    let temperature: Double // Celsius
    let feelsLike: Double
    let humidity: Double // 0-100
    let windSpeed: Double // km/h
    let windDirection: String
    let condition: WeatherType
    let uvIndex: Int
    let airQuality: AirQuality?
    let sunrise: Date?
    let sunset: Date?
    
    enum WeatherType: String, Codable {
        case sunny = "Sunny"
        case cloudy = "Cloudy"
        case partlyCloudy = "Partly Cloudy"
        case rainy = "Rainy"
        case snowy = "Snowy"
        case windy = "Windy"
        case stormy = "Stormy"
        case foggy = "Foggy"
        case hot = "Hot"
        case cold = "Cold"
        
        var icon: String {
            switch self {
            case .sunny: return "sun.max.fill"
            case .cloudy: return "cloud.fill"
            case .partlyCloudy: return "cloud.sun.fill"
            case .rainy: return "cloud.rain.fill"
            case .snowy: return "snow"
            case .windy: return "wind"
            case .stormy: return "cloud.bolt.fill"
            case .foggy: return "cloud.fog.fill"
            case .hot: return "thermometer.sun.fill"
            case .cold: return "thermometer.snowflake"
            }
        }
        
        var color: String {
            switch self {
            case .sunny, .hot: return "F59E0B"
            case .cloudy, .partlyCloudy, .foggy: return "9CA3AF"
            case .rainy, .stormy: return "3B82F6"
            case .snowy, .cold: return "93C5FD"
            case .windy: return "6EE7B7"
            }
        }
    }
    
    struct AirQuality: Codable {
        let index: Int
        let level: AirQualityLevel
        
        enum AirQualityLevel: String, Codable {
            case good = "Good"
            case moderate = "Moderate"
            case unhealthySensitive = "Unhealthy for Sensitive"
            case unhealthy = "Unhealthy"
            case veryUnhealthy = "Very Unhealthy"
            case hazardous = "Hazardous"
            
            var color: String {
                switch self {
                case .good: return "10B981"
                case .moderate: return "FBBF24"
                case .unhealthySensitive: return "F97316"
                case .unhealthy: return "EF4444"
                case .veryUnhealthy: return "7C3AED"
                case .hazardous: return "831843"
                }
            }
        }
    }
    
    var runningCondition: RunningConditionRating {
        var score = 100.0
        
        // Temperature impact
        if temperature < 0 || temperature > 35 {
            score -= 30
        } else if temperature < 5 || temperature > 30 {
            score -= 15
        } else if temperature >= 10 && temperature <= 20 {
            score += 10 // Optimal
        }
        
        // Humidity impact
        if humidity > 85 {
            score -= 20
        } else if humidity > 70 {
            score -= 10
        }
        
        // Wind impact
        if windSpeed > 30 {
            score -= 20
        } else if windSpeed > 20 {
            score -= 10
        }
        
        // Condition impact
        switch condition {
        case .rainy, .snowy, .stormy:
            score -= 25
        case .windy:
            score -= 10
        case .sunny:
            if temperature > 25 { score -= 10 }
        default:
            break
        }
        
        return RunningConditionRating(score: min(100, max(0, score)))
    }
    
    struct RunningConditionRating {
        let score: Double
        
        var level: String {
            switch score {
            case 80...100: return "Excellent"
            case 60..<80: return "Good"
            case 40..<60: return "Fair"
            case 20..<40: return "Poor"
            default: return "Not Recommended"
            }
        }
        
        var color: String {
            switch score {
            case 80...100: return "10B981"
            case 60..<80: return "34D399"
            case 40..<60: return "FBBF24"
            case 20..<40: return "F97316"
            default: return "EF4444"
            }
        }
    }
}

// MARK: - Route Heatmap

struct RouteHeatmapData {
    let coordinates: [HeatmapPoint]
    let bounds: MapBounds
    let totalRuns: Int
    let mostFrequentRoute: [CLLocationCoordinate2D]?
    
    struct HeatmapPoint: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let intensity: Double // 0-1, based on frequency
        let runCount: Int
    }
    
    struct MapBounds {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double
        
        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
        }
    }
}

// MARK: - Matched Runs Comparison

struct MatchedRunComparison: Identifiable {
    let id = UUID()
    let baseRun: AdvancedRunData
    let comparisonRuns: [AdvancedRunData]
    let routeSimilarity: Double // 0-100
    let distanceDifference: Double // km
    let timeDifference: TimeInterval // seconds
    let paceDifference: Double // seconds per km
    let improvements: [ImprovementMetric]
    
    struct ImprovementMetric: Identifiable {
        let id = UUID()
        let metric: String
        let improvement: Double
        let unit: String
        let isPositive: Bool
    }
    
    var bestMatchedRun: AdvancedRunData? {
        comparisonRuns.max(by: { $0.pace > $1.pace })
    }
    
    var averageImprovement: Double {
        guard !comparisonRuns.isEmpty else { return 0 }
        let avgPreviousPace = comparisonRuns.reduce(0) { $0 + $1.pace } / Double(comparisonRuns.count)
        return avgPreviousPace - baseRun.pace
    }
}

// MARK: - CLLocationCoordinate2D Codable Extension

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

// MARK: - Default Achievements

extension RunningAchievement {
    static var defaultAchievements: [RunningAchievement] {
        [
            // Distance Achievements
            RunningAchievement(id: UUID(), name: "First Steps", description: "Complete your first run", icon: "figure.walk", color: "10B981", category: .milestones, tier: .bronze, requirement: AchievementRequirement(type: .totalRuns, value: 1, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 100),
            
            RunningAchievement(id: UUID(), name: "Getting Started", description: "Run a total of 10 km", icon: "figure.run", color: "10B981", category: .distance, tier: .bronze, requirement: AchievementRequirement(type: .totalDistance, value: 10, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 150),
            
            RunningAchievement(id: UUID(), name: "Half Centurion", description: "Run a total of 50 km", icon: "50.circle.fill", color: "3B82F6", category: .distance, tier: .silver, requirement: AchievementRequirement(type: .totalDistance, value: 50, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 300),
            
            RunningAchievement(id: UUID(), name: "Centurion", description: "Run a total of 100 km", icon: "100.circle.fill", color: "8B5CF6", category: .distance, tier: .gold, requirement: AchievementRequirement(type: .totalDistance, value: 100, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 500),
            
            RunningAchievement(id: UUID(), name: "Marathon Legend", description: "Run a total of 500 km", icon: "star.circle.fill", color: "F59E0B", category: .distance, tier: .platinum, requirement: AchievementRequirement(type: .totalDistance, value: 500, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 1000),
            
            RunningAchievement(id: UUID(), name: "Ultra Runner", description: "Run a total of 1000 km", icon: "crown.fill", color: "EC4899", category: .distance, tier: .diamond, requirement: AchievementRequirement(type: .totalDistance, value: 1000, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 2000),
            
            // Single Run Achievements
            RunningAchievement(id: UUID(), name: "5K Finisher", description: "Complete a 5K run", icon: "5.circle.fill", color: "10B981", category: .milestones, tier: .bronze, requirement: AchievementRequirement(type: .singleRunDistance, value: 5, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 200),
            
            RunningAchievement(id: UUID(), name: "10K Warrior", description: "Complete a 10K run", icon: "10.circle.fill", color: "3B82F6", category: .milestones, tier: .silver, requirement: AchievementRequirement(type: .singleRunDistance, value: 10, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 400),
            
            RunningAchievement(id: UUID(), name: "Half Marathoner", description: "Complete a half marathon", icon: "medal.fill", color: "F59E0B", category: .milestones, tier: .gold, requirement: AchievementRequirement(type: .singleRunDistance, value: 21.0975, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 750),
            
            RunningAchievement(id: UUID(), name: "Marathoner", description: "Complete a full marathon", icon: "trophy.fill", color: "EC4899", category: .milestones, tier: .platinum, requirement: AchievementRequirement(type: .singleRunDistance, value: 42.195, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 1500),
            
            // Consistency Achievements
            RunningAchievement(id: UUID(), name: "Week Warrior", description: "Run 7 days in a row", icon: "flame.fill", color: "F59E0B", category: .consistency, tier: .silver, requirement: AchievementRequirement(type: .consecutiveDays, value: 7, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 350),
            
            RunningAchievement(id: UUID(), name: "Streak Master", description: "Run 30 days in a row", icon: "flame.circle.fill", color: "EF4444", category: .consistency, tier: .gold, requirement: AchievementRequirement(type: .consecutiveDays, value: 30, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 800),
            
            RunningAchievement(id: UUID(), name: "Iron Runner", description: "Run 100 days in a row", icon: "star.fill", color: "8B5CF6", category: .consistency, tier: .diamond, requirement: AchievementRequirement(type: .consecutiveDays, value: 100, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 2500),
            
            // Speed Achievements
            RunningAchievement(id: UUID(), name: "Speed Demon", description: "Run faster than 5:00/km pace", icon: "bolt.fill", color: "F59E0B", category: .speed, tier: .silver, requirement: AchievementRequirement(type: .paceBelowThreshold, value: 300, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 400),
            
            RunningAchievement(id: UUID(), name: "Lightning Legs", description: "Run faster than 4:30/km pace", icon: "bolt.circle.fill", color: "EF4444", category: .speed, tier: .gold, requirement: AchievementRequirement(type: .paceBelowThreshold, value: 270, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 600),
            
            RunningAchievement(id: UUID(), name: "Rocket Runner", description: "Run faster than 4:00/km pace", icon: "bolt.horizontal.fill", color: "EC4899", category: .speed, tier: .platinum, requirement: AchievementRequirement(type: .paceBelowThreshold, value: 240, currentValue: 0), isUnlocked: false, unlockedDate: nil, progress: 0, points: 1000)
        ]
    }
}

// MARK: - Default Challenges

extension RunningChallenge {
    static var defaultChallenges: [RunningChallenge] {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!.addingTimeInterval(-1)
        
        return [
            // Weekly Challenges
            RunningChallenge(id: UUID(), name: "Weekly 25K", description: "Run 25 kilometers this week", type: .distance, icon: "figure.run.circle.fill", color: "10B981", startDate: startOfWeek, endDate: endOfWeek, target: 25, progress: 0, isCompleted: false, reward: ChallengeReward(badge: "25k_week", points: 250), participants: 24892),
            
            RunningChallenge(id: UUID(), name: "4x This Week", description: "Complete 4 runs this week", type: .frequency, icon: "calendar.badge.plus", color: "3B82F6", startDate: startOfWeek, endDate: endOfWeek, target: 4, progress: 0, isCompleted: false, reward: ChallengeReward(badge: "4x_week", points: 200), participants: 18234),
            
            RunningChallenge(id: UUID(), name: "7-Day Streak", description: "Run every day this week", type: .streak, icon: "flame.fill", color: "F59E0B", startDate: startOfWeek, endDate: endOfWeek, target: 7, progress: 0, isCompleted: false, reward: ChallengeReward(badge: "7day_streak", points: 500), participants: 8921),
            
            // Monthly Challenges
            RunningChallenge(id: UUID(), name: "Monthly 100K", description: "Run 100 kilometers this month", type: .distance, icon: "100.circle.fill", color: "8B5CF6", startDate: startOfMonth, endDate: endOfMonth, target: 100, progress: 0, isCompleted: false, reward: ChallengeReward(badge: "100k_month", points: 750), participants: 45678),
            
            RunningChallenge(id: UUID(), name: "Elevation Hunter", description: "Gain 2000m elevation this month", type: .elevation, icon: "mountain.2.fill", color: "EC4899", startDate: startOfMonth, endDate: endOfMonth, target: 2000, progress: 0, isCompleted: false, reward: ChallengeReward(badge: "elevation_hunter", points: 600), participants: 12345)
        ]
    }
}

