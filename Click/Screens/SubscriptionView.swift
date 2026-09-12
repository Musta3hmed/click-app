//
//  SubscriptionView.swift
//  Click
//
//  Three tiers - click (free), click+ and click gold. Subscriptions are
//  SIMULATED (no billing backend): upgrading switches the stored tier,
//  credits the sign-up bonus, and says so plainly. The one wired benefit
//  is the free-super-likes-per-day allowance.
//

import SwiftUI
import SwiftData

struct SubscriptionView: View {
    @Binding var coinEarnTrigger: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.motion) private var motion

    @Query private var wallets: [Wallet]
    @State private var confirmingTier: SubscriptionTier?

    private var currentTier: SubscriptionTier {
        wallets.first?.subscriptionTier ?? .free
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metric.Space.xl) {
                    Text("more clicks, more perks. pick your tier.")
                        .font(.clickPlain(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.secondary)

                    VStack(spacing: Theme.Metric.Space.m) {
                        ForEach(SubscriptionTier.allCases) { tier in
                            tierCard(tier)
                        }
                    }

                    Label(
                        "demo build - upgrading is simulated and no real payment is taken. Prices are placeholders.",
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
            .navigationTitle("upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                        .font(.click(.body, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .accessibilityLabel("Done")
                }
            }
            .confirmationDialog(
                "Switch to \(confirmingTier?.label ?? "")?",
                isPresented: Binding(
                    get: { confirmingTier != nil },
                    set: { if !$0 { confirmingTier = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(confirmingTier == .free ? "Downgrade" : "Upgrade") {
                    if let tier = confirmingTier { activate(tier) }
                    confirmingTier = nil
                }
                Button("Cancel", role: .cancel) { confirmingTier = nil }
            } message: {
                Text(
                    confirmingTier == .free
                        ? "You keep your coins and boosters."
                        : "Simulated purchase at \(confirmingTier?.priceLabel ?? "") - no real charge. \(confirmingTier?.signupBonusCoins ?? 0) bonus coins are added now."
                )
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func tierCard(_ tier: SubscriptionTier) -> some View {
        let isCurrent = tier == currentTier
        let isGold = tier == .gold

        VStack(alignment: .leading, spacing: Theme.Metric.Space.m) {
            HStack(spacing: 8) {
                Text(tier.label)
                    .font(.click(.title3, weight: .black))
                    .foregroundStyle(isGold ? Theme.coin : Theme.primary)
                if isCurrent {
                    Text("current")
                        .font(.click(.caption2, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.online, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                Text(tier.priceLabel)
                    .font(.click(.subheadline, weight: .black))
                    .foregroundStyle(Theme.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(tier.benefits, id: \.self) { benefit in
                    Label {
                        Text(benefit)
                            .font(.clickPlain(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.primary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isGold ? Theme.coin : Theme.brandPink)
                    }
                }
            }

            if !isCurrent {
                Button {
                    confirmingTier = tier
                } label: {
                    Text(tier == .free ? "switch to free" : "get \(tier.label)")
                        .font(.click(.headline, weight: .heavy))
                        .foregroundStyle(tier == .free ? Theme.primary : Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            tier == .free ? Theme.surfaceHigh : Theme.primary,
                            in: Capsule()
                        )
                }
                .buttonStyle(.click)
                .accessibilityLabel("\(tier == .free ? "Switch to" : "Get") \(tier.label), \(tier.priceLabel). Demo purchase, no real charge.")
            }
        }
        .padding(Theme.Metric.gutter)
        .cardSurface(radius: Theme.Metric.card, elevated: isCurrent)
        .overlay {
            if isGold {
                RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous)
                    .strokeBorder(Theme.brandGradient, lineWidth: 2)
            } else if isCurrent {
                RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous)
                    .strokeBorder(Theme.online, lineWidth: 2)
            }
        }
        .animation(motion.state, value: isCurrent)
    }

    private func activate(_ tier: SubscriptionTier) {
        let wallet = Wallet.ensure(in: context)
        wallet.subscriptionTier = tier
        if tier.signupBonusCoins > 0 {
            wallet.coins += tier.signupBonusCoins
            coinEarnTrigger += 1
        }
        try? context.save()
        Haptics.notify(.success)
    }
}

#Preview {
    SubscriptionView(coinEarnTrigger: .constant(0))
        .modelContainer(MockData.previewContainer)
}
