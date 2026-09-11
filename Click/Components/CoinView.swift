//
//  CoinView.swift
//  Click
//
//  The Click coin: a gold smiley, drawn entirely with vectors so it is
//  crisp at any size, tintable and animatable. No raster assets.
//

import SwiftUI

struct CoinView: View {
    var size: CGFloat = 24
    /// Idle blink/wobble loop. Off for tiny inline coins where motion is noise.
    var animatesIdle: Bool = false
    /// Increment to fire the earn animation (spin + pop).
    var earnTrigger: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        Group {
            if animatesIdle && !reduceMotion {
                PhaseAnimator([IdlePhase.resting, .blinking, .wobbling]) { phase in
                    face(blinking: phase == .blinking)
                        .rotationEffect(.degrees(phase == .wobbling ? 6 : 0))
                } animation: { phase in
                    switch phase {
                    case .resting: .easeInOut(duration: 1.6)
                    case .blinking: .easeInOut(duration: 0.16)
                    case .wobbling: .spring(response: 0.5, dampingFraction: 0.5)
                    }
                }
            } else {
                face(blinking: false)
            }
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(spin ? 360 : 0), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(spin ? 1.25 : 1)
        .onChange(of: earnTrigger) { _, _ in
            // The 3D spin is the most vestibular-triggering motion in the
            // app — skip it entirely under Reduce Motion (the rolling coin
            // count still communicates the earn).
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) {
                spin = true
            } completion: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    spin = false
                }
            }
        }
        .accessibilityHidden(true)
    }

    private enum IdlePhase: CaseIterable {
        case resting, blinking, wobbling
    }

    private func face(blinking: Bool) -> some View {
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

            // Eyes. Blinking draws them as lines.
            let eyeColor = Color(hex: 0x7A5A00)
            let eyeY = center.y - d * 0.08
            let eyeOffset = d * 0.14
            let eyeR = d * 0.05

            for direction in [-1.0, 1.0] {
                let x = center.x + direction * eyeOffset
                if blinking {
                    var line = Path()
                    line.move(to: CGPoint(x: x - eyeR, y: eyeY))
                    line.addLine(to: CGPoint(x: x + eyeR, y: eyeY))
                    context.stroke(line, with: .color(eyeColor), style: StrokeStyle(lineWidth: d * 0.035, lineCap: .round))
                } else {
                    let rect = CGRect(x: x - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)
                    context.fill(Circle().path(in: rect), with: .color(eyeColor))
                }
            }

            // Smile.
            var smile = Path()
            let smileWidth = d * 0.34
            smile.move(to: CGPoint(x: center.x - smileWidth / 2, y: center.y + d * 0.10))
            smile.addQuadCurve(
                to: CGPoint(x: center.x + smileWidth / 2, y: center.y + d * 0.10),
                control: CGPoint(x: center.x, y: center.y + d * 0.28)
            )
            context.stroke(smile, with: .color(eyeColor), style: StrokeStyle(lineWidth: d * 0.045, lineCap: .round))

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
