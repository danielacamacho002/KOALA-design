//
//  CurveAnchorSimplifier.swift
//  Koala
//

import CoreGraphics
import Foundation

extension ShapeGeometry {
    /// Collapses a sampled outline (join, boolean, auto-close, or a flattened
    /// Bézier) back to corners plus a few cubics.
    ///
    /// Render sampling stores an anchor every few points along a curve. Those
    /// anchors are the outline, so deleting them by hand does not stick: the next
    /// select, move, or join writes the samples again. This fit keeps every sharp
    /// corner and replaces each smooth run with the smallest cubic chain that
    /// stays within `fitTolerance` of the samples. Sparse shapes, fillets, and
    /// parametric circles are left alone.
    nonisolated static func withSimplifiedDenseAnchors(_ stroke: VectorStroke) -> VectorStroke {
        guard stroke.cutoutPoints.isEmpty else { return stroke }
        guard !stroke.hasAnyCornerFillets else { return stroke }
        switch stroke.shapeType {
        case .polyline, .curve, .rectangle:
            break
        default:
            return stroke
        }

        let anchorCount = stroke.points.count
        let authoredCurve = stroke.shapeType == .curve && hasUserCubicHandles(stroke)
        if authoredCurve, anchorCount < denseCurveAnchorCount { return stroke }
        if !authoredCurve, anchorCount < densePolylineAnchorCount { return stroke }

        // Baked smooth corners and real cubics render a denser outline than the
        // anchors. Fit that outline so an already-saved piece collapses too.
        var samples = (authoredCurve || stroke.hasBakedSmoothCorners)
            ? renderPoints(for: stroke)
            : stroke.points
        samples = deduped(samples, closed: stroke.isClosed)
        guard samples.count >= densePolylineAnchorCount else { return stroke }

        if let fitted = fitOutline(samples, closed: stroke.isClosed),
           fitted.anchors.count < anchorCount,
           fitted.anchors.count * 3 < samples.count || fitted.anchors.count + 12 <= anchorCount {
            let simplified = strokeReplacing(stroke, with: fitted)
            if maxDeviation(of: samples, from: simplified) <= fitTolerance * 1.6 {
                return simplified
            }
        }
        return collinearFallback(stroke, samples: samples, anchorCount: anchorCount)
    }
}

private extension ShapeGeometry {
    /// About 0.04 in. Tight enough that a seam does not move on the page, loose
    /// enough that one sampled cubic comes back as two or three anchors instead
    /// of a new anchor every few points.
    static let fitTolerance: CGFloat = 3
    static let densePolylineAnchorCount = 16
    static let denseCurveAnchorCount = 24
    static let cornerTurn: CGFloat = 25 * .pi / 180
    static let duplicateEpsilon: CGFloat = 0.05

    struct FittedChain {
        var anchors: [CGPoint]
        var handles: [CurveHandle]

        var isCurve: Bool {
            handles.contains { handle in
                hypot(handle.inOffset.x, handle.inOffset.y) > 0.01
                    || hypot(handle.outOffset.x, handle.outOffset.y) > 0.01
            }
        }
    }

