//
//  AxisAlignment.swift
//  Koala
//
//  One-axis alignment while moving. A moving anchor, center, or midpoint can
//  stick to the row or column of another point and stay apart from it.
//  Landing on the point itself stays the object snap's job.
//

import CoreGraphics
import Foundation

enum AxisAlignment: Equatable, Sendable, Hashable {
    /// Shared Y. The guide is a horizontal dashed line.
    case horizontal
    /// Shared X. The guide is a vertical dashed line.
    case vertical
}

struct AxisAlignmentGuide: Equatable, Sendable {
    var axis: AxisAlignment
    /// Moving point after the correction.
    var moving: CGPoint
    /// Stationary point it lined up with.
    var stationary: CGPoint
}

struct AxisAlignmentUpdate: Equatable, Sendable {
    var correction: CGPoint
    var guides: [AxisAlignmentGuide]
    var didLock: Bool
}

/// Anchors, centers, and midpoints that can line up during a move.
enum AxisAlignmentPoints {
    static func points(on stroke: VectorStroke) -> [CGPoint] {
        var points = SnapGeometry.vertices(for: stroke)
        if let center = ShapeGeometry.shapeCenter(for: stroke) {
            points.append(center)
        }
        switch stroke.shapeType {
        case .polyline, .rectangle, .construction:
            points.append(contentsOf: SnapGeometry.segmentMidpoints(for: stroke))
        case .arc, .curve:
            if let mid = SnapGeometry.arcLengthMidpoint(of: ShapeGeometry.renderPoints(for: stroke)) {
                points.append(mid)
            }
        case .circle, .ellipse:
            break
        }
        return points
    }
}

/// Sticky one-axis lock for a single move gesture.
struct AxisAlignmentSession {
    private struct Lock: Equatable {
        var movingIndex: Int
        var target: CGPoint
    }

    private var horizontal: Lock?
    private var vertical: Lock?

    mutating func reset() {
        horizontal = nil
        vertical = nil
    }

    /// `proposed` is where each moving point would land before this correction.
    /// Distances are document units. `allowed` drops an axis the drag has locked out.
    mutating func update(
        proposed: [CGPoint],
        targets: [CGPoint],
        tolerance: CGFloat,
        breakaway: CGFloat,
        joinGap: CGFloat,
        allowed: Set<AxisAlignment>
    ) -> AxisAlignmentUpdate {
        var nextHorizontal = resolve(
            existing: horizontal,
            axis: .horizontal,
            proposed: proposed,
            targets: targets,
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: allowed.contains(.horizontal)
        )
        var nextVertical = resolve(
            existing: vertical,
            axis: .vertical,
            proposed: proposed,
            targets: targets,
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: allowed.contains(.vertical)
        )
        preferApart(
            horizontal: &nextHorizontal,
            vertical: &nextVertical,
            proposed: proposed
        )

        let didLock = acquired(horizontal, nextHorizontal) || acquired(vertical, nextVertical)
        horizontal = nextHorizontal
        vertical = nextVertical

        var correction = CGPoint.zero
        if let nextHorizontal, proposed.indices.contains(nextHorizontal.movingIndex) {
            let point = proposed[nextHorizontal.movingIndex]
            correction.y = nextHorizontal.target.y - point.y
        }
        if let nextVertical, proposed.indices.contains(nextVertical.movingIndex) {
            let point = proposed[nextVertical.movingIndex]
            correction.x = nextVertical.target.x - point.x
        }

        var guides: [AxisAlignmentGuide] = []
        if let nextHorizontal, let guide = guide(nextHorizontal, axis: .horizontal, proposed: proposed, correction: correction) {
            guides.append(guide)
        }
        if let nextVertical, let guide = guide(nextVertical, axis: .vertical, proposed: proposed, correction: correction) {
            guides.append(guide)
        }
        return AxisAlignmentUpdate(correction: correction, guides: guides, didLock: didLock)
    }

