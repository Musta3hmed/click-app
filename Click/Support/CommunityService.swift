//
//  CommunityService.swift
//  Click
//
//  The single place community rules live: the curated catalogue, seeding,
//  join/leave with caps and rate limits, suggestions from interest
//  overlap, creation requests and moderation. Views never write
//  membership rows themselves.
//
//  Safety posture (non-negotiable, see the customisation brief 3.5):
//  no sensitive categories in the catalogue; pending names render only
//  to their creator and the admin panel; block is transitive (the deck
//  lens filters the same non-blocked candidate set); no roster browsing
//  anywhere; memberships and user-created communities are erased with
//  the account.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
enum CommunityService {
    /// Mirrors the interests cap; also the anti-spam control.
    static let joinCap = 5
    /// Reach-farming brake: joins per local day.
    static let dailyJoinLimit = 10
    static let maxNameLength = 30
    static let maxSummaryLength = 80

    /// Codable so the catalogue can move to JSON/a remote URL without
    /// touching call sites.
    struct CatalogEntry: Codable {
        let id: String
        let name: String
        let summary: String
        let symbolName: String
        let tintToken: String
        let interestIDs: [String]
    }

    /// Curated catalogue — a content-policy decision made once, by a
    /// human. No community keyed to sexuality, religion, ethnicity,
    /// health, recovery, disability, immigration status or politics.
    static let catalog: [CatalogEntry] = [
        CatalogEntry(id: "late-night-music", name: "late-night music", summary: "for people whose best ideas arrive after midnight", symbolName: "music.note.house.fill", tintToken: "brandViolet", interestIDs: ["live-music", "making-music", "festivals", "karaoke"]),
        CatalogEntry(id: "film-club", name: "film club", summary: "watch it, argue about it, watch it again", symbolName: "film.fill", tintToken: "brandPink", interestIDs: ["films", "film-making", "tv-series", "anime"]),
        CatalogEntry(id: "early-birds", name: "early birds", summary: "runs, gyms and sunrises before everyone else wakes up", symbolName: "figure.run", tintToken: "brandCoral", interestIDs: ["gym", "running", "yoga", "martial-arts"]),
        CatalogEntry(id: "coffee-crawl", name: "coffee crawl", summary: "rating flat whites like it's a public service", symbolName: "cup.and.saucer.fill", tintToken: "brandGold", interestIDs: ["coffee", "brunch", "tea"]),
        CatalogEntry(id: "game-night", name: "game night", summary: "controllers, cards and the occasional table flip", symbolName: "gamecontroller.fill", tintToken: "brandMagenta", interestIDs: ["gaming", "board-games", "chess"]),
        CatalogEntry(id: "trail-heads", name: "trail heads", summary: "hikes, climbs and tents that almost stay up", symbolName: "figure.hiking", tintToken: "online", interestIDs: ["hiking", "camping", "climbing", "stargazing"]),
        CatalogEntry(id: "salt-water", name: "salt water", summary: "surf checks, sea swims and sand in everything", symbolName: "figure.surfing", tintToken: "verified", interestIDs: ["surfing", "swimming", "beach"]),
        CatalogEntry(id: "home-cooks", name: "home cooks", summary: "recipes traded, kitchens ruined, worth it", symbolName: "frying.pan", tintToken: "brandOrange", interestIDs: ["cooking", "baking", "street-food", "eating-out"]),
        CatalogEntry(id: "page-turners", name: "page turners", summary: "books, writing and strong opinions about endings", symbolName: "book.fill", tintToken: "brandViolet", interestIDs: ["books", "writing", "podcasts"]),
        CatalogEntry(id: "gallery-hoppers", name: "gallery hoppers", summary: "art, museums and pretending to understand both", symbolName: "paintbrush.fill", tintToken: "brandPink", interestIDs: ["art", "museums", "photography", "design"]),
        CatalogEntry(id: "pitch-side", name: "pitch side", summary: "playing badly, watching intensely", symbolName: "soccerball", tintToken: "online", interestIDs: ["football", "basketball", "tennis"]),
        CatalogEntry(id: "wanderers", name: "wanderers", summary: "always planning the next trip mid-trip", symbolName: "airplane", tintToken: "verified", interestIDs: ["travel", "backpacking", "city-breaks", "road-trips"]),
    ]

