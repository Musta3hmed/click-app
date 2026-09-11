//
//  SwipeView.swift
//  Click
//
//  Card deck. The top card follows the drag with rotation proportional to
//  horizontal travel; past the threshold it arcs off and fades, and the
//  next card scales up to meet it. The deck is filtered by the signed-in
//  user's "who I want to meet" answer. Blocked profiles never enter it.
//
//  Layout note: no ScrollView here — the card's drag gesture would fight
//  the scroll pan and make everything below the card unreachable. Instead
//  the card flexes into whatever height remains after the action row and
//  composer, capped to a 0.72 aspect, so an iPhone SE fits everything.
//
//  Deck state is keyed by profile ID, not index — blocking the top card
//  removes it from the filtered query mid-session, and integer indexes
//  silently aliased onto the wrong person.
//

import SwiftUI
import SwiftData

struct SwipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(
        filter: #Predicate<UserProfile> { !$0.isCurrentUser && !$0.isBlocked },
        sort: \UserProfile.createdAt
    )
    private var candidates: [UserProfile]

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    /// IDs the user has swiped this session, in order.
    @State private var swipedIDs: [UUID] = []
    /// Rows created by the most recent like, so rewind can undo them.
    @State private var lastLikeMatch: Match?
    @State private var lastLikeConversation: Conversation?
    @State private var drag: CGSize = .zero
    @State private var flyingAway = false
    @State private var opener = ""
    @State private var toast: String?
    @State private var celebrating: UserProfile?
    @State private var likeBounce = 0
    @State private var passBounce = 0
    @FocusState private var composerFocused: Bool

    /// Horizontal travel, in points, that commits a swipe.
    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            TexturedHeader(title: "swipe", texture: .clouds) {
                GlassCapsule {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.white)
                    Text("filters")
                        .font(.click(.footnote, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .font(.system(size: 14, weight: .bold))
            }

            OverlappingSheet {
                VStack(spacing: 14) {
                    cardArea
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
    }

    // MARK: - Deck state

    /// Deck after the seeking filter. Profiles with no/undisclosed gender
    /// only appear for users open to everyone.
    private var deck: [UserProfile] {
        let seeking = currentUsers.first?.seeking ?? []
        guard !seeking.isEmpty, !seeking.contains(.everyone) else { return candidates }
        return candidates.filter { profile in
            guard let gender = profile.gender else { return false }
            return seeking.contains { $0.includes(gender) }
        }
    }

    private var remaining: [UserProfile] {
        deck.filter { !swipedIDs.contains($0.id) }
    }

    private var dragProgress: CGFloat {
        min(1, abs(drag.width) / threshold)
    }

    // MARK: - Cards

    private var cardArea: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width, geo.size.height * 0.72)
            let cardHeight = min(geo.size.height, cardWidth / 0.72)

            ZStack {
                if remaining.isEmpty {
                    DeckExhaustedState { reset() }
                } else {
                    // Render back-to-front so the current card sits on top.
                    ForEach(Array(remaining.prefix(3).enumerated()).reversed(), id: \.element.id) { offset, profile in
                        SwipeCard(profile: profile)
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
                            .gesture(offset == 0 ? dragGesture : nil)
                            .allowsHitTesting(offset == 0)
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
                .scaleEffect(drag.width > 0 ? 0.5 + 0.5 * dragProgress : 0.5)
                .rotationEffect(.degrees(drag.width > 0 ? Double(-6 * (1 - dragProgress)) : 0))
            stamp(text: "NOPE", color: Theme.accent, baseRotation: 14)
                .opacity(Double(max(0, -drag.width) / threshold))
                .scaleEffect(drag.width < 0 ? 0.5 + 0.5 * dragProgress : 0.5)
                .rotationEffect(.degrees(drag.width < 0 ? Double(6 * (1 - dragProgress)) : 0))
        }
        .allowsHitTesting(false)
    }

    private func stamp(text: String, color: Color, baseRotation: Double) -> some View {
        Text(text)
            .font(.click(.largeTitle, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                if value.translation.width > threshold {
                    commit(liked: true)
                } else if value.translation.width < -threshold {
                    commit(liked: false)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        drag = .zero
                    }
                }
            }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 16) {
            circleButton("arrow.uturn.backward", tint: Theme.coin, label: "Rewind", size: 46, bounce: 0) {
                rewind()
            }
            .disabled(swipedIDs.isEmpty)
            .opacity(swipedIDs.isEmpty ? 0.4 : 1)

            circleButton("xmark", tint: Theme.accent, label: "Pass", size: 58, bounce: passBounce) {
                passBounce += 1
                commit(liked: false)
            }

            circleButton("heart.fill", tint: Theme.online, label: "Like", size: 58, bounce: likeBounce) {
                likeBounce += 1
                commit(liked: true)
            }

            circleButton("bolt.fill", tint: Theme.brandViolet, label: "Super chat", size: 46, bounce: 0) {
                commit(liked: true, isSuper: true)
            }
        }
        .disabled(remaining.isEmpty)
        .opacity(remaining.isEmpty ? 0.4 : 1)
    }

    private func circleButton(
        _ systemImage: String,
        tint: Color,
        label: String,
        size: CGFloat,
        bounce: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .heavy))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: bounce)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.glowStroke, lineWidth: 1))
                .shadow(color: Theme.shadowColor, radius: 8, y: 4)
        }
        .buttonStyle(.click)
        .accessibilityLabel(label)
    }

    // MARK: - Composer

    /// Send an opener with the like — creates the match AND the conversation
    /// in one action. Empty field = the heart button is a plain like.
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
        guard canSendOpener, let profile = remaining.first else { return }
        let text = opener.trimmingCharacters(in: .whitespaces)
        opener = ""
        composerFocused = false

        let conversation = Conversation(participant: profile, folder: .messages)
        context.insert(conversation)
        context.insert(Message(text: text, isFromMe: true, conversation: conversation))

        showToast("sent to \(profile.name.split(separator: " ").first.map(String.init) ?? profile.name)")
        commit(liked: true, conversation: conversation)
    }

    // MARK: - Swipe commit

    private func commit(liked: Bool, isSuper: Bool = false, conversation: Conversation? = nil) {
        guard let profile = remaining.first, !flyingAway else { return }

        Haptics.impact(liked ? .medium : .light)

        // Arc-and-fade fly-off. flyingAway drives the fade, so it must be
        // mutated INSIDE the animation or the card blinks out on frame one.
        // Reduce Motion gets a pure cross-fade, not a faster slide.
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.32)) {
            if !reduceMotion {
                drag = CGSize(width: liked ? 640 : -640, height: -180)
            }
            flyingAway = true
        }

        var createdMatch: Match?
        if liked {
            let match = Match(profile: profile, isSuperChat: isSuper)
            context.insert(match)
            createdMatch = match
            try? context.save()
        }

        lastLikeMatch = createdMatch
        lastLikeConversation = conversation
        let mutual = liked && Self.likesYouBack(profile)

        // Let the fly-off play, then swap cards with animations OFF so the
        // incoming card does not inherit drag = 640 and spring in from
        // off-screen (FINDINGS §42).
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.16 : 0.32)) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                swipedIDs.append(profile.id)
                drag = .zero
                flyingAway = false
            }
            if mutual {
                if reduceMotion {
                    celebrating = profile
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        celebrating = profile
                    }
                }
            }
        }
    }

    /// Mock mutuality until a backend exists: stable per profile.
    private static func likesYouBack(_ profile: UserProfile) -> Bool {
        Theme.stableHash(profile.name) % 2 == 0
    }

    /// Undo the last swipe — including the Match (and any opener
    /// conversation) it created, so no phantom chat survives.
    private func rewind() {
        guard !swipedIDs.isEmpty else { return }
        Haptics.impact(.light)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            _ = swipedIDs.removeLast()
        }
        if let match = lastLikeMatch {
            context.delete(match)
        }
        if let conversation = lastLikeConversation {
            context.delete(conversation)  // Messages cascade.
        }
        lastLikeMatch = nil
        lastLikeConversation = nil
        try? context.save()
    }

    private func reset() {
        withAnimation {
            swipedIDs = []
        }
        lastLikeMatch = nil
        lastLikeConversation = nil
    }

    // MARK: - Toast & celebration

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.25)) {
                if toast == text { toast = nil }
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Label(toast, systemImage: "paperplane.fill")
                .font(.click(.subheadline, weight: .bold))
                .foregroundStyle(Theme.onPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Theme.primary, in: Capsule())
                .padding(.bottom, Theme.Metric.tabBarClearance + 8)
                .transition(
                    reduceMotion
                        ? AnyTransition.opacity
                        : AnyTransition.move(edge: .bottom).combined(with: .opacity)
                )
                .accessibilityLabel(toast)
        }
    }

    @ViewBuilder
    private var celebrationOverlay: some View {
        if let profile = celebrating {
            MatchCelebrationView(
                profile: profile,
                myName: currentUsers.first?.name ?? "you"
            ) {
                withAnimation(.easeOut(duration: 0.25)) {
                    celebrating = nil
                }
            }
            .transition(
                reduceMotion
                    ? AnyTransition.opacity
                    : AnyTransition.opacity.combined(with: .scale(scale: 1.08))
            )
        }
    }
}

