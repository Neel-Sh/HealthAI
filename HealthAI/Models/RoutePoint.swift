import Foundation
import CoreLocation

/// Codable representation of a workout route point from HealthKit.
/// Stored in Core Data (`WorkoutLog.route`) as encoded `Data`.
struct RoutePoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let timestamp: Date?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum RouteCoding {
    static func encode(_ points: [RoutePoint]) -> Data? {
        guard !points.isEmpty else { return nil }
        return try? JSONEncoder().encode(points)
    }
    
    static func decode(_ data: Data?) -> [RoutePoint] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([RoutePoint].self, from: data)) ?? []
    }
}


