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

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        id: UUID = UUID(),
        participant: UserProfile? = nil,
        folder: ChatFolder = .messages,
        lastActivity: Date = .now,
        unreadCount: Int = 0,
        messages: [Message] = []
    ) {
        self.id = id
        self.participant = participant
        self.folderRaw = folder.rawValue
        self.lastActivity = lastActivity
        self.unreadCount = unreadCount
        self.messages = messages
    }

    var folder: ChatFolder {
        get { ChatFolder(rawValue: folderRaw) ?? .messages }
        set { folderRaw = newValue.rawValue }
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
