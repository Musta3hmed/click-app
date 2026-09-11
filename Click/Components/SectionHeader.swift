//
//  SectionHeader.swift
//  Click
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil

    init(_ title: String, trailing: String? = nil, trailingAction: (() -> Void)? = nil) {
        self.title = title
        self.trailing = trailing
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)

            Spacer()

            if let trailing, let trailingAction {
                Button(trailing, action: trailingAction)
                    .font(.click(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Black pill button used for primary actions throughout the app.
struct PillButton: View {
    let title: String
    var isEnabled: Bool = true
    var horizontalPadding: CGFloat = 28
    var verticalPadding: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Text(title)
                .font(.click(.headline, weight: .heavy))
                .foregroundStyle(isEnabled ? Theme.onPrimary : Theme.secondary)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    Capsule().fill(isEnabled ? Theme.primary : Theme.fillDisabled)
                )
        }
        .buttonStyle(.click)
        .disabled(!isEnabled)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        SectionHeader("boosters")
        SectionHeader("offers", trailing: "see all") {}
        PillButton(title: "edit profile") {}
        PillButton(title: "add code", isEnabled: false) {}
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.background)
}
