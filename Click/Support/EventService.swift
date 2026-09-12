//
//  EventService.swift
//  Click
//
//  The holiday event SYSTEM (MEGA-BRIEF P3), not a Halloween screen:
//  events are data (EventDefinition), progress is a registered @Model,
//  and this enum is the single place that decides whether an event is
//  live — no view computes a window.
//
//  The wheel is built the lawful way (owner decision):
//  - entries are EARNED, never purchased (one per local event day, plus
//    one per daily-reward claim during the event) — no coin price, no
//    IAP, so it is not a loot box;
//  - rewards are cosmetics and boosters only — NEVER coins (arbitrage
//    against the store), NEVER dating visibility;
//  - the outcome is FIXED when the entry is spent; the animation only
//    reveals it, and there is no engineered near-miss;
//  - odds are published (oddsTable) and a unit test asserts the table
//    matches the pool;
//  - deterministic pity: the top reward is guaranteed by entry N.
//

import Foundation
import SwiftData

/// A holiday event, defined as data. Codable so the catalogue can move
/// to JSON / a remote URL without touching call sites.
struct EventDefinition: Codable, Identifiable {
    let id: String
    /// Lowercase — Click draws it.
    let title: String
    let symbolName: String
    let tintToken: String
    /// UTC window.
    let startsAt: Date
    let endsAt: Date
    /// Weighted pool, encoded with the BingoReward codec. NO coins.
    let pool: [String]
    /// The pity target: guaranteed by `pityBy` spins if not yet owned.
    let topRewardID: String
    let pityBy: Int
}

@Model
final class EventProgress {
    @Attribute(.unique) var eventID: String
    var entries: Int = 0
    var spins: Int = 0
    var lastDailyGrantKey: String? = nil
    var popupShown: Bool = false

    init(eventID: String) {
        self.eventID = eventID
    }
}

@MainActor
enum EventService {

    /// The catalogue. New holidays are new entries — zero logic changes.
    static let catalog: [EventDefinition] = [
        EventDefinition(
            id: "halloween-2026",
            title: "spooky season",
            symbolName: "moon.stars.fill",
            tintToken: "brandOrange",
            startsAt: utcDate(2026, 10, 24),
            endsAt: utcDate(2026, 11, 2),
            pool: [
                BingoReward.cosmetic("pumpkin-frame").encoded,      // 1 - top
                BingoReward.cosmetic("midnight-frame").encoded,     // 2
                BingoReward.cosmetic("midnight-frame").encoded,
                BingoReward.cosmetic("ember-ring").encoded,         // 2
                BingoReward.cosmetic("ember-ring").encoded,
                BingoReward.cosmetic("phantom-ring").encoded,       // 1
                BingoReward.booster(.boost).encoded,                // 2
                BingoReward.booster(.boost).encoded,
                BingoReward.booster(.superChat).encoded,            // 1
                BingoReward.booster(.bulkChat).encoded              // 1
            ],
            topRewardID: "pumpkin-frame",
            pityBy: 8
        )
    ]

    /// Published odds for the active pool — the odds sheet renders this,
    /// and a unit test asserts it matches `pool` exactly.
    static let halloweenOddsTable: [(label: String, chance: String)] = [
        ("pumpkin frame", "1 in 10"),
        ("midnight frame", "2 in 10"),
        ("ember ring", "2 in 10"),
        ("phantom ring", "1 in 10"),
        ("1 boost", "2 in 10"),
        ("1 super chat", "1 in 10"),
        ("1 bulk chat", "1 in 10")
    ]

    static func activeEvent(at date: Date = .now) -> EventDefinition? {
        catalog.first { $0.startsAt <= date && date < $0.endsAt }
    }

    static func progress(for event: EventDefinition, in context: ModelContext) -> EventProgress {
        let id = event.id
        if let existing = try? context.fetch(FetchDescriptor<EventProgress>(
            predicate: #Predicate { $0.eventID == id }
        )).first {
            return existing
        }
        let fresh = EventProgress(eventID: id)
        context.insert(fresh)
        try? context.save()
        return fresh
    }

    /// One free entry per local day of the event. Called on foreground.
    static func grantDailyEntryIfDue(in context: ModelContext) {
        guard let event = activeEvent() else { return }
        let progress = progress(for: event, in: context)
        let key = BingoView.dateKey(for: .now)
        guard progress.lastDailyGrantKey != key else { return }
        progress.lastDailyGrantKey = key
        progress.entries += 1
        try? context.save()

        // A real, dated ending — schedule the honest reminder once.
        NotificationService.scheduleEventEnding(title: event.title, endsAt: event.endsAt)
    }

    /// An extra entry for a genuine in-app action during the event
    /// (daily-reward claims call this).
    static func grantActionEntry(in context: ModelContext) {
        guard let event = activeEvent() else { return }
        let progress = progress(for: event, in: context)
        progress.entries += 1
        try? context.save()
    }

    /// Spend one entry. The outcome is decided HERE, before any
    /// animation, deterministically (event + spin index + install salt):
    /// the wheel can only reveal it. Duplicate cosmetics become a boost
    /// (stated in the odds sheet). Pity: the top reward is forced by
    /// `pityBy` spins if still unowned.
    static func spin(event: EventDefinition, in context: ModelContext) -> BingoReward? {
        let progress = progress(for: event, in: context)
        guard progress.entries > 0 else { return nil }
        progress.entries -= 1
        progress.spins += 1

        let wallet = Wallet.ensure(in: context)
        var reward: BingoReward

        if progress.spins >= event.pityBy && !wallet.ownedCosmetics.contains(event.topRewardID) {
            reward = .cosmetic(event.topRewardID)
        } else {
            let seed = BingoView.installSalt
                ^ UInt64(bitPattern: Int64(event.id.hashValue))
                ^ UInt64(progress.spins) &* 0x9E3779B97F4A7C15
            var generator = SeededGenerator(seed: seed)
            let encoded = event.pool.randomElement(using: &generator) ?? event.pool[0]
            reward = BingoReward(encoded: encoded) ?? .booster(.boost)
        }

        // Duplicates convert to a boost — never a dead spin.
        if case .cosmetic(let id) = reward, wallet.ownedCosmetics.contains(id) {
            reward = .booster(.boost)
        }

        grant(reward, to: wallet, in: context)
        try? context.save()
        return reward
    }

    private static func grant(_ reward: BingoReward, to wallet: Wallet, in context: ModelContext) {
        switch reward {
        case .coins(let value):
            // The pool never contains coins; kept total for codec safety.
            wallet.coins += value
        case .booster(let kind):
            BoosterInventory.ensure(kind, in: context).count += 1
        case .cosmetic(let id):
            if !wallet.ownedCosmetics.contains(id) {
                wallet.ownedCosmetics.append(id)
            }
        }
    }

    /// Erasure: event progress is account data.
    static func eraseProgress(in context: ModelContext) {
        for progress in (try? context.fetch(FetchDescriptor<EventProgress>())) ?? [] {
            context.delete(progress)
        }
    }

    private static func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components) ?? .distantPast
    }
}
