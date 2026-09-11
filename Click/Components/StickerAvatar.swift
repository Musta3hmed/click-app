//
//  StickerAvatar.swift
//  Click
//
//  Cut-out style avatar with a thick white outline and drop shadow.
//
//  There are no photo assets in the project, so avatars render as initials
//  on a deterministic gradient derived from the name. Swap `avatarBody` for
//  an AsyncImage once real photos exist.
//

import SwiftUI

struct StickerAvatar: View {
    let name: String
    var size: CGFloat = 64
    var badgeNumber: Int? = nil
    var isVerified: Bool = false
    var isOnline: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            avatarBody
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: size * 0.06))
                .shadow(color: .black.opacity(0.18), radius: size * 0.12, y: size * 0.05)

            if badgeNumber != nil || isVerified {
                badgeRow
                    .offset(y: size * 0.10)
            }

            if isOnline {
                Circle()
                    .fill(Theme.online)
                    .frame(width: size * 0.20, height: size * 0.20)
                    .overlay(Circle().strokeBorder(.white, lineWidth: size * 0.045))
                    .offset(x: size * 0.36, y: -size * 0.06)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var avatarBody: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Text(initials)
                .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                .italic()
                .foregroundStyle(.white)
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 3) {
            if let badgeNumber {
                Text("\(badgeNumber)")
                    .font(.system(size: size * 0.20, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundStyle(Theme.primary)
            }
            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size * 0.20, weight: .bold))
                    .foregroundStyle(Theme.verified)
            }
        }
        .padding(.horizontal, size * 0.08)
        .padding(.vertical, size * 0.02)
        .background(Capsule().fill(Theme.surface))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private var accessibilityText: String {
        var parts = [name]
        if isVerified { parts.append("verified") }
        if isOnline { parts.append("online") }
        return parts.joined(separator: ", ")
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// Deterministic colour pair so a given name always looks the same.
    private var gradientColors: [Color] {
        Theme.gradient(for: name, in: Theme.avatarGradients)
    }
}

#Preview {
    VStack(spacing: 28) {
        StickerAvatar(name: "Maya Chen", size: 56, isOnline: true)
        StickerAvatar(name: "Jordan Ellis", size: 120, badgeNumber: 7, isVerified: true)
        StickerAvatar(name: "Sam", size: 44)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.background)
}
