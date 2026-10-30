import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct OverlapCutChoiceTests {
    @Test func defaultOverlapCutPunchesTheInnerShapeOutOfTheOuterOne() {
        let document = KoalaDocument()
        let inner = triangle(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 40, y: 42),
                CGPoint(x: 60, y: 42),
                CGPoint(x: 50, y: 62)
            ]
        )
        let outer = rectangle(layerID: document.activeLayerID, origin: .zero, size: 100)
        document.addStroke(inner)
        document.addStroke(outer)

        let proposal = document.proposedOverlapCut(at: CGPoint(x: 50, y: 50))
        #expect(proposal?.baseID == outer.id)
        #expect(proposal?.cutterID == inner.id)

        #expect(document.applyOverlapCut(baseID: outer.id, cutterID: inner.id))
        #expect(document.strokes.count == 1)
        #expect(document.strokes[0].id == outer.id)
        #expect(document.strokes[0].cutoutPoints.count == 1)
    }

    @Test func swappedOverlapCutNotchesTheShapeThatWouldHaveBeenTheCutter() {
        let back = rectangle(
            layerID: UUID(),
            origin: .zero,
            size: CGSize(width: 100, height: 80)
        )
        let front = rectangle(
            layerID: UUID(),
            origin: CGPoint(x: 50, y: 20),
            size: CGSize(width: 100, height: 80)
        )
        let overlap = CGPoint(x: 75, y: 50)
        let backOnly = CGPoint(x: 20, y: 10)
        let frontOnly = CGPoint(x: 130, y: 90)

        let document = pairedDocument(back: back, front: front)
        let proposal = document.proposedOverlapCut(at: overlap)
        #expect(proposal?.baseID == back.id)
        #expect(proposal?.cutterID == front.id)
        #expect(document.applyOverlapCut(baseID: back.id, cutterID: front.id))
        #expect(document.stroke(with: front.id) == nil)
        let notchedBack = document.stroke(with: back.id)
        #expect(notchedBack?.contains(backOnly) == true)
        #expect(notchedBack?.contains(overlap) == false)

        let swapped = pairedDocument(back: back, front: front)
        #expect(swapped.applyOverlapCut(baseID: front.id, cutterID: back.id))
        #expect(swapped.stroke(with: back.id) == nil)
        let notchedFront = swapped.stroke(with: front.id)
        #expect(notchedFront?.contains(frontOnly) == true)
        #expect(notchedFront?.contains(overlap) == false)
    }

    @Test func aSingleShapeDoesNotProposeAnOverlapCut() {
        let document = KoalaDocument()
        document.addStroke(rectangle(layerID: document.activeLayerID, origin: .zero, size: 100))
        #expect(document.proposedOverlapCut(at: CGPoint(x: 50, y: 50)) == nil)
        #expect(document.punchOverlapHole(at: CGPoint(x: 50, y: 50)) == false)
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
        rectangle(layerID: layerID, origin: origin, size: CGSize(width: size, height: size))
    }

    private func rectangle(layerID: UUID, origin: CGPoint, size: CGSize) -> VectorStroke {
        let maxX = origin.x + size.width
        let maxY = origin.y + size.height
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

    /// Places both shapes on a fresh document's active layer, keeping their ids.
    private func pairedDocument(back: VectorStroke, front: VectorStroke) -> KoalaDocument {
        let document = KoalaDocument()
        var back = back
        var front = front
        back.layerID = document.activeLayerID
        front.layerID = document.activeLayerID
        document.addStroke(back)
        document.addStroke(front)
        return document
    }
}