    /// Curated tint tokens, resolved by name. The only place a token
    /// string becomes a colour.
    static let tintTokens: [String: Color] = [
        "brandOrange": Theme.brandOrange,
        "brandCoral": Theme.brandCoral,
        "brandPink": Theme.brandPink,
        "brandGold": Theme.brandGold,
        "brandMagenta": Theme.brandMagenta,
        "brandViolet": Theme.brandViolet,
        "accent": Theme.accent,
        "online": Theme.online,
        "verified": Theme.verified,
        "coin": Theme.coin,
    ]

    static func tint(_ token: String) -> Color {
        tintTokens[token] ?? Theme.brandPink
    }

    // MARK: - Seeding

    /// Upserts the curated catalogue and gives seeded candidates
    /// deterministic memberships (interest overlap >= 2, at most 3 per
    /// person) so the lens and shared chips have something to show.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Community>())) ?? []
        let existingIDs = Set(existing.map(\.id))

        for (index, entry) in catalog.enumerated() where !existingIDs.contains(entry.id) {
            context.insert(Community(
                id: entry.id,
                name: entry.name,
                summary: entry.summary,
                symbolName: entry.symbolName,
                tintToken: entry.tintToken,
                interestIDs: entry.interestIDs,
                isCurated: true,
                sortIndex: index,
                state: .approved
            ))
        }

        // Candidate memberships, once.
        let membershipCount = (try? context.fetchCount(FetchDescriptor<CommunityMembership>())) ?? 0
        if membershipCount == 0 {
            let candidates = (try? context.fetch(
                FetchDescriptor<UserProfile>(predicate: #Predicate { !$0.isCurrentUser })
            )) ?? []
            for candidate in candidates {
                let mine = Set(candidate.interests)
                let matching = catalog
                    .filter { Set($0.interestIDs).intersection(mine).count >= 2 }
                    .prefix(3)
                for entry in matching {
                    context.insert(CommunityMembership(communityID: entry.id, member: candidate))
                }
            }
        }

        try? context.save()
    }

    // MARK: - Queries

