//
//  Chat.swift
//  Click
//

import Foundation
import SwiftData

@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var participant: UserProfile?
    var folderRaw: String
    var lastActivity: Date
    var unreadCount: Int
    /// Super-like request flags. Declared defaults keep lightweight
    /// migration from phase-3 stores working.
    var isSuperLike: Bool = false
    var requestStateRaw: String = RequestState.none.rawValue

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        id: UUID = UUID(),
        participant: UserProfile? = nil,
        folder: ChatFolder = .messages,
        lastActivity: Date = .now,
        unreadCount: Int = 0,
        isSuperLike: Bool = false,
        requestState: RequestState = .none,
        messages: [Message] = []
    ) {
        self.id = id
        self.participant = participant
        self.folderRaw = folder.rawValue
        self.lastActivity = lastActivity
        self.unreadCount = unreadCount
        self.isSuperLike = isSuperLike
        self.requestStateRaw = requestState.rawValue
        self.messages = messages
    }

    var folder: ChatFolder {
        get { ChatFolder(rawValue: folderRaw) ?? .messages }
        set { folderRaw = newValue.rawValue }
    }

    var requestState: RequestState {
        get { RequestState(rawValue: requestStateRaw) ?? .none }
        set { requestStateRaw = newValue.rawValue }
    }

    /// Legacy phase-3 `.requests` rows predate request states; an
    /// incoming-only row with state `none` is treated as pending so old
    /// data gets the accept/deny flow too.
    var isPendingRequest: Bool {
        guard folder == .requests else { return false }
        switch requestState {
        case .pending: return true
        case .none: return !messages.contains { $0.isFromMe }
        case .accepted, .denied: return false
        }
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.sentAt < $1.sentAt }
    }

    var preview: String {
        sortedMessages.last?.text ?? "Say hi"
    }

    /// Blocked participants drop out of every list.
    var isVisible: Bool {
        guard let participant else { return false }
        return !participant.isBlocked
    }
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var text: String
    var isFromMe: Bool
    var sentAt: Date
    var conversation: Conversation?

    init(
        id: UUID = UUID(),
        text: String,
        isFromMe: Bool,
        sentAt: Date = .now,
        conversation: Conversation? = nil
    ) {
        self.id = id
        self.text = text
        self.isFromMe = isFromMe
        self.sentAt = sentAt
        self.conversation = conversation
    }
}

/// A MUTUAL match only. One-way likes are SentLike rows — inserting a
/// Match on every like made the matches folder claim "it clicked" for
/// people who never answered (MEGA-BRIEF 0.1).
@Model
final class Match {
    @Attribute(.unique) var id: UUID
    var profile: UserProfile?
    var matchedAt: Date
    var isSuperChat: Bool

    init(
        id: UUID = UUID(),
        profile: UserProfile? = nil,
        matchedAt: Date = .now,
        isSuperChat: Bool = false
    ) {
        self.id = id
        self.profile = profile
        self.matchedAt = matchedAt
        self.isSuperChat = isSuperChat
    }
}

/// A persisted swipe decision (MEGA-BRIEF 4.2). Session state meant the
/// same 22 people returned on every cold launch; the deck now remembers.
@Model
final class SwipeDecision {
    @Attribute(.unique) var profileID: UUID
    var liked: Bool
    var decidedAt: Date

    init(profileID: UUID, liked: Bool, decidedAt: Date = .now) {
        self.profileID = profileID
        self.liked = liked
        self.decidedAt = decidedAt
    }
}

/// An outgoing like that has not been answered — surfaced honestly as
/// "liked — no answer yet", never as a match.
@Model
final class SentLike {
    @Attribute(.unique) var id: UUID
    var profile: UserProfile?
    var sentAt: Date
    var isSuperLike: Bool = false

    init(
        id: UUID = UUID(),
        profile: UserProfile? = nil,
        sentAt: Date = .now,
        isSuperLike: Bool = false
    ) {
        self.id = id
        self.profile = profile
        self.sentAt = sentAt
        self.isSuperLike = isSuperLike
    }
}
