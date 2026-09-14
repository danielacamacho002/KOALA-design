//
//  CircularAnchorCompactor.swift
//  vectr
//

import CoreGraphics
import Foundation

extension ShapeGeometry {
    /// Collapses tessellated circular geometry back to the default editable anchors:
    /// - a full circle → 4 cardinal points (N, E, S, W)
    /// - an arc → 2, 3, or 4 points depending on sweep (endpoints + crossed cardinals)
    ///
    /// Dense sample lists produced by join, boolean cuts, trim, or Add Anchor are
    /// rewritten in place so move/edit keep showing the compact default, not every
    /// tessellation vertex. Already-compact or user-densified (5–11 sparse) shapes
    /// are left alone.
    ///
    /// `rewritingPartialRuns` is for join/boolean leftovers (a circular bite in a
    /// polyline). Leave it off for move / thickness / selection so imported letters
    /// and ovals are not mistaken for circles.
    nonisolated static func withCompactedCircularAnchors(
        _ stroke: VectorStroke,
        rewritingPartialRuns: Bool = true
    ) -> VectorStroke {
        // Compound SVG paths (letters, overlapping ovals) must keep every contour.
        if !stroke.cutoutPoints.isEmpty { return stroke }
        switch stroke.shapeType {
        case .circle:
            return compactStandaloneCircle(stroke)
        case .ellipse:
            return compactStandaloneEllipse(stroke)
        case .arc:
            return compactStandaloneArc(stroke)
        case .curve:
            if let restored = restoreParametricCircular(stroke) {
                return restored
            }
            if stroke.points.count < 8 { return stroke }
            return compactCircularRuns(in: stroke, rewritingPartialRuns: rewritingPartialRuns)
        case .polyline, .rectangle:
            return compactCircularRuns(in: stroke, rewritingPartialRuns: rewritingPartialRuns)
        default:
            return stroke
        }
    }

    /// Default visible anchors for a circular arc of `sweep` radians starting at `start`.
    /// Closed / near-full sweeps become the four axis-aligned cardinals. Short arcs
    /// keep a midpoint so they stay circular without Bézier handles.
    nonisolated static func defaultCircularAnchors(
        center: CGPoint,
        radius: CGFloat,
        start: CGPoint,
        end: CGPoint,
        sweep: CGFloat,
        closed: Bool
    ) -> [CGPoint] {
        guard radius > 0.001 else { return [start, end] }
        if closed || abs(abs(sweep) - 2 * .pi) <= 0.08 {
            return circleCardinalPoints(center: center, radius: radius)
        }

        let startAngle = atan2(start.y - center.y, start.x - center.x)
        func point(at angle: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }

        var interiors = cardinalsInteriorToSweep(startAngle: startAngle, sweep: sweep).map(point(at:))
        let absSweep = abs(sweep)

        if absSweep <= .pi / 2 + 0.03 {
            return [start, point(at: startAngle + sweep / 2), end]
        }
        if absSweep <= .pi + 0.03 {
            if interiors.count == 1 {
                return [start, interiors[0], end]
            }
            return [start, point(at: startAngle + sweep / 2), end]
        }

        if interiors.count >= 2 {
            return [start, interiors[0], interiors[1], end]
        }
        if interiors.count == 1 {
            return [start, interiors[0], point(at: startAngle + sweep * 2 / 3), end]
        }
        return [
            start,
            point(at: startAngle + sweep / 3),
            point(at: startAngle + sweep * 2 / 3),
            end
        ]
    }

    /// Cubic handles that reproduce a circular sweep through `anchors` (all on `center`/`radius`).
    nonisolated static func circularCurveHandles(
        anchors: [CGPoint],
        center: CGPoint,
        radius: CGFloat,
        sweep: CGFloat,
        closed: Bool
    ) -> [CurveHandle] {
        let count = anchors.count
        var handles = Array(repeating: CurveHandle(), count: count)
        guard count >= 2, radius > 0.001, abs(sweep) > 0.0001 else { return handles }

        let segmentCount = closed ? count : count - 1
        for index in 0..<segmentCount {
            let next = (index + 1) % count
            let from = anchors[index]
            let to = anchors[next]
            let midAngle = circularMidAngle(from: from, to: to, center: center, sweep: sweep)
            let through = CGPoint(
                x: center.x + cos(midAngle) * radius,
                y: center.y + sin(midAngle) * radius
            )
            let offsets = circularArcHandleOffsets(
                from: from,
                to: to,
                center: center,
                radius: radius,
                through: through
            )
            handles[index].outOffset = offsets.outFromStart
            handles[next].inOffset = offsets.inToEnd
        }
        return handles
    }
}

