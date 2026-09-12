//
//  InterestMatching.swift
//  Click
//
//  The single place shared-interest logic lives — views never intersect
//  interest arrays themselves. Also the substrate MEGA-BRIEF 4.7's
//  icebreakers build on.
//

import Foundation

enum InterestMatching {
    /// Interests both profiles picked, in the order the second person
    /// (the one being looked at) lists them.
    static func shared(_ viewer: UserProfile?, _ other: UserProfile) -> [Interest] {
        guard let viewer else { return [] }
        let mine = Set(viewer.interests)
        return other.interests
            .filter { mine.contains($0) }
            .compactMap { InterestCatalog.byID[$0] }
    }

    /// Deck-ordering score: the count of shared interests. Reorders,
    /// never removes — ties fall back to the deck's stable createdAt sort.
    static func score(_ viewer: UserProfile?, _ other: UserProfile) -> Int {
        guard let viewer else { return 0 }
        return Set(viewer.interests).intersection(other.interests).count
    }

    /// "you both like coffee and film" — nil when nothing is shared.
    /// Lowercase per the casing rule (Click draws it).
    static func sharedLine(_ viewer: UserProfile?, _ other: UserProfile) -> String? {
        let labels = shared(viewer, other).map(\.label)
        switch labels.count {
        case 0: return nil
        case 1: return "you both like \(labels[0])"
        case 2: return "you both like \(labels[0]) and \(labels[1])"
        default: return "you both like \(labels[0]), \(labels[1]) and more"
        }
    }
}
