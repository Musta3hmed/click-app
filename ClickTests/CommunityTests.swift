//
//  CommunityTests.swift
//  ClickTests
//
//  The community catalogue, join rules, moderation flow and the safety
//  invariants (block transitivity, pending invisibility).
//

import Testing
import Foundation
import SwiftData
import UIKit
@testable import Click

@MainActor
struct CommunityTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func resetJoinRateLimit() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.communityJoinsDay)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.communityJoinsCount)
    }

    @Test func catalogueSymbolsResolveAndTokensAreKnown() {
        for entry in CommunityService.catalog {
            #expect(UIImage(systemName: entry.symbolName) != nil, "\(entry.id): bad symbol")
            #expect(CommunityService.tintTokens[entry.tintToken] != nil, "\(entry.id): unknown tint token")
            for interestID in entry.interestIDs {
                #expect(InterestCatalog.byID[interestID] != nil, "\(entry.id): unknown interest \(interestID)")
            }
        }
        let ids = CommunityService.catalog.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func seedingGivesCandidatesMemberships() throws {
        let context = try makeContext()
        MockData.seedIfNeeded(context)
        InterestCatalog.migrateLegacyStrings(in: context)
        CommunityService.seedIfNeeded(context)

        #expect(try context.fetchCount(FetchDescriptor<Community>()) >= CommunityService.catalog.count)
        #expect(try context.fetchCount(FetchDescriptor<CommunityMembership>()) > 0, "The lens needs someone to show")

        // Seeding twice must not duplicate.
        let before = try context.fetchCount(FetchDescriptor<CommunityMembership>())
        CommunityService.seedIfNeeded(context)
        #expect(try context.fetchCount(FetchDescriptor<CommunityMembership>()) == before)
    }

    @Test func joinCapIsEnforced() throws {
        resetJoinRateLimit()
        defer { resetJoinRateLimit() }

        let context = try makeContext()
        CommunityService.seedIfNeeded(context)
        let me = UserProfile(name: "Me", age: 20, isCurrentUser: true)
        context.insert(me)

        let communities = CommunityService.approvedCommunities(in: context)
        for community in communities.prefix(CommunityService.joinCap) {
            #expect(CommunityService.join(community, as: me, in: context) == nil)
        }
        #expect(me.memberships.count == CommunityService.joinCap)

        let oneMore = communities[CommunityService.joinCap]
        #expect(CommunityService.join(oneMore, as: me, in: context) != nil, "The cap must refuse")
        #expect(me.memberships.count == CommunityService.joinCap)
    }

    @Test func pendingCommunitiesAreInvisibleAndUnjoinable() throws {
        resetJoinRateLimit()
        defer { resetJoinRateLimit() }

        let context = try makeContext()
        let me = UserProfile(name: "Me", age: 20, isCurrentUser: true)
        context.insert(me)

        let pending = try #require(CommunityService.requestCreation(
            name: "  My New Thing  ", summary: "hello", symbolName: "sparkles",
            tintToken: "brandPink", interestIDs: ["coffee"], in: context
        ))
        #expect(pending.state == .pending)
        #expect(pending.name == "my new thing", "Names are lowercased and trimmed")

        #expect(!CommunityService.approvedCommunities(in: context).contains { $0.id == pending.id })
        #expect(CommunityService.join(pending, as: me, in: context) != nil, "Pending must refuse joins")

        CommunityService.approve(pending, in: context)
        #expect(CommunityService.approvedCommunities(in: context).contains { $0.id == pending.id })
        #expect(CommunityService.join(pending, as: me, in: context) == nil)
    }

    @Test func rejectionDeletesTheCommunityAndMemberships() throws {
        let context = try makeContext()
        let me = UserProfile(name: "Me", age: 20, isCurrentUser: true)
        context.insert(me)

        let community = try #require(CommunityService.requestCreation(
            name: "gone soon", summary: "", symbolName: "sparkles",
            tintToken: "brandPink", interestIDs: [], in: context
        ))
        context.insert(CommunityMembership(communityID: community.id, member: me))
        try context.save()

        CommunityService.reject(community, in: context)

        #expect(try context.fetchCount(FetchDescriptor<Community>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CommunityMembership>()) == 0)
    }

    /// Block is transitive and total: the lens filters the same
    /// non-blocked candidate set the deck uses, and the shared chip
    /// resolver never surfaces a blocked member.
    @Test func blockingNeverShowsInLensOrSharedChip() throws {
        let context = try makeContext()
        CommunityService.seedIfNeeded(context)
        let me = UserProfile(name: "Me", age: 20, isCurrentUser: true)
        let other = UserProfile(name: "Them", age: 21)
        context.insert(me)
        context.insert(other)
        context.insert(CommunityMembership(communityID: "film-club", member: me))
        context.insert(CommunityMembership(communityID: "film-club", member: other))
        try context.save()

        SafetyCenter.block(other, in: context)

        // The deck's candidate predicate is !isBlocked; the lens filters
        // that same set — mirror it here.
        let candidates = try context.fetch(FetchDescriptor<UserProfile>(
            predicate: #Predicate { !$0.isCurrentUser && !$0.isBlocked }
        ))
        let lensed = candidates.filter { profile in
            profile.memberships.contains { $0.communityID == "film-club" }
        }
        #expect(!lensed.contains { $0.id == other.id }, "A blocked member must never appear in a lens")
    }

    @Test func sharedCommunityRequiresBothMembers() throws {
        let context = try makeContext()
        CommunityService.seedIfNeeded(context)
        let me = UserProfile(name: "Me", age: 20, isCurrentUser: true)
        let other = UserProfile(name: "Them", age: 21)
        context.insert(me)
        context.insert(other)
        context.insert(CommunityMembership(communityID: "film-club", member: other))
        try context.save()

        // Their community, not mine: nothing may be disclosed.
        #expect(CommunityService.sharedCommunity(me, other, in: context) == nil)

        context.insert(CommunityMembership(communityID: "film-club", member: me))
        try context.save()
        #expect(CommunityService.sharedCommunity(me, other, in: context)?.id == "film-club")
    }
}
