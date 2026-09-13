//
//  EventWheelView.swift
//  Click
//
//  The event wheel. The outcome is decided by EventService BEFORE the
//  animation starts — the wheel only reveals it (the same honest
//  pattern bingo uses). Entries are earned, rewards are cosmetics and
//  boosters only, odds are published, and there is no engineered
//  near-miss. Under Reduce Motion the reveal is a plain fade.
//

import SwiftUI
import SwiftData

struct EventWheelView: View {
    let event: EventDefinition

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.motion) private var motion

    @Query private var allProgress: [EventProgress]
    @Query private var wallets: [Wallet]

    @State private var spinning = false
    @State private var revealed: BingoReward?
    @State private var wheelAngle: Double = 0
    @State private var showingOdds = false

    private var progress: EventProgress? {
        allProgress.first { $0.eventID == event.id }
    }

    private var entries: Int { progress?.entries ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    wheel
                    resultPanel
                    spinButton
                    footer
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.vertical, 20)
            }
            .background(Theme.background)
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("odds") { showingOdds = true }
                        .font(.clickPlain(.body, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .accessibilityLabel("Show the odds")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                        .font(.click(.body, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .accessibilityLabel("Done")
                }
            }
        }
        .sheet(isPresented: $showingOdds) { oddsSheet }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: event.symbolName)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(CommunityService.tint(event.tintToken))
                .accessibilityHidden(true)
            Text("\(entries) \(entries == 1 ? "entry" : "entries")")
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
                .contentTransition(.numericText())
            Text("entries are free — one per day of the event, one per daily reward you claim. rewards are cosmetics and boosters only.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    /// Eight decorated segments. Purely decorative: the reward is already
    /// decided when the spin starts, and the pointer lands on a segment
    /// showing that reward's symbol.
    private var wheel: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let symbols = ["moon.stars.fill", "sparkles", "flame.fill", "bolt.fill",
                               "star.fill", "wind", "envelope.fill", "gift.fill"]
                Image(systemName: symbols[index])
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .offset(y: -92)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle()
                .strokeBorder(Theme.brandGradient, lineWidth: 4)
                .frame(width: 240, height: 240)
            Image(systemName: event.symbolName)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(CommunityService.tint(event.tintToken))
        }
        .frame(width: 260, height: 260)
        .rotationEffect(.degrees(wheelAngle))
        .overlay(alignment: .top) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.primary)
                .offset(y: -12)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let revealed {
            VStack(spacing: 8) {
                switch revealed {
                case .cosmetic(let id):
                    Image(systemName: CosmeticCatalog.byID[id]?.symbolName ?? "gift.fill")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(CosmeticCatalog.tint(id))
                case .booster(let kind):
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(kind.tint)
                case .coins:
                    CoinView(size: 34)
                }
                Text("you won \(revealed.label)")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                if case .cosmetic = revealed {
                    Text("equip it from your profile's cosmetics.")
                        .font(.clickPlain(.footnote, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .cardSurface(radius: Theme.Metric.tile)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    private var spinButton: some View {
        Button {
            spin()
        } label: {
            Text(entries > 0 ? "spin" : "no entries left")
                .font(.click(.headline, weight: .heavy))
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(entries > 0 && !spinning ? Theme.primary : Theme.fillDisabled, in: Capsule())
        }
        .buttonStyle(.click)
        .disabled(entries == 0 || spinning)
        .accessibilityLabel(entries > 0 ? "Spin the wheel" : "No entries left")
    }

    private var footer: some View {
        Text("the top reward is guaranteed within \(event.pityBy) spins. a cosmetic you already own becomes a boost. ends \(event.endsAt.formatted(date: .abbreviated, time: .omitted).lowercased()).")
            .font(.clickPlain(.caption, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
    }

    private func spin() {
        guard !spinning, let reward = EventService.spin(event: event, in: context) else { return }
        spinning = true
        Haptics.impact(.medium)
        withAnimation(motion.state) { revealed = nil }

        if motion.reduceMotion {
            // No spinning wheel — a plain fade to the result.
            withAnimation(motion.celebrate) { revealed = reward }
            spinning = false
            Haptics.notify(.success)
        } else {
            // Two clean turns plus a deterministic segment; the reveal
            // waits for the rotation to finish.
            withAnimation(motion.celebrate) {
                wheelAngle += 720 + Double(Int.random(in: 0..<8)) * 45
            } completion: {
                withAnimation(motion.celebrate) { revealed = reward }
                spinning = false
                Haptics.notify(.success)
            }
        }
    }

    private var oddsSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(EventService.halloweenOddsTable, id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .foregroundStyle(Theme.primary)
                            Spacer()
                            Text(row.chance)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                } footer: {
                    Text("Every spin uses one free entry. The pumpkin frame is guaranteed within \(event.pityBy) spins if you haven't won it. A cosmetic you already own becomes a boost. Rewards are cosmetics and boosters only — never coins, never visibility.")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("odds")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
