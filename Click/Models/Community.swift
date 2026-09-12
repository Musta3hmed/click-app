//
//  Community.swift
//  Click
//
//  A community is a named, joinable lens on the deck — a shared context
//  that changes who you see and gives you something true to open with.
//  Deliberately NOT in v1: group chat, posts, feeds, member rosters,
//  roles. Members are reachable only through the deck (rate-limited by
//  swiping, and every card carries SafetyMenu).
//
//  The curated catalogue is defined in CommunityService (Codable shape,
//  ready to move to JSON/remote later). User-created communities exist
//  but are PENDING until approved in the admin panel — an unapproved
//  name is never shown to anyone but its creator and the moderator.
//

import Foundation
import SwiftData

/// Moderation state for a community. Curated entries ship approved;
/// user-created ones start pending.
enum CommunityState: String, Codable {
    case pending
    case approved
    case rejected
}

@Model
final class Community {
    /// Canonical slug for curated entries; a UUID string for user-created.
    @Attribute(.unique) var id: String
    /// Drawn text, lowercase per the casing rule. For user-created
    /// communities this is user-written — which is exactly why nothing
    /// renders it to other people before approval.
    var name: String
    var summary: String
    /// SF Symbol name — CI bans emoji; a test asserts these resolve.
    var symbolName: String
    /// Theme token BY NAME, looked up in Swift — never hex in data.
    var tintToken: String
    var interestIDs: [String] = []
    var isCurated: Bool = true
    var sortIndex: Int = 0
    var stateRaw: String = CommunityState.approved.rawValue
    /// True when the signed-in user created it (the creator sees its
    /// pending/rejected state; AccountEraser removes it).
    var createdByCurrentUser: Bool = false
    var createdAt: Date = Date.now

    var state: CommunityState {
        get { CommunityState(rawValue: stateRaw) ?? .approved }
        set { stateRaw = newValue.rawValue }
    }

    init(
        id: String,
        name: String,
        summary: String,
        symbolName: String,
        tintToken: String,
        interestIDs: [String] = [],
        isCurated: Bool = true,
        sortIndex: Int = 0,
        state: CommunityState = .approved,
        createdByCurrentUser: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.tintToken = tintToken
        self.interestIDs = interestIDs
        self.isCurated = isCurated
        self.sortIndex = sortIndex
        self.stateRaw = state.rawValue
        self.createdByCurrentUser = createdByCurrentUser
        self.createdAt = .now
    }
}

/// Join-model, not a [String] on the profile: predicate-queryable,
/// carries per-membership state, cascades when the member is erased.
@Model
final class CommunityMembership {
    @Attribute(.unique) var id: UUID
    var communityID: String
    var member: UserProfile?
    var joinedAt: Date
    /// Defaults true only because the catalogue carries no sensitive
    /// categories and user-created entries pass a human approval. If
    /// either rule is ever relaxed, flip this default for those entries.
    var showsOnCard: Bool = true

    init(communityID: String, member: UserProfile?, joinedAt: Date = .now, showsOnCard: Bool = true) {
        self.id = UUID()
        self.communityID = communityID
        self.member = member
        self.joinedAt = joinedAt
        self.showsOnCard = showsOnCard
    }
}
