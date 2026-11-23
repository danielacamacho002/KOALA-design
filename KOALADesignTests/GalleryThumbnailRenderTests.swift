import CoreGraphics
import Testing
import UIKit
@testable import KOALADesign

@MainActor
struct GalleryThumbnailRenderTests {
    @Test func pageSizedDrawingFitsAndBackgroundStaysClear() throws {
        let image = try galleryThumbnail(pageOutline(color: CodableColor(red: 0, green: 0, blue: 0)))

        let corner = try pixel(image, at: CGPoint(x: 1, y: 1))
        #expect(corner.a < 8)
        try expectInkSpansPreview(image) { $0.a > 200 && $0.r < 40 }
    }

    @Test func lightStrokeStaysInTheThumbnail() throws {
        let image = try galleryThumbnail(pageOutline(color: CodableColor(red: 1, green: 1, blue: 1)))

        let corner = try pixel(image, at: CGPoint(x: 1, y: 1))
        #expect(corner.a < 8)
        try expectInkSpansPreview(image) { $0.a > 200 && $0.r > 240 }
    }

    @Test func smallDrawingDoesNotCoverTheThumbnail() throws {
        let document = KoalaDocument()
        document.addStroke(rectangle(
            layerID: document.activeLayerID,
            half: 15,
            color: CodableColor(red: 0, green: 0, blue: 0)
        ))
        let image = try galleryThumbnail(document)

        let corner = try pixel(image, at: CGPoint(x: 1, y: 1))
        #expect(corner.a < 8)
        #expect(containsPixel(image, in: CGRect(origin: .zero, size: image.size)) { $0.a > 200 && $0.r < 40 })
    }

    @Test func exportImageKeepsAnOpaqueWhitePage() throws {
        let document = pageOutline(color: CodableColor(red: 0, green: 0, blue: 0))
        let rendered = try #require(DocumentRenderer.renderImage(snapshot: document.makeSnapshot()))
        guard let data = rendered.pngData(), let image = UIImage(data: data, scale: rendered.scale) else {
            Issue.record("Export image failed to encode")
            return
        }

        let corner = try pixel(image, at: CGPoint(x: 1, y: 1))
        #expect(corner.a > 250)
        #expect(corner.r > 250)
        #expect(corner.g > 250)
        #expect(corner.b > 250)
    }

    private func pageOutline(color: CodableColor) -> KoalaDocument {
        let document = KoalaDocument()
        let halfWidth = DocumentSettings.defaultCanvasWidth / 2
        let halfHeight = DocumentSettings.defaultCanvasHeight / 2
        document.addStroke(rectangle(
            layerID: document.activeLayerID,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            color: color
        ))
        return document
    }

    private func rectangle(
        layerID: UUID,
        half: CGFloat = 0,
        halfWidth: CGFloat? = nil,
        halfHeight: CGFloat? = nil,
        color: CodableColor
    ) -> VectorStroke {
        let hx = halfWidth ?? half
        let hy = halfHeight ?? half
        return VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: -hx, y: -hy),
                CGPoint(x: hx, y: -hy),
                CGPoint(x: hx, y: hy),
                CGPoint(x: -hx, y: hy)
            ],
            strokeWidth: 20,
            strokeColor: color,
            isClosed: true,
            fillOpacity: 0
        )
    }

    private func galleryThumbnail(_ document: KoalaDocument) throws -> UIImage {
        let rendered = try #require(ThumbnailRenderer.generate(for: document))
        guard let data = rendered.pngData(), let image = UIImage(data: data, scale: rendered.scale) else {
            Issue.record("Thumbnail failed to round-trip through PNG")
            return rendered
        }
        return image
    }

    /// The outline of a page-sized shape has to reach both sides of the preview.
    /// A zoom-out floor of 2 leaves only the middle of that shape, or none of it.
    private func expectInkSpansPreview(
        _ image: UIImage,
        where match: (Sample) -> Bool
    ) throws {
        let span = try inkXSpan(image, where: match)
        #expect(span.minX < image.size.width * 0.25)
        #expect(span.maxX > image.size.width * 0.75)
    }

    private func inkXSpan(
        _ image: UIImage,
        where match: (Sample) -> Bool
    ) throws -> (minX: CGFloat, maxX: CGFloat) {
        let bitmap = try bitmap(of: image)
        let scale = image.scale
        var minX = bitmap.width
        var maxX = 0
        var found = false
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where match(bitmap.sample(x: x, y: y)) {
                found = true
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        try #require(found)
        return (CGFloat(minX) / scale, CGFloat(maxX) / scale)
    }

    private struct Sample {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }

    private func pixel(_ image: UIImage, at point: CGPoint) throws -> Sample {
        let bitmap = try bitmap(of: image)
        let x = min(bitmap.width - 1, max(0, Int(point.x * image.scale)))
        let y = min(bitmap.height - 1, max(0, Int(point.y * image.scale)))
        return bitmap.sample(x: x, y: y)
    }

    private func containsPixel(
        _ image: UIImage,
        in rect: CGRect,
        where match: (Sample) -> Bool
    ) -> Bool {
        guard let bitmap = try? bitmap(of: image) else { return false }
        let scale = image.scale
        let minX = max(0, Int(rect.minX * scale))
        let maxX = min(bitmap.width, Int(rect.maxX * scale))
        let minY = max(0, Int(rect.minY * scale))
        let maxY = min(bitmap.height, Int(rect.maxY * scale))
        guard minX < maxX, minY < maxY else { return false }
        for y in minY..<maxY {
            for x in minX..<maxX where match(bitmap.sample(x: x, y: y)) {
                return true
            }
        }
        return false
    }

    private struct Bitmap {
        var width: Int
        var height: Int
        var bytes: [UInt8]

        func sample(x: Int, y: Int) -> Sample {
            let index = (y * width + x) * 4
            return Sample(r: bytes[index], g: bytes[index + 1], b: bytes[index + 2], a: bytes[index + 3])
        }
    }

    private func bitmap(of image: UIImage) throws -> Bitmap {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drew)
        return Bitmap(width: width, height: height, bytes: bytes)
    }
}
