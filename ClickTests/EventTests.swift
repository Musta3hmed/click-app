//
//  EventTests.swift
//  ClickTests
//
//  The event wheel's compliance surface: published odds match the pool,
//  no coins in the pool, deterministic pity, duplicate conversion, and
//  entries are the only way to spin.
//

import Testing
import Foundation
import SwiftData
import UIKit
@testable import Click

@MainActor
struct EventTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private var halloween: EventDefinition {
        EventService.catalog.first { $0.id == "halloween-2026" }!
    }

    /// Guideline 3.1.1 as a build failure: the published table must match
    /// the pool exactly.
    @Test func publishedOddsMatchThePool() {
        let pool = halloween.pool.compactMap { BingoReward(encoded: $0) }
        #expect(pool.count == halloween.pool.count, "Every pool entry must decode")

        for row in EventService.halloweenOddsTable {
            let expected = Int(row.chance.split(separator: " ").first ?? "0") ?? 0
            let actual = pool.filter { $0.label == row.label }.count
            #expect(actual == expected, "\(row.label): table says \(expected) in 10, pool has \(actual)")
        }
        let tableTotal = EventService.halloweenOddsTable
            .compactMap { Int($0.chance.split(separator: " ").first ?? "0") }
            .reduce(0, +)
        #expect(tableTotal == pool.count, "Table rows must cover the whole pool")
    }

    /// A coin reward on a free wheel is arbitrage against the coin store
    /// and re-inflates an economy with no sink.
    @Test func poolContainsNoCoins() {
        for encoded in halloween.pool {
            if case .coins = BingoReward(encoded: encoded) {
                Issue.record("The wheel pool must never contain coins")
            }
        }
    }

    @Test func everyPoolCosmeticAndSymbolResolves() {
        for encoded in halloween.pool {
            if case .cosmetic(let id) = BingoReward(encoded: encoded) {
                let cosmetic = CosmeticCatalog.byID[id]
                #expect(cosmetic != nil, "Unknown cosmetic \(id)")
                if let cosmetic {
                    #expect(UIImage(systemName: cosmetic.symbolName) != nil)
                }
            }
        }
        #expect(UIImage(systemName: halloween.symbolName) != nil)
        #expect(CosmeticCatalog.byID[halloween.topRewardID] != nil)
    }

    @Test func spinConsumesEntriesAndStopsAtZero() throws {
        let context = try makeContext()
        let progress = EventService.progress(for: halloween, in: context)
        #expect(EventService.spin(event: halloween, in: context) == nil, "No entries, no spin")

        progress.entries = 2
        #expect(EventService.spin(event: halloween, in: context) != nil)
        #expect(EventService.spin(event: halloween, in: context) != nil)
        #expect(EventService.spin(event: halloween, in: context) == nil)
        #expect(progress.entries == 0)
    }

    /// Deterministic pity: by `pityBy` spins the top reward is owned.
    @Test func topRewardGuaranteedByPity() throws {
        let context = try makeContext()
        let progress = EventService.progress(for: halloween, in: context)
        progress.entries = halloween.pityBy

        for _ in 0..<halloween.pityBy {
            _ = EventService.spin(event: halloween, in: context)
        }
        let wallet = Wallet.ensure(in: context)
        #expect(
            wallet.ownedCosmetics.contains(halloween.topRewardID),
            "The top reward must be guaranteed within \(halloween.pityBy) spins"
        )
    }

    /// A duplicate cosmetic converts to a boost, never a dead spin.
    @Test func duplicateCosmeticBecomesABoost() throws {
        let context = try makeContext()
        let wallet = Wallet.ensure(in: context)
        // Own everything, so every cosmetic outcome is a duplicate.
        wallet.ownedCosmetics = CosmeticCatalog.all.map(\.id)
        let progress = EventService.progress(for: halloween, in: context)
        progress.entries = 5

        for _ in 0..<5 {
            let reward = EventService.spin(event: halloween, in: context)
            if case .cosmetic = reward {
                Issue.record("An owned cosmetic must convert to a booster")
            }
        }
    }

    @Test func dailyEntryGrantsOncePerDay() throws {
        let context = try makeContext()
        guard EventService.activeEvent() != nil else {
            // Outside the event window the grant is a no-op — nothing to test.
            return
        }
        EventService.grantDailyEntryIfDue(in: context)
        let progress = try #require(try context.fetch(FetchDescriptor<EventProgress>()).first)
        let after = progress.entries
        EventService.grantDailyEntryIfDue(in: context)
        #expect(progress.entries == after, "Only one free entry per local day")
    }
}