    static func approvedCommunities(in context: ModelContext) -> [Community] {
        let approved = CommunityState.approved.rawValue
        let descriptor = FetchDescriptor<Community>(
            predicate: #Predicate { $0.stateRaw == approved },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func pendingCommunities(in context: ModelContext) -> [Community] {
        let pending = CommunityState.pending.rawValue
        let descriptor = FetchDescriptor<Community>(
            predicate: #Predicate { $0.stateRaw == pending },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func memberships(of profile: UserProfile) -> [CommunityMembership] {
        profile.memberships.sorted { $0.joinedAt < $1.joinedAt }
    }

    static func isMember(_ profile: UserProfile, of communityID: String) -> Bool {
        profile.memberships.contains { $0.communityID == communityID }
    }

    /// The shared-community chip: at most one, and ONLY when both people
    /// are in it — showing someone's community to a non-member is a
    /// disclosure with no consent story.
    static func sharedCommunity(_ viewer: UserProfile?, _ other: UserProfile, in context: ModelContext) -> Community? {
        guard let viewer else { return nil }
        let mine = Set(viewer.memberships.map(\.communityID))
        guard let sharedID = other.memberships.first(where: { mine.contains($0.communityID) && $0.showsOnCard })?.communityID
        else { return nil }
        return approvedCommunities(in: context).first { $0.id == sharedID }
    }

    /// Interest overlap >= 2 surfaces a community — the Part 2 payoff:
    /// interests are the discovery substrate.
    static func suggested(for profile: UserProfile?, in context: ModelContext) -> [Community] {
        guard let profile else { return [] }
        let mine = Set(profile.interests)
        let joined = Set(profile.memberships.map(\.communityID))
        return approvedCommunities(in: context).filter { community in
            !joined.contains(community.id) &&
            Set(community.interestIDs).intersection(mine).count >= 2
        }
    }

    // MARK: - Join / leave

    /// Returns a user-facing (system-cased) refusal, or nil on success.
    @discardableResult
    static func join(_ community: Community, as profile: UserProfile, in context: ModelContext) -> String? {
        guard community.state == .approved else {
            return "This community is still waiting for approval."
        }
        guard !isMember(profile, of: community.id) else { return nil }
        guard profile.memberships.count < joinCap else {
            return "You can join up to \(joinCap) communities. Leave one to join another."
        }

        // Per-day rate limit (reach-farming brake).
        let defaults = UserDefaults.standard
        let today = dayKey(.now)
        if defaults.string(forKey: DefaultsKey.communityJoinsDay) != today {
            defaults.set(today, forKey: DefaultsKey.communityJoinsDay)
            defaults.set(0, forKey: DefaultsKey.communityJoinsCount)
        }
        let joinsToday = defaults.integer(forKey: DefaultsKey.communityJoinsCount)
        guard joinsToday < dailyJoinLimit else {
            return "That's a lot of joining for one day — try again tomorrow."
        }
        defaults.set(joinsToday + 1, forKey: DefaultsKey.communityJoinsCount)

        context.insert(CommunityMembership(communityID: community.id, member: profile))
        try? context.save()
        return nil
    }

    /// Instant, no confirmation, unlogged.
    static func leave(_ communityID: String, as profile: UserProfile, in context: ModelContext) {
        for membership in profile.memberships where membership.communityID == communityID {
            context.delete(membership)
        }
        try? context.save()
    }

    // MARK: - Creation + moderation

    /// A creation request: the community exists immediately but PENDING —
    /// invisible to everyone except its creator and the admin panel until
    /// a human approves it.
    @discardableResult
    static func requestCreation(
        name: String,
        summary: String,
        symbolName: String,
        tintToken: String,
        interestIDs: [String],
        in context: ModelContext
    ) -> Community? {
        let cleanName = String(
            name.lowercased()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
                .prefix(maxNameLength)
        )
        let cleanSummary = String(
            summary.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
                .prefix(maxSummaryLength)
        )
        guard !cleanName.isEmpty, tintTokens[tintToken] != nil else { return nil }

        let community = Community(
            id: UUID().uuidString,
            name: cleanName,
            summary: cleanSummary,
            symbolName: symbolName,
            tintToken: tintToken,
            interestIDs: interestIDs,
            isCurated: false,
            sortIndex: catalog.count + 1,
            state: .pending,
            createdByCurrentUser: true
        )
        context.insert(community)
        try? context.save()
        return community
    }

    static func approve(_ community: Community, in context: ModelContext) {
        community.state = .approved
        try? context.save()
    }

    /// Rejection deletes the row (and any premature memberships) — a
    /// rejected name must not linger anywhere.
    static func reject(_ community: Community, in context: ModelContext) {
        let id = community.id
        let memberships = (try? context.fetch(
            FetchDescriptor<CommunityMembership>(predicate: #Predicate { $0.communityID == id })
        )) ?? []
        for membership in memberships {
            context.delete(membership)
        }
        context.delete(community)
        try? context.save()
    }

    // MARK: - Erasure

    /// Called from AccountEraser: the account's memberships cascade with
    /// the profile row, but its created communities (pending or approved)
    /// are top-level rows that must go explicitly.
    static func eraseUserCreated(in context: ModelContext) {
        let created = (try? context.fetch(
            FetchDescriptor<Community>(predicate: #Predicate { $0.createdByCurrentUser })
        )) ?? []
        for community in created {
            reject(community, in: context)  // Also clears memberships.
        }
        UserDefaults.standard.removeObject(forKey: DefaultsKey.communityJoinsDay)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.communityJoinsCount)
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
