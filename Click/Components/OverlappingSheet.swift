//
//  OverlappingSheet.swift
//  Click
//
//  The app's signature layout move: a rounded sheet that rides up over the
//  bottom of the textured header.
//

import SwiftUI

struct OverlappingSheet<Content: View>: View {
    var overlap: CGFloat = Theme.Metric.sheetOverlap
    /// backgroundRaised: identical to the background in light, one step
    /// lighter in dark — without it the sheet disappeared on OLED.
    var fill: Color = Theme.backgroundRaised
    /// The three main tabs draw the ambient brand wash inside the sheet.
    /// Conversations, settings and onboarding stay flat (readability).
    var ambient: Bool = false
    /// Mirrors the header's scroll-driven collapse: the top radius runs
    /// to 0 at full collapse so the sheet docks flush under the slim bar.
    /// 1:1 with the finger — never animated.
    var collapseProgress: CGFloat = 0
    @ViewBuilder var content: () -> Content

    private var shape: UnevenRoundedRectangle {
        let radius = Theme.Metric.sheet * (1 - collapseProgress)
        return UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: radius,
            style: .continuous
        )
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(fill)
                    .overlay {
                        if ambient {
                            AmbientBackground().clipShape(shape)
                        }
                    }
            }
            // Top hairline (masked to the curved top band only) so the
            // sheet edge reads in dark mode.
            .overlay {
                shape.strokeBorder(Theme.separator, lineWidth: 1)
                    .mask(alignment: .top) {
                        Rectangle()
                            .frame(height: Theme.Metric.sheet + 2)
                            .frame(maxWidth: .infinity)
                    }
            }
            .offset(y: -overlap)
            // Reclaim the space the offset created so following content
            // does not end up with a gap beneath it.
            .padding(.bottom, -overlap)
            // The scroll-driven radius must track the finger exactly.
            .transaction(value: collapseProgress) { $0.animation = nil }
    }
}

#Preview {
    VStack(spacing: 0) {
        TexturedHeader(title: "chats")
        OverlappingSheet {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("messages")
                Text("Sheet content sits on top of the header.")
                    .font(.clickPlain(.subheadline))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(Theme.Metric.gutter)
            .padding(.top, 12)
        }
        Spacer()
    }
    .background(Theme.background)
}
