import SwiftUI

struct SparklineChart: View {
    var data: [Double]
    var lineColor: Color
    var fillGradient: LinearGradient?
    var lineWidth: CGFloat = 2.0
    
    private var sanitizedData: [Double] {
        let filtered = data.filter { !$0.isNaN && !$0.isInfinite }
        if filtered.count < 2 { return [] }
        return filtered
    }
    
    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            if !points.isEmpty {
                ZStack {
                    if let fillGradient {
                        sparklinePath(points: points, in: proxy.size)
                            .fill(fillGradient)
                            .opacity(0.25)
                    }
                    linePath(points: points)
                        .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    if let last = points.last {
                        Circle()
                            .fill(lineColor)
                            .frame(width: 6, height: 6)
                            .position(last)
                    }
                }
            } else {
                Capsule()
                    .fill(lineColor.opacity(0.25))
                    .frame(height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: proxy.size.height / 2)
            }
        }
    }
    
    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let values = sanitizedData
        guard let minValue = values.min(), let maxValue = values.max(), maxValue - minValue != 0 else {
            return values.enumerated().map { index, _ in
                let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let y = size.height / 2
                return CGPoint(x: x, y: y)
            }
        }
        let range = maxValue - minValue
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let normalized = (value - minValue) / range
            let y = size.height - (CGFloat(normalized) * size.height)
            return CGPoint(x: x, y: y)
        }
    }
    
    private func linePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
    
    private func sparklinePath(points: [CGPoint], in size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        for point in points {
            path.addLine(to: point)
        }
        if let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: size.height))
        }
        path.closeSubpath()
        return path
    }
}

