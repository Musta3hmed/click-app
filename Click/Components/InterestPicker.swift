//
//  InterestPicker.swift
//  Click
//
//  The one interest-picking surface: the whole catalogue grouped by
//  category, chips with SF Symbols, an optional selection limit with a
//  visible n/limit counter. Used by the profile editor (limit 8) and
//  the deck filter sheet (no limit).
//

import SwiftUI

struct InterestPicker: View {
    let selected: Set<String>
    /// nil = unlimited (the filter sheet); the editor passes
    /// InterestCatalog.maxSelected.
    let limit: Int?
    let toggle: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let limit {
                Text("\(selected.count)/\(limit)")
                    .font(.click(.footnote, weight: .heavy))
                    .foregroundStyle(selected.count >= limit ? Theme.accent : Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(selected.count) of \(limit) selected")
            }

            ForEach(InterestCatalog.grouped(), id: \.category) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.category.label)
                        .font(.click(.footnote, weight: .heavy))
                        .foregroundStyle(Theme.secondary)
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(group.interests) { interest in
                            chip(interest)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ interest: Interest) -> some View {
        let isOn = selected.contains(interest.id)
        let atLimit = limit.map { selected.count >= $0 } ?? false

        Button {
            toggle(interest.id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: interest.symbolName)
                    .font(.system(size: 11, weight: .bold))
                Text(interest.label)
                    .font(.click(.subheadline, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isOn ? Theme.onPrimary : Theme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(isOn ? Theme.primary : Theme.surface, in: Capsule())
        }
        .buttonStyle(.clickQuiet)
        .disabled(!isOn && atLimit)
        .accessibilityLabel(interest.label)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    ScrollView {
        InterestPicker(selected: ["coffee", "films"], limit: 8) { _ in }
            .padding()
    }
    .background(Theme.background)
}
