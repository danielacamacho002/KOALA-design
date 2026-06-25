//
//  TrimEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

enum TrimEngine {
    struct TrimResult {
        var stroke: VectorStroke
        var strokeID: UUID
    }

    /// Finds the nearest segment to `tapPoint` and trims it at the closest intersection.
    static func trim(at tapPoint: CGPoint, threshold: CGFloat, strokes: [VectorStroke]) -> TrimResult? {
        var best: (stroke: VectorStroke, index: Int, distance: CGFloat, t: CGFloat, renderPoints: [CGPoint])?

        for stroke in strokes where !stroke.isConstruction {
            let renderPoints = ShapeGeometry.renderPoints(for: stroke)
            guard renderPoints.count >= 2 else { continue }
            let segmentCount = stroke.isClosed ? renderPoints.count : renderPoints.count - 1
            for index in 0..<segmentCount {
                let start = renderPoints[index]
                let end = renderPoints[(index + 1) % renderPoints.count]
                let distance = distanceToSegment(point: tapPoint, start: start, end: end)
                if distance < threshold, best == nil || distance < best!.distance {
                    best = (stroke, index, distance, parameter(on: start, end, point: tapPoint), renderPoints)
                }
            }
        }

        guard let match = best,
              let trimmed = trimStrokeInRenderSpace(
                match.stroke,
                renderPoints: match.renderPoints,
                segmentIndex: match.index,
                tapParameter: match.t,
                otherStrokes: strokes.filter { $0.id != match.stroke.id }
              ) else { return nil }

        return TrimResult(stroke: trimmed, strokeID: match.stroke.id)
    }

    private static func trimStrokeInRenderSpace(
        _ target: VectorStroke,
        renderPoints: [CGPoint],
        segmentIndex: Int,
        tapParameter: CGFloat,
        otherStrokes: [VectorStroke]
    ) -> VectorStroke? {
        let isClosed = target.isClosed
        let segStart = renderPoints[segmentIndex]
        let segEnd = renderPoints[(segmentIndex + 1) % renderPoints.count]

        var intersections: [(point: CGPoint, t: CGFloat)] = []
        for other in otherStrokes where other.id != target.id {
            for segment in segments(for: other) {
                if let hit = segmentIntersection(
                    p1: segStart, p2: segEnd,
                    p3: segment.start, p4: segment.end,
                    allowExtended: other.isConstruction
                ) {
                    let t = parameter(on: segStart, segEnd, point: hit)
                    if t > 0.001, t < 0.999 {
                        intersections.append((hit, t))
                    }
                }
            }
        }

        guard !intersections.isEmpty else { return nil }

        let trimHit = intersections.min(by: { abs($0.t - tapParameter) < abs($1.t - tapParameter) })!
        let trimPoint = trimHit.point
        let tInt = trimHit.t

        let trimmedPoints: [CGPoint]
        if tapParameter > tInt {
            var kept = Array(renderPoints.prefix(segmentIndex + 1))
            kept.append(trimPoint)
            trimmedPoints = kept
        } else {
            var kept: [CGPoint] = [trimPoint]
            if isClosed {
                kept.append(contentsOf: renderPoints[(segmentIndex + 1)...])
            } else {
                kept.append(contentsOf: renderPoints.suffix(from: segmentIndex + 1))
            }
            trimmedPoints = kept
        }

        guard trimmedPoints.count >= 2 else { return nil }
        return VectorStroke(
            id: target.id,
            layerID: target.layerID,
            points: trimmedPoints,
            strokeWidth: target.strokeWidth,
            strokeColor: target.strokeColor,
            isClosed: false,
            cornerRadius: 0,
            isConstruction: false,
            shapeType: .polyline
        )
    }

    private struct Segment {
        var start: CGPoint
        var end: CGPoint
    }

    private static func segments(for stroke: VectorStroke) -> [Segment] {
        guard stroke.points.count >= 2 else { return [] }

        if stroke.isConstruction, let first = stroke.points.first, let last = stroke.points.last {
            let dx = last.x - first.x
            let dy = last.y - first.y
            let length = hypot(dx, dy)
            guard length > 0 else { return [] }
            let extend: CGFloat = 8000
            let ux = dx / length
            let uy = dy / length
            return [Segment(
                start: CGPoint(x: first.x - ux * extend, y: first.y - uy * extend),
                end: CGPoint(x: last.x + ux * extend, y: last.y + uy * extend)
            )]
        }

        let renderPoints = ShapeGeometry.renderPoints(for: stroke)
        let count = stroke.isClosed ? renderPoints.count : renderPoints.count - 1
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            Segment(
                start: renderPoints[index],
                end: renderPoints[(index + 1) % renderPoints.count]
            )
        }
    }

    private static func segmentIntersection(
        p1: CGPoint, p2: CGPoint,
        p3: CGPoint, p4: CGPoint,
        allowExtended: Bool
    ) -> CGPoint? {
        let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
        guard abs(d) > 0.0001 else { return nil }
        let t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / d
        let u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / d
        guard t >= 0, t <= 1 else { return nil }
        if !allowExtended, (u < 0 || u > 1) { return nil }
        return CGPoint(x: p1.x + t * (p2.x - p1.x), y: p1.y + t * (p2.y - p1.y))
    }

    private static func parameter(on start: CGPoint, _ end: CGPoint, point: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return 0 }
        return max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq))
    }

    private static func distanceToSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let t = parameter(on: start, end, point: point)
        let proj = CGPoint(x: start.x + t * (end.x - start.x), y: start.y + t * (end.y - start.y))
        return hypot(point.x - proj.x, point.y - proj.y)
    }
}
