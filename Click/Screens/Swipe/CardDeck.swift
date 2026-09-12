//
//  CardDeck.swift
//  Click
//
//  Owns drag state so a drag frame re-renders only the deck, never the
//  header/composer/toast. Drag is the like/pass mechanism: the top card
//  follows the finger, commits past the distance threshold OR on a
//  flick, and flies off carrying the throw's velocity.
//

import SwiftUI

struct DeckCommand: Equatable {
    let liked: Bool
    /// Distinguishes two identical commands in a row.
    let id = UUID()
}

struct CardDeck: View {
    let cards: [UserProfile]
    /// The viewer's own profile — shared-interest chips need both sides.
    let viewer: UserProfile?
    @Binding var isBusy: Bool
    @Binding var command: DeckCommand?
    let onCommitStart: (UserProfile, Bool) -> Void
    let onFlyOffComplete: (UserProfile, Bool) -> Void
    let onReset: () -> Void

    @Environment(\.motion) private var motion
    @State private var drag: CGSize = .zero
    @State private var flyingAway = false
    /// Threshold "release now" cue: the stamp snaps up briefly.
    @State private var stampBoosted = false

    /// Horizontal travel, in points, that commits a swipe.
    private let threshold: CGFloat = 110
    /// A flick past this speed commits even below the distance threshold.
    private let flickVelocity: CGFloat = 420

    private var dragProgress: CGFloat {
        min(1, abs(drag.width) / threshold)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width, geo.size.height * 0.72)
            let cardHeight = min(geo.size.height, cardWidth / 0.72)

            ZStack {
                if cards.isEmpty {
                    DeckExhaustedState { onReset() }
                } else {
                    // Render back-to-front so the current card sits on top.
                    ForEach(Array(cards.prefix(3).enumerated()).reversed(), id: \.element.id) { offset, profile in
                        deckCard(profile: profile, offset: offset)
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(cardScale(offset: offset))
                            .offset(y: CGFloat(offset) * 12 * (offset == 1 ? (1 - dragProgress) : 1))
                            .rotationEffect(offset == 0 ? .degrees(Double(drag.width / 14)) : .zero)
                            .offset(offset == 0 ? drag : .zero)
                            .opacity(offset == 0 && flyingAway ? 0 : 1)
                            .overlay {
                                if offset == 0 {
                                    decisionOverlay
                                }
                            }
                            // Gesture AND hit-testing are gated on the
                            // fly-off: touching the departing card used to
                            // teleport it back to the finger.
                            .gesture((offset == 0 && !flyingAway) ? dragGesture : nil)
                            .allowsHitTesting(offset == 0 && !flyingAway)
                            // Back cards are visual context only — VoiceOver
                            // must not read three profiles at once.
                            .accessibilityHidden(offset != 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Metric.gutter)
        .onChange(of: command) { _, newValue in
            guard let newValue else { return }
            command = nil
            performSwipe(liked: newValue.liked, velocity: .zero)
        }
        .onChange(of: dragProgress >= 1) { _, crossed in
            guard crossed, !flyingAway else { return }
            // 120ms snap — the "release now" cue.
            withAnimation(motion.pressIn) { stampBoosted = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.12))
                withAnimation(motion.pressOut) { stampBoosted = false }
            }
        }
    }

    @ViewBuilder
    private func deckCard(profile: UserProfile, offset: Int) -> some View {
        if offset == 0 {
            SwipeCard(profile: profile, viewer: viewer)
                // Slight physical tilt with the drag.
                .rotation3DEffect(
                    .degrees(Double(drag.width / 180).clamped(to: -2...2)),
                    axis: (x: 0, y: 1, z: 0)
                )
                // The drag is the only like/pass mechanism — VoiceOver and
                // Switch Control users need real actions on the card.
                .accessibilityAction(named: "Like") {
                    performSwipe(liked: true, velocity: .zero)
                }
                .accessibilityAction(named: "Pass") {
                    performSwipe(liked: false, velocity: .zero)
                }
        } else {
            // Static back cards rasterise once instead of re-compositing
            // their shadows on every drag frame.
            SwipeCard(profile: profile, viewer: viewer)
                .drawingGroup()
        }
    }

    /// The card behind grows toward full size as the top card travels.
    private func cardScale(offset: Int) -> CGFloat {
        guard offset > 0 else { return 1 }
        let base = 1 - CGFloat(offset) * 0.04
        return offset == 1 ? base + 0.04 * dragProgress : base
    }

    private var decisionOverlay: some View {
        ZStack {
            stamp(text: "LIKE", color: Theme.online, baseRotation: -14)
                .opacity(Double(max(0, drag.width) / threshold))
                .scaleEffect(stampScale(active: drag.width > 0))
                .rotationEffect(.degrees(drag.width > 0 ? Double(-6 * (1 - dragProgress)) : 0))
            stamp(text: "NOPE", color: Theme.accent, baseRotation: 14)
                .opacity(Double(max(0, -drag.width) / threshold))
                .scaleEffect(stampScale(active: drag.width < 0))
                .rotationEffect(.degrees(drag.width < 0 ? Double(6 * (1 - dragProgress)) : 0))
        }
        .allowsHitTesting(false)
    }

    private func stampScale(active: Bool) -> CGFloat {
        guard active else { return 0.5 }
        let base = 0.5 + 0.5 * dragProgress
        return stampBoosted ? base * 1.12 : base
    }

    private func stamp(text: String, color: Color, baseRotation: Double) -> some View {
        Text(text)
            .font(.click(.largeTitle, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metric.chip, style: .continuous)
                    .strokeBorder(color, lineWidth: 5)
            )
            .rotationEffect(.degrees(baseRotation))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 36)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Direct 1:1 finger tracking — an implicit .animation here
                // once overrode the explicit fly-off (FINDINGS §42).
                drag = value.translation
            }
            .onEnded { value in
                let travelled = value.translation.width
                let speed = value.velocity.width
                if travelled > threshold || speed > flickVelocity {
                    performSwipe(liked: true, velocity: value.velocity)
                } else if travelled < -threshold || speed < -flickVelocity {
                    performSwipe(liked: false, velocity: value.velocity)
                } else {
                    withAnimation(motion.gesture) {
                        drag = .zero
                    }
                }
            }
    }

    /// Fly-off that carries the throw's velocity, sequenced with an
    /// interruptible animation completion instead of asyncAfter.
    private func performSwipe(liked: Bool, velocity: CGSize) {
        guard let profile = cards.first, !flyingAway else { return }

        isBusy = true
        onCommitStart(profile, liked)

        let vertical = (drag.height + velocity.height * 0.12).clamped(to: -260...80)
        withAnimation(motion.flyOff) {
            drag = CGSize(width: liked ? 640 : -640, height: vertical == 0 ? -120 : vertical)
            flyingAway = true
        } completion: {
            onFlyOffComplete(profile, liked)
            // Swap with animations OFF for the drag reset ONLY — the rest
            // of the deck animates on Motion.state from the parent.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                drag = .zero
                flyingAway = false
            }
            isBusy = false
        }
    }
}

// MARK: - Empty deck

struct DeckExhaustedState: View {
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Theme.brandPink)
            Text("that's everyone")
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)
            Text("check back later, or loosen your filters.")
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            PillButton(title: "start over", action: onReset)
                .padding(.top, 8)
        }
        .padding(Theme.Metric.gutter)
        .accessibilityElement(children: .contain)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
