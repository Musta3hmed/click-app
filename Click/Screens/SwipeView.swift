//
//  SwipeView.swift
//  Click
//
//  Card deck. Drag is the like/pass mechanism: the top card follows the
//  finger, commits past the distance threshold OR on a flick, and flies
//  off carrying the throw's velocity. The action row is
//  [rewind] [message] [super like]; VoiceOver likes/passes through
//  accessibility actions on the card itself.
//
//  Layout note: no ScrollView here — the card's drag gesture would fight
//  the scroll pan and make everything below the card unreachable.
//
//  Deck state is keyed by profile ID, not index — blocking the top card
//  removes it from the filtered query mid-session, and integer indexes
//  silently aliased onto the wrong person.
//
//  CardDeck owns the drag state, so a drag frame re-renders the deck only,
//  never the header/composer/toast (they used to re-render at 120Hz).
//

import SwiftUI
import SwiftData

struct SwipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.motion) private var motion

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
                .padding(.bottom, Theme.Metric.tabBarClearance)
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

    /// 1 free per day, then booster-gated. With composer text the opener is
    /// sent as a super-like thread; empty is a highlighted like. Rewinding
    /// a super like deletes the rows but does NOT refund the booster/free
    /// use — documented behaviour, not a bug.
    private func superLike() {
        guard !deckBusy, let profile = remaining.first else { return }

        let wallet = Wallet.ensure(in: context)
        let freeUsedToday = wallet.lastFreeSuperLikeAt.map { Calendar.current.isDateInToday($0) } ?? false
        if freeUsedToday {
            let inventory = BoosterInventory.ensure(.superChat, in: context)
            guard inventory.count > 0 else {
                Haptics.notify(.error)
                alertMessage = "You've used today's free super like, and you're out of super chat boosters. Earn more from daily rewards and bingo."
                return
            }
            inventory.count -= 1
        } else {
            wallet.lastFreeSuperLikeAt = .now
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

    @State private var celebrationPending: UserProfile?

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
                myName: me?.name ?? "you"
            ) {
                withAnimation(motion.celebrateOut) {
                    celebrating = nil
                }
            }
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

struct DeckCommand: Equatable {
    let liked: Bool
    /// Distinguishes two identical commands in a row.
    let id = UUID()
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

// MARK: - Card deck

/// Owns drag state so a drag frame re-renders only the deck.
private struct CardDeck: View {
    let cards: [UserProfile]
    @Binding var isBusy: Bool
    @Binding var command: DeckCommand?
    let onCommitStart: (UserProfile, Bool) -> Void
    let onFlyOffComplete: (UserProfile, Bool) -> Void
    let onReset: () -> Void

    @Environment(\.motion) private var motion
    @State private var drag: CGSize = .zero
    @State private var flyingAway = false
    /// Threshold "release now" cue: the stamp snaps up briefly.
    @State private var stampBoosted = false

    /// Horizontal travel, in points, that commits a swipe.
    private let threshold: CGFloat = 110
    /// A flick past this speed commits even below the distance threshold.
    private let flickVelocity: CGFloat = 420

    private var dragProgress: CGFloat {
        min(1, abs(drag.width) / threshold)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width, geo.size.height * 0.72)
            let cardHeight = min(geo.size.height, cardWidth / 0.72)

            ZStack {
                if cards.isEmpty {
                    DeckExhaustedState { onReset() }
                } else {
                    // Render back-to-front so the current card sits on top.
                    ForEach(Array(cards.prefix(3).enumerated()).reversed(), id: \.element.id) { offset, profile in
                        deckCard(profile: profile, offset: offset)
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(cardScale(offset: offset))
                            .offset(y: CGFloat(offset) * 12 * (offset == 1 ? (1 - dragProgress) : 1))
                            .rotationEffect(offset == 0 ? .degrees(Double(drag.width / 14)) : .zero)
                            .offset(offset == 0 ? drag : .zero)
                            .opacity(offset == 0 && flyingAway ? 0 : 1)
                            .overlay {
                                if offset == 0 {
                                    decisionOverlay
                                }
                            }
                            // Gesture AND hit-testing are gated on the
                            // fly-off: touching the departing card used to
                            // teleport it back to the finger.
                            .gesture((offset == 0 && !flyingAway) ? dragGesture : nil)
                            .allowsHitTesting(offset == 0 && !flyingAway)
                            // Back cards are visual context only — VoiceOver
                            // must not read three profiles at once.
                            .accessibilityHidden(offset != 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Metric.gutter)
        .onChange(of: command) { _, newValue in
            guard let newValue else { return }
            command = nil
            performSwipe(liked: newValue.liked, velocity: .zero)
        }
        .onChange(of: dragProgress >= 1) { _, crossed in
            guard crossed, !flyingAway else { return }
            // 120ms snap — the "release now" cue.
            withAnimation(motion.pressIn) { stampBoosted = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.12))
                withAnimation(motion.pressOut) { stampBoosted = false }
            }
        }
    }

    @ViewBuilder
    private func deckCard(profile: UserProfile, offset: Int) -> some View {
        if offset == 0 {
            SwipeCard(profile: profile)
                // Slight physical tilt with the drag.
                .rotation3DEffect(
                    .degrees(Double(drag.width / 180).clamped(to: -2...2)),
                    axis: (x: 0, y: 1, z: 0)
                )
                // The drag is the only like/pass mechanism — VoiceOver and
                // Switch Control users need real actions on the card.
                .accessibilityAction(named: "Like") {
                    performSwipe(liked: true, velocity: .zero)
                }
                .accessibilityAction(named: "Pass") {
                    performSwipe(liked: false, velocity: .zero)
                }
        } else {
            // Static back cards rasterise once instead of re-compositing
            // their shadows on every drag frame.
            SwipeCard(profile: profile)
                .drawingGroup()
        }
    }

    /// The card behind grows toward full size as the top card travels.
    private func cardScale(offset: Int) -> CGFloat {
        guard offset > 0 else { return 1 }
        let base = 1 - CGFloat(offset) * 0.04
        return offset == 1 ? base + 0.04 * dragProgress : base
    }

    private var decisionOverlay: some View {
        ZStack {
            stamp(text: "LIKE", color: Theme.online, baseRotation: -14)
                .opacity(Double(max(0, drag.width) / threshold))
                .scaleEffect(stampScale(active: drag.width > 0))
                .rotationEffect(.degrees(drag.width > 0 ? Double(-6 * (1 - dragProgress)) : 0))
            stamp(text: "NOPE", color: Theme.accent, baseRotation: 14)
                .opacity(Double(max(0, -drag.width) / threshold))
                .scaleEffect(stampScale(active: drag.width < 0))
                .rotationEffect(.degrees(drag.width < 0 ? Double(6 * (1 - dragProgress)) : 0))
        }
        .allowsHitTesting(false)
    }

    private func stampScale(active: Bool) -> CGFloat {
        guard active else { return 0.5 }
        let base = 0.5 + 0.5 * dragProgress
        return stampBoosted ? base * 1.12 : base
    }

    private func stamp(text: String, color: Color, baseRotation: Double) -> some View {
        Text(text)
            .font(.click(.largeTitle, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metric.chip, style: .continuous)
                    .strokeBorder(color, lineWidth: 5)
            )
            .rotationEffect(.degrees(baseRotation))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 36)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Direct 1:1 finger tracking — an implicit .animation here
                // once overrode the explicit fly-off (FINDINGS §42).
                drag = value.translation
            }
            .onEnded { value in
                let travelled = value.translation.width
                let speed = value.velocity.width
                if travelled > threshold || speed > flickVelocity {
                    performSwipe(liked: true, velocity: value.velocity)
                } else if travelled < -threshold || speed < -flickVelocity {
                    performSwipe(liked: false, velocity: value.velocity)
                } else {
                    withAnimation(motion.gesture) {
                        drag = .zero
                    }
                }
            }
    }

    /// Fly-off that carries the throw's velocity, sequenced with an
    /// interruptible animation completion instead of asyncAfter.
    private func performSwipe(liked: Bool, velocity: CGSize) {
        guard let profile = cards.first, !flyingAway else { return }

        isBusy = true
        onCommitStart(profile, liked)

        let vertical = (drag.height + velocity.height * 0.12).clamped(to: -260...80)
        withAnimation(motion.flyOff) {
            drag = CGSize(width: liked ? 640 : -640, height: vertical == 0 ? -120 : vertical)
            flyingAway = true
        } completion: {
            onFlyOffComplete(profile, liked)
            // Swap with animations OFF for the drag reset ONLY — the rest
            // of the deck animates on Motion.state from the parent.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                drag = .zero
                flyingAway = false
            }
            isBusy = false
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Match celebration

private struct MatchCelebrationView: View {
    let profile: UserProfile
    let myName: String
    let onDismiss: () -> Void

    @Environment(\.motion) private var motion
    /// Staged cascade index: 0 nothing, 1 avatars, 2 heading, 3 the rest.
    @State private var stage = 0
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ZStack {
            // Opaque: at 0.96 four percent of the dark app bled through.
            Theme.brandGradient
                .ignoresSafeArea()

            if motion.reduceMotion == false {
                ConfettiView()
            }

            VStack(spacing: 24) {
                Spacer()

                HStack(spacing: -18) {
                    StickerAvatar(name: myName, size: 110)
                        .rotationEffect(.degrees(-8))
                        .scaleEffect(stage >= 1 ? 1 : 0.2)
                    StickerAvatar(name: profile.name, size: 110)
                        .rotationEffect(.degrees(8))
                        .scaleEffect(stage >= 1 ? 1 : 0.2)
                }
                .opacity(stage >= 1 ? 1 : 0)

                Text("IT CLICKED!")
                    .font(.system(.largeTitle, design: .rounded).weight(.black).italic())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .scaleEffect(stage >= 2 ? 1 : 0.6)
                    .opacity(stage >= 2 ? 1 : 0)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)

                Text("\(profile.name.split(separator: " ").first.map(String.init) ?? profile.name) likes you too")
                    .font(.clickPlain(.headline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .opacity(stage >= 3 ? 1 : 0)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Text("keep swiping")
                        .font(.click(.headline, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.click)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .opacity(stage >= 3 ? 1 : 0)
                .accessibilityLabel("Keep swiping")
            }
        }
        .task {
            // Staged cascade on the shared celebrate spring; under Reduce
            // Motion the stagger is 0 and every step is a fade.
            for step in 1...3 {
                withAnimation(motion.celebrate) { stage = step }
                try? await Task.sleep(for: .seconds(motion.stagger == 0 ? 0.02 : motion.stagger * 2))
            }
            headingFocused = true
        }
        // A full-screen takeover: VoiceOver must not walk into the deck
        // behind it.
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("It's a match with \(profile.name)")
    }
}

// MARK: - Card

private struct SwipeCard: View {
    let profile: UserProfile

    @Environment(\.motion) private var motion
    @State private var photoIndex = 0
    /// Decoded once per card — decoding JPEGs inside a computed property ran
    /// on every drag frame once real photos existed.
    @State private var photos: [UIImage] = []
    @Namespace private var progress

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background

            // Bottom scrim so the text always reads over a photo.
            LinearGradient(
                colors: [.clear, Theme.cardScrim],
                startPoint: .center,
                endPoint: .bottom
            )

            infoBlock

            // Paging zones sit ABOVE the info text (tapping the name still
            // pages, stories-style) but BELOW the controls that follow —
            // and they cede the top band so the safety menu, online pill
            // and progress bar always win (FINDINGS §4).
            if photos.count > 1 {
                pagingTapZones
            }

            if photos.count > 1 {
                photoProgress
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if profile.isOnline {
                onlinePill
                    .padding(.top, photos.count > 1 ? 18 : 0)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            SafetyMenu(profile: profile)
                .padding(6)
                .background {
                    Circle().fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .light)
                }
                .padding(.top, photos.count > 1 ? 18 : 0)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous))
        // Edge stroke keeps the card's silhouette readable on OLED; the
        // compositing group collapses the layers to ONE Gaussian pass for
        // the shadow instead of three per drag frame.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous)
                .strokeBorder(Theme.glowStroke, lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Theme.shadowColor, radius: 16, y: 8)
        .task(id: profile.id) {
            photos = profile.orderedPhotos.compactMap { UIImage(data: $0.data) }
            photoIndex = 0
        }
        // DemoPhotos can add photos while the card is on screen.
        .onChange(of: profile.photos.count) { _, _ in
            photos = profile.orderedPhotos.compactMap { UIImage(data: $0.data) }
            photoIndex = min(photoIndex, max(0, photos.count - 1))
        }
        .accessibilityElement(children: .contain)
    }

    /// Left/right thirds page the photos; the top 88pt is left alone so the
    /// safety menu, online pill and progress bar stay tappable.
    private var pagingTapZones: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 88)
            HStack(spacing: 0) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { page(-1) }
                Rectangle().fill(.clear)
                    .allowsHitTesting(false)
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { page(1) }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var background: some View {
        if photos.indices.contains(photoIndex) {
            GeometryReader { geo in
                Image(uiImage: photos[photoIndex])
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            // Distinct identity per page, or the cross-fade never runs.
            .id(photoIndex)
            .transition(.opacity)
            .accessibilityHidden(true)
        } else {
            // No photos yet: keep the gradient look.
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Text(initials)
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundStyle(.white.opacity(0.35))
            }
            .accessibilityHidden(true)
        }
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(profile.name)
                    .font(.click(.title, weight: .heavy))
                Text("\(profile.displayAge)")
                    .font(.click(.title2, weight: .bold))
                    .opacity(0.9)
                if profile.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.verified)
                }
            }
            .foregroundStyle(Theme.onImagePrimary)

            Text(profile.bio)
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(Theme.onImageSecondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                CountryBadge(code: profile.countryCode, onDark: true)
                Text(profile.zodiac.label)
                    .font(.clickPlain(.caption, weight: .semibold))
                    .foregroundStyle(Theme.onImageSecondary)
                ForEach(profile.interests.prefix(3), id: \.self) { interest in
                    Text(interest)
                        .font(.clickPlain(.caption, weight: .semibold))
                        .foregroundStyle(Theme.onImagePrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.onImageFill))
                }
            }
        }
        .padding(20)
        // One merged element: without this, VoiceOver read every text twice
        // (once via children, once via a container label).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(profile.name), \(profile.displayAge). \(profile.bio). "
            + "\(profile.isVerified ? "Verified. " : "")Interests: \(profile.interests.prefix(3).joined(separator: ", "))"
        )
    }

    /// Stories-style progress: one sliding capsule over dimmed track
    /// segments. Also the VoiceOver handle for paging.
    private var photoProgress: some View {
        HStack(spacing: 4) {
            ForEach(photos.indices, id: \.self) { index in
                ZStack {
                    Capsule()
                        .fill(Theme.onImagePrimary.opacity(0.35))
                        .frame(height: 3)
                    if index == photoIndex {
                        Capsule()
                            .fill(Theme.onImagePrimary)
                            .frame(height: 3)
                            .matchedGeometryEffect(id: "photoProgress", in: progress)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photos")
        .accessibilityValue("Photo \(photoIndex + 1) of \(photos.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page(1)
            case .decrement: page(-1)
            @unknown default: break
            }
        }
    }

    private var onlinePill: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.online).frame(width: 8, height: 8)
            Text("online")
                .font(.click(.caption, weight: .heavy))
                .foregroundStyle(Theme.onImagePrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule().fill(.ultraThinMaterial)
                .environment(\.colorScheme, .light)
        }
    }

    private func page(_ delta: Int) {
        let next = photoIndex + delta
        guard photos.indices.contains(next) else { return }
        Haptics.selection()
        withAnimation(motion.screenFade) {
            photoIndex = next
        }
    }

    private var initials: String {
        let words = profile.name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var gradientColors: [Color] {
        Theme.gradient(for: profile.name, in: Theme.cardGradients)
    }
}

// MARK: - Bulk message sheet

/// Confirmation, determinate progress, and the done state for the bulk
/// send. The heavy lifting happens in SwipeView.performBulkSend().
private struct BulkMessageSheet: View {
    let text: String
    let recipientCount: Int
    @Binding var progress: Double?
    @Binding var sentCount: Int?
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            if let sentCount {
                doneState(sentCount)
            } else if progress != nil {
                sendingState
            } else {
                confirmState
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(progress != nil && sentCount == nil)
    }

    private var confirmState: some View {
        VStack(spacing: 16) {
            Text("bulk message")
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)

            Text(text)
                .font(.clickPlain(.body, weight: .medium))
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cardSurface(radius: Theme.Metric.control)

            VStack(spacing: 6) {
                Text("send to the next \(recipientCount) people in your deck")
                    .font(.click(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.primary)
                Text("costs 1 bulk chat booster · once per day")
                    .font(.clickPlain(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Text("everyone can report messages they don't want — keep it kind.")
                    .font(.clickPlain(.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onConfirm()
            } label: {
                Text("send to \(recipientCount) people")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .accessibilityLabel("Send to \(recipientCount) people")

            Button("cancel") { dismiss() }
                .font(.clickPlain(.body, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .accessibilityLabel("Cancel")
        }
    }

    private var sendingState: some View {
        VStack(spacing: 16) {
            Text("sending…")
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
            ProgressView(value: progress ?? 0)
                .tint(Theme.brandPink)
                .accessibilityLabel("Sending progress")
        }
        .padding(.top, 24)
    }

    private func doneState(_ count: Int) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.online)
                .accessibilityHidden(true)
            Text("sent to \(count) people")
                .font(.click(.title3, weight: .heavy))
                .foregroundStyle(Theme.primary)
            Button {
                dismiss()
            } label: {
                Text("done")
                    .font(.click(.headline, weight: .heavy))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(.click)
            .accessibilityLabel("Done")
        }
        .padding(.top, 16)
    }
}

// MARK: - Empty deck

private struct DeckExhaustedState: View {
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Theme.brandPink)
            Text("that's everyone")
                .font(.click(.title2, weight: .heavy))
                .foregroundStyle(Theme.primary)
            Text("check back later, or loosen your filters.")
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            PillButton(title: "start over", action: onReset)
                .padding(.top, 8)
        }
        .padding(Theme.Metric.gutter)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    SwipeView()
        .modelContainer(MockData.previewContainer)
}
