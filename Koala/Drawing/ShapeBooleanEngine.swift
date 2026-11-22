//
//  ShapeBooleanEngine.swift
//  Koala
//

import CoreGraphics
import Foundation

/// Pure-geometry Boolean helpers for closed polygon contours (document space).
///
/// Used by the Delete tool to punch a hole into a base shape by subtracting an
/// overlapping target shape: the cutout stored on the base is the intersection
/// `(base ∩ target)`, which renders as an even-odd hole via `cutoutPoints`.
///
/// Intersection uses the Sutherland–Hodgman polygon clipper, which is exact when
/// the clip polygon is convex (circles, ellipses, rectangles). When the target is
/// fully contained by the base the target contour is used verbatim so the cutout
/// keeps the target's exact geometry (quad, ellipse, Bézier path, or circle).
enum ShapeBooleanEngine {
    /// A reshaped outer contour plus the vertex indices whose outgoing edge is a cut
    /// edge (bounds the carved notch and should be filled through but not stroked).
    struct CutContour: Equatable {
        var points: [CGPoint]
        var cutEdgeStarts: [Int]
    }

    /// A circular span of a shape's outline (a live or baked fillet), so a Boolean
    /// result can rebuild that span as an arc instead of flattening its samples.
    struct OutlineArc: Equatable {
        var center: CGPoint
        var radius: CGFloat
        var startAngle: CGFloat
        var sweep: CGFloat

        func contains(_ point: CGPoint) -> Bool {
            let tolerance = max(0.05, radius * 0.01)
            guard abs(hypot(point.x - center.x, point.y - center.y) - radius) <= tolerance else { return false }
            var offset = atan2(point.y - center.y, point.x - center.x) - startAngle
            if sweep < 0 { offset = -offset }
            offset = offset.truncatingRemainder(dividingBy: 2 * .pi)
            if offset < 0 { offset += 2 * .pi }
            let slack = tolerance / radius
            return offset <= abs(sweep) + slack || offset >= 2 * .pi - slack
        }
    }

    /// The outline a Boolean should see for `stroke`: live fillets are baked and
    /// expanded so the cut follows the drawn rounded corners, plus the circular
    /// spans of those corners.
    static func booleanOutline(for stroke: VectorStroke) -> (contour: [CGPoint], arcs: [OutlineArc]) {
        switch stroke.shapeType {
        case .circle, .ellipse, .arc, .curve:
            return (ShapeGeometry.renderPoints(for: stroke), [])
        default:
            break
        }
        var outline = stroke
        if stroke.isClosed, let baked = FilletPathBuilder.bakedGeometry(for: stroke) {
            outline.points = baked.points
            outline.smoothCornerIndices = baked.smoothMiddles.isEmpty ? nil : baked.smoothMiddles
            outline.cornerRadius = 0
            outline.cornerRadiiByIndex = nil
            outline.shapeType = .polyline
        }
        return (ShapeGeometry.renderPoints(for: outline), smoothArcs(of: outline))
    }

    private static func smoothArcs(of stroke: VectorStroke) -> [OutlineArc] {
        guard stroke.isClosed, let smooth = stroke.smoothCornerIndices, !smooth.isEmpty else { return [] }
        let points = stroke.points
        let count = points.count
        let runs = ShapeGeometry.consecutiveSmoothRuns(count: count, smooth: smooth, closed: true)
        return runs.compactMap { run in
            guard run.count < count, let first = run.first, let last = run.last else { return nil }
            var chain = [points[(first - 1 + count) % count]]
            chain.append(contentsOf: run.map { points[$0] })
            chain.append(points[(last + 1) % count])
            guard let circle = circumcircle(chain[0], chain[chain.count / 2], chain[chain.count - 1]),
                  let sweep = ShapeGeometry.signedCircularSweep(of: chain, around: circle.center, closed: false),
                  abs(sweep) > 0.0001 else { return nil }
            return OutlineArc(
                center: circle.center,
                radius: circle.radius,
                startAngle: atan2(chain[0].y - circle.center.y, chain[0].x - circle.center.x),
                sweep: sweep
            )
        }
    }

    /// Outcome of subtracting a target shape from a base shape.
    enum Subtraction: Equatable {
        /// Target sits entirely inside the base: punch an even-odd hole by appending
        /// these contours to `base.cutoutPoints`.
        case interiorHole([[CGPoint]])
        /// Target crosses the base boundary: the base's *outer* outline must be
        /// reshaped. These are the resulting `base − target` contours (largest first).
        case boundaryCut([CutContour])
        /// Target fully covers the base: the base is consumed and should be removed.
        case baseRemoved
    }

