//
//  Enums.swift
//  Click
//
//  Value types shared across the models. These are stored on SwiftData
//  models as raw strings so the schema stays stable if cases are added.
//

import Foundation

enum BoosterKind: String, CaseIterable, Identifiable, Codable {
    case boost
    case bulkChat
    case admirers
    case reveal
    case superChat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .boost: "boost"
        case .bulkChat: "bulk chat"
        case .admirers: "admirers"
        case .reveal: "reveal"
        case .superChat: "super chat"
        }
    }

    /// SF Symbols rather than emoji: they always render, tint correctly and
    /// scale with Dynamic Type. Swap for custom artwork when it exists.
    var systemImage: String {
        switch self {
        case .boost: "bolt.fill"
        case .bulkChat: "envelope.fill"
        case .admirers: "eye.fill"
        case .reveal: "lock.open.fill"
        case .superChat: "heart.fill"
        }
    }
}

/// The four tabs on the chats screen. `topPicks` keeps its raw value for
/// stored rows but now presents as the matches list.
enum ChatFolder: String, CaseIterable, Identifiable, Codable {
    case messages
    case requests
    case views
    case topPicks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .messages: "messages"
        case .requests: "requests"
        case .views: "views"
        case .topPicks: "matches"
        }
    }
}

/// Subscription tiers. Purchases are SIMULATED until a billing backend
/// exists - every surface that sells one says so ("demo - no real
/// charge"). Prices are placeholders.
enum SubscriptionTier: String, CaseIterable, Identifiable, Codable {
    case free
    case plus
    case gold

    var id: String { rawValue }

    /// Lowercase - Click draws these (casing rule).
    var label: String {
        switch self {
        case .free: "click"
        case .plus: "click+"
        case .gold: "click gold"
        }
    }

    var priceLabel: String {
        switch self {
        case .free: "free"
        case .plus: "$4.99 / month"
        case .gold: "$9.99 / month"
        }
    }

    /// Marketing copy per tier. The one wired-up benefit today is the
    /// free-super-likes allowance; the rest are copy until a backend exists.
    var benefits: [String] {
        switch self {
        case .free: [
            "unlimited swiping",
            "1 free super like a day",
            "daily rewards and bingo",
        ]
        case .plus: [
            "everything in click",
            "5 free super likes a day",
            "100 bonus coins every month",
            "see who viewed your profile sooner",
        ]
        case .gold: [
            "everything in click+",
            "unlimited free super likes",
            "300 bonus coins every month",
            "a free boost every week",
            "gold badge on your profile",
        ]
        }
    }

    /// The wired benefit: free super likes per day.
    var freeSuperLikesPerDay: Int {
        switch self {
        case .free: 1
        case .plus: 5
        case .gold: .max
        }
    }

    /// Simulated first-month bonus credited on upgrade.
    var signupBonusCoins: Int {
        switch self {
        case .free: 0
        case .plus: 100
        case .gold: 300
        }
    }
}

/// Lifecycle of a super-like request in the requests folder.
/// Stored as a raw string on Conversation so the schema stays stable.
enum RequestState: String, Codable {
    case none
    case pending
    case accepted
    case denied
}

/// Reasons offered when reporting a profile or conversation.
/// Required for App Store review of user-generated-content apps.
/// Labels are lowercase: Click draws these menus itself (casing rule —
/// only system-drawn alerts use sentence case).
enum ReportReason: String, CaseIterable, Identifiable, Codable {
    case harassment
    case nudity
    case spam
    case underage
    case impersonation
    case selfHarm
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .harassment: "harassment or hate"
        case .nudity: "nudity or sexual content"
        case .spam: "spam or scam"
        case .underage: "user appears underage"
        case .impersonation: "impersonation or fake profile"
        case .selfHarm: "self-harm or suicide"
        case .other: "something else"
        }
    }
}

/// Self-described gender, set during onboarding.
enum Gender: String, CaseIterable, Identifiable, Codable {
    case man
    case woman
    case nonBinary
    case preferNotToSay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .man: "man"
        case .woman: "woman"
        case .nonBinary: "non-binary"
        case .preferNotToSay: "prefer not to say"
        }
    }
}

/// Who the user wants to meet. Multi-select; drives the swipe deck filter.
enum SeekingPreference: String, CaseIterable, Identifiable, Codable {
    case men
    case women
    case everyone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .men: "men"
        case .women: "women"
        case .everyone: "everyone"
        }
    }

    /// Whether a profile with this gender falls inside the preference.
    func includes(_ gender: Gender) -> Bool {
        switch self {
        case .everyone: true
        case .men: gender == .man
        case .women: gender == .woman
        }
    }
}

enum Zodiac: String, CaseIterable, Codable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces

    var label: String { rawValue }

    /// Sign for a birth date, so onboarding can derive it from the DOB
    /// instead of every profile defaulting to aquarius.
    static func from(birthDate: Date, calendar: Calendar = .current) -> Zodiac {
        let components = calendar.dateComponents([.month, .day], from: birthDate)
        guard let month = components.month, let day = components.day else { return .aquarius }
        switch (month, day) {
        case (3, 21...), (4, ...19): return .aries
        case (4, 20...), (5, ...20): return .taurus
        case (5, 21...), (6, ...20): return .gemini
        case (6, 21...), (7, ...22): return .cancer
        case (7, 23...), (8, ...22): return .leo
        case (8, 23...), (9, ...22): return .virgo
        case (9, 23...), (10, ...22): return .libra
        case (10, 23...), (11, ...21): return .scorpio
        case (11, 22...), (12, ...21): return .sagittarius
        case (12, 22...), (1, ...19): return .capricorn
        case (1, 20...), (2, ...18): return .aquarius
        default: return .pisces
        }
    }
}
