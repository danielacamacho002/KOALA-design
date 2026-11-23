import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct PrintSelectionTests {
    @Test func selectionHitTestIgnoresTheGapBetweenSelectedShapes() {
        let document = KoalaDocument()
        let left = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 100), CGPoint(x: 40, y: 100)]
        )
        let right = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 200, y: 100), CGPoint(x: 240, y: 100)]
        )
        document.addStroke(left)
        document.addStroke(right)
        document.setPrintSelection(strokeIDs: [left.id, right.id], textIDs: [])
        #expect(document.printSelectionCount == 2)

        #expect(document.printSelectionContains(point: CGPoint(x: 20, y: 100), threshold: 4))
        #expect(document.printSelectionContains(point: CGPoint(x: 220, y: 100), threshold: 4))
        // Inside the union bounding box but not on either shape: a drag here should
        // start a marquee rather than move the selection.
        #expect(!document.printSelectionContains(point: CGPoint(x: 120, y: 100), threshold: 4))
    }

    @Test func loneSelectionKeepsItsBoundingBoxDraggable() {
        let document = KoalaDocument()
        let corner = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 60), CGPoint(x: 60, y: 60)]
        )
        document.addStroke(corner)
        document.setPrintSelection(strokeIDs: [corner.id], textIDs: [])

        // Far from both segments of the open L, but inside its bounds.
        #expect(document.printSelectionContains(point: CGPoint(x: 50, y: 10), threshold: 2))
        #expect(!document.printSelectionContains(point: CGPoint(x: 200, y: 200), threshold: 2))
    }

    @Test func emptySelectionContainsNothing() {
        let document = KoalaDocument()
        let stroke = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 100), CGPoint(x: 40, y: 100)]
        )
        document.addStroke(stroke)

        #expect(!document.printSelectionContains(point: CGPoint(x: 20, y: 100), threshold: 4))
    }

    @Test func flippingMultiSelectionMirrorsTheArrangement() {
        let document = KoalaDocument()
        let left = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 100), CGPoint(x: 40, y: 100)]
        )
        let right = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 200, y: 100), CGPoint(x: 240, y: 100)]
        )
        document.addStroke(left)
        document.addStroke(right)
        document.setPrintSelection(strokeIDs: [left.id, right.id], textIDs: [])
        let revisionBefore = document.printLayoutRevision

        document.flipPrintSelection(horizontal: true)

        // Group bounding box spans x 0...240, so the two shapes swap sides.
        let leftBounds = document.printBounds(for: left.id)
        let rightBounds = document.printBounds(for: right.id)
        #expect(abs(leftBounds.minX - 200) < 0.01)
        #expect(abs(rightBounds.maxX - 40) < 0.01)
        // A horizontal flip must not move anything vertically.
        #expect(abs(leftBounds.midY - 100) < 0.01)
        #expect(abs(rightBounds.midY - 100) < 0.01)
        #expect(document.printLayoutRevision > revisionBefore)
    }

    @Test func flippingLoneSelectionLeavesItInPlace() {
        let document = KoalaDocument()
        let corner = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0), CGPoint(x: 60, y: 40)]
        )
        document.addStroke(corner)
        document.setPrintSelection(strokeIDs: [corner.id], textIDs: [])

        document.flipPrintSelection(horizontal: true)

        let transform = document.printTransform(for: corner.id)
        #expect(transform.flipHorizontal)
        #expect(transform.translation == .zero)
    }

    private func makePolyline(layerID: UUID, points: [CGPoint]) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: points,
            strokeWidth: 1.5,
            isClosed: false,
            shapeType: .polyline
        )
    }
}
