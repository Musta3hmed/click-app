//
//  UserProfile.swift
//  Click
//

import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var age: Int
    var bio: String
    var countryFlag: String
    var zodiacRaw: String
    var interests: [String]
    var isVerified: Bool
    var isOnline: Bool

    /// True for the single row representing the signed-in user.
    var isCurrentUser: Bool

    // MARK: Safety state
    // Blocking hides the profile everywhere. Muting only silences
    // notifications and keeps the conversation in place.
    var isBlocked: Bool
    var isMuted: Bool
    var reportedReasonRaw: String?
    var reportedAt: Date?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        age: Int,
        bio: String = "",
        countryFlag: String = "🇦🇺",
        zodiac: Zodiac = .aquarius,
        interests: [String] = [],
        isVerified: Bool = false,
        isOnline: Bool = false,
        isCurrentUser: Bool = false,
        isBlocked: Bool = false,
        isMuted: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.bio = bio
        self.countryFlag = countryFlag
        self.zodiacRaw = zodiac.rawValue
        self.interests = interests
        self.isVerified = isVerified
        self.isOnline = isOnline
        self.isCurrentUser = isCurrentUser
        self.isBlocked = isBlocked
        self.isMuted = isMuted
        self.reportedReasonRaw = nil
        self.reportedAt = nil
        self.createdAt = createdAt
    }

    var zodiac: Zodiac {
        get { Zodiac(rawValue: zodiacRaw) ?? .aquarius }
        set { zodiacRaw = newValue.rawValue }
    }

    var isReported: Bool { reportedAt != nil }
}
