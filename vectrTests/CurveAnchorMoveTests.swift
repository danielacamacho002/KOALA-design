import CoreGraphics
import Foundation
import Testing
@testable import vectr

/// Dragging an anchor of a `.curve` is a reshape, not a conversion to corners.
/// `CurveHandle` stores its tangents as offsets from the anchor, so a moved anchor has to
/// carry them along; clearing them collapses the neighbouring segments into straight chords.
@MainActor
struct CurveAnchorMoveTests {
    private static func renderedLength(_ stroke: VectorStroke) -> CGFloat {
        let points = ShapeGeometry.renderPoints(for: stroke)
        guard points.count >= 2 else { return 0 }
        let segments = stroke.isClosed ? points.count : points.count - 1
        var total: CGFloat = 0
        for index in 0..<segments {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            total += hypot(b.x - a.x, b.y - a.y)
        }
        return total
    }

    /// The same stroke with every tangent zeroed — what the anchors alone would render as.
    private static func flattened(_ stroke: VectorStroke) -> VectorStroke {
        var copy = stroke
        copy.curveHandles = stroke.points.map { _ in CurveHandle() }
        return copy
    }

    /// An open arch: three anchors whose tangents bow both segments well clear of their chords.
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
        var start = CurveHandle()
        var middle = CurveHandle()
        var end = CurveHandle()
        start.outOffset = CGPoint(x: 0, y: 90)
        middle.inOffset = CGPoint(x: -60, y: 0)
        middle.outOffset = CGPoint(x: 60, y: 0)
        end.inOffset = CGPoint(x: 0, y: 90)
        stroke.curveHandles = [start, middle, end]
        return stroke
    }

    /// A closed lens: two anchors whose segments bow to opposite sides.
    private static func lens() -> VectorStroke {
        var stroke = VectorStroke(
            layerID: UUID(),
            points: [CGPoint(x: 0, y: 80), CGPoint(x: 0, y: -80)],
            isClosed: true,
            shapeType: .curve
        )
        var top = CurveHandle()
        var bottom = CurveHandle()
        top.outOffset = CGPoint(x: 60, y: 0)
        bottom.inOffset = CGPoint(x: 60, y: 0)
        bottom.outOffset = CGPoint(x: -60, y: 0)
        top.inOffset = CGPoint(x: -60, y: 0)
        stroke.curveHandles = [top, bottom]
        return stroke
    }

    @Test func movingAnInteriorAnchorKeepsTheSegmentsCurved() {
        let curve = Self.arch()
        let moved = ShapeGeometry.applyingMovedAnchors(curve, moves: [1: CGPoint(x: 0, y: 200)])

        #expect(moved.points[1] == CGPoint(x: 0, y: 200))
        #expect(moved.points[0] == curve.points[0])
        #expect(moved.points[2] == curve.points[2])
        #expect(moved.curveHandles == curve.curveHandles)
        #expect(Self.renderedLength(moved) > Self.renderedLength(Self.flattened(moved)) + 5)
    }

    @Test func movingAnEndpointKeepsTheSegmentCurved() {
        let curve = Self.arch()
        let moved = ShapeGeometry.applyingMovedAnchors(curve, moves: [0: CGPoint(x: -220, y: -40)])

        #expect(moved.curveHandles == curve.curveHandles)
        #expect(Self.renderedLength(moved) > Self.renderedLength(Self.flattened(moved)) + 5)
    }

    @Test func movingOneAnchorOfAClosedCurveKeepsBothSegmentsCurved() {
        let curve = Self.lens()
        let moved = ShapeGeometry.applyingMovedAnchors(curve, moves: [0: CGPoint(x: 0, y: 160)])

        #expect(moved.isClosed)
        #expect(moved.curveHandles == curve.curveHandles)
        #expect(Self.renderedLength(moved) > Self.renderedLength(Self.flattened(moved)) + 5)
    }
}
