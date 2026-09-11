//
//  Theme.swift
//  Click
//
//  Design tokens. Every colour, font and metric in the app comes from here.
//

import SwiftUI

// MARK: - Colour helpers

extension Color {
    /// Build a colour from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }

    /// Build a colour that resolves differently in light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Theme

enum Theme {

    // MARK: Brand
    // Click's identity: the warm orange → pink of the logo. One identity,
    // everywhere — headers, welcome screen, celebration moments.

    static let brandOrange = Color(hex: 0xFFA24C)
    static let brandCoral = Color(hex: 0xFF6A4D)
    static let brandPink = Color(hex: 0xFF2D62)
    static let brandGold = Color(hex: 0xFFD36E)
    static let brandMagenta = Color(hex: 0xFF2D8F)
    static let brandViolet = Color(hex: 0x8A2BE2)

    /// Full three-stop brand wash, for hero surfaces (welcome, match overlay).
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandOrange, brandCoral, brandPink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Header gradient. Same hue in both modes — it sits behind white text.
    static let headerTop = Color(hex: 0xFF9A4C)
    static let headerBottom = Color(hex: 0xFF4D67)

    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [headerTop, headerBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Warm off-white, deliberately not pure white.
    static let background = Color(light: 0xF4F4EF, dark: 0x111114)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C20)
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x26262C)

    /// Primary is black in light mode and white in dark — always the
    /// highest-contrast fill. `onPrimary` is whatever sits on top of it.
    static let primary = Color(light: 0x000000, dark: 0xF2F2F2)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x000000)

    // Light value chosen for WCAG AA (4.54:1 on the off-white background).
    static let secondary = Color(light: 0x6B6B6B, dark: 0x8A8A90)
    static let accent = Color(hex: 0xFF3B5C)
    static let online = Color(hex: 0x34C759)
    static let coin = Color(hex: 0xE8B21E)
    static let coinDark = Color(hex: 0xB8860B)
    static let verified = Color(hex: 0x2D9CF0)
    static let violetDark = Color(hex: 0x5F3DC4)

    /// Deterministic decorative gradients for avatars and photo-less cards.
    /// Warm-leaning to match the brand, with enough spread to tell people apart.
    static let avatarGradients: [[Color]] = [
        [Color(hex: 0xFF9A4C), Color(hex: 0xFFD43B)],
        [Color(hex: 0xFF6B8A), Color(hex: 0xFFB199)],
        [Color(hex: 0x845EF7), Color(hex: 0xB197FC)],
        [Color(hex: 0xFFA94D), Color(hex: 0xFF4D67)],
        [Color(hex: 0x20C997), Color(hex: 0x63E6BE)],
        [Color(hex: 0xFF8787), Color(hex: 0xFFA8A8)],
        [Color(hex: 0xF06595), Color(hex: 0xFAA2C1)],
        [Color(hex: 0xFF5A5F), Color(hex: 0xFF2D8F)]
    ]

    static let cardGradients: [[Color]] = [
        [Color(hex: 0xFF9A4C), Color(hex: 0xE8590C)],
        [Color(hex: 0xFF6B8A), Color(hex: 0xC2255C)],
        [Color(hex: 0x845EF7), Color(hex: 0x4C2FA8)],
        [Color(hex: 0xFFA94D), Color(hex: 0xFF4D67)],
        [Color(hex: 0x20C997), Color(hex: 0x0C8A6A)],
        [Color(hex: 0xF06595), Color(hex: 0xAD1457)]
    ]

    /// Stable non-trapping hash (abs() of a wrapped Int can hit Int.min
    /// and trap; unsigned arithmetic cannot).
    static func stableHash(_ string: String) -> UInt64 {
        string.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
    }

    /// Stable pick from a gradient set for a given name.
    static func gradient(for name: String, in palette: [[Color]]) -> [Color] {
        palette[Int(stableHash(name) % UInt64(palette.count))]
    }

    static let separator = Color(light: 0xE6E6E0, dark: 0x33333A)

    // MARK: Metrics

    enum Metric {
        static let card: CGFloat = 24
        static let sheet: CGFloat = 28
        /// Buttons, rows, text fields and other standalone controls.
        static let control: CGFloat = 20
        /// Grid tiles (photos, bingo).
        static let tile: CGFloat = 16
        /// Small chips, toasts, stamps.
        static let chip: CGFloat = 12
        static let gutter: CGFloat = 16
        static let sheetOverlap: CGFloat = 24
        /// Height reserved at the bottom of scroll views so the floating
        /// tab bar never covers the last row.
        static let tabBarClearance: CGFloat = 96
    }
}

// MARK: - Typography

extension Font {
    /// The app voice: heavy, italic, rounded. Scales with Dynamic Type
    /// because it is built from a text style rather than a fixed size.
    static func click(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded).weight(weight).italic()
    }

    /// Non-italic variant for dense body copy, where italics hurt legibility.
    static func clickPlain(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

// MARK: - Shared modifiers

extension View {
    /// Standard white card surface.
    func cardSurface(radius: CGFloat = Theme.Metric.card) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Leaves room for the floating tab bar at the bottom of a scroll view.
    func tabBarClearance() -> some View {
        safeAreaPadding(.bottom, Theme.Metric.tabBarClearance)
    }
}
