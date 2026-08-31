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
    /// Exact mathematical origin of a circle / ellipse / arc. Glyph: concentric circle (⊙).
    case center
    /// North / south / east / west apex of a circular boundary. Glyph: diamond (⋄).
    case quadrant
    /// Point where an in-progress straight line kisses a curve without crossing it.
    /// Glyph: circle with a line across its top edge.
    case tangent
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
            return SnapGeometry.arcLengthMidpoint(of: ShapeGeometry.renderPoints(for: stroke)).map { [$0] } ?? []
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

// MARK: - Center plugin

/// Emits the center of any geometry:
/// - circles / ellipses: the parametric center,
/// - arcs: the center of the circle the arc lies on,
/// - rectangles / polylines / lines / curves: the shape center (same point used by the
///   cyan center handle), so a shape or line can be snapped by/to its middle.
struct CenterSnapProvider: SnapCandidateProvider {
    let kind: SnapKind = .center

    func candidates(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .circle:
            return ShapeGeometry.circleFromCardinalPoints(stroke.points).map { [$0.center] } ?? []
        case .ellipse:
            return ShapeGeometry.ellipseFromCardinalPoints(stroke.points).map { [$0.center] } ?? []
        case .arc:
            return ShapeGeometry.arcCircle(for: stroke).map { [$0.center] } ?? []
        case .curve:
            if let circle = ShapeGeometry.arcCircle(for: stroke) { return [circle.center] }
            return ShapeGeometry.shapeCenter(for: stroke).map { [$0] } ?? []
        case .polyline, .rectangle, .construction:
            return ShapeGeometry.shapeCenter(for: stroke).map { [$0] } ?? []
        }
    }
}

// MARK: - Quadrant plugin

/// Emits the four cardinal apexes (0° / 90° / 180° / 270°) of a circular or elliptical
/// boundary. These are the oriented quadrant handles of the shape.
struct QuadrantSnapProvider: SnapCandidateProvider {
    let kind: SnapKind = .quadrant

    func candidates(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .circle, .ellipse:
            return ShapeGeometry.handlePoints(for: stroke)
        default:
            return []
        }
    }
}

// MARK: - Tangent plugin

/// A provider that needs the anchored end of the in-progress line (its start point) to
/// resolve candidates — tangency is defined relative to that fixed point.
protocol AnchoredSnapCandidateProvider {
    /// The kind of snap this provider emits. Also drives the visual indicator glyph.
    var kind: SnapKind { get }

    /// Candidate points (document space) for `stroke`, given the fixed `referenceStart`
    /// of the line currently being drawn.
    func candidates(for stroke: VectorStroke, referenceStart: CGPoint) -> [CGPoint]
}

/// Emits the point(s) where a straight line from `referenceStart` touches a circle or arc
/// tangentially — kissing the edge without crossing it. Arc tangents are kept only when the
/// contact point actually lies on the drawn arc span.
struct TangentSnapProvider: AnchoredSnapCandidateProvider {
    let kind: SnapKind = .tangent

