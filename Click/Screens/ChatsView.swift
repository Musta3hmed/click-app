//
//  ChatsView.swift
//  Click
//

import SwiftUI
import SwiftData

struct ChatsView: View {
    @Query(sort: \Conversation.lastActivity, order: .reverse)
    private var conversations: [Conversation]

    @Query(filter: #Predicate<UserProfile> { !$0.isCurrentUser && !$0.isBlocked })
    private var candidates: [UserProfile]

    @State private var folder: ChatFolder = .messages
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                OverlappingSheet(ambient: true) {
                    VStack(spacing: 0) {
                        FolderTabs(selection: $folder, badgedFolders: badgedFolders)
                            .padding(.top, 18)

                        // The list itself scrolls — without this only the
                        // first few rows were reachable on a small screen.
                        ScrollView {
                            if visibleConversations.isEmpty {
                                EmptyChatsState(onlineCount: candidates.count * 547)
                                    .padding(.top, 40)
                            } else {
                                conversationList
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            // This tab lives in a NavigationStack with no title: hide the
            // bar so its inset doesn't push the header band lower than on
            // the other two tabs. ConversationView gets its bar back.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Conversation.self) { conversation in
                ConversationView(conversation: conversation)
                    .navigationTransition(.zoom(sourceID: conversation.id, in: zoom))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        TexturedHeader(title: "chats", texture: .clouds) {
            HStack(spacing: 10) {
                GlassCapsule {
                    Image(systemName: "gauge.with.needle.fill")
                        .foregroundStyle(.white)
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Theme.brandViolet)
                    CoinView(size: 18)
                }
                .font(.system(size: 16, weight: .bold))

                GlassCircleButton(systemImage: "ellipsis", accessibilityTitle: "More options") {}
            }
        }
    }

    // MARK: - List

    private var conversationList: some View {
        LazyVStack(spacing: 0) {
            ForEach(visibleConversations) { conversation in
                NavigationLink(value: conversation) {
                    ConversationRow(conversation: conversation)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: conversation.id, in: zoom)

                Divider()
                    .overlay(Theme.separator)
                    .padding(.leading, 84)
            }
        }
        .padding(.top, 8)
        .tabBarClearance()
    }

    /// Blocked participants are filtered out here, so blocking takes effect
    /// immediately without touching the stored conversations.
    private var visibleConversations: [Conversation] {
        conversations.filter { $0.isVisible && $0.folder == folder }
    }

    private var badgedFolders: Set<ChatFolder> {
        var result: Set<ChatFolder> = [.topPicks]
        for conversation in conversations where conversation.isVisible && conversation.unreadCount > 0 {
            result.insert(conversation.folder)
        }
        return result
    }
}

// MARK: - Folder tabs

private struct FolderTabs: View {
    @Binding var selection: ChatFolder
    let badgedFolders: Set<ChatFolder>

    var body: some View {
        // Horizontally scrollable: the four labels are `fixedSize`, so without
        // a scroll view they push the whole screen wider than the device at
        // larger Dynamic Type sizes.
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                ForEach(ChatFolder.allCases) { item in
                    tab(item)
                }
            }
            .padding(.horizontal, Theme.Metric.gutter)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func tab(_ item: ChatFolder) -> some View {
        let isSelected = selection == item

        Button {
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.2)) { selection = item }
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

                Rectangle()
                    .fill(isSelected ? Theme.primary : .clear)
                    .frame(height: 3)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Row

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            StickerAvatar(
                name: conversation.participant?.name ?? "?",
                size: 56,
                isOnline: conversation.participant?.isOnline ?? false
            )

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
                    .font(.clickPlain(.subheadline))
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
                SafetyMenu(profile: participant)
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Empty state

private struct EmptyChatsState: View {
    let onlineCount: Int

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

            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.online)
                    .frame(width: 9, height: 9)
                Text("tap to meet \(onlineCount.formatted(.number.notation(.compactName)))+ online people")
                    .font(.click(.subheadline, weight: .heavy))
                    .foregroundStyle(Theme.primary)
            }
            .padding(.top, 6)
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
        .modelContainer(MockData.previewContainer)
}
