//
//  ChatsView.swift
//  Click
//
//  Four folders: messages, requests (super-like accept/deny), views
//  (profile-view counter) and matches (every mutual like lands here).
//

import SwiftUI
import SwiftData

struct ChatsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.motion) private var motion
    @Environment(ChromeState.self) private var chrome

    @Query(sort: \Conversation.lastActivity, order: .reverse)
    private var conversations: [Conversation]

    @Query(sort: \Match.matchedAt, order: .reverse)
    private var matches: [Match]

    @Query(filter: #Predicate<UserProfile> { !$0.isCurrentUser && !$0.isBlocked })
    private var candidates: [UserProfile]

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @Query private var wallets: [Wallet]

    @State private var folder: ChatFolder = .messages
    @State private var slideFromTrailing = true
    @State private var path = NavigationPath()
    @State private var denying: Conversation?
    /// Scroll-driven header collapse, 0 → 1 over the first 56pt of scroll.
    @State private var headerCollapse: CGFloat = 0
    @Namespace private var zoom

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header

                OverlappingSheet(ambient: true, collapseProgress: headerCollapse) {
                    VStack(spacing: 0) {
                        FolderTabs(selection: folderSelection, badgedFolders: badgedFolders)
                            .padding(.top, 20)

                        // The list itself scrolls — without this only the
                        // first few rows were reachable on a small screen.
                        ScrollView {
                            folderContent
                                .id(folder)
                                .transition(.push(from: slideFromTrailing ? .trailing : .leading))
                        }
                        .scrollIndicators(.hidden)
                        // Drives the header collapse 1:1 with the finger.
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            geometry.contentOffset.y + geometry.contentInsets.top
                        } action: { _, offset in
                            headerCollapse = min(max(offset / HeaderCollapse.distance, 0), 1)
                        }
                        .animation(motion.state, value: folder)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            // This tab lives in a NavigationStack with no title: hide the
            // bar so its inset doesn't push the header band lower than on
            // the other two tabs. ConversationView gets its bar back.
            .toolbar(.hidden, for: .navigationBar)
            // The celebration's "say hi" lands here after the tab switch.
            .onAppear { openRequestedConversation() }
            .onChange(of: chrome.requestedConversationID) { _, _ in
                openRequestedConversation()
            }
            .navigationDestination(for: Conversation.self) { conversation in
                // Reduce Motion gets the standard push instead of the zoom.
                if motion.reduceMotion {
                    ConversationView(conversation: conversation)
                } else {
                    ConversationView(conversation: conversation)
                        .navigationTransition(.zoom(sourceID: conversation.id, in: zoom))
                }
            }
            .confirmationDialog(
                "Deny and delete this request?",
                isPresented: Binding(
                    get: { denying != nil },
                    set: { if !$0 { denying = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Deny request", role: .destructive) {
                    if let conversation = denying { deny(conversation) }
                    denying = nil
                }
                Button("Cancel", role: .cancel) { denying = nil }
            } message: {
                Text("The request and its message are removed. This can't be undone.")
            }
        }
    }

    private func openRequestedConversation() {
        guard let id = chrome.requestedConversationID,
              let conversation = conversations.first(where: { $0.id == id }) else { return }
        chrome.requestedConversationID = nil
        path.append(conversation)
    }

    /// Tab writes go through here so the list slide knows its direction.
    private var folderSelection: Binding<ChatFolder> {
        Binding(
            get: { folder },
            set: { newValue in
                let indices = ChatFolder.allCases
                let old = indices.firstIndex(of: folder) ?? 0
                let new = indices.firstIndex(of: newValue) ?? 0
                slideFromTrailing = new >= old
                folder = newValue
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        TexturedHeader(title: "chats", texture: .clouds, collapseProgress: headerCollapse) {
            HStack(spacing: 10) {
                // Real coin balance; taps through to the profile wallet.
                Button {
                    chrome.requestedTab = .profile
                } label: {
                    GlassCapsule {
                        if me?.isBoosted == true {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(Theme.brandViolet)
                        }
                        CoinView(size: 18)
                        Text("\(wallets.first?.coins ?? 0)")
                            .font(.click(.footnote, weight: .heavy))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                }
                .buttonStyle(.clickSilent)
                .accessibilityLabel("\(wallets.first?.coins ?? 0) coins\(me?.isBoosted == true ? ", boost active" : "")")
                .accessibilityHint("Opens your wallet on the profile tab")

                Menu {
                    Button {
                        markAllRead()
                    } label: {
                        Label("mark all read", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background {
                            Circle().fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .light)
                        }
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                }
                .accessibilityLabel("More options")
            }
        }
    }

    private func markAllRead() {
        for conversation in conversations where conversation.unreadCount > 0 {
            conversation.unreadCount = 0
        }
        try? context.save()
        Haptics.notify(.success)
    }

    // MARK: - Folder content

    @ViewBuilder
    private var folderContent: some View {
        switch folder {
        case .messages, .requests:
            if visibleConversations.isEmpty {
                emptyState
            } else {
                conversationList
            }
        case .topPicks:
            if visibleMatches.isEmpty {
                emptyState
            } else {
                matchesList
            }
        case .views:
            viewsSurface
        }
    }

    private var conversationList: some View {
        LazyVStack(spacing: 0) {
            ForEach(visibleConversations) { conversation in
                if folder == .requests && conversation.isPendingRequest {
                    RequestRow(
                        conversation: conversation,
                        onAccept: { accept(conversation) },
                        onDeny: { denying = conversation }
                    )
                    .matchedTransitionSource(id: conversation.id, in: zoom) { source in
                        source.clipShape(.rect(cornerRadius: Theme.Metric.tile))
                    }
                } else {
                    NavigationLink(value: conversation) {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                    // Configured source: the zoom lifts a rounded card, not
                    // a raw rectangle.
                    .matchedTransitionSource(id: conversation.id, in: zoom) { source in
                        source.clipShape(.rect(cornerRadius: Theme.Metric.tile))
                    }
                }

                Divider()
                    .overlay(Theme.separator)
                    .padding(.leading, 84)
            }
        }
        .padding(.top, 8)
        // Rows animate in/out (accepted requests slide away smoothly
        // instead of snapping).
        .animation(motion.state, value: visibleConversations.map(\.id))
        .tabBarClearance()
    }

    // MARK: - Matches (every Match row finally lands somewhere visible)

    private var matchesList: some View {
        LazyVStack(spacing: 0) {
            ForEach(visibleMatches, id: \.id) { match in
                if let profile = match.profile {
                    Button {
                        openConversation(with: profile)
                    } label: {
                        MatchRow(match: match)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(Theme.separator)
                        .padding(.leading, 84)
                }
            }
        }
        .padding(.top, 8)
        .tabBarClearance()
    }

    /// Newest match per profile — a re-like after rewind must not double up.
    private var visibleMatches: [Match] {
        var seen = Set<UUID>()
        return matches.filter { match in
            guard let profile = match.profile, !profile.isBlocked, !profile.isCurrentUser else { return false }
            return seen.insert(profile.id).inserted
        }
    }

    private func openConversation(with profile: UserProfile) {
        Haptics.selection()
        if let existing = conversations.first(where: { $0.participant?.id == profile.id }) {
            path.append(existing)
            return
        }
        let conversation = Conversation(participant: profile, folder: .messages)
        context.insert(conversation)
        try? context.save()
        path.append(conversation)
    }

    // MARK: - Views folder

    private var viewsSurface: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brandViolet)
                .accessibilityHidden(true)

            Text("\(wallets.first?.profileViews ?? 0)")
                .font(.click(.largeTitle, weight: .black))
                .foregroundStyle(Theme.primary)
                .contentTransition(.numericText())

            Text((wallets.first?.profileViews ?? 0) == 1 ? "profile view" : "profile views")
                .font(.click(.headline, weight: .heavy))
                .foregroundStyle(Theme.primary)

            Text(
                me?.isBoosted == true
                    ? "boost active — your profile is getting around."
                    : "use a boost to put your profile in front of more people."
            )
            .font(.clickPlain(.subheadline, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, Theme.Metric.gutter)
        .tabBarClearance()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Request accept / deny

    private func accept(_ conversation: Conversation) {
        Haptics.notify(.success)
        withAnimation(motion.state) {
            conversation.requestState = .accepted
            conversation.folder = .messages
            conversation.lastActivity = .now
        }
        try? context.save()
    }

    private func deny(_ conversation: Conversation) {
        Haptics.impact(.medium)
        withAnimation(motion.state) {
            conversation.requestState = .denied
            context.delete(conversation)  // Messages cascade.
        }
        try? context.save()
    }

    // MARK: - Filtering & badges

    /// Blocked participants are filtered out here, so blocking takes effect
    /// immediately without touching the stored conversations.
    private var visibleConversations: [Conversation] {
        conversations.filter { $0.isVisible && $0.folder == folder }
    }

    private var badgedFolders: Set<ChatFolder> {
        var result: Set<ChatFolder> = []
        for conversation in conversations where conversation.isVisible && conversation.unreadCount > 0 {
            result.insert(conversation.folder)
        }
        return result
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        switch folder {
        case .messages:
            EmptyChatsState(onlineCount: candidates.filter(\.isOnline).count) {
                chrome.requestedTab = .swipe
            }
            .padding(.top, 40)
        case .requests:
            FolderEmptyState(
                systemImage: "star.circle",
                title: "no requests",
                message: "super likes sent to you show up here for you to accept or deny."
            )
        case .topPicks:
            FolderEmptyState(
                systemImage: "heart.circle",
                title: "no matches yet",
                message: "when you and someone else both like each other, they land here."
            )
        case .views:
            // viewsSurface renders its own zero state.
            EmptyView()
        }
    }
}

// MARK: - Folder tabs

private struct FolderTabs: View {
    @Binding var selection: ChatFolder
    let badgedFolders: Set<ChatFolder>

    @Environment(\.motion) private var motion
    @Namespace private var underline

    var body: some View {
        // Horizontally scrollable: the four labels are `fixedSize`, so without
        // a scroll view they push the whole screen wider than the device at
        // larger Dynamic Type sizes.
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(ChatFolder.allCases) { item in
                        tab(item)
                            .id(item)
                    }
                }
                .padding(.horizontal, Theme.Metric.gutter)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, newValue in
                withAnimation(motion.state) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func tab(_ item: ChatFolder) -> some View {
        let isSelected = selection == item

        Button {
            Haptics.selection()
            withAnimation(motion.state) { selection = item }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text(item.label)
                        .font(.click(.headline, weight: .heavy))
                        .foregroundStyle(isSelected ? Theme.primary : Theme.secondary)

                    if badgedFolders.contains(item) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 7, height: 7)
                    }
                }

                // One underline that slides between tabs, instead of two
                // cross-fading.
                ZStack {
                    Rectangle().fill(.clear).frame(height: 3)
                    if isSelected {
                        Rectangle()
                            .fill(Theme.primary)
                            .frame(height: 3)
                            .matchedGeometryEffect(id: "folderUnderline", in: underline)
                    }
                }
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Rows

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.participant?.name ?? "Unknown")
                        .font(.click(.headline, weight: .heavy))
                        .foregroundStyle(Theme.primary)

                    if conversation.participant?.isMuted == true {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                    }
                }

                Text(conversation.preview)
                    .font(.clickPlain(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                Text(conversation.lastActivity, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.clickPlain(.caption2, weight: .medium))
                    .foregroundStyle(Theme.secondary)

                if conversation.unreadCount > 0 && conversation.participant?.isMuted != true {
                    // The count, not a bare dot — 8 unread should look
                    // different from 1.
                    Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                        .font(.clickPlain(.caption2, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule())
                        .accessibilityLabel("\(conversation.unreadCount) unread")
                }
            }

            if let participant = conversation.participant {
                SafetyMenu(profile: participant, surface: "chats")
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.vertical, 12)
        .background {
            // Star carries the super-like signal; the tint is reinforcement
            // only (never colour alone for colour-blind users).
            if conversation.isSuperLike {
                Theme.brandGradient.opacity(0.06)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    @ViewBuilder
    private var avatar: some View {
        StickerAvatar(
            name: conversation.participant?.name ?? "?",
            size: 56,
            isOnline: conversation.participant?.isOnline ?? false
        )
        .overlay(alignment: .bottomTrailing) {
            if conversation.isSuperLike {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Theme.brandViolet))
                    .offset(x: 3, y: 3)
            }
        }
    }

    private var rowAccessibilityLabel: String {
        var label = conversation.participant?.name ?? "Unknown"
        if conversation.isSuperLike { label += ", super like request" }
        label += ". \(conversation.preview)"
        return label
    }
}

/// Pending super-like request: the row navigates, the trailing buttons
/// accept or deny. Structured as siblings so the link can't swallow them.
private struct RequestRow: View {
    let conversation: Conversation
    let onAccept: () -> Void
    let onDeny: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: conversation) {
                ConversationRow(conversation: conversation)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.online))
                }
                .buttonStyle(.click)
                .accessibilityLabel("accept request from \(conversation.participant?.name ?? "unknown")")

                Button(action: onDeny) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.accent))
                }
                .buttonStyle(.click)
                .accessibilityLabel("deny request from \(conversation.participant?.name ?? "unknown")")
            }
            .padding(.trailing, Theme.Metric.gutter)
        }
    }
}

