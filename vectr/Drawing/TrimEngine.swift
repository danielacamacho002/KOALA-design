//
//  TrimEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

/// CAD-style trim: remove the contour span between the two cut points that bound a tap.
/// Cut points come from intersections with other strokes, attached endpoints, and — for
/// circles/ellipses — the cardinal quadrant anchors so each quarter can be removed.
enum TrimEngine {
    struct TrimResult {
        /// Replaces the original stroke.
        var stroke: VectorStroke
        var strokeID: UUID
        /// When trimming the middle of an open path splits it in two.
        var additionalStroke: VectorStroke?
        /// The span this trim drops, for the pre-cut highlight.
        var removedSegment: RemovedSegmentGeometry?
    }

    /// The about-to-be-removed span as a flattened open polyline in document space.
    struct RemovedSegmentGeometry {
        var points: [CGPoint]
        var strokeWidth: CGFloat
    }

    private struct ContourHit {
        var distance: CGFloat
        var point: CGPoint
        var segmentIndex: Int
        var t: CGFloat
    }

    private struct Cut {
        var distance: CGFloat
        var point: CGPoint
    }

    /// Trims the stroke nearest `tapPoint` (preferring `preferredStrokeID` when close).
    static func trim(
        at tapPoint: CGPoint,
        threshold: CGFloat,
        strokes: [VectorStroke],
        preferredStrokeID: UUID? = nil
    ) -> TrimResult? {
        guard let match = nearestContour(
            to: tapPoint,
            threshold: threshold,
            strokes: strokes,
            preferredStrokeID: preferredStrokeID
        ) else { return nil }

        // Closed arc / pie: the straight last→first chord is only implied by `isClosed`,
        // not stored as geometry. Tapping it should open the arc, not treat the pie as
        // a full circle (which cannot drop that chord).
        if let opened = openedStrokeIfTappingClosingChord(
            match.stroke,
            renderPoints: match.renderPoints,
            segmentIndex: match.segmentIndex,
            t: match.t
        ) {
            // The removed span is the chord itself: last sample back to the first.
            let chord = RemovedSegmentGeometry(
                points: [match.renderPoints[match.renderPoints.count - 1], match.renderPoints[0]],
                strokeWidth: match.stroke.strokeWidth
            )
            return TrimResult(
                stroke: opened,
                strokeID: match.stroke.id,
                additionalStroke: nil,
                removedSegment: chord
            )
        }

        let others = strokes.filter { $0.id != match.stroke.id }
        let cuts = collectCuts(
            for: match.stroke,
            renderPoints: match.renderPoints,
            otherStrokes: others
        )
        guard cuts.count >= 2 else { return nil }

        if match.stroke.isClosed {
            return trimClosed(
                match.stroke,
                renderPoints: match.renderPoints,
                tapDistance: match.distance,
                cuts: cuts
            )
        }
        return trimOpen(
            match.stroke,
            renderPoints: match.renderPoints,
            tapDistance: match.distance,
            cuts: cuts
        )
    }

    // MARK: - Closed trim

    private static func trimClosed(
        _ target: VectorStroke,
        renderPoints: [CGPoint],
        tapDistance: CGFloat,
        cuts: [Cut]
    ) -> TrimResult? {
        let totalLength = contourLength(renderPoints, closed: true)
        guard totalLength > 0.001 else { return nil }

        let ordered = cuts.sorted { $0.distance < $1.distance }
        guard let bounds = boundingCuts(around: tapDistance, cuts: ordered, totalLength: totalLength) else {
            return nil
        }

        // Mirror of the kept span below: prev → next is what goes away.
        let removed = removedGeometry(
            target,
            from: bounds.prev,
            to: bounds.next,
            renderPoints: renderPoints,
            closed: true
        )

        // Prefer circular arc result so curvature survives quadrant trims.
        // Skip when the closed contour is a pie (arc + chord): length ratios are not
        // a circle sweep, and snapping the chord onto the circle invents geometry.
        if contourLiesOnCircle(target, renderPoints: renderPoints),
           let arcStroke = trimmedCircleArc(
            target,
            renderPoints: renderPoints,
            from: bounds.next,
            to: bounds.prev,
            totalLength: totalLength
        ) {
            return TrimResult(
                stroke: arcStroke,
                strokeID: target.id,
                additionalStroke: nil,
                removedSegment: removed
            )
        }

        let kept = extractSpan(
            from: bounds.next.distance,
            to: bounds.prev.distance,
            points: renderPoints,
            closed: true,
            startPoint: bounds.next.point,
            endPoint: bounds.prev.point
        )
        guard kept.count >= 2 else { return nil }
        let keepAsArc = target.shapeType == .arc
            && kept.count >= 3
            && keptPointsLieOnCircle(kept, target: target)
        let draft = openStroke(
            from: target,
            points: keepAsArc ? collapsedArcAnchors(kept) : kept,
            shapeType: keepAsArc ? .arc : .polyline
        )
        return TrimResult(
            stroke: ShapeGeometry.withCompactedCircularAnchors(draft),
            strokeID: target.id,
            additionalStroke: nil,
            removedSegment: removed
        )
    }

