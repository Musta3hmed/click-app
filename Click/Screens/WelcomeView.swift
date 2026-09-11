//
//  WelcomeView.swift
//  Click
//
//  Sign-in screen shown before RootView. A full-screen "lava" background of
//  drifting gradient blobs (driven by TimelineView, so it never stops),
//  floating sticker cards, the Click logo and the sign-in buttons. All auth
//  goes through AuthSession; no state is faked here.
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AuthSession.self) private var auth
    @State private var appeared = false

    var body: some View {
        ZStack {
            LavaBackground()

            FloatingStickers()

            VStack(spacing: 0) {
                Text("click")
                    .font(.click(.largeTitle, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .padding(.bottom, 28)
                    .accessibilityLabel("Click logo")

                Text("MAKE IT\nCLICK")
                    .font(.system(size: 56, design: .rounded).weight(.black).italic())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

                Text("Meet new people. Zero small talk.")
                    .font(.clickPlain(.headline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 12)

                Spacer()
                Spacer()

                signInStack
                    .padding(.horizontal, Theme.Metric.gutter)
                    .padding(.bottom, 12)
            }
            .padding(.top, 8)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Sign in

    private var signInStack: some View {
        VStack(spacing: 12) {
            if let message = auth.lastErrorMessage {
                Text(message)
                    .font(.clickPlain(.footnote, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .transition(.opacity)
                    .accessibilityLabel("Sign in error: \(message)")
            }

            SignInButton(symbol: "apple.logo", label: "Continue with Apple", inProgress: auth.isSigningIn) {
                Task { await auth.signIn(with: .apple) }
            }
            SignInButton(symbol: "g.circle.fill", label: "Continue with Google", inProgress: auth.isSigningIn) {
                Task { await auth.signIn(with: .google) }
            }

            if AuthConfig.isFullyMocked {
                Label("Demo mode — sign-in is simulated on this build", systemImage: "wrench.and.screwdriver.fill")
                    .font(.clickPlain(.caption2, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 2)
            }

            Text("By continuing you agree to our Terms & Privacy Policy.")
                .font(.clickPlain(.caption2))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 4)
        }
        .animation(.easeInOut(duration: 0.25), value: auth.lastErrorMessage)
    }
}

// MARK: - Sign-in button

private struct SignInButton: View {
    let symbol: String
    let label: String
    var inProgress = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if inProgress {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(label)
                    .font(.clickPlain(.headline, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(inProgress)
        .accessibilityLabel(label)
        .accessibilityHint(inProgress ? "Signing in" : "")
    }
}

// MARK: - Animated background

/// Drifting, breathing gradient blobs over the brand gradient — the Click
/// answer to Wizz's vortex. Positions are pure functions of time (sin/cos at
/// incommensurate frequencies), so the motion loops organically forever.
private struct LavaBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    Theme.brandGradient

                    blob(Theme.brandGold, r: 0.55 * w,
                         x: w * (0.25 + 0.18 * sin(t * 0.31)),
                         y: h * (0.22 + 0.10 * cos(t * 0.23)),
                         breathe: 1 + 0.12 * sin(t * 0.47))

                    blob(Theme.brandMagenta, r: 0.65 * w,
                         x: w * (0.80 + 0.15 * cos(t * 0.27 + 1.3)),
                         y: h * (0.55 + 0.12 * sin(t * 0.19 + 0.7)),
                         breathe: 1 + 0.10 * cos(t * 0.41))

                    blob(Theme.brandViolet.opacity(0.8), r: 0.6 * w,
                         x: w * (0.35 + 0.20 * sin(t * 0.17 + 2.1)),
                         y: h * (0.85 + 0.08 * cos(t * 0.29 + 1.9)),
                         breathe: 1 + 0.14 * sin(t * 0.37 + 0.4))

                    blob(Theme.brandOrange, r: 0.5 * w,
                         x: w * (0.65 + 0.22 * cos(t * 0.21 + 0.4)),
                         y: h * (0.30 + 0.14 * sin(t * 0.33 + 2.6)),
                         breathe: 1 + 0.10 * sin(t * 0.53 + 1.1))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, r: CGFloat, x: CGFloat, y: CGFloat, breathe: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: r * breathe, height: r * breathe)
            .position(x: x, y: y)
            .blur(radius: r * 0.35)
            .blendMode(.screen)
            .opacity(0.75)
    }
}

// MARK: - Floating stickers

/// Wizz-style tilted sticker cards bobbing gently around the headline.
/// SF Symbols, not emoji — emoji render as boxes in the iOS 26.3 simulator.
private struct FloatingStickers: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    ChatSticker(text: "u up for a click?")
                        .rotationEffect(.degrees(-8 + 3 * sin(t * 0.8)))
                        .position(x: w * 0.68, y: h * 0.17 + 6 * sin(t * 0.9))

                    ChatSticker(text: "no small talk", tint: Theme.online)
                        .rotationEffect(.degrees(7 + 3 * cos(t * 0.7 + 1.2)))
                        .position(x: w * 0.30, y: h * 0.76 + 7 * cos(t * 0.8 + 0.5))

                    SymbolSticker(symbol: "face.smiling.inverse", tint: Theme.brandPink)
                        .rotationEffect(.degrees(10 + 4 * sin(t * 0.6 + 2)))
                        .position(x: w * 0.14, y: h * 0.24 + 8 * sin(t * 0.75 + 1.6))

                    SymbolSticker(symbol: "bolt.fill", tint: Theme.brandViolet)
                        .rotationEffect(.degrees(-12 + 4 * cos(t * 0.65 + 0.3)))
                        .position(x: w * 0.86, y: h * 0.66 + 8 * cos(t * 0.85 + 2.4))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct ChatSticker: View {
    let text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.clickPlain(.subheadline, weight: .bold))
            .foregroundStyle(tint == .white ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

private struct SymbolSticker: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(tint)
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

#Preview {
    WelcomeView()
        .environment(AuthSession())
}
