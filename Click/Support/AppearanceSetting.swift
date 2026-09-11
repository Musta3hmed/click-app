//
//  AppearanceSetting.swift
//  Click
//
//  Light/dark theme override. Applied in exactly ONE place — ClickApp's
//  WindowGroup root via .preferredColorScheme — because sheets get their
//  own host windows and anything lower does not propagate.
//

import SwiftUI

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// Lowercase — Click draws this picker itself (casing rule).
    var label: String { rawValue }

    /// nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