    /// The span between two bounding cuts, flattened for the pre-cut highlight.
    private static func removedGeometry(
        _ target: VectorStroke,
        from prev: Cut,
        to next: Cut,
        renderPoints: [CGPoint],
        closed: Bool
    ) -> RemovedSegmentGeometry? {
        let points = extractSpan(
            from: prev.distance,
            to: next.distance,
            points: renderPoints,
            closed: closed,
            startPoint: prev.point,
            endPoint: next.point
        )
        guard points.count >= 2 else { return nil }
        return RemovedSegmentGeometry(points: points, strokeWidth: target.strokeWidth)
    }

    /// Opens a closed arc (pie) when the tap lands on the implied closing chord.
    /// That chord is not stored — `isClosed` just connects the last sample back to the first.
    private static func openedStrokeIfTappingClosingChord(
        _ target: VectorStroke,
        renderPoints: [CGPoint],
        segmentIndex: Int,
        t: CGFloat
    ) -> VectorStroke? {
        guard target.isClosed,
              target.shapeType == .arc,
              renderPoints.count >= 2,
              segmentIndex == renderPoints.count - 1,
              t > 0.02,
              t < 0.98 else { return nil }

        let chordLength = segmentLength(renderPoints[renderPoints.count - 1], renderPoints[0])
        guard chordLength > 0.5 else { return nil }

        var opened = target
        opened.isClosed = false
        opened.cutoutPoints = []
        return opened
    }

    /// True when the closed contour itself lies on the underlying circle (a full
    /// circle or a tessellated closed ring), not a pie whose last→first edge is a chord.
    private static func contourLiesOnCircle(_ target: VectorStroke, renderPoints: [CGPoint]) -> Bool {
        guard renderPoints.count >= 2, let circle = circularSource(for: target) else { return false }
        guard target.isClosed else { return true }
        let first = renderPoints[0]
        let last = renderPoints[renderPoints.count - 1]
        let mid = CGPoint(x: (first.x + last.x) * 0.5, y: (first.y + last.y) * 0.5)
        let dist = hypot(mid.x - circle.center.x, mid.y - circle.center.y)
        return abs(dist - circle.radius) <= max(0.5, circle.radius * 0.02)
    }

    /// Collapse a circular tessellation back to the three anchors an `.arc` stroke stores.
    private static func collapsedArcAnchors(_ points: [CGPoint]) -> [CGPoint] {
        ShapeGeometry.arcAnchorPoints(points) ?? points
    }

    private static func keptPointsLieOnCircle(_ points: [CGPoint], target: VectorStroke) -> Bool {
        guard let circle = circularSource(for: target) else { return false }
        let tolerance = max(0.5, circle.radius * 0.02)
        for point in points {
            let dist = hypot(point.x - circle.center.x, point.y - circle.center.y)
            if abs(dist - circle.radius) > tolerance { return false }
        }
        return true
    }

    // MARK: - Open trim

