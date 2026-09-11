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
    var fill: Color = Theme.background
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.Metric.sheet,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: Theme.Metric.sheet,
                    style: .continuous
                )
                .fill(fill)
            )
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
