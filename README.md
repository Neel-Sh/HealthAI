# HealthAI

An experimental iOS fitness app combining HealthKit data, running and workout tracking, nutrition logs, and AI-assisted coaching. Built with SwiftUI and Core Data.

## Included features

- Health dashboards, sleep views, goals, and achievements.
- Running sessions, route maps, workout planning, and an exercise library.
- Nutrition and water logging.
- Coaching and recovery prompts through `HealthAI/Services/AIService.swift`.

These describe the source tree, not a claim that every device or live-service journey has been verified.

## Run locally

1. Open `HealthAI.xcodeproj` in Xcode with an iOS 18 or newer SDK. The project deployment target is **iOS 18.0**.
2. Select the **HealthAI** scheme and your own signing team.
3. Run on an iPhone for HealthKit, location, and workout behavior. Simulator data is not equivalent to a physical workout.
4. For optional AI calls, set `OPENAI_API_KEY` in your **local, unshared Xcode Run scheme environment**. The service reads process environment variables; there is no `.env` loader or `.env.example` in this app.

Do not put credentials in source files, shared schemes, or a distributed app's Info.plist. AI requests send the prompt's workout, health, or conversation context to the configured OpenAI service. Review the prompt construction before using personal health data.

## Project map

| Path | Purpose |
| --- | --- |
| `HealthAI/Models/` | Health, nutrition, goals, workouts, and run data |
| `HealthAI/Services/` | HealthKit, running, coaching, notifications, and analytics |
| `HealthAI/Views/` | Dashboard and feature interfaces |
| `HealthAITests/`, `HealthAIUITests/` | Xcode test targets |

Use Xcode's **Product → Test** for the chosen destination. Report device permissions, backend configuration, and checks actually run with changes; see [Contributing](CONTRIBUTING.md).

This is a software experiment; its generated coaching and metrics have not been clinically validated. No repository-wide license file is included.
