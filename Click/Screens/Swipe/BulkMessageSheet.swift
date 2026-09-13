//
//  BulkMessageSheet.swift
//  Click
//
//  Confirmation, determinate progress, and the done state for the bulk
//  send. The heavy lifting happens in SwipeView.performBulkSend().
//

import SwiftUI

struct BulkMessageSheet: View {
    let text: String
    let recipientCount: Int
    @Binding var progress: Double?
    @Binding var sentCount: Int?
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.motion) private var motion

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            if let sentCount {
                doneState(sentCount)
                    .background {
                        // Same particle canvas the match celebration uses
                        // (async render, stops its own display link,
                        // 54 particles) — no second Canvas.
                        if !motion.reduceMotion {
                            ConfettiView(duration: 1.8)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            } else if progress != nil {
                sendingState
            } else {
                confirmState
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(progress != nil && sentCount == nil)
    }

    private var confirmState: some View {
        VStack(spacing: 16) {
            Text("bulk message")
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)

            Text(text)
                .font(.clickPlain(.body, weight: .medium))
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cardSurface(radius: Theme.Metric.control)

            VStack(spacing: 6) {
                Text("send to the next \(recipientCount) people in your deck")
                    .font(.click(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.primary)
                Text("costs 1 bulk chat booster · once per day")
                    .font(.clickPlain(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Text("everyone can report messages they don't want — keep it kind.")
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onConfirm()
            } label: {
                Text("send to \(recipientCount) people")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .accessibilityLabel("Send to \(recipientCount) people")

            Button("cancel") { dismiss() }
                .font(.clickPlain(.body, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .accessibilityLabel("Cancel")
        }
    }

    private var sendingState: some View {
        VStack(spacing: 16) {
            Text("sending…")
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
            ProgressView(value: progress ?? 0)
                .tint(Theme.brandPink)
                .accessibilityLabel("Sending progress")
        }
        .padding(.top, 24)
    }

    /// The flourish is about reach EARNED (one booster, once a day), on
    /// COMPLETION — never layered over the send loop, and the restraint
    /// copy stays visible right under it. Omitted entirely under Reduce
    /// Motion (the check + haptic already carry the confirmation).
    private func doneState(_ count: Int) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.online)
                .accessibilityHidden(true)
            Text("sent to \(count) people")
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
            Text("everyone can report messages they don't want — keep it kind.")
                .font(.clickPlain(.footnote, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button {
                dismiss()
            } label: {
                Text("done")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .accessibilityLabel("Done")
        }
        .padding(.top, 16)
    }
}
