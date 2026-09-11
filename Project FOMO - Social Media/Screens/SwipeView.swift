//
//  SwipeView.swift
//  Click
//
//  Card deck. The top card follows the drag with rotation proportional to
//  horizontal travel; past the threshold it flies off, otherwise it springs
//  back. Blocked profiles never enter the deck.
//

import SwiftUI
import SwiftData

struct SwipeView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<UserProfile> { !$0.isCurrentUser && !$0.isBlocked },
        sort: \UserProfile.createdAt
    )
    private var deck: [UserProfile]

    @State private var topIndex = 0
    @State private var drag: CGSize = .zero
    @State private var lastSwipedIndex: Int?

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
                VStack(spacing: 18) {
                    cardArea
                    actionRow
                }
                .padding(.top, 20)
                .padding(.bottom, Theme.Metric.tabBarClearance)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .ignoresSafeArea(edges: .top)
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
                        .scaleEffect(1 - CGFloat(offset) * 0.04)
                        .offset(y: CGFloat(offset) * 12)
                        .rotationEffect(offset == 0 ? .degrees(Double(drag.width / 18)) : .zero)
                        .offset(offset == 0 ? drag : .zero)
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
        .frame(height: 460)
        .padding(.horizontal, Theme.Metric.gutter)
    }

    private var decisionOverlay: some View {
        ZStack {
            stamp(text: "LIKE", color: Theme.online, rotation: -14)
                .opacity(Double(max(0, drag.width) / threshold))
            stamp(text: "NOPE", color: Theme.accent, rotation: 14)
                .opacity(Double(max(0, -drag.width) / threshold))
        }
        .allowsHitTesting(false)
    }

    private func stamp(text: String, color: Color, rotation: Double) -> some View {
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
            .rotationEffect(.degrees(rotation))
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
            circleButton("arrow.uturn.backward", tint: Theme.coin, label: "Rewind", size: 48) {
                rewind()
            }
            .disabled(lastSwipedIndex == nil)
            .opacity(lastSwipedIndex == nil ? 0.4 : 1)

            circleButton("xmark", tint: Theme.accent, label: "Pass", size: 62) {
                commit(liked: false)
            }

            circleButton("heart.fill", tint: Theme.online, label: "Like", size: 62) {
                commit(liked: true)
            }

            circleButton("bolt.fill", tint: Color(hex: 0xA855F7), label: "Super chat", size: 48) {
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.surface))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Deck state

    private var remaining: [UserProfile] {
        guard topIndex < deck.count else { return [] }
        return Array(deck[topIndex...])
    }

    private func commit(liked: Bool, isSuper: Bool = false) {
        guard let profile = remaining.first else { return }

        Haptics.impact(liked ? .medium : .light)

        withAnimation(.easeOut(duration: 0.28)) {
            drag = CGSize(width: liked ? 700 : -700, height: -60)
        }

        if liked {
            let match = Match(profile: profile, isSuperChat: isSuper)
            context.insert(match)
            try? context.save()
        }

        lastSwipedIndex = topIndex

        // Let the fly-off animation play before the next card becomes active.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            topIndex += 1
            drag = .zero
        }
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
}

// MARK: - Card

private struct SwipeCard: View {
    let profile: UserProfile

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Scrim so text stays readable over the gradient.
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.click(.title, weight: .heavy))
                    Text("\(profile.age)")
                        .font(.click(.title2, weight: .bold))
                        .opacity(0.9)
                    if profile.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color(hex: 0x60C6FF))
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

            if profile.isOnline {
                HStack(spacing: 6) {
                    Circle().fill(Theme.online).frame(width: 8, height: 8)
                    Text("online")
                        .font(.click(.caption, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            SafetyMenu(profile: profile)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.card, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.age). \(profile.bio)")
    }

    private var gradientColors: [Color] {
        let palette: [(UInt32, UInt32)] = [
            (0x3BB8F5, 0x1E6FA8), (0xFF6B8A, 0xC2255C), (0x845EF7, 0x4C2FA8),
            (0xFFA94D, 0xE8590C), (0x20C997, 0x0C8A6A), (0x4DABF7, 0x1864AB)
        ]
        let hash = abs(profile.name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) })
        let pair = palette[hash % palette.count]
        return [Color(hex: pair.0), Color(hex: pair.1)]
    }
}

// MARK: - Empty deck

private struct DeckExhaustedState: View {
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("🎉")
                .font(.system(size: 60))
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
    }
}

#Preview {
    SwipeView()
        .modelContainer(MockData.previewContainer)
}
