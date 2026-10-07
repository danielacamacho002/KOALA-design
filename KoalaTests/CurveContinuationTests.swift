import CoreGraphics
import Foundation
import Testing
@testable import Koala

/// Extending an open curve adds anchors at one end and leaves the tangents that
/// already draw the curve alone.
@MainActor
struct CurveContinuationTests {
    private struct SegmentOffset: Equatable {
        var outOffset: CGPoint
        var inOffset: CGPoint
    }

    private static func segmentOffsets(_ stroke: VectorStroke) -> [SegmentOffset] {
        guard let handles = stroke.curveHandles else { return [] }
        let count = stroke.points.count
        guard count >= 2, handles.count == count else { return [] }
        let segments = stroke.isClosed ? count : count - 1
        return (0..<segments).map { index in
            let next = (index + 1) % count
            return SegmentOffset(outOffset: handles[index].outOffset, inOffset: handles[next].inOffset)
        }
    }

    /// An open arch whose custom tangents bow both segments off their chords.
    private static func arch() -> VectorStroke {
        var stroke = VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: -100, y: 0),
                CGPoint(x: 0, y: 60),
                CGPoint(x: 100, y: 0)
            ],
            isClosed: false,
            shapeType: .curve
        )
        stroke.curveHandles = [
            CurveHandle(inOffset: CGPoint(x: -10, y: 0), outOffset: CGPoint(x: 0, y: 90)),
            CurveHandle(inOffset: CGPoint(x: -60, y: 0), outOffset: CGPoint(x: 60, y: 0)),
            CurveHandle(inOffset: CGPoint(x: 0, y: 90), outOffset: CGPoint(x: 10, y: 0))
        ]
        stroke.smoothCornerIndices = [1]
        stroke.cornerRadiiByIndex = [1: 8]
        stroke.openEdgeStarts = [0]
        return stroke
    }

    private static func extend(
        _ stroke: VectorStroke,
        fromStart: Bool,
        extra: CGPoint,
        closeTolerance: CGFloat = 1
    ) -> VectorStroke {
        let seed = ShapeGeometry.continuationSeed(for: stroke, fromStart: fromStart)
        var anchors = seed.anchors
        anchors.append(extra)
        return ShapeGeometry.extendingOpenCurve(
            stroke,
            anchorsInContinuationOrder: anchors,
            originalHandles: seed.handles,
            reversed: seed.reversed,
            closeTolerance: closeTolerance
        )
    }

    @Test func extendingFromTheEndKeepsExistingTangents() {
        let curve = Self.arch()
        let updated = Self.extend(curve, fromStart: false, extra: CGPoint(x: 160, y: 40))

        #expect(updated.id == curve.id)
        #expect(!updated.isClosed)
        #expect(updated.points == curve.points + [CGPoint(x: 160, y: 40)])
        let original = Self.segmentOffsets(curve)
        let extended = Self.segmentOffsets(updated)
        #expect(Array(extended.prefix(original.count)) == original)
        #expect(updated.smoothCornerIndices == [1])
        #expect(updated.cornerRadiiByIndex == [1: 8])
        #expect(updated.openEdgeStarts == [0])
    }

    @Test func extendingFromTheStartPrependsAndKeepsExistingTangents() {
        let curve = Self.arch()
        let extra = CGPoint(x: -160, y: 30)
        let updated = Self.extend(curve, fromStart: true, extra: extra)

        #expect(updated.points == [extra] + curve.points)
        #expect(!updated.isClosed)
        let original = Self.segmentOffsets(curve)
        let extended = Self.segmentOffsets(updated)
        #expect(Array(extended.dropFirst()) == original)
        #expect(updated.smoothCornerIndices == [2])
        #expect(updated.cornerRadiiByIndex == [2: 8])
        #expect(updated.openEdgeStarts == [1])
    }

    @Test func meetingTheOtherEndClosesWithoutRewritingTheCurve() {
        let curve = Self.arch()
        let updated = Self.extend(curve, fromStart: false, extra: curve.points[0], closeTolerance: 0.5)

        #expect(updated.isClosed)
        #expect(updated.points == curve.points)
        let original = Self.segmentOffsets(curve)
        let closed = Self.segmentOffsets(updated)
        #expect(closed.count == original.count + 1)
        #expect(Array(closed.prefix(original.count)) == original)
    }

    @Test func aShortCurveDoesNotCloseOntoTwoAnchors() {
        var curve = VectorStroke(
            layerID: UUID(),
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 0)],
            isClosed: false,
            shapeType: .curve
        )
        curve.curveHandles = [
            CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: 30)),
            CurveHandle(inOffset: CGPoint(x: 0, y: -20), outOffset: .zero)
        ]
        let updated = Self.extend(curve, fromStart: false, extra: curve.points[0], closeTolerance: 1)

        #expect(!updated.isClosed)
        #expect(updated.points.count == 3)
        #expect(updated.curveHandles?[0].outOffset == CGPoint(x: 0, y: 30))
        #expect(updated.curveHandles?[1].inOffset == CGPoint(x: 0, y: -20))
    }

    @Test func endpointHitIgnoresClosedCurvesAndPicksTheNearerEnd() {
        let curve = Self.arch()
        let start = ShapeGeometry.openCurveEndpoint(in: [curve], near: curve.points[0], radius: 12)
        #expect(start?.fromStart == true)
        #expect(start?.stroke.id == curve.id)

        let end = ShapeGeometry.openCurveEndpoint(in: [curve], near: curve.points[2], radius: 12)
        #expect(end?.fromStart == false)

        #expect(ShapeGeometry.openCurveEndpoint(in: [curve], near: CGPoint(x: 0, y: 60), radius: 12) == nil)

        var closed = curve
        closed.isClosed = true
        #expect(ShapeGeometry.openCurveEndpoint(in: [closed], near: curve.points[0], radius: 12) == nil)
    }

    @Test func undoStopsAtTheSeededCurve() {
        let session = CurveDraftSession()
        let seeded = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)]
        session.beginContinuation(
            strokeID: UUID(),
            anchors: seeded,
            handles: [CurveHandle(), CurveHandle()],
            reversed: false
        )
        #expect(!session.canUndo)
        #expect(session.makeFinish() == nil)

        session.appendSegment(
            start: CGPoint(x: 40, y: 0),
            end: CGPoint(x: 80, y: 20),
            connectTolerance: 1
        )
        #expect(session.canUndo)
        #expect(session.makeFinish()?.anchors.count == 3)

        #expect(session.performUndo())
        #expect(session.anchors == seeded)
        #expect(!session.canUndo)
        #expect(session.makeFinish() == nil)
        #expect(!session.performUndo())

        #expect(session.performRedo())
        #expect(session.anchors.count == 3)
        #expect(session.continuationStrokeID != nil)
    }
}
