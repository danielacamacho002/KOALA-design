import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

/// Anchor edits on an `.arc`. An arc renders from the circle through its
/// (first, middle, last) anchors plus a sweep walked across the anchor chain, so anchors
/// that stop being co-circular render as geometry unrelated to the handles. Every edit
/// here must leave the arc a true circular arc.
@MainActor
struct ArcAnchorEditingTests {
    private static let radius: CGFloat = 100

    /// A 300°-ish arc, produced the way the reported bug was: trim the overlap out of one
    /// of two overlapping circles.
    private static func trimmedArc() -> VectorStroke? {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        document.strokes = [
            VectorStroke(
                layerID: layerID,
                points: ShapeGeometry.circleCardinalPoints(center: .zero, radius: radius),
                isClosed: true,
                shapeType: .circle
            ),
            VectorStroke(
                layerID: layerID,
                points: ShapeGeometry.circleCardinalPoints(
                    center: CGPoint(x: 120, y: 0), radius: radius
                ),
                isClosed: true,
                shapeType: .circle
            )
        ]
        let tap = CGPoint(x: cos(15 * .pi / 180) * radius, y: sin(15 * .pi / 180) * radius)
        guard document.trimAt(tap, threshold: 3) else { return nil }
        return document.strokes.first
    }

    /// Largest distance between the rendered curve and the circle the stroke itself implies.
    private static func maxDeviationFromOwnCircle(_ stroke: VectorStroke) -> CGFloat? {
        guard let circle = ShapeGeometry.arcCircle(for: stroke) else { return nil }
        var worst: CGFloat = 0
        for point in ShapeGeometry.renderPoints(for: stroke) {
            let distance = hypot(point.x - circle.center.x, point.y - circle.center.y)
            worst = max(worst, abs(distance - circle.radius))
        }
        return worst
    }

    private static func sweepDegrees(_ stroke: VectorStroke) -> CGFloat? {
        guard let circle = ShapeGeometry.arcCircle(for: stroke),
              let sweep = ShapeGeometry.signedCircularSweep(
                of: ShapeGeometry.renderPoints(for: stroke),
                around: circle.center
              ) else { return nil }
        return sweep * 180 / .pi
    }

    @Test func trimLeavesAMajorArc() throws {
        let arc = try #require(Self.trimmedArc())
        #expect(arc.shapeType == .arc)
        #expect(!arc.isClosed)
        let sweep = try #require(Self.sweepDegrees(arc))
        #expect(sweep > 180, "expected a major arc, got \(sweep)°")
    }

    /// Dragging any single anchor must reshape the arc, never decouple the rendered curve
    /// from the anchors. This is what collapsed before: the render was refitted from three
    /// anchors while the rest stayed put, so the drawn shape had nothing to do with them.
    @Test func draggingAnySingleAnchorKeepsTheArcCircular() throws {
        let arc = try #require(Self.trimmedArc())
        let handles = ShapeGeometry.handlePoints(for: arc)
        #expect(handles.count >= 3)

        for index in handles.indices {
            for delta in [CGPoint(x: 12, y: -8), CGPoint(x: 250, y: -150)] {
                let moved = ShapeGeometry.applyingMovedAnchors(
                    arc,
                    moves: [index: CGPoint(x: handles[index].x + delta.x,
                                           y: handles[index].y + delta.y)]
                )
                #expect(moved.shapeType == .arc)
                let deviation = try #require(Self.maxDeviationFromOwnCircle(moved))
                #expect(deviation < 0.01,
                        "anchor \(index) delta \(delta): render strays \(deviation) from its own circle")
            }
        }
    }

    /// Moving every anchor by one delta is a translation, so the arc must come out
    /// congruent — same sweep and radius, centre shifted. Applying the anchors one at a
    /// time used to refit the arc mid-way and shrink a 307° arc to 166°.
    @Test func movingEveryAnchorTranslatesTheArc() throws {
        let arc = try #require(Self.trimmedArc())
        let before = try #require(ShapeGeometry.arcCircle(for: arc))
        let beforeSweep = try #require(Self.sweepDegrees(arc))

        let handles = ShapeGeometry.handlePoints(for: arc)
        let delta = CGPoint(x: 250, y: -150)
        var moves: [Int: CGPoint] = [:]
        for index in handles.indices {
            moves[index] = CGPoint(x: handles[index].x + delta.x, y: handles[index].y + delta.y)
        }

        let moved = ShapeGeometry.applyingMovedAnchors(arc, moves: moves)
        let after = try #require(ShapeGeometry.arcCircle(for: moved))
        let afterSweep = try #require(Self.sweepDegrees(moved))

        #expect(abs(afterSweep - beforeSweep) < 0.5,
                "sweep changed from \(beforeSweep)° to \(afterSweep)°")
        #expect(abs(after.radius - before.radius) < 0.01)
        #expect(abs(after.center.x - (before.center.x + delta.x)) < 0.01)
        #expect(abs(after.center.y - (before.center.y + delta.y)) < 0.01)
    }

    /// Nudging an interior anchor changes the radius but must not flip a major arc to the
    /// short way round — the failure mode when the sweep is read from three points only.
    @Test func nudgingAnInteriorAnchorKeepsTheArcMajor() throws {
        let arc = try #require(Self.trimmedArc())
        let handles = ShapeGeometry.handlePoints(for: arc)
        let interior = handles.count / 2
        let circle = try #require(ShapeGeometry.arcCircle(for: arc))

        // Push it 5 units further out along its own radius.
        let anchor = handles[interior]
        let length = hypot(anchor.x - circle.center.x, anchor.y - circle.center.y)
        let nudged = CGPoint(
            x: circle.center.x + (anchor.x - circle.center.x) / length * (length + 5),
            y: circle.center.y + (anchor.y - circle.center.y) / length * (length + 5)
        )

        let moved = ShapeGeometry.applyingMovedAnchors(arc, moves: [interior: nudged])
        let sweep = try #require(Self.sweepDegrees(moved))
        #expect(sweep > 180, "major arc flipped to \(sweep)°")
        let movedCircle = try #require(ShapeGeometry.arcCircle(for: moved))
        #expect(movedCircle.radius > circle.radius, "radius should grow when pushed outward")
    }

    /// A drag that makes the three defining points collinear has no circle through them.
    /// The arc is left alone rather than storing anchors the renderer cannot interpret.
    @Test func collinearDragLeavesTheArcUntouched() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: -100, y: 0),
                CGPoint(x: 0, y: 100),
                CGPoint(x: 100, y: 0)
            ],
            isClosed: false,
            shapeType: .arc
        )
        // Drop the middle anchor onto the straight line joining the endpoints.
        let moved = ShapeGeometry.applyingMovedAnchors(stroke, moves: [1: CGPoint(x: 0, y: 0)])
        #expect(moved == stroke)
        #expect(ShapeGeometry.updateArcHandles(stroke, moves: [1: CGPoint(x: 0, y: 0)]) == nil)
    }
}
