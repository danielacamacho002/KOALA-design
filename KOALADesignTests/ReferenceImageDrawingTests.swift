import CoreGraphics
import Testing
import UIKit
@testable import KOALADesign

@MainActor
struct ReferenceImageDrawingTests {
    @Test func uprightImageKeepsOriginalPixels() {
        let image = solidImage(width: 40, height: 10)
        let upright = ReferenceImageDrawing.uprightCGImage(from: image)

        #expect(upright === image.cgImage)
        #expect(upright?.width == 40)
        #expect(upright?.height == 10)
    }

    @Test func sidewaysPhotoIsNotStretchedIntoItsFrame() {
        let stored = solidImage(width: 40, height: 10)
        guard let cgImage = stored.cgImage else {
            Issue.record("Expected a CGImage")
            return
        }
        // Camera portrait JPEGs are stored landscape and tagged `.right`.
        // UIImage.size is the upright box; the raw buffer is still 40×10.
        let photo = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        #expect(photo.size == CGSize(width: 10, height: 40))
        #expect(cgImage.width == 40)
        #expect(cgImage.height == 10)

        let upright = ReferenceImageDrawing.uprightCGImage(from: photo)
        #expect(upright?.width == 10)
        #expect(upright?.height == 40)
        #expect(upright !== cgImage)
    }

    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
