//
//  StrokeEditor.swift
//  vectr
//

import CoreGraphics
import Foundation

enum StrokeEditor {
    static func deletePoint(_ stroke: VectorStroke, at index: Int) -> VectorStroke? {
        var points = ShapeGeometry.handlePoints(for: stroke)
        guard points.indices.contains(index), points.count > 2 else { return nil }
        points.remove(at: index)
        let closed = stroke.isClosed && points.count > 2
        return updatedStroke(stroke, points: points, isClosed: closed)
    }

    /// Removes one side from a closed shape (reopens as polyline), or removes a vertex from an open path.
    static func deleteEdge(_ stroke: VectorStroke, edgeIndex: Int) -> VectorStroke? {
        let points = ShapeGeometry.handlePoints(for: stroke)
        let edgeCount = stroke.isClosed ? points.count : max(points.count - 1, 0)
        guard edgeIndex >= 0, edgeIndex < edgeCount, points.count >= 3 else { return nil }

        if stroke.isClosed {
            guard stroke.shapeType != .circle, stroke.shapeType != .ellipse else { return nil }
            // Drop the tapped edge by reopening the contour at the next corner.
            let startIndex = (edgeIndex + 1) % points.count
            let reopened = (0..<points.count).map { points[(startIndex + $0) % points.count] }
            return updatedStroke(stroke, points: reopened, isClosed: false)
        }

        var openPoints = points
        let removeIndex = edgeIndex + 1
        guard removeIndex < openPoints.count else { return nil }
        openPoints.remove(at: removeIndex)
        guard openPoints.count >= 2 else { return nil }
        return updatedStroke(stroke, points: openPoints, isClosed: false)
    }

    static func nearestHandleIndex(in stroke: VectorStroke, point: CGPoint, threshold: CGFloat) -> Int? {
        let handles = ShapeGeometry.handlePoints(for: stroke)
        var best: (index: Int, distance: CGFloat)?
        for (index, handle) in handles.enumerated() {
            let distance = hypot(handle.x - point.x, handle.y - point.y)
            if distance < threshold, best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    static func nearestEdgeIndex(in stroke: VectorStroke, point: CGPoint, threshold: CGFloat) -> Int? {
        let handles = ShapeGeometry.handlePoints(for: stroke)
        guard handles.count >= 2 else { return nil }
        let edgeCount = stroke.isClosed ? handles.count : handles.count - 1
        var best: (index: Int, distance: CGFloat)?
        for index in 0..<edgeCount {
            let start = handles[index]
            let end = handles[(index + 1) % handles.count]
            let distance = distanceToSegment(point: point, start: start, end: end)
            if distance < threshold, best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    private static func updatedStroke(_ stroke: VectorStroke, points: [CGPoint], isClosed: Bool) -> VectorStroke {
        var shapeType = stroke.shapeType
        if !isClosed, shapeType == .circle || shapeType == .ellipse || shapeType == .rectangle {
            shapeType = .polyline
        }
        return VectorStroke(
            id: stroke.id,
            layerID: stroke.layerID,
            points: points,
            strokeWidth: stroke.strokeWidth,
            strokeColor: stroke.strokeColor,
            isClosed: isClosed,
            cornerRadius: stroke.cornerRadius,
            cornerRadiiByIndex: nil,
            isConstruction: stroke.isConstruction,
            shapeType: shapeType,
            cutoutPoints: isClosed ? stroke.cutoutPoints : []
        )
    }

    private static func distanceToSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq
        t = max(0, min(1, t))
        let projX = start.x + t * dx
        let projY = start.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}
