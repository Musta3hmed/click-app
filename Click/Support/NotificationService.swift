//
//  NotificationService.swift
//  Click
//
//  Local notifications only — every piece of state is on-device, so
//  UNUserNotificationCenter delivers the whole lever with no backend,
//  no APNs, no entitlement.
//
//  HARD RULE (MEGA-BRIEF P1): a notification may only fire for an event
//  that actually happened — an unopened match or message from an
//  identified person, a daily reward that is ready, a boost that
//  expired, an event that is ending. Never a streak, a countdown, a
//  view count, or a fabricated "someone liked you".
//
//  Permission is primed IN APP after the first match (never at launch),
//  so a "no" on the pre-prompt isn't a permanent system-level no.
//

import Foundation
import UserNotifications

@MainActor
enum NotificationService {

    enum Identifier {
        static let boostExpiry = "boost-expiry"
        static let dailyReward = "daily-reward"
        static let unreadDigest = "unread-digest"
        static let eventEnding = "event-ending"
    }

    // MARK: - Authorization

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// The system prompt — only ever called from the in-app pre-prompt
    /// or the Settings toggle, never at launch.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Category gates

    private static func enabled(_ key: String) -> Bool {
        // Default ON once authorized; the key stores an explicit opt-out.
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    private static func canNotify(_ categoryKey: String) async -> Bool {
        guard enabled(categoryKey) else { return false }
        return await authorizationStatus() == .authorized
    }

    // MARK: - Real-event schedulers

    /// "Your boost finished" at the moment it actually expires.
    /// Re-activation reschedules under the same identifier.
    static func scheduleBoostExpiry(at date: Date) {
        Task {
            guard await canNotify(DefaultsKey.notifyBoost), date > .now else { return }
            let content = UNMutableNotificationContent()
            content.title = "Boost finished"
            content.body = "Your 30-minute boost just ended."
            content.sound = .default
            schedule(id: Identifier.boostExpiry, content: content, at: date)
        }
    }

    /// "Your daily reward is ready" — tomorrow morning, after a claim
    /// today made tomorrow's reward real. No streak language.
    static func scheduleDailyRewardReady() {
        Task {
            guard await canNotify(DefaultsKey.notifyDailyReward) else { return }
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) else { return }
            var components = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            components.hour = 10
            guard let fireDate = Calendar.current.date(from: components) else { return }

            let content = UNMutableNotificationContent()
            content.title = "Daily reward ready"
            content.body = "Today's reward is ready to collect."
            content.sound = .default
            schedule(id: Identifier.dailyReward, content: content, at: fireDate)
        }
    }

    /// Backgrounding with unread messages: one reminder, hours later,
    /// naming the real sender. Cancelled the moment the user returns.
    static func scheduleUnreadDigest(senderName: String, unreadCount: Int) {
        Task {
            guard await canNotify(DefaultsKey.notifyMessages), unreadCount > 0 else { return }
            let content = UNMutableNotificationContent()
            content.title = unreadCount == 1 ? "Unread message" : "Unread messages"
            content.body = unreadCount == 1
                ? "\(senderName) sent you a message."
                : "\(senderName) and others sent you \(unreadCount) messages."
            content.sound = .default
            schedule(id: Identifier.unreadDigest, content: content, at: .now.addingTimeInterval(3 * 60 * 60))
        }
    }

    /// The user came back — pending "you have unread" reminders are moot.
    static func cancelUnreadDigest() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Identifier.unreadDigest])
    }

    /// An event genuinely ending soon (scheduled when the event system
    /// grants entries; fires 24h before the window closes).
    static func scheduleEventEnding(title: String, endsAt: Date) {
        Task {
            guard await canNotify(DefaultsKey.notifyEvents) else { return }
            let fireDate = endsAt.addingTimeInterval(-24 * 60 * 60)
            guard fireDate > .now else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(title) ends tomorrow"
            content.body = "Your free entries expire when the event closes."
            content.sound = .default
            schedule(id: Identifier.eventEnding, content: content, at: fireDate)
        }
    }

    // MARK: - Plumbing

    private static func schedule(id: String, content: UNMutableNotificationContent, at date: Date) {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(request)
    }

    /// Sign-out/deletion: nothing scheduled for the previous account may
    /// fire for the next one.
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
