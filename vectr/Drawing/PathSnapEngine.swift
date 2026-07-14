//
//  PathSnapEngine.swift
//  vectr
//
//  Real-time, plugin-driven object snapping for Apple Pencil input.
//
//  This engine is intentionally decoupled from the canvas/UI. It only knows how to
//  turn a query point + a set of vector paths into the single best snap candidate.
//  New snap types (center points, intersections, tangents, …) can be added later by
//  implementing `SnapCandidateProvider` and registering it — no other code needs to change.
//
//  Sprint scope: Endpoints and Midpoints only.
//

import CoreGraphics
import Foundation
import QuartzCore

// MARK: - Snap vocabulary

/// The kind of geometric feature a snap candidate represents.
/// Adding a new case here is the first step to shipping a new snap-type plugin.
enum SnapKind: Equatable {
    case endpoint
    case midpoint
    case intersection
    // Future plugins: case center, case tangent, …
}

/// A single resolved snap target in document space.
struct SnapCandidate: Equatable {
    let point: CGPoint
    let kind: SnapKind
    /// Stroke the candidate was derived from, when it comes from a single stroke.
    /// `nil` for relational candidates such as intersections (which come from a pair).
    let sourceStrokeID: UUID?
}

// MARK: - Plugin interface

/// A pluggable source of snap candidates for a single stroke.
///
/// Providers are pure and stateless: given a stroke, they return the document-space
/// points they consider snappable. The engine handles all proximity culling, distance
/// ranking, and lock/breakaway lifecycle, so providers stay tiny and testable.
protocol SnapCandidateProvider {
    /// The kind of snap this provider emits. Also drives the visual indicator glyph.
    var kind: SnapKind { get }

    /// Candidate points (document space) for `stroke`. Return `[]` when the stroke has
    /// no features of this kind (e.g. a closed shape has no endpoints).
    func candidates(for stroke: VectorStroke) -> [CGPoint]
}

/// A provider that derives candidates from relationships *between* strokes (e.g. where two
/// paths cross) rather than from a single stroke. It receives the strokes already culled to
/// the proximity zone plus the query point, so implementations stay cheap.
protocol RelationalSnapCandidateProvider {
    /// The kind of snap this provider emits. Also drives the visual indicator glyph.
    var kind: SnapKind { get }

    /// Candidate points (document space) within `radius` of `point`, derived from the
    /// relationships among `strokes`.
    func candidates(near point: CGPoint, within radius: CGFloat, strokes: [VectorStroke]) -> [CGPoint]
}

// MARK: - Endpoint plugin

/// Emits a path's vertices — the manipulable key points of the geometry:
/// - open paths: the terminal points plus any intermediate corners,
/// - closed polygons/rectangles: every corner,
/// - circles/ellipses: the four quadrant (cardinal) points.
/// This matches standard CAD "endpoint" snapping, which locks onto vertices of both open
/// and closed shapes.
struct EndpointSnapProvider: SnapCandidateProvider {
    let kind: SnapKind = .endpoint

    func candidates(for stroke: VectorStroke) -> [CGPoint] {
        SnapGeometry.vertices(for: stroke)
    }
}

// MARK: - Midpoint plugin

/// Emits parametric midpoints:
/// - Straight/segmented paths (polyline, rectangle, construction): the midpoint of every
///   segment, computed directly from the underlying anchors.
/// - Smooth open geometry (arc, curve): the exact 50%-arc-length point of the true
///   sampled geometry.
/// Closed smooth loops (circle, ellipse) have no meaningful single midpoint and are skipped.
struct MidpointSnapProvider: SnapCandidateProvider {
    let kind: SnapKind = .midpoint

    func candidates(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .polyline, .rectangle, .construction:
            return SnapGeometry.segmentMidpoints(for: stroke)
        case .arc:
            return SnapGeometry.arcLengthMidpoint(of: stroke.points).map { [$0] } ?? []
        case .curve:
            return SnapGeometry.arcLengthMidpoint(of: ShapeGeometry.renderPoints(for: stroke)).map { [$0] } ?? []
        case .circle, .ellipse:
            return []
        }
    }
}

// MARK: - Intersection plugin