    private static func trimOpen(
        _ target: VectorStroke,
        renderPoints: [CGPoint],
        tapDistance: CGFloat,
        cuts: [Cut]
    ) -> TrimResult? {
        let totalLength = contourLength(renderPoints, closed: false)
        guard totalLength > 0.001,
              let first = renderPoints.first,
              let last = renderPoints.last else { return nil }

        var ordered = cuts
        ordered.append(Cut(distance: 0, point: first))
        ordered.append(Cut(distance: totalLength, point: last))
        ordered = dedupeCuts(ordered, totalLength: totalLength, closed: false)
            .sorted { $0.distance < $1.distance }
        guard ordered.count >= 2 else { return nil }

        guard let bounds = boundingCutsOpen(around: tapDistance, cuts: ordered) else { return nil }

        let removed = removedGeometry(
            target,
            from: bounds.prev,
            to: bounds.next,
            renderPoints: renderPoints,
            closed: false
        )

        let left = extractSpan(
            from: 0,
            to: bounds.prev.distance,
            points: renderPoints,
            closed: false,
            startPoint: first,
            endPoint: bounds.prev.point
        )
        let right = extractSpan(
            from: bounds.next.distance,
            to: totalLength,
            points: renderPoints,
            closed: false,
            startPoint: bounds.next.point,
            endPoint: last
        )

        let leftValid = left.count >= 2
        let rightValid = right.count >= 2
        guard leftValid || rightValid else { return nil }

        if leftValid, rightValid {
            // Keep both pieces when a middle span is removed.
            let primary = openStroke(
                from: target,
                points: refinedOpenPoints(left, target: target),
                shapeType: demotedShapeType(target)
            )
            var secondary = openStroke(
                from: target,
                points: refinedOpenPoints(right, target: target),
                shapeType: demotedShapeType(target)
            )
            secondary.id = UUID()
            return TrimResult(
                stroke: primary,
                strokeID: target.id,
                additionalStroke: secondary,
                removedSegment: removed
            )
        }

        let kept = leftValid ? left : right
        return TrimResult(
            stroke: openStroke(
                from: target,
                points: refinedOpenPoints(kept, target: target),
                shapeType: demotedShapeType(target)
            ),
            strokeID: target.id,
            additionalStroke: nil,
            removedSegment: removed
        )
    }

    /// Snap open circular leftovers onto the true circle without changing center.
    /// Avoids regenerating through a fitted/centroid center, which drifts for partial arcs.
    private static func refinedOpenPoints(_ points: [CGPoint], target: VectorStroke) -> [CGPoint] {
        guard points.count >= 2,
              let circle = circularSource(for: target) else { return points }
        return snapPointsToCircle(points, center: circle.center, radius: circle.radius)
    }

    // MARK: - Circle / ellipse parametric trim

    /// Builds an open circular arc from `startCut` to `endCut` along the kept (non-tapped) sweep.
    /// Anchors are emitted from the original center and sweep so the leftover stays circular
    /// and does not pick up a closing chord.
    private static func trimmedCircleArc(
        _ target: VectorStroke,
        renderPoints: [CGPoint],
        from startCut: Cut,
        to endCut: Cut,
        totalLength: CGFloat
    ) -> VectorStroke? {
        guard let circle = circularSource(for: target) else { return nil }

        let start = projectOntoCircle(startCut.point, center: circle.center, radius: circle.radius)
        let end = projectOntoCircle(endCut.point, center: circle.center, radius: circle.radius)

        var keptLength = endCut.distance - startCut.distance
        if keptLength <= 0 { keptLength += totalLength }
        let sweep = (keptLength / totalLength) * 2 * .pi
        guard sweep > 0.05, sweep < 2 * .pi - 0.05 else { return nil }

        // Build the leftover from the known center/sweep. Going through the 64-sample
        // tessellation and re-compacting can leave sparse anchors that render as a
        // straight chord across the opening.
        let anchors = ShapeGeometry.defaultCircularAnchors(
            center: circle.center,
            radius: circle.radius,
            start: start,
            end: end,
            sweep: sweep,
            closed: false
        )
        guard anchors.count >= 2 else { return nil }
        return openStroke(from: target, points: anchors, shapeType: .arc)
    }

    private static func snapPointsToCircle(
        _ points: [CGPoint],
        center: CGPoint,
        radius: CGFloat
    ) -> [CGPoint] {
        var snapped: [CGPoint] = []
        snapped.reserveCapacity(points.count)
        for point in points {
            let projected = projectOntoCircle(point, center: center, radius: radius)
            if let last = snapped.last,
               hypot(last.x - projected.x, last.y - projected.y) <= 0.0005 {
                continue
            }
            snapped.append(projected)
        }
        return snapped
    }

    private static func circularSource(for stroke: VectorStroke) -> (center: CGPoint, radius: CGFloat)? {
        switch stroke.shapeType {
        case .circle:
            // Use stored cardinals (not oriented handles) so rotation metadata cannot
            // shift the reconstructed center away from the rendered circle.
            return ShapeGeometry.circleFromCardinalPoints(stroke.points)
        case .arc:
            return ShapeGeometry.arcCircle(for: stroke)
        default:
            return nil
        }
    }

