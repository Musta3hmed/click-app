//
//  RootView.swift
//  Click
//
//  Routes between the three app phases — welcome (signed out), onboarding
//  (signed in, profile incomplete), and the tab shell — then hosts the
//  custom floating tab bar. A plain TabView would draw its own bar, so the
//  screens are swapped manually and FloatingTabBar is layered on top.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AuthSession.self) private var auth
    @State private var selection: AppTab = .swipe

    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    @Query private var conversations: [Conversation]

    var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                launchPlaceholder
            case .signedOut:
                WelcomeView()
                    .transition(.opacity)
            case .signedIn:
                if onboardingCompleted {
                    mainShell
                        .transition(.opacity)
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: auth.state)
        .animation(.easeInOut(duration: 0.4), value: onboardingCompleted)
    }

    /// Shown for the instant it takes to read the Keychain — brand wash so
    /// there is no white flash before WelcomeView.
    private var launchPlaceholder: some View {
        Theme.brandGradient.ignoresSafeArea()
    }

    private var mainShell: some View {
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
        .environment(AuthSession())
        .modelContainer(MockData.previewContainer)
}
