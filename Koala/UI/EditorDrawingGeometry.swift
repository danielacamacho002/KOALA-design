//
//  EditorDrawingGeometry.swift
//  Koala
//

import CoreGraphics
import Foundation

/// Decisions `EditorView` makes about a raw drag or tap before it becomes a stroke edit.
/// Extracted from the view so the variant rules are checkable without a live gesture.
nonisolated enum EditorDrawingGeometry: Sendable {
    /// Control points for a drag-to-draw gesture, in the layout each shape builder expects.
    /// Center variants describe the shape as center plus two axis extents; edge variants
    /// pass the raw drag endpoints straight through. Returns an empty array for categories
    /// that are not drawn by dragging.
    static func dragControlPoints(
        category: ToolCategory?,
        circleVariant: CircleVariant,
        rectangleVariant: RectangleVariant,
        start: CGPoint,
        end: CGPoint
    ) -> [CGPoint] {
        switch category {
        case .line:
            return [start, end]
        case .circle:
            switch circleVariant {
            case .center, .edge:
                return [start, end]
            case .ellipse:
                let rx = max(CanvasOverlayGeometry.epsilon, abs(end.x - start.x))
                let ry = max(CanvasOverlayGeometry.epsilon, abs(end.y - start.y))
                return [
                    start,
                    CGPoint(x: start.x + rx, y: start.y),
                    CGPoint(x: start.x, y: start.y + ry)
                ]
            }
        case .rectangle:
            switch rectangleVariant {
            case .center:
                let halfW = max(CanvasOverlayGeometry.epsilon, abs(end.x - start.x))
                let halfH = max(CanvasOverlayGeometry.epsilon, abs(end.y - start.y))
                return [
                    start,
                    CGPoint(x: start.x + halfW, y: start.y),
                    CGPoint(x: start.x, y: start.y + halfH)
                ]
            case .edge:
                return [start, end]
            }
        default:
            return []
        }
    }

    /// Whether a delete-edge tap may fall back to opening the shape at `edgeIndex`.
    /// An arc stores start/mid/end, so only its closing edge can be opened: cutting
    /// start→mid or mid→end would reorder the three anchors and flip the arc to the
    /// other side of its chord.
    static func closingEdgeFallbackAllowed(_ stroke: VectorStroke, edgeIndex: Int) -> Bool {
        guard stroke.shapeType == .arc else { return true }
        return stroke.isClosed && edgeIndex == max(stroke.points.count - 1, 0)
    }
}