    private static func projectOntoCircle(_ point: CGPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let length = hypot(dx, dy)
        guard length > 0.0001 else {
            return CGPoint(x: center.x + radius, y: center.y)
        }
        return CGPoint(x: center.x + dx / length * radius, y: center.y + dy / length * radius)
    }

    // MARK: - Cut collection

    private static func collectCuts(
        for target: VectorStroke,
        renderPoints: [CGPoint],
        otherStrokes: [VectorStroke]
    ) -> [Cut] {
        let closed = target.isClosed
        let totalLength = contourLength(renderPoints, closed: closed)
        guard totalLength > 0.001 else { return [] }

        var cuts: [Cut] = []

        // Cardinal anchors so each circle/ellipse quadrant (and remaining arc
        // quadrants) can be trimmed independently.
        let cardinalHandles: [CGPoint]
        if target.shapeType == .circle || target.shapeType == .ellipse {
            cardinalHandles = ShapeGeometry.handlePoints(for: target)
        } else if let circle = ShapeGeometry.arcCircle(for: target) {
            cardinalHandles = ShapeGeometry.circleCardinalPoints(
                center: circle.center,
                radius: circle.radius
            )
        } else {
            cardinalHandles = []
        }
        for handle in cardinalHandles {
            if let hit = projectOntoContour(handle, points: renderPoints, closed: closed),
               hit.radialDistance <= 0.5 {
                // Keep the true handle location (on the circle), not the chord projection.
                cuts.append(Cut(distance: hit.distance, point: handle))
            }
        }

        // A closed arc's start and end are always cut points, so the implied
        // closing chord can be removed even when nothing else intersects it.
        if closed, target.shapeType == .arc, renderPoints.count >= 2 {
            let openLength = contourLength(renderPoints, closed: false)
            cuts.append(Cut(distance: 0, point: renderPoints[0]))
            cuts.append(Cut(distance: openLength, point: renderPoints[renderPoints.count - 1]))
        }

        // Intersections with every other stroke (full contours).
        let targetCount = closed ? renderPoints.count : max(renderPoints.count - 1, 0)
        for other in otherStrokes {
            for segment in segments(for: other) {
                for index in 0..<targetCount {
                    let a = renderPoints[index]
                    let b = renderPoints[(index + 1) % renderPoints.count]
                    if let hit = segmentIntersection(
                        p1: a, p2: b,
                        p3: segment.start, p4: segment.end,
                        allowExtended: other.isConstruction
                    ) {
                        let t = parameter(on: a, b, point: hit)
                        if t > 0.001, t < 0.999 {
                            let distance = distanceToSegmentStart(
                                segmentIndex: index,
                                t: t,
                                points: renderPoints
                            )
                            cuts.append(Cut(distance: distance, point: hit))
                        }
                    }
                }
            }

            // Endpoints attached to this contour (shared anchors).
            let otherRender = ShapeGeometry.renderPoints(for: other)
            for endpoint in [otherRender.first, otherRender.last].compactMap({ $0 }) {
                if let hit = projectOntoContour(endpoint, points: renderPoints, closed: closed),
                   hypot(hit.point.x - endpoint.x, hit.point.y - endpoint.y) <= 0.5 {
                    cuts.append(Cut(distance: hit.distance, point: hit.point))
                }
            }
        }

        // Existing vertices act as cut points when they are true corners (so tapping a
        // polygon/rectangle edge removes only that edge, even when a line crosses the
        // shape) or when they sit on another stroke (baked intersection anchors). Near-
        // collinear points on demoted circles / curves are skipped so those keep trimming
        // by intersection spans instead of shedding a single tessellation segment.
        if target.shapeType != .circle, target.shapeType != .ellipse {
            for (index, vertex) in renderPoints.enumerated() {
                let isCorner = isCornerVertex(renderPoints, index: index, closed: closed)
                let touches = touchesAnyStroke(vertex, strokes: otherStrokes, tolerance: 0.5)
                guard isCorner || touches else { continue }
                let distance = distanceToSegmentStart(segmentIndex: index, t: 0, points: renderPoints)
                cuts.append(Cut(distance: distance, point: vertex))
            }
        }

        return dedupeCuts(cuts, totalLength: totalLength, closed: closed)
    }