/// Emits the exact coordinates where two different strokes cross. Works on the rendered
/// geometry, so line×line, line×shape and shape×shape crossings are all detected. To stay
/// fast, only segments that pass within the proximity radius of the query point are considered.
struct IntersectionSnapProvider: RelationalSnapCandidateProvider {
    let kind: SnapKind = .intersection

    private struct LocalSegment {
        let a: CGPoint
        let b: CGPoint
        let strokeIndex: Int
    }

    func candidates(near point: CGPoint, within radius: CGFloat, strokes: [VectorStroke]) -> [CGPoint] {
        // Gather only the segments that pass near the cursor, tagged by their owning stroke.
        var localSegments: [LocalSegment] = []
        for (index, stroke) in strokes.enumerated() {
            let points = ShapeGeometry.renderPoints(for: stroke)
            guard points.count >= 2 else { continue }
            let segmentCount = stroke.isClosed ? points.count : points.count - 1
            for segment in 0..<segmentCount {
                let a = points[segment]
                let b = points[(segment + 1) % points.count]
                if SnapGeometry.distance(from: point, toSegment: a, b) <= radius {
                    localSegments.append(LocalSegment(a: a, b: b, strokeIndex: index))
                }
            }
        }

        guard localSegments.count >= 2 else { return [] }

        // Cross every near-cursor segment against those from *other* strokes.
        var result: [CGPoint] = []
        for i in 0..<localSegments.count {
            for j in (i + 1)..<localSegments.count where localSegments[i].strokeIndex != localSegments[j].strokeIndex {
                if let crossing = SnapGeometry.segmentIntersection(
                    localSegments[i].a, localSegments[i].b,
                    localSegments[j].a, localSegments[j].b
                ), hypot(crossing.x - point.x, crossing.y - point.y) <= radius {
                    result.append(crossing)
                }
            }
        }
        return result
    }
}

// MARK: - Shared geometry helpers

enum SnapGeometry {
    /// The shape's manipulable key points (corners / quadrant handles), with the duplicate
    /// closing vertex and any coincident duplicates removed. Uses `ShapeGeometry.handlePoints`
    /// so circles/ellipses resolve to their oriented quadrant points.
    static func vertices(for stroke: VectorStroke) -> [CGPoint] {
        deduped(ShapeGeometry.handlePoints(for: stroke), isClosed: stroke.isClosed)
    }

    /// Midpoint of each segment between consecutive anchors. Includes the closing
    /// segment when the stroke is closed.
    static func segmentMidpoints(for stroke: VectorStroke) -> [CGPoint] {
        let points = deduped(stroke.points, isClosed: stroke.isClosed)
        guard points.count >= 2 else { return [] }
        let segmentCount = stroke.isClosed ? points.count : points.count - 1
        var result: [CGPoint] = []
        result.reserveCapacity(segmentCount)
        for index in 0..<segmentCount {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            result.append(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        }
        return result
    }

    /// True segment×segment intersection (bounded, not infinite lines). Returns `nil` for
    /// parallel/collinear segments or when the crossing lies outside either segment.
    static func segmentIntersection(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let s = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }

        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
        let u = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denominator
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }

        return CGPoint(x: a.x + t * r.x, y: a.y + t * r.y)
    }

    /// Shortest distance from `point` to the segment `a`–`b`.
    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// Removes consecutive coincident points and, for closed paths, the duplicated closing
    /// vertex, so a vertex is never emitted twice.
    static func deduped(_ points: [CGPoint], isClosed: Bool) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            if let last = result.last, hypot(last.x - point.x, last.y - point.y) <= 0.0001 { continue }
            result.append(point)
        }
        if isClosed,
           result.count > 1,
           let first = result.first,
           let last = result.last,
           hypot(first.x - last.x, first.y - last.y) <= 0.0001 {
            result.removeLast()
        }
        return result
    }

    /// The point at 50% of the total arc length along a sampled polyline.
    /// This gives the true geometric midpoint of curves/arcs regardless of how the
    /// samples are distributed.
    static func arcLengthMidpoint(of points: [CGPoint]) -> CGPoint? {
        guard points.count >= 2 else { return points.first }

        var totalLength: CGFloat = 0
        for index in 0..<(points.count - 1) {
            totalLength += hypot(points[index + 1].x - points[index].x,
                                 points[index + 1].y - points[index].y)
        }
        guard totalLength > 0 else { return points.first }

        let target = totalLength / 2
        var travelled: CGFloat = 0
        for index in 0..<(points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            let segment = hypot(b.x - a.x, b.y - a.y)
            if travelled + segment >= target {
                let remaining = target - travelled
                let t = segment > 0 ? remaining / segment : 0
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            travelled += segment
        }
        return points.last
    }
}

