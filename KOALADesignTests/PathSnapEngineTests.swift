import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct PathSnapEngineTests {
    private static let snapRadius: CGFloat = 16
    private static let circleRadius: CGFloat = 100
    private static let kinds: Set<SnapKind> = [.quadrant]

    private let engine = PathSnapEngine.makeDefault()

    @Test func cursorNearNorthLocksToCardinal() {
        let stroke = Self.circleStroke()
        let north = CGPoint(x: 0, y: -Self.circleRadius)
        let cursor = CGPoint(x: 4, y: -Self.circleRadius + 8)

        let candidate = snap(cursor, strokes: [stroke])

        #expect(candidate?.kind == .quadrant)
        #expect(pointsMatch(candidate?.point, north))
    }

    @Test func cursorOnFortyFiveDegreeRimLocksToRimNotCardinal() {
        let stroke = Self.circleStroke()
        let rim = Self.pointOnCircle(degrees: -45)

        let candidate = snap(rim, strokes: [stroke])

        #expect(candidate?.kind == .quadrant)
        #expect(pointsMatch(candidate?.point, rim))
        #expect(!pointsMatch(candidate?.point, CGPoint(x: 0, y: -Self.circleRadius)))
        #expect(!pointsMatch(candidate?.point, CGPoint(x: Self.circleRadius, y: 0)))
    }

    @Test func cursorWellInsideOrOutsideCircleDoesNotSnap() {
        let stroke = Self.circleStroke()

        #expect(snap(.zero, strokes: [stroke]) == nil)
        #expect(snap(CGPoint(x: 0, y: -Self.circleRadius * 2), strokes: [stroke]) == nil)
    }

    @Test func arcSnapsOnDrawnSpanAndMissesTheGap() {
        let stroke = Self.eastHalfArc()
        let onSpan = Self.pointOnCircle(degrees: -45)
        let inGap = CGPoint(x: -Self.circleRadius, y: 0)

        let hit = snap(onSpan, strokes: [stroke])
        #expect(hit?.kind == .quadrant)
        #expect(pointsMatch(hit?.point, onSpan))

        #expect(snap(inGap, strokes: [stroke]) == nil)
    }

    private func snap(_ point: CGPoint, strokes: [VectorStroke]) -> SnapCandidate? {
        engine.closestCandidate(
            to: point,
            within: Self.snapRadius,
            strokes: strokes,
            enabledKinds: Self.kinds
        )
    }

    private static func circleStroke() -> VectorStroke {
        VectorStroke(
            layerID: UUID(),
            points: ShapeGeometry.circleCardinalPoints(center: .zero, radius: circleRadius),
            isClosed: true,
            shapeType: .circle
        )
    }

    /// Open arc covering the east half of the unit circle (north → east → south).
    private static func eastHalfArc() -> VectorStroke {
        VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: 0, y: -circleRadius),
                CGPoint(x: circleRadius, y: 0),
                CGPoint(x: 0, y: circleRadius)
            ],
            shapeType: .arc
        )
    }

    private static func pointOnCircle(degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: cos(radians) * circleRadius,
            y: sin(radians) * circleRadius
        )
    }
}

private func pointsMatch(_ a: CGPoint?, _ b: CGPoint, tolerance: CGFloat = 0.05) -> Bool {
    guard let a else { return false }
    return hypot(a.x - b.x, a.y - b.y) <= tolerance
}
