//
//  FloatingTabBar.swift
//  Click
//
//  Black capsule detached from the screen edges. The active tab expands to
//  show its label; inactive tabs are icon-only.
//

import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case chats
    case swipe
    case profile

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .chats: "chats"
        case .swipe: "swipe"
        case .profile: "profile"
        }
    }

    var icon: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right.fill"
        case .swipe: "rectangle.on.rectangle.angled.fill"
        case .profile: "person.fill"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    /// Unread counts keyed by tab. Missing or zero means no badge.
    var badges: [AppTab: Int] = [:]

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(6)
        .background(Theme.primary, in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        let badge = badges[tab] ?? 0

        Button {
            guard selection != tab else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 26, height: 26)

                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .contentTransition(.numericText())
                            .animation(.snappy, value: badge)
                            .font(.clickPlain(.caption2, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                            .offset(x: 10, y: -6)
                    }
                }

                if isSelected {
                    // No .fixedSize() here: at accessibility text sizes it
                    // pushed the capsule wider than the window and clipped
                    // every screen (the FolderTabs bug, same pattern).
                    Text(tab.label)
                        .font(.click(.subheadline, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                }
            }
            .foregroundStyle(isSelected ? Theme.onPrimary : Theme.onPrimary.opacity(0.55))
            .padding(.horizontal, isSelected ? 18 : 14)
            .padding(.vertical, 12)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.onPrimary.opacity(0.14))
                        .matchedGeometryEffect(id: "activePill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityValue(badge > 0 ? "\(badge) unread" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    @Previewable @State var selection: AppTab = .chats

    return ZStack(alignment: .bottom) {
        Theme.background.ignoresSafeArea()
        FloatingTabBar(selection: $selection, badges: [.profile: 2])
    }
}
