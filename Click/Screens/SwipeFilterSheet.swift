//
//  SwipeFilterSheet.swift
//  Click
//
//  Real deck filters behind the header "filters" capsule: age range,
//  verified-only, interests. They feed the deck filter next to the
//  existing seeking logic; stored per account (AccountEraser clears them).
//

import SwiftUI

struct SwipeFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(DefaultsKey.filterMinAge) private var minAge = 18
    @AppStorage(DefaultsKey.filterMaxAge) private var maxAge = 99
    @AppStorage(DefaultsKey.filterVerifiedOnly) private var verifiedOnly = false
    @AppStorage(DefaultsKey.filterInterests) private var interestsRaw = ""

    /// Interests offered for filtering — the union used by the seeded deck.
    private static let allInterests = [
        "art", "books", "coffee", "cooking", "dance", "film", "food",
        "gaming", "gym", "hiking", "music", "photography", "sports", "travel"
    ]

    private var selectedInterests: Set<String> {
        Set(interestsRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ageSection
                    verifiedSection
                    interestsSection
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.top, 20)
            }
            .background(Theme.background)
            .navigationTitle("filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("reset") { reset() }
                        .font(.clickPlain(.body, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .accessibilityLabel("Reset filters")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                        .font(.click(.body, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("age range")

            HStack(spacing: 16) {
                Stepper(value: $minAge, in: 18...maxAge) {
                    Text("from \(minAge)")
                        .font(.click(.headline, weight: .bold))
                        .foregroundStyle(Theme.primary)
                }
                .accessibilityLabel("Minimum age \(minAge)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .cardSurface(radius: Theme.Metric.control)

            HStack(spacing: 16) {
                Stepper(value: $maxAge, in: minAge...99) {
                    Text("to \(maxAge)")
                        .font(.click(.headline, weight: .bold))
                        .foregroundStyle(Theme.primary)
                }
                .accessibilityLabel("Maximum age \(maxAge)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .cardSurface(radius: Theme.Metric.control)
        }
    }

    private var verifiedSection: some View {
        Toggle(isOn: $verifiedOnly) {
            VStack(alignment: .leading, spacing: 2) {
                Text("verified only")
                    .font(.click(.headline, weight: .bold))
                    .foregroundStyle(Theme.primary)
                Text("only show profiles with the blue check.")
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .tint(Theme.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .cardSurface(radius: Theme.Metric.control)
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("interests")
            Text("show people who share at least one selected interest. none selected means everyone.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)

            FlowChips(
                all: Self.allInterests,
                selected: selectedInterests,
                toggle: toggle(_:)
            )
        }
        .padding(.bottom, 24)
    }

    private func toggle(_ interest: String) {
        var current = selectedInterests
        if current.contains(interest) {
            current.remove(interest)
        } else {
            current.insert(interest)
        }
        interestsRaw = current.sorted().joined(separator: ",")
    }

    private func reset() {
        Haptics.selection()
        minAge = 18
        maxAge = 99
        verifiedOnly = false
        interestsRaw = ""
    }
}

/// Simple wrapping chip grid.
private struct FlowChips: View {
    let all: [String]
    let selected: Set<String>
    let toggle: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(all, id: \.self) { interest in
                let isOn = selected.contains(interest)
                Button {
                    toggle(interest)
                } label: {
                    Text(interest)
                        .font(.click(.subheadline, weight: .bold))
                        .foregroundStyle(isOn ? Theme.onPrimary : Theme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isOn ? Theme.primary : Theme.surface, in: Capsule())
                }
                .buttonStyle(.clickQuiet)
                .accessibilityLabel(interest)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

#Preview {
    SwipeFilterSheet()
}
