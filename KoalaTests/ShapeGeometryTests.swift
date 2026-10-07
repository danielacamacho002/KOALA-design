import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Koala

@MainActor
struct ShapeGeometryTests {
    private let layerID = UUID()

    private func expectClose(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 1e-6, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a.x - b.x) < tolerance, "x: \(a.x) vs \(b.x)", sourceLocation: sourceLocation)
        #expect(abs(a.y - b.y) < tolerance, "y: \(a.y) vs \(b.y)", sourceLocation: sourceLocation)
    }

    // MARK: - Control point contracts

    /// The command bar counts prompts off this, so a mismatch strands the user
    /// mid-shape or commits early.
    @Test func requiredControlPointsMatchEachVariant() {
        func required(_ category: ToolCategory, line: LineVariant = .line, circle: CircleVariant = .center, rect: RectangleVariant = .center) -> Int {
            ShapeGeometry.requiredControlPoints(
                category: category,
                lineVariant: line,
                circleVariant: circle,
                rectangleVariant: rect
            )
        }
        #expect(required(.line) == 2)
        #expect(required(.line, line: .arc) == 3)
        #expect(required(.circle, circle: .center) == 2)
        #expect(required(.circle, circle: .ellipse) == 3)
        #expect(required(.rectangle, rect: .center) == 3)
        #expect(required(.rectangle, rect: .edge) == 2)
        #expect(required(.move) == 0)
    }

    /// Reopening a shape in the command bar must hand back control points that
    /// rebuild the same geometry, or editing silently moves the shape.
    @Test func circleControlPointsRoundTripThroughTheBuilder() throws {
        let original = try #require(ShapeGeometry.buildStroke(
            controlPoints: [CGPoint(x: 50, y: 40), CGPoint(x: 70, y: 40)],
            category: .circle,
            lineVariant: .line,
            circleVariant: .center,
            rectangleVariant: .center,
            layerID: layerID,
            strokeWidth: 1.5,
            strokeColor: CodableColor(.primary),
            closed: true
        ))
        let controls = try #require(ShapeGeometry.controlPoints(
            from: original,
            category: .circle,
            lineVariant: .line,
            circleVariant: .center,
            rectangleVariant: .center
        ))
        let rebuilt = try #require(ShapeGeometry.buildStroke(
            controlPoints: controls,
            category: .circle,
            lineVariant: .line,
            circleVariant: .center,
            rectangleVariant: .center,
            layerID: layerID,
            strokeWidth: 1.5,
            strokeColor: CodableColor(.primary),
            closed: true
        ))
        #expect(rebuilt.points == original.points)
    }

    @Test func ellipseControlPointsRoundTripThroughTheBuilder() throws {
        let controls = [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 0, y: 10)]
        let original = try #require(ShapeGeometry.buildStroke(
            controlPoints: controls,
            category: .circle,
            lineVariant: .line,
            circleVariant: .ellipse,
            rectangleVariant: .center,
            layerID: layerID,
            strokeWidth: 1.5,
            strokeColor: CodableColor(.primary),
            closed: true
        ))
        #expect(original.shapeType == .ellipse)
        let recovered = try #require(ShapeGeometry.controlPoints(
            from: original,
            category: .circle,
            lineVariant: .line,
            circleVariant: .ellipse,
            rectangleVariant: .center
        ))
        #expect(recovered == controls)
    }

    // MARK: - Cardinal point round trips

    @Test func circleCardinalsRoundTripToCenterAndRadius() throws {
        let center = CGPoint(x: -12.5, y: 7.25)
        let points = ShapeGeometry.circleCardinalPoints(center: center, radius: 9)
        let circle = try #require(ShapeGeometry.circleFromCardinalPoints(points))
        expectClose(circle.center, center)
        #expect(abs(circle.radius - 9) < 1e-9)
    }

    @Test func ellipseCardinalsRoundTripToCenterAndRadii() throws {
        let center = CGPoint(x: 4, y: -3)
        let points = ShapeGeometry.ellipseCardinalPoints(center: center, rx: 20, ry: 5)
        let ellipse = try #require(ShapeGeometry.ellipseFromCardinalPoints(points))
        expectClose(ellipse.center, center)
        #expect(abs(ellipse.rx - 20) < 1e-9)
        #expect(abs(ellipse.ry - 5) < 1e-9)
    }

    /// A degenerate circle has no meaningful center, so callers must get nil rather
    /// than a zero-radius shape they would go on to render.
    @Test func degenerateCardinalsAreRejected() {
        let collapsed = [CGPoint](repeating: CGPoint(x: 5, y: 5), count: 4)
        #expect(ShapeGeometry.circleFromCardinalPoints(collapsed) == nil)
        #expect(ShapeGeometry.ellipseFromCardinalPoints(collapsed) == nil)
        #expect(ShapeGeometry.circleFromCardinalPoints([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]) == nil)
    }

    /// Cardinals stay axis-aligned under `ellipseAxes`, but the reported rotation
    /// tracks the stored first-axis direction.
    @Test func ellipseAxesReportTheAxisAngle() throws {
        let axes = try #require(ShapeGeometry.ellipseAxes(from: ShapeGeometry.orientedCardinalPoints(
            center: .zero,
            rx: 10,
            ry: 4,
            rotation: .pi / 2
        )))
        #expect(abs(axes.rx - 10) < 1e-6)
        #expect(abs(axes.ry - 4) < 1e-6)
        #expect(abs(axes.rotation - .pi / 2) < 1e-6)
    }

    // MARK: - Rectangles

    @Test func rectangleFromCornersNormalizesADraggedDiagonal() {
        let forward = ShapeGeometry.rectangleFromCorners(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5))
        let backward = ShapeGeometry.rectangleFromCorners(CGPoint(x: 10, y: 5), CGPoint(x: 0, y: 0))
        #expect(forward == backward)
        #expect(forward.count == 4)
        #expect(forward[0] == CGPoint(x: 0, y: 0))
        #expect(forward[2] == CGPoint(x: 10, y: 5))
    }

    @Test func rectangleFromCenterDistancesIsCenteredAndClockwise() {
        let points = ShapeGeometry.rectangleFromCenterDistances(CGPoint(x: 5, y: 5), halfWidth: 3, halfHeight: 2)
        #expect(points == [
            CGPoint(x: 2, y: 3),
            CGPoint(x: 8, y: 3),
            CGPoint(x: 8, y: 7),
            CGPoint(x: 2, y: 7)
        ])
    }

    // MARK: - Rotation

    @Test func normalizedRotationWrapsIntoZeroToThreeSixty() {
        #expect(abs(ShapeGeometry.normalizedRotationDegrees(.pi / 2) - 90) < 1e-9)
        #expect(abs(ShapeGeometry.normalizedRotationDegrees(-.pi / 2) - 270) < 1e-9)
        #expect(abs(ShapeGeometry.normalizedRotationDegrees(5 * .pi) - 180) < 1e-9)
        #expect(ShapeGeometry.normalizedRotationDegrees(0) == 0)
    }

    @Test func rotatingByFullTurnsRestoresTheOriginalPoints() {
        let points = [CGPoint(x: 1, y: 0), CGPoint(x: 3, y: 4), CGPoint(x: -2, y: 7)]
        let rotated = ShapeGeometry.rotatePoints(points, around: CGPoint(x: 2, y: 2), by: 2 * .pi)
        for (original, result) in zip(points, rotated) {
            expectClose(original, result, tolerance: 1e-9)
        }
    }

    /// Circles rotate by moving their center, not by spinning their cardinals, so
    /// the radius must survive untouched.
    @Test func rotatingACircleMovesTheCenterAndKeepsTheRadius() throws {
        let stroke = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.circleCardinalPoints(center: CGPoint(x: 10, y: 0), radius: 4),
            isClosed: true,
            shapeType: .circle
        )
        let rotated = ShapeGeometry.rotatedStroke(stroke, around: .zero, by: .pi / 2)
        let circle = try #require(ShapeGeometry.circleFromCardinalPoints(rotated.points))
        expectClose(circle.center, CGPoint(x: 0, y: 10), tolerance: 1e-6)
        #expect(abs(circle.radius - 4) < 1e-6)
    }

    /// The first rotation captures the un-rotated geometry so later absolute-angle
    /// edits have a base to measure against; it must not be recaptured afterwards.
    @Test func rotationBaseIsCapturedOnceAndThenLeftAlone() {
        let stroke = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        )
        #expect(stroke.rotationBasePoints == nil)

        let first = ShapeGeometry.rotatedStroke(stroke, around: .zero, by: .pi / 4)
        #expect(first.rotationBasePoints == stroke.points)

        let second = ShapeGeometry.rotatedStroke(first, around: .zero, by: .pi / 4)
        #expect(second.rotationBasePoints == stroke.points)
    }

    @Test func absoluteRotationIsIdempotent() {
        let stroke = ShapeGeometry.rotatedStroke(
            VectorStroke(layerID: layerID, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]),
            around: .zero,
            by: .pi / 3
        )
        let target = ShapeGeometry.strokeWithAbsoluteRotation(stroke, radians: .pi / 3, around: .zero)
        #expect(target.points == stroke.points)
    }

    // MARK: - Shape center

    @Test func shapeCenterUsesGeometryNotBoundsForCurvedShapes() throws {
        let circle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.circleCardinalPoints(center: CGPoint(x: 8, y: -3), radius: 6),
            isClosed: true,
            shapeType: .circle
        )
        expectClose(try #require(ShapeGeometry.shapeCenter(for: circle)), CGPoint(x: 8, y: -3))

        let rectangle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.rectangleFromCorners(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 4)),
            isClosed: true,
            shapeType: .rectangle
        )
        expectClose(try #require(ShapeGeometry.shapeCenter(for: rectangle)), CGPoint(x: 5, y: 2))
    }

    @Test func rotationPivotFallsBackToTheShapeCenterForAnOutOfRangeAnchor() throws {
        let rectangle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.rectangleFromCorners(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 4)),
            isClosed: true,
            shapeType: .rectangle
        )
        expectClose(try #require(ShapeGeometry.rotationPivot(for: rectangle, anchorIndex: 99)), CGPoint(x: 5, y: 2))
        expectClose(try #require(ShapeGeometry.rotationPivot(for: rectangle, anchorIndex: nil)), CGPoint(x: 5, y: 2))
    }

    // MARK: - Handle dragging

    @Test func draggingACircleHandleResizesAboutTheFixedCenter() throws {
        let center = CGPoint(x: 20, y: 20)
        let stroke = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.circleCardinalPoints(center: center, radius: 5),
            isClosed: true,
            shapeType: .circle
        )
        let points = ShapeGeometry.updateCircleHandle(at: 1, to: CGPoint(x: 32, y: 25), stroke: stroke)
        let circle = try #require(ShapeGeometry.circleFromCardinalPoints(points))
        expectClose(circle.center, center)
        #expect(abs(circle.radius - 12) < 1e-9)
    }

    /// Only the dragged axis may change; the other radius must hold.
    @Test func draggingAnEllipseHandleChangesOneAxisOnly() throws {
        let stroke = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.ellipseCardinalPoints(center: .zero, rx: 10, ry: 4),
            isClosed: true,
            shapeType: .ellipse
        )
        let points = ShapeGeometry.updateEllipseHandle(at: 0, to: CGPoint(x: 3, y: -9), stroke: stroke)
        let ellipse = try #require(ShapeGeometry.ellipseFromCardinalPoints(points))
        #expect(abs(ellipse.rx - 10) < 1e-9)
        #expect(abs(ellipse.ry - 9) < 1e-9)
    }

    /// A handle drag on the wrong shape type must be a no-op rather than silently
    /// converting the geometry.
    @Test func handleDragsIgnoreMismatchedShapeTypes() {
        let polyline = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 0), CGPoint(x: 1, y: -1)],
            isClosed: true
        )
        #expect(ShapeGeometry.updateCircleHandle(at: 0, to: CGPoint(x: 9, y: 9), stroke: polyline) == polyline.points)
        #expect(ShapeGeometry.updateEllipseHandle(at: 0, to: CGPoint(x: 9, y: 9), stroke: polyline) == polyline.points)
    }

    // MARK: - Quad edge editing

    @Test func onlyFourPointClosedQuadsAreEditable() {
        let rectangle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.rectangleFromCorners(.zero, CGPoint(x: 10, y: 4)),
            isClosed: true,
            shapeType: .rectangle
        )
        #expect(ShapeGeometry.isEditableQuad(rectangle))

        let openQuad = VectorStroke(
            layerID: layerID,
            points: rectangle.points,
            isClosed: false
        )
        #expect(!ShapeGeometry.isEditableQuad(openQuad))

        let triangle = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 2, y: 3)],
            isClosed: true
        )
        #expect(!ShapeGeometry.isEditableQuad(triangle))
    }

    /// The edge resizes about its own midpoint, so the opposite edge must not move.
    @Test func applyingAnEdgeLengthPinsTheOppositeEdge() throws {
        let rectangle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.rectangleFromCorners(.zero, CGPoint(x: 10, y: 4)),
            isClosed: true,
            shapeType: .rectangle
        )
        let updated = try #require(ShapeGeometry.applyEdgeLength(.top, newValue: 4, to: rectangle))
        expectClose(updated.points[0], CGPoint(x: 3, y: 0))
        expectClose(updated.points[1], CGPoint(x: 7, y: 0))
        #expect(updated.points[2] == rectangle.points[2])
        #expect(updated.points[3] == rectangle.points[3])
    }

    /// Once opposite edges differ the shape is no longer a rectangle, and keeping the
    /// type would let rectangle-only editing paths corrupt it.
    @Test func unevenEdgesDemoteARectangleToAPolyline() throws {
        let rectangle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.rectangleFromCorners(.zero, CGPoint(x: 10, y: 4)),
            isClosed: true,
            shapeType: .rectangle,
            shapeRotation: 0.5
        )
        let updated = try #require(ShapeGeometry.applyEdgeLength(.top, newValue: 4, to: rectangle))
        #expect(updated.shapeType == .polyline)
        #expect(updated.shapeRotation == nil)
        #expect(updated.rotationBasePoints == nil)
    }

    /// Setting an edge to the length it already has must not demote the shape —
    /// only a genuine mismatch with the opposite edge does.
    @Test func anEdgeThatStillMatchesItsOppositeKeepsTheRectangleType() throws {
        let rectangle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.rectangleFromCorners(.zero, CGPoint(x: 10, y: 4)),
            isClosed: true,
            shapeType: .rectangle
        )
        let updated = try #require(ShapeGeometry.applyEdgeLength(.top, newValue: 10, to: rectangle))
        #expect(updated.shapeType == .rectangle)
        #expect(updated.points == rectangle.points)
    }

    /// A demoted quad stays a polyline: the edit path no longer has matching
    /// opposite edges to promote it back.
    @Test func aDemotedQuadStaysAPolylineOnFurtherEdits() throws {
        let rectangle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.rectangleFromCorners(.zero, CGPoint(x: 10, y: 4)),
            isClosed: true,
            shapeType: .rectangle
        )
        let demoted = try #require(ShapeGeometry.applyEdgeLength(.top, newValue: 4, to: rectangle))
        let again = try #require(ShapeGeometry.applyEdgeLength(.bottom, newValue: 4, to: demoted))
        #expect(again.shapeType == .polyline)
        #expect(ShapeGeometry.isEditableQuad(again))
    }

    @Test func edgeLengthIsRejectedForNonQuads() {
        let line = VectorStroke(layerID: layerID, points: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0)])
        #expect(ShapeGeometry.applyEdgeLength(.top, newValue: 3, to: line) == nil)
    }
}
