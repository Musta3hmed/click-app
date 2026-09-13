//
//  Interest.swift
//  Click
//
//  The interest taxonomy: a value-type catalogue, NOT a @Model. Storage
//  on UserProfile stays `[String]` but its contract is canonical ids only
//  ("live-music", never a drawn label). Labels and SF Symbol names live
//  here so renaming a label never orphans stored rows, and localisation
//  later is a table, not a data migration. When a backend arrives,
//  promote to a @Model join the way CommunityMembership is shaped.
//

import Foundation
import SwiftData

enum InterestCategory: String, CaseIterable, Codable {
    case creative
    case active
    case food
    case media
    case goingOut = "going-out"
    case mind
    case living
    case travel

    /// Lowercase per the casing rule — Click draws this.
    var label: String {
        switch self {
        case .creative: "creative"
        case .active: "active"
        case .food: "food & drink"
        case .media: "media"
        case .goingOut: "going out"
        case .mind: "mind"
        case .living: "living"
        case .travel: "travel"
        }
    }
}

struct Interest: Identifiable, Hashable, Codable {
    /// Canonical slug, stable forever: "live-music".
    let id: String
    let category: InterestCategory
    /// SF Symbol — CI bans emoji, and a bad name renders as nothing:
    /// `interestCatalogSymbolsResolve` in ClickTests asserts every one.
    let symbolName: String
    /// The only string ever drawn (lowercase per the casing rule).
    let label: String
}

enum InterestCatalog {
    /// Stored interests cap (owner decision: raised 5 -> 8; the card
    /// still shows 3).
    static let maxSelected = 8
    /// How many chips a swipe card shows.
    static let shownOnCard = 3

    static let all: [Interest] = [
        // creative
        Interest(id: "art", category: .creative, symbolName: "paintbrush.fill", label: "art & drawing"),
        Interest(id: "photography", category: .creative, symbolName: "camera.fill", label: "photography"),
        Interest(id: "film-making", category: .creative, symbolName: "video.fill", label: "film-making"),
        Interest(id: "making-music", category: .creative, symbolName: "music.quarternote.3", label: "making music"),
        Interest(id: "writing", category: .creative, symbolName: "pencil.line", label: "writing"),
        Interest(id: "design", category: .creative, symbolName: "paintpalette.fill", label: "design"),
        Interest(id: "fashion", category: .creative, symbolName: "tshirt.fill", label: "fashion"),
        Interest(id: "crafts", category: .creative, symbolName: "scissors", label: "crafts"),
        // active
        Interest(id: "gym", category: .active, symbolName: "dumbbell.fill", label: "gym"),
        Interest(id: "running", category: .active, symbolName: "figure.run", label: "running"),
        Interest(id: "hiking", category: .active, symbolName: "figure.hiking", label: "hiking"),
        Interest(id: "climbing", category: .active, symbolName: "figure.climbing", label: "climbing"),
        Interest(id: "swimming", category: .active, symbolName: "figure.pool.swim", label: "swimming"),
        Interest(id: "surfing", category: .active, symbolName: "figure.surfing", label: "surfing"),
        Interest(id: "skating", category: .active, symbolName: "figure.skating", label: "skating"),
        Interest(id: "cycling", category: .active, symbolName: "figure.outdoor.cycle", label: "cycling"),
        Interest(id: "yoga", category: .active, symbolName: "figure.yoga", label: "yoga"),
        Interest(id: "football", category: .active, symbolName: "soccerball", label: "football"),
        Interest(id: "basketball", category: .active, symbolName: "basketball.fill", label: "basketball"),
        Interest(id: "tennis", category: .active, symbolName: "tennis.racket", label: "tennis"),
        Interest(id: "martial-arts", category: .active, symbolName: "figure.martial.arts", label: "martial arts"),
        Interest(id: "dance", category: .active, symbolName: "figure.dance", label: "dance"),
        // food & drink
        Interest(id: "coffee", category: .food, symbolName: "cup.and.saucer.fill", label: "coffee"),
        Interest(id: "cooking", category: .food, symbolName: "frying.pan", label: "cooking"),
        Interest(id: "baking", category: .food, symbolName: "birthday.cake.fill", label: "baking"),
        Interest(id: "eating-out", category: .food, symbolName: "fork.knife", label: "eating out"),
        Interest(id: "brunch", category: .food, symbolName: "sun.max.fill", label: "brunch"),
        Interest(id: "cocktails", category: .food, symbolName: "wineglass.fill", label: "cocktails"),
        Interest(id: "tea", category: .food, symbolName: "mug.fill", label: "tea"),
        Interest(id: "street-food", category: .food, symbolName: "takeoutbag.and.cup.and.straw.fill", label: "street food"),
        // media
        Interest(id: "films", category: .media, symbolName: "film.fill", label: "films"),
        Interest(id: "tv-series", category: .media, symbolName: "tv.fill", label: "tv & series"),
        Interest(id: "anime", category: .media, symbolName: "sparkles.tv.fill", label: "anime"),
        Interest(id: "books", category: .media, symbolName: "book.fill", label: "books"),
        Interest(id: "podcasts", category: .media, symbolName: "headphones", label: "podcasts"),
        Interest(id: "gaming", category: .media, symbolName: "gamecontroller.fill", label: "gaming"),
        Interest(id: "board-games", category: .media, symbolName: "dice.fill", label: "board games"),
        // going out
        Interest(id: "live-music", category: .goingOut, symbolName: "music.note.house.fill", label: "live music"),
        Interest(id: "festivals", category: .goingOut, symbolName: "party.popper.fill", label: "festivals"),
        Interest(id: "clubbing", category: .goingOut, symbolName: "figure.socialdance", label: "clubbing"),
        Interest(id: "pubs", category: .goingOut, symbolName: "wineglass", label: "pubs"),
        Interest(id: "karaoke", category: .goingOut, symbolName: "music.mic", label: "karaoke"),
        Interest(id: "comedy", category: .goingOut, symbolName: "theatermasks.fill", label: "comedy"),
        Interest(id: "museums", category: .goingOut, symbolName: "building.columns.fill", label: "museums"),
        Interest(id: "markets", category: .goingOut, symbolName: "basket.fill", label: "markets"),
        // mind
        Interest(id: "languages", category: .mind, symbolName: "globe", label: "languages"),
        Interest(id: "tech", category: .mind, symbolName: "laptopcomputer", label: "tech"),
        Interest(id: "science", category: .mind, symbolName: "atom", label: "science"),
        Interest(id: "history", category: .mind, symbolName: "scroll.fill", label: "history"),
        Interest(id: "philosophy", category: .mind, symbolName: "brain.head.profile", label: "philosophy"),
        Interest(id: "chess", category: .mind, symbolName: "checkerboard.rectangle", label: "chess"),
        Interest(id: "debate", category: .mind, symbolName: "bubble.left.and.bubble.right.fill", label: "debate"),
        Interest(id: "volunteering", category: .mind, symbolName: "hand.raised.fill", label: "volunteering"),
        Interest(id: "astrology", category: .mind, symbolName: "moon.stars.fill", label: "astrology"),
        // living
        Interest(id: "dogs", category: .living, symbolName: "dog.fill", label: "dogs"),
        Interest(id: "cats", category: .living, symbolName: "cat.fill", label: "cats"),
        Interest(id: "plants", category: .living, symbolName: "leaf.fill", label: "plants"),
        Interest(id: "gardening", category: .living, symbolName: "tree.fill", label: "gardening"),
        Interest(id: "camping", category: .living, symbolName: "tent.fill", label: "camping"),
        Interest(id: "beach", category: .living, symbolName: "beach.umbrella.fill", label: "beach"),
        Interest(id: "stargazing", category: .living, symbolName: "sparkles", label: "stargazing"),
        // travel
        Interest(id: "travel", category: .travel, symbolName: "airplane", label: "travel"),
        Interest(id: "road-trips", category: .travel, symbolName: "car.fill", label: "road trips"),
        Interest(id: "backpacking", category: .travel, symbolName: "backpack.fill", label: "backpacking"),
        Interest(id: "city-breaks", category: .travel, symbolName: "building.2.fill", label: "city breaks"),
    ]

