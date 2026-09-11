//
//  ClickTests.swift
//  Click
//

import Testing
import Foundation
import SwiftData
@testable import Click

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
        #expect(firstCount > 20, "Expected the seeded candidate deck")

        // Seeding again must be a no-op.
        MockData.seedIfNeeded(context)
        let secondCount = try context.fetchCount(FetchDescriptor<UserProfile>())
        #expect(secondCount == firstCount)
    }

    @Test func seedingDoesNotCreateACurrentUser() throws {
        // Onboarding owns the current-user row; seeding must never make one.
        let context = try makeContext()
        MockData.seedIfNeeded(context)

        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.isCurrentUser }
        )
        #expect(try context.fetchCount(descriptor) == 0)
    }

    @Test func everySeededCandidateHasAGender() throws {
        // The seeking filter needs this or profiles silently vanish.
        let context = try makeContext()
        MockData.seedIfNeeded(context)

        let all = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(all.allSatisfy { $0.gender != nil })
    }

    @Test func ageGateComputesFromBirthDate() throws {
        let calendar = Calendar.current
        let seventeen = calendar.date(byAdding: .year, value: -17, to: .now)!
        let eighteen = calendar.date(byAdding: .year, value: -18, to: .now)!

        #expect(UserProfile.age(from: seventeen) < 18)
        #expect(UserProfile.age(from: eighteen) >= 18)
    }

    @Test func seekingPreferenceFiltersByGender() {
        #expect(SeekingPreference.men.includes(.man))
        #expect(!SeekingPreference.men.includes(.woman))
        #expect(SeekingPreference.women.includes(.woman))
        #expect(!SeekingPreference.women.includes(.nonBinary))
        for gender in Gender.allCases {
            #expect(SeekingPreference.everyone.includes(gender))
        }
    }

    @Test func bingoBoardIsDeterministicPerDay() {
        let a = BingoView.generateRewards(dateKey: "2026-09-12")
        let b = BingoView.generateRewards(dateKey: "2026-09-12")
        let c = BingoView.generateRewards(dateKey: "2026-09-13")
        #expect(a == b, "Same day must produce the same board — no re-rolls")
        #expect(a != c, "Different days should differ")
        #expect(a.count == 9)
        #expect(a.allSatisfy { BingoReward(encoded: $0) != nil })
    }

    @Test func bingoRewardPoolMatchesPublishedOdds() {
        // Guideline 3.1.1: the odds we show must be the odds we use.
        let rewards = BingoView.generateRewards(dateKey: "2026-01-01")
            .compactMap(BingoReward.init(encoded:))
        #expect(rewards.filter { $0 == .coins(10) }.count == 3)
        #expect(rewards.filter { $0 == .coins(20) }.count == 2)
        #expect(rewards.filter { $0 == .coins(40) }.count == 1)
        #expect(rewards.filter { $0 == .booster(.boost) }.count == 1)
        #expect(rewards.filter { $0 == .booster(.reveal) }.count == 1)
        #expect(rewards.filter { $0 == .booster(.superChat) }.count == 1)
    }

    @Test func accountEraserRemovesEveryUserTrace() throws {
        let context = try makeContext()
        MockData.seedIfNeeded(context)

        let me = UserProfile(name: "Someone", age: 20, isCurrentUser: true)
        me.ownerProviderID = "user-a"
        context.insert(me)
        context.insert(ProfilePhoto(data: Data([0x01]), sortIndex: 0, owner: me))
        context.insert(Match(profile: me))
        context.insert(Wallet(coins: 50))
        try context.save()

        AccountEraser.eraseCurrentAccount(in: context)

        let currentUsers = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.isCurrentUser })
        #expect(try context.fetchCount(currentUsers) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ProfilePhoto>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Conversation>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Message>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Match>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Wallet>()) == 0)
        // Candidates are demo content and must survive.
        let candidates = FetchDescriptor<UserProfile>(predicate: #Predicate { !$0.isCurrentUser })
        #expect(try context.fetchCount(candidates) > 20)
    }

    @Test func photosStayOrderedBySortIndex() throws {
        let context = try makeContext()
        let profile = UserProfile(name: "Test Person", age: 20)
        context.insert(profile)

        for index in [2, 0, 1] {
            context.insert(ProfilePhoto(data: Data([0xFF]), sortIndex: index, owner: profile))
        }
        try context.save()

        #expect(profile.orderedPhotos.map(\.sortIndex) == [0, 1, 2])
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
