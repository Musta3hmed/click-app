//
//  Boost.swift
//  Click
//
//  Boost is an HONEST local simulation — there is no backend, so copy must
//  never claim real reach ("boost active - 24m left", not "more people see
//  you"). While boosted: the mock likes-you-back rate widens and the
//  SIMULATED profile-view counter ticks faster (every surface showing it
//  says simulated). Fabricated admirers are gone: seeding fake super-like
//  requests during a boost taught users that spending produces attention,
//  which is the harmful version of a demo — do not reintroduce it.
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
    /// profile-view counter (faster while boosted) and rotates the demo
    /// deck's online indicators.
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
        rotateOnlineStatus(in: context)
        try? context.save()
    }

    /// The seeded flag was assigned once and never changed — a third of
    /// the deck showed a green dot at 4am, forever. Deterministic per
    /// profile per hour: still demo data, but it breathes.
    private static func rotateOnlineStatus(in context: ModelContext) {
        let hourKey = Int(Date.now.timeIntervalSince1970 / 3600)
        let candidates = (try? context.fetch(FetchDescriptor<UserProfile>(
            predicate: #Predicate { !$0.isCurrentUser }
        ))) ?? []
        for candidate in candidates {
            candidate.isOnline = Theme.stableHash("\(candidate.name)#\(hourKey)") % 3 == 0
        }
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

}
