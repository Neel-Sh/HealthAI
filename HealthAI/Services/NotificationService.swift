import Foundation
import UserNotifications
import SwiftUI

final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Category: String {
        case hydration = "HYDRATION_REMINDER"
        case meal = "MEAL_REMINDER"
        case sleep = "SLEEP_REMINDER"
        case summary = "DAILY_SUMMARY"
        case morningBriefing = "MORNING_BRIEFING"
        case vitals = "VITALS_UPDATE"
        case motivation = "EXERCISE_MOTIVATION"
        case recovery = "RECOVERY_TIP"
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if !granted {
                print("🔕 Notification permission not granted by user.")
            }
        } catch {
            print("🔕 Notification permission error: \(error)")
        }
    }

    func registerCategories() {
        let center = UNUserNotificationCenter.current()
        let hydration = UNNotificationCategory(identifier: Category.hydration.rawValue, actions: [], intentIdentifiers: [], options: [])
        let meal = UNNotificationCategory(identifier: Category.meal.rawValue, actions: [], intentIdentifiers: [], options: [])
        let sleep = UNNotificationCategory(identifier: Category.sleep.rawValue, actions: [], intentIdentifiers: [], options: [])
        let summary = UNNotificationCategory(identifier: Category.summary.rawValue, actions: [], intentIdentifiers: [], options: [])
        let morning = UNNotificationCategory(identifier: Category.morningBriefing.rawValue, actions: [], intentIdentifiers: [], options: [])
        let vitals = UNNotificationCategory(identifier: Category.vitals.rawValue, actions: [], intentIdentifiers: [], options: [])
        let motivation = UNNotificationCategory(identifier: Category.motivation.rawValue, actions: [], intentIdentifiers: [], options: [])
        let recovery = UNNotificationCategory(identifier: Category.recovery.rawValue, actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([hydration, meal, sleep, summary, morning, vitals, motivation, recovery])
    }

    // Clear and schedule a sensible default set of reminders
    func scheduleDefaultDailyReminders() async {
        let center = UNUserNotificationCenter.current()
        await center.removeAllPendingNotificationRequests()

        // Morning briefing (wake up): default 7:00
        scheduleDaily(identifier: "morning_briefing", category: .morningBriefing, hour: 7, minute: 0, title: "Good Morning", body: "Here’s your plan: sleep recap, today’s goals, and a quick health check.")

        // Vitals updates: mid-morning and early evening
        scheduleDaily(identifier: "vitals_morning", category: .vitals, hour: 9, minute: 15, title: "Vitals Update", body: "Check HRV, resting HR, and recovery to guide today’s effort.")
        scheduleDaily(identifier: "vitals_evening", category: .vitals, hour: 18, minute: 0, title: "Evening Vitals", body: "Review today’s vitals and recovery trend before tomorrow.")

        // Exercise motivation: morning and late afternoon
        scheduleDaily(identifier: "motivation_am", category: .motivation, hour: 7, minute: 15, title: "Let’s Move", body: "A 20–30 min session today keeps momentum strong. You’ve got this.")
        scheduleDaily(identifier: "motivation_pm", category: .motivation, hour: 17, minute: 30, title: "Afternoon Boost", body: "Quick workout or brisk walk? Small efforts add up.")

        // Hydration: 9am, 12pm, 3pm, 6pm
        for hour in [9, 12, 15, 18] {
            scheduleDaily(identifier: "hydration_\(hour)", category: .hydration, hour: hour, minute: 0, title: "Hydration", body: "Time for some water. Aim for steady intake today.")
        }

        // Nutrition: meal logging nudges at typical times
        scheduleDaily(identifier: "meal_breakfast", category: .meal, hour: 8, minute: 0, title: "Breakfast log", body: "Log your breakfast for accurate daily calories.")
        scheduleDaily(identifier: "meal_lunch", category: .meal, hour: 12, minute: 30, title: "Lunch log", body: "Add lunch to stay on track with your goal.")
        scheduleDaily(identifier: "meal_dinner", category: .meal, hour: 19, minute: 0, title: "Dinner log", body: "Record dinner and finish strong today.")

        // Sleep: wind-down reminder at 10pm and brief recovery tip at 9pm
        scheduleDaily(identifier: "sleep_winddown", category: .sleep, hour: 22, minute: 0, title: "Wind Down", body: "Start winding down for quality sleep tonight.")
        scheduleDaily(identifier: "recovery_tip", category: .recovery, hour: 21, minute: 0, title: "Recovery Tip", body: "Light stretching and a consistent bedtime improve HRV and sleep quality.")

        // Daily summary: 8pm
        scheduleDaily(identifier: "daily_summary", category: .summary, hour: 20, minute: 0, title: "Daily Check-in", body: "See today's progress and tomorrow's plan.")
    }

    func scheduleDaily(identifier: String, category: Category, hour: Int, minute: Int, title: String, body: String) {
        var date = DateComponents()
        date.hour = hour
        date.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔔 Schedule error (\(identifier)): \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Show banner even when app is in foreground
        return [.badge, .banner, .sound]
    }
}


