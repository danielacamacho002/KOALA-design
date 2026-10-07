//
//  PrintSliceEngine.swift
//  Koala
//

import CoreGraphics
import Foundation

/// Slices a stroke (already transformed into print-grid space) along an
/// axis-aligned line into independent polyline fragments. Pure geometry — no
/// document state. Callers convert fragments back to base space as needed.
enum PrintSliceEngine {
    enum Axis {
        /// Vertical line: `x == coordinate`.
        case vertical
        /// Horizontal line: `y == coordinate`.
        case horizontal
    }

    /// Returns fragment strokes (in the same space as `strokeInP`) or `nil` when the
    /// stroke does not actually cross the line, so callers can leave it untouched.
    static func slice(_ strokeInP: VectorStroke, axis: Axis, coordinate: CGFloat) -> [VectorStroke]? {
        slice(strokeInP, axis: axis, coordinate: coordinate, nearestCrossingTo: nil)
    }

    /// Like `slice`, but for open paths only splits at the crossing nearest `tap`
    /// instead of every intersection with the infinite line. Closed shapes still
    /// bisect into two half-planes so each sheet can hold a complete piece.
    static func slice(
        _ strokeInP: VectorStroke,
        axis: Axis,
        coordinate: CGFloat,
        nearestCrossingTo tap: CGPoint?
    ) -> [VectorStroke]? {
        let pts = ShapeGeometry.renderPoints(for: strokeInP)
        // Only slice when the rendered points straddle the line.
        guard straddles(pts, axis: axis, coordinate: coordinate) else { return nil }

        if strokeInP.isClosed {
            return sliceClosed(strokeInP, pts: pts, axis: axis, coordinate: coordinate)
        }
        if let tap {
            return sliceOpenNearestCrossing(strokeInP, pts: pts, axis: axis, coordinate: coordinate, tap: tap)
        }
        return sliceOpen(strokeInP, pts: pts, axis: axis, coordinate: coordinate)
    }

    /// Whether the stroke would slice at all, without building any fragments. Lets a
    /// caller pick its target among many strokes before paying for the real cut.
    static func crosses(_ strokeInP: VectorStroke, axis: Axis, coordinate: CGFloat) -> Bool {
        straddles(ShapeGeometry.renderPoints(for: strokeInP), axis: axis, coordinate: coordinate)
    }

    private static func straddles(_ pts: [CGPoint], axis: Axis, coordinate: CGFloat) -> Bool {
        guard pts.count >= 2 else { return false }
        let epsilon: CGFloat = 0.0001
        var hasNegative = false
        var hasPositive = false
        for point in pts {
            let value = signedValue(point, axis: axis, coordinate: coordinate)
            if value < -epsilon { hasNegative = true }
            if value > epsilon { hasPositive = true }
            if hasNegative, hasPositive { return true }
        }
        return false
    }

    // MARK: - Open polylines

    private static func sliceOpen(
        _ source: VectorStroke,
        pts: [CGPoint],
        axis: Axis,
        coordinate: CGFloat
    ) -> [VectorStroke]? {
        let epsilon: CGFloat = 0.0001
        var pieces: [[CGPoint]] = []
        var current: [CGPoint] = [pts[0]]

        for index in 1..<pts.count {
            let a = pts[index - 1]
            let b = pts[index]
            let va = signedValue(a, axis: axis, coordinate: coordinate)
            let vb = signedValue(b, axis: axis, coordinate: coordinate)
            // Segment crosses the line only when its endpoints are on opposite sides.
            let crosses = (va < -epsilon && vb > epsilon) || (va > epsilon && vb < -epsilon)
            if crosses {
                let t = va / (va - vb)
                let cut = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                current.append(cut)
                pieces.append(current)
                current = [cut, b]
            } else {
                current.append(b)
            }
        }
        pieces.append(current)

        let result = pieces.compactMap { makePiece($0, from: source, closed: false) }
        return result.count >= 2 ? result : nil
    }

