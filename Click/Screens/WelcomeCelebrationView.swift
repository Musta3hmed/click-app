//
//  WelcomeCelebrationView.swift
//  Click
//
//  One-time celebratory takeover shown the first time a user reaches the
//  app after onboarding (presented as a fullScreenCover from RootView; the
//  flag lives in @AppStorage "welcomePopupShown" — it never fires twice).
//  The entrance is gated on a short did-present delay so nothing animates
//  while the cover is still travelling, and the cascade uses the same
//  celebrate spring as the match overlay — celebrations move identically.
//

import SwiftUI

struct WelcomeCelebrationView: View {
    let name: String
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.motion) private var motion
    /// 0 nothing, 1 logo+confetti, 2 headline, 3 the rest.
    @State private var stage = 0
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ZStack {
            Theme.brandGradient.ignoresSafeArea()

            if !motion.reduceMotion && stage >= 1 {
                ConfettiView(duration: 2.2)
            }

            VStack(spacing: 18) {
                Spacer()

                ClickLogoView(size: 110)
                    .scaleEffect(stage >= 1 ? 1 : 0.5)
                    .opacity(stage >= 1 ? 1 : 0)

                Text(headline)
                    .font(.system(.largeTitle, design: .rounded).weight(.black).italic())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .opacity(stage >= 2 ? 1 : 0)
                    .scaleEffect(stage >= 2 ? 1 : 0.85)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)

                VStack(spacing: 8) {
                    Text("Your profile is live. Time to meet some people.")
                        .font(.clickPlain(.headline, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 6) {
                        CoinView(size: 20)
                        Text("welcome bonus: \(Wallet.welcomeBonus) coins")
                            .font(.click(.subheadline, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.16), in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Welcome bonus: \(Wallet.welcomeBonus) coins")
                }
                .opacity(stage >= 3 ? 1 : 0)

                Spacer()

                Button {
                    onStart()
                    dismiss()
                } label: {
                    Text("start swiping")
                        .font(.click(.headline, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.click)
                .opacity(stage >= 3 ? 1 : 0)
                .accessibilityLabel("Start swiping")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        // Haptic fires WITH the visible entrance, not on presentation.
        .sensoryFeedback(.success, trigger: stage) { _, new in new == 1 }
        .task {
            // Entrance gated on the cover's travel time — half the confetti
            // burst used to play before the screen was visible.
            try? await Task.sleep(for: .seconds(0.32))
            for step in 1...3 {
                withAnimation(motion.celebrate) { stage = step }
                try? await Task.sleep(for: .seconds(motion.stagger == 0 ? 0.02 : motion.stagger * 2))
            }
            headingFocused = true
        }
        .accessibilityAddTraits(.isModal)
    }

    private var headline: String {
        name.isEmpty ? "WELCOME\nTO CLICK" : "WELCOME,\n\(name.uppercased())"
    }
}

#Preview {
    Color.clear.fullScreenCover(isPresented: .constant(true)) {
        WelcomeCelebrationView(name: "Jordan") {}
    }
}