// MARK: - Match celebration

private struct MatchCelebrationView: View {
    let profile: UserProfile
    let myName: String
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ZStack {
            // Opaque: at 0.96 four percent of the dark app bled through.
            Theme.brandGradient
                .ignoresSafeArea()

            if !reduceMotion {
                ConfettiView()
            }

            VStack(spacing: 24) {
                Spacer()

                HStack(spacing: -18) {
                    StickerAvatar(name: myName, size: 110)
                        .rotationEffect(.degrees(-8))
                        .scaleEffect(entranceScale(from: 0.2))
                    StickerAvatar(name: profile.name, size: 110)
                        .rotationEffect(.degrees(8))
                        .scaleEffect(entranceScale(from: 0.2))
                }

                Text("IT CLICKED!")
                    .font(.system(.largeTitle, design: .rounded).weight(.black).italic())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .scaleEffect(entranceScale(from: 0.6))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)

                Text("\(profile.name.split(separator: " ").first.map(String.init) ?? profile.name) likes you too")
                    .font(.clickPlain(.headline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

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
                .accessibilityLabel("Keep swiping")
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.55, dampingFraction: 0.6).delay(0.1)
            ) {
                appeared = true
            }
            headingFocused = true
        }
        // A full-screen takeover: VoiceOver must not walk into the deck
        // behind it.
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("It's a match with \(profile.name)")
    }

    /// Reduce Motion: fade in place instead of zooming in.
    private func entranceScale(from start: CGFloat) -> CGFloat {
        if reduceMotion { return 1 }
        return appeared ? 1 : start
    }
}