    func candidates(for stroke: VectorStroke, referenceStart: CGPoint) -> [CGPoint] {
        guard let circle = ShapeGeometry.arcCircle(for: stroke) else { return [] }
        let tangents = SnapGeometry.tangentPoints(
            from: referenceStart,
            center: circle.center,
            radius: circle.radius
        )
        guard stroke.shapeType == .arc else { return tangents }
        return tangents.filter { SnapGeometry.arc(stroke, contains: $0, center: circle.center) }
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

    /// The two points on a circle where lines from external point `p` touch tangentially.
    /// Returns `[]` when `p` is on or inside the circle (no external tangent exists).
    static func tangentPoints(from p: CGPoint, center: CGPoint, radius: CGFloat) -> [CGPoint] {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let distance = hypot(dx, dy)
        guard distance > radius + 0.0001 else { return [] }
        let baseAngle = atan2(dy, dx)
        let offset = acos(radius / distance)
        return [baseAngle + offset, baseAngle - offset].map { angle in
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    /// True when `point` lies on the angular span actually covered by the arc `stroke`.
    static func arc(_ stroke: VectorStroke, contains point: CGPoint, center: CGPoint) -> Bool {
        guard let first = stroke.points.first, let last = stroke.points.last else { return false }
        let start = atan2(first.y - center.y, first.x - center.x)
        let end = atan2(last.y - center.y, last.x - center.x)
        let target = atan2(point.y - center.y, point.x - center.x)

        func normalized(_ angle: CGFloat) -> CGFloat {
            var value = angle - start
            while value < 0 { value += 2 * .pi }
            while value >= 2 * .pi { value -= 2 * .pi }
            return value
        }

        let span = normalized(end)
        let relative = normalized(target)
        return relative <= span + 0.001 || relative >= 2 * .pi - 0.001
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
    var anchoredProviders: [AnchoredSnapCandidateProvider]

    /// Default engine: centers, quadrants, endpoints + midpoints (per-stroke), intersections
    /// (relational) and tangents (anchored to the in-progress line). Register additional
    /// providers here (or inject them) to extend the engine.
    ///
    /// Order matters for ties: `consider(_:)` keeps earlier candidates, so the circle-specific
    /// snaps (center, quadrant) win over a generic endpoint at the same coordinate.
    static func makeDefault() -> PathSnapEngine {
        PathSnapEngine(
            providers: [
                CenterSnapProvider(),
                QuadrantSnapProvider(),
                EndpointSnapProvider(),
                MidpointSnapProvider()
            ],
            relationalProviders: [
                IntersectionSnapProvider()
            ],
            anchoredProviders: [
                TangentSnapProvider()
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
    ///   - referenceStarts: fixed anchor point(s) of the segment(s) whose free end is being
    ///     placed, enabling tangent snaps. A dragged endpoint has one; a dragged middle anchor
    ///     has two (its neighbors), so tangent can engage on either adjacent segment.
    func closestCandidate(
        to point: CGPoint,
        within radius: CGFloat,
        strokes: [VectorStroke],
        excludedStrokeID: UUID? = nil,
        excludedStrokeIDs: Set<UUID> = [],
        enabledKinds: Set<SnapKind>,
        referenceStarts: [CGPoint] = []
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
            if excludedStrokeIDs.contains(stroke.id) { continue }
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

        // Stage 2c: anchored tangent fallback — only when a line is in progress and nothing
        // else snapped. Tangent contact points sit off-axis on the rim (not where the cursor
        // usually aims), so instead of requiring the cursor to hit that exact point we let the
        // line "kiss the edge": when the free end is dragged within `radius` of a circle/arc's
        // rim, it jumps to the correct tangent point. Vertex/center/quadrant snaps still win
        // when they are in range, so this never fights the precise snaps.
        if best == nil, !referenceStarts.isEmpty, !anchoredProviders.isEmpty {
            // Cap how far the endpoint may leap onto a contact point, so tangent engages only
            // near an actual contact (the "shoulders" of the circle) rather than teleporting the
            // line across the rim from the near edge. Bounded to a couple of snap radii.
            let maxLeap = radius * 2
            var bestTangentDistanceSquared = maxLeap * maxLeap
            for stroke in nearby {
                guard let circle = ShapeGeometry.arcCircle(for: stroke) else { continue }
                // Require the cursor to be near the boundary ring, so tangent only engages when
                // the user is clearly bringing the line up to the curve.
                let rimDistance = abs(hypot(point.x - circle.center.x, point.y - circle.center.y) - circle.radius)
                guard rimDistance <= radius else { continue }
                for provider in anchoredProviders where enabledKinds.contains(provider.kind) {
                    for referenceStart in referenceStarts {
                        for candidate in provider.candidates(for: stroke, referenceStart: referenceStart) {
                            let dx = candidate.x - point.x
                            let dy = candidate.y - point.y
                            let distanceSquared = dx * dx + dy * dy
                            if distanceSquared < bestTangentDistanceSquared {
                                bestTangentDistanceSquared = distanceSquared
                                best = SnapCandidate(point: candidate, kind: provider.kind, sourceStrokeID: stroke.id)
                            }
                        }
                    }
                }
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

    struct TranslationUpdate {
        /// The candidate a moving anchor is currently locked to, or `nil` if free.
        let candidate: SnapCandidate?
        /// Vector to add to the raw move delta so the locked anchor lands on the candidate.
        let correction: CGPoint
        /// `true` only on the frame a moving anchor newly locks onto a candidate (haptic trigger).
        let didLock: Bool
    }

    private(set) var lockedCandidate: SnapCandidate?
    /// The moving anchor origin (pre-translation) associated with `lockedCandidate` during a
    /// whole-object translation, so the correction can be recomputed each frame.
    private var lockedOrigin: CGPoint?
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
        excludedStrokeID: UUID? = nil,
        referenceStarts: [CGPoint] = []
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
        //
        // Tangent is exempt: its contact point sits off-axis on the rim, typically far from the
        // cursor, so point-distance stickiness would drop the lock immediately. Instead we fall
        // through and let the engine re-resolve the tangent against the rim every frame; it stays
        // engaged while the free end hovers the boundary and releases naturally when it leaves.
        if let current = lockedCandidate, current.kind != .tangent {
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
            enabledKinds: enabledKinds,
            referenceStarts: referenceStarts
        ) {
            let isNewLock = candidate != lockedCandidate
            lockedCandidate = candidate
            return Update(candidate: candidate, didLock: isNewLock)
        }

        lockedCandidate = nil
        return Update(candidate: nil, didLock: false)
    }

    /// Resolve snapping for a rigid whole-object translation.
    ///
    /// Unlike `update` (which snaps a single reference point), this treats *every* moving anchor
    /// as a candidate reference. Because the move is a pure translation by `rawDelta`, snapping
    /// anchor origin `o_i` onto target `c` yields `delta = c - o_i`. We pick the `(o_i, c)` pair
    /// with the smallest gap within the snap radius, then return the correction that lands that
    /// anchor exactly on the candidate. Distance hysteresis keeps the lock sticky.
    ///
    /// `centerOrigins` are the moving object's center point(s). They get a dedicated priority
    /// pass so a moving center reliably locks onto another object's center (center-to-center)
    /// even when a perimeter vertex happens to be a little closer to some other feature.
    ///
    /// All distances are in document units.
    func updateTranslation(
        origins: [CGPoint],
        centerOrigins: [CGPoint] = [],
        rawDelta: CGPoint,
        engine: PathSnapEngine,
        strokes: [VectorStroke],
        enabledKinds: Set<SnapKind>,
        snapRadius: CGFloat,
        breakawayRadius: CGFloat,
        excludedStrokeIDs: Set<UUID>
    ) -> TranslationUpdate {
        // Finds the moving origin whose projected position is nearest a candidate of `kinds`.
        func bestPair(origins: [CGPoint], kinds: Set<SnapKind>) -> (SnapCandidate, CGPoint)? {
            guard !kinds.isEmpty else { return nil }
            var best: SnapCandidate?
            var bestOrigin: CGPoint?
            var bestDistanceSquared = snapRadius * snapRadius
            for origin in origins {
                let projected = CGPoint(x: origin.x + rawDelta.x, y: origin.y + rawDelta.y)
                guard let candidate = engine.closestCandidate(
                    to: projected,
                    within: snapRadius,
                    strokes: strokes,
                    excludedStrokeIDs: excludedStrokeIDs,
                    enabledKinds: kinds
                ) else { continue }
                let dx = candidate.point.x - projected.x
                let dy = candidate.point.y - projected.y
                let distanceSquared = dx * dx + dy * dy
                if distanceSquared < bestDistanceSquared {
                    bestDistanceSquared = distanceSquared
                    best = candidate
                    bestOrigin = origin
                }
            }
            if let best, let bestOrigin { return (best, bestOrigin) }
            return nil
        }

        func lock(_ candidate: SnapCandidate, _ origin: CGPoint) -> TranslationUpdate {
            let isNewLock = candidate != lockedCandidate
            lockedCandidate = candidate
            lockedOrigin = origin
            let projected = CGPoint(x: origin.x + rawDelta.x, y: origin.y + rawDelta.y)
            let correction = CGPoint(x: candidate.point.x - projected.x, y: candidate.point.y - projected.y)
            return TranslationUpdate(candidate: candidate, correction: correction, didLock: isNewLock)
        }

        // A moving center snapping onto another object's center. This has priority and can even
        // take over a lower-priority lock, so aligning two centers is always reachable — a line's
        // endpoints, for example, no longer grab an endpoint lock that blocks center alignment.
        let centerMatch = bestPair(origins: centerOrigins, kinds: enabledKinds.intersection([.center]))

        // 1. Stay locked (hysteresis): keep the current candidate glued while the associated
        //    anchor's projected position stays within the outer radius — unless a center-to-center
        //    match is now available and we're not already on it (priority upgrade).
        if let current = lockedCandidate, let origin = lockedOrigin {
            let projected = CGPoint(x: origin.x + rawDelta.x, y: origin.y + rawDelta.y)
            let distance = hypot(projected.x - current.point.x, projected.y - current.point.y)
            if distance <= breakawayRadius {
                if let (best, bestOrigin) = centerMatch, best != current {
                    return lock(best, bestOrigin)
                }
                let correction = CGPoint(x: current.point.x - projected.x, y: current.point.y - projected.y)
                return TranslationUpdate(candidate: current, correction: correction, didLock: false)
            }
            lockedCandidate = nil
            lockedOrigin = nil
        }

        // 2a. Priority: center-to-center. 2b. Fallback: any moving anchor onto any enabled candidate.
        if let (best, bestOrigin) = centerMatch ?? bestPair(origins: origins, kinds: enabledKinds) {
            return lock(best, bestOrigin)
        }

        lockedCandidate = nil
        lockedOrigin = nil
        return TranslationUpdate(candidate: nil, correction: .zero, didLock: false)
    }

    /// Clears all lock/velocity state. Call when a gesture ends or is cancelled.
    func reset() {
        lockedCandidate = nil
        lockedOrigin = nil
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
        if centerSnapEnabled { kinds.insert(.center) }
        if quadrantSnapEnabled { kinds.insert(.quadrant) }
        if tangentSnapEnabled { kinds.insert(.tangent) }
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
