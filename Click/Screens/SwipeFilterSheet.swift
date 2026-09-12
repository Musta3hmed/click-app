//
//  SwipeFilterSheet.swift
//  Click
//
//  Real deck filters behind the header "filters" capsule: age range,
//  verified-only, interests (any/all). A live count shows how many
//  people the current filters leave BEFORE the sheet closes, so an
//  empty deck is never a surprise. Stored per account (AccountEraser
//  clears them).
//

import SwiftUI
import SwiftData

struct SwipeFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<UserProfile> { !$0.isCurrentUser && !$0.isBlocked },
        sort: \UserProfile.createdAt
    )
    private var candidates: [UserProfile]

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @AppStorage(DefaultsKey.filterMinAge) private var minAge = 18
    @AppStorage(DefaultsKey.filterMaxAge) private var maxAge = 99
    @AppStorage(DefaultsKey.filterVerifiedOnly) private var verifiedOnly = false
    @AppStorage(DefaultsKey.filterInterests) private var interestsRaw = ""
    @AppStorage(DefaultsKey.filterInterestsMatchAll) private var matchAll = false

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

    private var selectedInterests: Set<String> {
        Set(interestsRaw.split(separator: ",").map(String.init))
    }

    /// Identical logic to the deck itself — DeckFilter is the single source.
    private var matchCount: Int {
        let criteria = DeckFilter.Criteria(
            minAge: minAge, maxAge: maxAge, verifiedOnly: verifiedOnly,
            interests: selectedInterests, matchAll: matchAll
        )
        return DeckFilter.apply(criteria, to: DeckFilter.seekingFiltered(candidates, viewer: me)).count
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
            // The user learns the deck is about to be empty here, not
            // after closing the sheet.
            .safeAreaInset(edge: .bottom) { liveCount }
        }
        .presentationDetents([.medium, .large])
    }

    private var liveCount: some View {
        Text(matchCount == 0 ? "shows no one — the deck will show everyone instead" : "shows \(matchCount) \(matchCount == 1 ? "person" : "people")")
            .font(.click(.subheadline, weight: .heavy))
            .foregroundStyle(matchCount == 0 ? Theme.accent : Theme.primary)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.bar)
            .accessibilityLabel(matchCount == 0 ? "Shows no one. The deck will show everyone instead." : "Shows \(matchCount) people")
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
            Text("none selected means everyone.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)

            if !selectedInterests.isEmpty {
                Picker("match", selection: $matchAll) {
                    Text("any selected").tag(false)
                    Text("all selected").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Interest matching")
            }

            InterestPicker(
                selected: selectedInterests,
                limit: nil,
                toggle: toggle(_:)
            )
        }
        .padding(.bottom, 24)
    }

    private func toggle(_ id: String) {
        var current = selectedInterests
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        interestsRaw = current.sorted().joined(separator: ",")
    }

    private func reset() {
        Haptics.selection()
        minAge = 18
        maxAge = 99
        verifiedOnly = false
        interestsRaw = ""
        matchAll = false
    }
}

#Preview {
    SwipeFilterSheet()
        .modelContainer(MockData.previewContainer)
}
