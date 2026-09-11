//
//  SettingsView.swift
//  Click
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @AppStorage("showMyState") private var showMyState = false
    @AppStorage("visibleInFindNewFriends") private var visibleInFind = false

    @State private var didCopyUsername = false
    @State private var confirmingSignOut = false

    private var me: UserProfile? { currentUsers.first }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                swipeSection
                customizationSection
                visibilitySection
                notificationsSection
                communitySection
                subscriptionSection
                privacySection
                signOutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
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

            NavigationLink {
                Text("Age verification is handled during sign-up.")
                    .font(.clickPlain(.body))
                    .padding()
            } label: {
                LabeledContent("age", value: ageDescription)
            }

            NavigationLink {
                Text("Location settings")
                    .font(.clickPlain(.body))
                    .padding()
            } label: {
                LabeledContent("location", value: me?.countryFlag ?? "🇦🇺")
            }

            NavigationLink {
                BlockedUsersView()
            } label: {
                Text("blocked users")
            }
        }
    }

    private var swipeSection: some View {
        Section {
            NavigationLink {
                Text("Interest preferences")
                    .font(.clickPlain(.body))
                    .padding()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("swipe preferences")
                    Text("We'll show you people who share at least one of the interests you select.")
                        .font(.clickPlain(.footnote))
                        .foregroundStyle(Theme.secondary)
                }
            }
        } header: {
            Text("swipe")
        } footer: {
            Text("Preferences subject to profile availability")
        }
    }

    private var customizationSection: some View {
        Section("customization") {
            NavigationLink("chat") {
                Text("Chat appearance").padding()
            }
            NavigationLink("change app icon") {
                Text("App icon picker").padding()
            }
        }
    }

    private var visibilitySection: some View {
        Section("visibility") {
            Toggle("show my state", isOn: $showMyState)
            Toggle("visible in find new friends", isOn: $visibleInFind)
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

    private var communitySection: some View {
        Section("community") {
            NavigationLink("guidelines") { Text("Community guidelines").padding() }
            NavigationLink("help") { Text("Help centre").padding() }
            NavigationLink("is my account restricted?") { Text("Account status").padding() }
            NavigationLink("submit a feature request") { Text("Feature requests").padding() }
            NavigationLink("join the beta") { Text("Beta programme").padding() }
            NavigationLink("write a review") { Text("Leave a review").padding() }
        }
    }

    private var subscriptionSection: some View {
        Section("subscription") {
            Button("restore my subscription") {}
                .foregroundStyle(Theme.primary)
        }
    }

    private var privacySection: some View {
        Section("privacy & safety") {
            NavigationLink("privacy policy") { Text("Privacy policy").padding() }
            NavigationLink("terms of service") { Text("Terms of service").padding() }
            NavigationLink("my data") { Text("Download or delete your data").padding() }
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingSignOut = true
            } label: {
                Text("disconnect")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.bold)
            }
            .confirmationDialog(
                "Disconnect?",
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
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
        return "\(me.age)"
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
        .modelContainer(MockData.previewContainer)
}
