//
//  DimensionLabelCollision.swift
//  Koala
//

import CoreGraphics

/// What a dimension measures, in view space.
enum DimensionGeometry: Equatable {
    case linear(start: CGPoint, end: CGPoint)
    case arc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, sweep: CGFloat)
    case radial(anchor: CGPoint)

    /// On-screen length of what is measured; radial dimensions have none.
    var drawnLength: CGFloat {
        switch self {
        case let .linear(start, end):
            return hypot(end.x - start.x, end.y - start.y)
        case let .arc(_, radius, _, sweep):
            return abs(sweep) * radius
        case .radial:
            return .greatestFiniteMagnitude
        }
    }
}

/// Keeps dimension labels readable when they crowd: each label may slide outward along
/// its own dimension by about its own height, and is hidden if it still doesn't fit.
enum DimensionLabelCollision {
    struct Item {
        var id: String
        var geometry: DimensionGeometry
        var placement: CGPoint
        var halfSize: CGSize
        /// User-dragged labels stay where they were dropped and act as obstacles.
        var isFixed: Bool
        /// False for the label the user is working with: it may move but never disappears.
        var canHide: Bool = true
        /// Higher priority claims its spot first.
        var priority: CGFloat = 0
    }

    enum Placement: Equatable {
        case at(CGPoint)
        case hidden

        var point: CGPoint? {
            if case let .at(point) = self { return point }
            return nil
        }
    }

    static func resolve(
        _ items: [Item],
        step: CGFloat = 4,
        padding: CGFloat = 2,
        minimumLength: CGFloat = DimensionLabelStyle.minimumDrawableLength
    ) -> [String: Placement] {
        var result: [String: Placement] = [:]
        var placed: [Footprint] = []
        var pending: [Item] = []
        for item in items {
            if item.geometry.drawnLength < minimumLength {
                result[item.id] = .hidden
            } else if item.isFixed {
                result[item.id] = .at(item.placement)
                if let footprint = footprint(item, at: item.placement, padding: padding) {
                    placed.append(footprint)
                }
            } else {
                pending.append(item)
            }
        }

        let ordered = pending.enumerated().sorted { a, b in
            a.element.priority != b.element.priority
                ? a.element.priority > b.element.priority
                : a.offset < b.offset
        }.map(\.element)

        for item in ordered {
            guard let base = footprint(item, at: item.placement, padding: padding) else {
                result[item.id] = .at(item.placement)
                continue
            }
            var chosen: (Footprint, CGPoint)? = collides(base, with: placed) ? nil : (base, item.placement)
            let maxSteps = Int(ceil(item.halfSize.height * 2 / step))
            var k = 1
            while chosen == nil, k <= maxSteps {
                let distance = step * CGFloat(k)
                let point = CGPoint(
                    x: base.textCenter.x + base.push.x * distance,
                    y: base.textCenter.y + base.push.y * distance
                )
                if let candidate = footprint(item, at: point, padding: padding),
                   !collides(candidate, with: placed) {
                    chosen = (candidate, point)
                }
                k += 1
            }
            if let (footprint, point) = chosen {
                result[item.id] = .at(point)
                placed.append(footprint)
            } else if item.canHide {
                result[item.id] = .hidden
            } else {
                result[item.id] = .at(item.placement)
                placed.append(base)
            }
        }
        return result
    }

    // MARK: - Footprints

    struct Footprint {
        var label: [CGPoint]
        var segments: [(CGPoint, CGPoint)]
        var bounds: CGRect
        var textCenter: CGPoint
        /// Unit direction that moves the label further from what it measures.
        var push: CGPoint
    }

