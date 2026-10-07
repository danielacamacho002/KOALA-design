import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Koala

/// The trim tool flashes the span it is about to remove before cutting. That flash is
/// driven by `TrimResult.removedSegment`, so these pin that the reported span is the
/// geometry that actually disappears, and that probing for it changes nothing.
@MainActor
struct TrimRemovalPreviewTests {
    private static func rectangle(layerID: UUID) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 60),
                CGPoint(x: 0, y: 60)
            ],
            strokeWidth: 3,
            isClosed: true,
            shapeType: .rectangle
        )
    }

    private static func verticalLine(x: CGFloat, layerID: UUID) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: x, y: -20), CGPoint(x: x, y: 20)],
            isClosed: false,
            shapeType: .polyline
        )
    }

    private static func midpoint(_ points: [CGPoint]) -> CGPoint {
        let index = points.count / 2
        if points.count % 2 == 1 { return points[index] }
        let a = points[index - 1]
        let b = points[index]
        return CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }

    // MARK: - Closed contours

    /// A rectangle's corners are cut points, so tapping the top edge removes exactly that
    /// edge. The reported span must lie on the rectangle and must not survive the trim.
    @Test func closedRectangleReportsTheEdgeItRemoves() throws {
        let layerID = UUID()
        let rect = Self.rectangle(layerID: layerID)

        let result = try #require(
            TrimEngine.trim(at: CGPoint(x: 50, y: 0), threshold: 2, strokes: [rect])
        )
        let removed = try #require(result.removedSegment)

        #expect(removed.strokeWidth == rect.strokeWidth)
        #expect(removed.points.count >= 2)
        for point in removed.points {
            #expect(rect.distance(to: point) < 0.5, "\(point) is not on the rectangle")
        }

        // The span runs corner to corner along the tapped edge.
        let first = try #require(removed.points.first)
        let last = try #require(removed.points.last)
        #expect(min(first.x, last.x) < 0.5)
        #expect(max(first.x, last.x) > 99.5)
        #expect(removed.points.allSatisfy { abs($0.y) < 0.5 })

        // Its interior is gone from the leftover; only the two cut points remain as ends.
        #expect(result.stroke.distance(to: Self.midpoint(removed.points)) > 10)
    }

    // MARK: - Open contours

    /// Two crossing lines bracket the tap, so the middle span is removed and the polyline
    /// splits in two. The reported span must be that middle piece.
    @Test func openPolylineReportsTheMiddleSpanItRemoves() throws {
        let layerID = UUID()
        let path = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            isClosed: false,
            shapeType: .polyline
        )

        let result = try #require(
            TrimEngine.trim(
                at: CGPoint(x: 50, y: 0),
                threshold: 2,
                strokes: [
                    path,
                    Self.verticalLine(x: 30, layerID: layerID),
                    Self.verticalLine(x: 70, layerID: layerID)
                ]
            )
        )
        // Both flanks survive, which is what makes this a middle removal.
        #expect(result.additionalStroke != nil)

        let removed = try #require(result.removedSegment)
        let first = try #require(removed.points.first)
        let last = try #require(removed.points.last)
        #expect(abs(first.x - 30) < 0.5)
        #expect(abs(last.x - 70) < 0.5)
        #expect(removed.points.allSatisfy { $0.x >= 29.5 && $0.x <= 70.5 })
    }

    // MARK: - The document probe

    /// `trimRemovalPreview` runs before the flash, so it must not touch the document.
    /// It also has to agree with `trimAt` about whether the tap is trimmable, because the
    /// editor uses it to choose between trimming and the edge-delete fallback.
    @Test func previewIsReadOnlyAndAgreesWithTrimAt() throws {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        document.strokes = [Self.rectangle(layerID: layerID)]

        let strokesBefore = document.strokes
        let revisionBefore = document.geometryRevision
        let couldUndoBefore = document.canUndo

        let tap = CGPoint(x: 50, y: 0)
        let threshold: CGFloat = 2
        let preview = try #require(document.trimRemovalPreview(at: tap, threshold: threshold))
        #expect(!preview.points.isEmpty)

        #expect(document.strokes == strokesBefore)
        #expect(document.geometryRevision == revisionBefore)
        #expect(document.canUndo == couldUndoBefore)

        // Repeating the probe stays side-effect free, then the real trim does apply.
        #expect(document.trimRemovalPreview(at: tap, threshold: threshold) != nil)
        #expect(document.strokes == strokesBefore)
        #expect(document.trimAt(tap, threshold: threshold))
        #expect(document.geometryRevision > revisionBefore)
    }

    /// An untrimmable tap must come back `nil` so the editor falls through to its
    /// edge-delete fallback instead of flashing and then doing nothing.
    @Test func previewDeclinesTapsAwayFromAnyContour() {
        let document = KoalaDocument()
        document.strokes = [Self.rectangle(layerID: document.activeLayerID)]

        #expect(document.trimRemovalPreview(at: CGPoint(x: 50, y: 30), threshold: 2) == nil)
        #expect(!document.trimAt(CGPoint(x: 50, y: 30), threshold: 2))
    }

    // MARK: - The highlight layer

    /// The previous attempt at this feature reached the canvas through a handle that was
    /// never populated, so no layer was ever added and the flash silently did nothing.
    /// This pins that assigning the span is enough to get a red layer, and that clearing
    /// it takes the layer back down.
    @Test func settingTheSpanAddsAndRemovesARedLayer() throws {
        let document = KoalaDocument()
        document.strokes = [Self.rectangle(layerID: document.activeLayerID)]
        let canvas = DrawingCanvasUIView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 400)

        // The trim tool draws no other preview, so any preview-level shape layer here
        // is the highlight.
        func previewLayers() -> [CAShapeLayer] {
            (canvas.layer.sublayers ?? [])
                .compactMap { $0 as? CAShapeLayer }
                .filter { $0.zPosition == DrawingCanvasUIView.previewZPosition }
        }

        #expect(previewLayers().isEmpty)

        canvas.trimPreviewStrokeWidth = 3
        canvas.trimPreviewPoints = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]

        #expect(previewLayers().count == 1)
        let highlight = try #require(previewLayers().first)
        #expect(highlight.path != nil)
        #expect(highlight.lineWidth >= 3)
        #expect(highlight.strokeColor == UIColor.systemRed.cgColor)

        canvas.trimPreviewPoints = []
        #expect(previewLayers().isEmpty)
    }
}