// MARK: - Engine

/// Stateless resolver that finds the closest snap candidate to a query point.
///
/// Proximity is enforced in two stages so we never run candidate math across the whole
/// canvas: (1) a cheap axis-aligned bounding-box test culls strokes outside the active
/// zone, then (2) registered providers run only for the surviving strokes.
struct PathSnapEngine {
    var providers: [SnapCandidateProvider]
    var relationalProviders: [RelationalSnapCandidateProvider]

    /// Default engine: endpoints + midpoints (per-stroke) and intersections (relational).
    /// Register additional providers here (or inject them) to extend the engine.
    static func makeDefault() -> PathSnapEngine {
        PathSnapEngine(
            providers: [
                EndpointSnapProvider(),
                MidpointSnapProvider()
            ],
            relationalProviders: [
                IntersectionSnapProvider()
            ]
        )
    }

    /// Returns the nearest candidate within `radius` (document units) of `point`,
    /// or `nil` if nothing is close enough.
    ///
    /// - Parameters:
    ///   - excludedStrokeID: a stroke to ignore (e.g. the one currently being edited).
    ///   - enabledKinds: only providers whose kind is in this set contribute candidates.
    ///     Pass an empty set to disable snapping entirely.
    func closestCandidate(
        to point: CGPoint,
        within radius: CGFloat,
        strokes: [VectorStroke],
        excludedStrokeID: UUID? = nil,
        enabledKinds: Set<SnapKind>
    ) -> SnapCandidate? {
        guard radius > 0, !enabledKinds.isEmpty else { return nil }

        // Active proximity zone around the pencil tip.
        let zone = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        var best: SnapCandidate?
        var bestDistanceSquared = radius * radius

        func consider(_ candidatePoint: CGPoint, kind: SnapKind, sourceStrokeID: UUID?) {
            let dx = candidatePoint.x - point.x
            let dy = candidatePoint.y - point.y
            let distanceSquared = dx * dx + dy * dy
            // `<` keeps earlier candidates winning on ties, so endpoints (considered first)
            // take priority over midpoints and intersections at equal distance.
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                best = SnapCandidate(point: candidatePoint, kind: kind, sourceStrokeID: sourceStrokeID)
            }
        }

        // Stage 1: bounding-box cull, done once. Skips all candidate math for far-away shapes.
        var nearby: [VectorStroke] = []
        nearby.reserveCapacity(strokes.count)
        for stroke in strokes {
            if let excludedStrokeID, stroke.id == excludedStrokeID { continue }
            guard let box = stroke.boundingBox(padding: radius), box.intersects(zone) else { continue }
            nearby.append(stroke)
        }

        // Stage 2a: per-stroke providers (endpoints, midpoints, …).
        for stroke in nearby {
            for provider in providers where enabledKinds.contains(provider.kind) {
                for candidate in provider.candidates(for: stroke) {
                    consider(candidate, kind: provider.kind, sourceStrokeID: stroke.id)
                }
            }
        }

        // Stage 2b: relational providers (intersections, …) over the in-zone set.
        for provider in relationalProviders where enabledKinds.contains(provider.kind) {
            for candidate in provider.candidates(near: point, within: radius, strokes: nearby) {
                consider(candidate, kind: provider.kind, sourceStrokeID: nil)
            }
        }

        return best
    }
}

// MARK: - Interaction session (slide-to-snap + breakaway)

