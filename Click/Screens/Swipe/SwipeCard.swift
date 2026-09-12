//
//  SwipeCard.swift
//  Click
//
//  One profile card: full-bleed photo with stories-style paging, scrim,
//  name/bio/interest chips, online pill and safety menu.
//

import SwiftUI

struct SwipeCard: View {
    let profile: UserProfile
    /// The viewer's own profile — shared-interest chips need both sides.
    var viewer: UserProfile? = nil

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

            // The first answered prompt — identity the bio alone can't
            // carry. One on the card keeps it readable; the rest show in
            // the profile preview/editor.
            if let entry = profile.promptAnswers.first, let prompt = entry.prompt {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.question)
                        .font(.clickPlain(.caption2, weight: .bold))
                        .foregroundStyle(Theme.onImageSecondary)
                    Text(entry.answer)
                        .font(.clickPlain(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.onImagePrimary)
                        .lineLimit(2)
                }
            }

            if let line = InterestMatching.sharedLine(viewer, profile) {
                Text(line)
                    .font(.clickPlain(.caption, weight: .bold))
                    .foregroundStyle(Theme.onImagePrimary)
            }

            HStack(spacing: 6) {
                CountryBadge(code: profile.countryCode, onDark: true)
                Text(profile.zodiac.label)
                    .font(.clickPlain(.caption, weight: .semibold))
                    .foregroundStyle(Theme.onImageSecondary)
                // Shared interests first, then the rest, capped at 3.
                ForEach(orderedChipIDs, id: \.self) { id in
                    let isShared = sharedIDs.contains(id)
                    HStack(spacing: 4) {
                        if isShared, let symbol = InterestCatalog.symbolName(for: id) {
                            Image(systemName: symbol)
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(InterestCatalog.label(for: id))
                            .font(.clickPlain(.caption, weight: .semibold))
                    }
                    .foregroundStyle(Theme.onImagePrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(isShared ? Theme.onImageFillStrong : Theme.onImageFill))
                }
            }
        }
        .padding(20)
        // One merged element: without this, VoiceOver read every text twice
        // (once via children, once via a container label).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel)
    }

    /// Shared interests first, then the rest, capped at what the card shows.
    private var orderedChipIDs: [String] {
        let shared = profile.interests.filter { sharedIDs.contains($0) }
        let rest = profile.interests.filter { !sharedIDs.contains($0) }
        return Array((shared + rest).prefix(InterestCatalog.shownOnCard))
    }

    private var sharedIDs: Set<String> {
        Set(InterestMatching.shared(viewer, profile).map(\.id))
    }

    private var cardAccessibilityLabel: String {
        var label = "\(profile.name), \(profile.displayAge). \(profile.bio). "
        if profile.isVerified { label += "Verified. " }
        if let entry = profile.promptAnswers.first, let prompt = entry.prompt {
            label += "\(prompt.question): \(entry.answer). "
        }
        let sharedLabels = InterestMatching.shared(viewer, profile).map(\.label)
        if !sharedLabels.isEmpty {
            label += "\(sharedLabels.count) shared interest\(sharedLabels.count == 1 ? "" : "s"): \(sharedLabels.joined(separator: ", ")). "
        }
        let others = orderedChipIDs.filter { !sharedIDs.contains($0) }.map { InterestCatalog.label(for: $0) }
        if !others.isEmpty {
            label += "Interests: \(others.joined(separator: ", "))"
        }
        return label
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
