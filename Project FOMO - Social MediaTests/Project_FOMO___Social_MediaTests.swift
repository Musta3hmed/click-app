//
//  Project_FOMO___Social_MediaTests.swift
//  Click
//

import Testing
import Foundation
import SwiftData
@testable import Project_FOMO___Social_Media

@MainActor
struct ClickModelTests {

    /// Fresh in-memory store per test.
    private func makeContext() throws -> ModelContext {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func seedingPopulatesTheStoreOnce() throws {
        let context = try makeContext()

        MockData.seedIfNeeded(context)
        let firstCount = try context.fetchCount(FetchDescriptor<UserProfile>())
        #expect(firstCount > 20, "Expected the seeded deck plus the current user")

        // Seeding again must be a no-op.
        MockData.seedIfNeeded(context)
        let secondCount = try context.fetchCount(FetchDescriptor<UserProfile>())
        #expect(secondCount == firstCount)
    }

    @Test func exactlyOneCurrentUserIsSeeded() throws {
        let context = try makeContext()
        MockData.seedIfNeeded(context)

        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.isCurrentUser }
        )
        #expect(try context.fetchCount(descriptor) == 1)
    }

    @Test func blockingHidesTheConversation() throws {
        let context = try makeContext()
        let profile = UserProfile(name: "Test Person", age: 20)
        let conversation = Conversation(participant: profile)
        context.insert(profile)
        context.insert(conversation)

        #expect(conversation.isVisible)

        SafetyCenter.block(profile, in: context)

        #expect(profile.isBlocked)
        #expect(profile.isMuted, "Blocking should also silence notifications")
        #expect(!conversation.isVisible)
    }

    @Test func reportingRecordsReasonAndCanBlock() throws {
        let context = try makeContext()
        let profile = UserProfile(name: "Test Person", age: 20)
        context.insert(profile)

        SafetyCenter.report(profile, reason: .spam, alsoBlock: false, in: context)

        #expect(profile.isReported)
        #expect(profile.reportedReasonRaw == ReportReason.spam.rawValue)
        #expect(!profile.isBlocked, "alsoBlock was false")
    }

    @Test func muteTogglesBothWays() throws {
        let context = try makeContext()
        let profile = UserProfile(name: "Test Person", age: 20)
        context.insert(profile)

        SafetyCenter.toggleMute(profile, in: context)
        #expect(profile.isMuted)

        SafetyCenter.toggleMute(profile, in: context)
        #expect(!profile.isMuted)
    }

    @Test func zodiacRoundTripsThroughRawValue() throws {
        let profile = UserProfile(name: "Test Person", age: 20, zodiac: .scorpio)
        #expect(profile.zodiac == .scorpio)

        profile.zodiac = .leo
        #expect(profile.zodiacRaw == "leo")
    }
}
