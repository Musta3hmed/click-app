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

    @Query(sort: [SortDescriptor(\Community.sortIndex), SortDescriptor(\Community.createdAt)])
    private var allCommunities: [Community]

    // MARK: Swipe state

    /// Persisted decisions (MEGA-BRIEF 4.2) — session @State meant every
    /// cold launch reset the deck and the same people returned forever.
    @Query private var decisions: [SwipeDecision]

    private var swipedIDs: Set<UUID> {
        Set(decisions.map(\.profileID))
    }
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
    /// Community lens: session state, nil = everyone.
    @State private var lensCommunityID: String?

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
    @AppStorage(DefaultsKey.filterInterestsMatchAll) private var filterMatchAll = false

    private var me: UserProfile? { currentUsers.first { !$0.isDeleted } }

    var body: some View {
        VStack(spacing: 0) {
            header

            OverlappingSheet(ambient: true) {
                VStack(spacing: 14) {
                    if filtersFellBack {
                        fallbackBanner
                    }
                    if lensFellBack, let lensCommunity {
                        lensFallbackBanner(lensCommunity)
                    }
                    CardDeck(
                        cards: Array(remaining.prefix(3)),
                        viewer: me,
                        reportSurface: lensCommunity.map { "deck lens:\($0.id)" } ?? "deck",
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
                recipientCount: min(Self.bulkCap, remaining.count),
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

                // Community lens beside filters — only once there is a
                // community to switch into.
                if !myCommunities.isEmpty {
                    Menu {
                        Button {
                            lensCommunityID = nil
                        } label: {
                            Label("everyone", systemImage: lensCommunityID == nil ? "checkmark" : "person.2.fill")
                        }
                        ForEach(myCommunities) { community in
                            Button {
                                lensCommunityID = community.id
                            } label: {
                                Label(community.name, systemImage: lensCommunityID == community.id ? "checkmark" : community.symbolName)
                            }
                        }
                    } label: {
                        GlassCapsule {
                            Image(systemName: lensCommunity?.symbolName ?? "person.3.fill")
                                .foregroundStyle(.white)
                            Text(lensCommunity?.name ?? "everyone")
                                .font(.click(.footnote, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityLabel("Community lens")
                    .accessibilityValue(lensCommunity?.name ?? "everyone")
                    .accessibilityHint("Switches the deck to one of your communities")
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

    private var filterCriteria: DeckFilter.Criteria {
        DeckFilter.Criteria(
            minAge: filterMinAge,
            maxAge: filterMaxAge,
            verifiedOnly: filterVerifiedOnly,
            interests: Set(filterInterestsRaw.split(separator: ",").map(String.init)),
            matchAll: filterMatchAll
        )
    }

    /// Seeking always applies — it's core matching, not a filter.
    private var seekingDeck: [UserProfile] {
        DeckFilter.seekingFiltered(candidates, viewer: me)
    }

    private var filteredDeck: [UserProfile] {
        DeckFilter.apply(filterCriteria, to: seekingDeck)
    }

    /// Empty-deck guard: if the filters empty the deck but people exist
    /// behind them, show everyone with a persistent banner rather than a
    /// silent empty state.
    private var filtersFellBack: Bool {
        filterCriteria.isActive && filteredDeck.isEmpty && !seekingDeck.isEmpty
    }

    private var deck: [UserProfile] {
        filtersFellBack ? seekingDeck : filteredDeck
    }

    // MARK: Community lens
    // Filters the same non-blocked candidate set the deck already uses,
    // so block stays transitive by construction.

    private var myCommunities: [Community] {
        guard let me else { return [] }
        let joined = Set(me.memberships.map(\.communityID))
        return allCommunities.filter { joined.contains($0.id) && $0.state == .approved }
    }

    private var lensCommunity: Community? {
        guard let lensCommunityID else { return nil }
        return myCommunities.first { $0.id == lensCommunityID }
    }

    private var lensedDeck: [UserProfile] {
        guard let lensCommunity else { return deck }
        return deck.filter { profile in
            profile.memberships.contains { $0.communityID == lensCommunity.id }
        }
    }

    /// A lens is even easier to empty than a filter — same fallback rule.
    private var lensFellBack: Bool {
        lensCommunity != nil && lensedDeck.isEmpty && !deck.isEmpty
    }

    /// Scored by shared interests (reorders, never removes).
    private var remaining: [UserProfile] {
        let pool = lensFellBack ? deck : lensedDeck
        return DeckFilter.scored(pool.filter { !swipedIDs.contains($0.id) }, viewer: me)
    }

    /// Persistent, honest, and actionable — never a silent empty state.
    private var fallbackBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            Text("no one matches your filters — showing everyone")
                .font(.clickPlain(.footnote, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                showingFilters = true
            } label: {
                Text("change filters")
                    .font(.click(.footnote, weight: .heavy))
                    .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.clickQuiet)
            .accessibilityLabel("Change filters")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .cardSurface(radius: Theme.Metric.control)
        .padding(.horizontal, Theme.Metric.gutter)
        .accessibilityElement(children: .combine)
    }

    private func lensFallbackBanner(_ community: Community) -> some View {
        HStack(spacing: 10) {
            Image(systemName: community.symbolName)
                .foregroundStyle(CommunityService.tint(community.tintToken))
                .accessibilityHidden(true)
            Text("no one in \(community.name) right now — showing everyone")
                .font(.clickPlain(.footnote, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                lensCommunityID = nil
            } label: {
                Text("turn off")
                    .font(.click(.footnote, weight: .heavy))
                    .foregroundStyle(Theme.primary)
            }
            .buttonStyle(.clickQuiet)
            .accessibilityLabel("Turn off the community lens")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .cardSurface(radius: Theme.Metric.control)
        .padding(.horizontal, Theme.Metric.gutter)
        .accessibilityElement(children: .combine)
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

        let opener = conversationForOpener(profile: profile, text: text)
        pendingContext = SwipeContext(
            conversation: opener.conversation,
            createdConversation: opener.created,
            openerMessage: opener.message,
            isSuper: false
        )
        deckCommand = DeckCommand(liked: true)
    }

    /// Reuses an existing thread ("start over" must not duplicate) and
    /// reports exactly what it created, so rewind can undo ONLY that.
    private func conversationForOpener(
        profile: UserProfile,
        text: String
    ) -> (conversation: Conversation, message: Message, created: Bool) {
        if let existing = conversations.first(where: { $0.participant?.id == profile.id }) {
            let message = Message(text: text, isFromMe: true, conversation: existing)
            context.insert(message)
            existing.lastActivity = .now
            return (existing, message, false)
        }
        let conversation = Conversation(participant: profile, folder: .messages)
        context.insert(conversation)
        let message = Message(text: text, isFromMe: true, conversation: conversation)
        context.insert(message)
        return (conversation, message, true)
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
        var swipeContext = SwipeContext(conversation: nil, createdConversation: false, openerMessage: nil, isSuper: true)
        if !text.isEmpty {
            opener = ""
            composerFocused = false
            let result = conversationForOpener(profile: profile, text: text)
            result.conversation.isSuperLike = true
            swipeContext = SwipeContext(
                conversation: result.conversation,
                createdConversation: result.created,
                openerMessage: result.message,
                isSuper: true
            )
        }

        pendingContext = swipeContext
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

    /// Cap dropped 100 -> 25 (owner decision): unsolicited bulk messaging
    /// is the category's main harassment vector, and 25 keeps the
    /// feature's point with a fraction of the harm.
    static let bulkCap = 25

    /// One composed message to the next N (<= bulkCap) people. Guardrails:
    /// an earned booster is consumed, one send per 24h, celebrations are
    /// suppressed, no fake replies, and rewind is cleared (undoing bulk
    /// rows isn't supported).
    private func performBulkSend() {
        let text = opener.trimmingCharacters(in: .whitespaces)
        let targets = Array(remaining.prefix(Self.bulkCap))
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

                // A SENT LIKE per recipient (deduped) — bulk sends are
                // one-way, so they must never mint Match rows; the
                // matches folder is mutual-only now.
                let profileID = profile.id
                let likeDescriptor = FetchDescriptor<SentLike>(
                    predicate: #Predicate { $0.profile?.id == profileID }
                )
                if ((try? context.fetchCount(likeDescriptor)) ?? 0) == 0 {
                    context.insert(SentLike(profile: profile))
                }

                if index % 10 == 9 {
                    bulkProgress = Double(index + 1) / Double(targets.count)
                    // Let the progress bar actually render.
                    await Task.yield()
                }
            }

            // One save at the end; the deck swap happens in a single
            // animations-disabled transaction.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                let alreadySwiped = swipedIDs
                for profile in targets where !alreadySwiped.contains(profile.id) {
                    context.insert(SwipeDecision(profileID: profile.id, liked: true))
                }
            }
            try? context.save()
            rewindStack = []  // Undoing bulk rows isn't supported.

            bulkProgress = 1
            bulkSentCount = targets.count
            Haptics.notify(.success)
        }
    }

    // MARK: - Swipe data commit

    /// Runs the moment a swipe starts animating. Creates the Match (deduped
    /// — "start over" must not re-create rows), records the rewind entry,
    /// and decides on the celebration.
    ///
    /// The haptic fires immediately; the SwiftData work (fetch + save on
    /// the main thread) is deferred one runloop turn so the fly-off's
    /// first frames render before any disk I/O — committing synchronously
    /// at gesture release was a visible hitch. The fly-off runs ~0.4s, so
    /// the deferred work always lands before finishSwipe reads
    /// celebrationPending.
    private func commitData(profile: UserProfile, liked: Bool) {
        Haptics.impact(liked ? .medium : .light)
        let context0 = pendingContext
        pendingContext = nil

        Task { @MainActor in
            await Task.yield()
            commitDataDeferred(profile: profile, liked: liked, context0: context0)
        }
    }

    private func commitDataDeferred(profile: UserProfile, liked: Bool, context0: SwipeContext?) {
        var createdMatch: Match?
        var createdSentLike: SentLike?
        if liked {
            let profileID = profile.id

            // Every like is recorded honestly as a SentLike (deduped —
            // "start over" must not re-create rows).
            let existingLike = FetchDescriptor<SentLike>(
                predicate: #Predicate { $0.profile?.id == profileID }
            )
            if ((try? context.fetchCount(existingLike)) ?? 0) == 0 {
                let like = SentLike(profile: profile, isSuperLike: context0?.isSuper ?? false)
                context.insert(like)
                createdSentLike = like
            }

            // A Match exists ONLY when it's mutual — the matches folder
            // used to show every one-way like as "it clicked".
            let mutual = Boost.likesYouBack(profile, boosted: me?.isBoosted ?? false)
            if mutual {
                let existingMatch = FetchDescriptor<Match>(
                    predicate: #Predicate { $0.profile?.id == profileID }
                )
                if ((try? context.fetchCount(existingMatch)) ?? 0) == 0 {
                    let match = Match(profile: profile, isSuperChat: context0?.isSuper ?? false)
                    context.insert(match)
                    createdMatch = match
                }

                // A mutual like creates the conversation, so the match
                // exists in chats — the celebration used to lead nowhere.
                if context0?.conversation == nil,
                   !conversations.contains(where: { $0.participant?.id == profile.id }) {
                    context.insert(Conversation(participant: profile, folder: .messages))
                }
            }
            try? context.save()
        }

        rewindStack.append(RewindEntry(
            profileID: profile.id,
            match: createdMatch,
            sentLike: createdSentLike,
            createdConversation: (context0?.createdConversation == true) ? context0?.conversation : nil,
            addedMessage: (context0?.createdConversation == false) ? context0?.openerMessage : nil
        ))

        // Celebrate only when a match was actually created — re-swiping
        // someone already matched must not re-celebrate.
        if createdMatch != nil {
            celebrationPending = profile
        } else if context0?.conversation != nil {
            // Suppress the toast when a celebration will cover it anyway.
            showToast("sent to \(profile.name.split(separator: " ").first.map(String.init) ?? profile.name)")
        }
    }

    /// Runs when the fly-off animation completes.
    private func finishSwipe(profile: UserProfile, liked: Bool) {
        withAnimation(motion.state) {
            if !swipedIDs.contains(profile.id) {
                context.insert(SwipeDecision(profileID: profile.id, liked: liked))
            }
        }
        try? context.save()
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
            let profileID = entry.profileID
            for decision in decisions where decision.profileID == profileID {
                context.delete(decision)
            }
        }
        if let match = entry.match {
            context.delete(match)
        }
        if let sentLike = entry.sentLike {
            context.delete(sentLike)
        }
        if let conversation = entry.createdConversation {
            // Only a thread THIS swipe created cascades away.
            context.delete(conversation)
        } else if let message = entry.addedMessage {
            // Pre-existing thread: delete just the opener — rewinding
            // used to cascade-delete a week of history (MEGA-BRIEF 0.4).
            context.delete(message)
        }
        try? context.save()
    }

    private func reset() {
        withAnimation(motion.state) {
            for decision in decisions {
                context.delete(decision)
            }
        }
        try? context.save()
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
    let sentLike: SentLike?
    /// Only set when THIS swipe created the thread — rewinding must
    /// never cascade-delete a pre-existing conversation's history.
    let createdConversation: Conversation?
    /// The single opener message added to a PRE-EXISTING thread; rewind
    /// deletes just this row (MEGA-BRIEF 0.4).
    let addedMessage: Message?
}

private struct SwipeContext {
    let conversation: Conversation?
    /// True when the opener created the thread (vs reusing one).
    let createdConversation: Bool
    let openerMessage: Message?
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
