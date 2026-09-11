//
//  EditProfileView.swift
//  Click
//
//  The profile was uneditable after onboarding — a review failure hiding
//  behind a dead "edit profile" button. Reuses the onboarding step views
//  (photos, gender, seeking, location) and adds a bio/interests editor.
//  Everything writes straight to the current user's row; "done" saves.
//

import SwiftUI
import SwiftData

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @State private var name = ""
    @State private var bio = ""
    @State private var gender: Gender?
    @State private var seeking: Set<SeekingPreference> = []
    @State private var hydrated = false

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

    /// Interests offered in the editor (same pool as the deck filter).
    private static let allInterests = [
        "art", "books", "coffee", "cooking", "dance", "film", "food",
        "gaming", "gym", "hiking", "music", "photography", "sports", "travel"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let me {
                    VStack(alignment: .leading, spacing: 28) {
                        photosSection(me)
                        nameSection
                        bioSection
                        genderSection
                        seekingSection
                        interestsSection(me)
                        locationSection(me)
                    }
                    .padding(.horizontal, Theme.Metric.gutter)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { saveAndDismiss() }
                        .font(.click(.body, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .accessibilityLabel("Done")
                }
            }
        }
        .task { hydrate() }
    }

    // MARK: - Sections

    private func photosSection(_ me: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("photos")
            Text("At least 1, up to 6. Drag to reorder — first is your main.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)
            PhotosStep(profile: me)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("name")
            TextField("first name", text: $name)
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                .accessibilityLabel("First name")
                .onChange(of: name) { _, newValue in
                    if newValue.count > 30 { name = String(newValue.prefix(30)) }
                }
        }
    }

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("bio")
            TextField("something short and you", text: $bio, axis: .vertical)
                .lineLimit(2...5)
                .font(.clickPlain(.body, weight: .medium))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                .accessibilityLabel("Bio")
                .onChange(of: bio) { _, newValue in
                    if newValue.count > 120 { bio = String(newValue.prefix(120)) }
                }
            Text("\(bio.count)/120")
                .font(.clickPlain(.caption, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("how you identify")
            GenderStep(selection: $gender)
        }
    }

    private var seekingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("who you want to meet")
            SeekingStep(selection: $seeking)
        }
    }

    private func interestsSection(_ me: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("interests")
            Text("pick up to 5 — the top 3 show on your card.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Self.allInterests, id: \.self) { interest in
                    let isOn = me.interests.contains(interest)
                    Button {
                        toggleInterest(interest, on: me)
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
                    .disabled(!isOn && me.interests.count >= 5)
                    .accessibilityLabel(interest)
                    .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    private func locationSection(_ me: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("location")
            LocationStep(profile: me)
        }
    }

    // MARK: - Data

    private func hydrate() {
        guard !hydrated, let me else { return }
        hydrated = true
        name = me.name
        bio = me.bio
        gender = me.gender
        seeking = Set(me.seeking)
    }

    private func toggleInterest(_ interest: String, on me: UserProfile) {
        if let index = me.interests.firstIndex(of: interest) {
            me.interests.remove(at: index)
        } else if me.interests.count < 5 {
            me.interests.append(interest)
        }
        try? context.save()
        Haptics.selection()
    }

    private func saveAndDismiss() {
        if let me {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                me.name = String(trimmedName.prefix(30))
            }
            me.bio = String(bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            if let gender {
                me.gender = gender
            }
            if !seeking.isEmpty {
                me.seeking = Array(seeking)
            }
            try? context.save()
        }
        Haptics.notify(.success)
        dismiss()
    }
}

#Preview {
    EditProfileView()
        .modelContainer(MockData.previewContainer)
}
