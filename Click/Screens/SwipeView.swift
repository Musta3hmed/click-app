//
//  SwipeView.swift
//  Click
//
//  Card deck. The top card follows the drag with rotation proportional to
//  horizontal travel; past the threshold it arcs off and fades, and the
//  next card scales up to meet it. The deck is filtered by the signed-in
//  user's "who I want to meet" answer. Blocked profiles never enter it.
//

import SwiftUI
import SwiftData

struct SwipeView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<UserProfile> { !$0.isCurrentUser && !$0.isBlocked },
        sort: \UserProfile.createdAt
    )
    private var candidates: [UserProfile]

    @Query(filter: #Predicate<UserProfile> { $0.isCurrentUser })
    private var currentUsers: [UserProfile]

    @State private var topIndex = 0
    @State private var drag: CGSize = .zero
    @State private var flyingAway = false
    @State private var lastSwipedIndex: Int?
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
                .padding(.top, 20)
                .padding(.bottom, Theme.Metric.tabBarClearance)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .ignoresSafeArea(edges: .top)
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
        guard topIndex < deck.count else { return [] }
        return Array(deck[topIndex...])
    }

    private var dragProgress: CGFloat {
        min(1, abs(drag.width) / threshold)
    }

    // MARK: - Cards

    private var cardArea: some View {
        ZStack {
            if remaining.isEmpty {
                DeckExhaustedState { reset() }
            } else {
                // Render back-to-front so the current card sits on top.
                ForEach(Array(remaining.prefix(3).enumerated()).reversed(), id: \.element.id) { offset, profile in
                    SwipeCard(profile: profile)
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
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: drag)
                        .allowsHitTesting(offset == 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 440)
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
            .font(.system(size: 38, weight: .black, design: .rounded))
            .italic()
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
            .disabled(lastSwipedIndex == nil)
            .opacity(lastSwipedIndex == nil ? 0.4 : 1)

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
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
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
                    .background(canSendOpener ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.separator), in: Circle())
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
        commit(liked: true)
    }

    // MARK: - Swipe commit

    private func commit(liked: Bool, isSuper: Bool = false) {
        guard let profile = remaining.first, !flyingAway else { return }

        Haptics.impact(liked ? .medium : .light)

        // Arc-and-fade fly-off: out horizontally, up, extra rotation, fade.
        flyingAway = true
        withAnimation(.easeOut(duration: 0.32)) {
            drag = CGSize(width: liked ? 640 : -640, height: -180)
        }

        if liked {
            let match = Match(profile: profile, isSuperChat: isSuper)
            context.insert(match)
            try? context.save()
        }

        lastSwipedIndex = topIndex
        let mutual = liked && Self.likesYouBack(profile)

        // Let the fly-off play before the next card becomes active.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            topIndex += 1
            drag = .zero
            flyingAway = false
            if mutual {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    celebrating = profile
                }
            }
        }
    }

    /// Mock mutuality until a backend exists: stable per profile.
    private static func likesYouBack(_ profile: UserProfile) -> Bool {
        let hash = abs(profile.name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) })
        return hash % 2 == 0
    }

    private func rewind() {
        guard let last = lastSwipedIndex else { return }
        Haptics.impact(.light)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            topIndex = last
        }
        lastSwipedIndex = nil
    }

    private func reset() {
        withAnimation {
            topIndex = 0
            lastSwipedIndex = nil
        }
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
            .transition(.opacity.combined(with: .scale(scale: 1.08)))
        }
    }
}

// MARK: - Match celebration

private struct MatchCelebrationView: View {
    let profile: UserProfile
    let myName: String
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.brandGradient
                .ignoresSafeArea()
                .opacity(0.96)

            ConfettiView()

            VStack(spacing: 24) {
                Spacer()

                HStack(spacing: -18) {
                    StickerAvatar(name: myName, size: 110)
                        .rotationEffect(.degrees(-8))
                        .scaleEffect(appeared ? 1 : 0.2)
                    StickerAvatar(name: profile.name, size: 110)
                        .rotationEffect(.degrees(8))
                        .scaleEffect(appeared ? 1 : 0.2)
                }

                Text("IT CLICKED!")
                    .font(.system(size: 44, design: .rounded).weight(.black).italic())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .scaleEffect(appeared ? 1 : 0.6)

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
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.1)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("It's a match with \(profile.name)")
    }
}

// MARK: - Card

private struct SwipeCard: View {
    let profile: UserProfile

    @State private var photoIndex = 0

    private var photos: [UIImage] {
        profile.orderedPhotos.compactMap { UIImage(data: $0.data) }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background

            // Bottom scrim so the text always reads over a photo.
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )

            infoBlock

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
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .padding(.top, photos.count > 1 ? 18 : 0)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        // Tap left/right thirds to page photos, stories-style.
        .overlay {
            if photos.count > 1 {
                HStack(spacing: 0) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { page(-1) }
                    Rectangle().fill(.clear)
                        .allowsHitTesting(false)
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { page(1) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.displayAge). \(profile.bio)")
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
        } else {
            // No photos yet (all seeded profiles): keep the gradient look.
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
                Text(profile.countryFlag)
                Text(profile.zodiac.symbol)
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
    }

    /// Instagram-stories style segments across the top of the card.
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
        .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SwipeView()
        .modelContainer(MockData.previewContainer)
}
