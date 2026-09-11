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
@Model
final class Wallet {
    @Attribute(.unique) var id: String
    var coins: Int
    var referralCodeUsed: String?
    /// Consecutive-day claim streak. A skipped day resets it.
    var currentStreak: Int
    var lastClaimAt: Date?

    init(id: String = "primary", coins: Int = 0) {
        self.id = id
        self.coins = coins
        self.referralCodeUsed = nil
        self.currentStreak = 0
        self.lastClaimAt = nil
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
