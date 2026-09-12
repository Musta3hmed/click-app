//
//  TexturedHeader.swift
//  Click
//
//  Warm brand-gradient header with a soft procedural texture, a large
//  lowercase italic title, and a trailing glass capsule of actions.
//
//  The textures are drawn procedurally because the project ships with no
//  photo assets. To swap in real artwork, replace the `Canvas` inside
//  `CloudTexture` / `WaterTexture` with an `Image(...).resizable()`.
//

import SwiftUI

enum HeaderTexture {
    case clouds
    case water
}

/// Geometry of the scroll-driven header collapse (M137). Non-generic so
/// call sites don't have to specialise `TexturedHeader` to reach it.
enum HeaderCollapse {
    static let expandedHeight: CGFloat = 148
    static let collapsedHeight: CGFloat = 92
    /// The scroll distance that maps onto a full collapse.
    static var distance: CGFloat { expandedHeight - collapsedHeight }
}

struct TexturedHeader<Trailing: View>: View {
    let title: String
    var texture: HeaderTexture = .clouds
    /// Scroll-driven collapse, 0 (expanded, 148pt) → 1 (collapsed, 92pt).
    /// Driven 1:1 by the finger via `onScrollGeometryChange` — never
    /// wrapped in `withAnimation`, and guarded below so no implicit
    /// animation can smooth it into lag.
    var collapseProgress: CGFloat = 0
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        // The usable band is a fixed 148pt BELOW the safe area, so the
        // header reads the same on an SE (small inset) and a Pro Max
        // (Dynamic Island) instead of being squashed by the bigger inset.
        HStack(alignment: .center) {
            Text(title)
                .font(.click(.largeTitle, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                // 1 → 0.66, pinned to its baseline corner so the title
                // shrinks in place instead of drifting.
                .scaleEffect(1 - 0.34 * collapseProgress, anchor: .bottomLeading)

            Spacer(minLength: Theme.Metric.gutter)

            trailing()
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.bottom, Theme.Metric.sheetOverlap + 12)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .frame(
            height: HeaderCollapse.expandedHeight - HeaderCollapse.distance * collapseProgress,
            alignment: .bottom
        )
        .background {
            ZStack {
                Theme.headerGradient
                // Static content, frozen into one raster so it stops
                // re-compositing at 120Hz during drags on the sheet below.
                Group {
                    switch texture {
                    case .clouds: CloudTexture()
                    case .water: WaterTexture()
                    }
                }
                .drawingGroup()
                // Parallax at half the collapse rate.
                .offset(y: -HeaderCollapse.distance * collapseProgress * 0.5)
            }
            .ignoresSafeArea(edges: .top)
        }
        // Scroll-driven values are 1:1 with the finger: strip any implicit
        // animation whenever the progress changes (and only then, so the
        // trailing content keeps its own transitions).
        .transaction(value: collapseProgress) { $0.animation = nil }
    }
}

extension TexturedHeader where Trailing == EmptyView {
    init(title: String, texture: HeaderTexture = .clouds) {
        self.init(title: title, texture: texture, trailing: { EmptyView() })
    }
}

// MARK: - Textures

/// Soft overlapping blobs, heavily blurred, reading as cloud cover.
private struct CloudTexture: View {
    var body: some View {
        Canvas { context, size in
            // Normalised (x, y, radius) blobs — stable, not random, so the
            // header looks identical across launches.
            let blobs: [(CGFloat, CGFloat, CGFloat)] = [
                (0.08, 0.22, 0.20), (0.26, 0.12, 0.16), (0.44, 0.28, 0.22),
                (0.62, 0.10, 0.15), (0.78, 0.26, 0.19), (0.94, 0.14, 0.17),
                (0.16, 0.62, 0.18), (0.52, 0.70, 0.20), (0.86, 0.64, 0.16)
            ]

            for (nx, ny, nr) in blobs {
                let r = nr * size.width
                let rect = CGRect(
                    x: nx * size.width - r,
                    y: ny * size.height - r * 0.55,
                    width: r * 2,
                    height: r * 1.1
                )
                context.fill(Ellipse().path(in: rect), with: .color(.white.opacity(0.45)))
            }
        }
        .blur(radius: 22)
        .blendMode(.softLight)
        .allowsHitTesting(false)
    }
}

/// Horizontal sine bands reading as rippling pool water.
private struct WaterTexture: View {
    var body: some View {
        Canvas { context, size in
            let lineCount = 16
            for index in 0..<lineCount {
                let baseY = size.height * CGFloat(index) / CGFloat(lineCount)
                let phase = CGFloat(index) * 0.8
                var path = Path()
                path.move(to: CGPoint(x: 0, y: baseY))

                var x: CGFloat = 0
                while x <= size.width {
                    let y = baseY + sin(x / 24.0 + phase) * 4.5
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 5
                }

                context.stroke(
                    path,
                    with: .color(.white.opacity(0.22)),
                    lineWidth: 2.5
                )
            }
        }
        .blur(radius: 1.5)
        .blendMode(.softLight)
        .allowsHitTesting(false)
    }
}

// MARK: - Glass capsule

/// Frosted capsule that groups small header actions, as in the reference.
/// Sets its own glyph size — the three tabs used to override it with
/// three different values.
struct GlassCapsule<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @ScaledMetric(relativeTo: .callout) private var glyphSize = Theme.Metric.GlyphSize.s

    var body: some View {
        HStack(spacing: 14) {
            content()
        }
        .font(.system(size: glyphSize, weight: .bold))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // The header stays warm in dark mode, but .ultraThinMaterial flips
        // dark and turned these capsules into smudges — pin the glass light
        // so it survives the theme switch.
        .background {
            Capsule().fill(.ultraThinMaterial)
                .environment(\.colorScheme, .light)
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
    }
}

/// Single circular frosted button for the header.
struct GlassCircleButton: View {
    let systemImage: String
    var accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                // Pinned light for the same reason as GlassCapsule.
                .background {
                    Circle().fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .light)
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.clickSilent)
        .accessibilityLabel(accessibilityTitle)
    }
}

#Preview("Clouds") {
    VStack(spacing: 0) {
        TexturedHeader(title: "chats", texture: .clouds) {
            GlassCapsule {
                Image(systemName: "gauge.with.needle").foregroundStyle(.orange)
                Image(systemName: "bolt.fill").foregroundStyle(.purple)
                CoinView(size: 18)
            }
            .font(.system(size: 16, weight: .bold))
        }
        Spacer()
    }
    .background(Theme.background)
}

#Preview("Water") {
    VStack(spacing: 0) {
        TexturedHeader(title: "profile", texture: .water)
        Spacer()
    }
    .background(Theme.background)
}