// MARK: - Standalone shapes

private extension ShapeGeometry {
    nonisolated static func compactStandaloneCircle(_ stroke: VectorStroke) -> VectorStroke {
        if stroke.points.count < 8 { return stroke }
        guard let circle = fittedCircleIfCircular(stroke.points, closed: true) else {
            if stroke.points.count >= 8, let fitted = fitCircle(from: stroke.points) {
                return replacingPoints(
                    stroke,
                    points: circleCardinalPoints(center: fitted.center, radius: fitted.radius),
                    shapeType: .circle,
                    closed: true
                )
            }
            return stroke
        }
        return replacingPoints(
            stroke,
            points: circleCardinalPoints(center: circle.center, radius: circle.radius),
            shapeType: .circle,
            closed: true
        )
    }

    nonisolated static func compactStandaloneEllipse(_ stroke: VectorStroke) -> VectorStroke {
        if stroke.points.count == 4, ellipseFromCardinalPoints(stroke.points) != nil {
            return stroke
        }
        return stroke
    }

    nonisolated static func compactStandaloneArc(_ stroke: VectorStroke) -> VectorStroke {
        // Sparse arcs are already at the default 2–4 anchors (or user-edited).
        // Re-emitting cardinals here would insert extra points while dragging.
        if stroke.points.count < 8 { return stroke }
        guard let geometry = circularGeometry(from: stroke.points, closed: stroke.isClosed) else {
            return stroke
        }
        let anchors = defaultCircularAnchors(
            center: geometry.center,
            radius: geometry.radius,
            start: geometry.start,
            end: geometry.end,
            sweep: geometry.sweep,
            closed: stroke.isClosed && abs(abs(geometry.sweep) - 2 * .pi) <= 0.08
        )

        if stroke.isClosed, anchors.count == 4, abs(abs(geometry.sweep) - 2 * .pi) <= 0.08 {
            return replacingPoints(stroke, points: anchors, shapeType: .circle, closed: true)
        }

        if anchors.count == stroke.points.count,
           zip(anchors, stroke.points).allSatisfy({ hypot($0.x - $1.x, $0.y - $1.y) <= 0.05 }) {
            return stroke
        }
        return replacingPoints(stroke, points: anchors, shapeType: .arc, closed: false)
    }
}

// MARK: - Mixed polylines / curves

private extension ShapeGeometry {
    static let denseSampleThreshold = 8

    /// Turns a Bézier that is still a circle/arc (or circular runs plus straight
    /// sides) back into parametric `.circle` / `.arc` / `.polyline` storage.
    nonisolated static func restoreParametricCircular(_ stroke: VectorStroke) -> VectorStroke? {
        let points = stroke.points
        guard points.count >= 2 else { return nil }

        // Four closed anchors are often an ellipse (or a cubic oval). Only promote
        // when every vertex actually sits on one circle.
        if stroke.isClosed, points.count == 4,
           let circle = fittedCircleIfCircular(points, closed: true) {
            return replacingPoints(
                stroke,
                points: circleCardinalPoints(center: circle.center, radius: circle.radius),
                shapeType: .circle,
                closed: true
            )
        }
        if stroke.isClosed, points.count >= 8,
           let circle = fittedCircleIfCircular(points, closed: true) {
            return replacingPoints(
                stroke,
                points: circleCardinalPoints(center: circle.center, radius: circle.radius),
                shapeType: .circle,
                closed: true
            )
        }

        if !stroke.isClosed, let geometry = circularGeometry(from: points, closed: false) {
            let anchors = defaultCircularAnchors(
                center: geometry.center,
                radius: geometry.radius,
                start: geometry.start,
                end: geometry.end,
                sweep: geometry.sweep,
                closed: false
            )
            return replacingPoints(stroke, points: anchors, shapeType: .arc, closed: false)
        }

        if stroke.shapeType == .curve,
           let handles = stroke.curveHandles,
           handles.count == points.count,
           curveIsCircularOrStraight(points: points, handles: handles, closed: stroke.isClosed) {
            return demoteCircularCurveToPolyline(stroke, handles: handles)
        }
        return nil
    }