    /// Classifies how `target` subtracts from `base` and returns the geometry needed
    /// to apply it, or `nil` when the two shapes do not meaningfully overlap.
    ///
    /// Both contours are expected to be fully expanded render geometry (tessellated
    /// circles/ellipses, sampled Béziers, quads), so the result preserves the drawn
    /// shapes rather than re-approximating them.
    static func subtract(baseContour: [CGPoint], targetContour: [CGPoint]) -> Subtraction? {
        let base = normalized(baseContour)
        let target = normalized(targetContour)
        guard base.count >= 3, target.count >= 3 else { return nil }

        let baseArea = abs(signedArea(base))
        let targetArea = abs(signedArea(target))
        guard baseArea > .ulpOfOne, targetArea > .ulpOfOne else { return nil }
        let minArea = max(1e-4, min(baseArea, targetArea) * 0.0005)

        // Target fully contained → interior hole preserving the target's boundary.
        if target.allSatisfy({ polygon(base, contains: $0) }) {
            return .interiorHole([literalPolygonContour(target)])
        }

        // Base fully contained → the cut swallows the whole base.
        if base.allSatisfy({ polygon(target, contains: $0) }) {
            return .baseRemoved
        }

        // Must genuinely overlap (crossing edges or partial containment) to subtract.
        guard PolygonBoolean.polygonsOverlap(base, target) else { return nil }

        let contours = PolygonBoolean.difference(subject: base, clip: target)
            .filter { $0.points.count >= 3 && abs(signedArea($0.points)) > minArea }
            .sorted { abs(signedArea($0.points)) > abs(signedArea($1.points)) }
            .map { CutContour(points: $0.points, cutEdgeStarts: $0.cutEdgeStarts) }

        guard !contours.isEmpty else { return .baseRemoved }

        // Require that a meaningful area was actually carved away. Two shapes that only
        // touch along a shared edge (adjacent grid cells) pass `polygonsOverlap` because
        // a boundary vertex reads as "inside" in the even-odd test, yet `difference`
        // returns the base essentially unchanged. Reporting that as a cut would delete
        // the target while leaving the base untouched, so callers must keep searching
        // for a base the target genuinely overlaps.
        let remainingArea = contours.reduce(CGFloat.zero) { $0 + abs(signedArea($1.points)) }
        guard baseArea - remainingArea > minArea else { return nil }

        return .boundaryCut(contours)
    }

    /// Contours of `(base ∩ target)` to append to `base.cutoutPoints`, or `nil`
    /// when the two shapes do not meaningfully overlap.
    ///
    /// `targetContour` is expected to already be the target's fully expanded render
    /// geometry (e.g. a tessellated circle/ellipse or sampled Bézier path), so the
    /// hole preserves the drawn shape rather than being re-approximated.
    static func subtractionCutouts(baseContour: [CGPoint], targetContour: [CGPoint]) -> [[CGPoint]]? {
        let base = normalized(baseContour)
        let target = normalized(targetContour)
        guard base.count >= 3, target.count >= 3 else { return nil }

        let baseArea = abs(signedArea(base))
        let targetArea = abs(signedArea(target))
        guard baseArea > .ulpOfOne, targetArea > .ulpOfOne else { return nil }
        // Reject mere edge-touching / numeric slivers relative to the smaller shape.
        let minArea = max(1e-4, min(baseArea, targetArea) * 0.0005)

        // Fast, exact path: target fully inside base → the hole is the target itself,
        // preserving its precise vector boundary.
        if target.allSatisfy({ polygon(base, contains: $0) }) {
            return [literalPolygonContour(target)]
        }

        // General case: clip against whichever contour is convex for an exact result.
        let subject: [CGPoint]
        let clip: [CGPoint]
        if isConvex(target) {
            subject = base
            clip = target
        } else if isConvex(base) {
            subject = target
            clip = base
        } else {
            // Neither is convex: best-effort clip against the target.
            subject = base
            clip = target
        }

        let intersection = normalized(convexClip(subject: subject, clip: clip))
        guard intersection.count >= 3, abs(signedArea(intersection)) > minArea else { return nil }
        return [literalPolygonContour(intersection)]
    }

