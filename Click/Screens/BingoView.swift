//
//  BingoView.swift
//  Click
//
//  Daily bingo: a 3×3 board of face-down tiles. Pick three — each flips to
//  reveal a reward — then pay once (coins) to claim all three. One board per
//  calendar day, seeded deterministically from the date so force-quitting
//  can never re-roll it. Purely virtual currency, odds published up front
//  (App Store Guideline 3.1.1 requires disclosing odds for randomised
//  rewards; do not attach real money to this without legal review).
//

import SwiftUI
import SwiftData

struct BingoView: View {
    @Binding var coinEarnTrigger: Int

    @Environment(\.modelContext) private var context
    @Environment(\.motion) private var motion

    @Query private var boards: [BingoBoard]
    @Query private var wallets: [Wallet]

    @State private var showingOdds = false
    @State private var insufficientMessage: String?
    /// Bumped on claim: coins fly from the board toward the wallet capsule.
    @State private var coinFlight = 0
    @State private var claimedBounce = 0

    /// 25 -> 35 (MEGA-BRIEF 0.8): the pool's expected value is ~36.7
    /// coins plus a booster, so at 25 the only sink was a fountain and
    /// coins inflated forever. ~Neutral now; boosters stay the upside.
    /// The 50-coin welcome bonus still affords a day-1 claim.
    static let claimPrice = 35
    static let picksAllowed = 3

    private var todayKey: String {
        Self.dateKey(for: .now)
    }

    /// Today's board — or, after a clock rollback, the newest
    /// future-dated one. Serving a fresh board while a claimed one sits
    /// at a future date was an unbounded coin printer (MEGA-BRIEF 0.7).
    private var board: BingoBoard? {
        boards.first { $0.dateKey == todayKey }
            ?? boards.filter { $0.dateKey > todayKey }.max { $0.dateKey < $1.dateKey }
    }

    private var wallet: Wallet? { wallets.first }