    nonisolated static func curveIsCircularOrStraight(
        points: [CGPoint],
        handles: [CurveHandle],
        closed: Bool
    ) -> Bool {
        let count = points.count
        let segmentCount = closed ? count : count - 1
        var sawCircular = false
        for index in 0..<segmentCount {
            let next = (index + 1) % count
            let curved = hypot(handles[index].outOffset.x, handles[index].outOffset.y) > 0.01
                || hypot(handles[next].inOffset.x, handles[next].inOffset.y) > 0.01
            guard curved else { continue }
            let from = points[index]
            let to = points[next]
            let control1 = CGPoint(
                x: from.x + handles[index].outOffset.x,
                y: from.y + handles[index].outOffset.y
            )
            let control2 = CGPoint(
                x: to.x + handles[next].inOffset.x,
                y: to.y + handles[next].inOffset.y
            )
            let samples = [CGFloat(0), 0.25, 0.5, 0.75, 1].map {
                cubicBezierPoint(from, control1, control2, to, t: $0)
            }
            guard fittedCircleIfCircular(samples, closed: false) != nil else { return false }
            sawCircular = true
        }
        return sawCircular
    }

    nonisolated static func demoteCircularCurveToPolyline(
        _ stroke: VectorStroke,
        handles: [CurveHandle]
    ) -> VectorStroke {
        let points = stroke.points
        let count = points.count
        let closed = stroke.isClosed
        let segmentCount = closed ? count : count - 1
        var newPoints: [CGPoint] = []
        var smooth = Set<Int>()

        func append(_ point: CGPoint) {
            if let last = newPoints.last, hypot(last.x - point.x, last.y - point.y) <= 0.0005 {
                return
            }
            newPoints.append(point)
        }

        func isCurved(_ index: Int) -> Bool {
            let next = (index + 1) % count
            return hypot(handles[index].outOffset.x, handles[index].outOffset.y) > 0.01
                || hypot(handles[next].inOffset.x, handles[next].inOffset.y) > 0.01
        }

        var index = 0
        while index < segmentCount {
            append(points[index])
            if !isCurved(index) {
                index += 1
                continue
            }
            var end = index + 1
            while end < segmentCount, isCurved(end) {
                end += 1
            }
            let runCount = end - index + 1
            if runCount == 2 {
                let from = points[index]
                let to = points[end % count]
                let control1 = CGPoint(
                    x: from.x + handles[index].outOffset.x,
                    y: from.y + handles[index].outOffset.y
                )
                let next = end % count
                let control2 = CGPoint(
                    x: to.x + handles[next].inOffset.x,
                    y: to.y + handles[next].inOffset.y
                )
                append(cubicBezierPoint(from, control1, control2, to, t: 0.5))
                if let mid = newPoints.indices.last {
                    smooth.insert(mid)
                }
            } else {
                for offset in 1..<(runCount - 1) {
                    append(points[index + offset])
                    if let mid = newPoints.indices.last {
                        smooth.insert(mid)
                    }
                }
            }
            index = end
        }
        if !closed {
            append(points[count - 1])
        }

        guard newPoints.count >= 2 else { return stroke }
        return replacingPoints(
            stroke,
            points: newPoints,
            shapeType: .polyline,
            closed: closed,
            smoothCornerIndices: smooth.isEmpty ? nil : smooth
        )
    }

