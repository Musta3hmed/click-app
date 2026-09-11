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

    var emoji: String {
        switch self {
        case .boost: "⚡️"
        case .bulkChat: "💌"
        case .admirers: "👁️"
        case .reveal: "🔓"
        case .superChat: "❤️"
        }
    }
}

/// The four tabs on the chats screen.
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
        case .topPicks: "top picks"
        }
    }
}

/// Reasons offered when reporting a profile or conversation.
/// Required for App Store review of user-generated-content apps.
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
        case .harassment: "Harassment or hate"
        case .nudity: "Nudity or sexual content"
        case .spam: "Spam or scam"
        case .underage: "User appears underage"
        case .impersonation: "Impersonation or fake profile"
        case .selfHarm: "Self-harm or suicide"
        case .other: "Something else"
        }
    }
}

enum Zodiac: String, CaseIterable, Codable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces

    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .aries: "♈️"
        case .taurus: "♉️"
        case .gemini: "♊️"
        case .cancer: "♋️"
        case .leo: "♌️"
        case .virgo: "♍️"
        case .libra: "♎️"
        case .scorpio: "♏️"
        case .sagittarius: "♐️"
        case .capricorn: "♑️"
        case .aquarius: "♒️"
        case .pisces: "♓️"
        }
    }
}
