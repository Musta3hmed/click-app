//
//  SectionHeader.swift
//  Click
//

import SwiftUI

struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)

            Spacer()
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
        // No manual haptic here: the .click style provides it (the pair
        // used to double-fire).
        Button(action: action) {
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
        PillButton(title: "edit profile") {}
        PillButton(title: "add code", isEnabled: false) {}
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.background)
}
