//
//  Boost.swift
//  Click
//
//  Boost is an HONEST local simulation — there is no backend, so copy must
//  never claim real reach ("boost active - 24m left", not "more people see
//  you"). While boosted: the mock likes-you-back rate widens, the
//  profile-view counter ticks faster, and up to two extra super-like
//  requests can arrive.
//

import Foundation
import SwiftData

@MainActor
enum Boost {

    static let duration: TimeInterval = 30 * 60

    /// Consume one boost from inventory and extend the window. Re-use
    /// extends from max(now, boostedUntil), capped at 2x duration; a clock
    /// rollback can never strand a years-long boost.
    static func activate(for profile: UserProfile, in context: ModelContext) -> Bool {
        let inventory = BoosterInventory.ensure(.boost, in: context)
        guard inventory.count > 0 else { return false }
        inventory.count -= 1

        let now = Date.now
        let base = max(now, profile.boostedUntil ?? .distantPast)
        let capped = min(base.addingTimeInterval(duration), now.addingTimeInterval(2 * duration))
        profile.boostedUntil = capped
        try? context.save()
        return true
    }

    /// Mock likes-you-back: stable per profile; ~50% normally, ~67% while
    /// boosted. Boost state is passed in — commit() must not fetch.
    static func likesYouBack(_ profile: UserProfile, boosted: Bool) -> Bool {
        let hash = Theme.stableHash(profile.name)
        return boosted ? hash % 3 != 0 : hash % 2 == 0
    }

    /// Runs when the app comes to the foreground: ticks the simulated
    /// profile-view counter (faster while boosted) and, while boosted,
    /// seeds up to 2 extra pending super-like requests from candidates
    /// the user has no conversation with (blocked/seeking respected).
    static func foregroundTick(in context: ModelContext) {
        let currentUsers = (try? context.fetch(
            FetchDescriptor<UserProfile>(predicate: #Predicate { $0.isCurrentUser })
        )) ?? []
        guard let me = currentUsers.first(where: { !$0.isDeleted }) else { return }

        // Clock-rollback clamp.
        if let until = me.boostedUntil, until > Date.now.addingTimeInterval(2 * duration) {
            me.boostedUntil = Date.now.addingTimeInterval(duration)
        }

        let boosted = me.isBoosted
        let wallet = Wallet.ensure(in: context)
        wallet.profileViews += boosted ? Int.random(in: 5...10) : Int.random(in: 1...3)

        grantSubscriptionBenefits(to: wallet, in: context)

        if boosted {
            seedBoostRequestIfRoom(for: me, in: context)
        }
        try? context.save()
    }

    /// Simulated recurring subscription benefits: monthly bonus coins on
    /// plus/gold, plus a weekly free boost on gold. Idempotent per window.
    private static func grantSubscriptionBenefits(to wallet: Wallet, in context: ModelContext) {
        let tier = wallet.subscriptionTier
        guard tier != .free else { return }
        let now = Date.now

        let month: TimeInterval = 30 * 24 * 60 * 60
        if let last = wallet.lastMonthlyBonusAt {
            if now.timeIntervalSince(last) >= month {
                wallet.coins += tier.signupBonusCoins
                wallet.lastMonthlyBonusAt = now
            }
        } else {
            // Anchor the window at upgrade time (the sign-up bonus already
            // covered this month).
            wallet.lastMonthlyBonusAt = now
        }

        if tier == .gold {
            let week: TimeInterval = 7 * 24 * 60 * 60
            let due = wallet.lastWeeklyBoostAt.map { now.timeIntervalSince($0) >= week } ?? true
            if due {
                BoosterInventory.ensure(.boost, in: context).count += 1
                wallet.lastWeeklyBoostAt = now
            }
        }
    }

    /// At most 2 pending requests whose activity falls inside the current
    /// boost window.
    private static func seedBoostRequestIfRoom(for me: UserProfile, in context: ModelContext) {
        guard let until = me.boostedUntil else { return }
        let windowStart = until.addingTimeInterval(-2 * duration)

        let pendingRaw = RequestState.pending.rawValue
        let pending = (try? context.fetch(FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.requestStateRaw == pendingRaw }
        ))) ?? []
        guard pending.filter({ $0.lastActivity >= windowStart }).count < 2 else { return }

        let candidates = (try? context.fetch(FetchDescriptor<UserProfile>(
            predicate: #Predicate { !$0.isCurrentUser && !$0.isBlocked }
        ))) ?? []
        let conversations = (try? context.fetch(FetchDescriptor<Conversation>())) ?? []
        let taken = Set(conversations.compactMap { $0.participant?.id })

        let seeking = me.seeking
        let eligible = candidates.filter { candidate in
            guard !taken.contains(candidate.id) else { return false }
            guard !seeking.isEmpty, !seeking.contains(.everyone) else { return true }
            guard let gender = candidate.gender else { return false }
            return seeking.contains { $0.includes(gender) }
        }
        guard let profile = eligible.randomElement() else { return }

        let openers = [
            "saw you pop up and had to say hi",
            "ok your profile is my whole vibe",
            "this felt worth a super like"
        ]
        let conversation = Conversation(
            participant: profile,
            folder: .requests,
            lastActivity: .now,
            unreadCount: 1,
            isSuperLike: true,
            requestState: .pending
        )
        context.insert(conversation)
        context.insert(Message(
            text: openers.randomElement() ?? openers[0],
            isFromMe: false,
            conversation: conversation
        ))
    }
}
