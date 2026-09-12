//
//  InterestTests.swift
//  ClickTests
//
//  The interest catalogue, migration, matching and deck-filter fallback.
//

import Testing
import Foundation
import SwiftData
import UIKit
@testable import Click

@MainActor
struct InterestTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// A bad SF Symbol name renders as NOTHING, silently — CI catches it
    /// here instead.
    @Test func everyCatalogueSymbolResolves() {
        for interest in InterestCatalog.all {
            #expect(
                UIImage(systemName: interest.symbolName) != nil,
                "\(interest.id) has an unresolvable symbol '\(interest.symbolName)'"
            )
        }
    }

    @Test func catalogueIDsAreUniqueAndSlugShaped() {
        let ids = InterestCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate interest id")
        for id in ids {
            #expect(id == id.lowercased() && !id.contains(" "), "'\(id)' is not a canonical slug")
        }
    }

    /// Every legacy string phase-4 seed data used must map to a live
    /// catalogue entry — an unmapped one would vanish from profiles.
    @Test func everyLegacyStringMapsIntoTheCatalogue() {
        for (legacy, id) in InterestCatalog.legacyMap {
            #expect(
                InterestCatalog.byID[id] != nil,
                "Legacy '\(legacy)' maps to '\(id)', which is not in the catalogue"
            )
        }
    }

    @Test func seededInterestsAreAllCanonical() throws {
        let context = try makeContext()
        MockData.seedIfNeeded(context)

        let all = try context.fetch(FetchDescriptor<UserProfile>())
        for profile in all {
            for id in profile.interests {
                #expect(InterestCatalog.byID[id] != nil, "Seeded '\(id)' is not a canonical id")
            }
        }
    }

    @Test func sharedInterestsAndScoreAgree() throws {
        let context = try makeContext()
        let viewer = UserProfile(name: "Me", age: 20, isCurrentUser: true)
        viewer.interests = ["coffee", "films", "gym"]
        let other = UserProfile(name: "Them", age: 21)
        other.interests = ["films", "coffee", "travel"]
        context.insert(viewer)
        context.insert(other)

        let shared = InterestMatching.shared(viewer, other)
        // In THEIR order: films first, then coffee.
        #expect(shared.map(\.id) == ["films", "coffee"])
        #expect(InterestMatching.score(viewer, other) == 2)
        #expect(InterestMatching.sharedLine(viewer, other) == "you both like films and coffee")
        #expect(InterestMatching.shared(nil, other).isEmpty)
    }

    @Test func scoringReordersButNeverRemoves() throws {
        let context = try makeContext()
        let viewer = UserProfile(name: "Me", age: 20, isCurrentUser: true)
        viewer.interests = ["coffee"]
        let stranger = UserProfile(name: "A", age: 21)
        stranger.interests = ["travel"]
        let kindred = UserProfile(name: "B", age: 22)
        kindred.interests = ["coffee"]
        context.insert(viewer)
        context.insert(stranger)
        context.insert(kindred)

        let scored = DeckFilter.scored([stranger, kindred], viewer: viewer)
        #expect(scored.count == 2, "Scoring must never remove")
        #expect(scored.first?.name == "B", "Shared interests sort first")
    }

    @Test func interestFilterSupportsAnyAndAll() {
        let a = UserProfile(name: "A", age: 21)
        a.interests = ["coffee", "films"]
        let b = UserProfile(name: "B", age: 22)
        b.interests = ["coffee"]

        var criteria = DeckFilter.Criteria(
            minAge: 18, maxAge: 99, verifiedOnly: false,
            interests: ["coffee", "films"], matchAll: false
        )
        #expect(DeckFilter.apply(criteria, to: [a, b]).count == 2, "ANY: one shared pick is enough")

        criteria.matchAll = true
        let all = DeckFilter.apply(criteria, to: [a, b])
        #expect(all.count == 1 && all.first?.name == "A", "ALL: every pick required")
    }
}
