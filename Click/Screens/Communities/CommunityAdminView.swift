//
//  CommunityAdminView.swift
//  Click
//
//  The moderation queue for user-created communities. With no backend,
//  approval happens on this device — the panel says so honestly. When a
//  backend exists this becomes a remote queue reviewed by real staff;
//  the approve/reject contract stays the same.
//

import SwiftUI
import SwiftData

struct CommunityAdminView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Community.createdAt)])
    private var allCommunities: [Community]

    @State private var rejecting: Community?

    private var pending: [Community] {
        allCommunities.filter { $0.state == .pending }
    }

    private var userCreatedApproved: [Community] {
        allCommunities.filter { !$0.isCurated && $0.state == .approved }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("every user-created community lands here before anyone can see it. approvals are local to this device until a backend exists — this panel is the moderation path.")
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("waiting for review")
                    if pending.isEmpty {
                        Text("nothing to review.")
                            .font(.clickPlain(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(pending) { community in
                                pendingRow(community)
                            }
                        }
                    }
                }

                if !userCreatedApproved.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("approved user communities")
                        Text("approval can be withdrawn — removing one deletes it and every membership.")
                            .font(.clickPlain(.footnote, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                        VStack(spacing: 10) {
                            ForEach(userCreatedApproved) { community in
                                approvedRow(community)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle("community moderation")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reject and delete this community?",
            isPresented: Binding(
                get: { rejecting != nil },
                set: { if !$0 { rejecting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reject", role: .destructive) {
                if let community = rejecting {
                    CommunityService.reject(community, in: context)
                    Haptics.impact(.medium)
                }
                rejecting = nil
            }
            Button("Cancel", role: .cancel) { rejecting = nil }
        } message: {
            Text("The name is removed everywhere and any memberships are deleted. This can't be undone.")
        }
    }

    private func pendingRow(_ community: Community) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CommunityRow(community: community, isJoined: false)

            HStack(spacing: 10) {
                Button {
                    CommunityService.approve(community, in: context)
                    Haptics.notify(.success)
                } label: {
                    Label("approve", systemImage: "checkmark")
                        .font(.click(.subheadline, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.online, in: Capsule())
                }
                .buttonStyle(.click)
                .accessibilityLabel("Approve \(community.name)")

                Button {
                    rejecting = community
                } label: {
                    Label("reject", systemImage: "xmark")
                        .font(.click(.subheadline, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.click)
                .accessibilityLabel("Reject \(community.name)")
            }
        }
    }

    private func approvedRow(_ community: Community) -> some View {
        HStack(spacing: 10) {
            CommunityRow(community: community, isJoined: false)
            Button {
                rejecting = community
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.surface))
            }
            .buttonStyle(.clickQuiet)
            .accessibilityLabel("Remove \(community.name)")
        }
    }
}

#Preview {
    NavigationStack {
        CommunityAdminView()
    }
    .modelContainer(MockData.previewContainer)
}
