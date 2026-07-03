//
//  AnchorPointEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Inserts and distributes anchor points on closed shapes.
enum AnchorPointEngine {
    private static let dedupeEpsilon: CGFloat = 0.001
    private static let endpointEpsilon: CGFloat = 0.001

    private struct AnchorOnPath {
        var point: CGPoint
        var arcDistance: CGFloat
    }

    static func canEditAnchors(on stroke: VectorStroke) -> Bool {
        stroke.isClosed
            && !stroke.isConstruction
            && anchorCount(for: stroke) >= 3
    }

    static func anchorCount(for stroke: VectorStroke) -> Int {
        dedupedHandlePoints(for: stroke).count
    }

    static func insertAtTap(
        stroke: VectorStroke,
        point: CGPoint,
        threshold: CGFloat
    ) -> VectorStroke? {
        guard canEditAnchors(on: stroke) else { return nil }

        let working = editableStroke(for: stroke)
        guard let projection = StrokeEditor.projectPointOnNearestEdge(
            in: working,
            point: point,
            threshold: threshold
        ) else { return nil }

        guard projection.t > endpointEpsilon, projection.t < 1 - endpointEpsilon else { return nil }

        var points = dedupedHandlePoints(for: working)
        let insertIndex = projection.edgeIndex + 1
        guard insertIndex <= points.count else { return nil }

        points.insert(projection.projected, at: insertIndex)

        let remappedCorners = remappedCornerRadii(
            from: working,
            oldPoints: dedupedHandlePoints(for: working),
            newPoints: points,
            insertedAt: insertIndex
        )

        return updatedStroke(working, points: points, cornerRadiiByIndex: remappedCorners)
    }

    static func distributeToTotal(stroke: VectorStroke, targetCount: Int) -> VectorStroke? {
        guard canEditAnchors(on: stroke), targetCount >= 3 else { return nil }

        let existing = dedupedHandlePoints(for: stroke)
        let current = existing.count
        guard targetCount > current else { return nil }

        let toAdd = targetCount - current
        let path = pathPoints(for: stroke)
        guard path.count >= 3 else { return nil }

        let totalLength = perimeterLength(of: path)
        guard totalLength > 0 else { return nil }

        let ordered = anchorsOrderedAlongPath(existing, path: path, totalLength: totalLength)
        guard ordered.count == current else { return nil }

        var gapLengths: [CGFloat] = []
        for index in ordered.indices {
            let start = ordered[index].arcDistance
            let end = ordered[(index + 1) % ordered.count].arcDistance
            gapLengths.append(forwardGapLength(from: start, to: end, totalLength: totalLength))
        }

        let allocation = allocateCounts(total: toAdd, weights: gapLengths)
        var result: [CGPoint] = []

        for (index, anchor) in ordered.enumerated() {
            appendUnique(anchor.point, to: &result)

            let gapLength = gapLengths[index]
            let insertCount = allocation[index]
            guard insertCount > 0, gapLength > 0 else { continue }

            let start = anchor.arcDistance
            for slot in 1...insertCount {
                let fraction = CGFloat(slot) / CGFloat(insertCount + 1)
                let distance = wrappedArcDistance(start + fraction * gapLength, totalLength: totalLength)
                let inserted = pointAtArcLength(path, arcDistance: distance, totalLength: totalLength)
                appendUnique(inserted, to: &result)
            }
        }

        guard result.count == targetCount else { return nil }

        let working = editableStroke(for: stroke)
        let remappedCorners = remappedCornerRadii(
            from: working,
            oldPoints: existing,
            newPoints: result,
            insertedAt: nil
        )

        return updatedStroke(working, points: result, cornerRadiiByIndex: remappedCorners)
    }

    // MARK: - Path geometry

