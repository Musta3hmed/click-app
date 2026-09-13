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
    /// Lets the launch-placeholder logo carry into this screen.
    var logoNamespace: Namespace.ID

    @Environment(AuthSession.self) private var auth
    // Resolved through the motion environment - RootView is the single
    // accessibilityReduceMotion read (MEGA-BRIEF 5.3 cleanup).
    @Environment(\.motion) private var motion
    private var reduceMotion: Bool { motion.reduceMotion }
    @State private var appeared = false
    @State private var legalDocument: LegalDocument?
    @State private var showingEmailSignUp = false
    /// Hero type that still scales with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 56

    var body: some View {
        ZStack {
            // ONE TimelineView drives the lava mesh AND the stickers.
            WelcomeBackdrop(animated: !reduceMotion)

            VStack(spacing: 0) {
                Text("click")
                    .font(.click(.largeTitle, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                // Vector mark — centred by construction, no baked-in corner
                // radius fighting a clipShape, and no asset to maintain.
                ClickLogoView(size: 110)
                    .matchedGeometryEffect(id: "clickLogo", in: logoNamespace)
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                    // Fade, don't zoom, under Reduce Motion.
                    .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.7))
                    .padding(.bottom, 28)

                Text("MAKE IT\nCLICK")
                    .font(.system(size: heroSize, design: .rounded).weight(.black).italic())
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
            withAnimation(
                reduceMotion
                    ? Theme.Motion.screenFade
                    : Theme.Motion.screen.delay(0.1)
            ) {
                appeared = true
            }
        }
        .sheet(item: $legalDocument) { document in
            LegalSheet(document: document)
        }
        .sheet(isPresented: $showingEmailSignUp) {
            EmailSignUpSheet()
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
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Metric.chip, style: .continuous))
                    // Enters as its own element, not by shoving the stack.
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityLabel("Sign in error: \(message)")
            }

            // Only the tapped button spins; both stay disabled mid-flight.
            SignInButton(
                symbol: "apple.logo",
                label: "Continue with Apple",
                inProgress: auth.signingInWith == .apple,
                disabled: auth.isSigningIn
            ) {
                Task { await auth.signIn(with: .apple) }
            }
            SignInButton(
                symbol: "g.circle.fill",
                label: "Continue with Google",
                inProgress: auth.signingInWith == .google,
                disabled: auth.isSigningIn
            ) {
                Task { await auth.signIn(with: .google) }
            }
            SignInButton(
                symbol: "envelope.fill",
                label: "Sign up with email",
                inProgress: false,
                disabled: auth.isSigningIn
            ) {
                showingEmailSignUp = true
            }

            if AuthConfig.isFullyMocked {
                Label("Demo mode — sign-in is simulated on this build", systemImage: "wrench.and.screwdriver.fill")
                    .font(.clickPlain(.caption2, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 2)
            }

            // Actually openable — asking users to agree to documents they
            // cannot read is an App Review rejection.
            HStack(spacing: 4) {
                Text("By continuing you agree to our")
                Button("Terms") { legalDocument = .terms }
                    .underline()
                Text("&")
                Button("Privacy Policy") { legalDocument = .privacy }
                    .underline()
            }
            .font(.clickPlain(.caption2))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.top, 4)
        }
        .animation(Theme.Motion.screenFade, value: auth.lastErrorMessage)
    }
}

// MARK: - Email sign-up

/// Email + password. The password is validated but deliberately never
/// stored — no backend exists to check it against, and the sheet says so.
private struct EmailSignUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthSession.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metric.Space.m) {
                    TextField("email", text: $email)
                        .font(.clickPlain(.body, weight: .medium))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                        .accessibilityLabel("Email address")

                    SecureField("password (8+ characters)", text: $password)
                        .font(.clickPlain(.body, weight: .medium))
                        .textContentType(.newPassword)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous))
                        .accessibilityLabel("Password")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.clickPlain(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    Button {
                        submit()
                    } label: {
                        Text("create account")
                            .font(.click(.headline, weight: .heavy))
                            .foregroundStyle(Theme.onPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.Metric.primaryButton)
                            .background(Theme.primary, in: Capsule())
                    }
                    .buttonStyle(.click)
                    .accessibilityLabel("Create account")

                    Text("demo build - your password is checked but never stored, and nothing leaves this device.")
                        .font(.clickPlain(.footnote, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.top, Theme.Metric.sheetTopInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("sign up with email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        let looksLikeEmail = trimmed.contains("@")
            && trimmed.split(separator: "@").last?.contains(".") == true
            && !trimmed.contains(" ")
        guard looksLikeEmail else {
            errorMessage = "That doesn't look like an email address."
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password needs at least 8 characters."
            return
        }
        auth.signIn(withEmail: trimmed)
        dismiss()
    }
}

// MARK: - Legal documents

enum LegalDocument: String, Identifiable {
    case terms
    case privacy
    case guidelines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Terms of Service"
        case .privacy: "Privacy Policy"
        case .guidelines: "Community Guidelines"
        }
    }

    /// Honest placeholder copy for the pre-release build — a real document
    /// must land here before any public release.
    var body: String {
        switch self {
        case .terms:
            """
            Click is in early testing. By using this build you agree to: \
            be 18 or older; treat other people with respect; and accept that \
            accounts, coins and boosters are test data that may be reset at \
            any time. Coins have no monetary value and cannot be cashed out. \
            A full Terms of Service will replace this text before public \
            release.
            """
        case .privacy:
            """
            Click stores your profile, photos, messages and city-level \
            location on your device only. Nothing is uploaded to a server \
            in this build. Photos are stripped of metadata (including GPS) \
            on import. Signing out or deleting your account removes all of \
            this data from the device. A full Privacy Policy will replace \
            this text before public release.
            """
        case .guidelines:
            """
            Click is for meeting people, kindly. Be yourself — no \
            impersonation, no fake profiles. Be respectful — harassment, \
            hate and unwanted sexual content get accounts removed. Be an \
            adult — Click is 18+, no exceptions. If someone makes you \
            uncomfortable, use report or block from any card or chat; \
            blocking hides them everywhere immediately.
            """
        }
    }
}

