//
//  ReferenceImageDrawing.swift
//  vectr
//

import CoreGraphics
import UIKit

enum ReferenceImageDrawing {
    /// CGImage whose pixels are already upright.
    ///
    /// `CALayer.contents` ignores `UIImage.imageOrientation`, so assigning
    /// `image.cgImage` stretches a sideways photo into the oriented frame.
    /// Images that are already `.up` are returned as-is.
    static func uprightCGImage(from image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }
}
