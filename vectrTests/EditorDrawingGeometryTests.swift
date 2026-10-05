import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct EditorDrawingGeometryTests {
    private let start = CGPoint(x: 10, y: 20)
    private let end = CGPoint(x: 40, y: 60)

    private func dragPoints(
        _ category: ToolCategory?,
        circle: CircleVariant = .center,
        rectangle: RectangleVariant = .center
    ) -> [CGPoint] {
        EditorDrawingGeometry.dragControlPoints(
            category: category,
            circleVariant: circle,
            rectangleVariant: rectangle,
            start: start,
            end: end
        )
    }

    @Test func edgeVariantsPassTheDragEndpointsThrough() {
        #expect(dragPoints(.line) == [start, end])
        #expect(dragPoints(.circle, circle: .center) == [start, end])
        #expect(dragPoints(.circle, circle: .edge) == [start, end])
        #expect(dragPoints(.rectangle, rectangle: .edge) == [start, end])
    }

    @Test func ellipseDragBecomesCenterPlusTwoAxisExtents() {
        #expect(dragPoints(.circle, circle: .ellipse) == [
            start,
            CGPoint(x: 40, y: 20),
            CGPoint(x: 10, y: 60)
        ])
    }

    @Test func centerRectangleDragBecomesCenterPlusTwoHalfExtents() {
        #expect(dragPoints(.rectangle, rectangle: .center) == [
            start,
            CGPoint(x: 40, y: 20),
            CGPoint(x: 10, y: 60)
        ])
    }

    /// A drag that never leaves the start point must still describe a shape with
    /// non-zero extents, or the builder produces a degenerate stroke.
    @Test func zeroLengthDragKeepsNonZeroExtents() {
        let points = EditorDrawingGeometry.dragControlPoints(
            category: .circle,
            circleVariant: .ellipse,
            rectangleVariant: .center,
            start: start,
            end: start
        )
        #expect(points.count == 3)
        #expect(points[1].x > points[0].x)
        #expect(points[2].y > points[0].y)
    }

    @Test func nonDragCategoriesProduceNoControlPoints() {
        #expect(dragPoints(.curve).isEmpty)
        #expect(dragPoints(.move).isEmpty)
        #expect(dragPoints(nil).isEmpty)
    }

    @Test func nonArcShapesAlwaysAllowTheClosingEdgeFallback() {
        let rectangle = VectorStroke(
            layerID: UUID(),
            points: ShapeGeometry.rectangleFromCorners(start, end),
            isClosed: true,
            shapeType: .rectangle
        )
        #expect(EditorDrawingGeometry.closingEdgeFallbackAllowed(rectangle, edgeIndex: 0))
        #expect(EditorDrawingGeometry.closingEdgeFallbackAllowed(rectangle, edgeIndex: 3))
    }

    /// An arc stores start/mid/end, so only the implied closing chord may be dropped.
    /// Cutting an interior edge would reorder the anchors and flip the arc.
    @Test func closedArcOnlyAllowsTheClosingChord() {
        let arc = VectorStroke(
            layerID: UUID(),
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 0)],
            isClosed: true,
            shapeType: .arc
        )
        #expect(EditorDrawingGeometry.closingEdgeFallbackAllowed(arc, edgeIndex: 2))
        #expect(!EditorDrawingGeometry.closingEdgeFallbackAllowed(arc, edgeIndex: 0))
        #expect(!EditorDrawingGeometry.closingEdgeFallbackAllowed(arc, edgeIndex: 1))
    }

    @Test func openArcNeverAllowsTheFallback() {
        let arc = VectorStroke(
            layerID: UUID(),
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 0)],
            isClosed: false,
            shapeType: .arc
        )
        for index in 0..<3 {
            #expect(!EditorDrawingGeometry.closingEdgeFallbackAllowed(arc, edgeIndex: index))
        }
    }
}