    var body: some View {
        VStack(spacing: 14) {
            statusLine

            if let board {
                grid(for: board)

                if board.pickedIndexes.count == Self.picksAllowed && !board.isClaimed {
                    claimPanel(for: board)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if board.isClaimed {
                    Label("claimed — new board tomorrow", systemImage: "checkmark.circle.fill")
                        .font(.click(.footnote, weight: .bold))
                        .foregroundStyle(Theme.online)
                        .symbolEffect(.bounce, value: claimedBounce)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            Button {
                showingOdds = true
            } label: {
                Label("what can I win?", systemImage: "info.circle")
                    .font(.clickPlain(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("What can I win? Shows the odds of each reward.")
        }
        .padding(16)
        .cardSurface(radius: Theme.Metric.card)
        .animation(motion.state, value: board?.pickedIndexes.count ?? 0)
        .animation(motion.state, value: board?.isClaimed ?? false)
        // Coins arcing up-and-right, toward the wallet capsule.
        .overlay(alignment: .topTrailing) {
            CoinFlightOverlay(trigger: coinFlight)
        }
        // Keyed on the date so the board rolls over at midnight while the
        // app stays open, instead of vanishing until the next relaunch.
        .task(id: todayKey) { ensureBoard() }
        .sheet(isPresented: $showingOdds) { oddsSheet }
        .alert(
            "Not enough coins",
            isPresented: Binding(
                get: { insufficientMessage != nil },
                set: { if !$0 { insufficientMessage = nil } }
            )
        ) {
            Button("OK") { insufficientMessage = nil }
        } message: {
            Text(insufficientMessage ?? "")
        }
    }

    // MARK: - Pieces

    private var statusLine: some View {
        HStack {
            Text(headline)
                .font(.clickPlain(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var headline: String {
        guard let board else { return "pick 3 tiles" }
        if board.isClaimed { return "today's board is done" }
        let remaining = Self.picksAllowed - board.pickedIndexes.count
        return remaining > 0 ? "pick \(remaining) more tile\(remaining == 1 ? "" : "s")" : "your three rewards"
    }

    private func grid(for board: BingoBoard) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
            spacing: 10
        ) {
            ForEach(0..<9, id: \.self) { index in
                BingoTile(
                    reward: reward(at: index, on: board),
                    isRevealed: board.pickedIndexes.contains(index),
                    isEnabled: !board.isClaimed && board.pickedIndexes.count < Self.picksAllowed
                        && !board.pickedIndexes.contains(index)
                ) {
                    pick(index, on: board)
                }
            }
        }
    }

    private func claimPanel(for board: BingoBoard) -> some View {
        let rewards = board.pickedIndexes.compactMap { reward(at: $0, on: board) }
        let summary = rewards.map(\.label).joined(separator: " + ")
        let balance = wallet?.coins ?? 0
        let canAfford = balance >= Self.claimPrice

        return VStack(spacing: 8) {
            Text(summary)
                .font(.click(.subheadline, weight: .bold))
                .foregroundStyle(Theme.primary)
                .multilineTextAlignment(.center)

            Button {
                claim(board)
            } label: {
                Text("claim all — \(Self.claimPrice) coins")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(canAfford ? Theme.onPrimary : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(canAfford ? Theme.primary : Theme.fillDisabled, in: Capsule())
            }
            .buttonStyle(.click)
            .disabled(!canAfford)
            .accessibilityLabel("Claim all three rewards for \(Self.claimPrice) coins")

            if !canAfford {
                // Never a silent no-op — and honest about the timeline: one
                // daily reward does NOT close the gap.
                Text("You have \(balance.formatted()) coins — you need \(Self.claimPrice). Daily rewards and referral codes will get you there over the next days. Today's board expires at midnight.")
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var oddsSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Self.oddsTable, id: \.label) { row in
                        LabeledContent(row.label, value: row.chance)
                            .listRowBackground(Theme.surface)
                    }
                } header: {
                    Text("Each of the 9 tiles is drawn with these odds")
                } footer: {
                    Text("Rewards are Click coins and boosters only — no real money is involved, and coins cannot be cashed out. The board is fixed for the whole day: quitting the app never re-rolls it.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("bingo odds")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Mechanics

    /// Published odds. Keep this table in sync with `generateRewards` —
    /// the tests assert they match.
    static let oddsTable: [(label: String, chance: String)] = [
        ("10 coins", "3 in 9"),
        ("20 coins", "2 in 9"),
        ("40 coins", "1 in 9"),
        ("1 boost", "1 in 9"),
        ("1 bulk chat", "1 in 9"),
        ("1 super chat", "1 in 9")
    ]

    /// The fixed reward pool per board: shuffled deterministically by date.
    /// Only boosters with a real mechanic — `reveal` sold nothing and was
    /// retired from the pool with the store card.
    static func generateRewards(dateKey: String) -> [String] {
        let pool: [BingoReward] = [
            .coins(10), .coins(10), .coins(10),
            .coins(20), .coins(20),
            .coins(40),
            .booster(.boost),
            .booster(.bulkChat),
            .booster(.superChat)
        ]
        var generator = SeededGenerator(seed: Self.seed(for: dateKey))
        return pool.shuffled(using: &generator).map(\.encoded)
    }

    static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // Explicit, not implicit: the day boundary follows the device's
        // current zone by DESIGN, stated here (MEGA-BRIEF 0.7).
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Salted per install: the seed used to be a hash of the date string
    /// alone, so every user got the identical board and one forum post
    /// turned a blind pick into a guaranteed payout (MEGA-BRIEF 0.7).
    static var installSalt: UInt64 {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: DefaultsKey.bingoSeedSalt) as? String,
           let value = UInt64(stored) {
            return value
        }
        let fresh = UInt64.random(in: UInt64.min...UInt64.max)
        defaults.set(String(fresh), forKey: DefaultsKey.bingoSeedSalt)
        return fresh
    }

    private static func seed(for dateKey: String) -> UInt64 {
        let dateHash = dateKey.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return dateHash ^ installSalt
    }

    private func ensureBoard() {
        // Prune only boards strictly OLDER than today. A claimed board at
        // a future date (clock rolled back) must survive — deleting claim
        // state on key mismatch was the unbounded coin printer.
        for stale in boards where stale.dateKey < todayKey {
            context.delete(stale)
        }
        guard board == nil else {
            try? context.save()
            return
        }
        let fresh = BingoBoard(dateKey: todayKey, tileRewards: Self.generateRewards(dateKey: todayKey))
        context.insert(fresh)
        try? context.save()
    }

    private func reward(at index: Int, on board: BingoBoard) -> BingoReward? {
        guard board.tileRewards.indices.contains(index) else { return nil }
        return BingoReward(encoded: board.tileRewards[index])
    }

    private func pick(_ index: Int, on board: BingoBoard) {
        guard !board.isClaimed,
              board.pickedIndexes.count < Self.picksAllowed,
              !board.pickedIndexes.contains(index) else { return }
        board.pickedIndexes.append(index)
        try? context.save()
        Haptics.impact(.medium)
    }

    private func claim(_ board: BingoBoard) {
        guard !board.isClaimed, board.pickedIndexes.count == Self.picksAllowed else { return }

        let wallet = Wallet.ensure(in: context)
        guard wallet.coins >= Self.claimPrice else {
            insufficientMessage = "Claiming costs \(Self.claimPrice) coins and you have \(wallet.coins)."
            Haptics.notify(.error)
            return
        }

        wallet.coins -= Self.claimPrice
        for index in board.pickedIndexes {
            switch reward(at: index, on: board) {
            case .coins(let value):
                wallet.coins += value
            case .booster(let kind):
                // ensure(_:in:) — a missing inventory row must never eat a
                // reward the user just paid for.
                BoosterInventory.ensure(kind, in: context).count += 1
            case .cosmetic(let id):
                // The bingo pool never contains cosmetics (they are
                // event-wheel rewards), but the shared codec allows it.
                if !wallet.ownedCosmetics.contains(id) {
                    wallet.ownedCosmetics.append(id)
                }
            case nil:
                break
            }
        }
        board.isClaimed = true
        try? context.save()
        coinEarnTrigger += 1
        coinFlight += 1
        claimedBounce += 1
        Haptics.notify(.success)
    }
}

// MARK: - Tile

/// A tile that GENUINELY flips (the file header used to claim a flip that
/// was really a hard cut through a non-animatable AnyShapeStyle swap):
/// two faces, back and front, rotating 0->180 with perspective, faces
/// swapped exactly at the 90-degree midpoint.
private struct BingoTile: View {
    let reward: BingoReward?
    let isRevealed: Bool
    let isEnabled: Bool
    let onPick: () -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        Button(action: onPick) {
            TileFlip(
                angle: isRevealed ? 180 : 0,
                front: revealedFace,
                back: faceDown
            )
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.click)
        .disabled(!isEnabled)
        // Disabled face-down tiles visibly dim — they used to be
        // pixel-identical to live ones.
        .saturation(isRevealed || isEnabled ? 1 : 0.5)
        .opacity(isRevealed || isEnabled ? 1 : 0.55)
        .animation(motion.state, value: isRevealed)
        .animation(motion.state, value: isEnabled)
        .accessibilityLabel(accessibilityText)
    }

    private var faceDown: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Metric.tile, style: .continuous)
                .fill(Theme.brandGradient)
            Image(systemName: "questionmark")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(.white)
        }
        // Same 1pt hairline as the revealed face so the grid reads as one
        // even surface — only revealed tiles had a border before, which
        // made the board look uneven (MEGA-BRIEF 2.3).
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.tile, style: .continuous)
                .strokeBorder(Theme.glowStroke, lineWidth: 1)
        }
    }

    private var revealedFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Metric.tile, style: .continuous)
                .fill(Theme.surface)
            VStack(spacing: 4) {
                switch reward {
                case .coins:
                    CoinView(size: 26)
                case .booster(let kind):
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(kind.tint)
                case .cosmetic(let id):
                    Image(systemName: CosmeticCatalog.byID[id]?.symbolName ?? "gift.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(CosmeticCatalog.tint(id))
                case nil:
                    EmptyView()
                }
                Text(reward?.label ?? "")
                    .font(.click(.caption2, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
        }
        .overlay {
            // 1pt tempered stroke, not the 2pt full-saturation fringe.
            RoundedRectangle(cornerRadius: Theme.Metric.tile, style: .continuous)
                .strokeBorder(Theme.brandPink.opacity(0.7), lineWidth: 1)
        }
    }

    private var accessibilityText: String {
        if isRevealed {
            return "Revealed: \(reward?.label ?? "unknown reward")"
        }
        return isEnabled ? "Face-down tile. Double-tap to reveal." : "Face-down tile, not selectable."
    }
}

/// Animatable two-faced flip. `angle` interpolates per frame, so the face
/// swap really happens at the visual midpoint.
private struct TileFlip<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            if angle < 90 {
                back
            } else {
                // Pre-rotated so it reads correctly once the parent
                // rotation passes 90.
                front.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// Three coins arcing up toward the wallet capsule after a claim, then
/// fading. Self-contained (no cross-view namespace plumbing); the coins
/// are always in the hierarchy at opacity 0 and animate on the trigger.
private struct CoinFlightOverlay: View {
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<3, id: \.self) { index in
                    FlyingCoin(delay: Double(index) * Theme.Motion.stagger, trigger: trigger)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FlyingCoin: View {
    let delay: Double
    let trigger: Int

    private struct FlightValues {
        var offset = CGSize(width: -60, height: 140)
        var opacity = 0.0
        var scale = 0.8
    }

    var body: some View {
        CoinView(size: 22)
            .keyframeAnimator(initialValue: FlightValues(), trigger: trigger) { view, values in
                view
                    .offset(values.offset)
                    // Invisible until (and after) a flight — trigger 0 is
                    // the untouched initial state.
                    .opacity(trigger == 0 ? 0 : values.opacity)
                    .scaleEffect(values.scale)
            } keyframes: { _ in
                KeyframeTrack(\.offset) {
                    CubicKeyframe(CGSize(width: -60, height: 140), duration: delay + 0.01)
                    CubicKeyframe(CGSize(width: -10, height: 20), duration: 0.42)
                    CubicKeyframe(CGSize(width: 8, height: -34), duration: 0.28)
                }
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(0, duration: delay + 0.01)
                    CubicKeyframe(1, duration: 0.18)
                    CubicKeyframe(1, duration: 0.34)
                    CubicKeyframe(0, duration: 0.18)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.8, duration: delay + 0.01)
                    CubicKeyframe(1.0, duration: 0.42)
                    CubicKeyframe(0.6, duration: 0.28)
                }
            }
    }
}

/// Deterministic RNG so a date always produces the same board.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

#Preview {
    ScrollView {
        BingoView(coinEarnTrigger: .constant(0))
            .padding()
    }
    .background(Theme.background)
    .modelContainer(MockData.previewContainer)
}
