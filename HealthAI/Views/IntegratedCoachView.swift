import SwiftUI

struct IntegratedCoachView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var aiService: AIService
    @StateObject private var smartCoach = SmartCoachService.shared
    @StateObject private var workoutService = WorkoutService.shared
    
    @State private var messages: [CoachMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showingQuickActions = true
    
    // Premium accent color
    private let accentColor = Color(hex: "E07A5F")
    
    // Quick action suggestions
    private let quickActions = [
        QuickAction(icon: "figure.strengthtraining.traditional", text: "What should I train today?", color: Color(hex: "E07A5F")),
        QuickAction(icon: "fork.knife", text: "What should I eat?", color: Color(hex: "34D399")),
        QuickAction(icon: "bed.double.fill", text: "How's my recovery?", color: Color(hex: "8B5CF6")),
        QuickAction(icon: "chart.line.uptrend.xyaxis", text: "Analyze my progress", color: Color(hex: "3B82F6")),
        QuickAction(icon: "flame.fill", text: "Am I overtraining?", color: Color(hex: "EF4444")),
        QuickAction(icon: "target", text: "Help me reach my goals", color: Color(hex: "8B5CF6"))
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with context
                    coachHeader
                    
                    // Messages or empty state
                    if messages.isEmpty {
                        emptyState
                    } else {
                        messagesList
                    }
                    
                    // Input area
                    inputArea
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                smartCoach.configure(with: viewContext)
                addWelcomeMessage()
            }
        }
    }
    
    // MARK: - Coach Header
    private var coachHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // AI Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Coach")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text("Connected to your data")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : Color(hex: "6B6B6B"))
                }
                
                Spacer()
                
                // Context indicator
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: "34D399"))
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "34D399"))
                    }
                    
                    Text("Readiness: \(smartCoach.todayReadiness.totalScore)%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Data connection indicators
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dataChip(icon: "dumbbell.fill", label: "\(workoutService.totalWorkoutsThisWeek()) workouts", color: accentColor)
                    dataChip(icon: "heart.fill", label: "HRV \(Int(smartCoach.todayReadiness.recoveryScore))", color: Color(hex: "F472B6"))
                    dataChip(icon: "leaf.fill", label: "\(Int(smartCoach.nutritionStatus.proteinProgress * 100))% protein", color: Color(hex: "34D399"))
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)
        }
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.white)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.03), radius: 8, y: 4)
        )
    }
    
    private func dataChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : Color(hex: "4B5563"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
        .clipShape(Capsule())
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 40)
                
                // Welcome illustration
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(accentColor)
                }
                
                VStack(spacing: 10) {
                    Text("Your Personal AI Coach")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    
                    Text("I have access to your workouts, nutrition, sleep, and recovery data. Ask me anything!")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : Color(hex: "6B6B6B"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Quick action buttons
                VStack(spacing: 14) {
                    Text("Try asking:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : Color(hex: "9CA3AF"))
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(quickActions, id: \.text) { action in
                            quickActionButton(action)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
        }
    }
    
    private func quickActionButton(_ action: QuickAction) -> some View {
        Button {
            sendMessage(action.text)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(action.color)
                
                Text(action.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color.white.opacity(0.04)
                          : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.08)
                                    : Color.black.opacity(0.04),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Messages List
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubble(message: message, accentColor: accentColor)
                            .id(message.id)
                    }
                    
                    if isLoading {
                        HStack {
                            TypingIndicator(accentColor: accentColor)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Input Area
    private var inputArea: some View {
        VStack(spacing: 12) {
            // Quick suggestion chips (when not empty)
            if !messages.isEmpty && showingQuickActions {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(contextualSuggestions, id: \.self) { suggestion in
                            Button {
                                sendMessage(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(accentColor.opacity(colorScheme == .dark ? 0.2 : 0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            // Text input
            HStack(spacing: 12) {
                TextField("Ask your coach...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .regular))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(colorScheme == .dark
                                  ? Color.white.opacity(0.06)
                                  : Color.black.opacity(0.04))
                    )
                    .foregroundColor(colorScheme == .dark ? .white : Color(hex: "1A1A1A"))
                    .tint(accentColor)
                
                Button {
                    sendMessage(inputText)
                } label: {
                    ZStack {
                        Circle()
                            .fill(inputText.isEmpty
                                  ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                  : accentColor)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(inputText.isEmpty
                                             ? (colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
                                             : .white)
                    }
                }
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? Color(hex: "0A0A0B") : Color(hex: "F8F8FA"))
                .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.05), radius: 10, y: -5)
        )
    }
    
    // MARK: - Contextual Suggestions
    private var contextualSuggestions: [String] {
        var suggestions: [String] = []
        
        if smartCoach.todayReadiness.totalScore < 60 {
            suggestions.append("Why is my recovery low?")
        }
        
        if smartCoach.nutritionStatus.proteinProgress < 0.5 {
            suggestions.append("High protein meal ideas?")
        }
        
        if let recommendation = smartCoach.recommendedWorkout {
            suggestions.append("Tell me more about \(recommendation.splitType.rawValue)")
        }
        
        suggestions.append("What's my weekly progress?")
        
        return Array(suggestions.prefix(4))
    }
    
    // MARK: - Message Handling
    private func addWelcomeMessage() {
        guard messages.isEmpty else { return }
        
        let readiness = smartCoach.todayReadiness.totalScore
        let workouts = workoutService.totalWorkoutsThisWeek()
        
        let greeting = getTimeBasedGreeting()
        let contextMessage: String
        
        if readiness >= 80 {
            contextMessage = "\(greeting)! You're looking strong today with a \(readiness)% readiness score. \(workouts > 0 ? "You've crushed \(workouts) workout\(workouts > 1 ? "s" : "") this week. " : "")What would you like to work on?"
        } else if readiness >= 60 {
            contextMessage = "\(greeting)! Your readiness is at \(readiness)% - not bad! I can see your complete fitness picture. How can I help you today?"
        } else {
            contextMessage = "\(greeting). Your body is showing \(readiness)% readiness, so recovery might be a good focus today. I'm here to help with whatever you need!"
        }
        
        let welcomeMessage = CoachMessage(
            content: contextMessage,
            isUser: false,
            timestamp: Date()
        )
        messages.append(welcomeMessage)
    }
    
    private func getTimeBasedGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hey there"
        }
    }
    
    private func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = CoachMessage(content: text, isUser: true, timestamp: Date())
        messages.append(userMessage)
        
        inputText = ""
        isLoading = true
        showingQuickActions = false
        
        Task {
            let context = smartCoach.buildAIContext()
            
            let chatHistory = messages.dropLast().map { msg in
                ChatMessage(id: msg.id, content: msg.content, isUser: msg.isUser, timestamp: msg.timestamp)
            }
            
            if let response = await aiService.getIntegratedCoachResponse(
                message: text,
                smartCoachContext: context,
                conversationHistory: Array(chatHistory)
            ) {
                await MainActor.run {
                    let coachResponse = CoachMessage(content: response, isUser: false, timestamp: Date())
                    messages.append(coachResponse)
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    let errorMessage = CoachMessage(
                        content: "I'm having trouble connecting right now. Please try again in a moment.",
                        isUser: false,
                        timestamp: Date()
                    )
                    messages.append(errorMessage)
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Supporting Types
struct CoachMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
}

struct QuickAction {
    let icon: String
    let text: String
    let color: Color
}

// MARK: - Message Bubble
struct MessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: CoachMessage
    let accentColor: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !message.isUser {
                // Coach avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(message.isUser ? .white : (colorScheme == .dark ? .white : Color(hex: "1A1A1A")))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(message.isUser
                                  ? accentColor
                                  : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.white))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                message.isUser
                                    ? Color.clear
                                    : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)),
                                lineWidth: 1
                            )
                    )
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : Color(hex: "9CA3AF"))
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isUser ? .trailing : .leading)
            
            if message.isUser {
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var dotOpacities: [Double] = [0.3, 0.3, 0.3]
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Coach avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(colorScheme == .dark ? Color.white : Color(hex: "6B6B6B"))
                        .frame(width: 6, height: 6)
                        .opacity(dotOpacities[index])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04),
                                lineWidth: 1
                            )
                    )
            )
        }
        .onAppear {
            animateDots()
        }
    }
    
    private func animateDots() {
        for index in 0..<3 {
            withAnimation(
                Animation
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.15)
            ) {
                dotOpacities[index] = 1.0
            }
        }
    }
}

// MARK: - Preview
#Preview {
    IntegratedCoachView()
        .environmentObject(AIService(context: PersistenceController.preview.container.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
