//
//  ConversationView.swift
//  Click
//

import SwiftUI
import SwiftData

struct ConversationView: View {
    let conversation: Conversation

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
        .background(Theme.background)
        .navigationTitle(conversation.participant?.name ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let participant = conversation.participant {
                    SafetyMenu(profile: participant)
                }
            }
        }
        .onAppear {
            conversation.unreadCount = 0
            try? context.save()
        }
        // Blocking mid-conversation must take effect where it happened:
        // pop the screen instead of leaving the thread readable.
        .onChange(of: conversation.participant?.isBlocked) { _, isBlocked in
            if isBlocked == true { dismiss() }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(conversation.sortedMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, Theme.Metric.gutter)
                .padding(.vertical, 12)
            }
            .onAppear {
                if let last = conversation.sortedMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("message…", text: $draft, axis: .vertical)
                .font(.clickPlain(.body))
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.surface, in: Capsule())

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(canSend ? Theme.primary : Theme.separator))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.vertical, 10)
        .background(Theme.background)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && conversation.isVisible
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let message = Message(text: text, isFromMe: true, conversation: conversation)
        context.insert(message)
        conversation.lastActivity = .now
        draft = ""
        try? context.save()
        Haptics.impact(.light)
    }
}

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isFromMe { Spacer(minLength: 50) }

            Text(message.text)
                .font(.clickPlain(.body))
                .foregroundStyle(message.isFromMe ? Theme.onPrimary : Theme.primary)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(
                    message.isFromMe ? Theme.primary : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

            if !message.isFromMe { Spacer(minLength: 50) }
        }
        .accessibilityLabel("\(message.isFromMe ? "You said" : "They said"): \(message.text)")
    }
}

#Preview {
    NavigationStack {
        ConversationView(
            conversation: Conversation(
                participant: UserProfile(name: "Maya Chen", age: 19),
                messages: []
            )
        )
    }
    .modelContainer(MockData.previewContainer)
}