    /// Dense path used for edge projection and arc-length placement.
    private static func pathPoints(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .circle, .ellipse:
            return ShapeGeometry.renderPoints(for: stroke)
        default:
            return dedupedHandlePoints(for: stroke)
        }
    }

    /// Stroke used for mutations; converts parametric shapes to editable polylines when needed.
    private static func editableStroke(for stroke: VectorStroke) -> VectorStroke {
        switch stroke.shapeType {
        case .circle, .ellipse:
            let rendered = ShapeGeometry.renderPoints(for: stroke)
            guard rendered.count >= 3 else { return stroke }
            return VectorStroke(
                id: stroke.id,
                layerID: stroke.layerID,
                points: rendered,
                strokeWidth: stroke.strokeWidth,
                strokeColor: stroke.strokeColor,
                isClosed: stroke.isClosed,
                cornerRadius: 0,
                cornerRadiiByIndex: nil,
                isConstruction: stroke.isConstruction,
                shapeType: .polyline,
                cutoutPoints: stroke.cutoutPoints
            )
        default:
            return stroke
        }
    }

    private static func dedupedHandlePoints(for stroke: VectorStroke) -> [CGPoint] {
        var points = ShapeGeometry.handlePoints(for: stroke)
        if stroke.isClosed,
           points.count > 1,
           distance(points[0], points[points.count - 1]) <= dedupeEpsilon {
            points.removeLast()
        }
        return points
    }

    private static func anchorsOrderedAlongPath(
        _ anchors: [CGPoint],
        path: [CGPoint],
        totalLength: CGFloat
    ) -> [AnchorOnPath] {
        anchors.compactMap { anchor in
            guard let projection = closestPointOnPath(path, to: anchor, totalLength: totalLength) else {
                return nil
            }
            return AnchorOnPath(point: anchor, arcDistance: projection.arcDistance)
        }
        .sorted { $0.arcDistance < $1.arcDistance }
    }

    private static func closestPointOnPath(
        _ path: [CGPoint],
        to point: CGPoint,
        totalLength: CGFloat
    ) -> (point: CGPoint, arcDistance: CGFloat)? {
        guard path.count >= 2, totalLength > 0 else { return nil }

        var best: (point: CGPoint, arcDistance: CGFloat, distance: CGFloat)?
        var traversed: CGFloat = 0

        for index in path.indices {
            let next = (index + 1) % path.count
            let start = path[index]
            let end = path[next]
            let segmentLength = distance(start, end)
            guard segmentLength > 0 else { continue }

            let projection = StrokeEditor.projectPointOnSegment(point: point, start: start, end: end)
            if best == nil || projection.distance < best!.distance {
                best = (
                    projection.point,
                    traversed + projection.t * segmentLength,
                    projection.distance
                )
            }
            traversed += segmentLength
        }

        guard let best else { return nil }
        return (best.point, wrappedArcDistance(best.arcDistance, totalLength: totalLength))
    }

    private static func forwardGapLength(from start: CGFloat, to end: CGFloat, totalLength: CGFloat) -> CGFloat {
        if end >= start {
            return end - start
        }
        return totalLength - start + end
    }

    private static func wrappedArcDistance(_ distance: CGFloat, totalLength: CGFloat) -> CGFloat {
        guard totalLength > 0 else { return 0 }
        var value = distance.truncatingRemainder(dividingBy: totalLength)
        if value < 0 { value += totalLength }
        return value
    }

    private static func allocateCounts(total: Int, weights: [CGFloat]) -> [Int] {
        guard total > 0, !weights.isEmpty else { return Array(repeating: 0, count: weights.count) }

        let sum = weights.reduce(0, +)
        guard sum > 0 else { return Array(repeating: 0, count: weights.count) }

        var exact = weights.map { CGFloat(total) * $0 / sum }
        var counts = exact.map { Int(floor($0)) }
        var remaining = total - counts.reduce(0, +)

        let ranked = exact.enumerated().sorted { lhs, rhs in
            let leftRemainder = lhs.element - floor(lhs.element)
            let rightRemainder = rhs.element - floor(rhs.element)
            if leftRemainder == rightRemainder {
                return lhs.offset < rhs.offset
            }
            return leftRemainder > rightRemainder
        }

        for index in ranked.prefix(remaining).map(\.offset) {
            counts[index] += 1
        }

        return counts
    }

    // MARK: - Arc length

    private static func perimeterLength(of points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for index in points.indices {
            let next = (index + 1) % points.count
            total += distance(points[index], points[next])
        }
        return total
    }

    private static func pointAtArcLength(
        _ points: [CGPoint],
        arcDistance: CGFloat,
        totalLength: CGFloat
    ) -> CGPoint {
        guard !points.isEmpty, totalLength > 0 else { return points.first ?? .zero }

        var remaining = wrappedArcDistance(arcDistance, totalLength: totalLength)

        for index in points.indices {
            let next = (index + 1) % points.count
            let segmentLength = Self.distance(points[index], points[next])
            if segmentLength <= 0 {
                continue
            }
            if remaining <= segmentLength + dedupeEpsilon {
                let t = segmentLength > 0 ? remaining / segmentLength : 0
                return CGPoint(
                    x: points[index].x + t * (points[next].x - points[index].x),
                    y: points[index].y + t * (points[next].y - points[index].y)
                )
            }
            remaining -= segmentLength
        }

        return points[0]
    }

    // MARK: - Corner radius remapping

    private static func remappedCornerRadii(
        from stroke: VectorStroke,
        oldPoints: [CGPoint],
        newPoints: [CGPoint],
        insertedAt: Int?
    ) -> [Int: CGFloat]? {
        guard let overrides = stroke.cornerRadiiByIndex, !overrides.isEmpty else { return stroke.cornerRadiiByIndex }

        var remapped: [Int: CGFloat] = [:]
        for (oldIndex, radius) in overrides {
            let shiftedIndex: Int
            if let insertedAt, oldIndex >= insertedAt {
                shiftedIndex = oldIndex + 1
            } else {
                shiftedIndex = oldIndex
            }
            guard oldPoints.indices.contains(shiftedIndex) else { continue }
            let oldPoint = oldPoints[shiftedIndex]
            if let newIndex = newPoints.firstIndex(where: { distance($0, oldPoint) <= dedupeEpsilon * 10 }) {
                remapped[newIndex] = radius
            }
        }
        return remapped.isEmpty ? nil : remapped
    }

    // MARK: - Helpers

    private static func appendUnique(_ point: CGPoint, to points: inout [CGPoint]) {
        if let last = points.last, distance(last, point) <= dedupeEpsilon {
            return
        }
        points.append(point)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func updatedStroke(
        _ stroke: VectorStroke,
        points: [CGPoint],
        cornerRadiiByIndex: [Int: CGFloat]?
    ) -> VectorStroke {
        var shapeType = stroke.shapeType
        if shapeType == .circle || shapeType == .ellipse {
            shapeType = .polyline
        } else if shapeType == .rectangle, points.count != 4 {
            shapeType = .polyline
        }

        let keepRectangleRadius = shapeType == .rectangle && points.count == 4
        return VectorStroke(
            id: stroke.id,
            layerID: stroke.layerID,
            points: points,
            strokeWidth: stroke.strokeWidth,
            strokeColor: stroke.strokeColor,
            isClosed: true,
            cornerRadius: keepRectangleRadius ? stroke.cornerRadius : 0,
            cornerRadiiByIndex: keepRectangleRadius ? cornerRadiiByIndex : nil,
            isConstruction: stroke.isConstruction,
            shapeType: shapeType,
            cutoutPoints: stroke.cutoutPoints
        )
    }
}
