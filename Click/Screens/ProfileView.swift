//
//  ProfileView.swift
//  Click
//
//  Identity, daily bingo, boosters, daily reward streak, referral. The
//  paid surfaces (offers, subscription, coin store, challenges) were
//  deliberately removed — do not reintroduce them without a decision.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @Query(sort: \BoosterInventory.kindRaw)
    private var boosters: [BoosterInventory]

    @Query(sort: \DailyReward.day)
    private var dailyRewards: [DailyReward]

    @Query private var wallets: [Wallet]

    @State private var showingSettings = false
    @State private var referralCode = ""
    /// Bumped when coins are earned so the wallet coin spins.
    @State private var coinEarnTrigger = 0
    @State private var insufficientCoinsMessage: String?

    private var me: UserProfile? { currentUsers.first }
    private var wallet: Wallet? { wallets.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                OverlappingSheet {
                    VStack(alignment: .leading, spacing: 28) {
                        identityBlock
                        bingoSection
                        dailyRewardsSection
                        boostersSection
                        referralSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .tabBarClearance()
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert(
            "Not enough coins",
            isPresented: Binding(
                get: { insufficientCoinsMessage != nil },
                set: { if !$0 { insufficientCoinsMessage = nil } }
            )
        ) {
            Button("OK") { insufficientCoinsMessage = nil }
        } message: {
            Text(insufficientCoinsMessage ?? "")
        }
        .task { resetRewardCycleIfFinished() }
    }

    // MARK: - Header

    private var header: some View {
        TexturedHeader(title: "", texture: .water) {
            HStack(spacing: 10) {
                Spacer()
                GlassCapsule {
                    CoinView(size: 20, earnTrigger: coinEarnTrigger)
                    Text((wallet?.coins ?? 0).formatted())
                        .font(.click(.subheadline, weight: .heavy))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: wallet?.coins ?? 0)
                }
                .font(.system(size: 15, weight: .bold))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(wallet?.coins ?? 0) coins")

                GlassCircleButton(systemImage: "gearshape.fill", accessibilityTitle: "Settings") {
                    showingSettings = true
                }
            }
        }
    }

    // MARK: - Identity

    private var identityBlock: some View {
        VStack(spacing: 12) {
            // Half in the header, half in the sheet — a deliberate straddle.
            // 116pt (not 132) so it clears the coin capsule on a 375pt screen.
            StickerAvatar(
                name: me?.name ?? "You",
                size: 116,
                badgeNumber: me?.displayAge,
                isVerified: me?.isVerified ?? false
            )
            .offset(y: -58 - Theme.Metric.sheetOverlap / 2)
            .padding(.bottom, -(58 - 8) - Theme.Metric.sheetOverlap / 2)

            HStack(spacing: 8) {
                CountryBadge(code: me?.countryCode)
                Text(me?.zodiac.label ?? "")
                    .font(.click(.headline, weight: .bold))
                    .foregroundStyle(Theme.primary)
                if let city = me?.city {
                    Text(city)
                        .font(.clickPlain(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }

            PillButton(title: "edit profile") {}
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bingo

    private var bingoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("daily bingo")
            BingoView(coinEarnTrigger: $coinEarnTrigger)
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    // MARK: - Boosters

    private var boostersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("boosters")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(orderedBoosters) { inventory in
                    BoosterCard(kind: inventory.kind, count: inventory.count) {
                        buyBooster(inventory)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    /// The @Query sorts by raw value, which is alphabetical. Present them in
    /// the order the enum declares instead.
    private var orderedBoosters: [BoosterInventory] {
        BoosterKind.allCases.compactMap { kind in
            boosters.first { $0.kindRaw == kind.rawValue }
        }
    }

    private static let boosterPrice = 25

    /// A real purchase, not a silent no-op: insufficient balance says so.
    private func buyBooster(_ inventory: BoosterInventory) {
        let wallet = ensureWallet()
        guard wallet.coins >= Self.boosterPrice else {
            insufficientCoinsMessage = "A \(inventory.kind.label) costs \(Self.boosterPrice) coins — you have \(wallet.coins). Earn more with daily rewards and bingo."
            Haptics.notify(.error)
            return
        }
        wallet.coins -= Self.boosterPrice
        inventory.count += 1
        try? context.save()
        Haptics.notify(.success)
    }

    // MARK: - Daily rewards

    private var dailyRewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("daily rewards")
                if let streak = wallet?.currentStreak, streak > 1 {
                    Text("\(streak)-day streak")
                        .font(.click(.footnote, weight: .heavy))
                        .foregroundStyle(Theme.brandPink)
                }
            }
            .padding(.horizontal, Theme.Metric.gutter)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(dailyRewards) { reward in
                        DailyRewardCard(
                            reward: reward,
                            isActive: reward.day == activeRewardDay,
                            isClaimableToday: !claimedToday
                        ) {
                            claim(reward)
                        }
                    }
                }
                .padding(.horizontal, Theme.Metric.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The first unclaimed day is the one the user can collect.
    private var activeRewardDay: Int {
        dailyRewards.first(where: { !$0.isClaimed })?.day ?? 0
    }

    /// One claim per calendar day — this is what stops the whole track being
    /// farmed in a single sitting.
    private var claimedToday: Bool {
        dailyRewards.contains {
            guard let claimedAt = $0.claimedAt else { return false }
            return Calendar.current.isDateInToday(claimedAt)
        }
    }

    private func claim(_ reward: DailyReward) {
        guard !reward.isClaimed, !claimedToday else { return }

        // Credit BEFORE consuming, and never against a nil wallet.
        let wallet = ensureWallet()
        wallet.coins += reward.coinValue
        if let kind = reward.boosterKind,
           let inventory = boosters.first(where: { $0.kindRaw == kind.rawValue }) {
            inventory.count += 1
        }

        // Streak: consecutive calendar days; a gap resets to 1.
        if let last = wallet.lastClaimAt,
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now),
           Calendar.current.isDate(last, inSameDayAs: yesterday) {
            wallet.currentStreak += 1
        } else {
            wallet.currentStreak = 1
        }
        wallet.lastClaimAt = .now

        reward.isClaimed = true
        reward.claimedAt = .now
        try? context.save()
        coinEarnTrigger += 1
        Haptics.notify(.success)
    }

    /// After day 7 is claimed, the track restarts the NEXT day — without
    /// this the section dies permanently.
    private func resetRewardCycleIfFinished() {
        guard !dailyRewards.isEmpty, dailyRewards.allSatisfy(\.isClaimed) else { return }
        guard !claimedToday else { return }
        for reward in dailyRewards {
            reward.isClaimed = false
            reward.claimedAt = nil
        }
        try? context.save()
    }

    private func ensureWallet() -> Wallet {
        if let wallet { return wallet }
        let fresh = Wallet()
        context.insert(fresh)
        try? context.save()
        return fresh
    }

    // MARK: - Referral

    private var referralSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("referral code")

            HStack(spacing: 10) {
                TextField("drop the code", text: $referralCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.clickPlain(.body, weight: .medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Theme.surface, in: Capsule())
                    .accessibilityLabel("Referral code")

                PillButton(
                    title: "add code",
                    isEnabled: !referralCode.trimmingCharacters(in: .whitespaces).isEmpty,
                    horizontalPadding: 20
                ) {
                    ensureWallet().referralCodeUsed = referralCode
                    referralCode = ""
                    try? context.save()
                }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }
}

// MARK: - Daily reward card

private struct DailyRewardCard: View {
    let reward: DailyReward
    let isActive: Bool
    /// False once anything was claimed today — one reward per calendar day.
    let isClaimableToday: Bool
    let onClaim: () -> Void

    private var canCollect: Bool { isActive && !reward.isClaimed && isClaimableToday }

    var body: some View {
        VStack(spacing: 8) {
            if reward.coinValue > 0 && canCollect {
                CoinView(size: 28, animatesIdle: true)
            } else if reward.coinValue > 0 {
                CoinView(size: 28)
                    .saturation(reward.isClaimed || !isActive ? 0 : 1)
                    .opacity(reward.isClaimed || !isActive ? 0.5 : 1)
            } else {
                Image(systemName: reward.boosterKind?.systemImage ?? "gift.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(iconColor)
            }

            Text(reward.rewardLabel)
                .font(.click(.footnote, weight: .heavy))
                .foregroundStyle(reward.isClaimed || !isActive ? Theme.secondary : Theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if canCollect {
                Button(action: onClaim) {
                    Text("collect")
                        .font(.click(.caption, weight: .heavy))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Theme.primary)
                }
                .buttonStyle(.click)
                .accessibilityLabel("Collect day \(reward.day) reward: \(reward.rewardLabel)")
            } else {
                Text(statusText)
                    .font(.click(.caption, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
        }
        .padding(.top, 12)
        .frame(width: 104)
        .background(canCollect ? Theme.surface : Theme.separator.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if canCollect {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.primary, lineWidth: 2)
            }
        }
        // .contain, not .combine: the collect button must stay reachable as
        // its own VoiceOver element.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Day \(reward.day): \(reward.rewardLabel)\(reward.isClaimed ? ", claimed" : "")")
    }

    private var statusText: String {
        if reward.isClaimed { return "claimed" }
        if isActive && !isClaimableToday { return "tomorrow" }
        return "day \(reward.day)"
    }

    private var iconColor: Color {
        if reward.isClaimed || !isActive { return Theme.secondary.opacity(0.6) }
        return reward.coinValue > 0 ? Theme.coin : Theme.accent
    }
}

#Preview {
    ProfileView()
        .modelContainer(MockData.previewContainer)
}
