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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var boards: [BingoBoard]
    @Query private var wallets: [Wallet]

    @State private var showingOdds = false
    @State private var insufficientMessage: String?

    static let claimPrice = 25
    static let picksAllowed = 3

    private var todayKey: String {
        Self.dateKey(for: .now)
    }

    private var board: BingoBoard? {
        boards.first { $0.dateKey == todayKey }
    }

    private var wallet: Wallet? { wallets.first }

    var body: some View {
        VStack(spacing: 14) {
            statusLine

            if let board {
                grid(for: board)

                if board.pickedIndexes.count == Self.picksAllowed && !board.isClaimed {
                    claimPanel(for: board)
                }
                if board.isClaimed {
                    Label("claimed — new board tomorrow", systemImage: "checkmark.circle.fill")
                        .font(.click(.footnote, weight: .bold))
                        .foregroundStyle(Theme.online)
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
                        && !board.pickedIndexes.contains(index),
                    reduceMotion: reduceMotion
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
                    .background(canAfford ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.separator), in: Capsule())
            }
            .buttonStyle(.click)
            .disabled(!canAfford)
            .accessibilityLabel("Claim all three rewards for \(Self.claimPrice) coins")

            if !canAfford {
                // Never a silent no-op: say exactly why and what to do.
                Text("You have \(balance.formatted()) coins — you need \(Self.claimPrice). Collect your daily reward to top up; your picks stay saved.")
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
                    }
                } header: {
                    Text("Each of the 9 tiles is drawn with these odds")
                } footer: {
                    Text("Rewards are Click coins and boosters only — no real money is involved, and coins cannot be cashed out. The board is fixed for the whole day: quitting the app never re-rolls it.")
                }
            }
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
        ("1 reveal", "1 in 9"),
        ("1 super chat", "1 in 9")
    ]

    /// The fixed reward pool per board: shuffled deterministically by date.
    static func generateRewards(dateKey: String) -> [String] {
        let pool: [BingoReward] = [
            .coins(10), .coins(10), .coins(10),
            .coins(20), .coins(20),
            .coins(40),
            .booster(.boost),
            .booster(.reveal),
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
        return formatter.string(from: date)
    }

    private static func seed(for dateKey: String) -> UInt64 {
        dateKey.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
    }

    private func ensureBoard() {
        // Yesterday's boards are dead weight — prune them so the table
        // doesn't grow forever.
        for stale in boards where stale.dateKey != todayKey {
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
            case nil:
                break
            }
        }
        board.isClaimed = true
        try? context.save()
        coinEarnTrigger += 1
        Haptics.notify(.success)
    }
}

// MARK: - Tile

private struct BingoTile: View {
    let reward: BingoReward?
    let isRevealed: Bool
    let isEnabled: Bool
    let reduceMotion: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Metric.tile, style: .continuous)
                    .fill(isRevealed ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(Theme.brandGradient))

                if isRevealed {
                    revealedFace
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isRevealed {
                    RoundedRectangle(cornerRadius: Theme.Metric.tile, style: .continuous)
                        .strokeBorder(Theme.brandPink, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.click)
        .disabled(!isEnabled)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.65),
            value: isRevealed
        )
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var revealedFace: some View {
        VStack(spacing: 4) {
            switch reward {
            case .coins:
                CoinView(size: 26)
            case .booster(let kind):
                Image(systemName: kind.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(kind.tint)
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

    private var accessibilityText: String {
        if isRevealed {
            return "Revealed: \(reward?.label ?? "unknown reward")"
        }
        return isEnabled ? "Face-down tile. Double-tap to reveal." : "Face-down tile, not selectable."
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