/// Stateful wrapper around `PathSnapEngine` that models the magnetic lock lifecycle for a
/// single continuous gesture (one pencil drag). It provides:
///
/// - **Slide-to-snap:** acquires a lock when the pencil enters `snapRadius` of a candidate.
/// - **Hysteresis breakaway:** once locked, the point stays glued until the pencil is pulled
///   past the larger `breakawayRadius`, so it doesn't flicker at the edge of the zone.
/// - **Velocity breakaway:** a fast flick past `breakawayVelocity` snaps the lock off
///   immediately, so the user never feels "stuck".
final class SnapInteractionSession {
    struct Update {
        /// The candidate the cursor is currently locked to, or `nil` if free.
        let candidate: SnapCandidate?
        /// `true` only on the frame the cursor newly locks onto a candidate (haptic trigger).
        let didLock: Bool
    }

    private(set) var lockedCandidate: SnapCandidate?
    private var lastPoint: CGPoint?
    private var lastTimestamp: TimeInterval?

    /// Feed a fresh raw pencil position and resolve the snap state.
    ///
    /// All distances are in document units; `breakawayVelocity` is document units / second.
    func update(
        rawPoint: CGPoint,
        engine: PathSnapEngine,
        strokes: [VectorStroke],
        enabledKinds: Set<SnapKind>,
        snapRadius: CGFloat,
        breakawayRadius: CGFloat,
        breakawayVelocity: CGFloat,
        excludedStrokeID: UUID? = nil
    ) -> Update {
        let now = CACurrentMediaTime()
        let previousPoint = lastPoint
        let previousTimestamp = lastTimestamp
        lastPoint = rawPoint
        lastTimestamp = now

        // 1. Velocity breakaway — a rapid move clears any existing lock immediately.
        if lockedCandidate != nil,
           let previousPoint,
           let previousTimestamp {
            let dt = now - previousTimestamp
            if dt > 0 {
                let speed = hypot(rawPoint.x - previousPoint.x, rawPoint.y - previousPoint.y) / CGFloat(dt)
                if speed > breakawayVelocity {
                    lockedCandidate = nil
                }
            }
        }

        // 2. Distance breakaway / stickiness — stay glued within the outer radius.
        if let current = lockedCandidate {
            let distance = hypot(rawPoint.x - current.point.x, rawPoint.y - current.point.y)
            if distance <= breakawayRadius {
                return Update(candidate: current, didLock: false)
            }
            lockedCandidate = nil
        }

        // 3. Acquire a new lock if a candidate is inside the (tighter) snap radius.
        if let candidate = engine.closestCandidate(
            to: rawPoint,
            within: snapRadius,
            strokes: strokes,
            excludedStrokeID: excludedStrokeID,
            enabledKinds: enabledKinds
        ) {
            let isNewLock = candidate != lockedCandidate
            lockedCandidate = candidate
            return Update(candidate: candidate, didLock: isNewLock)
        }

        lockedCandidate = nil
        return Update(candidate: nil, didLock: false)
    }

    /// Clears all lock/velocity state. Call when a gesture ends or is cancelled.
    func reset() {
        lockedCandidate = nil
        lastPoint = nil
        lastTimestamp = nil
    }
}

// MARK: - Document integration

extension VectrDocument {
    /// The snap kinds currently active for this document, honoring the master switch and the
    /// per-type toggles. Empty when snapping is off, which disables the engine entirely.
    var enabledSnapKinds: Set<SnapKind> {
        guard isSnappingEnabled else { return [] }
        var kinds: Set<SnapKind> = []
        if endpointSnapEnabled { kinds.insert(.endpoint) }
        if midpointSnapEnabled { kinds.insert(.midpoint) }
        if intersectionSnapEnabled { kinds.insert(.intersection) }
        return kinds
    }
}

// MARK: - Tuning

/// Central place for snap feel. Values are in view points (screen space) and are converted
/// to document units at call sites so behavior is consistent across zoom levels.
enum SnapTuning {
    /// Distance at which the cursor is pulled onto a candidate.
    static let snapRadiusPoints: CGFloat = 16
    /// Larger radius the cursor must be dragged past to break a lock (hysteresis).
    static let breakawayRadiusPoints: CGFloat = 32
    /// Pencil speed (points/second) above which a lock breaks instantly.
    static let breakawayVelocityPoints: CGFloat = 2600
}