    nonisolated static func compactCircularRuns(
        in stroke: VectorStroke,
        rewritingPartialRuns: Bool = true
    ) -> VectorStroke {
        let points = stroke.points
        guard points.count >= denseSampleThreshold else { return stroke }

        let closed = stroke.isClosed
        let runs = circularRuns(in: points, closed: closed)
        guard !runs.isEmpty else { return stroke }

        if closed, runs.count == 1, Set(runs[0]).count == points.count,
           let geometry = circularGeometry(from: points, closed: true) {
            return replacingPoints(
                stroke,
                points: circleCardinalPoints(center: geometry.center, radius: geometry.radius),
                shapeType: .circle,
                closed: true
            )
        }

        if !closed, runs.count == 1, Set(runs[0]).count == points.count {
            var draft = stroke
            draft.shapeType = .arc
            return compactStandaloneArc(draft)
        }

        guard rewritingPartialRuns else { return stroke }
        return rebuildStroke(stroke, replacing: runs)
    }

    nonisolated static func circularRuns(in points: [CGPoint], closed: Bool) -> [[Int]] {
        let count = points.count
        guard count >= denseSampleThreshold else { return [] }

        var candidates: [[Int]] = []
        let starts = closed ? count : max(0, count - denseSampleThreshold + 1)
        for start in 0..<starts {
            if let run = growCircularRun(in: points, start: start, closed: closed) {
                candidates.append(run)
            }
        }
        candidates.sort { $0.count > $1.count }

        var accepted: [[Int]] = []
        var used = Set<Int>()
        for run in candidates {
            if run.contains(where: { used.contains($0) }) { continue }
            accepted.append(run)
            used.formUnion(run)
        }
        return accepted
    }

    nonisolated static func growCircularRun(in points: [CGPoint], start: Int, closed: Bool) -> [Int]? {
        let count = points.count
        let maxLength = closed ? count : count - start
        guard maxLength >= denseSampleThreshold else { return nil }

        var run = Array(0..<denseSampleThreshold).map { index in
            closed ? (start + index) % count : start + index
        }
        guard let seed = fittedCircleIfCircular(run.map { points[$0] }, closed: false) else {
            return nil
        }

        var length = denseSampleThreshold
        while length < maxLength {
            let nextIndex = closed ? (start + length) % count : start + length
            if !pointLiesOnCircle(points[nextIndex], seed) { break }
            let previous = points[run[run.count - 1]]
            let midpoint = CGPoint(
                x: (previous.x + points[nextIndex].x) / 2,
                y: (previous.y + points[nextIndex].y) / 2
            )
            if !edgeHugsCircle(from: previous, to: points[nextIndex], circle: seed, midpoint: midpoint) {
                break
            }
            // Straight sides that are chords of the same circle (a line or
            // rectangle joined to an arc) must not be absorbed into the run.
            if circularStepRadians(from: previous, to: points[nextIndex], center: seed.center) > .pi / 7 {
                break
            }
            run.append(nextIndex)
            length += 1
        }
        return run.count >= denseSampleThreshold ? run : nil
    }

