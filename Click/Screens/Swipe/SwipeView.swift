//
//  SwipeView.swift
//  Click
//
//  Orchestrates the swipe tab: header, deck, action row, composer,
//  toast and celebration. The deck's drag mechanics live in CardDeck,
//  the card itself in SwipeCard, the celebration and bulk sheet in
//  their own files.
//
//  Layout note: no ScrollView here — the card's drag gesture would fight
//  the scroll pan and make everything below the card unreachable.
//
//  Deck state is keyed by profile ID, not index — blocking the top card
//  removes it from the filtered query mid-session, and integer indexes
//  silently aliased onto the wrong person.
//

import SwiftUI
import SwiftData

struct SwipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.motion) private var motion
    @Environment(ChromeState.self) private var chrome

    @Query(
        filter: #Predicate<UserProfile> { !$0.isCurrentUser && !$0.isBlocked },
        sort: \UserProfile.createdAt
    )
    private var candidates: [UserProfile]

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @Query private var conversations: [Conversation]

    // MARK: Session state

    /// O(1) membership + explicit order (rewind needs the order).
    @State private var swipedIDs: Set<UUID> = []
    @State private var swipeOrder: [UUID] = []
    /// Everything each swipe created, so rewind is N-deep and cleans up.
    @State private var rewindStack: [RewindEntry] = []
    /// Set for the swipe the deck is currently animating (opener/super
    /// context travels alongside the fly-off).
    @State private var pendingContext: SwipeContext?
    /// Parent-visible "deck is animating" flag (mutated by CardDeck only).
    @State private var deckBusy = false
    /// Parent -> deck: programmatic swipe (message send, super like).
    @State private var deckCommand: DeckCommand?

    @State private var opener = ""
    @State private var toast: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var celebrating: UserProfile?
    @State private var celebrationPending: UserProfile?
    @State private var showingFilters = false
    @State private var alertMessage: String?

    // Bulk message flow
    @State private var showingBulkSheet = false
    @State private var bulkProgress: Double?
    @State private var bulkSentCount: Int?

    @FocusState private var composerFocused: Bool

    // Deck filters (SwipeFilterSheet writes these).
    @AppStorage(DefaultsKey.filterMinAge) private var filterMinAge = 18
    @AppStorage(DefaultsKey.filterMaxAge) private var filterMaxAge = 99
    @AppStorage(DefaultsKey.filterVerifiedOnly) private var filterVerifiedOnly = false
    @AppStorage(DefaultsKey.filterInterests) private var filterInterestsRaw = ""

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

    var body: some View {
        VStack(spacing: 0) {
            header

            OverlappingSheet(ambient: true) {
                VStack(spacing: 14) {
                    CardDeck(
                        cards: Array(remaining.prefix(3)),
                        viewer: me,
                        isBusy: $deckBusy,
                        command: $deckCommand,
                        onCommitStart: { profile, liked in
                            commitData(profile: profile, liked: liked)
                        },
                        onFlyOffComplete: { profile, liked in
                            finishSwipe(profile: profile, liked: liked)
                        },
                        onReset: { reset() }
                    )
                    actionRow
                    composer
                }
                .padding(.top, 16)
                // The keyboard covers the tab bar anyway: while the
                // composer is focused the clearance collapses, so the
                // whole column slides up and the field stays visible
                // above the keyboard.
                .padding(.bottom, composerFocused ? Theme.Metric.Space.m : Theme.Metric.tabBarClearance)
                .animation(motion.state, value: composerFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .overlay(alignment: .bottom) { toastView }
        .overlay { celebrationOverlay }
        .sensoryFeedback(.success, trigger: celebrating != nil) { _, new in new }
        .sheet(isPresented: $showingFilters) {
            SwipeFilterSheet()
        }
        .sheet(isPresented: $showingBulkSheet) {
            BulkMessageSheet(
                text: opener.trimmingCharacters(in: .whitespaces),
                recipientCount: min(100, remaining.count),
                progress: $bulkProgress,
                sentCount: $bulkSentCount,
                onConfirm: { performBulkSend() }
            )
        }
        .alert(
            "Hold on",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        TexturedHeader(title: "swipe", texture: .clouds) {
            HStack(spacing: 10) {
                if let me, me.isBoosted, let until = me.boostedUntil {
                    BoostBadge(until: until)
                }

                Button {
                    showingFilters = true
                } label: {
                    GlassCapsule {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.white)
                        Text("filters")
                            .font(.click(.footnote, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.clickSilent)
                .accessibilityLabel("Filters")
                .accessibilityHint("Age range, verified only, interests")
            }
        }
    }

    // MARK: - Deck contents

    /// Seeking + filter sheet criteria. Profiles with no/undisclosed gender
    /// only appear for users open to everyone.
    private var deck: [UserProfile] {
        let seeking = me?.seeking ?? []
        let interests = Set(filterInterestsRaw.split(separator: ",").map(String.init))
        return candidates.filter { profile in
            if !seeking.isEmpty && !seeking.contains(.everyone) {
                guard let gender = profile.gender,
                      seeking.contains(where: { $0.includes(gender) }) else { return false }
            }
            let age = profile.displayAge
            guard age >= filterMinAge, age <= filterMaxAge else { return false }
            if filterVerifiedOnly && !profile.isVerified { return false }
            if !interests.isEmpty && Set(profile.interests).isDisjoint(with: interests) { return false }
            return true
        }
    }

    private var remaining: [UserProfile] {
        deck.filter { !swipedIDs.contains($0.id) }
    }

    // MARK: - Action row: [rewind] [message] [super like]

    private var actionRow: some View {
        HStack(spacing: 12) {
            circleButton("arrow.uturn.backward", tint: Theme.coin, label: "Rewind", size: 46) {
                rewind()
            }
            .disabled(rewindStack.isEmpty)

            // Tap = focus the opener composer; long-press menu = bulk.
            Menu {
                Button {
                    startBulkFlow()
                } label: {
                    Label("bulk message", systemImage: "envelope.fill")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .heavy))
                    Text("message")
                        .font(.click(.headline, weight: .heavy))
                }
                .foregroundStyle(Theme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.primary, in: Capsule())
            } primaryAction: {
                Haptics.selection()
                composerFocused = true
            }
            .accessibilityLabel("Message")
            .accessibilityHint("Writes an opener; hold for bulk message")

            circleButton("star.fill", tint: Theme.coin, label: "Super like", size: 58) {
                superLike()
            }
            .overlay {
                Circle().strokeBorder(Theme.brandGradient, lineWidth: 2)
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .disabled(remaining.isEmpty)
    }

    private func circleButton(
        _ systemImage: String,
        tint: Color,
        label: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.glowStroke, lineWidth: 1))
                .compositingGroup()
                .shadow(color: Theme.shadowColor, radius: 8, y: 4)
        }
        .buttonStyle(.click)
        .accessibilityLabel(label)
    }

    // MARK: - Composer

    /// Send an opener with the like — creates the match AND the conversation
    /// in one action. Empty field = nothing; the deck itself likes/passes.
    private var composer: some View {
        HStack(spacing: 10) {
            TextField("say something with your like…", text: $opener)
                .font(.clickPlain(.subheadline, weight: .medium))
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { sendOpener() }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface, in: Capsule())
                .accessibilityLabel("Message to send with your like")

            Button {
                sendOpener()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 44, height: 44)
                    .background(canSendOpener ? Theme.primary : Theme.fillDisabled, in: Circle())
                    .animation(motion.state, value: canSendOpener)
            }
            .buttonStyle(.click)
            .disabled(!canSendOpener)
            .accessibilityLabel("Send message with like")
        }
        .padding(.horizontal, Theme.Metric.gutter)
    }

    private var canSendOpener: Bool {
        !opener.trimmingCharacters(in: .whitespaces).isEmpty && !remaining.isEmpty
    }

    private func sendOpener() {
        // Guard FIRST: tapping send during the fly-off created orphan
        // conversations for the next card.
        guard !deckBusy, canSendOpener, let profile = remaining.first else { return }
        let text = opener.trimmingCharacters(in: .whitespaces)
        opener = ""
        composerFocused = false

        let conversation = conversationForOpener(profile: profile, text: text)
        pendingContext = SwipeContext(conversation: conversation, isSuper: false)
        deckCommand = DeckCommand(liked: true)
    }

    /// Reuses an existing thread ("start over" must not duplicate).
    private func conversationForOpener(profile: UserProfile, text: String) -> Conversation {
        if let existing = conversations.first(where: { $0.participant?.id == profile.id }) {
            context.insert(Message(text: text, isFromMe: true, conversation: existing))
            existing.lastActivity = .now
            return existing
        }
        let conversation = Conversation(participant: profile, folder: .messages)
        context.insert(conversation)
        context.insert(Message(text: text, isFromMe: true, conversation: conversation))
        return conversation
    }

    // MARK: - Super like

    /// Free per day up to the subscription tier's allowance (1 on free,
    /// 5 on click+, unlimited on gold), then booster-gated. With composer
    /// text the opener is sent as a super-like thread; empty is a
    /// highlighted like. Rewinding a super like deletes the rows but does
    /// NOT refund the booster/free use — documented behaviour, not a bug.
    private func superLike() {
        guard !deckBusy, let profile = remaining.first else { return }

        let wallet = Wallet.ensure(in: context)
        // Day rollover resets the allowance counter.
        let sameDay = wallet.lastFreeSuperLikeAt.map { Calendar.current.isDateInToday($0) } ?? false
        if !sameDay {
            wallet.freeSuperLikesUsedToday = 0
        }
        let allowance = wallet.subscriptionTier.freeSuperLikesPerDay
        if wallet.freeSuperLikesUsedToday < allowance {
            wallet.freeSuperLikesUsedToday += 1
            wallet.lastFreeSuperLikeAt = .now
        } else {
            let inventory = BoosterInventory.ensure(.superChat, in: context)
            guard inventory.count > 0 else {
                Haptics.notify(.error)
                alertMessage = "You've used today's free super likes, and you're out of super chat boosters. Earn more from daily rewards and bingo — or upgrade your tier for a bigger daily allowance."
                return
            }
            inventory.count -= 1
        }

        let text = opener.trimmingCharacters(in: .whitespaces)
        var conversation: Conversation?
        if !text.isEmpty {
            opener = ""
            composerFocused = false
            let thread = conversationForOpener(profile: profile, text: text)
            thread.isSuperLike = true
            conversation = thread
        }

        pendingContext = SwipeContext(conversation: conversation, isSuper: true)
        deckCommand = DeckCommand(liked: true)
    }

    // MARK: - Bulk message

    private func startBulkFlow() {
        let text = opener.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            alertMessage = "Write your message in the composer first — bulk message sends that text."
            return
        }
        guard !remaining.isEmpty else {
            alertMessage = "Your deck is empty — no one to send to."
            return
        }

        let wallet = Wallet.ensure(in: context)
        if let last = wallet.lastBulkSendAt, Date.now.timeIntervalSince(last) < 24 * 60 * 60 {
            let next = last.addingTimeInterval(24 * 60 * 60)
            alertMessage = "Bulk message is limited to once a day. You can send again \(next.formatted(.relative(presentation: .named)))."
            return
        }
        guard BoosterInventory.ensure(.bulkChat, in: context).count > 0 else {
            Haptics.notify(.error)
            alertMessage = "Bulk message costs 1 bulk chat booster and you have none. Earn them from daily rewards and bingo."
            return
        }

        bulkProgress = nil
        bulkSentCount = nil
        showingBulkSheet = true
    }

    /// One composed message to the next N (<=100) people. Guardrails: an
    /// earned booster is consumed, one send per 24h, celebrations are
    /// suppressed, no fake replies, and rewind is cleared (undoing 100
    /// rows isn't supported).
    private func performBulkSend() {
        let text = opener.trimmingCharacters(in: .whitespaces)
        let targets = Array(remaining.prefix(100))
        guard !text.isEmpty, !targets.isEmpty else { return }

        let wallet = Wallet.ensure(in: context)
        BoosterInventory.ensure(.bulkChat, in: context).count -= 1
        wallet.lastBulkSendAt = .now

        opener = ""
        composerFocused = false
        bulkProgress = 0

        Task { @MainActor in
            let now = Date.now
            for (index, profile) in targets.enumerated() {
                let existing = conversations.first { $0.participant?.id == profile.id }
                let conversation: Conversation
                if let existing {
                    conversation = existing
                } else {
                    conversation = Conversation(participant: profile, folder: .messages)
                    context.insert(conversation)
                }
                // Staggered lastActivity keeps ChatsView sorting stable;
                // unread stays 0 so the badge doesn't explode.
                let sentAt = now.addingTimeInterval(-Double(targets.count - index) * 0.5)
                context.insert(Message(text: text, isFromMe: true, sentAt: sentAt, conversation: conversation))
                conversation.lastActivity = sentAt
                conversation.unreadCount = 0

                // A like per recipient, but NO celebration in the loop —
                // ~50 takeovers would fire otherwise.
                let profileID = profile.id
                let matchDescriptor = FetchDescriptor<Match>(
                    predicate: #Predicate { $0.profile?.id == profileID }
                )
                if ((try? context.fetchCount(matchDescriptor)) ?? 0) == 0 {
                    context.insert(Match(profile: profile))
                }

                if index % 10 == 9 {
                    bulkProgress = Double(index + 1) / Double(targets.count)
                    // Let the progress bar actually render.
                    await Task.yield()
                }
            }

            // One save at the end; the deck swap happens in a single
            // animations-disabled transaction.
            try? context.save()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                for profile in targets {
                    swipedIDs.insert(profile.id)
                    swipeOrder.append(profile.id)
                }
            }
            rewindStack = []  // Undoing 100 rows isn't supported.

            bulkProgress = 1
            bulkSentCount = targets.count
            Haptics.notify(.success)
        }
    }

    // MARK: - Swipe data commit

    /// Runs the moment a swipe starts animating. Creates the Match (deduped
    /// — "start over" must not re-create rows), records the rewind entry,
    /// and decides on the celebration.
    private func commitData(profile: UserProfile, liked: Bool) {
        Haptics.impact(liked ? .medium : .light)
        let context0 = pendingContext
        pendingContext = nil

        var createdMatch: Match?
        var mutual = false
        if liked {
            let profileID = profile.id
            let existingMatch = FetchDescriptor<Match>(
                predicate: #Predicate { $0.profile?.id == profileID }
            )
            if ((try? context.fetchCount(existingMatch)) ?? 0) == 0 {
                let match = Match(profile: profile, isSuperChat: context0?.isSuper ?? false)
                context.insert(match)
                createdMatch = match
            }
            try? context.save()
            mutual = Boost.likesYouBack(profile, boosted: me?.isBoosted ?? false)

            // A mutual like creates the conversation, so the match exists
            // in chats — the celebration used to lead nowhere.
            if mutual, context0?.conversation == nil,
               !conversations.contains(where: { $0.participant?.id == profile.id }) {
                context.insert(Conversation(participant: profile, folder: .messages))
                try? context.save()
            }
        }

        rewindStack.append(RewindEntry(
            profileID: profile.id,
            match: createdMatch,
            conversation: context0?.conversation
        ))

        if mutual {
            celebrationPending = profile
        } else if context0?.conversation != nil {
            // Suppress the toast when a celebration will cover it anyway.
            showToast("sent to \(profile.name.split(separator: " ").first.map(String.init) ?? profile.name)")
        }
    }

    /// Runs when the fly-off animation completes.
    private func finishSwipe(profile: UserProfile, liked: Bool) {
        withAnimation(motion.state) {
            swipedIDs.insert(profile.id)
            swipeOrder.append(profile.id)
        }
        if let profile = celebrationPending {
            celebrationPending = nil
            withAnimation(motion.celebrate) {
                celebrating = profile
            }
        }
    }

    // MARK: - Rewind (N-deep)

    private func rewind() {
        guard let entry = rewindStack.popLast() else { return }
        Haptics.impact(.light)
        withAnimation(motion.state) {
            swipedIDs.remove(entry.profileID)
            swipeOrder.removeAll { $0 == entry.profileID }
        }
        if let match = entry.match {
            context.delete(match)
        }
        if let conversation = entry.conversation {
            context.delete(conversation)  // Messages cascade.
        }
        try? context.save()
    }

    private func reset() {
        withAnimation(motion.state) {
            swipedIDs = []
            swipeOrder = []
        }
        rewindStack = []
    }

    // MARK: - Toast & celebration

    private func showToast(_ text: String) {
        toastDismissTask?.cancel()
        withAnimation(motion.state) {
            toast = text
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(motion.celebrateOut) {
                toast = nil
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Label(toast, systemImage: "paperplane.fill")
                .font(.click(.subheadline, weight: .bold))
                .foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.primary, in: Capsule())
                .padding(.bottom, Theme.Metric.tabBarClearance + 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel(toast)
        }
    }

    @ViewBuilder
    private var celebrationOverlay: some View {
        if let profile = celebrating {
            MatchCelebrationView(
                profile: profile,
                myName: me?.name ?? "you",
                onSayHi: {
                    withAnimation(motion.celebrateOut) {
                        celebrating = nil
                    }
                    // The mutual like created the conversation; jump
                    // straight into it via the chats tab.
                    if let conversation = conversations.first(where: { $0.participant?.id == profile.id }) {
                        chrome.requestedConversationID = conversation.id
                        chrome.requestedTab = .chats
                    }
                },
                onDismiss: {
                    withAnimation(motion.celebrateOut) {
                        celebrating = nil
                    }
                }
            )
            // The parent owns the entrance — the view no longer fights it
            // with its own onAppear spring.
            .transition(motion.takeover)
        }
    }
}

// MARK: - Swipe plumbing types

private struct RewindEntry {
    let profileID: UUID
    let match: Match?
    let conversation: Conversation?
}

private struct SwipeContext {
    let conversation: Conversation?
    let isSuper: Bool
}

// MARK: - Boost badge

/// Isolated so the per-second countdown tick can't re-render (and jank)
/// anything else.
private struct BoostBadge: View {
    let until: Date

    var body: some View {
        GlassCapsule {
            Image(systemName: "bolt.fill")
                .foregroundStyle(Theme.brandViolet)
            Text(timerInterval: Date.now...until, countsDown: true)
                .font(.click(.footnote, weight: .heavy))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Boost active")
        .accessibilityValue("about \(max(1, Int(until.timeIntervalSinceNow / 60))) minutes remaining")
    }
}

#Preview {
    SwipeView()
        .environment(ChromeState())
        .modelContainer(MockData.previewContainer)
}