    /// True when the vertex is a real corner: the incoming and outgoing edges change
    /// direction by more than `toleranceDegrees`. Open-path endpoints (one edge) are not
    /// corners. The threshold sits well above the per-vertex turn of tessellated circles
    /// (~5.6° at 64 segments) so curved geometry is not mistaken for corners.
    private static func isCornerVertex(
        _ points: [CGPoint],
        index: Int,
        closed: Bool,
        toleranceDegrees: CGFloat = 15
    ) -> Bool {
        let count = points.count
        guard count >= 3 else { return false }
        let prevIndex: Int
        let nextIndex: Int
        if closed {
            prevIndex = (index - 1 + count) % count
            nextIndex = (index + 1) % count
        } else {
            guard index > 0, index < count - 1 else { return false }
            prevIndex = index - 1
            nextIndex = index + 1
        }
        let prev = points[prevIndex]
        let point = points[index]
        let next = points[nextIndex]
        if PolygonBoolean.isCollinearVertex(prev: prev, point: point, next: next) {
            return false
        }
        let v1x = point.x - prev.x
        let v1y = point.y - prev.y
        let v2x = next.x - point.x
        let v2y = next.y - point.y
        let l1 = hypot(v1x, v1y)
        let l2 = hypot(v2x, v2y)
        guard l1 > 0.0001, l2 > 0.0001 else { return false }
        let cosTurn = max(-1, min(1, (v1x * v2x + v1y * v2y) / (l1 * l2)))
        let turnDegrees = acos(cosTurn) * 180 / .pi
        return turnDegrees >= toleranceDegrees
    }

    private static func touchesAnyStroke(
        _ point: CGPoint,
        strokes: [VectorStroke],
        tolerance: CGFloat
    ) -> Bool {
        for stroke in strokes where !stroke.isConstruction {
            if stroke.distance(to: point) <= tolerance { return true }
        }
        return false
    }

    private static func dedupeCuts(_ cuts: [Cut], totalLength: CGFloat, closed: Bool) -> [Cut] {
        let epsilon = max(totalLength * 0.001, 0.05)
        let sorted = cuts.sorted { $0.distance < $1.distance }
        var unique: [Cut] = []
        for cut in sorted {
            if let last = unique.last, abs(last.distance - cut.distance) <= epsilon {
                continue
            }
            unique.append(cut)
        }
        if closed,
           unique.count >= 2,
           let first = unique.first,
           let last = unique.last,
           abs((last.distance - totalLength) - first.distance) <= epsilon
            || abs(totalLength - last.distance + first.distance) <= epsilon {
            unique.removeLast()
        }
        return unique
    }

    // MARK: - Bounding cuts

    private static func boundingCuts(
        around tapDistance: CGFloat,
        cuts: [Cut],
        totalLength: CGFloat
    ) -> (prev: Cut, next: Cut)? {
        guard cuts.count >= 2 else { return nil }
        let d = wrapDistance(tapDistance, totalLength: totalLength)

        var prev = cuts.last!
        var next = cuts.first!
        for cut in cuts {
            if cut.distance <= d + 0.0001 {
                prev = cut
            }
        }
        if let found = cuts.first(where: { $0.distance >= d - 0.0001 }) {
            next = found
        } else {
            next = cuts.first!
        }

        // Tap landed exactly on a cut — pick the shorter adjacent span.
        if abs(prev.distance - next.distance) <= 0.0001
            || (prev.distance == cuts.last!.distance && next.distance == cuts.first!.distance
                && abs(d - prev.distance) <= 0.0001) {
            guard let index = cuts.firstIndex(where: { abs($0.distance - prev.distance) <= 0.0001 }) else {
                return nil
            }
            let prevIndex = (index - 1 + cuts.count) % cuts.count
            let nextIndex = (index + 1) % cuts.count
            // Prefer the span whose midpoint is closer to the original tap projection.
            let left = (cuts[prevIndex], cuts[index])
            let right = (cuts[index], cuts[nextIndex])
            let leftMid = midpointDistance(from: left.0.distance, to: left.1.distance, totalLength: totalLength)
            let rightMid = midpointDistance(from: right.0.distance, to: right.1.distance, totalLength: totalLength)
            if abs(wrapDistance(d - leftMid, totalLength: totalLength))
                <= abs(wrapDistance(d - rightMid, totalLength: totalLength)) {
                return (left.0, left.1)
            }
            return (right.0, right.1)
        }

        // Ensure prev/next bracket the tap on a closed contour.
        if prev.distance <= d, next.distance >= d {
            return (prev, next)
        }
        // Wrapped: tap is after last cut or before first.
        return (cuts.last!, cuts.first!)
    }