    nonisolated static func rebuildStroke(_ stroke: VectorStroke, replacing runs: [[Int]]) -> VectorStroke {
        let points = stroke.points
        let count = points.count
        let closed = stroke.isClosed
        let runByStart = Dictionary(
            uniqueKeysWithValues: runs.map { (runStart($0, count: count), $0) }
        )
        let wrappedMembership = Set(runs.flatMap { run in
            let start = runStart(run, count: count)
            return run.filter { $0 < start }
        })

        var newPoints: [CGPoint] = []
        var smooth = Set<Int>()
        var anyCircular = false
        var index = 0

        func appendStraight(_ point: CGPoint) {
            if let last = newPoints.last, hypot(last.x - point.x, last.y - point.y) <= 0.0005 {
                return
            }
            newPoints.append(point)
        }

        func appendCompact(_ compact: [CGPoint]) {
            guard let first = compact.first else { return }
            let dropFirst = newPoints.last.map { hypot($0.x - first.x, $0.y - first.y) <= 0.05 } ?? false
            let startIndex = dropFirst ? newPoints.count - 1 : newPoints.count
            if !dropFirst {
                newPoints.append(first)
            }
            for point in compact.dropFirst() {
                newPoints.append(point)
            }
            if compact.count >= 3 {
                for offset in 1..<(compact.count - 1) {
                    smooth.insert(startIndex + offset)
                }
                anyCircular = true
            }
        }

        while index < count {
            if wrappedMembership.contains(index) {
                index += 1
                continue
            }
            if let run = runByStart[index],
               let geometry = circularGeometry(from: run.map { points[$0] }, closed: false) {
                let compact = defaultCircularAnchors(
                    center: geometry.center,
                    radius: geometry.radius,
                    start: geometry.start,
                    end: geometry.end,
                    sweep: geometry.sweep,
                    closed: false
                )
                appendCompact(compact)
                let runSet = Set(run)
                repeat { index += 1 } while index < count && runSet.contains(index)
                continue
            }
            appendStraight(points[index])
            index += 1
        }

        if closed, let first = newPoints.first, let last = newPoints.last,
           hypot(first.x - last.x, first.y - last.y) <= 0.0005, newPoints.count > 1 {
            newPoints.removeLast()
            if let lastIndex = newPoints.indices.last {
                smooth.remove(lastIndex + 1)
            }
        }

        guard newPoints.count >= 2, newPoints.count < points.count else { return stroke }

        return replacingPoints(
            stroke,
            points: newPoints,
            shapeType: .polyline,
            closed: closed,
            smoothCornerIndices: anyCircular && !smooth.isEmpty ? smooth : nil
        )
    }

    nonisolated static func runStart(_ run: [Int], count: Int) -> Int {
        let set = Set(run)
        if set.count == count, let first = run.first { return first }
        for index in run {
            let predecessor = (index - 1 + count) % count
            if !set.contains(predecessor) { return index }
        }
        return run[0]
    }
}

// MARK: - Geometry helpers

private struct CircularGeometry {
    var center: CGPoint
    var radius: CGFloat
    var start: CGPoint
    var end: CGPoint
    var sweep: CGFloat
}

private extension ShapeGeometry {
    nonisolated static func circularGeometry(from points: [CGPoint], closed: Bool) -> CircularGeometry? {
        guard let circle = fittedCircleIfCircular(points, closed: closed),
              let first = points.first, let last = points.last else { return nil }
        guard let sweep = sweepFrom(points, center: circle.center, closed: closed) else { return nil }
        return CircularGeometry(
            center: circle.center,
            radius: circle.radius,
            start: first,
            end: closed ? first : last,
            sweep: sweep
        )
    }

    nonisolated static func fittedCircleIfCircular(
        _ points: [CGPoint],
        closed: Bool
    ) -> (center: CGPoint, radius: CGFloat)? {
        guard points.count >= 3 else { return nil }
        let i0 = 0
        let i1 = points.count / 3
        let i2 = min(points.count - 1, (2 * points.count) / 3)
        guard i0 != i1, i1 != i2, i0 != i2,
              let circle = circumcircle(points[i0], points[i1], points[i2]) else {
            return nil
        }
        let tolerance = circleTolerance(radius: circle.radius)
        for point in points {
            if !pointLiesOnCircle(point, circle, tolerance: tolerance) { return nil }
        }
        // Sparse defining anchors (2–4) already sit on the circle; their chords are
        // long and must not be rejected. Edge-midpoint hugging only applies to
        // tessellations, where it distinguishes a sampled arc from a square/hexagon.
        if points.count >= 8 {
            let edgeCount = closed ? points.count : points.count - 1
            for index in 0..<edgeCount {
                let a = points[index]
                let b = points[(index + 1) % points.count]
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                if !edgeHugsCircle(from: a, to: b, circle: circle, midpoint: mid, tolerance: tolerance) {
                    return nil
                }
            }
        }
        return circle
    }

    nonisolated static func sweepFrom(_ points: [CGPoint], center: CGPoint, closed: Bool) -> CGFloat? {
        signedCircularSweep(of: points, around: center, closed: closed)
    }

