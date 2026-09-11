//
//  ClickMotion.swift
//  Click
//
//  Reduce-Motion-aware resolver over Theme.Motion. RootView injects one
//  instance built from the system setting; every call site reads
//  `@Environment(\.motion)` and never branches on
//  `accessibilityReduceMotion` itself. Under Reduce Motion every tier
//  collapses to a short cross-fade and the takeover transition becomes a
//  plain opacity fade.
//

import SwiftUI

struct ClickMotion: Equatable {
    var reduceMotion: Bool = false

    /// The one curve everything maps to under Reduce Motion.
    private var fade: Animation { .easeInOut(duration: 0.15) }

    // Tier 1 — touch feedback
    var pressIn: Animation { reduceMotion ? fade : Theme.Motion.pressIn }
    var pressOut: Animation { reduceMotion ? fade : Theme.Motion.pressOut }

    // Tier 2 — state inside a screen
    var state: Animation { reduceMotion ? fade : Theme.Motion.state }

    // Tier 3 — the screen/step itself changed
    var screen: Animation { reduceMotion ? fade : Theme.Motion.screen }
    var screenFade: Animation { reduceMotion ? fade : Theme.Motion.screenFade }

    // Tier 4 — physical objects under the finger
    var gesture: Animation { reduceMotion ? fade : Theme.Motion.gesture }
    var flyOff: Animation { reduceMotion ? fade : Theme.Motion.flyOff }

    // Tier 5 — celebration
    var celebrate: Animation { reduceMotion ? fade : Theme.Motion.celebrate }
    var celebrateOut: Animation { reduceMotion ? fade : Theme.Motion.celebrateOut }
    var numeric: Animation { reduceMotion ? fade : Theme.Motion.numeric }

    var stagger: Double { reduceMotion ? 0 : Theme.Motion.stagger }
    var celebrationDuration: Double { Theme.Motion.celebrationDuration }

    /// Full-screen takeover (match celebration). Scale-in normally, a pure
    /// fade under Reduce Motion.
    var takeover: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.94).combined(with: .opacity)
    }
}

extension EnvironmentValues {
    @Entry var motion = ClickMotion()
}