    private static func boundingCutsOpen(
        around tapDistance: CGFloat,
        cuts: [Cut]
    ) -> (prev: Cut, next: Cut)? {
        guard cuts.count >= 2 else { return nil }
        var prev = cuts[0]
        var next = cuts[cuts.count - 1]
        for cut in cuts where cut.distance <= tapDistance + 0.0001 {
            prev = cut
        }
        if let found = cuts.first(where: { $0.distance >= tapDistance - 0.0001 }) {
            next = found
        }
        if abs(prev.distance - next.distance) <= 0.0001 {
            guard let index = cuts.firstIndex(where: { abs($0.distance - prev.distance) <= 0.0001 }) else {
                return nil
            }
            if index > 0 { return (cuts[index - 1], cuts[index]) }
            if index + 1 < cuts.count { return (cuts[index], cuts[index + 1]) }
            return nil
        }
        return (prev, next)
    }

    private static func midpointDistance(from a: CGFloat, to b: CGFloat, totalLength: CGFloat) -> CGFloat {
        if b >= a {
            return (a + b) * 0.5
        }
        let mid = (a + b + totalLength) * 0.5
        return wrapDistance(mid, totalLength: totalLength)
    }

    // MARK: - Contour helpers

    private static func nearestContour(
        to tapPoint: CGPoint,
        threshold: CGFloat,
        strokes: [VectorStroke],
        preferredStrokeID: UUID?
    ) -> (stroke: VectorStroke, renderPoints: [CGPoint], distance: CGFloat, segmentIndex: Int, t: CGFloat)? {
        var best: (stroke: VectorStroke, renderPoints: [CGPoint], distance: CGFloat, screenDistance: CGFloat, segmentIndex: Int, t: CGFloat)?

        for stroke in strokes where !stroke.isConstruction {
            let renderPoints = ShapeGeometry.renderPoints(for: stroke)
            guard let hit = projectOntoContour(tapPoint, points: renderPoints, closed: stroke.isClosed),
                  hit.radialDistance <= threshold else { continue }
            let preferredBoost: CGFloat = (stroke.id == preferredStrokeID) ? -threshold * 0.25 : 0
            let score = hit.radialDistance + preferredBoost
            if best == nil || score < best!.screenDistance {
                best = (stroke, renderPoints, hit.distance, score, hit.segmentIndex, hit.t)
            }
        }
        guard let best else { return nil }
        return (best.stroke, best.renderPoints, best.distance, best.segmentIndex, best.t)
    }

    private static func projectOntoContour(
        _ point: CGPoint,
        points: [CGPoint],
        closed: Bool
    ) -> (distance: CGFloat, point: CGPoint, radialDistance: CGFloat, segmentIndex: Int, t: CGFloat)? {
        guard points.count >= 2 else { return nil }
        let segmentCount = closed ? points.count : points.count - 1
        var best: ContourHit?
        var bestRadial = CGFloat.greatestFiniteMagnitude
        var accrued: CGFloat = 0

        for index in 0..<segmentCount {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let projection = projectPointOnSegment(point: point, start: start, end: end)
            if projection.distance < bestRadial {
                bestRadial = projection.distance
                best = ContourHit(
                    distance: accrued + segmentLength(start, end) * projection.t,
                    point: projection.point,
                    segmentIndex: index,
                    t: projection.t
                )
            }
            accrued += segmentLength(start, end)
        }
        guard let best else { return nil }
        return (best.distance, best.point, bestRadial, best.segmentIndex, best.t)
    }

