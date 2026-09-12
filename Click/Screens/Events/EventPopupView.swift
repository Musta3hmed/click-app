//
//  EventPopupView.swift
//  Click
//
//  Once per event id, on the first foreground while it is live. States
//  what the event is and that entries are free. Deliberately NO
//  countdown pressure and no "don't miss out" framing.
//

import SwiftUI

struct EventPopupView: View {
    let event: EventDefinition
    let onOpenWheel: () -> Void
    let onDismiss: () -> Void

    @Environment(\.motion) private var motion
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .accessibilityHidden(true)

            Spacer()

            Image(systemName: event.symbolName)
                .font(.system(size: 56, weight: .heavy))
                .foregroundStyle(CommunityService.tint(event.tintToken))
                .accessibilityHidden(true)

            Text(event.title)
                .font(.click(.largeTitle, weight: .heavy))
                .foregroundStyle(Theme.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)

            Text("the event wheel is open: one free entry every day, plus one for each daily reward you claim. rewards are cosmetics and boosters — nothing to buy.")
                .font(.clickPlain(.body, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer()

            Button {
                onOpenWheel()
            } label: {
                Text("open the wheel")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .accessibilityLabel("Open the wheel")

            Button {
                onDismiss()
            } label: {
                Text("maybe later")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.secondary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.clickSilent)
            .accessibilityLabel("Maybe later")
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.bottom, 24)
        .background(Theme.background)
        .task {
            try? await Task.sleep(for: .seconds(0.32))
            headingFocused = true
        }
        // A takeover for VoiceOver — focus must not walk behind it.
        .accessibilityAddTraits(.isModal)
    }
}