    /// Guarantees a cutout contour is rendered literally as a polygon.
    ///
    /// `cutoutPoints` are ambiguous in the model: consumers (`StrokeRenderer`,
    /// `VectorStroke.contains`) treat an *exactly* 4-point contour as a circle's
    /// cardinal points (the legacy donut-hole convention) and re-expand it into a
    /// circle. A quadrilateral/clipped-rectangle cutout also has 4 points and would
    /// wrongly become a circle. Subdividing each edge with its midpoint keeps the
    /// identical straight-edged outline while making the vertex count != 4, so the
    /// contour is drawn verbatim.
    private static func literalPolygonContour(_ contour: [CGPoint]) -> [CGPoint] {
        guard contour.count == 4 else { return contour }
        var result: [CGPoint] = []
        result.reserveCapacity(contour.count * 2)
        let count = contour.count
        for index in 0..<count {
            let current = contour[index]
            let next = contour[(index + 1) % count]
            result.append(current)
            result.append(CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2))
        }
        return result
    }

    // MARK: - Sutherland–Hodgman

    /// Clips `subject` against the convex `clip` polygon, returning the intersection.
    /// Exact only when `clip` is convex.
    static func convexClip(subject: [CGPoint], clip: [CGPoint]) -> [CGPoint] {
        guard subject.count >= 3, clip.count >= 3 else { return [] }
        let clipCCW = signedArea(clip) < 0 ? Array(clip.reversed()) : clip
        var output = subject
        let clipCount = clipCCW.count

        for i in 0..<clipCount {
            guard !output.isEmpty else { break }
            let edgeStart = clipCCW[i]
            let edgeEnd = clipCCW[(i + 1) % clipCount]
            let input = output
            output = []
            let inputCount = input.count
            for j in 0..<inputCount {
                let current = input[j]
                let previous = input[(j + inputCount - 1) % inputCount]
                let currentInside = isLeft(edgeStart, edgeEnd, current) >= 0
                let previousInside = isLeft(edgeStart, edgeEnd, previous) >= 0
                if currentInside {
                    if !previousInside {
                        output.append(lineIntersection(previous, current, edgeStart, edgeEnd))
                    }
                    output.append(current)
                } else if previousInside {
                    output.append(lineIntersection(previous, current, edgeStart, edgeEnd))
                }
            }
        }
        return output
    }

    // MARK: - Geometry primitives

    /// Signed area (positive/negative depending on winding under this convention).
    static func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        let count = polygon.count
        for i in 0..<count {
            let a = polygon[i]
            let b = polygon[(i + 1) % count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// True when the polygon turns in a single direction at every vertex.
    static func isConvex(_ polygon: [CGPoint]) -> Bool {
        let pts = normalized(polygon)
        let count = pts.count
        guard count >= 3 else { return false }
        var sign = 0
        for i in 0..<count {
            let a = pts[i]
            let b = pts[(i + 1) % count]
            let c = pts[(i + 2) % count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-9 { continue }
            let current = cross > 0 ? 1 : -1
            if sign == 0 {
                sign = current
            } else if current != sign {
                return false
            }
        }
        return true
    }

    /// Even-odd ray-cast point containment for a polygon contour.
    static func polygon(_ polygon: [CGPoint], contains point: CGPoint) -> Bool {
        let count = polygon.count
        guard count >= 3 else { return false }
        var inside = false
        var j = count - 1
        for i in 0..<count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y) {
                let denominator = pj.y - pi.y
                if abs(denominator) > .ulpOfOne {
                    let xCross = pi.x + (point.y - pi.y) / denominator * (pj.x - pi.x)
                    if point.x < xCross { inside.toggle() }
                }
            }
            j = i
        }
        return inside
    }

    // MARK: - Private helpers

    /// Cross product of `(b - a)` and `(p - a)`; > 0 when `p` is left of a→b.
    private static func isLeft(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> CGFloat {
        (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    }

    /// Intersection of segment `p1→p2` with the infinite line through `a` and `b`.
    private static func lineIntersection(_ p1: CGPoint, _ p2: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let normalX = b.y - a.y
        let normalY = a.x - b.x
        let lineConstant = normalX * a.x + normalY * a.y
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let denominator = normalX * dx + normalY * dy
        guard abs(denominator) > 1e-12 else { return p1 }
        let t = (lineConstant - (normalX * p1.x + normalY * p1.y)) / denominator
        return CGPoint(x: p1.x + t * dx, y: p1.y + t * dy)
    }

    /// Rebuilds a Boolean outline so sharp corners stay corners.
    ///
    /// Edges that came from the cutter become a circular arc when they actually lie on
    /// one circle. The arc's endpoints stay ordinary corners — they are not smoothed
    /// into the curve, and neither are the base shape's other corners. A curved run
    /// that is not circular (an ellipse or a free curve) returns nil so the caller can
    /// keep its own curve fit. Base edges lying on one of `baseArcs` (the base's fillets)
    /// are rebuilt as arcs too, so a rounded corner the cut did not touch stays rounded.
    static func cornerPreservingContour(
        points: [CGPoint],
        cutEdgeStarts: [Int],
        baseArcs: [OutlineArc] = []
    ) -> (points: [CGPoint], smoothCornerIndices: Set<Int>)? {
        let count = points.count
        guard count >= 3, !cutEdgeStarts.isEmpty else { return nil }
        guard cutEdgeStarts.allSatisfy({ $0 >= 0 && $0 < count }) else { return nil }
        let cut = Set(cutEdgeStarts)
        guard cut.count < count else { return nil }

        // edgeArc[i] is the base arc the edge points[i] → points[i + 1] lies on.
        let edgeArc: [Int?] = (0..<count).map { index in
            guard !cut.contains(index) else { return nil }
            let start = points[index]
            let end = points[(index + 1) % count]
            return baseArcs.firstIndex { $0.contains(start) && $0.contains(end) }
        }

        // Start on a vertex whose incoming edge is neither a cut nor part of an arc,
        // so each run is walked as one contiguous sequence.
        func startsRun(_ index: Int) -> Bool {
            let incoming = (index - 1 + count) % count
            return !cut.contains(incoming) && edgeArc[incoming] == nil
        }
        guard let origin = (0..<count).first(where: startsRun)
            ?? (0..<count).first(where: { !cut.contains(($0 - 1 + count) % count) }) else {
            return nil
        }

        var built: [CGPoint] = []
        var smooth = Set<Int>()

        func append(_ point: CGPoint, smoothPoint: Bool) {
            if let last = built.last, hypot(last.x - point.x, last.y - point.y) <= 0.05 {
                return
            }
            if smoothPoint {
                smooth.insert(built.count)
            }
            built.append(point)
        }

        var index = origin
        var isFirst = true
        var steps = 0
        while isFirst || index != origin {
            isFirst = false
            steps += 1
            guard steps <= count + 1 else { return nil }

            if cut.contains(index) {
                var run = [points[index]]
                var cursor = index
                while cut.contains(cursor) {
                    cursor = (cursor + 1) % count
                    run.append(points[cursor])
                    if cursor == origin || run.count > count + 1 { break }
                }
                if run.count >= 4, let arc = circularCutAnchors(run) {
                    for (offset, point) in arc.enumerated() {
                        let isEnd = offset == 0 || offset == arc.count - 1
                        append(point, smoothPoint: !isEnd)
                    }
                } else if runLooksCurved(run) {
                    return nil
                } else {
                    for point in run {
                        append(point, smoothPoint: false)
                    }
                }
                index = cursor
            } else if let arcIndex = edgeArc[index] {
                let arc = baseArcs[arcIndex]
                var run = [points[index]]
                var cursor = index
                while edgeArc[cursor] == arcIndex {
                    cursor = (cursor + 1) % count
                    run.append(points[cursor])
                    if cursor == origin || run.count > count + 1 { break }
                }
                let anchors: [CGPoint]
                if let first = run.first,
                   let last = run.last,
                   let sweep = ShapeGeometry.signedCircularSweep(of: run, around: arc.center, closed: false),
                   abs(sweep) > 0.01 {
                    anchors = ShapeGeometry.defaultCircularAnchors(
                        center: arc.center,
                        radius: arc.radius,
                        start: first,
                        end: last,
                        sweep: sweep,
                        closed: false
                    )
                } else {
                    anchors = [run[0], run[run.count - 1]]
                }
                for (offset, point) in anchors.enumerated() {
                    let isEnd = offset == 0 || offset == anchors.count - 1
                    append(point, smoothPoint: !isEnd)
                }
                index = cursor
            } else {
                append(points[index], smoothPoint: false)
                index = (index + 1) % count
            }
        }

        if built.count > 1,
           let first = built.first,
           let last = built.last,
           hypot(first.x - last.x, first.y - last.y) <= 0.05 {
            smooth.remove(built.count - 1)
            built.removeLast()
        }

        let cleaned = dropCollinearCorners(built, smooth: smooth)
        guard cleaned.points.count >= 3 else { return nil }
        return cleaned
    }

    /// Drops repeated consecutive points and a duplicate closing point.
    private static func normalized(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            if let last = result.last, hypot(last.x - point.x, last.y - point.y) <= 1e-6 { continue }
            result.append(point)
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           hypot(first.x - last.x, first.y - last.y) <= 1e-6 {
            result.removeLast()
        }
        return result
    }

    /// Compact anchors for a cut run that lies on one circle, or nil when it does not.
    private static func circularCutAnchors(_ run: [CGPoint]) -> [CGPoint]? {
        guard let first = run.first, let last = run.last, run.count >= 4 else { return nil }
        let through = run[run.count / 2]
        guard let circle = circumcircle(first, through, last) else { return nil }
        let tolerance = max(1.25, circle.radius * 0.02)
        for point in run {
            if abs(hypot(point.x - circle.center.x, point.y - circle.center.y) - circle.radius) > tolerance {
                return nil
            }
        }
        for index in 0..<(run.count - 1) {
            let start = run[index]
            let end = run[index + 1]
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            if abs(hypot(mid.x - circle.center.x, mid.y - circle.center.y) - circle.radius) > tolerance {
                return nil
            }
        }
        guard let sweep = ShapeGeometry.signedCircularSweep(of: run, around: circle.center, closed: false),
              abs(sweep) > 0.05 else { return nil }
        let anchors = ShapeGeometry.defaultCircularAnchors(
            center: circle.center,
            radius: circle.radius,
            start: first,
            end: last,
            sweep: sweep,
            closed: false
        )
        return anchors.count >= 2 ? anchors : nil
    }

    /// True when the run bows away from its chord, so it is a curve rather than a straight cut.
    private static func runLooksCurved(_ run: [CGPoint]) -> Bool {
        guard let first = run.first, let last = run.last, run.count >= 3 else { return false }
        let dx = last.x - first.x
        let dy = last.y - first.y
        let lengthSquared = dx * dx + dy * dy
        var worst: CGFloat = 0
        for point in run.dropFirst().dropLast() {
            let distance: CGFloat
            if lengthSquared <= 1e-8 {
                distance = hypot(point.x - first.x, point.y - first.y)
            } else {
                let t = max(0, min(1, ((point.x - first.x) * dx + (point.y - first.y) * dy) / lengthSquared))
                let projection = CGPoint(x: first.x + t * dx, y: first.y + t * dy)
                distance = hypot(point.x - projection.x, point.y - projection.y)
            }
            worst = max(worst, distance)
        }
        return worst > 2
    }

    /// Drops vertices that sit on a straight edge. Arc samples and the corners where
    /// an arc meets a straight side are kept, so the junction is not absorbed into the curve.
    private static func dropCollinearCorners(
        _ points: [CGPoint],
        smooth: Set<Int>
    ) -> (points: [CGPoint], smoothCornerIndices: Set<Int>) {
        let count = points.count
        guard count >= 4 else { return (points, smooth) }
        var keep = [Bool](repeating: true, count: count)
        for index in 0..<count where !smooth.contains(index) {
            let previousIndex = (index - 1 + count) % count
            let nextIndex = (index + 1) % count
            if smooth.contains(previousIndex) || smooth.contains(nextIndex) { continue }
            let turn = turnAngle(points[previousIndex], points[index], points[nextIndex])
            if turn < 8 * .pi / 180 {
                keep[index] = false
            }
        }
        var rebuilt: [CGPoint] = []
        var rebuiltSmooth = Set<Int>()
        for index in 0..<count where keep[index] {
            if smooth.contains(index) {
                rebuiltSmooth.insert(rebuilt.count)
            }
            rebuilt.append(points[index])
        }
        guard rebuilt.count >= 3 else { return (points, smooth) }
        return (rebuilt, rebuiltSmooth)
    }

    private static func turnAngle(_ previous: CGPoint, _ current: CGPoint, _ next: CGPoint) -> CGFloat {
        let incoming = CGPoint(x: current.x - previous.x, y: current.y - previous.y)
        let outgoing = CGPoint(x: next.x - current.x, y: next.y - current.y)
        let inLength = hypot(incoming.x, incoming.y)
        let outLength = hypot(outgoing.x, outgoing.y)
        guard inLength > 1e-6, outLength > 1e-6 else { return 0 }
        let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
        let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
        return abs(atan2(cross, dot))
    }

    private static func circumcircle(
        _ a: CGPoint,
        _ b: CGPoint,
        _ c: CGPoint
    ) -> (center: CGPoint, radius: CGFloat)? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 0.001 else { return nil }
        let ux = ((a.x * a.x + a.y * a.y) * (b.y - c.y)
            + (b.x * b.x + b.y * b.y) * (c.y - a.y)
            + (c.x * c.x + c.y * c.y) * (a.y - b.y)) / d
        let uy = ((a.x * a.x + a.y * a.y) * (c.x - b.x)
            + (b.x * b.x + b.y * b.y) * (a.x - c.x)
            + (c.x * c.x + c.y * c.y) * (b.x - a.x)) / d
        let center = CGPoint(x: ux, y: uy)
        let radius = hypot(a.x - center.x, a.y - center.y)
        guard radius > 0.001 else { return nil }
        return (center, radius)
    }
}
