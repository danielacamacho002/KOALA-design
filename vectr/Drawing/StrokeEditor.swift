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
        let originalCount = points.count
        let aligned = alignedCurveHandles(stroke, pointCount: originalCount)
        points.remove(at: index)
        let closed = stroke.isClosed && points.count > 2
        let keptIndices = (0..<originalCount).filter { $0 != index }
        return updatedStroke(
            stroke,
            points: points,
            isClosed: closed,
            sourceIndices: keptIndices,
            sourceCount: originalCount,
            preservedCurveHandles: pickHandles(aligned, keeping: keptIndices)
        )
    }

    /// Result of deleting a single anchor. `additionalStroke` is only produced when an
    /// interior corner on an open path splits the path into two pieces.
    struct AnchorDeletionResult {
        var stroke: VectorStroke
        var additionalStroke: VectorStroke?
    }

    /// Deletes the anchor at `index` using tap-friendly semantics:
    /// - A collinear anchor (sitting on a straight run between its neighbors) is removed
    ///   while the surrounding geometry stays identical.
    /// - A corner anchor removes the two edges meeting at that vertex: a closed contour
    ///   reopens at the gap, and an interior corner on an open path splits it in two.
    static func deleteAnchor(
        _ stroke: VectorStroke,
        at index: Int,
        collinearToleranceDegrees: CGFloat = 6
    ) -> AnchorDeletionResult? {
        var points = ShapeGeometry.handlePoints(for: stroke)
        if stroke.isClosed,
           points.count > 1,
           hypot(points[0].x - points[points.count - 1].x, points[0].y - points[points.count - 1].y) <= 0.001 {
            points.removeLast()
        }
        guard points.indices.contains(index) else { return nil }
        let count = points.count
        let alignedHandles = alignedCurveHandles(stroke, pointCount: count)

        // Neighbors that bound the vertex. Endpoints of an open path only have one edge,
        // so they can never be a two-edge corner.
        let hasBothNeighbors = stroke.isClosed || (index > 0 && index < count - 1)

        if hasBothNeighbors {
            let straight = PolygonBoolean.isRedundantContourVertex(
                points,
                index: index,
                closed: stroke.isClosed
            ) || isStraightVertex(
                prev: points[(index - 1 + count) % count],
                point: points[index],
                next: points[(index + 1) % count],
                toleranceDegrees: collinearToleranceDegrees
            )
            if straight {
                // Collinear point: drop it, geometry is unchanged.
                guard count > 2 else { return nil }
                let keptIndices = (0..<count).filter { $0 != index }
                points.remove(at: index)
                let closed = stroke.isClosed && points.count > 2
                let updated = updatedStroke(
                    stroke,
                    points: points,
                    isClosed: closed,
                    sourceIndices: keptIndices,
                    sourceCount: count,
                    preservedCurveHandles: pickHandles(alignedHandles, keeping: keptIndices)
                )
                return AnchorDeletionResult(stroke: updated, additionalStroke: nil)
            }

            // Corner: remove both adjacent edges.
            if stroke.isClosed {
                guard count >= 3 else { return nil }
                // Reopen the contour starting just past the removed vertex, keeping every
                // other point. The gap left behind spans the vertex's two former edges.
                let order = (0..<(count - 1)).map { (index + 1 + $0) % count }
                let reopened = order.map { points[$0] }
                guard reopened.count >= 2 else { return nil }
                let updated = updatedStroke(
                    stroke,
                    points: reopened,
                    isClosed: false,
                    sourceIndices: order,
                    sourceCount: count,
                    preservedCurveHandles: pickHandles(alignedHandles, keeping: order)
                )
                return AnchorDeletionResult(stroke: updated, additionalStroke: nil)
            }

            // Interior corner on an open path: split into two open paths at the gap.
            let leftIndices = Array(0..<index)
            let rightIndices = Array((index + 1)..<count)
            let left = leftIndices.map { points[$0] }
            let right = rightIndices.map { points[$0] }
            let leftValid = left.count >= 2
            let rightValid = right.count >= 2
            guard leftValid || rightValid else { return nil }
            if leftValid, rightValid {
                let primary = updatedStroke(
                    stroke,
                    points: left,
                    isClosed: false,
                    sourceIndices: leftIndices,
                    sourceCount: count,
                    preservedCurveHandles: pickHandles(alignedHandles, keeping: leftIndices)
                )
                var secondary = updatedStroke(
                    stroke,
                    points: right,
                    isClosed: false,
                    sourceIndices: rightIndices,
                    sourceCount: count,
                    preservedCurveHandles: pickHandles(alignedHandles, keeping: rightIndices)
                )
                secondary.id = UUID()
                return AnchorDeletionResult(stroke: primary, additionalStroke: secondary)
            }
            let keptIndices = leftValid ? leftIndices : rightIndices
            let kept = leftValid ? left : right
            return AnchorDeletionResult(
                stroke: updatedStroke(
                    stroke,
                    points: kept,
                    isClosed: false,
                    sourceIndices: keptIndices,
                    sourceCount: count,
                    preservedCurveHandles: pickHandles(alignedHandles, keeping: keptIndices)
                ),
                additionalStroke: nil
            )
        }

        // Open-path endpoint: only one edge, so just trim the endpoint off.
        guard count > 2 else { return nil }
        let keptIndices = (0..<count).filter { $0 != index }
        points.remove(at: index)
        let updated = updatedStroke(
            stroke,
            points: points,
            isClosed: false,
            sourceIndices: keptIndices,
            sourceCount: count,
            preservedCurveHandles: pickHandles(alignedHandles, keeping: keptIndices)
        )
        return AnchorDeletionResult(stroke: updated, additionalStroke: nil)
    }

    /// True when `point` lies on a (near) straight run between `prev` and `next`.
    private static func isStraightVertex(
        prev: CGPoint,
        point: CGPoint,
        next: CGPoint,
        toleranceDegrees: CGFloat
    ) -> Bool {
        PolygonBoolean.isCollinearVertex(
            prev: prev,
            point: point,
            next: next,
            angleToleranceDegrees: toleranceDegrees
        )
    }

    /// Removes one side from a closed shape (reopens as polyline), or removes a vertex from an open path.
    static func deleteEdge(_ stroke: VectorStroke, edgeIndex: Int) -> VectorStroke? {
        let points = ShapeGeometry.handlePoints(for: stroke)
        let edgeCount = stroke.isClosed ? points.count : max(points.count - 1, 0)
        guard edgeIndex >= 0, edgeIndex < edgeCount, points.count >= 3 else { return nil }
        let aligned = alignedCurveHandles(stroke, pointCount: points.count)

        if stroke.isClosed {
            guard stroke.shapeType != .circle, stroke.shapeType != .ellipse else { return nil }
            // Drop the tapped edge by reopening the contour at the next corner. No anchor is
            // removed, only the closure and one edge, so every anchor keeps its handle.
            let startIndex = (edgeIndex + 1) % points.count
            let order = (0..<points.count).map { (startIndex + $0) % points.count }
            let reopened = order.map { points[$0] }
            return updatedStroke(
                stroke,
                points: reopened,
                isClosed: false,
                sourceIndices: order,
                sourceCount: points.count,
                preservedCurveHandles: pickHandles(aligned, keeping: order)
            )
        }

        var openPoints = points
        let removeIndex = edgeIndex + 1
        guard removeIndex < openPoints.count else { return nil }
        let keptIndices = (0..<openPoints.count).filter { $0 != removeIndex }
        openPoints.remove(at: removeIndex)
        guard openPoints.count >= 2 else { return nil }
        return updatedStroke(
            stroke,
            points: openPoints,
            isClosed: false,
            sourceIndices: keptIndices,
            sourceCount: points.count,
            preservedCurveHandles: pickHandles(aligned, keeping: keptIndices)
        )
    }

    static func nearestHandleIndex(in stroke: VectorStroke, point: CGPoint, threshold: CGFloat) -> Int? {
        let handles = handlePointsForEditing(stroke)
        var best: (index: Int, distance: CGFloat)?
        for (index, handle) in handles.enumerated() {
            let distance = hypot(handle.x - point.x, handle.y - point.y)
            if distance < threshold, best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    /// Trim-tool hit test: if a leftover (collinear) anchor is in range, prefer it over a
    /// nearby structural corner so tapping extras between teeth does not reopen a tooth.
    static func nearestTrimAnchorIndex(in stroke: VectorStroke, point: CGPoint, threshold: CGFloat) -> Int? {
        let handles = handlePointsForEditing(stroke)
        let closed = stroke.isClosed
        var bestRedundant: (index: Int, distance: CGFloat)?
        var bestAny: (index: Int, distance: CGFloat)?
        for (index, handle) in handles.enumerated() {
            let distance = hypot(handle.x - point.x, handle.y - point.y)
            guard distance < threshold else { continue }
            if bestAny == nil || distance < bestAny!.distance {
                bestAny = (index, distance)
            }
            if PolygonBoolean.isRedundantContourVertex(handles, index: index, closed: closed),
               bestRedundant == nil || distance < bestRedundant!.distance {
                bestRedundant = (index, distance)
            }
        }
        return bestRedundant?.index ?? bestAny?.index
    }

    /// Handle points used for vertex editing: drops a duplicate closing vertex so indices
    /// match `deleteAnchor`.
    static func handlePointsForEditing(_ stroke: VectorStroke) -> [CGPoint] {
        var points = ShapeGeometry.handlePoints(for: stroke)
        if stroke.isClosed,
           points.count > 1,
           hypot(points[0].x - points[points.count - 1].x, points[0].y - points[points.count - 1].y) <= 0.001 {
            points.removeLast()
        }
        return points
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

    /// Projects a point onto the nearest edge of the stroke.
    static func projectPointOnNearestEdge(
        in stroke: VectorStroke,
        point: CGPoint,
        threshold: CGFloat
    ) -> (edgeIndex: Int, projected: CGPoint, t: CGFloat)? {
        let handles = ShapeGeometry.handlePoints(for: stroke)
        guard handles.count >= 2 else { return nil }
        let edgeCount = stroke.isClosed ? handles.count : handles.count - 1
        var best: (index: Int, projected: CGPoint, t: CGFloat, distance: CGFloat)?
        for index in 0..<edgeCount {
            let start = handles[index]
            let end = handles[(index + 1) % handles.count]
            let projection = projectPointOnSegment(point: point, start: start, end: end)
            if projection.distance < threshold,
               best == nil || projection.distance < best!.distance {
                best = (index, projection.point, projection.t, projection.distance)
            }
        }
        guard let best else { return nil }
        return (best.index, best.projected, best.t)
    }

    static func projectPointOnSegment(
        point: CGPoint,
        start: CGPoint,
        end: CGPoint
    ) -> (point: CGPoint, t: CGFloat, distance: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            let distance = hypot(point.x - start.x, point.y - start.y)
            return (start, 0, distance)
        }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq
        t = max(0, min(1, t))
        let projected = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        let distance = hypot(point.x - projected.x, point.y - projected.y)
        return (projected, t, distance)
    }

    private static func distanceToSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        projectPointOnSegment(point: point, start: start, end: end).distance
    }

    /// Curve tangent handles aligned 1:1 with the `pointCount` anchors returned by
    /// `handlePoints`, or `nil` when the stroke is not a handle-carrying curve. A closed
    /// curve may store a trailing duplicate anchor that `handlePoints` drops, so allow
    /// an off-by-one and trim it.
    static func alignedCurveHandles(_ stroke: VectorStroke, pointCount: Int) -> [CurveHandle]? {
        guard stroke.shapeType == .curve, let handles = stroke.curveHandles else { return nil }
        if handles.count == pointCount { return handles }
        if handles.count == pointCount + 1 { return Array(handles.prefix(pointCount)) }
        return nil
    }

    /// Selects the handles for the surviving anchors, mapping each new position to the old
    /// anchor index it came from. Returns `nil` if any index is missing so the caller can
    /// fall back to regenerating handles.
    static func pickHandles(_ handles: [CurveHandle]?, keeping oldIndices: [Int]) -> [CurveHandle]? {
        guard let handles else { return nil }
        let picked = oldIndices.compactMap { handles.indices.contains($0) ? handles[$0] : nil }
        return picked.count == oldIndices.count ? picked : nil
    }

    /// Carries the fillet modifiers onto the anchors that survived an edit.
    /// `sourceIndices[new]` is the anchor a kept point came from, so a per-corner radius
    /// follows its corner. A baked arc midpoint only survives while both anchors its sweep
    /// runs between are still its neighbors; otherwise the arc would be rebuilt through
    /// whatever geometry the edit left next to it.
    private static func remappedFilletModifiers(
        _ stroke: VectorStroke,
        sourceIndices: [Int],
        sourceCount: Int,
        isClosed: Bool
    ) -> (radiiByIndex: [Int: CGFloat]?, smoothMiddles: Set<Int>?) {
        var newPositions: [Int: Int] = [:]
        for (new, source) in sourceIndices.enumerated() {
            newPositions[source] = new
        }

        // A zero override is meaningful: it is how one corner stays sharp under a positive
        // global `cornerRadius`, so it has to travel with its corner too.
        var radii: [Int: CGFloat] = [:]
        if let existing = stroke.cornerRadiiByIndex {
            for (new, source) in sourceIndices.enumerated() {
                if let radius = existing[source] { radii[new] = max(0, radius) }
            }
        }

        var middles: Set<Int> = []
        if let existing = stroke.smoothCornerIndices {
            let newCount = sourceIndices.count
            for (new, source) in sourceIndices.enumerated() where existing.contains(source) {
                let sourcePrev = stroke.isClosed ? (source - 1 + sourceCount) % sourceCount : source - 1
                let sourceNext = stroke.isClosed ? (source + 1) % sourceCount : source + 1
                let newPrev = isClosed ? (new - 1 + newCount) % newCount : new - 1
                let newNext = isClosed ? (new + 1) % newCount : new + 1
                guard newPositions[sourcePrev] == newPrev, newPositions[sourceNext] == newNext else { continue }
                middles.insert(new)
            }
        }

        return (radii.isEmpty ? nil : radii, middles.isEmpty ? nil : middles)
    }

    private static func updatedStroke(
        _ stroke: VectorStroke,
        points: [CGPoint],
        isClosed: Bool,
        sourceIndices: [Int],
        sourceCount: Int,
        preservedCurveHandles: [CurveHandle]? = nil
    ) -> VectorStroke {
        var shapeType = stroke.shapeType
        if !isClosed, shapeType == .circle || shapeType == .ellipse || shapeType == .rectangle {
            shapeType = .polyline
        }
        // For a curve, keep the surviving anchors' hand-tuned tangents when the caller
        // supplies them (so deleting one anchor doesn't re-curve the whole outline); fall
        // back to a rebuilt cardinal spline only when they can't be spliced.
        let curveHandles: [CurveHandle]?
        if shapeType == .curve {
            if let preservedCurveHandles, preservedCurveHandles.count == points.count {
                curveHandles = preservedCurveHandles
            } else {
                curveHandles = ShapeGeometry.defaultCurveHandles(anchors: points, closed: isClosed)
            }
        } else {
            curveHandles = nil
        }
        let fillets = remappedFilletModifiers(
            stroke,
            sourceIndices: sourceIndices,
            sourceCount: sourceCount,
            isClosed: isClosed
        )
        return VectorStroke(
            id: stroke.id,
            layerID: stroke.layerID,
            points: points,
            strokeWidth: stroke.strokeWidth,
            strokeColor: stroke.strokeColor,
            isClosed: isClosed,
            cornerRadius: stroke.cornerRadius,
            cornerRadiiByIndex: fillets.radiiByIndex,
            smoothCornerIndices: fillets.smoothMiddles,
            isConstruction: stroke.isConstruction,
            shapeType: shapeType,
            cutoutPoints: isClosed ? stroke.cutoutPoints : [],
            curveHandles: curveHandles
        )
    }
}
