//
//  DeckFilter.swift
//  Click
//
//  The one place deck-filtering logic lives, so the swipe deck and the
//  filter sheet's live count can never disagree.
//

import Foundation

enum DeckFilter {
    struct Criteria {
        var minAge: Int
        var maxAge: Int
        var verifiedOnly: Bool
        var interests: Set<String>
        /// false = show anyone sharing ANY selected interest;
        /// true = require ALL of them.
        var matchAll: Bool

        /// Whether anything beyond the defaults is set — the fallback
        /// banner only makes sense when a filter is actually narrowing.
        var isActive: Bool {
            minAge > 18 || maxAge < 99 || verifiedOnly || !interests.isEmpty
        }
    }

    /// The seeking preference is core matching, not a filter — it always
    /// applies, fallback or not. Profiles with no/undisclosed gender only
    /// appear for users open to everyone.
    static func seekingFiltered(_ candidates: [UserProfile], viewer: UserProfile?) -> [UserProfile] {
        let seeking = viewer?.seeking ?? []
        guard !seeking.isEmpty, !seeking.contains(.everyone) else { return candidates }
        return candidates.filter { profile in
            guard let gender = profile.gender else { return false }
            return seeking.contains { $0.includes(gender) }
        }
    }

    static func apply(_ criteria: Criteria, to profiles: [UserProfile]) -> [UserProfile] {
        profiles.filter { profile in
            let age = profile.displayAge
            guard age >= criteria.minAge, age <= criteria.maxAge else { return false }
            if criteria.verifiedOnly && !profile.isVerified { return false }
            if !criteria.interests.isEmpty {
                let theirs = Set(profile.interests)
                if criteria.matchAll {
                    guard criteria.interests.isSubset(of: theirs) else { return false }
                } else {
                    guard !theirs.isDisjoint(with: criteria.interests) else { return false }
                }
            }
            return true
        }
    }

    /// Score by default: shared interests reorder the deck (never remove),
    /// tie-breaking on the stable createdAt sort so it stays deterministic.
    static func scored(_ profiles: [UserProfile], viewer: UserProfile?) -> [UserProfile] {
        profiles.sorted { a, b in
            let scoreA = InterestMatching.score(viewer, a)
            let scoreB = InterestMatching.score(viewer, b)
            if scoreA != scoreB { return scoreA > scoreB }
            return a.createdAt < b.createdAt
        }
    }
}
