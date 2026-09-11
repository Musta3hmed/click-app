//
//  WelcomeCelebrationView.swift
//  Click
//
//  One-time celebratory sheet shown the first time a user reaches the app
//  after onboarding. The presenting flag lives in RootView
//  (@AppStorage "welcomePopupShown") — it never fires twice.
//

import SwiftUI

struct WelcomeCelebrationView: View {
    let name: String
    let onStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ZStack {
            Theme.brandGradient.ignoresSafeArea()

            if !reduceMotion {
                ConfettiView(duration: 2.2)
            }

            VStack(spacing: 18) {
                Spacer()

                ClickLogoView(size: 110)
                    .scaleEffect(appeared ? 1 : 0.5)

                Text(headline)
                    .font(.system(.largeTitle, design: .rounded).weight(.black).italic())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)

                Text("Your profile is live. Time to meet some people.")
                    .font(.clickPlain(.headline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)

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
                .accessibilityLabel("Start swiping")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .opacity(appeared ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: appeared) { _, new in new }
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.6, dampingFraction: 0.65).delay(0.1)
            ) {
                appeared = true
            }
            headingFocused = true
        }
        // Dismissible by swipe (sheet default) AND the button; modal for
        // VoiceOver so focus stays inside.
        .accessibilityAddTraits(.isModal)
    }

    private var headline: String {
        name.isEmpty ? "WELCOME\nTO CLICK" : "WELCOME,\n\(name.uppercased())"
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        WelcomeCelebrationView(name: "Jordan") {}
    }
}