    /// Splits an open polyline at the single cut closest to `tap`.
    private static func sliceOpenNearestCrossing(
        _ source: VectorStroke,
        pts: [CGPoint],
        axis: Axis,
        coordinate: CGFloat,
        tap: CGPoint
    ) -> [VectorStroke]? {
        let epsilon: CGFloat = 0.0001
        var bestIndex: Int?
        var bestCut: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for index in 1..<pts.count {
            let a = pts[index - 1]
            let b = pts[index]
            let va = signedValue(a, axis: axis, coordinate: coordinate)
            let vb = signedValue(b, axis: axis, coordinate: coordinate)
            let crosses = (va < -epsilon && vb > epsilon) || (va > epsilon && vb < -epsilon)
            guard crosses else { continue }
            let t = va / (va - vb)
            let cut = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let distance = hypot(cut.x - tap.x, cut.y - tap.y)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
                bestCut = cut
            }
        }
        guard let splitIndex = bestIndex, let cut = bestCut else { return nil }

        var before = Array(pts[0..<splitIndex])
        before.append(cut)
        var after = [cut]
        after.append(contentsOf: pts[splitIndex...])

        let result = [before, after].compactMap { makePiece($0, from: source, closed: false) }
        return result.count >= 2 ? result : nil
    }

    // MARK: - Closed polygons (Sutherland–Hodgman)

    private static func sliceClosed(
        _ source: VectorStroke,
        pts: [CGPoint],
        axis: Axis,
        coordinate: CGFloat
    ) -> [VectorStroke]? {
        let epsilon: CGFloat = 0.0001
        var polygon = pts
        if polygon.count > 1,
           let first = polygon.first,
           let last = polygon.last,
           hypot(first.x - last.x, first.y - last.y) <= epsilon {
            polygon.removeLast()
        }
        guard polygon.count >= 3 else { return nil }

        let sideLow = clip(polygon, axis: axis, coordinate: coordinate, keepLessOrEqual: true)
        let sideHigh = clip(polygon, axis: axis, coordinate: coordinate, keepLessOrEqual: false)

        var result: [VectorStroke] = []
        if let piece = makePiece(sideLow, from: source, closed: true) { result.append(piece) }
        if let piece = makePiece(sideHigh, from: source, closed: true) { result.append(piece) }
        return result.count >= 2 ? result : nil
    }

    /// Clips a polygon to one half-plane of the axis-aligned line.
    private static func clip(
        _ polygon: [CGPoint],
        axis: Axis,
        coordinate: CGFloat,
        keepLessOrEqual: Bool
    ) -> [CGPoint] {
        func isInside(_ point: CGPoint) -> Bool {
            let value = signedValue(point, axis: axis, coordinate: coordinate)
            return keepLessOrEqual ? value <= 0 : value >= 0
        }
        func intersection(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let va = signedValue(a, axis: axis, coordinate: coordinate)
            let vb = signedValue(b, axis: axis, coordinate: coordinate)
            let denominator = va - vb
            guard abs(denominator) > 1e-9 else { return a }
            let t = va / denominator
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        var output: [CGPoint] = []
        let count = polygon.count
        for index in 0..<count {
            let current = polygon[index]
            let previous = polygon[(index + count - 1) % count]
            let currentInside = isInside(current)
            let previousInside = isInside(previous)
            if currentInside {
                if !previousInside { output.append(intersection(previous, current)) }
                output.append(current)
            } else if previousInside {
                output.append(intersection(previous, current))
            }
        }
        return output
    }

    // MARK: - Helpers

    private static func signedValue(_ point: CGPoint, axis: Axis, coordinate: CGFloat) -> CGFloat {
        axis == .vertical ? point.x - coordinate : point.y - coordinate
    }

    /// Builds a fragment as a plain polyline, copying only style/identity from the
    /// source and dropping shape-specific metadata (fillets, curve handles, rotation
    /// bases, cutouts). Points remain in the source's coordinate space.
    private static func makePiece(_ points: [CGPoint], from source: VectorStroke, closed: Bool) -> VectorStroke? {
        guard points.count >= (closed ? 3 : 2) else { return nil }
        return VectorStroke(
            id: UUID(),
            layerID: source.layerID,
            points: points,
            strokeWidth: source.strokeWidth,
            strokeColor: source.strokeColor,
            isClosed: closed,
            isConstruction: source.isConstruction,
            shapeType: .polyline
        )
    }
}