    nonisolated static func cardinalsInteriorToSweep(startAngle: CGFloat, sweep: CGFloat) -> [CGFloat] {
        let cardinals: [CGFloat] = [-.pi / 2, 0, .pi / 2, .pi]
        var hits: [(parameter: CGFloat, angle: CGFloat)] = []
        for cardinal in cardinals {
            var delta = cardinal - startAngle
            if sweep >= 0 {
                while delta <= 0 { delta += 2 * .pi }
                while delta >= 2 * .pi { delta -= 2 * .pi }
                if delta > 0.04, delta < sweep - 0.04 {
                    hits.append((delta, cardinal))
                }
            } else {
                while delta >= 0 { delta -= 2 * .pi }
                while delta <= -2 * .pi { delta += 2 * .pi }
                if delta < -0.04, delta > sweep + 0.04 {
                    hits.append((abs(delta), cardinal))
                }
            }
        }
        return hits.sorted { $0.parameter < $1.parameter }.map(\.angle)
    }

    nonisolated static func circularMidAngle(from start: CGPoint, to end: CGPoint, center: CGPoint, sweep: CGFloat) -> CGFloat {
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var segment = endAngle - startAngle
        if sweep >= 0 {
            if segment < 0 { segment += 2 * .pi }
        } else if segment > 0 {
            segment -= 2 * .pi
        }
        return startAngle + segment / 2
    }

    nonisolated static func circumcircle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> (center: CGPoint, radius: CGFloat)? {
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

    nonisolated static func circleTolerance(radius: CGFloat) -> CGFloat {
        max(0.75, radius * 0.025)
    }

    nonisolated static func circularStepRadians(from a: CGPoint, to b: CGPoint, center: CGPoint) -> CGFloat {
        let start = atan2(a.y - center.y, a.x - center.x)
        let end = atan2(b.y - center.y, b.x - center.x)
        var step = end - start
        if step > .pi { step -= 2 * .pi }
        if step < -.pi { step += 2 * .pi }
        return abs(step)
    }

    nonisolated static func pointLiesOnCircle(
        _ point: CGPoint,
        _ circle: (center: CGPoint, radius: CGFloat),
        tolerance: CGFloat? = nil
    ) -> Bool {
        let allowed = tolerance ?? circleTolerance(radius: circle.radius)
        return abs(hypot(point.x - circle.center.x, point.y - circle.center.y) - circle.radius) <= allowed
    }

    nonisolated static func edgeHugsCircle(
        from a: CGPoint,
        to b: CGPoint,
        circle: (center: CGPoint, radius: CGFloat),
        midpoint: CGPoint,
        tolerance: CGFloat? = nil
    ) -> Bool {
        let allowed = tolerance ?? circleTolerance(radius: circle.radius)
        let chord = hypot(b.x - a.x, b.y - a.y)
        guard chord > 0.0001 else { return true }
        // A square's vertices lie on a circle, but its edge midpoints sit far inside.
        // Tessellated arcs keep midpoints within a small sagitta of the rim.
        let sagitta = abs(hypot(midpoint.x - circle.center.x, midpoint.y - circle.center.y) - circle.radius)
        let maxSagitta = max(allowed, circle.radius * (1 - cos(min(.pi / 8, chord / circle.radius / 2))))
        return sagitta <= maxSagitta * 2
    }

    nonisolated static func replacingPoints(
        _ stroke: VectorStroke,
        points: [CGPoint],
        shapeType: StrokeShapeType,
        closed: Bool,
        handles: [CurveHandle]? = nil,
        smoothCornerIndices: Set<Int>? = nil
    ) -> VectorStroke {
        var updated = stroke
        updated.points = points
        updated.shapeType = shapeType
        updated.isClosed = closed
        updated.curveHandles = (shapeType == .curve) ? handles : nil
        if shapeType == .circle || shapeType == .ellipse || shapeType == .arc {
            updated.smoothCornerIndices = nil
        } else {
            updated.smoothCornerIndices = smoothCornerIndices
        }
        if shapeType == .circle || shapeType == .ellipse {
            updated.shapeRotation = stroke.shapeRotation
        } else {
            updated.shapeRotation = nil
            updated.rotationBasePoints = nil
            updated.rotationBaseCenter = nil
        }
        return updated
    }
}
