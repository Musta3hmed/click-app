//
//  ClickLogoView.swift
//  Click
//
//  The Click mark drawn as vectors — two overlapping faces on the brand
//  gradient with the vertical "shutter" dashes. Centred by construction,
//  crisp at any size, no raster asset. AppIcon.png stays for the icon only.
//

import SwiftUI

struct ClickLogoView: View {
    var size: CGFloat = 110
    /// Corner radius as a fraction of size (iOS icon squircle feel).
    var cornerFraction: CGFloat = 0.235

    var body: some View {
        Canvas { context, canvasSize in
            let d = min(canvasSize.width, canvasSize.height)
            let origin = CGPoint(
                x: (canvasSize.width - d) / 2,
                y: (canvasSize.height - d) / 2
            )
            let frame = CGRect(origin: origin, size: CGSize(width: d, height: d))

            // Background: brand gradient in a rounded square.
            let shape = RoundedRectangle(cornerRadius: d * cornerFraction, style: .continuous)
                .path(in: frame)
            context.fill(shape, with: .linearGradient(
                Gradient(colors: [Theme.brandOrange, Theme.brandCoral, Theme.brandPink]),
                startPoint: frame.origin,
                endPoint: CGPoint(x: frame.maxX, y: frame.maxY)
            ))
            context.clip(to: shape)

            let cx = frame.midX
            let cy = frame.midY

            // Vertical shutter dashes, top and bottom.
            let dashWidth = d * 0.035
            let dashHeight = d * 0.09
            for yOffset in [-0.305, 0.305] {
                let rect = CGRect(
                    x: cx - dashWidth / 2,
                    y: cy + d * yOffset - dashHeight / 2,
                    width: dashWidth,
                    height: dashHeight
                )
                context.fill(
                    Capsule().path(in: rect),
                    with: .color(.white)
                )
            }

            // Back face: translucent, to the right.
            let backR = d * 0.155
            let backCenter = CGPoint(x: cx + d * 0.145, y: cy)
            context.fill(
                Circle().path(in: circleRect(center: backCenter, radius: backR)),
                with: .color(.white.opacity(0.45))
            )

            // Back face features (white).
            let backEyeR = backR * 0.13
            for dx in [-0.38, 0.38] {
                let eye = CGPoint(x: backCenter.x + backR * dx, y: backCenter.y - backR * 0.22)
                context.fill(
                    Circle().path(in: circleRect(center: eye, radius: backEyeR)),
                    with: .color(.white)
                )
            }
            var backSmile = Path()
            backSmile.move(to: CGPoint(x: backCenter.x - backR * 0.34, y: backCenter.y + backR * 0.28))
            backSmile.addQuadCurve(
                to: CGPoint(x: backCenter.x + backR * 0.34, y: backCenter.y + backR * 0.28),
                control: CGPoint(x: backCenter.x, y: backCenter.y + backR * 0.62)
            )
            context.stroke(backSmile, with: .color(.white),
                           style: StrokeStyle(lineWidth: backR * 0.14, lineCap: .round))

            // Front face: solid white, to the left, winking.
            let frontR = d * 0.185
            let frontCenter = CGPoint(x: cx - d * 0.11, y: cy)
            context.fill(
                Circle().path(in: circleRect(center: frontCenter, radius: frontR)),
                with: .color(.white)
            )

            let ink = Color(hex: 0x232135)
            // Right eye: dot. Left eye: wink line.
            let eyeY = frontCenter.y - frontR * 0.22
            context.fill(
                Circle().path(in: circleRect(
                    center: CGPoint(x: frontCenter.x + frontR * 0.36, y: eyeY),
                    radius: frontR * 0.115
                )),
                with: .color(ink)
            )
            var wink = Path()
            wink.move(to: CGPoint(x: frontCenter.x - frontR * 0.52, y: eyeY))
            wink.addLine(to: CGPoint(x: frontCenter.x - frontR * 0.18, y: eyeY))
            context.stroke(wink, with: .color(ink),
                           style: StrokeStyle(lineWidth: frontR * 0.12, lineCap: .round))

            var smile = Path()
            smile.move(to: CGPoint(x: frontCenter.x - frontR * 0.38, y: frontCenter.y + frontR * 0.30))
            smile.addQuadCurve(
                to: CGPoint(x: frontCenter.x + frontR * 0.38, y: frontCenter.y + frontR * 0.30),
                control: CGPoint(x: frontCenter.x, y: frontCenter.y + frontR * 0.68)
            )
            context.stroke(smile, with: .color(ink),
                           style: StrokeStyle(lineWidth: frontR * 0.12, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Click logo")
    }

    private func circleRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}

#Preview {
    VStack(spacing: 30) {
        ClickLogoView(size: 60)
        ClickLogoView(size: 110)
        ClickLogoView(size: 200)
    }
    .padding()
    .background(Theme.background)
}
