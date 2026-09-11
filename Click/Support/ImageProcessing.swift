//
//  ImageProcessing.swift
//  Click
//
//  Photo normalisation before anything reaches SwiftData. Full-resolution
//  camera originals are 10MB+; at 1080px/JPEG 0.8 a photo is a few hundred
//  kilobytes and indistinguishable on a phone screen.
//

import UIKit

enum ImageProcessing {
    /// Downscale to at most `maxDimension` on the long edge and re-encode
    /// as JPEG. Returns nil for undecodable input.
    static func downscaledJPEG(
        from data: Data,
        maxDimension: CGFloat = 1080,
        quality: CGFloat = 0.8
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > 0 else { return nil }

        let scale = min(1, maxDimension / longEdge)
        let targetSize = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // Pixel-exact; the screen scale is irrelevant for storage.
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: quality)
    }
}
