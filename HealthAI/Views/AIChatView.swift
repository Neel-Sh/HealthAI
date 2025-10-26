import SwiftUI
import CoreData

struct AIChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var aiService: AIService
    @EnvironmentObject var healthKitService: HealthKitService
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        animation: .default)
    private var healthMetrics: FetchedResults<HealthMetrics>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)],
        animation: .default)
    private var workouts: FetchedResults<WorkoutLog>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NutritionLog.date, ascending: false)],
        animation: .default)
    private var nutritionLogs: FetchedResults<NutritionLog>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HeartRateReading.timestamp, ascending: false)],
        animation: .default)
    private var heartRateReadings: FetchedResults<HeartRateReading>
    
    @State private var messages: [ChatMessage] = []
    @State private var currentMessage = ""
    @State private var isLoading = false
    @State private var showingHealthDataSheet = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Welcome message
                            if messages.isEmpty {
                                welcomeMessage
                            }
                            
                            ForEach(messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                            
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("AI is thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding()
                                .id("loading")
                            }
                        }
                        .padding()
                    }
                    .onTapGesture {
                        isTextFieldFocused = false
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation {
                            if let lastMessage = messages.last {
                                scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isLoading) { _ in
                        if isLoading {
                            withAnimation {
                                if let lastMessage = messages.last {
                                    scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                // Input area
                VStack(spacing: 12) {
                    // Quick action buttons
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            QuickChatButton(
                                title: "Health Summary",
                                icon: "heart.fill",
                                color: .red
                            ) {
                                sendQuickMessage("Give me a quick overview of my health status today")
                            }
                            
                            QuickChatButton(
                                title: "Heart Rate",
                                icon: "waveform.path.ecg",
                                color: .pink
                            ) {
                                sendQuickMessage("How is my heart rate trending today?")
                            }
                            
                            QuickChatButton(
                                title: "Recovery",
                                icon: "moon.zzz",
                                color: .purple
                            ) {
                                sendQuickMessage("How is my recovery and what should I focus on?")
                            }
                            
                            QuickChatButton(
                                title: "Fitness Goals",
                                icon: "target",
                                color: .green
                            ) {
                                sendQuickMessage("What should I focus on to improve my fitness?")
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Message input
                    HStack(spacing: 12) {
                        TextField("Ask about your health...", text: $currentMessage, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(1...4)
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                if !currentMessage.isEmpty {
                                    sendMessage()
                                }
                            }
                        
                        Button(action: sendMessage) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                        }
                        .disabled(currentMessage.isEmpty || isLoading)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .onTapGesture {
                    isTextFieldFocused = false
                }
            }
            .navigationTitle("AI Health Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Health Data") {
                        showingHealthDataSheet = true
                    }
                    .font(.subheadline)
                }
            }
            .sheet(isPresented: $showingHealthDataSheet) {
                HealthDataSummaryView()
            }
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
    }
    
    private var welcomeMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.purple)
            
            Text("AI Health Coach")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("I'm your personal health companion. I analyze your comprehensive health data including heart rate patterns, HRV, VO2 Max, sleep quality, and workouts to provide personalized insights and recommendations.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Try asking me:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• How is my heart rate trending today?")
                    Text("• What does my HRV tell me about recovery?")
                    Text("• How can I improve my sleep quality?")
                    Text("• What should I focus on this week?")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Button("Get Started") {
                sendQuickMessage("Give me a quick overview of my health status today")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(25)
        }
        .padding(24)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private func sendMessage() {
        guard !currentMessage.isEmpty, !isLoading else { return }
        
        let userMessage = ChatMessage(
            id: UUID(),
            content: currentMessage,
            isUser: true,
            timestamp: Date()
        )
        
        messages.append(userMessage)
        let messageToSend = currentMessage
        currentMessage = ""
        isTextFieldFocused = false // Dismiss keyboard when sending
        isLoading = true
        
        Task {
            let response = await aiService.getHealthInsights(
                message: messageToSend,
                healthMetrics: Array(healthMetrics.prefix(30)),
                workouts: Array(workouts.prefix(20)),
                nutritionLogs: Array(nutritionLogs.prefix(50)),
                heartRateReadings: Array(heartRateReadings.prefix(30))
            )
            
            await MainActor.run {
                let aiMessage = ChatMessage(
                    id: UUID(),
                    content: response ?? "I'm sorry, I couldn't process your request right now. Please try again.",
                    isUser: false,
                    timestamp: Date()
                )
                messages.append(aiMessage)
                isLoading = false
            }
        }
    }
    
    private func sendQuickMessage(_ message: String) {
        currentMessage = message
        sendMessage()
    }
}



struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding(12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .frame(maxWidth: 280, alignment: .trailing)
                    
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.purple)
                        
                        Text("AI Health Coach")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(message.content)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                        .frame(maxWidth: 280, alignment: .leading)
                    
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }
}

struct QuickChatButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .cornerRadius(20)
        }
    }
}

struct HealthDataSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HealthMetrics.date, ascending: false)],
        animation: .default)
    private var healthMetrics: FetchedResults<HealthMetrics>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \WorkoutLog.timestamp, ascending: false)],
        animation: .default)
    private var workouts: FetchedResults<WorkoutLog>
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Health Metrics Summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Health Metrics")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let recent = healthMetrics.first {
                            VStack(alignment: .leading, spacing: 8) {
                                DataRow(label: "Steps", value: "\(recent.stepCount)")
                                DataRow(label: "Active Calories", value: "\(Int(recent.activeCalories))")
                                DataRow(label: "Heart Rate", value: "\(recent.restingHeartRate) bpm")
                                DataRow(label: "Sleep Hours", value: String(format: "%.1f", recent.sleepHours))
                                DataRow(label: "HRV", value: String(format: "%.1f ms", recent.hrv))
                            }
                        } else {
                            Text("No health metrics available")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // Workouts Summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Workouts")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if workouts.isEmpty {
                            Text("No workouts recorded")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(workouts.prefix(5)), id: \.id) { workout in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workout.workoutType.capitalized)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Text(workout.timestamp.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(String(format: "%.1f km", workout.distance))
                                            .font(.subheadline)
                                        
                                        Text(formatDuration(workout.duration))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Data Sources
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Sources")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            DataSourceRow(name: "Apple Health", connected: true)
                            DataSourceRow(name: "Nutrition Logs", connected: true)
                            DataSourceRow(name: "Manual Entry", connected: true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Health Data")
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
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct DataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct DataSourceRow: View {
    let name: String
    let connected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(connected ? .green : .red)
            
            Text(name)
                .font(.subheadline)
            
            Spacer()
            
            Text(connected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    AIChatView()
        .environmentObject(AIService(context: PersistenceController.preview.container.viewContext, apiKey: ""))
        .environmentObject(HealthKitService(context: PersistenceController.preview.container.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 