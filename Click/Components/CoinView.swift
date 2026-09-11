//
//  CoinView.swift
//  Click
//
//  The Click coin: a gold smiley, drawn entirely with vectors so it is
//  crisp at any size, tintable and animatable. No raster assets.
//
//  The earn animation is a keyframe track: monotonic 0->360 spin (the old
//  completion-based version visibly rewound 360->0) plus a three-stage
//  scale overshoot; it resets instantly between triggers and is skipped
//  under Reduce Motion. Eyes are real vector shapes OVER the canvas so a
//  blink animates openness instead of swapping non-interpolable paths.
//

import SwiftUI

struct CoinView: View {
    var size: CGFloat = 24
    /// Idle blink/wobble loop. Off for tiny inline coins where motion is noise.
    var animatesIdle: Bool = false
    /// Increment to fire the earn animation (spin + pop).
    var earnTrigger: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct EarnValues {
        var angle = 0.0
        var scale = 1.0
    }

    var body: some View {
        Group {
            if animatesIdle && !reduceMotion {
                PhaseAnimator([IdlePhase.resting, .blinking, .wobbling]) { phase in
                    coinFace(eyeOpenness: phase == .blinking ? 0.08 : 1)
                        .rotationEffect(.degrees(phase == .wobbling ? 6 : 0))
                } animation: { phase in
                    switch phase {
                    case .resting: Theme.Motion.screenFade.speed(0.2)
                    case .blinking: Theme.Motion.screenFade.speed(1.6)
                    case .wobbling: Theme.Motion.celebrate
                    }
                }
            } else {
                coinFace(eyeOpenness: 1)
            }
        }
        .frame(width: size, height: size)
        // Collapse the layers BEFORE any 3D transform: spinning inside a
        // .ultraThinMaterial otherwise invalidates the material sample
        // every frame.
        .compositingGroup()
        .keyframeAnimator(
            initialValue: EarnValues(),
            trigger: earnTrigger
        ) { view, values in
            view
                // Monotonic — the coin can never spin backwards. Skipped
                // under Reduce Motion (the rolling count still communicates
                // the earn).
                .rotation3DEffect(
                    .degrees(reduceMotion ? 0 : values.angle),
                    axis: (x: 0, y: 1, z: 0)
                )
                .scaleEffect(reduceMotion ? 1 : values.scale)
        } keyframes: { _ in
            KeyframeTrack(\.angle) {
                CubicKeyframe(360, duration: 0.62)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.18, duration: 0.20)
                CubicKeyframe(1.30, duration: 0.16)
                CubicKeyframe(1.00, duration: 0.26)
            }
        }
        .accessibilityHidden(true)
    }

    private enum IdlePhase: CaseIterable {
        case resting, blinking, wobbling
    }

    private static let eyeColor = Color(hex: 0x7A5A00)

    /// Canvas base (rim, plate, smile, glint) + animatable vector eyes.
    private func coinFace(eyeOpenness: CGFloat) -> some View {
        base
            .overlay {
                GeometryReader { geo in
                    let d = min(geo.size.width, geo.size.height)
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let eyeY = center.y - d * 0.08
                    let eyeOffset = d * 0.14
                    let eyeR = d * 0.05

                    ForEach([-1.0, 1.0], id: \.self) { direction in
                        Ellipse()
                            .fill(Self.eyeColor)
                            .frame(width: eyeR * 2, height: eyeR * 2)
                            // Openness is a vertical squash — animatable,
                            // unlike a circle-for-line path swap.
                            .scaleEffect(x: 1, y: max(0.08, eyeOpenness))
                            .position(x: center.x + direction * eyeOffset, y: eyeY)
                    }
                }
            }
    }

    private var base: some View {
        Canvas { context, canvasSize in
            let d = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            // Rim: radial gold gradient, darker at the edge like a minted coin.
            let rimRect = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            context.fill(
                Circle().path(in: rimRect),
                with: .radialGradient(
                    Gradient(colors: [Color(hex: 0xFFE28A), Color(hex: 0xE8B21E), Color(hex: 0xB8860B)]),
                    center: CGPoint(x: center.x - d * 0.1, y: center.y - d * 0.12),
                    startRadius: 0,
                    endRadius: d * 0.62
                )
            )

            // Inner face plate.
            let inset = d * 0.12
            let faceRect = rimRect.insetBy(dx: inset, dy: inset)
            context.fill(
                Circle().path(in: faceRect),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: 0xFFD75E), Color(hex: 0xF0B429)]),
                    startPoint: CGPoint(x: center.x, y: faceRect.minY),
                    endPoint: CGPoint(x: center.x, y: faceRect.maxY)
                )
            )

            // Smile.
            var smile = Path()
            let smileWidth = d * 0.34
            smile.move(to: CGPoint(x: center.x - smileWidth / 2, y: center.y + d * 0.10))
            smile.addQuadCurve(
                to: CGPoint(x: center.x + smileWidth / 2, y: center.y + d * 0.10),
                control: CGPoint(x: center.x, y: center.y + d * 0.28)
            )
            context.stroke(
                smile,
                with: .color(Self.eyeColor),
                style: StrokeStyle(lineWidth: d * 0.045, lineCap: .round)
            )

            // Glint.
            let glintRect = CGRect(
                x: center.x - d * 0.30, y: center.y - d * 0.36,
                width: d * 0.14, height: d * 0.08
            )
            var glint = Path(ellipseIn: glintRect)
            glint = glint.applying(CGAffineTransform(rotationAngle: -0.5)
                .translatedBy(x: 0, y: 0))
            context.fill(glint, with: .color(.white.opacity(0.55)))
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        CoinView(size: 20)
        CoinView(size: 44, animatesIdle: true)
        CoinView(size: 80, animatesIdle: true)
    }
    .padding()
    .background(Theme.background)
}
