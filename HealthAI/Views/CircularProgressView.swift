import SwiftUI

struct CircularProgressView: View {
    let progress: Double
    let title: String
    let subtitle: String
    let size: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: size, height: size)
                
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)
                
                VStack(spacing: 4) {
                    Text(subtitle)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    CircularProgressView(
        progress: 0.75,
        title: "Progress",
        subtitle: "75%",
        size: 120
    )
} 