// MARK: - Card

private struct SwipeCard: View {
    let profile: UserProfile

    @State private var photoIndex = 0
    /// Decoded once per card — decoding JPEGs inside a computed property ran
    /// on every drag frame once real photos existed.
    @State private var photos: [UIImage] = []

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
                .background(.ultraThinMaterial, in: Circle())
                .padding(.top, photos.count > 1 ? 18 : 0)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous))
        // Edge stroke keeps the card's silhouette readable on OLED.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous)
                .strokeBorder(Theme.glowStroke, lineWidth: 1)
        )
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
            .foregroundStyle(.white)

            Text(profile.bio)
                .font(.clickPlain(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            HStack(spacing: 6) {
                CountryBadge(code: profile.countryCode, onDark: true)
                Text(profile.zodiac.label)
                    .font(.clickPlain(.caption, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                ForEach(profile.interests.prefix(3), id: \.self) { interest in
                    Text(interest)
                        .font(.clickPlain(.caption, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.22)))
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

    /// Instagram-stories style segments across the top of the card. Also the
    /// VoiceOver handle for paging: `.contain` on the card means adjustable
    /// actions must live on a real element, so they live here.
    private var photoProgress: some View {
        HStack(spacing: 4) {
            ForEach(photos.indices, id: \.self) { index in
                Capsule()
                    .fill(index == photoIndex ? .white : .white.opacity(0.35))
                    .frame(height: 3)
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
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func page(_ delta: Int) {
        let next = photoIndex + delta
        guard photos.indices.contains(next) else { return }
        Haptics.selection()
        withAnimation(.easeInOut(duration: 0.15)) {
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
            Text("check back later for new people near you.")
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