    static func deduped(_ points: [CGPoint], closed: Bool) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, hypot(last.x - point.x, last.y - point.y) <= duplicateEpsilon {
                continue
            }
            result.append(point)
        }
        if closed, result.count > 1,
           let first = result.first, let last = result.last,
           hypot(first.x - last.x, first.y - last.y) <= duplicateEpsilon {
            result.removeLast()
        }
        return result
    }

    static func fitOutline(_ points: [CGPoint], closed: Bool) -> FittedChain? {
        let count = points.count
        guard count >= 2 else { return nil }
        let corners = cornerIndices(in: points, closed: closed)

        var chain = FittedChain(anchors: [], handles: [])
        if closed {
            let breaks = corners.isEmpty ? [0] : corners
            for index in breaks.indices {
                let start = breaks[index]
                let end = breaks[(index + 1) % breaks.count]
                let span = closedSpan(points, from: start, to: end)
                guard span.count >= 2 else { continue }
                let left = corners.isEmpty ? seamTangent(points) : outgoingTangent(span)
                let right = corners.isEmpty ? CGPoint(x: -left.x, y: -left.y) : incomingTangent(span)
                append(fitSpan(span, depth: 0, leftTangent: left, rightTangent: right), onto: &chain)
            }
            guard chain.anchors.count >= 2, let last = chain.anchors.last, let first = chain.anchors.first else {
                return nil
            }
            if hypot(first.x - last.x, first.y - last.y) <= duplicateEpsilon {
                let incoming = chain.handles[chain.handles.count - 1].inOffset
                chain.anchors.removeLast()
                chain.handles.removeLast()
                if !chain.handles.isEmpty {
                    chain.handles[0].inOffset = incoming
                }
            }
            guard chain.anchors.count >= 3, chain.handles.count == chain.anchors.count else { return nil }
        } else {
            var boundaries = [0]
            boundaries.append(contentsOf: corners)
            if boundaries.last != count - 1 { boundaries.append(count - 1) }
            for index in 0..<(boundaries.count - 1) {
                let span = Array(points[boundaries[index]...boundaries[index + 1]])
                guard span.count >= 2 else { continue }
                append(
                    fitSpan(span, depth: 0, leftTangent: outgoingTangent(span), rightTangent: incomingTangent(span)),
                    onto: &chain
                )
            }
            guard chain.anchors.count >= 2, chain.handles.count == chain.anchors.count else { return nil }
        }
        return chain
    }

    static func cornerIndices(in points: [CGPoint], closed: Bool) -> [Int] {
        let count = points.count
        guard count >= 3 else { return [] }
        var corners: [Int] = []
        let upper = closed ? count : count - 1
        let lower = closed ? 0 : 1
        for index in lower..<upper {
            let previous = points[(index - 1 + count) % count]
            let current = points[index]
            let next = points[(index + 1) % count]
            let incoming = CGPoint(x: current.x - previous.x, y: current.y - previous.y)
            let outgoing = CGPoint(x: next.x - current.x, y: next.y - current.y)
            let inLength = hypot(incoming.x, incoming.y)
            let outLength = hypot(outgoing.x, outgoing.y)
            guard inLength > duplicateEpsilon, outLength > duplicateEpsilon else { continue }
            let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
            let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
            let turn = abs(atan2(cross, dot))
            if turn >= cornerTurn { corners.append(index) }
        }
        return corners
    }

    static func closedSpan(_ points: [CGPoint], from start: Int, to end: Int) -> [CGPoint] {
        if start == end {
            var loop = Array(points[start...]) + Array(points[..<start])
            if let first = loop.first { loop.append(first) }
            return loop
        }
        if start < end {
            return Array(points[start...end])
        }
        return Array(points[start...]) + Array(points[...end])
    }

    static func seamTangent(_ points: [CGPoint]) -> CGPoint {
        guard let first = points.first, points.count >= 2 else { return CGPoint(x: 1, y: 0) }
        let previous = points[points.count - 1]
        let next = points[1]
        return unit(CGPoint(x: next.x - previous.x, y: next.y - previous.y))
            ?? unit(CGPoint(x: next.x - first.x, y: next.y - first.y))
            ?? CGPoint(x: 1, y: 0)
    }

    static func outgoingTangent(_ points: [CGPoint]) -> CGPoint {
        guard let first = points.first else { return CGPoint(x: 1, y: 0) }
        for point in points.dropFirst() {
            if let direction = unit(CGPoint(x: point.x - first.x, y: point.y - first.y)),
               hypot(point.x - first.x, point.y - first.y) > 0.5 {
                return direction
            }
        }
        guard points.count >= 2 else { return CGPoint(x: 1, y: 0) }
        let ahead = points[1]
        return unit(CGPoint(x: ahead.x - first.x, y: ahead.y - first.y)) ?? CGPoint(x: 1, y: 0)
    }

    static func incomingTangent(_ points: [CGPoint]) -> CGPoint {
        guard let last = points.last else { return CGPoint(x: -1, y: 0) }
        for point in points.dropLast().reversed() {
            if let direction = unit(CGPoint(x: point.x - last.x, y: point.y - last.y)),
               hypot(point.x - last.x, point.y - last.y) > 0.5 {
                return direction
            }
        }
        guard points.count >= 2 else { return CGPoint(x: -1, y: 0) }
        let behind = points[points.count - 2]
        return unit(CGPoint(x: behind.x - last.x, y: behind.y - last.y)) ?? CGPoint(x: -1, y: 0)
    }

    static func append(_ span: FittedChain, onto chain: inout FittedChain) {
        guard !span.anchors.isEmpty, span.handles.count == span.anchors.count else { return }
        if chain.anchors.isEmpty {
            chain = span
            return
        }
        let joint = chain.handles.count - 1
        chain.handles[joint].outOffset = span.handles[0].outOffset
        chain.anchors.append(contentsOf: span.anchors.dropFirst())
        chain.handles.append(contentsOf: span.handles.dropFirst())
    }

    static func fitSpan(
        _ points: [CGPoint],
        depth: Int,
        leftTangent: CGPoint,
        rightTangent: CGPoint
    ) -> FittedChain {
        let count = points.count
        guard count >= 2, let first = points.first, let last = points.last else {
            return FittedChain(anchors: points, handles: points.map { _ in CurveHandle() })
        }
        if count == 2 || maxChordDeviation(points) <= fitTolerance {
            return line(from: first, to: last)
        }
        // A span that still will not fit must keep its samples. Replacing it with
        // the chord used to miss the outline, and the whole shape was then left dense.
        if depth >= 14 {
            return verbatim(points)
        }
        if count == 3 {
            return throughMiddle(points)
        }

        let controls = cubicControls(points, leftTangent: leftTangent, rightTangent: rightTangent)
        let error = farthestSample(points, controls: controls)
        if error.distance <= fitTolerance {
            return FittedChain(
                anchors: [first, last],
                handles: [
                    CurveHandle(inOffset: .zero, outOffset: CGPoint(x: controls.1.x - first.x, y: controls.1.y - first.y)),
                    CurveHandle(inOffset: CGPoint(x: controls.2.x - last.x, y: controls.2.y - last.y), outOffset: .zero)
                ]
            )
        }

        var split = error.index
        if split <= 1 || split >= count - 2 { split = count / 2 }
        let tangent = centerTangent(points, at: split)
        let left = fitSpan(
            Array(points[...split]),
            depth: depth + 1,
            leftTangent: leftTangent,
            rightTangent: CGPoint(x: -tangent.x, y: -tangent.y)
        )
        let right = fitSpan(
            Array(points[split...]),
            depth: depth + 1,
            leftTangent: tangent,
            rightTangent: rightTangent
        )
        var combined = FittedChain(anchors: [], handles: [])
        append(left, onto: &combined)
        append(right, onto: &combined)
        return combined
    }

    static func line(from start: CGPoint, to end: CGPoint) -> FittedChain {
        FittedChain(
            anchors: [start, end],
            handles: [CurveHandle(), CurveHandle()]
        )
    }

    static func strokeReplacing(_ stroke: VectorStroke, with fitted: FittedChain) -> VectorStroke {
        var simplified = stroke
        simplified.points = fitted.anchors
        simplified.isClosed = stroke.isClosed
        simplified.shapeRotation = nil
        simplified.rotationBasePoints = nil
        simplified.rotationBaseCenter = nil
        simplified.smoothCornerIndices = nil
        simplified.cornerRadius = 0
        simplified.cornerRadiiByIndex = nil
        if fitted.isCurve {
            simplified.shapeType = .curve
            simplified.curveHandles = fitted.handles
        } else {
            simplified.shapeType = .polyline
            simplified.curveHandles = nil
        }
        return simplified
    }

    static func verbatim(_ points: [CGPoint]) -> FittedChain {
        FittedChain(
            anchors: points,
            handles: points.map { _ in CurveHandle() }
        )
    }

    static func collinearFallback(
        _ stroke: VectorStroke,
        samples: [CGPoint],
        anchorCount: Int
    ) -> VectorStroke {
        let reduced = ramerDouglas(samples, epsilon: fitTolerance)
        guard reduced.count >= (stroke.isClosed ? 3 : 2), reduced.count + 12 <= anchorCount else {
            return stroke
        }
        var simplified = stroke
        simplified.points = reduced
        simplified.shapeType = .polyline
        simplified.curveHandles = nil
        simplified.smoothCornerIndices = nil
        simplified.shapeRotation = nil
        simplified.rotationBasePoints = nil
        simplified.rotationBaseCenter = nil
        return simplified
    }

    static func ramerDouglas(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var farthest: CGFloat = 0
        var farthestIndex = 0
        for index in 1..<(points.count - 1) {
            let distance = distanceToSegment(points[index], first, last)
            if distance > farthest {
                farthest = distance
                farthestIndex = index
            }
        }
        guard farthest > epsilon else { return [first, last] }
        let left = ramerDouglas(Array(points[...farthestIndex]), epsilon: epsilon)
        let right = ramerDouglas(Array(points[farthestIndex...]), epsilon: epsilon)
        return left.dropLast() + right
    }

    static func throughMiddle(_ points: [CGPoint]) -> FittedChain {
        FittedChain(
            anchors: points,
            handles: points.map { _ in CurveHandle() }
        )
    }

    static func maxChordDeviation(_ points: [CGPoint]) -> CGFloat {
        guard let first = points.first, let last = points.last, points.count >= 3 else { return 0 }
        var worst: CGFloat = 0
        for point in points.dropFirst().dropLast() {
            worst = max(worst, distanceToSegment(point, first, last))
        }
        return worst
    }

    static func cubicControls(
        _ points: [CGPoint],
        leftTangent: CGPoint,
        rightTangent: CGPoint
    ) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        let start = points[0]
        let end = points[points.count - 1]
        let chord = hypot(end.x - start.x, end.y - start.y)
        let fallback = max(chord / 3, 0.001)
        let solved = solveHandleLengths(points, leftTangent: leftTangent, rightTangent: rightTangent)
        let alpha = (solved.alpha > 0.001 && solved.alpha < chord * 3) ? solved.alpha : fallback
        let beta = (solved.beta > 0.001 && solved.beta < chord * 3) ? solved.beta : fallback
        let control1 = CGPoint(x: start.x + leftTangent.x * alpha, y: start.y + leftTangent.y * alpha)
        let control2 = CGPoint(x: end.x + rightTangent.x * beta, y: end.y + rightTangent.y * beta)
        return (start, control1, control2, end)
    }

    /// Least-squares handle lengths for a cubic with fixed end tangents.
    static func solveHandleLengths(
        _ points: [CGPoint],
        leftTangent: CGPoint,
        rightTangent: CGPoint
    ) -> (alpha: CGFloat, beta: CGFloat) {
        let count = points.count
        let start = points[0]
        let end = points[count - 1]
        var lengths: [CGFloat] = [0]
        for index in 1..<count {
            let previous = points[index - 1]
            let current = points[index]
            lengths.append(lengths[index - 1] + hypot(current.x - previous.x, current.y - previous.y))
        }
        let total = lengths[count - 1]
        guard total > 0.001 else { return (0, 0) }

        var c00: CGFloat = 0
        var c01: CGFloat = 0
        var c11: CGFloat = 0
        var d0: CGFloat = 0
        var d1: CGFloat = 0
        for index in 1..<(count - 1) {
            let t = lengths[index] / total
            let mt = 1 - t
            let b1 = 3 * mt * mt * t
            let b2 = 3 * mt * t * t
            let b0 = mt * mt * mt
            let b3 = t * t * t
            let remainder = CGPoint(
                x: points[index].x - (b0 + b1) * start.x - (b2 + b3) * end.x,
                y: points[index].y - (b0 + b1) * start.y - (b2 + b3) * end.y
            )
            let a = CGPoint(x: b1 * leftTangent.x, y: b1 * leftTangent.y)
            let b = CGPoint(x: b2 * rightTangent.x, y: b2 * rightTangent.y)
            c00 += a.x * a.x + a.y * a.y
            c01 += a.x * b.x + a.y * b.y
            c11 += b.x * b.x + b.y * b.y
            d0 += a.x * remainder.x + a.y * remainder.y
            d1 += b.x * remainder.x + b.y * remainder.y
        }
        let determinant = c00 * c11 - c01 * c01
        guard abs(determinant) > 1e-8 else { return (0, 0) }
        return (
            alpha: (d0 * c11 - c01 * d1) / determinant,
            beta: (c00 * d1 - c01 * d0) / determinant
        )
    }

    static func farthestSample(
        _ points: [CGPoint],
        controls: (CGPoint, CGPoint, CGPoint, CGPoint)
    ) -> (distance: CGFloat, index: Int) {
        var worst: CGFloat = 0
        var index = 1
        guard points.count >= 3 else { return (0, 0) }
        for sampleIndex in 1..<(points.count - 1) {
            var best = CGFloat.greatestFiniteMagnitude
            for step in 0...24 {
                let t = CGFloat(step) / 24
                let point = cubicBezierPoint(controls.0, controls.1, controls.2, controls.3, t: t)
                let sample = points[sampleIndex]
                best = min(best, hypot(point.x - sample.x, point.y - sample.y))
            }
            if best > worst {
                worst = best
                index = sampleIndex
            }
        }
        return (worst, index)
    }

    static func centerTangent(_ points: [CGPoint], at index: Int) -> CGPoint {
        let previous = points[max(0, index - 1)]
        let next = points[min(points.count - 1, index + 1)]
        return unit(CGPoint(x: next.x - previous.x, y: next.y - previous.y)) ?? CGPoint(x: 1, y: 0)
    }

    static func unit(_ vector: CGPoint) -> CGPoint? {
        let length = hypot(vector.x, vector.y)
        guard length > 0.0001 else { return nil }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }

    static func distanceToSegment(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-8 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    static func maxDeviation(of samples: [CGPoint], from stroke: VectorStroke) -> CGFloat {
        let rendered = renderPoints(for: stroke)
        guard rendered.count >= 2 else { return .greatestFiniteMagnitude }
        let segmentCount = stroke.isClosed ? rendered.count : rendered.count - 1
        var worst: CGFloat = 0
        for sample in samples {
            var best = CGFloat.greatestFiniteMagnitude
            for index in 0..<segmentCount {
                let start = rendered[index]
                let end = rendered[(index + 1) % rendered.count]
                best = min(best, distanceToSegment(sample, start, end))
            }
            worst = max(worst, best)
        }
        return worst
    }
}
