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

    private var step: OnboardingStep {
        OnboardingStep(rawValue: storedStep.clamped(to: 0...(OnboardingStep.allCases.count - 1))) ?? .name
    }

    private var profile: UserProfile? { currentUsers.first }

    var body: some View {
        VStack(spacing: 0) {
            topBar

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
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.top, 24)
            .animation(nil, value: storedStep)

            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.top, 20)

            continueButton
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.bottom, 16)
        }
        .background(Theme.background.ignoresSafeArea())
        .task { hydrate() }
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
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
            }
            .disabled(step == .name)
            .accessibilityLabel("Back")

            ProgressView(value: Double(storedStep + 1), total: Double(OnboardingStep.allCases.count))
                .tint(Theme.brandPink)
                .accessibilityLabel("Step \(storedStep + 1) of \(OnboardingStep.allCases.count)")
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
            BirthDateStep(birthDate: $birthDate, touched: $birthDateTouched)
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

        if profile == nil {
            // First entry: create the row now, prefilled from the credential.
            // Apple only sends name/email once, so AuthSession captured them
            // in the Keychain — this is the moment they reach SwiftData.
            let row = UserProfile(name: "", age: 0, isCurrentUser: true)
            context.insert(row)
            try? context.save()
        }

        if let profile {
            name = profile.name
            if name.isEmpty, let credentialName = auth.current?.name {
                name = String(credentialName.split(separator: " ").first ?? "")
            }
            if let stored = profile.birthDate {
                birthDate = stored
                birthDateTouched = true
            }
            gender = profile.gender
            seeking = Set(profile.seeking)
        }
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
        try? context.save()

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
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel("First name")

            Text("\(name.count)/30")
                .font(.clickPlain(.caption, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity, alignment: .top)
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

    private var age: Int { UserProfile.age(from: birthDate) }

    var body: some View {
        VStack(spacing: 20) {
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

            if touched {
                if age >= 18 {
                    Label("you're \(age) — you're in", systemImage: "checkmark.circle.fill")
                        .font(.click(.headline, weight: .bold))
                        .foregroundStyle(Theme.online)
                } else {
                    // The hard gate. Continue stays disabled while under 18.
                    VStack(spacing: 6) {
                        Label("Click is for 18 and over", systemImage: "hand.raised.fill")
                            .font(.click(.headline, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        Text("You can't use Click yet. Come back when you're 18 — we'll be here.")
                            .font(.clickPlain(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: age >= 18)
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
        .frame(maxHeight: .infinity, alignment: .top)
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
        .frame(maxHeight: .infinity, alignment: .top)
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
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
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
