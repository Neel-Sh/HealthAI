import SwiftUI
import MapKit
import CoreLocation

// MARK: - Route Heatmap View
struct RouteHeatmapView: View {
    let heatmapData: RouteHeatmapData
    @State private var region: MKCoordinateRegion
    @Environment(\.colorScheme) private var colorScheme
    
    init(heatmapData: RouteHeatmapData) {
        self.heatmapData = heatmapData
        
        let center = heatmapData.bounds.center
        let latSpan = (heatmapData.bounds.maxLat - heatmapData.bounds.minLat) * 1.2
        let lonSpan = (heatmapData.bounds.maxLon - heatmapData.bounds.minLon) * 1.2
        
        _region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: max(latSpan, 0.01), longitudeDelta: max(lonSpan, 0.01))
        ))
    }
    
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: heatmapData.coordinates) { point in
                MapAnnotation(coordinate: point.coordinate) {
                    Circle()
                        .fill(heatmapColor(for: point.intensity))
                        .frame(width: 8 + (point.intensity * 12), height: 8 + (point.intensity * 12))
                        .opacity(0.4 + point.intensity * 0.4)
                        .blur(radius: 2)
                }
            }
            .mapStyle(colorScheme == .dark ? .standard(elevation: .flat) : .standard)
            
            // Overlay with legend
            VStack {
                Spacer()
                
                HStack {
                    // Legend
                    HStack(spacing: 8) {
                        ForEach(0..<5) { i in
                            Circle()
                                .fill(heatmapColor(for: Double(i) / 4.0))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Stats
                    Text("\(heatmapData.totalRuns) runs")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private func heatmapColor(for intensity: Double) -> Color {
        let colors: [Color] = [
            Color(hex: "3B82F6"), // Blue - low
            Color(hex: "10B981"), // Green
            Color(hex: "FBBF24"), // Yellow
            Color(hex: "F97316"), // Orange
            Color(hex: "EF4444")  // Red - high
        ]
        
        let index = min(Int(intensity * 4), 4)
        return colors[index]
    }
}

// MARK: - Running Segment Map View
struct SegmentMapView: View {
    let segment: RunningSegment
    @State private var region: MKCoordinateRegion
    @Environment(\.colorScheme) private var colorScheme
    
    private let accentColor = Color(hex: "10B981")
    
    init(segment: RunningSegment) {
        self.segment = segment
        
        let midLat = (segment.startLocation.latitude + segment.endLocation.latitude) / 2
        let midLon = (segment.startLocation.longitude + segment.endLocation.longitude) / 2
        let latSpan = abs(segment.startLocation.latitude - segment.endLocation.latitude) * 1.5
        let lonSpan = abs(segment.startLocation.longitude - segment.endLocation.longitude) * 1.5
        
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            span: MKCoordinateSpan(latitudeDelta: max(latSpan, 0.005), longitudeDelta: max(lonSpan, 0.005))
        ))
    }
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: [
            SegmentMarker(id: "start", coordinate: segment.startLocation, type: .start),
            SegmentMarker(id: "end", coordinate: segment.endLocation, type: .end)
        ]) { marker in
            MapAnnotation(coordinate: marker.coordinate) {
                ZStack {
                    Circle()
                        .fill(marker.type == .start ? Color(hex: "10B981") : Color(hex: "EF4444"))
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: marker.type == .start ? "flag.fill" : "flag.checkered")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .mapStyle(colorScheme == .dark ? .standard(elevation: .flat) : .standard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SegmentMarker: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let type: MarkerType
    
    enum MarkerType {
        case start, end
    }
}

// MARK: - Matched Run Comparison View
struct MatchedRunComparisonView: View {
    let comparison: MatchedRunComparison
    @Environment(\.colorScheme) private var colorScheme
    
    private let accentColor = Color(hex: "10B981")
    private let secondaryAccent = Color(hex: "3B82F6")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(secondaryAccent)
                
                Text("Matched Runs")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                
                Spacer()
                
                Text("\(comparison.comparisonRuns.count) similar runs")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
            }
            
            // Improvement metrics
            VStack(spacing: 10) {
                ForEach(comparison.improvements) { improvement in
                    HStack {
                        Text(improvement.metric)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: improvement.isPositive ? "arrow.up" : "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                            
                            Text(String(format: "%.1f %@", abs(improvement.improvement), improvement.unit))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(improvement.isPositive ? accentColor : Color(hex: "EF4444"))
                    }
                }
            }
            
            // Route similarity
            if comparison.routeSimilarity > 0 {
                HStack {
                    Text("Route Match")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                    
                    Spacer()
                    
                    Text("\(Int(comparison.routeSimilarity))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(secondaryAccent)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
    }
}

// MARK: - Weekly Heatmap Calendar
struct WeeklyHeatmapCalendar: View {
    let runDates: [Date]
    @Environment(\.colorScheme) private var colorScheme
    
    private let accentColor = Color(hex: "10B981")
    private let weeks = 12 // Show last 12 weeks
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            WeeklyHeatmapGrid(
                runDates: runDates,
                weeks: weeks,
                daysOfWeek: daysOfWeek,
                accentColor: accentColor
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.04),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
                .foregroundColor(accentColor)
            
            Text("Activity Heatmap")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
            
            Spacer()
            
            let totalRuns = runDates.count
            Text("\(totalRuns) \(totalRuns == 1 ? "run" : "runs")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accentColor)
        }
    }
}

private struct WeeklyHeatmapGrid: View {
    let runDates: [Date]
    let weeks: Int
    let daysOfWeek: [String]
    let accentColor: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            let config = gridConfig(for: geometry.size.width)
            let runCounts = makeRunCounts(runDates)
            
            VStack(spacing: 12) {
                HStack {
                    Spacer(minLength: 0)
                    
                    VStack(alignment: .leading, spacing: config.cellSpacing) {
                        HStack(alignment: .top, spacing: config.cellSpacing) {
                            dayLabelsColumn(cell: config.cell, dayLabelWidth: config.dayLabelWidth, cellSpacing: config.cellSpacing)
                            cellsGrid(runCounts: runCounts, cell: config.cell, cellSpacing: config.cellSpacing)
                        }
                        
                        legendRow(dayLabelWidth: config.dayLabelWidth)
                    }
                    .frame(width: config.gridWidth, alignment: .center)
                    
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 170)
    }
    
    private func dayLabelsColumn(cell: CGFloat, dayLabelWidth: CGFloat, cellSpacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { day in
                Text(daysOfWeek[day])
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.35) : Color(hex: "9CA3AF"))
                    .frame(width: dayLabelWidth, alignment: .leading)
                    .frame(height: cell)
            }
        }
    }
    
    private func cellsGrid(runCounts: [Date: Int], cell: CGFloat, cellSpacing: CGFloat) -> some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { day in
                HStack(spacing: cellSpacing) {
                    ForEach(0..<weeks, id: \.self) { week in
                        let date = dateFor(week: week, day: day)
                        let key = Calendar.current.startOfDay(for: date)
                        let runCount = runCounts[key, default: 0]
                        let hasRun = runCount > 0
                        
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(cellColor(runCount: runCount, hasRun: hasRun))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }
    
    private func legendRow(dayLabelWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: dayLabelWidth)
            
            Text("Less")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.35) : Color(hex: "9CA3AF"))
            
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(legendColor(level: i))
                        .frame(width: 12, height: 12)
                }
            }
            
            Text("More")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.35) : Color(hex: "9CA3AF"))
            
            Spacer(minLength: 0)
        }
    }
    
    private struct GridConfig {
        let dayLabelWidth: CGFloat
        let cellSpacing: CGFloat
        let cell: CGFloat
        let gridWidth: CGFloat
    }
    
    private func gridConfig(for availableWidth: CGFloat) -> GridConfig {
        let dayLabelWidth: CGFloat = 18
        let cellSpacing: CGFloat = 4
        let minCell: CGFloat = 10
        let maxCell: CGFloat = 18
        
        let rawCell = floor((availableWidth - dayLabelWidth - CGFloat(weeks - 1) * cellSpacing) / CGFloat(weeks))
        let cell = min(max(rawCell, minCell), maxCell)
        let gridWidth = dayLabelWidth + (CGFloat(weeks) * cell) + (CGFloat(weeks - 1) * cellSpacing)
        
        return GridConfig(dayLabelWidth: dayLabelWidth, cellSpacing: cellSpacing, cell: cell, gridWidth: gridWidth)
    }
    
    private func makeRunCounts(_ dates: [Date]) -> [Date: Int] {
        var dict: [Date: Int] = [:]
        dict.reserveCapacity(dates.count)
        for d in dates {
            let key = Calendar.current.startOfDay(for: d)
            dict[key, default: 0] += 1
        }
        return dict
    }
    
    private func dateFor(week: Int, day: Int) -> Date {
        let calendar = Calendar.current
        let today = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let weeksAgo = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1 - week), to: startOfWeek)!
        return calendar.date(byAdding: .day, value: day, to: weeksAgo) ?? today
    }
    
    private func cellColor(runCount: Int, hasRun: Bool) -> Color {
        if !hasRun {
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color(hex: "E5E7EB")
        }
        
        switch runCount {
        case 1: return accentColor.opacity(0.3)
        case 2: return accentColor.opacity(0.5)
        case 3: return accentColor.opacity(0.7)
        default: return accentColor
        }
    }
    
    private func legendColor(level: Int) -> Color {
        if level == 0 {
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color(hex: "E5E7EB")
        }
        return accentColor.opacity(0.25 * Double(level))
    }
}

// MARK: - Preview
#Preview {
    WeeklyHeatmapCalendar(runDates: [
        Date(),
        Date().addingTimeInterval(-86400),
        Date().addingTimeInterval(-86400 * 3),
        Date().addingTimeInterval(-86400 * 7),
        Date().addingTimeInterval(-86400 * 8)
    ])
    .padding()
    .background(Color(hex: "0A0A0B"))
}

