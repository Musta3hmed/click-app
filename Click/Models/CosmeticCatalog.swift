//
//  CosmeticCatalog.swift
//  Click
//
//  Cosmetic unlocks: card frames and avatar rings. HARD RULES: earned
//  only (the event wheel grants them — no coin price, no IAP path), and
//  strictly cosmetic — a cosmetic must NEVER buy dating visibility.
//

import SwiftUI

enum CosmeticKind: String, Codable {
    case cardFrame
    case avatarRing

    var label: String {
        switch self {
        case .cardFrame: "card frame"
        case .avatarRing: "avatar ring"
        }
    }
}

struct Cosmetic: Identifiable, Hashable {
    /// Canonical slug, stable forever.
    let id: String
    let kind: CosmeticKind
    /// Lowercase — Click draws it.
    let label: String
    /// Theme token BY NAME (resolved in tint()) — never hex in data.
    let tintToken: String
    let symbolName: String
}

enum CosmeticCatalog {
    static let all: [Cosmetic] = [
        // Halloween 2026 wheel pool.
        Cosmetic(id: "pumpkin-frame", kind: .cardFrame, label: "pumpkin frame", tintToken: "brandOrange", symbolName: "moon.stars.fill"),
        Cosmetic(id: "midnight-frame", kind: .cardFrame, label: "midnight frame", tintToken: "brandViolet", symbolName: "sparkles"),
        Cosmetic(id: "ember-ring", kind: .avatarRing, label: "ember ring", tintToken: "brandCoral", symbolName: "flame.fill"),
        Cosmetic(id: "phantom-ring", kind: .avatarRing, label: "phantom ring", tintToken: "brandMagenta", symbolName: "wind"),
    ]

    static let byID: [String: Cosmetic] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    /// Resolved through the same named-token map communities use.
    @MainActor
    static func tint(_ id: String) -> Color {
        guard let cosmetic = byID[id] else { return Theme.brandPink }
        return CommunityService.tint(cosmetic.tintToken)
    }
}
