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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: AppTab = .swipe
    @State private var chrome = ChromeState()

    @AppStorage(DefaultsKey.onboardingCompleted) private var onboardingCompleted = false

    @Query private var conversations: [Conversation]

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

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
        .animation(Theme.Motion.screenFade, value: auth.state)
        .animation(Theme.Motion.screenFade, value: onboardingCompleted)
        // The single place Reduce Motion is read; everything below resolves
        // tiers through @Environment(\.motion).
        .environment(\.motion, ClickMotion(reduceMotion: reduceMotion))
    }

    /// Shown while the Keychain (and, with real Apple auth, a bounded
    /// network check) restores the session. Logo + spinner, not a bare
    /// gradient — restore can take a moment on weak signal.
    private var launchPlaceholder: some View {
        ZStack {
            Theme.brandGradient.ignoresSafeArea()
            VStack(spacing: 20) {
                ClickLogoView(size: 96)
                ProgressView()
                    .tint(.white)
            }
        }
        // .ignore so the label is actually announced — on a plain ZStack it
        // was dropped and VoiceOver read the unlabeled children instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Click is starting")
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

            if !chrome.tabBarHidden {
                FloatingTabBar(selection: $selection, badges: badges)
                    // Real margin on devices without a home indicator (SE).
                    .padding(.bottom, 10)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .animation(Theme.Motion.state, value: chrome.tabBarHidden)
        .environment(chrome)
        .task {
            MockData.seedIfNeeded(context)
            await DemoPhotos.seedIfNeeded(context)
        }
        .sheet(isPresented: welcomeSheetBinding) {
            WelcomeCelebrationView(name: currentUserName) {
                selection = .swipe
                welcomePopupShown = true
            }
        }
    }

    // MARK: - First-run welcome popup

    @AppStorage(DefaultsKey.welcomePopupShown) private var welcomePopupShown = false

    /// Fires exactly once: the first arrival in the shell after onboarding.
    private var welcomeSheetBinding: Binding<Bool> {
        Binding(
            get: { onboardingCompleted && !welcomePopupShown },
            set: { showing in if !showing { welcomePopupShown = true } }
        )
    }

    private var currentUserName: String {
        currentUsers.first { !$0.isDeleted }?.name ?? ""
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
