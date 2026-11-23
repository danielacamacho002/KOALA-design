import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

/// Trim removes one span from a contour, so a filleted shape must come back with every
/// corner it did not cut still rounded. Live fillets are a modifier on sharp points, so
/// the trim has to bake them into anchors first — otherwise the leftover is a plain
/// polyline and the whole shape loses its rounding.
@MainActor
struct FilletedTrimTests {
    private static let radius: CGFloat = 12

    /// Corners of the test rectangle, in stored order.
    private static let corners = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 60),
        CGPoint(x: 0, y: 60)
    ]

    private static func rectangle(layerID: UUID, cornerRadius: CGFloat = 0) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: corners,
            isClosed: true,
            cornerRadius: cornerRadius,
            shapeType: .rectangle
        )
    }

    /// The point on a 90° fillet arc closest to the corner it replaces: the corner pulled
    /// `radius * (√2 - 1)` along the bisector toward the rectangle's interior.
    private static func filletArcMidpoint(cornerIndex: Int, radius: CGFloat = radius) -> CGPoint {
        let corner = corners[cornerIndex]
        let prev = corners[(cornerIndex + corners.count - 1) % corners.count]
        let next = corners[(cornerIndex + 1) % corners.count]
        let toPrev = CGPoint(x: prev.x - corner.x, y: prev.y - corner.y)
        let toNext = CGPoint(x: next.x - corner.x, y: next.y - corner.y)
        let bisector = CGPoint(
            x: toPrev.x / hypot(toPrev.x, toPrev.y) + toNext.x / hypot(toNext.x, toNext.y),
            y: toPrev.y / hypot(toPrev.x, toPrev.y) + toNext.y / hypot(toNext.x, toNext.y)
        )
        let length = hypot(bisector.x, bisector.y)
        let offset = radius * (sqrt(2) - 1)
        return CGPoint(
            x: corner.x + bisector.x / length * offset,
            y: corner.y + bisector.y / length * offset
        )
    }

    /// Tapping the top edge of a fully filleted rectangle drops that edge between the two
    /// fillet tangent points. All four rounded corners have to survive.
    @Test func trimmingOneEdgeKeepsEveryFilletOnTheRest() throws {
        let rect = Self.rectangle(layerID: UUID(), cornerRadius: Self.radius)

        let result = try #require(
            TrimEngine.trim(at: CGPoint(x: 50, y: 0), threshold: 2, strokes: [rect])
        )
        #expect(result.strokeID == rect.id)
        #expect(result.additionalStroke == nil)

        let leftover = ShapeGeometry.withCompactedCircularAnchors(result.stroke)
        #expect(!leftover.isClosed)

        // The tapped span is gone.
        #expect(leftover.distance(to: CGPoint(x: 50, y: 0)) > 5)

        for index in Self.corners.indices {
            let corner = Self.corners[index]
            #expect(
                leftover.distance(to: Self.filletArcMidpoint(cornerIndex: index)) < 0.6,
                "corner \(index) lost its fillet arc"
            )
            #expect(
                leftover.distance(to: corner) > 2,
                "corner \(index) came back sharp"
            )
        }
    }

    /// A second trim works on the already-baked leftover, where the fillets live in
    /// `smoothCornerIndices` rather than a radius. Cutting the opposite edge must still
    /// keep every rounded corner, now spread across the two surviving pieces.
    @Test func trimmingTheLeftoverAgainKeepsTheRemainingFillets() throws {
        let layerID = UUID()
        let rect = Self.rectangle(layerID: layerID, cornerRadius: Self.radius)

        let first = try #require(
            TrimEngine.trim(at: CGPoint(x: 50, y: 0), threshold: 2, strokes: [rect])
        )
        let onceTrimmed = ShapeGeometry.withCompactedCircularAnchors(first.stroke)

        let second = try #require(
            TrimEngine.trim(at: CGPoint(x: 50, y: 60), threshold: 2, strokes: [onceTrimmed])
        )
        let pieces = [second.stroke, try #require(second.additionalStroke)]
            .map { ShapeGeometry.withCompactedCircularAnchors($0) }

        for index in Self.corners.indices {
            let arcMidpoint = Self.filletArcMidpoint(cornerIndex: index)
            #expect(
                pieces.contains { $0.distance(to: arcMidpoint) < 0.6 },
                "corner \(index) lost its fillet arc on the second trim"
            )
        }
        // The bottom edge is gone from both pieces.
        #expect(pieces.allSatisfy { $0.distance(to: CGPoint(x: 50, y: 60)) > 5 })
    }

    // MARK: - The trim tool's tap chain

    /// The editor tries the anchor delete first, then the trim, then the edge-delete
    /// fallback. Returns which branch took the tap.
    private static func trimTap(
        _ document: KoalaDocument,
        at point: CGPoint,
        threshold: CGFloat
    ) -> String {
        if document.deleteStrokeAnchor(near: point, threshold: threshold) { return "anchor" }
        if document.trimRemovalPreview(at: point, threshold: threshold) != nil {
            document.trimAt(point, threshold: threshold)
            return "trim"
        }
        guard let stroke = document.selectedStrokeID.flatMap({ document.stroke(with: $0) }),
              AnchorPointEngine.roundedOutlineDistance(from: stroke, to: point) <= threshold,
              let edge = StrokeEditor.nearestEdgeIndex(in: stroke, point: point, threshold: threshold)
        else { return "none" }
        document.deleteStrokeEdge(at: edge)
        return "edge"
    }

    private static func filletedDocument() -> (document: KoalaDocument, strokeID: UUID) {
        let document = KoalaDocument()
        var rect = rectangle(layerID: document.activeLayerID)
        rect.cornerRadiiByIndex = Dictionary(
            uniqueKeysWithValues: corners.indices.map { ($0, radius) }
        )
        document.strokes = [rect]
        document.selectedStrokeID = rect.id
        return (document, rect.id)
    }

    /// A tap on an edge has to reach the trim, and the shape it leaves behind keeps every
    /// rounded corner.
    @Test func edgeTapTrimsAndKeepsTheFillets() throws {
        let (document, strokeID) = Self.filletedDocument()

        #expect(Self.trimTap(document, at: CGPoint(x: 50, y: 0), threshold: 3) == "trim")

        let leftover = try #require(document.stroke(with: strokeID))
        for index in Self.corners.indices {
            #expect(leftover.distance(to: Self.filletArcMidpoint(cornerIndex: index)) < 0.6)
            #expect(leftover.distance(to: Self.corners[index]) > 2)
        }
    }

    /// A filleted corner's anchor sits outside the rounded outline, so tapping out there
    /// is not a tap on the shape. It used to delete the corner, dropping both of its edges
    /// and every fillet in one go.
    @Test func filletedCornerAnchorTapLeavesTheShapeAlone() throws {
        let (document, strokeID) = Self.filletedDocument()
        let before = try #require(document.stroke(with: strokeID))

        #expect(Self.trimTap(document, at: Self.corners[1], threshold: 3) == "none")
        #expect(document.stroke(with: strokeID) == before)
    }

    // MARK: - Fillets across anchor and edge edits

    /// Deleting a sharp corner reopens the shape, and the corners that survive keep the
    /// radius the user set on them.
    @Test func deletingACornerKeepsTheOtherCornersFilleted() throws {
        var rect = Self.rectangle(layerID: UUID())
        rect.cornerRadiiByIndex = [3: Self.radius]

        let result = try #require(StrokeEditor.deleteAnchor(rect, at: 1))
        let reopened = result.stroke
        #expect(!reopened.isClosed)
        #expect(reopened.points.count == 3)
        // The surviving filleted corner is now the interior anchor of the open path.
        #expect(reopened.resolvedFilletCornerRadii() == [1: Self.radius])
        #expect(
            AnchorPointEngine.roundedOutlineDistance(
                from: reopened,
                to: Self.filletArcMidpoint(cornerIndex: 3)
            ) < 0.6
        )
    }

    /// A zero override is how one corner stays sharp while the global radius rounds the
    /// rest, so it has to survive an edit alongside the positive radii.
    @Test func deletingACornerKeepsAnExplicitlySharpCorner() throws {
        var rect = Self.rectangle(layerID: UUID(), cornerRadius: Self.radius)
        rect.cornerRadiiByIndex = [3: 0]

        let result = try #require(StrokeEditor.deleteAnchor(rect, at: 1))
        // Reopened as BR, BL, TL: old corner 3 is the interior anchor and stays sharp.
        #expect(result.stroke.resolvedFilletCornerRadii().isEmpty)
    }

    /// Baked fillet arcs live in `smoothCornerIndices`, which the edge delete used to drop
    /// while reopening the contour — flattening every rounded corner on the shape.
    @Test func deletingAnEdgeKeepsBakedFilletArcs() throws {
        let rect = Self.rectangle(layerID: UUID(), cornerRadius: Self.radius)
        let baked = try #require(AnchorPointEngine.bakedFilletStroke(for: rect))
        let straightEdge = try #require(
            StrokeEditor.nearestEdgeIndex(in: baked, point: CGPoint(x: 50, y: 0), threshold: 1)
        )

        let reopened = try #require(StrokeEditor.deleteEdge(baked, edgeIndex: straightEdge))
        #expect(!reopened.isClosed)
        #expect(reopened.smoothCornerIndices?.count == baked.smoothCornerIndices?.count)
        for index in Self.corners.indices {
            #expect(reopened.distance(to: Self.filletArcMidpoint(cornerIndex: index)) < 0.6)
        }
    }

    /// Only one corner is filleted, so the sharp corners still bound the tapped edge and
    /// must stay sharp — the fix may not round anything the user did not fillet.
    @Test func trimmingLeavesUnfilletedCornersSharp() throws {
        var rect = Self.rectangle(layerID: UUID())
        rect.cornerRadiiByIndex = [3: Self.radius]

        let result = try #require(
            TrimEngine.trim(at: CGPoint(x: 50, y: 0), threshold: 2, strokes: [rect])
        )
        let leftover = ShapeGeometry.withCompactedCircularAnchors(result.stroke)

        #expect(leftover.distance(to: Self.filletArcMidpoint(cornerIndex: 3)) < 0.6)
        #expect(leftover.distance(to: Self.corners[3]) > 2)
        #expect(leftover.distance(to: Self.corners[1]) < 0.5)
        #expect(leftover.distance(to: Self.corners[2]) < 0.5)
    }
}
