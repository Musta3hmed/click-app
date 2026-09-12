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
        #expect(rewards.filter { $0 == .booster(.bulkChat) }.count == 1)
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

        // Community traces: a membership and a user-created community.
        CommunityService.seedIfNeeded(context)
        context.insert(CommunityMembership(communityID: "film-club", member: me))
        _ = CommunityService.requestCreation(
            name: "my thing", summary: "", symbolName: "sparkles",
            tintToken: "brandPink", interestIDs: [], in: context
        )

        // Behavioural data on candidate rows must not survive either.
        let candidateDescriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { !$0.isCurrentUser }
        )
        let someCandidate = try #require(try context.fetch(candidateDescriptor).first)
        SafetyCenter.block(someCandidate, in: context)
        try context.save()

        AccountEraser.eraseCurrentAccount(in: context)

        #expect(!someCandidate.isBlocked, "The next account must not inherit the previous user's blocklist")
        #expect(!someCandidate.isMuted)

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

        // The account's memberships cascade with the profile row; its
        // created communities are removed explicitly. Candidate
        // memberships (demo content) survive.
        let myMemberships = try context.fetch(FetchDescriptor<CommunityMembership>())
        #expect(myMemberships.allSatisfy { $0.member?.isCurrentUser != true })
        let created = FetchDescriptor<Community>(predicate: #Predicate { $0.createdByCurrentUser })
        #expect(try context.fetchCount(created) == 0, "User-created communities must not survive erasure")
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

    // MARK: - Phase 4

    @Test func zodiacDerivesFromBirthDate() {
        var components = DateComponents()
        components.year = 2000

        func date(month: Int, day: Int) -> Date {
            components.month = month
            components.day = day
            return Calendar.current.date(from: components)!
        }

        #expect(Zodiac.from(birthDate: date(month: 3, day: 21)) == .aries)
        #expect(Zodiac.from(birthDate: date(month: 4, day: 19)) == .aries)
        #expect(Zodiac.from(birthDate: date(month: 4, day: 20)) == .taurus)
        #expect(Zodiac.from(birthDate: date(month: 8, day: 1)) == .leo)
        #expect(Zodiac.from(birthDate: date(month: 12, day: 25)) == .capricorn)
        #expect(Zodiac.from(birthDate: date(month: 1, day: 19)) == .capricorn)
        #expect(Zodiac.from(birthDate: date(month: 1, day: 20)) == .aquarius)
        #expect(Zodiac.from(birthDate: date(month: 3, day: 1)) == .pisces)
    }

    @Test func welcomeBonusGrantedOnWalletCreation() throws {
        let context = try makeContext()
        let wallet = Wallet.ensure(in: context)
        #expect(wallet.coins == Wallet.welcomeBonus, "Day-1 economy needs the welcome bonus")

        // ensure() must not grant twice.
        let again = Wallet.ensure(in: context)
        #expect(again.coins == Wallet.welcomeBonus)
    }

    @Test func boostActivationConsumesInventoryAndCaps() throws {
        let context = try makeContext()
        let me = UserProfile(name: "Someone", age: 20, isCurrentUser: true)
        context.insert(me)

        // No inventory: activation fails, nothing changes.
        #expect(!Boost.activate(for: me, in: context))
        #expect(me.boostedUntil == nil)

        BoosterInventory.ensure(.boost, in: context).count = 3
        #expect(Boost.activate(for: me, in: context))
        let first = try #require(me.boostedUntil)
        #expect(first.timeIntervalSinceNow > 29 * 60)

        // Re-use extends but is capped at 2x duration from now.
        #expect(Boost.activate(for: me, in: context))
        #expect(Boost.activate(for: me, in: context))
        let capped = try #require(me.boostedUntil)
        #expect(capped.timeIntervalSinceNow <= 60 * 60 + 1)
        #expect(BoosterInventory.ensure(.boost, in: context).count == 0)
    }

    @Test func boostWidensLikesYouBackRate() {
        let names = (0..<200).map { "Person \($0)" }
        let normal = names.filter {
            Boost.likesYouBack(UserProfile(name: $0, age: 20), boosted: false)
        }.count
        let boosted = names.filter {
            Boost.likesYouBack(UserProfile(name: $0, age: 20), boosted: true)
        }.count
        #expect(boosted > normal, "Boost should widen the mock match rate")
    }

    @Test func legacyRequestRowsReadAsPending() throws {
        // Phase-3 rows predate request states: incoming-only .requests rows
        // must get the accept/deny flow.
        let context = try makeContext()
        let profile = UserProfile(name: "Test Person", age: 20)
        context.insert(profile)

        let legacy = Conversation(participant: profile, folder: .requests)
        context.insert(legacy)
        context.insert(Message(text: "hi", isFromMe: false, conversation: legacy))
        try context.save()
        #expect(legacy.isPendingRequest)

        // A row the user already replied to is not pending.
        context.insert(Message(text: "hey", isFromMe: true, conversation: legacy))
        try context.save()
        #expect(!legacy.isPendingRequest)

        // Denied/accepted rows never re-enter the flow.
        let accepted = Conversation(participant: profile, folder: .requests, requestState: .accepted)
        context.insert(accepted)
        #expect(!accepted.isPendingRequest)
    }

    @Test func superLikeRequestsAreSeeded() throws {
        let context = try makeContext()
        MockData.seedIfNeeded(context)

        let pendingRaw = RequestState.pending.rawValue
        let pending = try context.fetch(FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.isSuperLike && $0.requestStateRaw == pendingRaw }
        ))
        #expect(pending.count >= 2, "The accept/deny flow needs seeded requests to exercise")
        #expect(pending.allSatisfy { $0.folder == .requests })

        // Seeding again must not stack more.
        MockData.seedIfNeeded(context)
        let after = try context.fetch(FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.isSuperLike && $0.requestStateRaw == pendingRaw }
        ))
        #expect(after.count == pending.count)
    }

    @Test func messageSeedsWaitForFirstLike() throws {
        let context = try makeContext()
        MockData.seedIfNeeded(context)

        // Before any like: only super-like requests exist, no .messages
        // conversations — the "no chats yet" state can actually appear.
        let messagesRaw = ChatFolder.messages.rawValue
        let messageThreads = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.folderRaw == messagesRaw }
        )
        #expect(try context.fetchCount(messageThreads) == 0)

        // After a like, the next seeding pass delivers the demo chats.
        let candidate = try #require(try context.fetch(
            FetchDescriptor<UserProfile>(predicate: #Predicate { !$0.isCurrentUser })
        ).first)
        context.insert(Match(profile: candidate))
        try context.save()
        MockData.seedIfNeeded(context)
        #expect(try context.fetchCount(messageThreads) > 0)
    }
}