    private func resolve(
        existing: Lock?,
        axis: AxisAlignment,
        proposed: [CGPoint],
        targets: [CGPoint],
        tolerance: CGFloat,
        breakaway: CGFloat,
        joinGap: CGFloat,
        allowed: Bool
    ) -> Lock? {
        guard allowed, tolerance > 0 else { return nil }
        if let existing,
           proposed.indices.contains(existing.movingIndex),
           holds(
            existing,
            axis: axis,
            point: proposed[existing.movingIndex],
            breakaway: breakaway,
            joinGap: joinGap
           ) {
            return existing
        }
        return acquire(
            axis: axis,
            proposed: proposed,
            targets: targets,
            tolerance: tolerance,
            joinGap: joinGap
        )
    }

    private func holds(
        _ lock: Lock,
        axis: AxisAlignment,
        point: CGPoint,
        breakaway: CGFloat,
        joinGap: CGFloat
    ) -> Bool {
        abs(axisDelta(point, lock.target, axis)) <= breakaway
            && offAxisGap(point, lock.target, axis) > joinGap
    }

    private func acquire(
        axis: AxisAlignment,
        proposed: [CGPoint],
        targets: [CGPoint],
        tolerance: CGFloat,
        joinGap: CGFloat
    ) -> Lock? {
        var best: Lock?
        var bestError = tolerance
        var bestGap = CGFloat.greatestFiniteMagnitude
        for (index, point) in proposed.enumerated() {
            for target in targets {
                let error = abs(axisDelta(point, target, axis))
                let gap = offAxisGap(point, target, axis)
                guard error <= tolerance, gap > joinGap else { continue }
                let closer = best == nil || error < bestError - 0.0001
                let shorter = best != nil && abs(error - bestError) <= 0.0001 && gap < bestGap
                if closer || shorter {
                    best = Lock(movingIndex: index, target: target)
                    bestError = error
                    bestGap = gap
                }
            }
        }
        return best
    }

    /// Two axes locking onto one stationary point would drop the mover on top of it.
    /// Keep the closer axis so the points line up and stay apart.
    private func preferApart(
        horizontal: inout Lock?,
        vertical: inout Lock?,
        proposed: [CGPoint]
    ) {
        guard let horizontalLock = horizontal, let verticalLock = vertical,
              samePoint(horizontalLock.target, verticalLock.target),
              proposed.indices.contains(horizontalLock.movingIndex),
              proposed.indices.contains(verticalLock.movingIndex) else { return }
        let horizontalError = abs(axisDelta(
            proposed[horizontalLock.movingIndex], horizontalLock.target, .horizontal
        ))
        let verticalError = abs(axisDelta(
            proposed[verticalLock.movingIndex], verticalLock.target, .vertical
        ))
        if horizontalError <= verticalError {
            vertical = nil
        } else {
            horizontal = nil
        }
    }

    private func acquired(_ previous: Lock?, _ next: Lock?) -> Bool {
        guard let next else { return false }
        guard let previous else { return true }
        return previous.movingIndex != next.movingIndex || !samePoint(previous.target, next.target)
    }

    private func guide(
        _ lock: Lock,
        axis: AxisAlignment,
        proposed: [CGPoint],
        correction: CGPoint
    ) -> AxisAlignmentGuide? {
        guard proposed.indices.contains(lock.movingIndex) else { return nil }
        let point = proposed[lock.movingIndex]
        let moving = CGPoint(x: point.x + correction.x, y: point.y + correction.y)
        return AxisAlignmentGuide(axis: axis, moving: moving, stationary: lock.target)
    }

    private func samePoint(_ a: CGPoint, _ b: CGPoint) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 0.01
    }

    private func axisDelta(_ point: CGPoint, _ target: CGPoint, _ axis: AxisAlignment) -> CGFloat {
        switch axis {
        case .horizontal: return point.y - target.y
        case .vertical: return point.x - target.x
        }
    }

    private func offAxisGap(_ point: CGPoint, _ target: CGPoint, _ axis: AxisAlignment) -> CGFloat {
        switch axis {
        case .horizontal: return abs(point.x - target.x)
        case .vertical: return abs(point.y - target.y)
        }
    }
}
