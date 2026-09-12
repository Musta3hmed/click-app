//
//  ClickButtonStyle.swift
//  Click
//
//  The one press treatment for the whole app.
//
//  - Constant-point press inset (3pt per edge) converted to a per-size
//    scale, so a 30pt chip and a full-width pill both visibly dip by the
//    same physical amount instead of sharing one fixed 0.96.
//  - Asymmetric motion: fast press-in, soft bounce out (Theme.Motion tiers,
//    resolved through the environment so Reduce Motion collapses to fades).
//  - Built-in disabled treatment (dim + desaturate, animated) — no more
//    hand-rolled .opacity(0.4) at call sites.
//  - Haptics are part of the style: `.click` (standard), `.clickQuiet`
//    (soft), `.clickSilent` (none for repeated/ambient taps).
//

import SwiftUI

struct ClickButtonStyle: ButtonStyle {
    enum HapticLevel {
        case standard, quiet, silent
    }

    /// Press depth in points, per edge.
    var inset: CGFloat = 3
    var haptic: HapticLevel = .standard

    func makeBody(configuration: Configuration) -> some View {
        ClickButtonBody(configuration: configuration, inset: inset, haptic: haptic)
    }
}

/// Inner view so the style can read the environment (motion, isEnabled).
private struct ClickButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let inset: CGFloat
    let haptic: ClickButtonStyle.HapticLevel

    @Environment(\.motion) private var motion
    @Environment(\.isEnabled) private var isEnabled
    @State private var size: CGSize = .zero

    private var pressedScale: CGFloat {
        // Constant-point inset → per-size scale, clamped so tiny chips
        // don't collapse before the size is known.
        let dimension = max(size.width, size.height)
        guard dimension > 0 else { return 0.97 }
        return max(0.90, (dimension - inset * 2) / dimension)
    }

    var body: some View {
        configuration.label
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size = $0 }
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .saturation(isEnabled ? 1 : 0.3)
            .animation(
                configuration.isPressed ? motion.pressIn : motion.pressOut,
                value: configuration.isPressed
            )
            .animation(motion.state, value: isEnabled)
            .sensoryFeedback(trigger: configuration.isPressed) { old, new in
                guard !old, new else { return nil }
                switch haptic {
                case .standard: return .impact(weight: .light)
                case .quiet: return .impact(weight: .light, intensity: 0.5)
                case .silent: return nil
                }
            }
    }
}

extension ButtonStyle where Self == ClickButtonStyle {
    /// `Button { } label: { }.buttonStyle(.click)`
    static var click: ClickButtonStyle { ClickButtonStyle() }
    /// Softer haptic for secondary or dense controls.
    static var clickQuiet: ClickButtonStyle { ClickButtonStyle(haptic: .quiet) }
    /// No haptic — for controls that fire their own feedback or repeat fast.
    static var clickSilent: ClickButtonStyle { ClickButtonStyle(haptic: .silent) }
}
