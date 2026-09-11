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

    // Tempered for dark (-12% sat, -6% light): full-saturation brand on
    // near-black glows. Color(light:dark:) resolves per trait, so every
    // call site — gradients included — adapts with no changes.
    static let brandOrange = Color(light: 0xFFA24C, dark: 0xE8924A)
    static let brandCoral = Color(light: 0xFF6A4D, dark: 0xE0614A)
    static let brandPink = Color(light: 0xFF2D62, dark: 0xDE3260)
    static let brandGold = Color(light: 0xFFD36E, dark: 0xE6BE66)
    static let brandMagenta = Color(light: 0xFF2D8F, dark: 0xDE3487)
    static let brandViolet = Color(light: 0x8A2BE2, dark: 0x8A46CC)

    /// Full three-stop brand wash, for hero surfaces (welcome, match overlay).
    /// Stored, not computed — these sit inside TimelineViews and must not
    /// allocate per frame.
    static let brandGradient = LinearGradient(
        colors: [brandOrange, brandCoral, brandPink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Header gradient. Warm in both modes, but the dark variant drops the
    // ~14:1 lightbox to ~6:1 while white titles still clear 4.5:1.
    static let headerTop = Color(light: 0xFF9A4C, dark: 0xB5552C)
    static let headerBottom = Color(light: 0xFF4D67, dark: 0x8E2A44)

    static let headerGradient = LinearGradient(
        colors: [headerTop, headerBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Launch placeholder wash: full brand in light, a warm near-dark in
    /// dark — no more orange flash into a black app.
    static let launchGradient = LinearGradient(
        colors: [
            Color(light: 0xFFA24C, dark: 0x16161B),
            Color(light: 0xFF6A4D, dark: 0x20181D),
            Color(light: 0xFF2D62, dark: 0x2A1A20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Screen background: flat in light, a subtle vertical near-black wash
    /// in dark so the floating tab bar has something to sit on.
    static let backgroundWash = LinearGradient(
        colors: [
            Color(light: 0xF4F4EF, dark: 0x0E0E12),
            Color(light: 0xF4F4EF, dark: 0x16161B)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // Elevated dark ramp: each step is visibly lighter than the one below,
    // so hierarchy survives on OLED (the old three surfaces sat at 1.28:1).
    /// Warm off-white, deliberately not pure white.
    static let background = Color(light: 0xF4F4EF, dark: 0x0E0E12)
    /// The overlapping sheet's fill — one step above the background.
    static let backgroundRaised = Color(light: 0xF4F4EF, dark: 0x16161B)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1E1E25)
    static let surfaceRaised = Color(light: 0xFAFAF7, dark: 0x2A2A33)
    /// Menus, pressed states, and chrome that must not be a white slab.
    static let surfaceHigh = Color(light: 0xFFFFFF, dark: 0x363641)
    /// Disabled control fills — never use `separator` as a fill.
    static let fillDisabled = Color(light: 0xE6E6E0, dark: 0x2F2F38)

    /// The floating tab bar capsule: black in light, but NOT a glowing
    /// near-white slab in dark — an elevated grey with light text.
    static let tabBarFill = Color(light: 0x000000, dark: 0x363641)
    static let onTabBarFill = Color(light: 0xFFFFFF, dark: 0xF2F2F2)

    /// Primary is black in light mode and white in dark — always the
    /// highest-contrast fill. `onPrimary` is whatever sits on top of it.
    static let primary = Color(light: 0x000000, dark: 0xF2F2F2)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x000000)

    // Light value chosen for WCAG AA (4.54:1 on the off-white background).
    static let secondary = Color(light: 0x6B6B6B, dark: 0x8A8A90)
    static let accent = Color(light: 0xFF3B5C, dark: 0xE8465F)
    static let online = Color(light: 0x34C759, dark: 0x30B851)
    static let coin = Color(light: 0xE8B21E, dark: 0xD4A527)
    static let coinDark = Color(hex: 0xB8860B)
    static let verified = Color(light: 0x2D9CF0, dark: 0x3D9BE0)
    static let violetDark = Color(hex: 0x5F3DC4)

    // MARK: On-image constants
    // Whites drawn over photos/scrims are mode-INVARIANT by design — named
    // so a future theming pass can't accidentally flip them.
    static let onImagePrimary = Color.white
    static let onImageSecondary = Color.white.opacity(0.9)
    static let onImageFill = Color.white.opacity(0.22)

    // MARK: Elevation
    // Black-on-black shadows are invisible; dark mode compensates with a
    // deeper shadow plus a faint top-edge glow stroke on elevated cards.
    static let shadowColor = Color(uiColor: UIColor { traits in
        UIColor.black.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.55 : 0.16)
    })
    /// 1px top-edge stroke on elevated cards in dark; invisible in light.
    static let glowStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.clear
    })

    /// Bottom scrim on photo cards — slightly lighter in dark so the
    /// card's lower edge doesn't dissolve into the background.
    static let cardScrim = Color(uiColor: UIColor { traits in
        UIColor.black.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.55 : 0.65)
    })

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

    // MARK: Motion
    // The five-tier Click motion system. No animation curve may be declared
    // anywhere else (CI lints for it); call sites resolve tiers through
    // `@Environment(\.motion)` so Reduce Motion is handled in one place.

    enum Motion {
        // Tier 1 — touch feedback (asymmetric: fast in, soft bounce out)
        static let pressIn  = Animation.spring(response: 0.16, dampingFraction: 0.92)
        static let pressOut = Animation.spring(response: 0.30, dampingFraction: 0.62)
        // Tier 2 — state inside a screen (selection, toggle, reveal, folder switch)
        static let state = Animation.spring(response: 0.32, dampingFraction: 0.82)
        // Tier 3 — the screen/step itself changed
        static let screen = Animation.spring(response: 0.42, dampingFraction: 0.90)
        static let screenFade = Animation.easeInOut(duration: 0.26)   // pure cross-fades
        // Tier 4 — physical objects under the finger
        static let gesture = Animation.interpolatingSpring(stiffness: 210, damping: 26)
        static let flyOff  = Animation.spring(response: 0.40, dampingFraction: 1.0)
        // Tier 5 — celebration (the ONLY loud bounce allowed)
        static let celebrate    = Animation.spring(response: 0.50, dampingFraction: 0.62)
        static let celebrateOut = Animation.easeOut(duration: 0.22)
        static let numeric = Animation.snappy(duration: 0.28, extraBounce: 0.12)
        static let stagger: Double = 0.055
        static let celebrationDuration: Double = 2.4
    }

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
    /// Standard raised card surface. `elevated` adds the one elevation
    /// treatment (mode-aware shadow + dark-mode glow stroke) so light/dark
    /// elevation is decided here, not per screen.
    @ViewBuilder
    func cardSurface(radius: CGFloat = Theme.Metric.card, elevated: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if elevated {
            background(Theme.surface, in: shape)
                .overlay(shape.strokeBorder(Theme.glowStroke, lineWidth: 1))
                .shadow(color: Theme.shadowColor, radius: 12, y: 6)
        } else {
            background(Theme.surface, in: shape)
        }
    }

    /// Leaves room for the floating tab bar at the bottom of a scroll view.
    func tabBarClearance() -> some View {
        safeAreaPadding(.bottom, Theme.Metric.tabBarClearance)
    }
}
