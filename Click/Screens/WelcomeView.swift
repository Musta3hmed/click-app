//
//  WelcomeView.swift
//  Click
//
//  Sign-in screen shown before RootView. A full-screen "lava" background of
//  drifting gradient blobs (driven by TimelineView, so it never stops),
//  floating sticker cards, the Click logo and mock sign-in buttons.
//  Sign-in state lives in @AppStorage("isSignedIn") — RootView flips on it.
//

import SwiftUI

struct WelcomeView: View {
    @AppStorage("isSignedIn") private var isSignedIn = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            LavaBackground()

            FloatingStickers()

            VStack(spacing: 0) {
                // Wordmark
                Text("click")
                    .font(.system(size: 44, design: .rounded).weight(.black).italic())
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                Spacer()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .padding(.bottom, 28)

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

                VStack(spacing: 12) {
                    SignInButton(symbol: "apple.logo", label: "Continue with Apple") {
                        signIn()
                    }
                    SignInButton(symbol: "envelope.fill", label: "Continue with Email") {
                        signIn()
                    }

                    Text("By continuing you agree to our Terms & Privacy Policy.")
                        .font(.clickPlain(.caption2))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                }
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

    private func signIn() {
        Haptics.notify(.success)
        withAnimation(.easeInOut(duration: 0.45)) {
            isSignedIn = true
        }
    }
}

// MARK: - Sign-in button

private struct SignInButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
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
                    // Base brand gradient (matches the logo).
                    LinearGradient(
                        colors: [Color(hex: 0xFFA24C), Color(hex: 0xFF6A4D), Color(hex: 0xFF2D62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    blob(Color(hex: 0xFFD36E), r: 0.55 * w,
                         x: w * (0.25 + 0.18 * sin(t * 0.31)),
                         y: h * (0.22 + 0.10 * cos(t * 0.23)),
                         breathe: 1 + 0.12 * sin(t * 0.47))

                    blob(Color(hex: 0xFF2D8F), r: 0.65 * w,
                         x: w * (0.80 + 0.15 * cos(t * 0.27 + 1.3)),
                         y: h * (0.55 + 0.12 * sin(t * 0.19 + 0.7)),
                         breathe: 1 + 0.10 * cos(t * 0.41))

                    blob(Color(hex: 0x8A2BE2).opacity(0.8), r: 0.6 * w,
                         x: w * (0.35 + 0.20 * sin(t * 0.17 + 2.1)),
                         y: h * (0.85 + 0.08 * cos(t * 0.29 + 1.9)),
                         breathe: 1 + 0.14 * sin(t * 0.37 + 0.4))

                    blob(Color(hex: 0xFF8A3D), r: 0.5 * w,
                         x: w * (0.65 + 0.22 * cos(t * 0.21 + 0.4)),
                         y: h * (0.30 + 0.14 * sin(t * 0.33 + 2.6)),
                         breathe: 1 + 0.10 * sin(t * 0.53 + 1.1))
                }
            }
        }
        .ignoresSafeArea()
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

                    ChatSticker(text: "no small talk 🔥", tint: Color(hex: 0x34C759))
                        .rotationEffect(.degrees(7 + 3 * cos(t * 0.7 + 1.2)))
                        .position(x: w * 0.30, y: h * 0.76 + 7 * cos(t * 0.8 + 0.5))

                    EmojiSticker(emoji: "😉")
                        .rotationEffect(.degrees(10 + 4 * sin(t * 0.6 + 2)))
                        .position(x: w * 0.14, y: h * 0.24 + 8 * sin(t * 0.75 + 1.6))

                    EmojiSticker(emoji: "⚡️")
                        .rotationEffect(.degrees(-12 + 4 * cos(t * 0.65 + 0.3)))
                        .position(x: w * 0.86, y: h * 0.66 + 8 * cos(t * 0.85 + 2.4))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
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

private struct EmojiSticker: View {
    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.system(size: 30))
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

#Preview {
    WelcomeView()
}
