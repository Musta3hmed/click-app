//
//  EditProfileView.swift
//  Click
//
//  Profile editor. One save semantics: name, bio, gender, seeking and
//  interests are staged and land on "done"; cancel (or swiping the
//  sheet down) discards them. Photos and location reuse the onboarding
//  step views, which write through as you go — the copy says so.
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
    @State private var interests: [String] = []
    @State private var prompts: [PromptAnswer] = []
    @State private var hydrated = false
    @State private var showingPreview = false
    @State private var showingCommunities = false

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

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
                        interestsSection
                        communitiesSection(me)
                        promptsSection
                        locationSection(me)
                        previewSection
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                        .font(.clickPlain(.body, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { saveAndDismiss() }
                        .font(.click(.body, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .accessibilityLabel("Done")
                }
            }
        }
        // Keyed on the row's identity: the first appearance can race the
        // query, and hydrating from nil used to leave bio empty — which
        // "done" then wrote back, silently wiping it.
        .task(id: me?.id) { hydrate() }
        .sheet(isPresented: $showingPreview) {
            if let me {
                ProfileCardPreview(profile: me)
            }
        }
        .sheet(isPresented: $showingCommunities) {
            CommunitiesView()
        }
    }

    // MARK: - Sections

    private func photosSection(_ me: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("photos")
            Text("At least 1, up to 6. Drag to reorder — first is your main. Photos save as you go.")
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

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("interests")
            Text("pick up to \(InterestCatalog.maxSelected) — up to \(InterestCatalog.shownOnCard) show on your card, shared ones first.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)

            InterestPicker(
                selected: Set(interests),
                limit: InterestCatalog.maxSelected,
                toggle: toggleInterest(_:)
            )
        }
    }

    private func communitiesSection(_ me: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("communities")
            Text(me.memberships.isEmpty
                 ? "join a community to swipe through its people."
                 : "you're in \(me.memberships.count) of \(CommunityService.joinCap).")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Button {
                showingCommunities = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("browse communities")
                        .font(.click(.subheadline, weight: .heavy))
                }
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: Capsule())
            }
            .buttonStyle(.clickQuiet)
            .accessibilityLabel("Browse communities")
        }
    }

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("prompts")
            Text("answer up to \(PromptCatalog.maxAnswered) — they show on your card.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)

            ForEach($prompts) { $entry in
                promptRow($entry)
            }

            if prompts.count < PromptCatalog.maxAnswered {
                Menu {
                    ForEach(unansweredPrompts) { prompt in
                        Button(prompt.question) {
                            prompts.append(PromptAnswer(promptID: prompt.id, answer: ""))
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("add a prompt")
                            .font(.click(.subheadline, weight: .heavy))
                    }
                    .foregroundStyle(Theme.brandPink)
                    .padding(.vertical, 8)
                }
                .accessibilityLabel("Add a prompt")
            }
        }
    }

    private func promptRow(_ entry: Binding<PromptAnswer>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.wrappedValue.prompt?.question ?? entry.wrappedValue.promptID)
                    .font(.click(.subheadline, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                Spacer()
                Button {
                    prompts.removeAll { $0.promptID == entry.wrappedValue.promptID }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.clickQuiet)
                .accessibilityLabel("Remove prompt \(entry.wrappedValue.prompt?.question ?? "")")
            }

            TextField("your answer", text: entry.answer, axis: .vertical)
                .lineLimit(1...3)
                .font(.clickPlain(.body, weight: .medium))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                .accessibilityLabel("Answer to \(entry.wrappedValue.prompt?.question ?? "prompt")")
                .onChange(of: entry.wrappedValue.answer) { _, newValue in
                    if newValue.count > PromptCatalog.maxAnswerLength {
                        entry.wrappedValue.answer = String(newValue.prefix(PromptCatalog.maxAnswerLength))
                    }
                }
        }
    }

    private var unansweredPrompts: [Prompt] {
        let used = Set(prompts.map(\.promptID))
        return PromptCatalog.all.filter { !used.contains($0.id) }
    }

    private func locationSection(_ me: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("location")
            Text("Location saves as you go.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)
            LocationStep(profile: me)
        }
    }

    private var previewSection: some View {
        Button {
            showingPreview = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("see your card")
                    .font(.click(.headline, weight: .heavy))
            }
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.primary, in: Capsule())
        }
        .buttonStyle(.click)
        .accessibilityLabel("See your card")
        .accessibilityHint("Shows your profile the way other people see it")
    }

    // MARK: - Data

    private func hydrate() {
        guard !hydrated, let me else { return }
        hydrated = true
        name = me.name
        bio = me.bio
        gender = me.gender
        seeking = Set(me.seeking)
        interests = me.interests
        prompts = me.promptAnswers
    }

    /// Staged — lands on "done" with everything else. No manual haptic:
    /// the chip's .clickQuiet style owns it.
    private func toggleInterest(_ id: String) {
        if let index = interests.firstIndex(of: id) {
            interests.remove(at: index)
        } else if interests.count < InterestCatalog.maxSelected {
            interests.append(id)
        }
    }

    private func saveAndDismiss() {
        if let me, hydrated {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                me.name = String(trimmedName.prefix(30))
            }
            // Clearing the bio, gender or seeking is a deliberate act now
            // that hydration can't race an empty first appearance.
            me.bio = String(bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            me.gender = gender
            me.seeking = Array(seeking)
            me.interests = interests
            me.promptAnswers = prompts  // The setter validates and caps.
            try? context.save()
        }
        Haptics.notify(.success)
        dismiss()
    }
}

// MARK: - Card preview

/// Your card exactly as another person sees it — the same SwipeCard the
/// deck renders, with you as the profile and nobody as the viewer (so
/// no chip reads as "shared" with yourself).
struct ProfileCardPreview: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Query private var wallets: [Wallet]

    var body: some View {
        VStack(spacing: 16) {
            Text("your card")
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
                .padding(.top, 20)

            Text("this is what people see in the deck.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)

            GeometryReader { geo in
                let width = min(geo.size.width, geo.size.height * 0.72)
                let height = min(geo.size.height, width / 0.72)
                SwipeCard(profile: profile)
                    // Equipped card frame (cosmetic — earned, never
                    // bought, never visibility).
                    .overlay {
                        if let frameID = wallets.first?.equippedCardFrame {
                            RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous)
                                .strokeBorder(CosmeticCatalog.tint(frameID), lineWidth: 3)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: width, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, Theme.Metric.gutter)

            Button {
                dismiss()
            } label: {
                Text("done")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.bottom, 16)
            .accessibilityLabel("Done")
        }
        .background(Theme.background)
    }
}

#Preview {
    EditProfileView()
        .modelContainer(MockData.previewContainer)
}
