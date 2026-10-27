import CoreGraphics
import Testing
@testable import Koala

@MainActor
struct ViewportTransformTests {
    @Test func clampingZoomOutKeepsAFarAnchorFixed() {
        let anchor = CGPoint(x: 500, y: 400)
        let documentPoint = CGPoint(x: 900, y: 700)
        var viewport = ViewportTransform()
        viewport.scale = 1
        viewport.translation = CGPoint(
            x: anchor.x - documentPoint.x,
            y: anchor.y - documentPoint.y
        )

        viewport.zoom(to: 0.05, anchorViewPoint: anchor)

        let viewSize = CGSize(width: 1000, height: 800)
        let canvasSize = CGSize(width: 1728, height: 1296)
        viewport.clampToCanvasSize(in: viewSize, canvasSize: canvasSize, preserving: anchor)

        let placed = viewport.documentToView(documentPoint)
        #expect(abs(placed.x - anchor.x) < 0.01)
        #expect(abs(placed.y - anchor.y) < 0.01)
        let floor = ViewportTransform.minimumScaleToFitCanvas(in: viewSize, canvasSize: canvasSize)
        #expect(abs(viewport.scale - floor) < 0.001)
    }

    @Test func clampWithoutAnAnchorOnlyChangesScale() {
        var viewport = ViewportTransform(scale: 0.05, translation: CGPoint(x: 40, y: -20))
        let viewSize = CGSize(width: 1000, height: 800)
        let canvasSize = CGSize(width: 1728, height: 1296)
        viewport.clampToCanvasSize(in: viewSize, canvasSize: canvasSize)
        #expect(viewport.translation == CGPoint(x: 40, y: -20))
        let floor = ViewportTransform.minimumScaleToFitCanvas(in: viewSize, canvasSize: canvasSize)
        #expect(abs(viewport.scale - floor) < 0.001)
    }
}