    static func footprint(_ item: Item, at placement: CGPoint, padding: CGFloat) -> Footprint? {
        let half = CGSize(width: item.halfSize.width + padding, height: item.halfSize.height + padding)

        switch item.geometry {
        case let .linear(start, end):
            guard let layout = LinearDimensionLayout.layout(
                start: start,
                end: end,
                placement: placement,
                textHalfHeight: item.halfSize.height
            ) else { return nil }
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let segments = (layout.extensions + layout.shafts).map { ($0.start, $0.end) }
            return make(
                center: layout.textCenter,
                angle: layout.textAngle,
                half: half,
                segments: segments,
                push: unit(from: mid, to: layout.textCenter)
            )
        case let .arc(center, radius, startAngle, sweep):
            guard let layout = ArcDimensionLayout.layout(
                center: center,
                radius: radius,
                startAngle: startAngle,
                sweep: sweep,
                placement: placement,
                textHalfHeight: item.halfSize.height
            ) else { return nil }
            let midAngle = startAngle + sweep / 2
            let arcMid = CGPoint(x: center.x + cos(midAngle) * radius, y: center.y + sin(midAngle) * radius)
            var segments = layout.extensions.map { ($0.start, $0.end) }
            for run in layout.arcRuns {
                segments += zip(run, run.dropFirst()).map { ($0, $1) }
            }
            return make(
                center: layout.textCenter,
                angle: layout.textAngle,
                half: half,
                segments: segments,
                push: unit(from: arcMid, to: layout.textCenter)
            )
        case let .radial(anchor):
            let leaderEnd = DimensionLabelStyle.leaderEnd(from: anchor, to: placement, halfSize: item.halfSize)
            let leaderLength = hypot(leaderEnd.x - anchor.x, leaderEnd.y - anchor.y)
            return make(
                center: placement,
                angle: 0,
                half: half,
                segments: leaderLength > 4 ? [(anchor, leaderEnd)] : [],
                push: unit(from: anchor, to: placement)
            )
        }
    }

    private static func make(
        center: CGPoint,
        angle: CGFloat,
        half: CGSize,
        segments: [(CGPoint, CGPoint)],
        push: CGPoint
    ) -> Footprint {
        let u = CGPoint(x: cos(angle), y: sin(angle))
        let v = CGPoint(x: -u.y, y: u.x)
        let label = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { sx, sy in
            CGPoint(
                x: center.x + u.x * half.width * sx + v.x * half.height * sy,
                y: center.y + u.y * half.width * sx + v.y * half.height * sy
            )
        }
        var points = label
        for segment in segments {
            points.append(segment.0)
            points.append(segment.1)
        }
        return Footprint(
            label: label,
            segments: segments,
            bounds: boundingBox(points),
            textCenter: center,
            push: push
        )
    }

    private static func unit(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return CGPoint(x: 0, y: -1) }
        return CGPoint(x: dx / length, y: dy / length)
    }

    // MARK: - Overlap tests

    static func collides(_ footprint: Footprint, with placed: [Footprint]) -> Bool {
        placed.contains { other in
            guard footprint.bounds.intersects(other.bounds) else { return false }
            if polygonsOverlap(footprint.label, other.label) { return true }
            if other.segments.contains(where: { polygonsOverlap([$0.0, $0.1], footprint.label) }) { return true }
            return footprint.segments.contains { polygonsOverlap([$0.0, $0.1], other.label) }
        }
    }

    /// Separating-axis test for convex polygons; a two-point polygon is a segment.
    /// Touching counts as clear.
    static func polygonsOverlap(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        for polygon in [a, b] where polygon.count >= 2 {
            for i in polygon.indices {
                let p = polygon[i]
                let q = polygon[(i + 1) % polygon.count]
                let axis = CGPoint(x: p.y - q.y, y: q.x - p.x)
                guard hypot(axis.x, axis.y) > 0.0001 else { continue }
                let (minA, maxA) = project(a, on: axis)
                let (minB, maxB) = project(b, on: axis)
                if maxA <= minB || maxB <= minA { return false }
            }
        }
        return true
    }

    private static func project(_ polygon: [CGPoint], on axis: CGPoint) -> (CGFloat, CGFloat) {
        var lo = CGFloat.greatestFiniteMagnitude
        var hi = -CGFloat.greatestFiniteMagnitude
        for point in polygon {
            let d = point.x * axis.x + point.y * axis.y
            lo = min(lo, d)
            hi = max(hi, d)
        }
        return (lo, hi)
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
