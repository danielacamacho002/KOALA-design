import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct CircularAnchorCompactorTests {
    // `nonisolated` because both are used as default argument values below, which are
    // evaluated outside the suite's MainActor isolation (a hard error in Swift 6 mode).
    private nonisolated static let radius: CGFloat = 100
    private nonisolated static let center = CGPoint(x: 0, y: 0)

    private static func onCircle(
        _ degrees: CGFloat,
        center: CGPoint = center,
        radius: CGFloat = radius
    ) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }

    /// Sweep the renderer recovers from a stroke's stored anchors, in degrees.
    private static func renderedSweepDegrees(_ stroke: VectorStroke) -> CGFloat? {
        let points = ShapeGeometry.renderPoints(for: stroke)
        guard let circle = ShapeGeometry.arcCircle(for: stroke),
              let sweep = ShapeGeometry.signedCircularSweep(of: points, around: circle.center)
        else { return nil }
        return sweep * 180 / .pi
    }

    // MARK: - Anchor round trip

    /// Anchors are the only record of an arc's sweep, and sweep recovery resolves each
    /// anchor step to the shorter arc. Any gap of half a turn or more is therefore
    /// unrecoverable, so the emitted anchors must stay closer together than that.
    @Test func anchorsNeverLeaveAGapOfHalfATurn() {
        for startDegrees in stride(from: CGFloat(0), to: 360, by: 7) {
            for sweepDegrees in stride(from: CGFloat(5), through: 355, by: 5) {
                let start = Self.onCircle(startDegrees)
                let end = Self.onCircle(startDegrees + sweepDegrees)
                let anchors = ShapeGeometry.defaultCircularAnchors(
                    center: Self.center,
                    radius: Self.radius,
                    start: start,
                    end: end,
                    sweep: sweepDegrees * .pi / 180,
                    closed: false
                )
                let recovered = ShapeGeometry.signedCircularSweep(
                    of: anchors,
                    around: Self.center
                )
                #expect(recovered != nil)
                let degrees = (recovered ?? 0) * 180 / .pi
                #expect(
                    abs(degrees - sweepDegrees) < 0.5,
                    "start \(startDegrees)° sweep \(sweepDegrees)° recovered \(degrees)°"
                )
            }
        }
    }

    /// A 350° arc used to come back as a -10° sliver: only the first two interior
    /// cardinals were kept, leaving a 190° gap to the end anchor.
    @Test func nearlyFullSweepSurvivesAnchorRoundTrip() {
        let anchors = ShapeGeometry.defaultCircularAnchors(
            center: Self.center,
            radius: Self.radius,
            start: Self.onCircle(20),
            end: Self.onCircle(370),
            sweep: 350 * .pi / 180,
            closed: false
        )
        let recovered = ShapeGeometry.signedCircularSweep(of: anchors, around: Self.center)
        #expect(((recovered ?? 0) * 180 / .pi - 350).magnitude < 0.5)
    }

    /// Small sweeps keep the compact default (endpoints plus one midpoint) so trimming
    /// a quadrant does not stamp extra anchors onto the leftover.
    @Test func quarterSweepKeepsThreeAnchors() {
        let anchors = ShapeGeometry.defaultCircularAnchors(
            center: Self.center,
            radius: Self.radius,
            start: Self.onCircle(0),
            end: Self.onCircle(90),
            sweep: 90 * .pi / 180,
            closed: false
        )
        #expect(anchors.count == 3)
    }

    /// A full sweep still collapses to the four cardinal anchors of a circle.
    @Test func fullSweepReturnsFourCardinals() {
        let anchors = ShapeGeometry.defaultCircularAnchors(
            center: Self.center,
            radius: Self.radius,
            start: Self.onCircle(0),
            end: Self.onCircle(0),
            sweep: 2 * .pi,
            closed: false
        )
        #expect(anchors == ShapeGeometry.circleCardinalPoints(center: Self.center, radius: Self.radius))
    }

    // MARK: - Trim leftover

    /// Circle B crosses circle A at 24° and 84°, so trimming the overlap out of A
    /// leaves the 300° major arc. That leftover must keep its sweep through the anchor
    /// re-compaction that starts every move drag, and through the move itself.
    @Test func trimmedMajorArcKeepsItsSweepAcrossAMove() throws {
        let layerID = UUID()
        let circleA = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.circleCardinalPoints(center: Self.center, radius: Self.radius),
            isClosed: true,
            shapeType: .circle
        )
        let centerB = CGPoint(x: 86.1708, y: 118.6039)
        let circleB = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.circleCardinalPoints(center: centerB, radius: 78.1025),
            isClosed: true,
            shapeType: .circle
        )

        let result = try #require(
            TrimEngine.trim(
                at: Self.onCircle(54),
                threshold: 2,
                strokes: [circleA, circleB]
            )
        )
        #expect(result.strokeID == circleA.id)
        #expect(result.additionalStroke == nil)

        let leftover = result.stroke
        #expect(leftover.shapeType == .arc)
        #expect(!leftover.isClosed)

        let trimmedSweep = try #require(Self.renderedSweepDegrees(leftover))
        #expect(abs(trimmedSweep - 300) < 2, "trim leftover swept \(trimmedSweep)°")

        // `beginInteractiveEdit()` re-compacts anchors before a drag applies any delta.
        let compacted = ShapeGeometry.withCompactedCircularAnchors(leftover)
        let compactedSweep = try #require(Self.renderedSweepDegrees(compacted))
        #expect(abs(compactedSweep - 300) < 2, "after compaction swept \(compactedSweep)°")

        let moved = compacted.offsettingGeometry(by: CGPoint(x: 250, y: -175))
        let movedSweep = try #require(Self.renderedSweepDegrees(moved))
        #expect(abs(movedSweep - 300) < 2, "after move swept \(movedSweep)°")

        // The moved leftover must still be the same circle, just translated.
        let movedCircle = try #require(ShapeGeometry.arcCircle(for: moved))
        #expect(abs(movedCircle.radius - Self.radius) < 0.5)
        #expect(abs(movedCircle.center.x - 250) < 0.5)
        #expect(abs(movedCircle.center.y + 175) < 0.5)
    }
}
