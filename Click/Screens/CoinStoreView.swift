//
//  CoinStoreView.swift
//  Click
//
//  Coin packs behind the wallet's "+" button. Purchases are SIMULATED -
//  there is no billing backend, so tapping buy credits the coins and the
//  sheet says so plainly. Prices are placeholders.
//

import SwiftUI
import SwiftData

struct CoinPack: Identifiable {
    let id: Int
    let coins: Int
    let priceLabel: String
    let tag: String?

    static let all: [CoinPack] = [
        CoinPack(id: 1, coins: 100, priceLabel: "$1.99", tag: nil),
        CoinPack(id: 2, coins: 550, priceLabel: "$7.99", tag: "popular"),
        CoinPack(id: 3, coins: 1200, priceLabel: "$14.99", tag: nil),
        CoinPack(id: 4, coins: 3000, priceLabel: "$29.99", tag: "best value"),
    ]
}

struct CoinStoreView: View {
    /// Bumped on purchase so the wallet coin spins behind the sheet.
    @Binding var coinEarnTrigger: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.motion) private var motion

    @Query private var wallets: [Wallet]
    @State private var purchasedPackID: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metric.Space.xl) {
                    HStack(spacing: 10) {
                        CoinView(size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(wallets.first?.coins ?? 0) coins")
                                .font(.click(.title2, weight: .black))
                                .foregroundStyle(Theme.primary)
                                .contentTransition(.numericText())
                                .animation(motion.numeric, value: wallets.first?.coins ?? 0)
                            Text("spend them on boosters and bingo claims.")
                                .font(.clickPlain(.footnote, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                        }
                    }

                    VStack(spacing: Theme.Metric.Space.m) {
                        ForEach(CoinPack.all) { pack in
                            packRow(pack)
                        }
                    }

                    Label(
                        "demo build - tapping buy adds the coins instantly and no real payment is taken. Prices are placeholders.",
                        systemImage: "info.circle"
                    )
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.top, Theme.Metric.sheetTopInset)
                .padding(.bottom, Theme.Metric.Space.xxxl)
            }
            .background(Theme.background)
            .navigationTitle("get coins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                        .font(.click(.body, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func packRow(_ pack: CoinPack) -> some View {
        Button {
            buy(pack)
        } label: {
            HStack(spacing: 12) {
                CoinView(size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pack.coins) coins")
                        .font(.click(.headline, weight: .black))
                        .foregroundStyle(Theme.primary)
                    if let tag = pack.tag {
                        Text(tag)
                            .font(.click(.caption2, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.brandPink, in: Capsule())
                    }
                }
                Spacer()
                Text(purchasedPackID == pack.id ? "added" : pack.priceLabel)
                    .font(.click(.subheadline, weight: .black))
                    .foregroundStyle(purchasedPackID == pack.id ? Theme.online : Theme.onPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        purchasedPackID == pack.id ? Theme.surface : Theme.primary,
                        in: Capsule()
                    )
                    .contentTransition(.opacity)
            }
            .padding(Theme.Metric.gutter)
            .cardSurface(radius: Theme.Metric.control, elevated: true)
        }
        .buttonStyle(.click)
        .accessibilityLabel("Buy \(pack.coins) coins for \(pack.priceLabel). Demo purchase, no real charge.")
    }

    private func buy(_ pack: CoinPack) {
        let wallet = Wallet.ensure(in: context)
        wallet.coins += pack.coins
        try? context.save()
        coinEarnTrigger += 1
        Haptics.notify(.success)
        withAnimation(motion.state) { purchasedPackID = pack.id }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(motion.state) {
                if purchasedPackID == pack.id { purchasedPackID = nil }
            }
        }
    }
}

#Preview {
    CoinStoreView(coinEarnTrigger: .constant(0))
        .modelContainer(MockData.previewContainer)
}
