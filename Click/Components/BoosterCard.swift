//
//  BoosterCard.swift
//  Click
//

import SwiftUI

extension BoosterKind {
    /// Icon tint. Lives here rather than on the model so the enum stays
    /// free of SwiftUI.
    var tint: Color {
        switch self {
        case .boost: Theme.brandViolet
        case .bulkChat: Theme.online
        case .admirers: Theme.coin
        case .reveal: Theme.verified
        case .superChat: Theme.accent
        }
    }
}

struct BoosterCard: View {
    let kind: BoosterKind
    let count: Int
    /// Coin price shown on the card — it used to be visible only in the
    /// failure alert.
    var price: Int? = nil
    let onAdd: () -> Void
    /// Shown when count > 0 and the booster has a direct use (boost).
    var onUse: (() -> Void)? = nil

    @Environment(\.motion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count)")
                        .font(.click(.title3, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .contentTransition(.numericText())
                        .animation(motion.numeric, value: count)
                    Text(kind.label)
                        .font(.clickPlain(.footnote, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .layoutPriority(1)

                Spacer(minLength: 2)

                Button {
                    // Haptic comes from the .click style.
                    onAdd()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.primary))
                }
                .buttonStyle(.click)
                .accessibilityLabel("Buy more \(kind.label)\(price.map { " for \($0) coins" } ?? "")")
            }

            HStack(spacing: 8) {
                if let price {
                    HStack(spacing: 3) {
                        CoinView(size: 12)
                        Text("\(price)")
                            .font(.clickPlain(.caption2, weight: .heavy))
                            .foregroundStyle(Theme.secondary)
                    }
                    .accessibilityLabel("\(price) coins each")
                }

                Spacer(minLength: 0)

                if count > 0, let onUse {
                    Button {
                        onUse()
                    } label: {
                        Text("use")
                            .font(.click(.caption, weight: .heavy))
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(kind.tint, in: Capsule())
                    }
                    .buttonStyle(.click)
                    .accessibilityLabel("Use a \(kind.label)")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .cardSurface(radius: Theme.Metric.control)
        // .contain, not .combine — combining swallowed the buttons so
        // VoiceOver could never activate them.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(count) \(kind.label)")
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        BoosterCard(kind: .boost, count: 2, price: 25, onAdd: {}, onUse: {})
        BoosterCard(kind: .superChat, count: 0, price: 25, onAdd: {})
        BoosterCard(kind: .bulkChat, count: 1, price: 25, onAdd: {})
    }
    .padding()
    .background(Theme.background)
}