    static let byID: [String: Interest] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func grouped() -> [(category: InterestCategory, interests: [Interest])] {
        InterestCategory.allCases.compactMap { category in
            let members = all.filter { $0.category == category }
            return members.isEmpty ? nil : (category, members)
        }
    }

    /// The drawn label for a stored id. Falls back to the raw string so a
    /// not-yet-migrated legacy value degrades to what it always showed.
    static func label(for id: String) -> String {
        byID[id]?.label ?? id
    }

    static func symbolName(for id: String) -> String? {
        byID[id]?.symbolName
    }

    // MARK: - Legacy migration

    /// The 29 strings phase-4 seed data stored, mapped to canonical ids.
    /// Most were already id-shaped; the five renames are explicit.
    static let legacyMap: [String: String] = [
        "film": "films",
        "food": "eating-out",
        "music": "live-music",
        "sports": "football",
        // Already-canonical legacy strings map to themselves so migration
        // is a plain lookup with no special cases.
        "art": "art", "books": "books", "coffee": "coffee",
        "cooking": "cooking", "dance": "dance", "gaming": "gaming",
        "gym": "gym", "hiking": "hiking", "photography": "photography",
        "travel": "travel", "anime": "anime", "baking": "baking",
        "cats": "cats", "chess": "chess", "climbing": "climbing",
        "debate": "debate", "design": "design", "dogs": "dogs",
        "fashion": "fashion", "football": "football", "plants": "plants",
        "skating": "skating", "surfing": "surfing", "swimming": "swimming",
        "tech": "tech",
    ]

    /// One-shot store migration: rewrites every profile's interests (and
    /// the deck filter defaults) from legacy strings to canonical ids.
    /// Guarded by DefaultsKey.interestsSchemaVersion so it runs once.
    @MainActor
    static func migrateLegacyStrings(in context: ModelContext) {
        let key = DefaultsKey.interestsSchemaVersion
        guard UserDefaults.standard.integer(forKey: key) < 1 else { return }

        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        for profile in profiles {
            let migrated = profile.interests.compactMap { legacyMap[$0] ?? byID[$0]?.id }
            if migrated != profile.interests {
                // De-dupe while keeping order (film + films must not double).
                var seen = Set<String>()
                profile.interests = migrated.filter { seen.insert($0).inserted }
            }
        }
        try? context.save()

        // The filter sheet stored the same legacy strings.
        let filterRaw = UserDefaults.standard.string(forKey: DefaultsKey.filterInterests) ?? ""
        if !filterRaw.isEmpty {
            let migrated = filterRaw.split(separator: ",")
                .compactMap { legacyMap[String($0)] ?? byID[String($0)]?.id }
            UserDefaults.standard.set(Set(migrated).sorted().joined(separator: ","), forKey: DefaultsKey.filterInterests)
        }

        UserDefaults.standard.set(1, forKey: key)
    }
}
