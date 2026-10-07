import CoreGraphics
import Foundation
import Testing
@testable import Koala

/// Driven by the user's real reproduction document (`Fixtures/CircleTrimError.vectr`).
///
/// The fixture is read from the source tree via `#filePath` rather than a bundle resource:
/// simulator tests share the host filesystem, so this needs no Xcode project changes and
/// leaves no orphan project references.
@MainActor
struct CircleTrimErrorFixtureTests {
    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CircleTrimError.vectr")
    }

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

    private static func renderedBox(_ stroke: VectorStroke) -> CGRect {
        ShapeGeometry.renderPoints(for: stroke)
            .reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    // MARK: - The user's document

    /// Pins the representation the trim pipeline actually produced, so a future change to
    /// trim/merge that alters it fails loudly here rather than silently in the canvas.
    @Test func userDocumentIsASingleMergedClosedPolyline() throws {
        let document = try DocumentCodec.read(from: Self.fixtureURL)

        #expect(document.strokes.count == 1)
        let stroke = try #require(document.strokes.first)
        #expect(stroke.shapeType == .polyline)
        #expect(stroke.isClosed)
        #expect(stroke.curveHandles == nil)
        #expect(stroke.cutoutPoints.isEmpty)
        // A merged trim result: parametric arcs are gone, so no circle can be fitted.
        #expect(ShapeGeometry.arcCircle(for: stroke) == nil)
    }

    // Deliberately no "moving this fixture preserves it" test: the saved shape is already
    // collapsed to 7 points, which compaction skips and translation cannot alter, so such
    // a test passes whether or not the bug is present. The erosion tests below reconstruct
    // the pre-collapse merged state, which is what actually exercises the fix.

    // MARK: - The mechanism that produced it

    private static func arcStroke(
        center: CGPoint, radius: CGFloat, startDeg: CGFloat, sweepDeg: CGFloat, layerID: UUID
    ) -> VectorStroke {
        let start = startDeg * .pi / 180
        let sweep = sweepDeg * .pi / 180
        func point(_ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        return VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.defaultCircularAnchors(
                center: center, radius: radius,
                start: point(start), end: point(start + sweep),
                sweep: sweep, closed: false
            ),
            isClosed: false,
            shapeType: .arc
        )
    }

    /// Mirrors `ClosedShapeDetector.mergeLoopPoints`: a trimmed loop is fused by
    /// concatenating each member's tessellated `renderPoints` into one closed `.polyline`
    /// with no smooth-corner data. This is the shape a trim actually leaves behind.
    private static func mergeArcChain(_ arcs: [VectorStroke], layerID: UUID) -> VectorStroke {
        var merged: [CGPoint] = []
        for arc in arcs {
            let points = ShapeGeometry.renderPoints(for: arc)
            if merged.isEmpty {
                merged.append(contentsOf: points)
            } else if let last = merged.last, let first = points.first,
                      hypot(last.x - first.x, last.y - first.y) <= 0.5 {
                merged.append(contentsOf: points.dropFirst())
            } else {
                merged.append(contentsOf: points)
            }
        }
        if let first = merged.first, let last = merged.last,
           hypot(first.x - last.x, first.y - last.y) <= 0.5 {
            merged.removeLast()
        }
        return VectorStroke(
            layerID: layerID, points: merged, isClosed: true, shapeType: .polyline
        )
    }

    /// A lens: two 106.26-degree arcs of radius 100 on circles 120 apart, meeting at
    /// (60, +/-80) — trimming two overlapping circles down to their overlap.
    private static func mergedLens() -> VectorStroke {
        let layerID = UUID()
        return mergeArcChain([
            arcStroke(center: .zero, radius: 100,
                      startDeg: 53.13, sweepDeg: -106.26, layerID: layerID),
            arcStroke(center: CGPoint(x: 120, y: 0), radius: 100,
                      startDeg: 233.13, sweepDeg: -106.26, layerID: layerID)
        ], layerID: layerID)
    }

    /// Compaction runs on every `beginInteractiveEdit()`, i.e. every drag start, so it has
    /// to be idempotent. It used to recover one dense arc per pass while straightening the
    /// arcs earlier passes had already compacted, so a merged trim result shed one curve
    /// every time the user grabbed it until only straight chords were left.
    @Test func repeatedDragStartsKeepEveryArcOfAMergedTrimResult() {
        var stroke = Self.mergedLens()
        let tessellatedLength = Self.renderedLength(stroke)
        // Both arcs straightened to chords would measure ~320; one straightened ~364.
        #expect(abs(tessellatedLength - 370.9) < 1.0)

        for pass in 1...8 {
            stroke = ShapeGeometry.withCompactedCircularAnchors(stroke)
            #expect(
                abs(Self.renderedLength(stroke) - tessellatedLength) < 1.5,
                Comment(rawValue: "pass \(pass) lost curvature: "
                    + "length \(Self.renderedLength(stroke)) vs \(tessellatedLength), "
                    + "pts=\(stroke.points.count) "
                    + "smooth=\(stroke.smoothCornerIndices.map { Array($0).sorted() } ?? [])")
            )
        }

        // Fully compacted, both arcs still curved, and stable against further passes.
        #expect(stroke.points.count <= 6)
        #expect((stroke.smoothCornerIndices?.count ?? 0) >= 2)
        let again = ShapeGeometry.withCompactedCircularAnchors(stroke)
        #expect(again.points == stroke.points)
        #expect(again.smoothCornerIndices == stroke.smoothCornerIndices)
    }

    /// The same erosion seen end-to-end: compact, translate, compact again, as the canvas
    /// does across two successive drags.
    @Test func mergedTrimResultSurvivesTwoSuccessiveDrags() {
        let document = KoalaDocument()
        var lens = Self.mergedLens()
        lens.layerID = document.activeLayerID
        document.strokes = [lens]
        let expected = Self.renderedLength(lens)

        for _ in 0..<2 {
            document.selectedStrokeIDs = [lens.id]
            document.selectedStrokeID = lens.id
            document.selectedAnchorIndices = []
            document.beginInteractiveEdit()
            guard let current = document.stroke(with: lens.id) else { break }
            document.updateStroke(
                current.offsettingGeometry(by: CGPoint(x: 40, y: 25)), recordUndo: false
            )
        }

        let moved = document.stroke(with: lens.id)
        #expect(moved != nil)
        #expect(abs(Self.renderedLength(moved ?? lens) - expected) < 1.5)
    }
}
