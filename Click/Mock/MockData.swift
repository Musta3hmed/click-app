//
//  MockData.swift
//  Click
//
//  Everything in this folder stands in for a backend. To move to a real API,
//  replace `seedIfNeeded` with a network sync and delete this file.
//
//  No emoji anywhere in seed copy — emoji render as boxes wherever the
//  emoji font is unavailable (a live issue in the iOS 26.3 simulator).
//

import Foundation
import SwiftData
import UIKit

enum MockData {

    // MARK: - Seeding

    /// Populates the store with demo content. Safe to call on every launch.
    /// Each content family has its OWN emptiness guard: AccountEraser
    /// deletes conversations on sign-out but keeps candidate profiles, and
    /// with a single guard the demo chats would never come back for the
    /// next account. The CURRENT user's row is created by onboarding, never
    /// here.
    static func seedIfNeeded(_ context: ModelContext) {
        // UI tests need a deterministic store: wipe demo content first so a
        // reused simulator container cannot leave the test running against
        // stale (photo-less) data.
        if CommandLine.arguments.contains("--uitest-photos") {
            wipeAll(context)
        }

        // Sorted by createdAt (seeded with staggered timestamps) so the
        // index-based conversation scripts always attach to the intended
        // profile, and the deck order is stable.
        let candidatesDescriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { !$0.isCurrentUser },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        if (try? context.fetchCount(candidatesDescriptor)) == 0 {
            for profile in candidateProfiles() {
                context.insert(profile)
            }
        }

        let profiles = (try? context.fetch(candidatesDescriptor)) ?? []

        // Demo chats no longer pre-empt the empty state: a brand-new
        // account sees "no chats yet" and the message seeds only arrive
        // once the user has actually liked someone (checked per launch, so
        // they trickle in rather than appearing en masse on day one).
        // Guarded on the MESSAGES folder specifically — counting every
        // conversation let the seeded super-like requests block the demo
        // chats forever.
        let hasSwiped = ((try? context.fetchCount(FetchDescriptor<Match>())) ?? 0) > 0
        let messagesRaw = ChatFolder.messages.rawValue
        let messageThreads = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.folderRaw == messagesRaw }
        )
        if hasSwiped, (try? context.fetchCount(messageThreads)) == 0 {
            seedConversations(context, profiles: profiles)
        }

        // Super-like requests top-up: fetch-count guard so existing
        // phase-3 stores gain the accept/deny flow too.
        let superRaw = RequestState.pending.rawValue
        let pendingDescriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.isSuperLike && $0.requestStateRaw == superRaw }
        )
        if (try? context.fetchCount(pendingDescriptor)) == 0 {
            seedSuperLikeRequests(context, profiles: profiles)
        }
        if (try? context.fetchCount(FetchDescriptor<BoosterInventory>())) == 0 {
            seedBoosters(context)
        }
        if (try? context.fetchCount(FetchDescriptor<DailyReward>())) == 0 {
            seedDailyRewards(context)
        }

        if CommandLine.arguments.contains("--uitest-photos") {
            seedUITestPhotos(context, profiles: profiles)
        }

        try? context.save()
    }

    /// Full demo-content wipe, used only under the UI-test flag.
    private static func wipeAll(_ context: ModelContext) {
        for profile in (try? context.fetch(FetchDescriptor<UserProfile>())) ?? [] {
            context.delete(profile)
        }
        for conversation in (try? context.fetch(FetchDescriptor<Conversation>())) ?? [] {
            context.delete(conversation)
        }
        for match in (try? context.fetch(FetchDescriptor<Match>())) ?? [] {
            context.delete(match)
        }
        try? context.save()
    }

    // MARK: - Profiles

    private static func candidateProfiles() -> [UserProfile] {
        let seeds: [(String, Int, String, String, Zodiac, [String], Bool, Gender)] = [
            ("Maya Chen", 19, "coffee first, talk later", "AU", .virgo, ["coffee", "film", "art"], true, .woman),
            ("Leo Martins", 21, "skate or sleep", "BR", .leo, ["skating", "music", "travel"], false, .man),
            ("Priya Raman", 20, "will out-argue you about movies", "IN", .gemini, ["film", "books", "debate"], true, .woman),
            ("Noah Whitfield", 22, "gym, food, repeat", "GB", .taurus, ["gym", "food", "football"], false, .man),
            ("Sofia Rossi", 19, "chaotic good", "IT", .sagittarius, ["dance", "fashion", "travel"], false, .woman),
            ("Kai Tanaka", 20, "producing beats at 3am", "JP", .pisces, ["music", "gaming", "anime"], true, .man),
            ("Amara Okafor", 21, "plant mum, dog aunt", "NG", .cancer, ["plants", "dogs", "cooking"], false, .woman),
            ("Ethan Brooks", 23, "ask me about my fantasy team", "US", .aries, ["sports", "gaming", "food"], false, .man),
            ("Lena Novak", 18, "sketching strangers on the tram", "PL", .libra, ["art", "coffee", "music"], false, .woman),
            ("Diego Herrera", 22, "salsa lessons, no experience needed", "MX", .scorpio, ["dance", "cooking", "travel"], true, .man),
            ("Chloe Dubois", 20, "your nan's favourite", "FR", .capricorn, ["baking", "books", "cats"], false, .woman),
            ("Arjun Patel", 21, "startup bro in recovery", "IN", .aquarius, ["tech", "gym", "coffee"], false, .man),
            ("Zoe Kelly", 19, "surf report is my horoscope", "AU", .pisces, ["surfing", "music", "dogs"], true, .woman),
            ("Mateo Silva", 20, "two truths and a lie, go", "AR", .gemini, ["football", "music", "travel"], false, .man),
            ("Hana Kim", 22, "film photography enjoyer", "KR", .virgo, ["photography", "film", "coffee"], false, .woman),
            ("Oscar Lindqvist", 23, "cold water swimmer, warm person", "SE", .taurus, ["swimming", "books", "hiking"], false, .man),
            ("Fatima Haddad", 20, "architecture student, tired", "LB", .leo, ["design", "art", "coffee"], true, .woman),
            ("Ruby Thompson", 18, "I will beat you at Mario Kart", "NZ", .aries, ["gaming", "music", "dogs"], false, .woman),
            ("Tomas Novotny", 21, "climbing walls, literally", "CZ", .sagittarius, ["climbing", "hiking", "food"], false, .man),
            ("Isla Fraser", 19, "playlist curator, professionally nosy", "GB", .cancer, ["music", "books", "film"], false, .woman),
            ("Yusuf Demir", 22, "chess in the park, every Sunday", "TR", .libra, ["chess", "coffee", "travel"], false, .man),
            ("Nina Petrova", 20, "ballet then burgers", "RU", .scorpio, ["dance", "food", "art"], false, .woman)
        ]

        let base = Date.now
        return seeds.enumerated().map { index, seed in
            UserProfile(
                name: seed.0,
                age: seed.1,
                bio: seed.2,
                countryCode: seed.3,
                zodiac: seed.4,
                interests: seed.5,
                isVerified: seed.6,
                isOnline: index % 3 == 0,
                gender: seed.7,
                createdAt: base.addingTimeInterval(Double(index) * 0.01)
            )
        }
    }

    // MARK: - Conversations

    private static func seedConversations(_ context: ModelContext, profiles: [UserProfile]) {
        let scripts: [(Int, ChatFolder, Int, [(String, Bool, Int)])] = [
            // (profile index, folder, unread, [(text, isFromMe, minutes ago)])
            (0, .messages, 2, [
                ("heyy how's your week going", false, 180),
                ("honestly chaotic, yours?", true, 174),
                ("same tbh. what are you up to this weekend?", false, 12),
                ("nothing planned yet, tempt me", false, 8)
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
                ("hey! saw we both like cooking", false, 300)
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

    /// 2–3 pending super-like requests so the accept/deny flow is
    /// exercisable without a backend.
    private static func seedSuperLikeRequests(_ context: ModelContext, profiles: [UserProfile]) {
        let scripts: [(Int, String, Int)] = [
            (7, "ok your bio got me. fantasy team rivalry when?", 240),
            (13, "two truths and a lie: I super liked you, I regret it, I make great pasta", 720),
            (19, "your playlist taste is elite and I need the link", 1_100)
        ]
        for (profileIndex, text, minutesAgo) in scripts {
            guard profiles.indices.contains(profileIndex) else { continue }
            let profile = profiles[profileIndex]

            // Don't stack a request on someone the user already talks to.
            let profileID = profile.id
            let existing = FetchDescriptor<Conversation>(
                predicate: #Predicate { $0.participant?.id == profileID }
            )
            guard ((try? context.fetchCount(existing)) ?? 0) == 0 else { continue }

            let sentAt = Date.now.addingTimeInterval(-Double(minutesAgo) * 60)
            let conversation = Conversation(
                participant: profile,
                folder: .requests,
                lastActivity: sentAt,
                unreadCount: 1,
                isSuperLike: true,
                requestState: .pending
            )
            context.insert(conversation)
            context.insert(Message(text: text, isFromMe: false, sentAt: sentAt, conversation: conversation))
        }
    }

    // MARK: - Gamification

    private static func seedBoosters(_ context: ModelContext) {
        for kind in BoosterKind.allCases {
            context.insert(BoosterInventory(kind: kind, count: 0))
        }
    }

    private static func seedDailyRewards(_ context: ModelContext) {
        let rewards: [(Int, String, Int, BoosterKind?)] = [
            (1, "5 coins", 5, nil),
            (2, "8 coins", 8, nil),
            (3, "1 super chat", 0, .superChat),
            (4, "15 coins", 15, nil),
            (5, "20 coins", 20, nil),
            (6, "1 boost", 0, .boost),
            (7, "50 coins", 50, nil)
        ]
        for (day, label, coins, booster) in rewards {
            context.insert(DailyReward(day: day, rewardLabel: label, coinValue: coins, boosterKind: booster))
        }
    }

    // MARK: - UI test support

    /// Two solid-colour photos for EVERY profile, so whichever card is on
    /// top, UI tests exercise multi-photo paging and the safety-menu hit
    /// target (the paging overlay once swallowed it — FINDINGS §4).
    private static func seedUITestPhotos(_ context: ModelContext, profiles: [UserProfile]) {
        let colors: [UIColor] = [.systemOrange, .systemPink]
        let size = CGSize(width: 405, height: 540)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let datas: [Data] = colors.compactMap { color in
            UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                color.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }.jpegData(compressionQuality: 0.7)
        }

        for profile in profiles {
            for (index, data) in datas.enumerated() {
                context.insert(ProfilePhoto(data: data, sortIndex: index, owner: profile))
            }
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
            countryCode: "AU",
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
        me.ownerProviderID = "preview-user"
        container.mainContext.insert(me)
        container.mainContext.insert(Wallet(coins: 120))
        try? container.mainContext.save()

        return container
    }()
}
