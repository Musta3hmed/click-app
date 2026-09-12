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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .swipe
    @State private var chrome = ChromeState()
    /// Non-blocking welcome-back banner after >= 48h away (MEGA-BRIEF
    /// 4.5) — what's waiting, never an interstitial, never guilt.
    @State private var returnSummary: String?
    /// The launch logo carries into WelcomeView — same mark, free continuity.
    @Namespace private var logoNamespace

    @AppStorage(DefaultsKey.onboardingCompleted) private var onboardingCompleted = false
    @AppStorage(DefaultsKey.phoneVerified) private var phoneVerified = false

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                LaunchPlaceholder(logoNamespace: logoNamespace)
            case .signedOut:
                WelcomeView(logoNamespace: logoNamespace)
                    .transition(.opacity)
            case .signedIn:
                // Every account verifies a phone number before onboarding.
                if !phoneVerified {
                    PhoneVerificationView()
                        .transition(.opacity)
                } else if onboardingCompleted {
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
        .animation(Theme.Motion.screenFade, value: phoneVerified)
        // The single place Reduce Motion is read; everything below resolves
        // tiers through @Environment(\.motion).
        .environment(\.motion, ClickMotion(reduceMotion: reduceMotion))
    }

    private var mainShell: some View {
        ZStack(alignment: .bottom) {
            Theme.backgroundWash.ignoresSafeArea()

            Group {
                switch selection {
                case .chats: ChatsView()
                case .swipe: SwipeView()
                case .profile: ProfileView()
                }
            }
            .transition(.opacity)
            // Content cross-fades on screenFade, decoupled from the pill's
            // spring in the tab bar.
            .animation(Theme.Motion.screenFade, value: selection)

            if !chrome.tabBarHidden {
                // TabBarHost owns the badge @Query — a message write no
                // longer re-renders the entire shell.
                TabBarHost(selection: $selection)
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
        .onChange(of: chrome.requestedTab) { _, requested in
            guard let requested else { return }
            withAnimation(Theme.Motion.state) { selection = requested }
            chrome.requestedTab = nil
        }
        .environment(chrome)
        .task {
            MockData.seedIfNeeded(context)
            // After seeding, before anything reads interests: phase-4
            // stores hold legacy label-strings, the catalog wants ids.
            InterestCatalog.migrateLegacyStrings(in: context)
            // After the interest migration — candidate memberships are
            // derived from canonical interest ids.
            CommunityService.seedIfNeeded(context)
            Boost.foregroundTick(in: context)
            checkReturnGap()
            await DemoPhotos.seedIfNeeded(context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Boost.foregroundTick(in: context)
                checkReturnGap()
            }
        }
        .overlay(alignment: .top) { returnBanner }
        // Full-screen: a brand takeover inside a sheet's rounded card with
        // a grabber was a register mismatch.
        .fullScreenCover(isPresented: welcomeSheetBinding) {
            WelcomeCelebrationView(name: currentUserName) {
                // One animated helper for the selection mutation — the pill
                // used to teleport at the exact moment the app should feel
                // celebratory.
                withAnimation(Theme.Motion.state) { selection = .swipe }
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

    // MARK: - Welcome-back banner (MEGA-BRIEF 4.5)

    /// After >= 48h away, say what's actually waiting. Non-blocking,
    /// dismissible, no guilt, no countdowns.
    private func checkReturnGap() {
        let defaults = UserDefaults.standard
        let lastActive = defaults.object(forKey: DefaultsKey.lastActiveAt) as? Date
        defaults.set(Date.now, forKey: DefaultsKey.lastActiveAt)

        guard onboardingCompleted,
              let lastActive,
              Date.now.timeIntervalSince(lastActive) >= 48 * 60 * 60 else { return }

        var parts: [String] = []

        let unread = ((try? context.fetch(FetchDescriptor<Conversation>())) ?? [])
            .filter { $0.isVisible && $0.unreadCount > 0 }
            .count
        if unread > 0 {
            parts.append("\(unread) unread chat\(unread == 1 ? "" : "s")")
        }

        let unclaimed = ((try? context.fetch(FetchDescriptor<DailyReward>())) ?? [])
            .contains { !$0.isClaimed }
        if unclaimed {
            parts.append("your daily reward is ready")
        }

        // Everything that expires does so silently — acknowledge it.
        if let me = currentUsers.first(where: { !$0.isDeleted }),
           let until = me.boostedUntil, until < .now, until > lastActive {
            parts.append("your boost finished while you were away")
        }

        guard !parts.isEmpty else { return }
        withAnimation(Theme.Motion.state) {
            returnSummary = "welcome back — " + parts.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private var returnBanner: some View {
        if let returnSummary {
            HStack(spacing: 10) {
                Image(systemName: "hand.wave.fill")
                    .foregroundStyle(Theme.brandOrange)
                    .accessibilityHidden(true)
                Text(returnSummary)
                    .font(.clickPlain(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button {
                    withAnimation(Theme.Motion.state) { self.returnSummary = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.clickQuiet)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .cardSurface(radius: Theme.Metric.control)
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Launch placeholder

/// Shown while the Keychain (and, with real Apple auth, a bounded network
/// check) restores the session. The spinner is delayed 600ms so a fast
/// restore never flashes it; while waiting the logo breathes gently.
private struct LaunchPlaceholder: View {
    let logoNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSpinner = false

    var body: some View {
        ZStack {
            // launchGradient: full brand in light, warm near-dark in dark —
            // no orange flash into a black app.
            Theme.launchGradient.ignoresSafeArea()
            VStack(spacing: 20) {
                Group {
                    if reduceMotion {
                        ClickLogoView(size: 96)
                    } else {
                        PhaseAnimator([false, true]) { pulsing in
                            ClickLogoView(size: 96)
                                .scaleEffect(pulsing ? 1.05 : 1.0)
                        } animation: { _ in
                            Theme.Motion.screenFade.speed(0.22)
                        }
                    }
                }
                .matchedGeometryEffect(id: "clickLogo", in: logoNamespace)

                ProgressView()
                    .tint(.white)
                    .opacity(showSpinner ? 1 : 0)
                    .animation(Theme.Motion.screenFade, value: showSpinner)
            }
        }
        // .ignore so the label is actually announced — on a plain ZStack it
        // was dropped and VoiceOver read the unlabeled children instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Click is starting")
        .task {
            try? await Task.sleep(for: .seconds(0.6))
            showSpinner = true
        }
    }
}

// MARK: - Tab bar host

/// Owns the badge computation and its @Query so message writes re-render
/// only this leaf, never the whole shell (and its active screen).
private struct TabBarHost: View {
    @Binding var selection: AppTab

    @Query private var conversations: [Conversation]

    var body: some View {
        FloatingTabBar(selection: $selection, badges: badges)
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
