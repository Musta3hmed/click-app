//
//  SafetyCenter.swift
//  Click
//
//  Report / block / mute. Required by App Store Review Guideline 1.2 for
//  apps with user-generated content. Blocking is immediate and global:
//  a blocked profile disappears from the swipe deck and the chat list.
//

import SwiftUI
import SwiftData

enum SafetyCenter {

    static func block(_ profile: UserProfile, in context: ModelContext) {
        profile.isBlocked = true
        // A blocked user should not keep generating unread badges.
        profile.isMuted = true
        try? context.save()
        Haptics.notify(.success)
    }

    static func unblock(_ profile: UserProfile, in context: ModelContext) {
        profile.isBlocked = false
        profile.isMuted = false
        try? context.save()
    }

    static func toggleMute(_ profile: UserProfile, in context: ModelContext) {
        profile.isMuted.toggle()
        try? context.save()
        Haptics.selection()
    }

    static func report(
        _ profile: UserProfile,
        reason: ReportReason,
        alsoBlock: Bool,
        surface: String? = nil,
        in context: ModelContext
    ) {
        profile.reportedReasonRaw = reason.rawValue
        profile.reportedAt = .now
        // Where the report came from ("deck", "deck lens:<community-id>",
        // "chats", ...) so a community-originated report is
        // distinguishable when the pipeline goes live.
        profile.reportedSurface = surface
        if alsoBlock {
            profile.isBlocked = true
            profile.isMuted = true
        }
        try? context.save()
        Haptics.notify(.success)
    }
}

// MARK: - Report sheet

struct ReportSheet: View {
    let profile: UserProfile
    var surface: String? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: ReportReason?
    @State private var alsoBlock = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ReportReason.allCases) { reason in
                        Button {
                            Haptics.selection()
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason.label)
                                    .foregroundStyle(Theme.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                        .fontWeight(.bold)
                                }
                            }
                        }
                        .accessibilityAddTraits(selectedReason == reason ? [.isSelected, .isButton] : .isButton)
                    }
                } header: {
                    Text("Why are you reporting \(profile.name)?")
                }

                if selectedReason == .selfHarm {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("If someone may be in danger")
                                .font(.clickPlain(.subheadline, weight: .bold))
                            Text("If you think they might hurt themselves, contact your local emergency number, or in Australia call Lifeline on 13 11 14. You matter too — support is there for you as well.")
                                .font(.clickPlain(.footnote))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Also block \(profile.name)", isOn: $alsoBlock)
                } footer: {
                    // Honest copy: Click has no backend yet, so no claim of a
                    // moderation team. Do NOT restore that sentence until a
                    // real report pipeline exists.
                    Text("Blocking removes them from your swipe deck and chats immediately. Click is in early testing: your report is saved on this device and will be submitted for review once reporting goes live.")
                }

                Section {
                    Button(role: .destructive) {
                        guard let selectedReason else { return }
                        SafetyCenter.report(profile, reason: selectedReason, alsoBlock: alsoBlock, surface: surface, in: context)
                        dismiss()
                    } label: {
                        Text("Submit report")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                    }
                    .disabled(selectedReason == nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Reusable safety menu

/// Drop-in overflow menu for any profile or conversation surface.
struct SafetyMenu: View {
    let profile: UserProfile
    var surface: String? = nil
    @Environment(\.modelContext) private var context
    @State private var showingReport = false
    @State private var confirmingBlock = false

    var body: some View {
        Menu {
            Button {
                SafetyCenter.toggleMute(profile, in: context)
            } label: {
                // Lowercase: Click draws this menu (casing rule).
                Label(
                    profile.isMuted ? "unmute" : "mute",
                    systemImage: profile.isMuted ? "bell.fill" : "bell.slash.fill"
                )
            }

            Button {
                showingReport = true
            } label: {
                Label("report", systemImage: "flag.fill")
            }

            Button(role: .destructive) {
                confirmingBlock = true
            } label: {
                Label("block", systemImage: "hand.raised.fill")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Safety options for \(profile.name)")
        .sheet(isPresented: $showingReport) {
            ReportSheet(profile: profile, surface: surface)
        }
        .confirmationDialog(
            "Block \(profile.name)?",
            isPresented: $confirmingBlock,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                SafetyCenter.block(profile, in: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will be removed from your swipe deck and chats. They won't be told.")
        }
    }
}

#Preview {
    ReportSheet(profile: UserProfile(name: "Maya Chen", age: 19))
        .modelContainer(MockData.previewContainer)
}
