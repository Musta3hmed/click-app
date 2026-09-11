//
//  ConfettiView.swift
//  Click
//
//  Lightweight particle burst for the match celebration. Pure Canvas —
//  positions are functions of elapsed time, no per-frame state.
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
    }

    private static let particles: [Particle] = {
        var generator = SeededRandom(seed: 0xC11C)
        return (0..<90).map { _ in
            Particle(
                originX: CGFloat(generator.next()),
                velocityY: 140 + CGFloat(generator.next()) * 220,
                driftX: (CGFloat(generator.next()) - 0.5) * 120,
                spinSpeed: 2 + generator.next() * 6,
                hueIndex: Int(generator.next() * 100),
                size: 6 + CGFloat(generator.next()) * 6,
                delay: generator.next() * 0.7
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                guard elapsed < duration else { return }

                let palette: [Color] = [
                    Theme.brandOrange, Theme.brandPink, Theme.brandGold,
                    Theme.brandViolet, Theme.online, .white
                ]

                for particle in Self.particles {
                    let t = elapsed - particle.delay
                    guard t > 0 else { continue }

                    let y = particle.velocityY * t + 80 * t * t  // gravity-ish
                    let x = particle.originX * size.width + particle.driftX * CGFloat(sin(t * 2))
                    guard y < size.height + 20 else { continue }

                    let fade = min(1, max(0, (duration - elapsed) / 0.5))
                    let rect = CGRect(
                        x: x - particle.size / 2,
                        y: y - particle.size / 2,
                        width: particle.size,
                        height: particle.size * 0.6
                    )

                    var ctx = context
                    ctx.translateBy(x: rect.midX, y: rect.midY)
                    ctx.rotate(by: .radians(t * particle.spinSpeed))
                    ctx.translateBy(x: -rect.midX, y: -rect.midY)
                    ctx.fill(
                        RoundedRectangle(cornerRadius: 2).path(in: rect),
                        with: .color(palette[particle.hueIndex % palette.count].opacity(fade))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
