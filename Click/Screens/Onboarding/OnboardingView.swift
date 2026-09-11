//
//  OnboardingView.swift
//  Click
//
//  Paged post-sign-in questionnaire. Every answer is written to the current
//  user's SwiftData row the moment its step is confirmed, and the step index
//  itself is persisted — killing the app mid-flow resumes at the same step.
//

import SwiftUI
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case name
    case birthDate
    case gender
    case seeking
    case photos
    case location

    var title: String {
        switch self {
        case .name: "what's your name?"
        case .birthDate: "when were you born?"
        case .gender: "how do you identify?"
        case .seeking: "who do you want to meet?"
        case .photos: "show yourself off"
        case .location: "where are you?"
        }
    }

    var subtitle: String {
        switch self {
        case .name: "First name only — it's what people see."
        case .birthDate: "Click is 18+. Your age shows, your birthday doesn't."
        case .gender: "Pick whatever fits."
        case .seeking: "Choose as many as you like. This filters your deck."
        case .photos: "At least 1, up to 6. Drag to reorder — first is your main."
        case .location: "City only. We never store your exact position."
        }
    }
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AuthSession.self) private var auth

    @AppStorage("onboardingStep") private var storedStep = 0
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    // Draft answers, hydrated from the profile row so resuming shows what
    // was already saved.
    @State private var name = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now
    @State private var birthDateTouched = false
    @State private var gender: Gender?
    @State private var seeking: Set<SeekingPreference> = []
    @State private var hydrated = false
    @State private var saveErrorMessage: String?

    private var step: OnboardingStep {
        OnboardingStep(rawValue: storedStep.clamped(to: 0...(OnboardingStep.allCases.count - 1))) ?? .name
    }

    private var profile: UserProfile? { currentUsers.first }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // Scrolls so large Dynamic Type can never push content (or the
            // wheel) out of reach; Continue stays pinned below.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.title)
                            .font(.click(.largeTitle, weight: .heavy))
                            .foregroundStyle(Theme.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text(step.subtitle)
                            .font(.clickPlain(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(nil, value: storedStep)

                    stepBody
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)

            continueButton
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.bottom, 16)
        }
        .background(Theme.background.ignoresSafeArea())
        .task { hydrate() }
        .alert(
            "Couldn't save",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(step == .name ? Theme.secondary.opacity(0.4) : Theme.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            .disabled(step == .name)
            .accessibilityLabel("Back")

            ProgressView(value: Double(storedStep + 1), total: Double(OnboardingStep.allCases.count))
                .tint(Theme.brandPink)
                .accessibilityLabel("Step \(storedStep + 1) of \(OnboardingStep.allCases.count)")

            // The exit that was missing: without it, an under-18 user or a
            // wrong-account sign-in was trapped in onboarding forever.
            Button {
                Haptics.selection()
                auth.signOut(erasing: context)
            } label: {
                Text("sign out")
                    .font(.clickPlain(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(height: 44)
            }
            .accessibilityLabel("Sign out")
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .name:
            NameStep(name: $name)
        case .birthDate:
            BirthDateStep(birthDate: $birthDate, touched: $birthDateTouched) {
                auth.signOut(erasing: context)
            }
        case .gender:
            GenderStep(selection: $gender)
        case .seeking:
            SeekingStep(selection: $seeking)
        case .photos:
            if let profile {
                PhotosStep(profile: profile)
            }
        case .location:
            if let profile {
                LocationStep(profile: profile)
            }
        }
    }

    private var continueButton: some View {
        Button {
            advance()
        } label: {
            Text(step == .location ? "let's go" : "continue")
                .font(.click(.headline, weight: .heavy))
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(canContinue ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.separator), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        .accessibilityLabel(step == .location ? "Finish onboarding" : "Continue")
    }

    // MARK: - Validation

    private var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
    }

    private var isAdult: Bool {
        UserProfile.age(from: birthDate) >= 18
    }

    private var canContinue: Bool {
        switch step {
        case .name: !trimmedName.isEmpty
        case .birthDate: birthDateTouched && isAdult
        case .gender: gender != nil
        case .seeking: !seeking.isEmpty
        case .photos: !(profile?.photos.isEmpty ?? true)
        case .location: profile?.city != nil
        }
    }

    // MARK: - Flow

    private func hydrate() {
        guard !hydrated else { return }
        hydrated = true

        let currentProviderID = auth.current?.providerUserID

        // A leftover row from a DIFFERENT credential is someone else's
        // identity — never resume it. Erase and start clean. (Sign-out also
        // erases; this is the belt to that braces.)
        if let existing = profile,
           existing.ownerProviderID != nil,
           existing.ownerProviderID != currentProviderID {
            AccountEraser.eraseCurrentAccount(in: context)
        }

        // Work with the concrete row, not the @Query result — the query does
        // not re-fetch within this call, so reading it back right after an
        // insert returns nil and skips the credential prefill.
        let row: UserProfile
        if let existing = profile, existing.ownerProviderID == currentProviderID {
            row = existing
        } else {
            // First entry: create the row now, bound to the credential.
            // Apple only sends name/email once, so AuthSession captured them
            // in the Keychain — this is the moment they reach SwiftData.
            row = UserProfile(name: "", age: 0, isCurrentUser: true)
            row.ownerProviderID = currentProviderID
            context.insert(row)
            try? context.save()
        }

        name = row.name
        if name.isEmpty, let credentialName = auth.current?.name {
            name = String(credentialName.split(separator: " ").first ?? "")
        }
        if let stored = row.birthDate {
            // Resuming this same credential's own mid-onboarding answers.
            birthDate = stored
            birthDateTouched = true
        }
        gender = row.gender
        seeking = Set(row.seeking)
    }

    private func advance() {
        guard canContinue, let profile else { return }
        Haptics.impact(.light)

        // Persist this step's answer before moving on.
        switch step {
        case .name:
            profile.name = trimmedName
        case .birthDate:
            profile.birthDate = birthDate
            profile.age = UserProfile.age(from: birthDate)
        case .gender:
            profile.gender = gender
        case .seeking:
            profile.seeking = Array(seeking)
        case .photos, .location:
            break  // Those steps save into the profile as they go.
        }

        do {
            try context.save()
        } catch {
            // A failed save (full disk) must not wave the user through with
            // a half-written profile.
            saveErrorMessage = "Couldn't save your answer — free up some space and try again."
            return
        }

        if step == .location {
            onboardingCompleted = true
            storedStep = 0
            Haptics.notify(.success)
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                storedStep += 1
            }
        }
    }

    private func goBack() {
        guard step != .name else { return }
        Haptics.selection()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            storedStep -= 1
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Step 1: name

private struct NameStep: View {
    @Binding var name: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("first name", text: $name)
                .font(.click(.title, weight: .heavy))
                .foregroundStyle(Theme.primary)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                .accessibilityLabel("First name")

            Text("\(name.count)/30")
                .font(.clickPlain(.caption, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear { focused = true }
        .onChange(of: name) { _, newValue in
            if newValue.count > 30 { name = String(newValue.prefix(30)) }
        }
    }
}

// MARK: - Step 2: date of birth (18+ hard gate)

private struct BirthDateStep: View {
    @Binding var birthDate: Date
    @Binding var touched: Bool
    let onSignOut: () -> Void

    /// Once an under-18 date is confirmed this becomes a terminal screen,
    /// not a live picker to fiddle with. "Fix my birth date" covers honest
    /// mis-scrolls; sign out is the real exit.
    @State private var showingRejection = false

    private var age: Int { UserProfile.age(from: birthDate) }

    var body: some View {
        VStack(spacing: 20) {
            if showingRejection {
                rejectionCard
            } else {
                DatePicker(
                    "Date of birth",
                    selection: Binding(
                        get: { birthDate },
                        set: { birthDate = $0; touched = true }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .accessibilityLabel("Date of birth")

                if !touched {
                    // Continue stays disabled until the wheel moves; say so.
                    Label("scroll the wheel to set your birthday", systemImage: "hand.point.up.left.fill")
                        .font(.clickPlain(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                } else if age >= 18 {
                    Label("you're \(age) — you're in", systemImage: "checkmark.circle.fill")
                        .font(.click(.headline, weight: .bold))
                        .foregroundStyle(Theme.online)
                } else {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { showingRejection = true }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingRejection)
        .onChange(of: touched) { _, isTouched in
            if isTouched && age < 18 { showingRejection = true }
        }
    }

    private var rejectionCard: some View {
        VStack(spacing: 12) {
            Label("Click is for 18 and over", systemImage: "hand.raised.fill")
                .font(.click(.headline, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("You can't use Click yet. Come back when you're 18 — we'll be here.")
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)

            Button {
                onSignOut()
            } label: {
                Text("sign out")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .accessibilityLabel("Sign out")

            Button("I picked the wrong date") {
                showingRejection = false
            }
            .font(.clickPlain(.footnote, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .accessibilityLabel("I picked the wrong date, go back to the date picker")
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
    }
}

// MARK: - Step 3: gender

private struct GenderStep: View {
    @Binding var selection: Gender?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Gender.allCases) { option in
                ChoiceRow(
                    label: option.label,
                    isSelected: selection == option
                ) {
                    selection = option
                }
            }
        }

    }
}

// MARK: - Step 4: seeking (multi-select)

private struct SeekingStep: View {
    @Binding var selection: Set<SeekingPreference>

    var body: some View {
        VStack(spacing: 12) {
            ForEach(SeekingPreference.allCases) { option in
                ChoiceRow(
                    label: option.label,
                    isSelected: selection.contains(option)
                ) {
                    toggle(option)
                }
            }
        }

    }

    /// "Everyone" subsumes the others, so keep the selection coherent.
    private func toggle(_ option: SeekingPreference) {
        if selection.contains(option) {
            selection.remove(option)
        } else if option == .everyone {
            selection = [.everyone]
        } else {
            selection.remove(.everyone)
            selection.insert(option)
        }
    }
}

// MARK: - Shared choice row

private struct ChoiceRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack {
                Text(label)
                    .font(.click(.headline, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.onPrimary : Theme.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.onPrimary : Theme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                isSelected ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.surface),
                in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    OnboardingView()
        .environment(AuthSession())
        .modelContainer(MockData.previewContainer)
}
