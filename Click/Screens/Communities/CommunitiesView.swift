//
//  CommunitiesView.swift
//  Click
//
//  Discover, join and leave communities. Not a fourth tab — presented as
//  a sheet from the profile tab and the editor. No member rosters
//  anywhere: members are reachable only through the deck lens.
//

import SwiftUI
import SwiftData

struct CommunitiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @Query(sort: [SortDescriptor(\Community.sortIndex), SortDescriptor(\Community.createdAt)])
    private var allCommunities: [Community]

    @State private var showingCreate = false
    @State private var joinRefusal: String?

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

    private var approved: [Community] {
        allCommunities.filter { $0.state == .approved }
    }

    /// The creator sees their own pending/rejected requests; nobody else
    /// ever does.
    private var myPending: [Community] {
        allCommunities.filter { $0.createdByCurrentUser && $0.state == .pending }
    }

    private var joinedIDs: Set<String> {
        Set(me?.memberships.map(\.communityID) ?? [])
    }

    private var suggested: [Community] {
        guard let me else { return [] }
        let mine = Set(me.interests)
        return approved.filter { community in
            !joinedIDs.contains(community.id) &&
            Set(community.interestIDs).intersection(mine).count >= 2
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if !myPending.isEmpty {
                        section("waiting for approval", communities: myPending)
                    }

                    let joined = approved.filter { joinedIDs.contains($0.id) }
                    if !joined.isEmpty {
                        section("your communities", communities: joined)
                    }

                    if !suggested.isEmpty {
                        section("suggested from your interests", communities: suggested)
                    }

                    let rest = approved.filter { !joinedIDs.contains($0.id) && !suggested.contains($0) }
                    if !rest.isEmpty {
                        section("all communities", communities: rest)
                    }

                    createButton
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Theme.background)
            .navigationTitle("communities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                        .font(.click(.body, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                        .accessibilityLabel("Done")
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateCommunitySheet()
        }
        .alert(
            "Can't join yet",
            isPresented: Binding(
                get: { joinRefusal != nil },
                set: { if !$0 { joinRefusal = nil } }
            )
        ) {
            Button("OK") { joinRefusal = nil }
        } message: {
            Text(joinRefusal ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("a community is a lens on your deck — join one to swipe through its people, and it shows on your card when you share it.")
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text("join up to \(CommunityService.joinCap).")
                .font(.clickPlain(.footnote, weight: .semibold))
                .foregroundStyle(Theme.secondary)
        }
    }

    private func section(_ title: String, communities: [Community]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title)
            VStack(spacing: 10) {
                ForEach(communities) { community in
                    CommunityRow(
                        community: community,
                        isJoined: joinedIDs.contains(community.id),
                        onJoin: { join(community) },
                        onLeave: { leave(community) }
                    )
                }
            }
        }
    }

    private var createButton: some View {
        Button {
            showingCreate = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("create a community")
                    .font(.click(.headline, weight: .heavy))
            }
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.primary, in: Capsule())
        }
        .buttonStyle(.click)
        .accessibilityLabel("Create a community")
        .accessibilityHint("Sends a request for approval")
    }

    private func join(_ community: Community) {
        guard let me else { return }
        if let refusal = CommunityService.join(community, as: me, in: context) {
            Haptics.notify(.error)
            joinRefusal = refusal
        }
    }

    private func leave(_ community: Community) {
        guard let me else { return }
        CommunityService.leave(community.id, as: me, in: context)
    }
}

// MARK: - Row

struct CommunityRow: View {
    let community: Community
    let isJoined: Bool
    var onJoin: (() -> Void)? = nil
    var onLeave: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: community.symbolName)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(CommunityService.tint(community.tintToken))
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.surface))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(community.name)
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                Text(community.state == .pending ? "waiting for approval" : community.summary)
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if community.state == .pending {
                Image(systemName: "hourglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .accessibilityHidden(true)
            } else if onJoin == nil && onLeave == nil {
                // Read-only context (the admin panel) — no dead buttons.
                EmptyView()
            } else if isJoined {
                Button {
                    onLeave?()
                } label: {
                    Text("leave")
                        .font(.click(.footnote, weight: .heavy))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.clickQuiet)
                .accessibilityLabel("Leave \(community.name)")
            } else {
                Button {
                    onJoin?()
                } label: {
                    Text("join")
                        .font(.click(.footnote, weight: .heavy))
                        .foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.click)
                .accessibilityLabel("Join \(community.name)")
            }
        }
        .padding(12)
        .cardSurface(radius: Theme.Metric.tile)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CommunitiesView()
        .modelContainer(MockData.previewContainer)
}
