//
//  ClickButtonStyle.swift
//  Click
//
//  The one press animation for the whole app: scale to 0.96 with a spring
//  release, a subtle opacity dip, and impact haptics on press.
//

import SwiftUI

struct ClickButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { old, new in
                !old && new
            }
    }
}

extension ButtonStyle where Self == ClickButtonStyle {
    /// `Button { } label: { }.buttonStyle(.click)`
    static var click: ClickButtonStyle { ClickButtonStyle() }
}
