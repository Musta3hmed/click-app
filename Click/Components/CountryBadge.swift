//
//  CountryBadge.swift
//  Click
//
//  ISO country code as a small text pill. Replaces flag emoji, which render
//  as boxes wherever the emoji font is unavailable.
//

import SwiftUI

struct CountryBadge: View {
    /// ISO 3166-1 alpha-2, e.g. "AU".
    let code: String?
    /// White-on-translucent for photo overlays; themed otherwise.
    var onDark: Bool = false

    var body: some View {
        if let code, !code.isEmpty {
            Text(code.uppercased())
                .font(.clickPlain(.caption2, weight: .heavy))
                .kerning(0.8)
                .foregroundStyle(onDark ? .white : Theme.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    onDark ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(Theme.separator.opacity(0.6)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .accessibilityLabel(countryName)
        }
    }

    private var countryName: String {
        guard let code else { return "" }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

#Preview {
    HStack {
        CountryBadge(code: "AU")
        CountryBadge(code: "BR")
        ZStack {
            Theme.brandGradient
            CountryBadge(code: "JP", onDark: true)
        }
        .frame(width: 80, height: 40)
    }
    .padding()
    .background(Theme.background)
}
