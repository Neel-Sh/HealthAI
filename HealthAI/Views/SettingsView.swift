import SwiftUI
import HealthKit

struct SettingsView: View {
    @EnvironmentObject var healthKitService: HealthKitService
    @State private var isSyncing = false
    @State private var showingClearDataAlert = false
    
    // Personal Information States
    @State private var height: Double = 175.0
    @State private var age: Double = 30.0
    @State private var gender: String = "Male"
    @State private var currentWeight: Double = 70.0
    @State private var userProfile: UserProfile?
    @State private var isLoadingProfile = false
    @State private var profileLoadError: String?
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 32) {
                    // Header
                    headerSection
                    
                    // Personal Information Section
                    personalInformationSection
                    
                    // Health Data Section
                    healthDataSection
                    
                    // Sync Section
                    syncSection
                    
                    // About Section
                    aboutSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .alert("Clear All Data", isPresented: $showingClearDataAlert) {
            Button("Clear", role: .destructive) {
                clearAllData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all your health data from the app. This action cannot be undone.")
        }
        .onAppear {
            // Automatically load profile from HealthKit when settings view appears
            Task {
                await loadProfileFromHealthKit()
            }
        }
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.title)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Manage your health data and preferences")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fontWeight(.regular)
            }
            
            Spacer()
        }
    }
    
    private var healthDataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Health Data")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 12) {
                // HealthKit Status
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HealthKit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(healthKitService.authorizationStatus == .sharingAuthorized ? "Connected" : "Not Connected")
                            .font(.caption)
                            .foregroundColor(healthKitService.authorizationStatus == .sharingAuthorized ? .green : .orange)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await healthKitService.requestAuthorization()
                        }
                    }) {
                        Text(healthKitService.authorizationStatus == .sharingAuthorized ? "Manage" : "Connect")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // AI Coach Status
                HStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.purple)
                        .frame(width: 32, height: 32)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Coach")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Management")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 12) {
                // Sync Now Button
                Button(action: {
                    Task {
                        await syncHealthData()
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: isSyncing ? "arrow.clockwise" : "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .rotationEffect(.degrees(isSyncing ? 360 : 0))
                            .animation(isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSyncing)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sync Health Data")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text(isSyncing ? "Syncing..." : "Update with latest data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if !isSyncing {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .disabled(isSyncing)
                .buttonStyle(PlainButtonStyle())
                
                // Clear Data Button
                Button(action: {
                    showingClearDataAlert = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear All Data")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                            
                            Text("Delete all stored health data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.headline)
                .fontWeight(.medium)
            
            VStack(spacing: 12) {
                // Version
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("1.0.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Privacy Policy
                Button(action: {
                    if let url = URL(string: "https://apple.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                            .frame(width: 32, height: 32)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privacy Policy")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("How we protect your data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Personal Information Section
    
    private var personalInformationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Personal Information")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await loadProfileFromHealthKit()
                    }
                }) {
                    HStack(spacing: 4) {
                        if isLoadingProfile {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                        }
                        Text("Load from Apple Health")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .disabled(isLoadingProfile)
            }
            
            if let profile = userProfile, profile.isComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Data automatically loaded from Apple Health")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.vertical, 4)
            }
            
            if let error = profileLoadError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 4)
            }
            
            VStack(spacing: 12) {
                // Body Weight
                HStack {
                    Text("Current Weight:")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    if let profile = userProfile, let weight = profile.weight {
                        Text(profile.displayWeight)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    } else {
                        HStack {
                            Button("-") {
                                if currentWeight > 40 {
                                    currentWeight -= 0.5
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(15)
                            
                            Text(String(format: "%.1f kg", currentWeight))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(minWidth: 60)
                            
                            Button("+") {
                                if currentWeight < 200 {
                                    currentWeight += 0.5
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(15)
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Age
                HStack {
                    Text("Age:")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    if let profile = userProfile, let profileAge = profile.age {
                        Text(profile.displayAge)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    } else {
                        HStack {
                            Button("-") {
                                if age > 16 {
                                    age -= 1
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(15)
                            
                            Text(String(format: "%.0f years", age))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(minWidth: 80)
                            
                            Button("+") {
                                if age < 100 {
                                    age += 1
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(15)
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Height
                HStack {
                    Text("Height:")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    if let profile = userProfile, let profileHeight = profile.height {
                        Text(profile.displayHeight)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    } else {
                        HStack {
                            Button("-") {
                                if height > 120 {
                                    height -= 1
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(15)
                            
                            Text(String(format: "%.0f cm", height))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(minWidth: 60)
                            
                            Button("+") {
                                if height < 220 {
                                    height += 1
                                }
                            }
                            .frame(width: 30, height: 30)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(15)
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Gender
                HStack {
                    Text("Gender:")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    if let profile = userProfile, let profileGender = profile.gender {
                        Text(profile.displayGender)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    } else {
                        Picker("Gender", selection: $gender) {
                            Text("Male").tag("Male")
                            Text("Female").tag("Female")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 120)
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
            
            Text("💡 This information is used for accurate calorie calculations. Data from Apple Health is automatically synchronized.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }
    
    // MARK: - Actions
    
    private func syncHealthData() async {
        await MainActor.run {
            isSyncing = true
        }
        
        await healthKitService.syncHealthMetrics()
        await healthKitService.syncRecentWorkouts()
        
        await MainActor.run {
            isSyncing = false
        }
    }
    
    private func loadProfileFromHealthKit() async {
        guard healthKitService.hasValidAuthorization() else {
            await MainActor.run {
                profileLoadError = "HealthKit access required. Please enable in Settings."
            }
            return
        }
        
        await MainActor.run {
            isLoadingProfile = true
            profileLoadError = nil
        }
        
        let profile = await healthKitService.getUserProfile()
        
        await MainActor.run {
            if let profile = profile {
                self.userProfile = profile
                
                // Update local values with HealthKit data
                if let age = profile.age {
                    self.age = age
                }
                if let gender = profile.gender {
                    self.gender = gender
                }
                if let height = profile.height {
                    self.height = height
                }
                if let weight = profile.weight {
                    self.currentWeight = weight
                }
                
                profileLoadError = nil
                print("✅ Successfully loaded profile from HealthKit in Settings")
            } else {
                profileLoadError = "Could not load profile data from Apple Health"
            }
            
            isLoadingProfile = false
        }
    }
    
    private func clearAllData() {
        // Implementation for clearing all data
        // This would clear Core Data entities
        print("Clearing all data...")
    }
}

#Preview {
    SettingsView()
        .environmentObject(HealthKitService(context: PersistenceController.preview.container.viewContext))
} 