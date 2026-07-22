//
//  IntersectionAnchorEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Inserts anchor points where stroke segments intersect.
enum IntersectionAnchorEngine {
    private static let intersectionEpsilon: CGFloat = 0.0001
    private static let endpointEpsilon: CGFloat = 0.001
    private static let dedupeEpsilon: CGFloat = 0.001

    private struct Hit {
        var t: CGFloat
        var point: CGPoint
    }

    static func reconcile(
        strokes: [VectorStroke],
        candidateIDs: Set<UUID>? = nil
    ) -> [VectorStroke] {
        guard strokes.count >= 2 else { return strokes }

        let renderPoints = strokes.map { ShapeGeometry.renderPoints(for: $0) }
        var hitsByStroke: [Int: [Int: [Hit]]] = [:]

        for firstIndex in strokes.indices {
            let firstStroke = strokes[firstIndex]
            guard !firstStroke.isConstruction else { continue }
            let firstPoints = renderPoints[firstIndex]
            let firstSegmentCount = segmentCount(for: firstStroke, points: firstPoints)
            guard firstSegmentCount > 0 else { continue }

            for secondIndex in strokes.indices where secondIndex > firstIndex {
                let secondStroke = strokes[secondIndex]
                guard !secondStroke.isConstruction else { continue }

                if let candidateIDs,
                   !candidateIDs.contains(firstStroke.id),
                   !candidateIDs.contains(secondStroke.id) {
                    continue
                }

                let secondPoints = renderPoints[secondIndex]
                let secondSegmentCount = segmentCount(for: secondStroke, points: secondPoints)
                guard secondSegmentCount > 0 else { continue }
                guard boundsOverlap(firstPoints, secondPoints) else { continue }

                for firstSegment in 0..<firstSegmentCount {
                    let a = firstPoints[firstSegment]
                    let b = firstPoints[(firstSegment + 1) % firstPoints.count]

                    for secondSegment in 0..<secondSegmentCount {
                        let c = secondPoints[secondSegment]
                        let d = secondPoints[(secondSegment + 1) % secondPoints.count]

                        guard let intersection = segmentIntersection(a, b, c, d) else { continue }

                        let tFirst = parameter(on: a, b, point: intersection)
                        if acceptsInsertedAnchors(firstStroke), isInteriorParameter(tFirst) {
                            recordHit(
                                into: &hitsByStroke,
                                strokeIndex: firstIndex,
                                segmentIndex: firstSegment,
                                point: intersection,
                                t: tFirst
                            )
                        }

                        let tSecond = parameter(on: c, d, point: intersection)
                        if acceptsInsertedAnchors(secondStroke), isInteriorParameter(tSecond) {
                            recordHit(
                                into: &hitsByStroke,
                                strokeIndex: secondIndex,
                                segmentIndex: secondSegment,
                                point: intersection,
                                t: tSecond
                            )
                        }
                    }
                }
            }
        }

        guard !hitsByStroke.isEmpty else { return strokes }

        var updated = strokes
        for strokeIndex in hitsByStroke.keys.sorted() {
            guard let rebuilt = rebuiltStroke(
                stroke: updated[strokeIndex],
                basePoints: renderPoints[strokeIndex],
                hitsBySegment: hitsByStroke[strokeIndex] ?? [:]
            ) else { continue }
            updated[strokeIndex] = rebuilt
        }

        return updated == strokes ? strokes : updated
    }

    private static func rebuiltStroke(
        stroke: VectorStroke,
        basePoints: [CGPoint],
        hitsBySegment: [Int: [Hit]]
    ) -> VectorStroke? {
        let segmentTotal = segmentCount(for: stroke, points: basePoints)
        guard segmentTotal > 0 else { return nil }

        var points: [CGPoint] = []
        for segmentIndex in 0..<segmentTotal {
            let start = basePoints[segmentIndex]
            let end = basePoints[(segmentIndex + 1) % basePoints.count]

            append(point: start, to: &points)

            let sortedHits = uniqueHits(hitsBySegment[segmentIndex] ?? [])
            for hit in sortedHits {
                append(point: hit.point, to: &points)
            }

            if !stroke.isClosed || segmentIndex < segmentTotal - 1 {
                append(point: end, to: &points)
            }
        }

        if stroke.isClosed,
           let first = points.first,
           let last = points.last,
           distance(first, last) <= dedupeEpsilon {
            points.removeLast()
        }

        let minimumCount = stroke.isClosed ? 3 : 2
        guard points.count >= minimumCount else { return nil }

        let normalizedShapeType: StrokeShapeType
        switch stroke.shapeType {
        case .polyline:
            normalizedShapeType = .polyline
        default:
            normalizedShapeType = .polyline
        }

        return VectorStroke(
            id: stroke.id,
            layerID: stroke.layerID,
            points: points,
            strokeWidth: stroke.strokeWidth,
            strokeColor: stroke.strokeColor,
            isClosed: stroke.isClosed,
            cornerRadius: 0,
            isConstruction: stroke.isConstruction,
            shapeType: normalizedShapeType,
            cutoutPoints: stroke.cutoutPoints
        )
    }

