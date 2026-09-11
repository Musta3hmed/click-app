//
//  RootView.swift
//  Click
//
//  Custom tab shell. A plain TabView would draw its own bar, so the screens
//  are swapped manually and FloatingTabBar is layered on top.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: AppTab = .chats

    @Query private var conversations: [Conversation]

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch selection {
                case .chats: ChatsView()
                case .swipe: SwipeView()
                case .profile: ProfileView()
                }
            }
            .transition(.opacity)

            FloatingTabBar(selection: $selection, badges: badges)
        }
        .task {
            MockData.seedIfNeeded(context)
        }
    }

    private var badges: [AppTab: Int] {
        let unread = conversations
            .filter { $0.isVisible && !( $0.participant?.isMuted ?? false) }
            .reduce(0) { $0 + $1.unreadCount }
        return unread > 0 ? [.chats: unread] : [:]
    }
}

#Preview {
    RootView()
        .modelContainer(MockData.previewContainer)
}
