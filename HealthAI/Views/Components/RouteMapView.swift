import SwiftUI
import MapKit

struct RouteMapView: View {
    let points: [RoutePoint]
    let strokeColor: Color
    
    @State private var position: MapCameraPosition
    
    init(points: [RoutePoint], strokeColor: Color = Color(hex: "10B981")) {
        self.points = points
        self.strokeColor = strokeColor
        
        let region = RouteMapView.region(for: points) ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        _position = State(initialValue: .region(region))
    }
    
    var body: some View {
        Map(position: $position) {
            if !points.isEmpty {
                MapPolyline(coordinates: points.map(\.coordinate))
                    .stroke(strokeColor, lineWidth: 4)
                
                if let start = points.first?.coordinate {
                    Annotation("Start", coordinate: start) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
                
                if let end = points.last?.coordinate {
                    Annotation("Finish", coordinate: end) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }
    
    private static func region(for points: [RoutePoint]) -> MKCoordinateRegion? {
        guard points.count >= 2 else { return nil }
        
        let lats = points.map { $0.latitude }
        let lons = points.map { $0.longitude }
        
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max() else { return nil }
        
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.002, (maxLat - minLat) * 1.35),
            longitudeDelta: max(0.002, (maxLon - minLon) * 1.35)
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
}


