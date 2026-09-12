//
//  ConfettiView.swift
//  Click
//
//  Lightweight particle burst for the celebrations. Pure Canvas —
//  positions are functions of elapsed time, no per-frame state. 54
//  particles in three parallax depth bands (near/mid/far), one shared
//  unit path scaled per particle, a static palette, asynchronous
//  rendering, and a keyframed opacity ramp (120ms in, 600ms out).
//

import SwiftUI

struct ConfettiView: View {
    /// Seconds the burst lasts before fading out.
    var duration: Double = 2.6

    // @State, not a stored let: a plain property re-initialises on every
    // body re-render, which made the burst loop forever.
    @State private var startDate = Date()

    private struct Particle {
        let originX: CGFloat      // 0...1
        let velocityY: CGFloat    // points/sec
        let driftX: CGFloat
        let spinSpeed: Double
        let hueIndex: Int
        let size: CGFloat
        let delay: Double
        /// 0 far, 1 mid, 2 near — scales size/speed for parallax depth.
        let band: Int
    }

    private static let particles: [Particle] = {
        var generator = SeededRandom(seed: 0xC11C)
        return (0..<54).map { index in
            let band = index % 3
            let depth = 0.6 + CGFloat(band) * 0.35   // far small+slow, near big+fast
            return Particle(
                originX: CGFloat(generator.next()),
                velocityY: (140 + CGFloat(generator.next()) * 220) * depth,
                driftX: (CGFloat(generator.next()) - 0.5) * 120,
                spinSpeed: 2 + generator.next() * 6,
                hueIndex: Int(generator.next() * 100),
                size: (6 + CGFloat(generator.next()) * 6) * depth,
                delay: generator.next() * 0.7,
                band: band
            )
        }
    }()

    /// Static — allocating this per frame was measurable.
    private static let palette: [Color] = [
        Theme.brandOrange, Theme.brandPink, Theme.brandGold,
        Theme.brandViolet, Theme.online, .white
    ]

    /// One unit path, scaled per particle instead of re-built 54 times a
    /// frame.
    private static let unitPath = RoundedRectangle(cornerRadius: 0.2)
        .path(in: CGRect(x: -0.5, y: -0.3, width: 1, height: 0.6))

    /// Flips once the burst finishes so the display link stops instead of
    /// invoking an empty Canvas every frame for as long as the overlay lives.
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(paused: finished)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                guard elapsed < duration else { return }

                // Keyframed global ramp: 120ms fade-in, 600ms fade-out —
                // no more snap to a linear ramp half a second early.
                let fadeIn = min(1, elapsed / 0.12)
                let fadeOut = min(1, max(0, (duration - elapsed) / 0.6))
                let globalFade = fadeIn * fadeOut

                for particle in Self.particles {
                    let t = elapsed - particle.delay
                    guard t > 0 else { continue }

                    let y = particle.velocityY * t + 80 * t * t  // gravity-ish
                    let x = particle.originX * size.width + particle.driftX * CGFloat(sin(t * 2))
                    guard y < size.height + 20 else { continue }

                    var ctx = context
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(t * particle.spinSpeed))
                    ctx.scaleBy(x: particle.size, y: particle.size)
                    ctx.fill(
                        Self.unitPath,
                        with: .color(Self.palette[particle.hueIndex % Self.palette.count].opacity(globalFade))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(duration + 0.1))
            finished = true
        }
    }
}

/// Tiny deterministic PRNG so the confetti layout is stable across renders.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B9 : seed }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}

#Preview {
    ZStack {
        Theme.brandGradient.ignoresSafeArea()
        ConfettiView()
    }
}
