//
//  AppSchema.swift
//  Click
//

import Foundation
import SwiftData

enum AppSchema {
    /// Single source of truth for the SwiftData schema. Used by the app
    /// container and by the preview container so they cannot drift apart.
    static let models: [any PersistentModel.Type] = [
        UserProfile.self,
        ProfilePhoto.self,
        Conversation.self,
        Message.self,
        Match.self,
        BoosterInventory.self,
        DailyReward.self,
        Wallet.self,
        BingoBoard.self,
        Community.self,
        CommunityMembership.self
    ]
}
