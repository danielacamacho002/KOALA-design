import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Koala

@MainActor
struct DonutDetectorTests {
    @Test func concentricCircleHoleStaysRound() {
        let document = KoalaDocument()
        let center = CGPoint(x: 200, y: 200)
        document.addStroke(circle(layerID: document.activeLayerID, center: center, radius: 100))
        document.addStroke(circle(layerID: document.activeLayerID, center: center, radius: 50))

        #expect(document.strokes.count == 1)
        let donut = try! #require(document.strokes.first)
        let hole = try! #require(donut.cutoutPoints.first)
        #expect(hole.count > 4)

        // A diamond's edge midpoint sits at r·cos(45°) ≈ 35; a round hole stays near 50.
        let rendered = StrokeRenderer.path(for: donut, viewport: ViewportTransform()).cgPath
        let diagonal = CGPoint(x: center.x + 40 * cos(.pi / 4), y: center.y + 40 * sin(.pi / 4))
        #expect(!rendered.contains(diagonal, using: .evenOdd))
    }

    @Test func quadInsideQuadBecomesHole() {
        let document = KoalaDocument()
        let outer = rectangle(layerID: document.activeLayerID, center: CGPoint(x: 200, y: 200), half: 100)
        document.addStroke(outer)
        document.addStroke(rectangle(layerID: document.activeLayerID, center: CGPoint(x: 200, y: 200), half: 40))

        #expect(document.strokes.count == 1)
        let host = try! #require(document.strokes.first)
        #expect(host.id == outer.id)
        #expect(host.cutoutPoints.count == 1)

        let rendered = StrokeRenderer.path(for: host, viewport: ViewportTransform()).cgPath
        #expect(!rendered.contains(CGPoint(x: 200, y: 200), using: .evenOdd))
        #expect(rendered.contains(CGPoint(x: 120, y: 120), using: .evenOdd))
    }

    @Test func outerQuadDrawnSecondStillCutsHole() {
        let document = KoalaDocument()
        document.addStroke(rectangle(layerID: document.activeLayerID, center: CGPoint(x: 200, y: 200), half: 40))
        let outer = rectangle(layerID: document.activeLayerID, center: CGPoint(x: 220, y: 180), half: 100)
        document.addStroke(outer)

        #expect(document.strokes.count == 1)
        #expect(document.strokes.first?.id == outer.id)
        #expect(document.strokes.first?.cutoutPoints.count == 1)
    }

    @Test func overlappingQuadsStaySeparate() {
        let document = KoalaDocument()
        document.addStroke(rectangle(layerID: document.activeLayerID, center: CGPoint(x: 200, y: 200), half: 100))
        document.addStroke(rectangle(layerID: document.activeLayerID, center: CGPoint(x: 290, y: 200), half: 40))

        #expect(document.strokes.count == 2)
        #expect(document.strokes.allSatisfy { $0.cutoutPoints.isEmpty })
    }

    @Test func quadDrawnInsideExistingHoleStaysSeparate() {
        let document = KoalaDocument()
        let center = CGPoint(x: 200, y: 200)
        document.addStroke(rectangle(layerID: document.activeLayerID, center: center, half: 100))
        document.addStroke(rectangle(layerID: document.activeLayerID, center: center, half: 60))
        document.addStroke(rectangle(layerID: document.activeLayerID, center: center, half: 20))

        #expect(document.strokes.count == 2)
        #expect(document.strokes.map(\.cutoutPoints.count).sorted() == [0, 1])
    }

    @Test func quadsOnDifferentLayersStaySeparate() {
        let document = KoalaDocument()
        let center = CGPoint(x: 200, y: 200)
        document.addStroke(rectangle(layerID: document.activeLayerID, center: center, half: 100))
        document.addStroke(rectangle(layerID: UUID(), center: center, half: 40))

        #expect(document.strokes.count == 2)
        #expect(document.strokes.allSatisfy { $0.cutoutPoints.isEmpty })
    }

