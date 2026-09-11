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
    let onAdd: () -> Void

    var body: some View {
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
                    .animation(.snappy, value: count)
                Text(kind.label)
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .layoutPriority(1)

            Spacer(minLength: 2)

            Button {
                Haptics.impact(.light)
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.primary))
            }
            .buttonStyle(.click)
            .accessibilityLabel("Buy more \(kind.label)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .cardSurface(radius: Theme.Metric.control)
        // .contain, not .combine — combining swallowed the buy button so
        // VoiceOver could never activate it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(count) \(kind.label)")
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(BoosterKind.allCases) { kind in
            BoosterCard(kind: kind, count: 0) {}
        }
    }
    .padding()
    .background(Theme.background)
}
