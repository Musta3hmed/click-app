//
//  AccountEraser.swift
//  Click
//
//  Destroys every trace of the signed-in account on this device. Used by
//  sign-out AND account deletion — on a shared or resold phone the next
//  person must never inherit the previous user's identity, DOB, photos or
//  messages (that inheritance was also a full 18+ gate bypass).
//

import Foundation
import SwiftData

enum AccountEraser {

    /// Delete the current user's profile (photos cascade), all conversations
    /// and messages, matches, wallet, bingo boards; reset daily-reward and
    /// booster progress; clear the onboarding flags. Seeded candidate
    /// profiles stay — they are demo content, not user data.
    @MainActor
    static func eraseCurrentAccount(in context: ModelContext) {
        let currentUsers = (try? context.fetch(
            FetchDescriptor<UserProfile>(predicate: #Predicate { $0.isCurrentUser })
        )) ?? []
        for user in currentUsers {
            context.delete(user)  // ProfilePhoto rows cascade.
        }

        for conversation in (try? context.fetch(FetchDescriptor<Conversation>())) ?? [] {
            context.delete(conversation)  // Messages cascade.
        }
        for match in (try? context.fetch(FetchDescriptor<Match>())) ?? [] {
            context.delete(match)
        }
        for like in (try? context.fetch(FetchDescriptor<SentLike>())) ?? [] {
            context.delete(like)
        }
        for decision in (try? context.fetch(FetchDescriptor<SwipeDecision>())) ?? [] {
            context.delete(decision)
        }
        for wallet in (try? context.fetch(FetchDescriptor<Wallet>())) ?? [] {
            context.delete(wallet)
        }
        for board in (try? context.fetch(FetchDescriptor<BingoBoard>())) ?? [] {
            context.delete(board)
        }
        for reward in (try? context.fetch(FetchDescriptor<DailyReward>())) ?? [] {
            reward.isClaimed = false
            reward.claimedAt = nil
        }
        for inventory in (try? context.fetch(FetchDescriptor<BoosterInventory>())) ?? [] {
            inventory.count = 0
        }

        // The account's memberships cascade with its profile row above;
        // communities IT created (pending or approved) are top-level rows
        // and go here, along with the join rate-limit defaults.
        CommunityService.eraseUserCreated(in: context)

        // Block/mute/report state lives ON the candidate rows — it is the
        // previous user's behavioural data and must not be inherited by the
        // next account (who would see a blocklist they never made).
        for candidate in (try? context.fetch(FetchDescriptor<UserProfile>())) ?? [] {
            candidate.isBlocked = false
            candidate.isMuted = false
            candidate.reportedReasonRaw = nil
            candidate.reportedAt = nil
            candidate.reportedSurface = nil
        }

        try? context.save()

        let defaults = UserDefaults.standard
        defaults.set(false, forKey: DefaultsKey.onboardingCompleted)
        defaults.set(0, forKey: DefaultsKey.onboardingStep)
        defaults.set(false, forKey: DefaultsKey.welcomePopupShown)
        // Account-scoped preferences must not leak to the next sign-in.
        defaults.removeObject(forKey: DefaultsKey.showMyState)
        defaults.removeObject(forKey: DefaultsKey.visibleInFindNewFriends)
        defaults.removeObject(forKey: DefaultsKey.demoPhotosLastFailure)
        defaults.removeObject(forKey: DefaultsKey.phoneVerified)
        defaults.removeObject(forKey: DefaultsKey.phoneNumber)
        defaults.removeObject(forKey: DefaultsKey.filterMinAge)
        defaults.removeObject(forKey: DefaultsKey.filterMaxAge)
        defaults.removeObject(forKey: DefaultsKey.filterVerifiedOnly)
        defaults.removeObject(forKey: DefaultsKey.filterInterests)
        defaults.removeObject(forKey: DefaultsKey.filterInterestsMatchAll)
        defaults.removeObject(forKey: DefaultsKey.lastActiveAt)
        defaults.removeObject(forKey: DefaultsKey.notificationsPrimed)
        defaults.removeObject(forKey: DefaultsKey.notifyMessages)
        defaults.removeObject(forKey: DefaultsKey.notifyDailyReward)
        defaults.removeObject(forKey: DefaultsKey.notifyBoost)
        defaults.removeObject(forKey: DefaultsKey.notifyEvents)
        // Nothing scheduled for this account may fire for the next one.
        NotificationService.cancelAll()
        // DefaultsKey.appearance stays — it is a device preference.
    }
}
