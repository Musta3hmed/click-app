//
//  MockData.swift
//  Click
//
//  Everything in this folder stands in for a backend. To move to a real API,
//  replace `seedIfNeeded` with a network sync and delete this file.
//

import Foundation
import SwiftData

enum MockData {

    // MARK: - Seeding

    /// Populates an empty store with candidate profiles. Safe to call on
    /// every launch. The CURRENT user's row is created by onboarding, not
    /// here — so the guard counts only non-current profiles.
    static func seedIfNeeded(_ context: ModelContext) {
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { !$0.isCurrentUser }
        )
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        let profiles = candidateProfiles()
        for profile in profiles {
            context.insert(profile)
        }

        seedConversations(context, profiles: profiles)
        seedBoosters(context)
        seedDailyRewards(context)
        context.insert(Wallet(coins: 0))

        try? context.save()
    }

    // MARK: - Profiles

    private static func candidateProfiles() -> [UserProfile] {
        let seeds: [(String, Int, String, String, Zodiac, [String], Bool, Gender)] = [
            ("Maya Chen", 19, "coffee first, talk later ☕️", "🇦🇺", .virgo, ["coffee", "film", "art"], true, .woman),
            ("Leo Martins", 21, "skate or sleep", "🇧🇷", .leo, ["skating", "music", "travel"], false, .man),
            ("Priya Raman", 20, "will out-argue you about movies", "🇮🇳", .gemini, ["film", "books", "debate"], true, .woman),
            ("Noah Whitfield", 22, "gym → food → repeat", "🇬🇧", .taurus, ["gym", "food", "football"], false, .man),
            ("Sofia Rossi", 19, "chaotic good", "🇮🇹", .sagittarius, ["dance", "fashion", "travel"], false, .woman),
            ("Kai Tanaka", 20, "producing beats at 3am", "🇯🇵", .pisces, ["music", "gaming", "anime"], true, .man),
            ("Amara Okafor", 21, "plant mum, dog aunt", "🇳🇬", .cancer, ["plants", "dogs", "cooking"], false, .woman),
            ("Ethan Brooks", 23, "ask me about my fantasy team", "🇺🇸", .aries, ["sports", "gaming", "food"], false, .man),
            ("Lena Novak", 18, "sketching strangers on the tram", "🇵🇱", .libra, ["art", "coffee", "music"], false, .woman),
            ("Diego Herrera", 22, "salsa lessons, no experience needed", "🇲🇽", .scorpio, ["dance", "cooking", "travel"], true, .man),
            ("Chloe Dubois", 20, "your nan's favourite", "🇫🇷", .capricorn, ["baking", "books", "cats"], false, .woman),
            ("Arjun Patel", 21, "startup bro in recovery", "🇮🇳", .aquarius, ["tech", "gym", "coffee"], false, .man),
            ("Zoe Kelly", 19, "surf report is my horoscope", "🇦🇺", .pisces, ["surfing", "music", "dogs"], true, .woman),
            ("Mateo Silva", 20, "two truths and a lie, go", "🇦🇷", .gemini, ["football", "music", "travel"], false, .man),
            ("Hana Kim", 22, "film photography enjoyer", "🇰🇷", .virgo, ["photography", "film", "coffee"], false, .woman),
            ("Oscar Lindqvist", 23, "cold water swimmer, warm person", "🇸🇪", .taurus, ["swimming", "books", "hiking"], false, .man),
            ("Fatima Haddad", 20, "architecture student, tired", "🇱🇧", .leo, ["design", "art", "coffee"], true, .woman),
            ("Ruby Thompson", 18, "I will beat you at Mario Kart", "🇳🇿", .aries, ["gaming", "music", "dogs"], false, .woman),
            ("Tomas Novotny", 21, "climbing walls, literally", "🇨🇿", .sagittarius, ["climbing", "hiking", "food"], false, .man),
            ("Isla Fraser", 19, "playlist curator, professionally nosy", "🇬🇧", .cancer, ["music", "books", "film"], false, .woman),
            ("Yusuf Demir", 22, "chess in the park, every Sunday", "🇹🇷", .libra, ["chess", "coffee", "travel"], false, .man),
            ("Nina Petrova", 20, "ballet then burgers", "🇷🇺", .scorpio, ["dance", "food", "art"], false, .woman)
        ]

        return seeds.enumerated().map { index, seed in
            UserProfile(
                name: seed.0,
                age: seed.1,
                bio: seed.2,
                countryFlag: seed.3,
                zodiac: seed.4,
                interests: seed.5,
                isVerified: seed.6,
                isOnline: index % 3 == 0,
                gender: seed.7
            )
        }
    }

    // MARK: - Conversations

    private static func seedConversations(_ context: ModelContext, profiles: [UserProfile]) {
        let scripts: [(Int, ChatFolder, Int, [(String, Bool, Int)])] = [
            // (profile index, folder, unread, [(text, isFromMe, minutes ago)])
            (0, .messages, 2, [
                ("heyy how's your week going", false, 180),
                ("honestly chaotic 😂 yours?", true, 174),
                ("same tbh. what are you up to this weekend?", false, 12),
                ("nothing planned yet 👀", false, 8)
            ]),
            (2, .messages, 0, [
                ("ok but your film takes are unhinged", true, 1_440),
                ("you say that like it's a bad thing", false, 1_430),
                ("it's a compliment. mostly.", true, 1_425)
            ]),
            (5, .messages, 1, [
                ("sent you that beat", false, 600),
                ("it goes hard actually", true, 590),
                ("wait really? I nearly deleted it", false, 45)
            ]),
            (12, .messages, 0, [
                ("surf was unreal this morning", false, 2_880),
                ("jealous. I was asleep", true, 2_870)
            ]),
            (9, .requests, 1, [
                ("hey! saw we both like cooking 👋", false, 300)
            ]),
            (16, .requests, 1, [
                ("your profile made me laugh", false, 900)
            ])
        ]

        for (profileIndex, folder, unread, messageSeeds) in scripts {
            guard profiles.indices.contains(profileIndex) else { continue }

            let conversation = Conversation(
                participant: profiles[profileIndex],
                folder: folder,
                lastActivity: .now,
                unreadCount: unread
            )
            context.insert(conversation)

            var newest = Date.distantPast
            for (text, isFromMe, minutesAgo) in messageSeeds {
                let sentAt = Date.now.addingTimeInterval(-Double(minutesAgo) * 60)
                let message = Message(
                    text: text,
                    isFromMe: isFromMe,
                    sentAt: sentAt,
                    conversation: conversation
                )
                context.insert(message)
                newest = max(newest, sentAt)
            }
            conversation.lastActivity = newest
        }
    }

    // MARK: - Gamification

    private static func seedBoosters(_ context: ModelContext) {
        for kind in BoosterKind.allCases {
            context.insert(BoosterInventory(kind: kind, count: 0))
        }
    }

    private static func seedDailyRewards(_ context: ModelContext) {
        let rewards: [(Int, String, Int)] = [
            (1, "5 coins", 5),
            (2, "8 coins", 8),
            (3, "1 super chat", 0),
            (4, "15 coins", 15),
            (5, "20 coins", 20),
            (6, "1 boost", 0),
            (7, "50 coins", 50)
        ]
        for (day, label, coins) in rewards {
            context.insert(DailyReward(day: day, rewardLabel: label, coinValue: coins))
        }
    }

    // MARK: - Previews

    /// In-memory container with seed data, for SwiftUI previews.
    @MainActor
    static var previewContainer: ModelContainer = {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Previews cannot recover from a broken schema, so failing loudly
        // here is the correct behaviour.
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seedIfNeeded(container.mainContext)

        // Previews skip onboarding, so fabricate the current-user row that
        // onboarding would normally create.
        let me = UserProfile(
            name: "Jordan",
            age: 18,
            bio: "just here for the vibes",
            countryFlag: "🇦🇺",
            zodiac: .aquarius,
            interests: ["music", "gaming", "gym"],
            isVerified: true,
            isOnline: true,
            isCurrentUser: true,
            gender: .man
        )
        me.birthDate = Calendar.current.date(byAdding: .year, value: -18, to: .now)
        me.seeking = [.everyone]
        me.city = "Sydney"
        me.country = "Australia"
        me.countryCode = "AU"
        container.mainContext.insert(me)
        try? container.mainContext.save()

        return container
    }()
}