struct LegalSheet: View {
    let document: LegalDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document.body)
                    .font(.clickPlain(.body))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Metric.gutter)
            }
            .background(Theme.background)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Sign-in button

private struct SignInButton: View {
    let symbol: String
    let label: String
    var inProgress = false
    var disabled = false
    let action: () -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Fixed-width cross-fade: the icon<->spinner swap must not
                // reflow the label.
                ZStack {
                    ProgressView()
                        .tint(.black)
                        .opacity(inProgress ? 1 : 0)
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .opacity(inProgress ? 0 : 1)
                }
                .frame(width: 24, height: 24)
                .animation(motion.screenFade, value: inProgress)

                Text(label)
                    .font(.clickPlain(.headline, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
        .buttonStyle(.click)
        .disabled(disabled || inProgress)
        .accessibilityLabel(label)
        .accessibilityHint(inProgress ? "Signing in" : "")
    }
}

// MARK: - Animated background

/// The welcome "lava" — now a GPU-native MeshGradient (no ~80pt blur
/// passes, no screen blend, no offscreen groups) — plus the floating
/// stickers, all driven by ONE TimelineView. GeometryReader sits outside
/// the timeline so layout isn't re-measured per frame. Under Reduce
/// Motion the timeline pauses at t=0: a static wash.
private struct WelcomeBackdrop: View {
    var animated = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            TimelineView(.animation(paused: !animated)) { timeline in
                let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0

                ZStack {
                    lavaMesh(at: t)

                    // All y-positions stay above ~0.62h: the sign-in stack
                    // owns the bottom third, and stickers must never
                    // collide with it. drawingGroup rasterises each
                    // sticker's shadow once; the per-frame transforms are
                    // then cheap.
                    ChatSticker(text: "u up for a click?")
                        .drawingGroup()
                        .rotationEffect(.degrees(-8 + 3 * sin(t * 0.8)))
                        .position(x: w * 0.68, y: h * 0.17 + 6 * sin(t * 0.9))

                    ChatSticker(text: "no small talk", tint: Theme.online)
                        .drawingGroup()
                        .rotationEffect(.degrees(7 + 3 * cos(t * 0.7 + 1.2)))
                        .position(x: w * 0.28, y: h * 0.60 + 6 * cos(t * 0.8 + 0.5))

                    SymbolSticker(symbol: "face.smiling.inverse", tint: Theme.brandPink)
                        .drawingGroup()
                        .rotationEffect(.degrees(10 + 4 * sin(t * 0.6 + 2)))
                        .position(x: w * 0.14, y: h * 0.24 + 8 * sin(t * 0.75 + 1.6))

                    SymbolSticker(symbol: "bolt.fill", tint: Theme.brandViolet)
                        .drawingGroup()
                        .rotationEffect(.degrees(-12 + 4 * cos(t * 0.65 + 0.3)))
                        .position(x: w * 0.86, y: h * 0.56 + 7 * cos(t * 0.85 + 2.4))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Full-strength brand mesh: the same drift idea as AmbientBackground
    /// but loud — this is the one hero surface.
    private func lavaMesh(at t: TimeInterval) -> MeshGradient {
        let drift = { (rate: Double, phase: Double, amplitude: Float) -> Float in
            amplitude * Float(sin(t * rate + phase))
        }

        let points: [SIMD2<Float>] = [
            [0, 0],
            [0.5 + drift(0.31, 0.0, 0.20), 0],
            [1, 0],
            [0, 0.5 + drift(0.23, 1.3, 0.22)],
            [0.5 + drift(0.27, 2.1, 0.26), 0.5 + drift(0.19, 4.2, 0.26)],
            [1, 0.5 + drift(0.21, 5.0, 0.22)],
            [0, 1],
            [0.5 + drift(0.29, 3.3, 0.20), 1],
            [1, 1]
        ]

        let colors: [Color] = [
            Theme.brandOrange, Theme.brandGold, Theme.brandCoral,
            Theme.brandCoral, Theme.brandMagenta, Theme.brandPink,
            Theme.brandViolet, Theme.brandPink, Theme.brandMagenta
        ]

        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
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
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.Metric.tile, style: .continuous))
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
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.Metric.tile, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

#Preview {
    @Previewable @Namespace var logo
    return WelcomeView(logoNamespace: logo)
        .environment(AuthSession())
}