    /// Open lines/polylines are never subdivided — repositioning a line should never carve
    /// extra anchors into it. Parametric shapes (circles, ellipses, arcs) are also left
    /// untouched: a circle/ellipse must always keep exactly its 4 cardinal quadrant anchors and
    /// an arc must always keep exactly its 3 (start / mid / end) anchors. The only way to add
    /// anchors to any of these is through the Add Anchor tool. Other closed shapes (rectangles,
    /// closed polygons) still gain anchors where other geometry crosses them.
    private static func acceptsInsertedAnchors(_ stroke: VectorStroke) -> Bool {
        switch stroke.shapeType {
        case .circle, .ellipse, .arc:
            return false
        case .polyline:
            return stroke.isClosed
        default:
            return true
        }
    }

    private static func segmentCount(for stroke: VectorStroke, points: [CGPoint]) -> Int {
        guard points.count >= 2 else { return 0 }
        return stroke.isClosed ? points.count : points.count - 1
    }

    private static func recordHit(
        into storage: inout [Int: [Int: [Hit]]],
        strokeIndex: Int,
        segmentIndex: Int,
        point: CGPoint,
        t: CGFloat
    ) {
        var bySegment = storage[strokeIndex] ?? [:]
        var hits = bySegment[segmentIndex] ?? []
        hits.append(Hit(t: t, point: point))
        bySegment[segmentIndex] = hits
        storage[strokeIndex] = bySegment
    }

    private static func uniqueHits(_ hits: [Hit]) -> [Hit] {
        let sorted = hits.sorted { $0.t < $1.t }
        var unique: [Hit] = []
        for hit in sorted {
            guard let last = unique.last else {
                unique.append(hit)
                continue
            }
            if abs(hit.t - last.t) <= endpointEpsilon || distance(hit.point, last.point) <= dedupeEpsilon {
                continue
            }
            unique.append(hit)
        }
        return unique
    }

    private static func append(point: CGPoint, to points: inout [CGPoint]) {
        if let last = points.last, distance(last, point) <= dedupeEpsilon {
            return
        }
        points.append(point)
    }

    private static func segmentIntersection(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let denominator = (a.x - b.x) * (c.y - d.y) - (a.y - b.y) * (c.x - d.x)
        guard abs(denominator) > intersectionEpsilon else { return nil }

        let t = ((a.x - c.x) * (c.y - d.y) - (a.y - c.y) * (c.x - d.x)) / denominator
        let u = -((a.x - b.x) * (a.y - c.y) - (a.y - b.y) * (a.x - c.x)) / denominator

        guard t >= -endpointEpsilon,
              t <= 1 + endpointEpsilon,
              u >= -endpointEpsilon,
              u <= 1 + endpointEpsilon else { return nil }

        return CGPoint(
            x: a.x + t * (b.x - a.x),
            y: a.y + t * (b.y - a.y)
        )
    }

    private static func parameter(on start: CGPoint, _ end: CGPoint, point: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }
        return ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
    }

    private static func isInteriorParameter(_ t: CGFloat) -> Bool {
        t > endpointEpsilon && t < (1 - endpointEpsilon)
    }

    private static func boundsOverlap(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        guard let firstA = a.first, let firstB = b.first else { return false }
        var minAX = firstA.x
        var minAY = firstA.y
        var maxAX = firstA.x
        var maxAY = firstA.y
        for point in a.dropFirst() {
            minAX = min(minAX, point.x)
            minAY = min(minAY, point.y)
            maxAX = max(maxAX, point.x)
            maxAY = max(maxAY, point.y)
        }

        var minBX = firstB.x
        var minBY = firstB.y
        var maxBX = firstB.x
        var maxBY = firstB.y
        for point in b.dropFirst() {
            minBX = min(minBX, point.x)
            minBY = min(minBY, point.y)
            maxBX = max(maxBX, point.x)
            maxBY = max(maxBY, point.y)
        }

        return maxAX >= minBX &&
            maxBX >= minAX &&
            maxAY >= minBY &&
            maxBY >= minAY
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