private struct MatchRow: View {
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            StickerAvatar(
                name: match.profile?.name ?? "?",
                size: 56,
                isOnline: match.profile?.isOnline ?? false
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(match.profile?.name ?? "Unknown")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                Text("it clicked \(match.matchedAt.formatted(.relative(presentation: .named)))")
                    .font(.clickPlain(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "bubble.left.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.brandPink)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.profile?.name ?? "Unknown"), matched \(match.matchedAt.formatted(.relative(presentation: .named))). Opens the conversation.")
    }
}

// MARK: - Empty states

private struct FolderEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Theme.brandPink)
                .accessibilityHidden(true)
            Text(title)
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)
            Text(message)
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.horizontal, Theme.Metric.gutter)
        .tabBarClearance()
    }
}

private struct EmptyChatsState: View {
    let onlineCount: Int
    let onMeetPeople: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.headerTop)
                .accessibilityHidden(true)

            Text("no chats yet")
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)

            Text("start swiping to get your first chats.")
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)

            CurlyArrow()
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .frame(width: 110, height: 150)
                .padding(.top, 26)
                .accessibilityHidden(true)

            // A real button — it switches to the swipe tab, and the count
            // is the actual number of online candidates.
            Button(action: onMeetPeople) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.online)
                        .frame(width: 9, height: 9)
                    Text("tap to meet \(onlineCount) online people")
                        .font(.click(.subheadline, weight: .heavy))
                        .foregroundStyle(Theme.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.click)
            .padding(.top, 6)
            .accessibilityLabel("Meet \(onlineCount) online people")
            .accessibilityHint("Switches to the swipe tab")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.bottom, Theme.Metric.tabBarClearance)
    }
}

/// Hand-drawn looping arrow from the reference, as a parametric path.
private struct CurlyArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.72, y: h * 0.02))
        path.addCurve(
            to: CGPoint(x: w * 0.30, y: h * 0.36),
            control1: CGPoint(x: w * 0.18, y: h * 0.06),
            control2: CGPoint(x: w * 0.16, y: h * 0.30)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.66, y: h * 0.40),
            control1: CGPoint(x: w * 0.52, y: h * 0.44),
            control2: CGPoint(x: w * 0.80, y: h * 0.30)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.44, y: h * 0.94),
            control1: CGPoint(x: w * 0.48, y: h * 0.54),
            control2: CGPoint(x: w * 0.34, y: h * 0.72)
        )

        // Arrowhead
        path.move(to: CGPoint(x: w * 0.20, y: h * 0.76))
        path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.94))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.68))

        return path
    }
}

#Preview {
    ChatsView()
        .environment(ChromeState())
        .modelContainer(MockData.previewContainer)
}
