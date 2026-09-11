//
//  ProfileView.swift
//  Click
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
    /// Fixed end point so the countdown does not reset on every redraw.
    @State private var offerEndsAt = Date().addingTimeInterval(24 * 60 * 60)

    private var me: UserProfile? { currentUsers.first }
    private var wallet: Wallet? { wallets.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                OverlappingSheet {
                    VStack(alignment: .leading, spacing: 28) {
                        identityBlock
                        offersSection
                        boostersSection
                        subscriptionSection
                        coinStoreSection
                        challengesSection
                        dailyRewardsSection
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
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    // MARK: - Header

    private var header: some View {
        TexturedHeader(title: "", texture: .water) {
            HStack(spacing: 10) {
                Spacer()
                GlassCapsule {
                    CoinView(size: 20, earnTrigger: coinEarnTrigger)
                    Text("\(wallet?.coins ?? 0)")
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
            // Half in the header, half in the sheet — a deliberate straddle,
            // with matching negative padding so the flow below stays even.
            StickerAvatar(
                name: me?.name ?? "You",
                size: 132,
                badgeNumber: me?.displayAge,
                isVerified: me?.isVerified ?? false
            )
            .offset(y: -66 - Theme.Metric.sheetOverlap / 2)
            .padding(.bottom, -(66 - 8) - Theme.Metric.sheetOverlap / 2)

            HStack(spacing: 8) {
                Text(me?.countryFlag ?? "🇦🇺")
                Text(me?.zodiac.symbol ?? "♒️")
                Text(me?.zodiac.label ?? "Aquarius")
                    .font(.click(.headline, weight: .bold))
                    .foregroundStyle(Theme.primary)
            }
            .font(.system(size: 19))

            PillButton(title: "edit profile") {}
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Offers

    private var offersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("offers")
                .padding(.horizontal, Theme.Metric.gutter)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    OfferCard(
                        title: "Royal Offer",
                        subtitle: "Limited-Time Steal!",
                        endsAt: offerEndsAt,
                        tint: [Theme.coin, Theme.coinDark]
                    )
                    OfferCard(
                        title: "Starter Pack",
                        subtitle: "First-timers only",
                        endsAt: offerEndsAt.addingTimeInterval(3_600),
                        tint: [Theme.brandViolet, Theme.violetDark]
                    )
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
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
                    BoosterCard(kind: inventory.kind, count: inventory.count) {}
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

    // MARK: - Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("subscription")
            SubscriptionCard(isSubscriber: wallet?.isSubscriber ?? false)
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    // MARK: - Coin store

    private var coinStoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("coins")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(CoinPack.catalog) { pack in
                    CoinPackCard(pack: pack)
                }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    // MARK: - Challenges

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("challenges")
            ChallengeCard()
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    // MARK: - Daily rewards

    private var dailyRewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("daily rewards")
                .padding(.horizontal, Theme.Metric.gutter)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(dailyRewards) { reward in
                        DailyRewardCard(
                            reward: reward,
                            isActive: reward.day == activeRewardDay
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

    private func claim(_ reward: DailyReward) {
        guard !reward.isClaimed else { return }
        reward.isClaimed = true
        reward.claimedAt = .now
        wallet?.coins += reward.coinValue
        try? context.save()
        coinEarnTrigger += 1
        Haptics.notify(.success)
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
                    wallet?.referralCodeUsed = referralCode
                    referralCode = ""
                    try? context.save()
                }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }
}

// MARK: - Offer card

private struct OfferCard: View {
    let title: String
    let subtitle: String
    let endsAt: Date
    let tint: [Color]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: tint, startPoint: .topLeading, endPoint: .bottomTrailing)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(countdown(to: endsAt, from: timeline.date))
                    .font(.click(.subheadline, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(12)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                Text(title)
                    .font(.click(.title2, weight: .heavy))
                Text(subtitle)
                    .font(.click(.subheadline, weight: .bold))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("Shop now")
                        .font(.click(.subheadline, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white))
                }
            }
            .padding(16)
        }
        .frame(width: 300, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle).")
    }

    private func countdown(to end: Date, from now: Date) -> String {
        let remaining = max(0, end.timeIntervalSince(now))
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        return "Ends in \(hours)h \(minutes)m \(seconds)s"
    }
}

// MARK: - Subscription card

private struct SubscriptionCard: View {
    let isSubscriber: Bool

    private let perks = [
        ("circle.fill", "1000 Coins /wk"),
        ("lock.open.fill", "Unlimited Reveal"),
        ("arrow.uturn.backward", "Unlimited Rewinds"),
        ("plus.circle.fill", "+ 5 more")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("click infinity")
                    .font(.click(.title2, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Text(isSubscriber ? "Active" : "Get Infinity")
                    .font(.click(.subheadline, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(perks, id: \.1) { perk in
                    Label {
                        Text(perk.1)
                    } icon: {
                        if perk.0 == "circle.fill" {
                            CoinView(size: 15)
                        } else {
                            Image(systemName: perk.0)
                        }
                    }
                    .font(.clickPlain(.footnote, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous))
    }
}

// MARK: - Coin pack card

private struct CoinPackCard: View {
    let pack: CoinPack

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(pack.coins)")
                        .font(.click(.title2, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                    Text("coins")
                        .font(.clickPlain(.footnote, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                CoinView(size: 26)
            }

            Text(pack.price)
                .font(.click(.headline, weight: .heavy))
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Theme.primary))
        }
        .padding(14)
        .cardSurface(radius: 20)
        .overlay(alignment: .topTrailing) {
            if let discount = pack.discountPercent {
                Text("\(discount)% off")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent))
                    .offset(x: 6, y: -8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pack.coins) coins for \(pack.price)")
    }
}

// MARK: - Challenge card

private struct ChallengeCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("$5,000 Challenge")
                    .font(.click(.title3, weight: .heavy))
                    .foregroundStyle(.white)
                Text("complete challenges to get rewards")
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Start challenge")
                    .font(.click(.subheadline, weight: .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
            }

            Spacer(minLength: 0)

            // Stand-in for the collaged screenshots in the reference.
            ZStack {
                ForEach(0..<2) { index in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.brandCoral, Theme.brandViolet],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 46, height: 84)
                        .rotationEffect(.degrees(index == 0 ? -8 : 8))
                        .offset(x: CGFloat(index) * 20 - 10)
                }
            }
            .shadow(color: Theme.brandCoral.opacity(0.5), radius: 12)
        }
        .padding(18)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Daily reward card

private struct DailyRewardCard: View {
    let reward: DailyReward
    let isActive: Bool
    let onClaim: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if reward.coinValue > 0 && !reward.isClaimed && isActive {
                CoinView(size: 28, animatesIdle: true)
            } else if reward.coinValue > 0 {
                CoinView(size: 28)
                    .saturation(reward.isClaimed || !isActive ? 0 : 1)
                    .opacity(reward.isClaimed || !isActive ? 0.5 : 1)
            } else {
                Image(systemName: "heart.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(iconColor)
            }

            Text(reward.rewardLabel)
                .font(.click(.footnote, weight: .heavy))
                .foregroundStyle(reward.isClaimed || !isActive ? Theme.secondary : Theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if isActive && !reward.isClaimed {
                Button(action: onClaim) {
                    Text("collect")
                        .font(.click(.caption, weight: .heavy))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Theme.primary)
                }
                .buttonStyle(.plain)
            } else {
                Text(reward.isClaimed ? "claimed" : "day \(reward.day)")
                    .font(.click(.caption, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
        }
        .padding(.top, 12)
        .frame(width: 104)
        .background(isActive && !reward.isClaimed ? Theme.surface : Theme.separator.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isActive && !reward.isClaimed {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.primary, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isActive && !reward.isClaimed {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
                    .offset(x: -8, y: 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day \(reward.day): \(reward.rewardLabel)")
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
