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
    @State private var showingEditProfile = false
    @State private var referralCode = ""
    @State private var referralFeedback: String?
    /// Bumped when coins are earned so the wallet coin spins.
    @State private var coinEarnTrigger = 0
    @State private var insufficientCoinsMessage: String?
    /// Decoded once, not per body evaluation.
    @State private var myPhoto: UIImage?

    @Environment(\.motion) private var motion

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }
    private var wallet: Wallet? { wallets.first }

    var body: some View {
        // Header OUTSIDE the scroll view: its safe-area-bleeding background
        // cannot escape a ScrollView's clipped, inset geometry, which left a
        // background strip behind the status bar on this tab only.
        VStack(spacing: 0) {
            header
            ScrollView {
                OverlappingSheet(ambient: true) {
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
                .tabBarClearance()
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
        }
        .task(id: me?.photos.count ?? 0) {
            myPhoto = me?.orderedPhotos.first.flatMap { UIImage(data: $0.data) }
        }
        .alert(
            "Referral code",
            isPresented: Binding(
                get: { referralFeedback != nil },
                set: { if !$0 { referralFeedback = nil } }
            )
        ) {
            Button("OK") { referralFeedback = nil }
        } message: {
            Text(referralFeedback ?? "")
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
        // A real title so all three tab headers share a baseline.
        TexturedHeader(title: "profile", texture: .water) {
            HStack(spacing: 10) {
                GlassCapsule {
                    CoinView(size: 20, earnTrigger: coinEarnTrigger)
                    Text((wallet?.coins ?? 0).formatted())
                        .font(.click(.subheadline, weight: .heavy))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(motion.numeric, value: wallet?.coins ?? 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(wallet?.coins ?? 0) coins")

                GlassCircleButton(systemImage: "gearshape.fill", accessibilityTitle: "Settings") {
                    showingSettings = true
                }
            }
        }
    }

    // MARK: - Identity

    /// Avatar size and the derived straddle offsets, named instead of
    /// magic-numbered. 116pt (not 132) so it clears the coin capsule on a
    /// 375pt screen; half rides up over the header edge.
    private static let avatarSize: CGFloat = 116

    private var identityBlock: some View {
        VStack(spacing: 12) {
            // Half in the header, half in the sheet — a deliberate straddle.
            StickerAvatar(
                name: me?.name ?? "You",
                size: Self.avatarSize,
                badgeNumber: me?.displayAge,
                isVerified: me?.isVerified ?? false,
                photo: myPhoto
            )
            .offset(y: -Self.avatarSize / 2 - Theme.Metric.sheetOverlap / 2)
            .padding(.bottom, -(Self.avatarSize / 2 - 8) - Theme.Metric.sheetOverlap / 2)

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

            if let me, me.isBoosted, let until = me.boostedUntil {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(timerInterval: Date.now...until, countsDown: true)
                        .font(.click(.footnote, weight: .heavy))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.brandViolet, in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Boost active")
                .accessibilityValue("about \(max(1, Int(until.timeIntervalSinceNow / 60))) minutes remaining")
            }

            HStack(spacing: 16) {
                Label("\(wallet?.profileViews ?? 0) views", systemImage: "eye.fill")
                    .font(.clickPlain(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }

            PillButton(title: "edit profile") {
                showingEditProfile = true
            }
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

    /// Only the boosters with a real mechanic are sold — `admirers` and
    /// `reveal` had none, and Click doesn't sell dead goods. The enum
    /// cases survive for stored inventory rows.
    private static let liveBoosterKinds: [BoosterKind] = [.boost, .superChat, .bulkChat]

    private var boostersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("boosters")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(orderedBoosters) { inventory in
                    BoosterCard(
                        kind: inventory.kind,
                        count: inventory.count,
                        price: Self.boosterPrice,
                        onAdd: { buyBooster(inventory) },
                        onUse: inventory.kind == .boost ? { useBoost() } : nil
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    /// The @Query sorts by raw value, which is alphabetical. Present the
    /// live kinds in the order the enum declares instead.
    private var orderedBoosters: [BoosterInventory] {
        Self.liveBoosterKinds.compactMap { kind in
            boosters.first { $0.kindRaw == kind.rawValue }
        }
    }

    /// Boost = real (locally simulated) profile visibility for 30 minutes.
    private func useBoost() {
        guard let me else { return }
        if Boost.activate(for: me, in: context) {
            Haptics.notify(.success)
        } else {
            Haptics.notify(.error)
        }
    }

    private static let boosterPrice = 25

    /// A real purchase, not a silent no-op: insufficient balance says so.
    private func buyBooster(_ inventory: BoosterInventory) {
        let wallet = Wallet.ensure(in: context)
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
            // One baseline row, no nested Spacer fight — the streak sits
            // right next to its header instead of at the screen edge.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("daily rewards")
                    .font(.click(.title2, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                    .accessibilityAddTraits(.isHeader)
                if let streak = wallet?.currentStreak, streak > 1 {
                    Text("\(streak)-day streak")
                        .font(.click(.footnote, weight: .heavy))
                        .foregroundStyle(Theme.brandPink)
                }
                Spacer()
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

        // Credit BEFORE consuming, and never against a nil wallet or a
        // missing inventory row.
        let wallet = Wallet.ensure(in: context)
        wallet.coins += reward.coinValue
        if let kind = reward.boosterKind {
            BoosterInventory.ensure(kind, in: context).count += 1
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

    // MARK: - Referral

    /// Valid codes and their coin credit. Hardcoded until a backend exists.
    private static let referralCodes: [String: Int] = [
        "CLICK50": 50,
        "FRIEND25": 25,
        "WELCOME10": 10
    ]

    private var referralSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("referral code")

            if wallet?.referralCodeUsed != nil {
                Label("code applied — thanks!", systemImage: "checkmark.circle.fill")
                    .font(.clickPlain(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.online)
            } else {
                HStack(spacing: 10) {
                    TextField("drop the code", text: $referralCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.clickPlain(.body, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.surface, in: Capsule())
                        .accessibilityLabel("Referral code")

                    PillButton(
                        title: "add code",
                        isEnabled: !referralCode.trimmingCharacters(in: .whitespaces).isEmpty,
                        horizontalPadding: 20
                    ) {
                        redeemReferralCode()
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    /// A real redemption: valid codes credit coins, garbage says so —
    /// nothing is silently swallowed any more.
    private func redeemReferralCode() {
        let code = referralCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard let credit = Self.referralCodes[code] else {
            Haptics.notify(.error)
            referralFeedback = "\"\(code)\" isn't a valid referral code. Check the spelling and try again."
            return
        }
        let wallet = Wallet.ensure(in: context)
        wallet.coins += credit
        wallet.referralCodeUsed = code
        try? context.save()
        referralCode = ""
        coinEarnTrigger += 1
        Haptics.notify(.success)
        referralFeedback = "Code accepted — \(credit) coins added to your wallet."
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
        .background(canCollect ? Theme.surface : Theme.fillDisabled.opacity(0.75))
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
