//
//  ConversationView.swift
//  Click
//
//  One thread. While the conversation is a pending super-like request the
//  composer is replaced by an accept/deny bar — no replying to a request
//  without accepting it (also the honest safety posture).
//

import SwiftUI
import SwiftData

struct ConversationView: View {
    let conversation: Conversation

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motion) private var motion
    @Environment(ChromeState.self) private var chrome
    @State private var draft = ""
    @State private var sendBounce = 0
    @State private var confirmingDeny = false

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

    var body: some View {
        VStack(spacing: 0) {
            if conversation.isSuperLike {
                superLikeBanner
            }
            messageList
            icebreakerRow
            if conversation.isPendingRequest {
                requestBar
            } else {
                composer
            }
        }
        .background(Theme.background)
        .navigationTitle(conversation.participant?.name ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let participant = conversation.participant {
                    SafetyMenu(profile: participant, surface: "conversation")
                }
            }
        }
        .onAppear {
            conversation.unreadCount = 0
            try? context.save()
            // Full-height thread: the floating tab bar overlaid the
            // composer. onDisappear covers pop, block-induced dismiss and
            // the zoom transition alike.
            chrome.tabBarHidden = true
        }
        .onDisappear {
            chrome.tabBarHidden = false
        }
        // Blocking mid-conversation must take effect where it happened:
        // pop the screen instead of leaving the thread readable.
        .onChange(of: conversation.participant?.isBlocked) { _, isBlocked in
            if isBlocked == true { dismiss() }
        }
        .confirmationDialog(
            "Deny and delete this request?",
            isPresented: $confirmingDeny,
            titleVisibility: .visible
        ) {
            Button("Deny request", role: .destructive) { denyAndDismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The request and its message are removed. This can't be undone.")
        }
    }

    // MARK: - Super-like chrome

    private var superLikeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
            Text(
                conversation.isPendingRequest
                    ? "\(firstName) super liked you"
                    : "it started with a super like"
            )
            .font(.click(.footnote, weight: .heavy))
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.brandGradient)
        .accessibilityElement(children: .combine)
    }

    private var firstName: String {
        let name = conversation.participant?.name ?? "they"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// Replaces the composer while the request is pending.
    private var requestBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(motion.state) {
                    conversation.requestState = .accepted
                    conversation.folder = .messages
                    conversation.lastActivity = .now
                }
                try? context.save()
                Haptics.notify(.success)
            } label: {
                Label("accept", systemImage: "checkmark")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.online, in: Capsule())
            }
            .buttonStyle(.click)
            .accessibilityLabel("accept request from \(firstName)")

            Button {
                confirmingDeny = true
            } label: {
                Label("deny", systemImage: "xmark")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.click)
            .accessibilityLabel("deny request from \(firstName)")
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.vertical, 10)
        .background(Theme.background)
    }

    /// Denying from inside the thread must dismiss BEFORE deleting (same
    /// pattern as the blocked-participant onChange).
    private func denyAndDismiss() {
        Haptics.impact(.medium)
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.05))
            context.delete(conversation)  // Messages cascade.
            try? context.save()
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // The thread was the emptiest surface in the app: no
                // context, no time. The participant's summary opens it,
                // and messages carry day separators + drift timestamps.
                if let participant = conversation.participant {
                    ParticipantSummary(profile: participant, viewer: me)
                        .padding(.bottom, 12)
                }

                ForEach(threadItems) { item in
                    switch item.kind {
                    case .daySeparator(let label):
                        Text(label)
                            .font(.click(.caption, weight: .heavy))
                            .foregroundStyle(Theme.secondary)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .accessibilityAddTraits(.isHeader)
                    case .message(let message, let showsTime):
                        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 3) {
                            MessageBubble(message: message)
                            if showsTime {
                                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                                    .font(.clickPlain(.caption2, weight: .medium))
                                    .foregroundStyle(Theme.secondary)
                                    .padding(message.isFromMe ? .trailing : .leading, 6)
                                    .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
                            }
                        }
                        .transition(
                            message.isFromMe
                                ? .move(edge: .trailing)
                                    .combined(with: .scale(scale: 0.92, anchor: .bottomTrailing))
                                    .combined(with: .opacity)
                                : .opacity
                        )
                    }
                }
            }
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.vertical, 12)
            .animation(motion.state, value: conversation.messages.count)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
    }

    private struct ThreadItem: Identifiable {
        enum Kind {
            case daySeparator(String)
            case message(Message, showsTime: Bool)
        }
        let id: String
        let kind: Kind
    }

    /// Day separators between calendar days; a timestamp under a bubble
    /// whenever more than 10 minutes passed since the previous one (and
    /// always on the last message).
    private var threadItems: [ThreadItem] {
        let messages = conversation.sortedMessages
        var items: [ThreadItem] = []
        var previous: Message?
        let calendar = Calendar.current

        for (index, message) in messages.enumerated() {
            if previous.map({ !calendar.isDate($0.sentAt, inSameDayAs: message.sentAt) }) ?? true {
                let label: String
                if calendar.isDateInToday(message.sentAt) {
                    label = "today"
                } else if calendar.isDateInYesterday(message.sentAt) {
                    label = "yesterday"
                } else {
                    label = message.sentAt.formatted(date: .abbreviated, time: .omitted).lowercased()
                }
                items.append(ThreadItem(id: "day-\(message.id.uuidString)", kind: .daySeparator(label)))
            }

            let drifted = previous.map { message.sentAt.timeIntervalSince($0.sentAt) > 10 * 60 } ?? true
            let isLast = index == messages.count - 1
            items.append(ThreadItem(
                id: message.id.uuidString,
                kind: .message(message, showsTime: drifted || isLast)
            ))
            previous = message
        }
        return items
    }

    // MARK: - Icebreakers (MEGA-BRIEF 4.7)

    /// Generated from the ACTUAL interest overlap — genuine value from
    /// real data, and honest when there is none. Tapping fills the
    /// composer; it never sends.
    private var icebreakers: [String] {
        guard let participant = conversation.participant else { return [] }
        let shared = InterestMatching.shared(me, participant).prefix(2)
        var lines: [String] = shared.flatMap { interest in
            [
                "you put down \(interest.label) too — how did you get into it?",
                "ok important question: best \(interest.label) memory?"
            ]
        }
        if let entry = participant.promptAnswers.first(where: { !$0.answer.isEmpty }),
           let prompt = entry.prompt {
            lines.append("\"\(entry.answer)\" — tell me more about that (\(prompt.question))")
        }
        if lines.isEmpty {
            lines = [
                "what's been the best part of your week?",
                "describe your perfect sunday in three words",
                "what should I absolutely not ask you about?"
            ]
        }
        return Array(lines.prefix(3))
    }

    @ViewBuilder
    private var icebreakerRow: some View {
        if conversation.messages.isEmpty && !conversation.isPendingRequest {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(icebreakers, id: \.self) { line in
                        Button {
                            draft = line
                        } label: {
                            Text(line)
                                .font(.clickPlain(.footnote, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Theme.surface, in: Capsule())
                        }
                        .buttonStyle(.clickQuiet)
                        .accessibilityLabel("Use icebreaker: \(line)")
                        .accessibilityHint("Fills the message field, doesn't send")
                    }
                }
                .padding(.horizontal, Theme.Metric.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 4)
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("message…", text: $draft, axis: .vertical)
                .font(.clickPlain(.body))
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: Capsule())

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .symbolEffect(.bounce, value: sendBounce)
                    .frame(width: 44, height: 44)
                    // Plain Color animates; AnyShapeStyle erasure didn't.
                    .background(Circle().fill(canSend ? Theme.primary : Theme.fillDisabled))
                    .animation(motion.state, value: canSend)
            }
            .buttonStyle(.clickSilent)
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
        // First outgoing message promotes a request thread to messages —
        // replying must never leave the row stranded in the requests folder.
        if conversation.folder == .requests {
            conversation.folder = .messages
            if conversation.requestState == RequestState.none {
                conversation.requestState = .accepted
            }
        }
        draft = ""
        sendBounce += 1
        try? context.save()
        Haptics.impact(.light)
    }
}

/// Who you're talking to, at the top of the thread: photo/initials, the
/// bio, and what you genuinely share.
private struct ParticipantSummary: View {
    let profile: UserProfile
    let viewer: UserProfile?

    var body: some View {
        VStack(spacing: 8) {
            StickerAvatar(name: profile.name, size: 72, isOnline: profile.isOnline)

            HStack(spacing: 6) {
                Text(profile.name)
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.primary)
                Text("\(profile.displayAge)")
                    .font(.click(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.verified)
                }
            }

            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if let line = InterestMatching.sharedLine(viewer, profile) {
                Text(line)
                    .font(.click(.caption, weight: .heavy))
                    .foregroundStyle(Theme.brandPink)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    message.isFromMe ? Theme.primary : Theme.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Metric.control, style: .continuous)
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
    .environment(ChromeState())
    .modelContainer(MockData.previewContainer)
}
