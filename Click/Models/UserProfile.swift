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
    var zodiacRaw: String
    var interests: [String]
    var isVerified: Bool
    var isOnline: Bool

    /// True for the single row representing the signed-in user.
    var isCurrentUser: Bool

    /// For the current-user row: the AuthResult.providerUserID that owns it.
    /// Onboarding refuses to reuse a row whose owner doesn't match the
    /// signed-in credential — the backstop against inheriting a previous
    /// account's identity on a shared phone.
    var ownerProviderID: String?

    // MARK: Onboarding answers
    // Nil/default until onboarding fills them in. Seeded mock profiles get
    // a gender so the deck filter has something to bite on.

    var birthDate: Date?
    var genderRaw: String?
    /// The signed-in user's "who I want to meet" answer(s).
    var seekingRaw: [String]

    // Coarse location only — city-level, never precise coordinates.
    var city: String?
    var country: String?
    /// ISO 3166-1 alpha-2, e.g. "AU". Rendered as a text badge — flag emoji
    /// are banned because they render as boxes where the emoji font is missing.
    var countryCode: String?

    @Relationship(deleteRule: .cascade, inverse: \ProfilePhoto.owner)
    var photos: [ProfilePhoto]

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
        countryCode: String? = nil,
        zodiac: Zodiac = .aquarius,
        interests: [String] = [],
        isVerified: Bool = false,
        isOnline: Bool = false,
        isCurrentUser: Bool = false,
        isBlocked: Bool = false,
        isMuted: Bool = false,
        gender: Gender? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.bio = bio
        self.zodiacRaw = zodiac.rawValue
        self.interests = interests
        self.isVerified = isVerified
        self.isOnline = isOnline
        self.isCurrentUser = isCurrentUser
        self.isBlocked = isBlocked
        self.isMuted = isMuted
        self.reportedReasonRaw = nil
        self.reportedAt = nil
        self.birthDate = nil
        self.genderRaw = gender?.rawValue
        self.seekingRaw = []
        self.city = nil
        self.country = nil
        self.countryCode = countryCode
        self.ownerProviderID = nil
        self.photos = []
        self.createdAt = createdAt
    }

    var zodiac: Zodiac {
        get { Zodiac(rawValue: zodiacRaw) ?? .aquarius }
        set { zodiacRaw = newValue.rawValue }
    }

    var gender: Gender? {
        get { genderRaw.flatMap(Gender.init(rawValue:)) }
        set { genderRaw = newValue?.rawValue }
    }

    var seeking: [SeekingPreference] {
        get { seekingRaw.compactMap(SeekingPreference.init(rawValue:)) }
        set { seekingRaw = newValue.map(\.rawValue) }
    }

    /// Photos in display order; the first is the primary.
    var orderedPhotos: [ProfilePhoto] {
        photos.sorted { $0.sortIndex < $1.sortIndex }
    }

    var isReported: Bool { reportedAt != nil }

    /// Age derived from DOB when onboarding has provided one; otherwise the
    /// stored (seeded) value.
    var displayAge: Int {
        guard let birthDate else { return age }
        return Self.age(from: birthDate)
    }

    static func age(from birthDate: Date, on date: Date = .now) -> Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: date).year ?? 0
    }
}

/// One profile photo. Bytes live in external storage so the SwiftData store
/// file stays small; images are downscaled before they ever get here.
@Model
final class ProfilePhoto {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var data: Data
    var sortIndex: Int
    var owner: UserProfile?

    init(id: UUID = UUID(), data: Data, sortIndex: Int, owner: UserProfile? = nil) {
        self.id = id
        self.data = data
        self.sortIndex = sortIndex
        self.owner = owner
    }
}
