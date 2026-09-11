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
    @ViewBuilder var content: () -> Content

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Theme.Metric.sheet,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Theme.Metric.sheet,
            style: .continuous
        )
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
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
