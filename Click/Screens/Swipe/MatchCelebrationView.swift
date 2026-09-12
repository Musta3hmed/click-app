//
//  MatchCelebrationView.swift
//  Click
//
//  Full-screen "IT CLICKED!" takeover on a mutual like. The parent owns
//  the entrance transition; this view stages its own internal cascade.
//

import SwiftUI

struct MatchCelebrationView: View {
    let profile: UserProfile
    let myName: String
    let onSayHi: () -> Void
    let onDismiss: () -> Void

    @Environment(\.motion) private var motion
    /// Staged cascade index: 0 nothing, 1 avatars, 2 heading, 3 the rest.
    @State private var stage = 0
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ZStack {
            // Opaque: at 0.96 four percent of the dark app bled through.
            Theme.brandGradient
                .ignoresSafeArea()

            if motion.reduceMotion == false {
                ConfettiView()
            }

            VStack(spacing: 24) {
                Spacer()

                HStack(spacing: -18) {
                    StickerAvatar(name: myName, size: 110)
                        .rotationEffect(.degrees(-8))
                        .scaleEffect(stage >= 1 ? 1 : 0.2)
                    StickerAvatar(name: profile.name, size: 110)
                        .rotationEffect(.degrees(8))
                        .scaleEffect(stage >= 1 ? 1 : 0.2)
                }
                .opacity(stage >= 1 ? 1 : 0)

                Text("IT CLICKED!")
                    .font(.system(.largeTitle, design: .rounded).weight(.black).italic())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .scaleEffect(stage >= 2 ? 1 : 0.6)
                    .opacity(stage >= 2 ? 1 : 0)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)

                Text("\(profile.name.split(separator: " ").first.map(String.init) ?? profile.name) likes you too")
                    .font(.clickPlain(.headline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .opacity(stage >= 3 ? 1 : 0)

                Spacer()

                // "say hi" jumps into the new conversation; "keep
                // swiping" stays in the deck.
                VStack(spacing: 14) {
                    Button {
                        onSayHi()
                    } label: {
                        Text("say hi to \(profile.name.split(separator: " ").first.map(String.init) ?? profile.name)")
                            .font(.click(.headline, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.click)
                    .accessibilityLabel("Say hi to \(profile.name)")

                    Button {
                        onDismiss()
                    } label: {
                        Text("keep swiping")
                            .font(.click(.headline, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.clickSilent)
                    .accessibilityLabel("Keep swiping")
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .opacity(stage >= 3 ? 1 : 0)
            }
        }
        .task {
            // Staged cascade on the shared celebrate spring; under Reduce
            // Motion the stagger is 0 and every step is a fade.
            for step in 1...3 {
                withAnimation(motion.celebrate) { stage = step }
                try? await Task.sleep(for: .seconds(motion.stagger == 0 ? 0.02 : motion.stagger * 2))
            }
            headingFocused = true
        }
        // A full-screen takeover: VoiceOver must not walk into the deck
        // behind it.
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("It's a match with \(profile.name)")
    }
}
