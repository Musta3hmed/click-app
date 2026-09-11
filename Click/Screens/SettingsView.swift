//
//  SettingsView.swift
//  Click
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthSession.self) private var auth

    @State private var confirmingDelete = false
    @State private var deleteConfirmationText = ""
    @State private var deleteMismatch = false

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @AppStorage(DefaultsKey.showMyState) private var showMyState = false
    @AppStorage(DefaultsKey.appearance) private var appearanceRaw = AppearanceSetting.system.rawValue

    @State private var didCopyUsername = false
    @State private var copyRevertTask: Task<Void, Never>?
    @State private var confirmingSignOut = false
    @State private var legalDocument: LegalDocument?

    // isDeleted guard: sign-out erases the row while the dismissal
    // transition still has this screen on screen for a frame.
    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

    private var appearance: Binding<AppearanceSetting> {
        Binding(
            get: { AppearanceSetting(rawValue: appearanceRaw) ?? .system },
            set: { newValue in
                withAnimation(Theme.Motion.screenFade) {
                    appearanceRaw = newValue.rawValue
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                customizationSection
                visibilitySection
                notificationsSection
                communitySection
                privacySection
                signOutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $legalDocument) { document in
                LegalSheet(document: document)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.primary)
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("my account") {
            Button {
                UIPasteboard.general.string = username
                Haptics.notify(.success)
                didCopyUsername = true
                copyRevertTask?.cancel()
                copyRevertTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation(Theme.Motion.state) { didCopyUsername = false }
                }
            } label: {
                LabeledContent("username") {
                    HStack(spacing: 6) {
                        Text(username)
                            .foregroundStyle(Theme.secondary)
                        Image(systemName: didCopyUsername ? "checkmark" : "doc.on.doc")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
            .accessibilityHint("Copies your username")

            // Age isn't editable — a chevron promised a screen that could
            // never exist.
            LabeledContent("age", value: ageDescription)

            if let me {
                NavigationLink {
                    LocationSettingsView(profile: me)
                } label: {
                    LabeledContent("location", value: locationDescription)
                }
            }

            NavigationLink {
                BlockedUsersView()
            } label: {
                Text("blocked users")
            }
        }
    }

    private var customizationSection: some View {
        Section("customization") {
            Picker("appearance", selection: appearance) {
                ForEach(AppearanceSetting.allCases) { setting in
                    Text(setting.label).tag(setting)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var visibilitySection: some View {
        Section {
            Toggle("show when I'm online", isOn: $showMyState)
        } header: {
            Text("visibility")
        } footer: {
            Text("When off, other people don't see your online indicator.")
        }
        .tint(Theme.primary)
    }

    private var notificationsSection: some View {
        Section("system notifications") {
            Button("manage notifications") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .foregroundStyle(Theme.primary)
        }
    }

    // The dead rows (help, feature request, beta, account status, chat
    // appearance, app icon) are gone — every remaining control leads to a
    // real outcome.
    private var communitySection: some View {
        Section("community") {
            Button("guidelines") { legalDocument = .guidelines }
                .foregroundStyle(Theme.primary)

            Button("write a review") {
                // App Store write-review deep link (placeholder id until
                // the app is listed).
                guard let url = URL(string: "https://apps.apple.com/app/id0000000000?action=write-review") else { return }
                UIApplication.shared.open(url)
            }
            .foregroundStyle(Theme.primary)
        }
    }

    private var privacySection: some View {
        Section("privacy & safety") {
            Button("privacy policy") { legalDocument = .privacy }
                .foregroundStyle(Theme.primary)
            Button("terms of service") { legalDocument = .terms }
                .foregroundStyle(Theme.primary)
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingSignOut = true
            } label: {
                Text("sign out")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.bold)
            }
            .confirmationDialog(
                "Sign out?",
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    dismiss()
                    // Sign-out destroys the local account: profile, photos,
                    // chats, matches, wallet. Nothing is inherited by the
                    // next person to sign in on this phone.
                    auth.signOut(erasing: context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Signing out removes your profile, photos and chats from this phone.")
            }

            Button(role: .destructive) {
                deleteConfirmationText = ""
                confirmingDelete = true
            } label: {
                Text("delete account")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.bold)
            }
            .alert("Delete your account?", isPresented: $confirmingDelete) {
                TextField("type DELETE to confirm", text: $deleteConfirmationText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button("Delete forever", role: .destructive) {
                    guard deleteConfirmationText.trimmingCharacters(in: .whitespaces)
                        .uppercased() == "DELETE" else {
                        // An alert button always dismisses — a wrong entry
                        // must say so, never silently do nothing.
                        deleteMismatch = true
                        return
                    }
                    dismiss()
                    auth.signOut(erasing: context)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your profile, photos, matches and messages from this device. There is no undo. Type DELETE to confirm.")
            }
            .alert("Nothing was deleted", isPresented: $deleteMismatch) {
                Button("Try again") {
                    deleteConfirmationText = ""
                    confirmingDelete = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The confirmation didn't match. Type DELETE exactly to delete your account.")
            }
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private var username: String {
        guard let me else { return "unknown" }
        // Stable pseudo-handle derived from the account id.
        let raw = me.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let first = raw.prefix(8)
        let second = raw.dropFirst(8).prefix(6)
        return "\(first)-\(second)"
    }

    private var ageDescription: String {
        guard let me else { return "—" }
        return "\(me.displayAge)"
    }

    private var locationDescription: String {
        guard let me else { return "—" }
        if let city = me.city, let code = me.countryCode {
            return "\(city), \(code)"
        }
        return me.countryCode ?? "not set"
    }
}

// MARK: - Location settings

/// Changing city post-onboarding — reuses the onboarding LocationStep.
struct LocationSettingsView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("City only. We never store your exact position.")
                    .font(.clickPlain(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                LocationStep(profile: profile)
            }
            .padding(Theme.Metric.gutter)
        }
        .background(Theme.background)
        .navigationTitle("location")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Blocked users

struct BlockedUsersView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<UserProfile> { $0.isBlocked }, sort: \UserProfile.name)
    private var blocked: [UserProfile]

    var body: some View {
        List {
            if blocked.isEmpty {
                ContentUnavailableView(
                    "No blocked users",
                    systemImage: "hand.raised.slash",
                    description: Text("People you block will appear here.")
                )
            } else {
                ForEach(blocked) { profile in
                    HStack(spacing: 12) {
                        StickerAvatar(name: profile.name, size: 40)
                        Text(profile.name)
                            .font(.click(.headline, weight: .bold))
                        Spacer()
                        Button("Unblock") {
                            SafetyCenter.unblock(profile, in: context)
                        }
                        .font(.click(.subheadline, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("blocked users")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environment(AuthSession())
        .modelContainer(MockData.previewContainer)
}
