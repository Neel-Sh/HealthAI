# HealthAI - Your Intelligent Fitness Companion

HealthAI is an advanced iOS fitness application that combines artificial intelligence with comprehensive health tracking to provide personalized fitness insights, nutrition recommendations, and workout analytics.

## Features

### 🏃‍♂️ Workout Tracking
- Automatic workout detection and logging
- Detailed metrics including distance, pace, heart rate, and perceived exertion
- AI-powered performance analysis and recommendations
- Recovery tips based on workout intensity

### 🍎 Nutrition Management
- Smart meal logging with AI image recognition
- Comprehensive nutritional analysis including macro and micronutrients
- Personalized meal recommendations
- Water intake tracking
- Caloric deficit analysis

### 💪 Health Analytics
- Real-time health metrics monitoring
- Sleep quality analysis
- Heart rate variability (HRV) tracking
- VO2 max estimation
- Recovery and readiness scores

### 🤖 AI-Powered Features
- Personalized workout recommendations
- Recovery optimization
- Nutrition insights
- Progress predictions
- Health trend analysis

## Requirements

- iOS 15.0+
- Xcode 13.0+
- Swift 5.0+
- HealthKit compatible device

## Installation

1. Clone the repository


2. Open the project in Xcode
```bash
cd HealthAI
open HealthAI.xcodeproj
```

3. Set up your OpenAI API key:
   - Create a copy of `.env.example` and name it `.env`
   - Add your OpenAI API key to the `.env` file
   - Or add it directly to your Info.plist as `OPENAI_API_KEY`

4. Build and run the project in Xcode

## Configuration

### HealthKit Permissions
The app requires the following HealthKit permissions:
- Steps
- Heart Rate
- Workouts
- Sleep Analysis
- Active Energy
- Height
- Weight

### API Keys
Make sure to configure your OpenAI API key in one of these locations:
1. Environment variable: `OPENAI_API_KEY`
2. Info.plist: Add as `OPENAI_API_KEY`
3. Direct initialization of `AIService` with API key

## Architecture

The app follows the MVVM (Model-View-ViewModel) architecture pattern and includes:

### Core Components
- `Models/`: Data models and CoreData entities
- `Views/`: SwiftUI views and UI components
- `ViewModels/`: View models and business logic
- `Services/`: Core services including AI, HealthKit, and Analytics

### Key Services
- `AIService`: Handles AI-powered features and OpenAI integration
- `HealthKitService`: Manages health data access and synchronization
- `AnalyticsService`: Tracks user metrics and app performance
- `AchievementService`: Manages user achievements and goals

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request


## Acknowledgments

- OpenAI for providing the AI capabilities
- Apple HealthKit for health data integration
- The iOS development community for various open-source contributions

