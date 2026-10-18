import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct AnchorPointEngineTests {
    @Test func openLineAcceptsAnchors() {
        let stroke = openLine(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        #expect(AnchorPointEngine.canEditAnchors(on: stroke))
    }

    @Test func insertingMidpointKeepsOpenLineOrder() {
        let stroke = openLine(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let updated = AnchorPointEngine.insertAtTap(
            stroke: stroke,
            point: CGPoint(x: 50, y: 1),
            threshold: 8
        )

        #expect(updated != nil)
        #expect(updated?.isClosed == false)
        #expect(updated?.shapeType == .polyline)
        let points = updated?.points ?? []
        #expect(points.count == 3)
        #expect(pointsApproximatelyEqual(points[0], CGPoint(x: 0, y: 0)))
        #expect(pointsApproximatelyEqual(points[1], CGPoint(x: 50, y: 0)))
        #expect(pointsApproximatelyEqual(points[2], CGPoint(x: 100, y: 0)))
    }

    @Test func tapAwayFromOpenLineDoesNotInsert() {
        let stroke = openLine(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let updated = AnchorPointEngine.insertAtTap(
            stroke: stroke,
            point: CGPoint(x: 50, y: 40),
            threshold: 8
        )
        #expect(updated == nil)
    }

    @Test func distributingOpenLineAddsEvenSpacedAnchors() {
        let stroke = openLine(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 300, y: 0))
        let updated = AnchorPointEngine.distributeToTotal(stroke: stroke, targetCount: 4)

        #expect(updated != nil)
        #expect(updated?.isClosed == false)
        let points = updated?.points ?? []
        #expect(points.count == 4)
        #expect(pointsApproximatelyEqual(points[0], CGPoint(x: 0, y: 0)))
        #expect(pointsApproximatelyEqual(points[1], CGPoint(x: 100, y: 0)))
        #expect(pointsApproximatelyEqual(points[2], CGPoint(x: 200, y: 0)))
        #expect(pointsApproximatelyEqual(points[3], CGPoint(x: 300, y: 0)))
    }

    @Test func closedShapeStillInsertsOnAnEdge() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 90, y: 0),
                CGPoint(x: 90, y: 90),
                CGPoint(x: 0, y: 90)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        let updated = AnchorPointEngine.insertAtTap(
            stroke: stroke,
            point: CGPoint(x: 45, y: 1),
            threshold: 8
        )

        #expect(updated != nil)
        #expect(updated?.isClosed == true)
        #expect(updated?.points.count == 5)
        #expect(pointsApproximatelyEqual(updated?.points[1] ?? .zero, CGPoint(x: 45, y: 0)))
    }

    @Test func curveRejectsAnAnchorThatWouldStackOnAnExistingOne() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [CurveHandle(), CurveHandle()]
        )
        let stacked = AnchorPointEngine.insertAtTap(
            stroke: stroke,
            point: CGPoint(x: 20, y: 0),
            threshold: 8,
            minimumSeparation: 44
        )
        #expect(stacked == nil)

        let midpoint = AnchorPointEngine.insertAtTap(
            stroke: stroke,
            point: CGPoint(x: 100, y: 1),
            threshold: 8,
            minimumSeparation: 44
        )
        #expect(midpoint?.points.count == 3)
    }

    @Test func constructionLineCannotReceiveAnchors() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            isClosed: false,
            isConstruction: true,
            shapeType: .construction
        )
        #expect(!AnchorPointEngine.canEditAnchors(on: stroke))
        #expect(
            AnchorPointEngine.insertAtTap(
                stroke: stroke,
                point: CGPoint(x: 50, y: 0),
                threshold: 8
            ) == nil
        )
    }

    private func openLine(from start: CGPoint, to end: CGPoint) -> VectorStroke {
        VectorStroke(
            layerID: UUID(),
            points: [start, end],
            isClosed: false,
            shapeType: .polyline
        )
    }

    private func pointsApproximatelyEqual(_ a: CGPoint, _ b: CGPoint, accuracy: CGFloat = 0.02) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= accuracy
    }
}
