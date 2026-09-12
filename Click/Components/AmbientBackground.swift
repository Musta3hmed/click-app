//
//  AmbientBackground.swift
//  Click
//
//  A calm, slowly-shifting brand-hued wash behind the three main tabs —
//  the grown-up sibling of the welcome screen's lava. GPU-native
//  MeshGradient: no blur passes, no blend modes, no offscreen groups.
//
//  Runs at 30fps (visually identical for this motion, half the GPU
//  wakeups); renders a static t=0 wash with NO TimelineView at all under
//  Reduce Motion / Reduce Transparency or when the scene is inactive.
//

import SwiftUI

struct AmbientBackground: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var isStatic: Bool {
        reduceMotion || reduceTransparency || scenePhase != .active
    }

    var body: some View {
        if isStatic {
            mesh(at: 0)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                mesh(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    /// 3x3 mesh. Corners stay pinned, edge points drift along their edge,
    /// the centre drifts freely — all on slow sin/cos (~0.07–0.12 rad/s).
    private func mesh(at t: TimeInterval) -> some View {
        let drift = { (rate: Double, phase: Double, amplitude: Float) -> Float in
            amplitude * Float(sin(t * rate + phase))
        }

        let points: [SIMD2<Float>] = [
            [0, 0],
            [0.5 + drift(0.09, 0.0, 0.16), 0],
            [1, 0],
            [0, 0.5 + drift(0.07, 1.3, 0.18)],
            [0.5 + drift(0.11, 2.1, 0.20), 0.5 + drift(0.08, 4.2, 0.20)],
            [1, 0.5 + drift(0.10, 5.0, 0.18)],
            [0, 1],
            [0.5 + drift(0.12, 3.3, 0.16), 1],
            [1, 1]
        ]

        // Brand hues at low opacity over the base; slightly stronger in
        // dark where the base is near-black.
        let boost = colorScheme == .dark ? 1.0 : 0.75
        let colors: [Color] = [
            Theme.brandOrange.opacity(0.12 * boost),
            Theme.brandGold.opacity(0.08 * boost),
            Theme.brandCoral.opacity(0.10 * boost),
            Theme.brandPink.opacity(0.09 * boost),
            Theme.brandMagenta.opacity(0.13 * boost),
            Theme.brandViolet.opacity(0.10 * boost),
            Theme.brandCoral.opacity(0.11 * boost),
            Theme.brandOrange.opacity(0.08 * boost),
            Theme.brandPink.opacity(0.12 * boost)
        ]

        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        AmbientBackground().ignoresSafeArea()
    }
}