    @Test func holeMovesWithItsShape() {
        let document = KoalaDocument()
        let center = CGPoint(x: 200, y: 200)
        let outer = rectangle(layerID: document.activeLayerID, center: center, half: 100)
        document.addStroke(outer)
        document.addStroke(rectangle(layerID: document.activeLayerID, center: center, half: 40))
        let holeBefore = try! #require(document.stroke(with: outer.id)?.cutoutPoints.first)

        document.translateStroke(id: outer.id, delta: CGPoint(x: 50, y: -30), recordUndo: true)

        let holeAfter = try! #require(document.stroke(with: outer.id)?.cutoutPoints.first)
        #expect(holeAfter == holeBefore.map { CGPoint(x: $0.x + 50, y: $0.y - 30) })
    }

    @Test func filletingAShapeKeepsItsHole() {
        let document = KoalaDocument()
        let center = CGPoint(x: 200, y: 200)
        let outer = rectangle(layerID: document.activeLayerID, center: center, half: 100)
        document.addStroke(outer)
        document.addStroke(rectangle(layerID: document.activeLayerID, center: center, half: 40))
        document.selectedStrokeID = outer.id

        document.applyFilletToSelected(radius: 20)

        let host = try! #require(document.stroke(with: outer.id))
        #expect(host.hasAnyCornerFillets)
        #expect(host.cutoutPoints.count == 1)
        let rendered = StrokeRenderer.path(for: host, viewport: ViewportTransform()).cgPath
        #expect(!rendered.contains(center, using: host.resolvedCGFillRule))
        #expect(rendered.contains(CGPoint(x: 120, y: 200), using: host.resolvedCGFillRule))
        #expect(!rendered.contains(CGPoint(x: 101, y: 101), using: host.resolvedCGFillRule))
    }

    @Test func joiningAShapeOntoADonutKeepsTheHole() {
        let document = KoalaDocument()
        let center = CGPoint(x: 200, y: 200)
        let donut = circle(layerID: document.activeLayerID, center: center, radius: 100)
        document.addStroke(donut)
        document.addStroke(circle(layerID: document.activeLayerID, center: center, radius: 40))
        let tab = rectangle(layerID: document.activeLayerID, center: CGPoint(x: 300, y: 200), half: 30)
        document.addStroke(tab)
        #expect(document.strokes.count == 2)

        document.setElementSelection(strokeIDs: [donut.id, tab.id], textIDs: [])
        #expect(document.joinSelectedShapes())

        #expect(document.strokes.count == 1)
        let joined = try! #require(document.strokes.first)
        #expect(joined.cutoutPoints.count == 1)
        let rendered = StrokeRenderer.path(for: joined, viewport: ViewportTransform()).cgPath
        #expect(!rendered.contains(center, using: joined.resolvedCGFillRule))
        #expect(rendered.contains(CGPoint(x: 320, y: 200), using: joined.resolvedCGFillRule))
    }

    @Test func joiningAShapeOntoACornerOfAHoledQuadKeepsTheHole() {
        let document = KoalaDocument()
        let center = CGPoint(x: 200, y: 200)
        let outer = rectangle(layerID: document.activeLayerID, center: center, half: 100)
        document.addStroke(outer)
        document.addStroke(rectangle(layerID: document.activeLayerID, center: center, half: 40))
        let corner = try! #require(outer.points.max { $0.x + $0.y < $1.x + $1.y })
        let tab = rectangle(
            layerID: document.activeLayerID,
            center: CGPoint(x: corner.x + 30, y: corner.y + 30),
            half: 30
        )
        document.addStroke(tab)

        document.setElementSelection(strokeIDs: [outer.id, tab.id], textIDs: [])
        #expect(document.joinSelectedShapes())

        #expect(document.strokes.count == 1)
        let joined = try! #require(document.strokes.first)
        #expect(joined.cutoutPoints.count == 1)
        #expect(!joined.contains(center))
    }

    private func rectangle(layerID: UUID, center: CGPoint, half: CGFloat) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.rectangleFromCenterDistances(center, halfWidth: half, halfHeight: half),
            strokeWidth: 1.5,
            isClosed: true,
            shapeType: .rectangle
        )
    }

    private func circle(layerID: UUID, center: CGPoint, radius: CGFloat) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.circleCardinalPoints(center: center, radius: radius),
            strokeWidth: 1.5,
            isClosed: true,
            shapeType: .circle
        )
    }
}