    private static func extractSpan(
        from startDistance: CGFloat,
        to endDistance: CGFloat,
        points: [CGPoint],
        closed: Bool,
        startPoint: CGPoint,
        endPoint: CGPoint
    ) -> [CGPoint] {
        let totalLength = contourLength(points, closed: closed)
        guard totalLength > 0.001 else { return [startPoint, endPoint] }

        var result: [CGPoint] = [startPoint]

        func appendUnique(_ point: CGPoint) {
            if let last = result.last,
               hypot(last.x - point.x, last.y - point.y) <= 0.0005 {
                return
            }
            result.append(point)
        }

        if closed {
            // Walk forward from `start` to `end`, wrapping across the seam, so the kept
            // vertices are emitted in traversal order. Appending in raw index order would
            // scramble a wrapping span into diagonal chords across the shape.
            let start = wrapDistance(startDistance, totalLength: totalLength)
            let end = wrapDistance(endDistance, totalLength: totalLength)
            var spanLength = end - start
            if spanLength <= 0.0001 { spanLength += totalLength }

            var interior: [(offset: CGFloat, point: CGPoint)] = []
            var accrued: CGFloat = 0
            for index in 0..<points.count {
                var offset = accrued - start
                if offset < 0 { offset += totalLength }
                if offset > 0.0001, offset < spanLength - 0.0001 {
                    interior.append((offset, points[index]))
                }
                accrued += segmentLength(points[index], points[(index + 1) % points.count])
            }
            interior.sort { $0.offset < $1.offset }
            for item in interior {
                appendUnique(item.point)
            }
            appendUnique(endPoint)
            return result
        }

        let start = startDistance
        let end = endDistance
        var accrued: CGFloat = 0
        for index in 0..<(points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            let length = segmentLength(a, b)
            if accrued > start + 0.0001, accrued < end - 0.0001 {
                appendUnique(a)
            }
            if accrued + length > start + 0.0001, accrued + length < end - 0.0001 {
                appendUnique(b)
            }
            accrued += length
        }

        appendUnique(endPoint)
        return result
    }

    private static func contourLength(_ points: [CGPoint], closed: Bool) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        let count = closed ? points.count : points.count - 1
        var length: CGFloat = 0
        for index in 0..<count {
            length += segmentLength(points[index], points[(index + 1) % points.count])
        }
        return length
    }

    private static func distanceToSegmentStart(
        segmentIndex: Int,
        t: CGFloat,
        points: [CGPoint]
    ) -> CGFloat {
        var distance: CGFloat = 0
        for index in 0..<segmentIndex {
            distance += segmentLength(points[index], points[(index + 1) % points.count])
        }
        let start = points[segmentIndex]
        let end = points[(segmentIndex + 1) % points.count]
        return distance + segmentLength(start, end) * t
    }

    private static func wrapDistance(_ distance: CGFloat, totalLength: CGFloat) -> CGFloat {
        guard totalLength > 0 else { return 0 }
        var value = distance.truncatingRemainder(dividingBy: totalLength)
        if value < 0 { value += totalLength }
        return value
    }

    // MARK: - Stroke builders / geometry primitives

    private static func openStroke(
        from target: VectorStroke,
        points: [CGPoint],
        shapeType: StrokeShapeType
    ) -> VectorStroke {
        VectorStroke(
            id: target.id,
            layerID: target.layerID,
            points: points,
            strokeWidth: target.strokeWidth,
            strokeColor: target.strokeColor,
            isClosed: false,
            cornerRadius: 0,
            cornerRadiiByIndex: nil,
            smoothCornerIndices: nil,
            isConstruction: false,
            shapeType: shapeType,
            shapeRotation: nil,
            rotationBasePoints: nil,
            rotationBaseCenter: nil,
            cutoutPoints: [],
            curveHandles: nil
        )
    }

    private static func demotedShapeType(_ stroke: VectorStroke) -> StrokeShapeType {
        switch stroke.shapeType {
        case .circle, .ellipse, .rectangle:
            return .polyline
        case .arc:
            return .arc
        default:
            return stroke.shapeType == .curve ? .polyline : stroke.shapeType
        }
    }

    private struct Segment {
        var start: CGPoint
        var end: CGPoint
    }

    private static func segments(for stroke: VectorStroke) -> [Segment] {
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
        let count = stroke.isClosed ? renderPoints.count : max(renderPoints.count - 1, 0)
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

    private static func projectPointOnSegment(
        point: CGPoint,
        start: CGPoint,
        end: CGPoint
    ) -> (point: CGPoint, t: CGFloat, distance: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            let distance = hypot(point.x - start.x, point.y - start.y)
            return (start, 0, distance)
        }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq
        t = max(0, min(1, t))
        let projected = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        let distance = hypot(point.x - projected.x, point.y - projected.y)
        return (projected, t, distance)
    }

    private static func segmentLength(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}
