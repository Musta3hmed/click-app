//
//  Gamification.swift
//  Click
//
//  Currency, consumables and the daily login streak.
//

import Foundation
import SwiftData

@Model
final class BoosterInventory {
    @Attribute(.unique) var kindRaw: String
    var count: Int

    init(kind: BoosterKind, count: Int = 0) {
        self.kindRaw = kind.rawValue
        self.count = count
    }

    var kind: BoosterKind {
        get { BoosterKind(rawValue: kindRaw) ?? .boost }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class DailyReward {
    @Attribute(.unique) var day: Int
    var rewardLabel: String
    var coinValue: Int
    /// Set for days whose reward is a booster rather than coins.
    var boosterKindRaw: String?
    var isClaimed: Bool
    var claimedAt: Date?

    init(day: Int, rewardLabel: String, coinValue: Int, boosterKind: BoosterKind? = nil, isClaimed: Bool = false) {
        self.day = day
        self.rewardLabel = rewardLabel
        self.coinValue = coinValue
        self.boosterKindRaw = boosterKind?.rawValue
        self.isClaimed = isClaimed
        self.claimedAt = nil
    }

    var boosterKind: BoosterKind? {
        boosterKindRaw.flatMap(BoosterKind.init(rawValue:))
    }
}

/// Single-row wallet for the signed-in user.
/// New stored properties carry declared defaults so SwiftData lightweight
/// migration can open a store written by an older build instead of
/// throwing (which ClickApp turns into a launch crash).
@Model
final class Wallet {
    @Attribute(.unique) var id: String
    var coins: Int = 0
    var referralCodeUsed: String?
    /// Consecutive-day claim streak. A skipped day resets it.
    var currentStreak: Int = 0
    var lastClaimAt: Date?
    /// Simulated profile-view counter (fed faster while boosted).
    var profileViews: Int = 0
    /// Bulk message rate limit: at most one send per 24h.
    var lastBulkSendAt: Date? = nil
    /// Free super likes per day (allowance set by the subscription tier);
    /// after that they cost a booster.
    var lastFreeSuperLikeAt: Date? = nil
    var freeSuperLikesUsedToday: Int = 0
    /// Simulated subscription (no real billing). Declared default keeps
    /// lightweight migration working.
    var subscriptionTierRaw: String = SubscriptionTier.free.rawValue
    /// Simulated recurring benefits: monthly coin bonus (plus/gold) and
    /// the weekly free boost (gold).
    var lastMonthlyBonusAt: Date? = nil
    var lastWeeklyBoostAt: Date? = nil

    /// Completed daily-reward cycles (MEGA-BRIEF 4.3): cycle 1+ doubles
    /// the coin days, so day 30 is no longer identical to day 2.
    /// Declared default keeps lightweight migration working.
    var rewardCycle: Int = 0
    /// Highest streak milestone already granted (7/14/30) — reset when
    /// the streak breaks, so the climb can be earned again.
    var lastMilestoneGranted: Int = 0

    init(id: String = "primary", coins: Int = 0) {
        self.id = id
        self.coins = coins
        self.referralCodeUsed = nil
        self.currentStreak = 0
        self.lastClaimAt = nil
    }

    /// Day-1 economy unlock: without this the balance starts at 0, both
    /// sinks cost 25 and day-1 income is 5 — nothing is affordable.
    static let welcomeBonus = 50

    var subscriptionTier: SubscriptionTier {
        get { SubscriptionTier(rawValue: subscriptionTierRaw) ?? .free }
        set { subscriptionTierRaw = newValue.rawValue }
    }

    /// The single fetch-or-create path. Always goes through a fresh fetch —
    /// two views each lazily inserting from their own (possibly stale)
    /// @Query produced duplicate unique-key upserts that zeroed the balance.
    @MainActor
    static func ensure(in context: ModelContext) -> Wallet {
        if let existing = try? context.fetch(FetchDescriptor<Wallet>()).first {
            return existing
        }
        let fresh = Wallet(coins: welcomeBonus)
        context.insert(fresh)
        try? context.save()
        return fresh
    }
}

extension BoosterInventory {
    /// Fetch-or-create for a booster kind, so granting a reward can never
    /// silently vanish because a row was missing from an old store.
    @MainActor
    static func ensure(_ kind: BoosterKind, in context: ModelContext) -> BoosterInventory {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<BoosterInventory>(
            predicate: #Predicate { $0.kindRaw == raw }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let fresh = BoosterInventory(kind: kind)
        context.insert(fresh)
        return fresh
    }
}

/// One day's bingo board: nine face-down tiles, pick three, pay once to
/// claim all three. Seeded deterministically from the date so force-quitting
/// can never re-roll it.
@Model
final class BingoBoard {
    /// "yyyy-MM-dd" — one board per calendar day.
    @Attribute(.unique) var dateKey: String
    /// Reward per tile, index 0–8. Encoded as "coins:25" / "booster:boost".
    var tileRewards: [String]
    var pickedIndexes: [Int]
    var isClaimed: Bool

    init(dateKey: String, tileRewards: [String]) {
        self.dateKey = dateKey
        self.tileRewards = tileRewards
        self.pickedIndexes = []
        self.isClaimed = false
    }
}

/// A decoded bingo tile reward.
enum BingoReward: Equatable {
    case coins(Int)
    case booster(BoosterKind)

    var encoded: String {
        switch self {
        case .coins(let value): "coins:\(value)"
        case .booster(let kind): "booster:\(kind.rawValue)"
        }
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "coins":
            guard let value = Int(parts[1]) else { return nil }
            self = .coins(value)
        case "booster":
            guard let kind = BoosterKind(rawValue: parts[1]) else { return nil }
            self = .booster(kind)
        default:
            return nil
        }
    }

    var label: String {
        switch self {
        case .coins(let value): "\(value) coins"
        case .booster(let kind): "1 \(kind.label)"
        }
    }
}
