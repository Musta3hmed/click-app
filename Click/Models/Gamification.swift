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
    var isClaimed: Bool
    var claimedAt: Date?

    init(day: Int, rewardLabel: String, coinValue: Int, isClaimed: Bool = false) {
        self.day = day
        self.rewardLabel = rewardLabel
        self.coinValue = coinValue
        self.isClaimed = isClaimed
        self.claimedAt = nil
    }
}

/// Single-row wallet for the signed-in user.
@Model
final class Wallet {
    @Attribute(.unique) var id: String
    var coins: Int
    var isSubscriber: Bool
    var referralCodeUsed: String?

    init(id: String = "primary", coins: Int = 0, isSubscriber: Bool = false) {
        self.id = id
        self.coins = coins
        self.isSubscriber = isSubscriber
        self.referralCodeUsed = nil
    }
}

/// Non-persisted description of a coin bundle in the store.
struct CoinPack: Identifiable, Hashable {
    let id = UUID()
    let coins: Int
    let price: String
    let discountPercent: Int?

    static let catalog: [CoinPack] = [
        CoinPack(coins: 225, price: "$4.99", discountPercent: nil),
        CoinPack(coins: 475, price: "$9.99", discountPercent: 6),
        CoinPack(coins: 1_000, price: "$19.99", discountPercent: 10),
        CoinPack(coins: 2_750, price: "$49.99", discountPercent: 19)
    ]
}
