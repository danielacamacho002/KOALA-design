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

    /// Collapses any live fillets on the stroke into permanent anchor points and clears the
    /// fillet modifier. Returns `nil` when there is nothing to bake so callers can fall back
    /// to the original stroke.
    static func bakedFilletStroke(for stroke: VectorStroke) -> VectorStroke? {
        guard stroke.hasAnyCornerFillets,
              let baked = FilletPathBuilder.bakedGeometry(for: stroke),
              baked.points.count >= 3 else { return nil }

        // Once fillets are baked, the geometry is a plain polyline; rectangle/parametric
        // types no longer describe the point set, so demote to polyline.
        var shapeType = stroke.shapeType
        if shapeType != .polyline {
            shapeType = .polyline
        }

        return VectorStroke(
            id: stroke.id,
            layerID: stroke.layerID,
            points: baked.points,
            strokeWidth: stroke.strokeWidth,
            strokeColor: stroke.strokeColor,
            isClosed: stroke.isClosed,
            cornerRadius: 0,
            cornerRadiiByIndex: nil,
            smoothCornerIndices: baked.smoothMiddles.isEmpty ? nil : baked.smoothMiddles,
            isConstruction: stroke.isConstruction,
            shapeType: shapeType,
            cutoutPoints: stroke.cutoutPoints
        )
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

        // Curves keep their custom tangent handles: split the exact bezier segment
        // under the tap (de Casteljau) so the shape is preserved and every existing
        // handle stays intact.
        if stroke.shapeType == .curve,
           let handles = stroke.curveHandles,
           handles.count == stroke.points.count {
            return insertOnCurve(stroke: stroke, handles: handles, point: point, threshold: threshold)
        }

        // Bake live fillets into permanent anchors first so the rounded corners survive editing.
        let bakedBase = bakedFilletStroke(for: stroke) ?? stroke

        let working = editableStroke(for: bakedBase)
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
        let remappedSmooth = shiftedSmoothIndices(working.smoothCornerIndices, insertedAt: insertIndex)

        return updatedStroke(
            working,
            points: points,
            cornerRadiiByIndex: remappedCorners,
            smoothMiddles: remappedSmooth
        )
    }

    /// Inserts an anchor onto a `.curve` stroke by splitting the exact cubic segment
    /// under the tap. Existing tangent handles are preserved; the split segment's two
    /// halves reproduce the original curvature so the shape does not change.
    private static func insertOnCurve(
        stroke: VectorStroke,
        handles: [CurveHandle],
        point: CGPoint,
        threshold: CGFloat
    ) -> VectorStroke? {
        let anchors = stroke.points
        let count = anchors.count
        guard count >= 2, handles.count == count else { return nil }

        let samples = 48
        var best: (segment: Int, t: CGFloat, distance: CGFloat, isClosing: Bool)?

        func consider(_ segment: Int, _ t: CGFloat, _ candidate: CGPoint, isClosing: Bool) {
            let d = distance(candidate, point)
            if best == nil || d < best!.distance {
                best = (segment, t, d, isClosing)
            }
        }

        // Cubic bezier segments i -> i+1.
        for index in 0..<(count - 1) {
            let p0 = anchors[index]
            let p3 = anchors[index + 1]
            let c1 = controlOut(anchor: p0, handle: handles[index])
            let c2 = controlIn(anchor: p3, handle: handles[index + 1])
            for step in 0...samples {
                let t = CGFloat(step) / CGFloat(samples)
                consider(index, t, subdivideCubic(p0, c1, c2, p3, t: t).f, isClosing: false)
            }
        }

        // Closing edge (last -> first) is a straight line for closed curves.
        if stroke.isClosed, count >= 3 {
            let p0 = anchors[count - 1]
            let p3 = anchors[0]
            if distance(p0, p3) > dedupeEpsilon {
                for step in 0...samples {
                    let t = CGFloat(step) / CGFloat(samples)
                    consider(count - 1, t, lerp(p0, p3, t), isClosing: true)
                }
            }
        }

        guard let best, best.distance <= threshold else { return nil }
        guard best.t > endpointEpsilon, best.t < 1 - endpointEpsilon else { return nil }

        var newPoints = anchors
        var newHandles = handles

        if best.isClosing {
            // Keep the closing edge straight: zero-offset handles produce a line.
            let p0 = anchors[count - 1]
            let p3 = anchors[0]
            newHandles[count - 1].outOffset = .zero
            newPoints.append(lerp(p0, p3, best.t))
            newHandles.append(CurveHandle())
        } else {
            let index = best.segment
            let p0 = anchors[index]
            let p3 = anchors[index + 1]
            let c1 = controlOut(anchor: p0, handle: handles[index])
            let c2 = controlIn(anchor: p3, handle: handles[index + 1])
            let split = subdivideCubic(p0, c1, c2, p3, t: best.t)

            // Left half controls: p0, split.a, split.d, split.f
            newHandles[index].outOffset = offset(from: p0, to: split.a)
            // Right half controls: split.f, split.e, split.c, p3
            newHandles[index + 1].inOffset = offset(from: p3, to: split.c)
            let inserted = CurveHandle(
                inOffset: offset(from: split.f, to: split.d),
                outOffset: offset(from: split.f, to: split.e)
            )
            newPoints.insert(split.f, at: index + 1)
            newHandles.insert(inserted, at: index + 1)
        }

        var updated = stroke
        updated.points = newPoints
        updated.curveHandles = newHandles
        updated.isClosed = true
        // Curves don't carry fillet/rotation-baseline metadata that survives a
        // changed anchor count; clear it so nothing renders against stale indices.
        updated.cornerRadiiByIndex = nil
        updated.smoothCornerIndices = nil
        updated.rotationBasePoints = nil
        updated.rotationBaseCenter = nil
        return updated
    }

    private static func controlOut(anchor: CGPoint, handle: CurveHandle) -> CGPoint {
        CGPoint(x: anchor.x + handle.outOffset.x, y: anchor.y + handle.outOffset.y)
    }

    private static func controlIn(anchor: CGPoint, handle: CurveHandle) -> CGPoint {
        CGPoint(x: anchor.x + handle.inOffset.x, y: anchor.y + handle.inOffset.y)
    }

    private static func offset(from anchor: CGPoint, to control: CGPoint) -> CGPoint {
        CGPoint(x: control.x - anchor.x, y: control.y - anchor.y)
    }

    private static func lerp(_ p: CGPoint, _ q: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
    }

    /// de Casteljau subdivision of a cubic at `t`. Returns the intermediate points
    /// needed to rebuild both halves: left = (p0, a, d, f), right = (f, e, c, p3).
    private static func subdivideCubic(
        _ p0: CGPoint,
        _ c1: CGPoint,
        _ c2: CGPoint,
        _ p3: CGPoint,
        t: CGFloat
    ) -> (a: CGPoint, c: CGPoint, d: CGPoint, e: CGPoint, f: CGPoint) {
        let a = lerp(p0, c1, t)
        let b = lerp(c1, c2, t)
        let c = lerp(c2, p3, t)
        let d = lerp(a, b, t)
        let e = lerp(b, c, t)
        let f = lerp(d, e, t)
        return (a, c, d, e, f)
    }

    /// Shifts baked-arc midpoint indices to account for a newly inserted anchor. If the anchor
    /// lands inside an arc span (adjacent to its midpoint) that corner's smoothing is dropped,
    /// since the arc's defining neighbors would otherwise change.
    private static func shiftedSmoothIndices(_ indices: Set<Int>?, insertedAt: Int) -> Set<Int>? {
        guard let indices, !indices.isEmpty else { return nil }
        let shifted = indices.compactMap { middle -> Int? in
            if insertedAt == middle || insertedAt == middle + 1 { return nil }
            return middle >= insertedAt ? middle + 1 : middle
        }
        let set = Set(shifted)
        return set.isEmpty ? nil : set
    }

    static func distributeToTotal(stroke inputStroke: VectorStroke, targetCount: Int) -> VectorStroke? {
        guard canEditAnchors(on: inputStroke), targetCount >= 3 else { return nil }

        // Bake live fillets into permanent anchors first so the rounded corners survive editing.
        let stroke = bakedFilletStroke(for: inputStroke) ?? inputStroke

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
        case .circle, .ellipse, .arc:
            return ShapeGeometry.renderPoints(for: stroke)
        default:
            return dedupedHandlePoints(for: stroke)
        }
    }

    /// Stroke used for mutations; converts parametric shapes to editable polylines when needed.
    private static func editableStroke(for stroke: VectorStroke) -> VectorStroke {
        switch stroke.shapeType {
        case .circle, .ellipse, .arc:
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
        cornerRadiiByIndex: [Int: CGFloat]?,
        smoothMiddles: Set<Int>? = nil
    ) -> VectorStroke {
        var shapeType = stroke.shapeType
        if shapeType == .circle || shapeType == .ellipse {
            shapeType = .polyline
        } else if shapeType == .rectangle, points.count != 4 {
            shapeType = .polyline
        }

        let keepRectangleRadius = shapeType == .rectangle && points.count == 4
        // A curve's anchor count changed, so rebuild its tangent handles to stay in
        // sync; otherwise the move tool can't show/edit the beziers after editing.
        let curveHandles = shapeType == .curve
            ? ShapeGeometry.defaultCurveHandles(anchors: points)
            : nil
        return VectorStroke(
            id: stroke.id,
            layerID: stroke.layerID,
            points: points,
            strokeWidth: stroke.strokeWidth,
            strokeColor: stroke.strokeColor,
            isClosed: true,
            cornerRadius: keepRectangleRadius ? stroke.cornerRadius : 0,
            cornerRadiiByIndex: keepRectangleRadius ? cornerRadiiByIndex : nil,
            smoothCornerIndices: smoothMiddles,
            isConstruction: stroke.isConstruction,
            shapeType: shapeType,
            cutoutPoints: stroke.cutoutPoints,
            curveHandles: curveHandles
        )
    }
}
