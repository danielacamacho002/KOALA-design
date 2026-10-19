import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct NestedShapeHitTests {
    @Test func lineInsideAClosedShapeIsHitOnTheLine() {
        let document = KoalaDocument()
        let outer = rectangle(
            layerID: document.activeLayerID,
            origin: .zero,
            size: 100
        )
        let line = VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 20, y: 50), CGPoint(x: 80, y: 50)]
        )
        document.addStroke(outer)
        document.addStroke(line)

        let hit = document.elementHit(near: CGPoint(x: 50, y: 50), threshold: 4)
        #expect(hit == .stroke(line.id))
    }

    @Test func smallerShapeInsideALaterLargerShapeIsHitFromItsInterior() {
        let document = KoalaDocument()
        // A triangle, not a quad: nested rectangles are absorbed into a hole.
        let inner = triangle(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 40, y: 42),
                CGPoint(x: 60, y: 42),
                CGPoint(x: 50, y: 62)
            ]
        )
        let outer = rectangle(
            layerID: document.activeLayerID,
            origin: .zero,
            size: 100
        )
        document.addStroke(inner)
        document.addStroke(outer)

        // Inside the triangle, farther than the threshold from every edge.
        let hit = document.elementHit(near: CGPoint(x: 50, y: 50), threshold: 4)
        #expect(hit == .stroke(inner.id))
    }

    @Test func largerShapeInteriorOutsideTheInnerShapeHitsTheLargerShape() {
        let document = KoalaDocument()
        let inner = triangle(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 40, y: 42),
                CGPoint(x: 60, y: 42),
                CGPoint(x: 50, y: 62)
            ]
        )
        let outer = rectangle(
            layerID: document.activeLayerID,
            origin: .zero,
            size: 100
        )
        document.addStroke(inner)
        document.addStroke(outer)

        let hit = document.elementHit(near: CGPoint(x: 10, y: 10), threshold: 4)
        #expect(hit == .stroke(outer.id))
    }

    @Test func tappingAnInnerShapePunchesItOutOfTheLargerShape() {
        let document = KoalaDocument()
        let inner = triangle(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 40, y: 42),
                CGPoint(x: 60, y: 42),
                CGPoint(x: 50, y: 62)
            ]
        )
        let outer = rectangle(
            layerID: document.activeLayerID,
            origin: .zero,
            size: 100
        )
        // Outer is added last, so its fill is in front of the inner shape.
        document.addStroke(inner)
        document.addStroke(outer)

        #expect(document.punchOverlapHole(at: CGPoint(x: 50, y: 50)))
        #expect(document.strokes.count == 1)
        #expect(document.strokes[0].id == outer.id)
        #expect(document.strokes[0].cutoutPoints.count == 1)
    }

    @Test func frontLayerShapeBlocksTheActiveLayerUnderneath() {
        let document = KoalaDocument()
        let backID = document.activeLayerID
        let inner = rectangle(layerID: backID, origin: CGPoint(x: 40, y: 40), size: 20)
        document.addStroke(inner)

        let front = document.addLayer()
        let cover = rectangle(layerID: front.id, origin: .zero, size: 100)
        document.addStroke(cover)
        document.setActiveLayer(id: backID)

        let point = CGPoint(x: 50, y: 50)
        #expect(document.topmostOccupyingStroke(near: point, threshold: 4)?.id == cover.id)
        #expect(document.elementHit(near: point, threshold: 4) == .none)
    }

    private func triangle(layerID: UUID, points: [CGPoint]) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: points,
            isClosed: true,
            shapeType: .polyline
        )
    }

    private func rectangle(layerID: UUID, origin: CGPoint, size: CGFloat) -> VectorStroke {
        let maxX = origin.x + size
        let maxY = origin.y + size
        return VectorStroke(
            layerID: layerID,
            points: [
                origin,
                CGPoint(x: maxX, y: origin.y),
                CGPoint(x: maxX, y: maxY),
                CGPoint(x: origin.x, y: maxY)
            ],
            isClosed: true,
            shapeType: .polyline
        )
    }
}
