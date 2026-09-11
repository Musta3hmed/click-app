//
//  BoosterCard.swift
//  Click
//

import SwiftUI

struct BoosterCard: View {
    let kind: BoosterKind
    let count: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(kind.emoji)
                .font(.system(size: 30))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.click(.title3, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                Text(kind.label)
                    .font(.clickPlain(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Button {
                Haptics.impact(.light)
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buy more \(kind.label)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .cardSurface(radius: 20)
        .accessibilityElement(children: .combine)
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
