//
//  ShapeGeometry.swift
//  vectr
//

import CoreGraphics
import Foundation

nonisolated enum ShapeGeometry: Sendable {
    static func requiredControlPoints(
        category: ToolCategory,
        lineVariant: LineVariant,
        circleVariant: CircleVariant,
        rectangleVariant: RectangleVariant
    ) -> Int {
        switch category {
        case .line:
            switch lineVariant {
            case .line, .constructionLine: return 2
            case .arc: return 3
            }
        case .circle:
            switch circleVariant {
            case .center, .edge: return 2
            case .ellipse: return 3
            }
        case .rectangle:
            switch rectangleVariant {
            case .center: return 3
            case .edge: return 2
            }
        default:
            return 0
        }
    }

    static func previewPoints(
        controlPoints: [CGPoint],
        category: ToolCategory,
        lineVariant: LineVariant,
        circleVariant: CircleVariant,
        rectangleVariant: RectangleVariant,
        arcSweepRadians: CGFloat? = nil
    ) -> [CGPoint] {
        guard !controlPoints.isEmpty else { return [] }
        switch category {
        case .line:
            switch lineVariant {
            case .line, .constructionLine:
                return controlPoints
            case .arc:
                guard controlPoints.count >= 3 else { return controlPoints }
                return arcPoints(
                    center: controlPoints[0],
                    start: controlPoints[1],
                    end: controlPoints[2],
                    sweep: arcSweepRadians
                )
            }
        case .circle:
            switch circleVariant {
            case .center:
                guard controlPoints.count >= 2 else { return controlPoints }
                let radius = hypot(
                    controlPoints[1].x - controlPoints[0].x,
                    controlPoints[1].y - controlPoints[0].y
                )
                return circleCardinalPoints(center: controlPoints[0], radius: radius)
            case .edge:
                guard controlPoints.count >= 2 else { return controlPoints }
                let center = CGPoint(
                    x: (controlPoints[0].x + controlPoints[1].x) / 2,
                    y: (controlPoints[0].y + controlPoints[1].y) / 2
                )
                let radius = hypot(controlPoints[1].x - controlPoints[0].x, controlPoints[1].y - controlPoints[0].y) / 2
                return circleCardinalPoints(center: center, radius: radius)
            case .ellipse:
                guard controlPoints.count >= 2 else { return controlPoints }
                let center = controlPoints[0]
                let rx = abs(controlPoints[1].x - center.x)
                if controlPoints.count >= 3 {
                    let ry = abs(controlPoints[2].y - center.y)
                    return ellipseCardinalPoints(center: center, rx: rx, ry: ry)
                }
                return ellipseCardinalPoints(center: center, rx: rx, ry: rx)
            }
        case .rectangle:
            guard !controlPoints.isEmpty else { return controlPoints }
            switch rectangleVariant {
            case .center:
                let center = controlPoints[0]
                if controlPoints.count == 1 { return [center] }
                let halfW = abs(controlPoints[1].x - center.x)
                if controlPoints.count == 2 {
                    return rectangleFromCenterDistances(center, halfWidth: halfW, halfHeight: halfW)
                }
                let halfH = abs(controlPoints[2].y - center.y)
                return rectangleFromCenterDistances(center, halfWidth: halfW, halfHeight: halfH)
            case .edge:
                guard controlPoints.count >= 2 else { return controlPoints }
                return rectangleFromCorners(controlPoints[0], controlPoints[1])
            }
        default:
            return controlPoints
        }
    }

    static func controlPoints(
        from stroke: VectorStroke,
        category: ToolCategory,
        lineVariant: LineVariant,
        circleVariant: CircleVariant,
        rectangleVariant: RectangleVariant
    ) -> [CGPoint]? {
        switch category {
        case .line:
            switch lineVariant {
            case .line, .constructionLine:
                guard let start = stroke.points.first, let end = stroke.points.last else { return nil }
                return [start, end]
            case .arc:
                guard stroke.points.count >= 3,
                      let start = stroke.points.first,
                      let end = stroke.points.last,
                      let center = arcControlCenter(from: stroke.points) else { return nil }
                return [center, start, end]
            }
        case .circle:
            switch circleVariant {
            case .center:
                guard let circle = circleFromCardinalPoints(stroke.points) else { return nil }
                return [
                    circle.center,
                    CGPoint(x: circle.center.x + circle.radius, y: circle.center.y)
                ]
            case .ellipse:
                guard let ellipse = ellipseFromCardinalPoints(stroke.points) else { return nil }
                return [
                    ellipse.center,
                    CGPoint(x: ellipse.center.x + ellipse.rx, y: ellipse.center.y),
                    CGPoint(x: ellipse.center.x, y: ellipse.center.y + ellipse.ry)
                ]
            case .edge:
                guard let circle = circleFromCardinalPoints(stroke.points) else { return nil }
                return [
                    CGPoint(x: circle.center.x - circle.radius, y: circle.center.y),
                    CGPoint(x: circle.center.x + circle.radius, y: circle.center.y)
                ]
            }
        case .rectangle:
            switch rectangleVariant {
            case .center:
                guard stroke.points.count == 4 else { return nil }
                let center = CGPoint(
                    x: (stroke.points[0].x + stroke.points[2].x) / 2,
                    y: (stroke.points[0].y + stroke.points[2].y) / 2
                )
                let halfW = abs(stroke.points[1].x - center.x)
                let halfH = abs(stroke.points[2].y - center.y)
                return [
                    center,
                    CGPoint(x: center.x + halfW, y: center.y),
                    CGPoint(x: center.x, y: center.y + halfH)
                ]
            case .edge:
                guard stroke.points.count == 4 else { return nil }
                return [stroke.points[0], stroke.points[2]]
            }
        default:
            return nil
        }
    }

    static func buildStroke(
        controlPoints: [CGPoint],
        category: ToolCategory,
        lineVariant: LineVariant,
        circleVariant: CircleVariant,
        rectangleVariant: RectangleVariant,
        layerID: UUID,
        strokeWidth: CGFloat,
        strokeColor: CodableColor,
        closed: Bool,
        cornerRadius: CGFloat = 0,
        arcSweepRadians: CGFloat? = nil
    ) -> VectorStroke? {
        let points = previewPoints(
            controlPoints: controlPoints,
            category: category,
            lineVariant: lineVariant,
            circleVariant: circleVariant,
            rectangleVariant: rectangleVariant,
            arcSweepRadians: arcSweepRadians
        )
        guard points.count >= 2 else { return nil }

        switch category {
        case .line:
            switch lineVariant {
            case .line:
                return VectorStroke(
                    layerID: layerID,
                    points: points,
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: false,
                    shapeType: .polyline
                )
            case .constructionLine:
                return VectorStroke(
                    layerID: layerID,
                    points: points,
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: false,
                    isConstruction: true,
                    shapeType: .construction
                )
            case .arc:
                guard controlPoints.count >= 3 else { return nil }
                let draft = VectorStroke(
                    layerID: layerID,
                    points: points,
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: false,
                    shapeType: .arc
                )
                return withCompactedCircularAnchors(draft)
            }
        case .circle:
            switch circleVariant {
            case .ellipse:
                guard controlPoints.count >= 3,
                      let cardinal = ellipseCardinalPoints(from: controlPoints) else { return nil }
                return VectorStroke(
                    layerID: layerID,
                    points: cardinal,
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: true,
                    shapeType: .ellipse
                )
            default:
                return VectorStroke(
                    layerID: layerID,
                    points: points,
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: true,
                    shapeType: .circle
                )
            }
        case .rectangle:
            return VectorStroke(
                layerID: layerID,
                points: points,
                strokeWidth: strokeWidth,
                strokeColor: strokeColor,
                isClosed: true,
                cornerRadius: max(0, cornerRadius),
                shapeType: .rectangle
            )
        default:
            return nil
        }
    }

    static func handlePoints(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .circle:
            if stroke.points.count == 4, let circle = circleFromCardinalPoints(stroke.points) {
                return orientedCardinalPoints(
                    center: circle.center,
                    rx: circle.radius,
                    ry: circle.radius,
                    rotation: stroke.resolvedShapeRotation
                )
            }
            if stroke.points.count >= 8 {
                return handlePointsForLegacyCircle(stroke.points)
            }
            return stroke.points
        case .ellipse:
            if stroke.points.count == 4, let ellipse = ellipseFromCardinalPoints(stroke.points) {
                return orientedCardinalPoints(
                    center: ellipse.center,
                    rx: ellipse.rx,
                    ry: ellipse.ry,
                    rotation: stroke.resolvedShapeRotation
                )
            }
            return stroke.points
        case .arc:
            if stroke.points.count >= 8 {
                return arcAnchorPoints(stroke.points) ?? stroke.points
            }
            return stroke.points
        default:
            let compacted = withCompactedCircularAnchors(stroke)
            if compacted.shapeType == .circle
                || compacted.shapeType == .ellipse
                || compacted.shapeType == .arc {
                return handlePoints(for: compacted)
            }
            return compacted.points
        }
    }

    /// Moves one stored anchor. Circles and ellipses stay parametric (radius /
    /// axis resize). Adjacent Bézier handles are cleared on leftover curves so
    /// joined circular segments do not implode from stale tangent offsets.
    static func applyingMovedAnchor(
        _ stroke: VectorStroke,
        at index: Int,
        to point: CGPoint
    ) -> VectorStroke {
        guard stroke.points.indices.contains(index) else { return stroke }
        switch stroke.shapeType {
        case .circle:
            var updated = stroke
            updated.points = updateCircleHandle(at: index, to: point, stroke: stroke)
            return updated
        case .ellipse:
            var updated = stroke
            updated.points = updateEllipseHandle(at: index, to: point, stroke: stroke)
            return updated
        default:
            break
        }
        var updated = stroke
        updated.points[index] = point
        guard var handles = updated.curveHandles, handles.count == updated.points.count else {
            return updated
        }
        let count = updated.points.count
        handles[index] = CurveHandle()
        if updated.isClosed || index > 0 {
            handles[(index - 1 + count) % count].outOffset = .zero
        }
        if updated.isClosed || index < count - 1 {
            handles[(index + 1) % count].inOffset = .zero
        }
        updated.curveHandles = handles
        return updated
    }

    static func filletCornerIndices(for stroke: VectorStroke) -> [Int] {
        let handles = handlePoints(for: stroke)
        var count = handles.count
        if stroke.isClosed,
           count > 1,
           hypot(handles[0].x - handles[count - 1].x, handles[0].y - handles[count - 1].y) <= 0.001 {
            count -= 1
        }
        guard count >= 3 else { return [] }
        if stroke.isClosed {
            return Array(0..<count)
        }
        return Array(1..<(count - 1))
    }

    static func shapeCenter(for stroke: VectorStroke) -> CGPoint? {
        switch stroke.shapeType {
        case .circle:
            return circleFromCardinalPoints(stroke.points)?.center
        case .ellipse:
            return ellipseFromCardinalPoints(stroke.points)?.center
        case .arc:
            // Geometric circle center — not the bbox midpoint, which drifts for partial arcs.
            return arcCircle(for: stroke)?.center
        case .rectangle:
            if stroke.points.count == 4 {
                return CGPoint(
                    x: (stroke.points[0].x + stroke.points[2].x) / 2,
                    y: (stroke.points[0].y + stroke.points[2].y) / 2
                )
            }
            return stroke.boundingBox().map { CGPoint(x: $0.midX, y: $0.midY) }
        case .polyline, .construction:
            if let center = stablePolylineCenter(for: stroke) {
                return center
            }
            if let bbox = stroke.boundingBox() {
                return CGPoint(x: bbox.midX, y: bbox.midY)
            }
            guard let first = stroke.points.first, let last = stroke.points.last else { return nil }
            return CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        default:
            if let bbox = stroke.boundingBox() {
                return CGPoint(x: bbox.midX, y: bbox.midY)
            }
            guard let first = stroke.points.first, let last = stroke.points.last else { return nil }
            return CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        }
    }

    static func rotationPivot(for stroke: VectorStroke, anchorIndex: Int?) -> CGPoint? {
        if let anchorIndex {
            let handles = handlePoints(for: stroke)
            if handles.indices.contains(anchorIndex) {
                return handles[anchorIndex]
            }
        }
        return shapeCenter(for: stroke)
    }

    static func normalizedRotationDegrees(_ radians: CGFloat) -> Double {
        var degrees = Double(radians * 180 / .pi)
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    static func captureRotationBaseIfNeeded(_ stroke: VectorStroke) -> VectorStroke {
        var updated = stroke
        guard updated.rotationBasePoints == nil else { return updated }
        updated.rotationBasePoints = stroke.points
        updated.rotationBaseCenter = shapeCenter(for: stroke)
        return updated
    }

    static func strokeWithAbsoluteRotation(
        _ stroke: VectorStroke,
        radians target: CGFloat,
        around pivot: CGPoint
    ) -> VectorStroke {
        let delta = target - stroke.resolvedShapeRotation
        guard abs(delta) > 0.000001 else { return stroke }
        return rotatedStroke(stroke, around: pivot, by: delta)
    }

    static func rotatePoints(_ points: [CGPoint], around pivot: CGPoint, by angle: CGFloat) -> [CGPoint] {
        let cosA = cos(angle)
        let sinA = sin(angle)
        return points.map { point in
            let dx = point.x - pivot.x
            let dy = point.y - pivot.y
            return CGPoint(
                x: pivot.x + dx * cosA - dy * sinA,
                y: pivot.y + dx * sinA + dy * cosA
            )
        }
    }

    static func rotatePoint(_ point: CGPoint, around pivot: CGPoint, by angle: CGFloat) -> CGPoint {
        rotatePoints([point], around: pivot, by: angle)[0]
    }

    static func orientedCardinalPoints(
        center: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        rotation: CGFloat
    ) -> [CGPoint] {
        let locals = [
            CGPoint(x: 0, y: -ry),
            CGPoint(x: rx, y: 0),
            CGPoint(x: 0, y: ry),
            CGPoint(x: -rx, y: 0)
        ]
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        return locals.map { local in
            CGPoint(
                x: center.x + local.x * cosR - local.y * sinR,
                y: center.y + local.x * sinR + local.y * cosR
            )
        }
    }

    static func rotatedStroke(_ stroke: VectorStroke, around pivot: CGPoint, by angle: CGFloat) -> VectorStroke {
        var updated = captureRotationBaseIfNeeded(stroke)

        switch stroke.shapeType {
        case .circle:
            if let circle = circleFromCardinalPoints(stroke.points) {
                let newCenter = rotatePoint(circle.center, around: pivot, by: angle)
                updated.points = circleCardinalPoints(center: newCenter, radius: circle.radius)
                updated.shapeRotation = stroke.resolvedShapeRotation + angle
            } else {
                updated.points = rotatePoints(stroke.points, around: pivot, by: angle)
                updated.shapeRotation = stroke.resolvedShapeRotation + angle
            }
        case .ellipse:
            if let ellipse = ellipseFromCardinalPoints(stroke.points) {
                let newCenter = rotatePoint(ellipse.center, around: pivot, by: angle)
                updated.points = ellipseCardinalPoints(center: newCenter, rx: ellipse.rx, ry: ellipse.ry)
                updated.shapeRotation = stroke.resolvedShapeRotation + angle
            } else {
                updated.points = rotatePoints(stroke.points, around: pivot, by: angle)
                updated.shapeRotation = stroke.resolvedShapeRotation + angle
            }
        default:
            updated.points = rotatePoints(stroke.points, around: pivot, by: angle)
            updated.shapeRotation = stroke.resolvedShapeRotation + angle
        }

        updated.cutoutPoints = stroke.cutoutPoints.map {
            rotatePoints($0, around: pivot, by: angle)
        }

        if let handles = stroke.curveHandles {
            let cosR = cos(angle)
            let sinR = sin(angle)
            updated.curveHandles = handles.map { handle in
                CurveHandle(
                    inOffset: rotateVector(handle.inOffset, cos: cosR, sin: sinR),
                    outOffset: rotateVector(handle.outOffset, cos: cosR, sin: sinR)
                )
            }
        }
        return updated
    }

    /// Rotates a free vector (offset) about the origin.
    private static func rotateVector(_ vector: CGPoint, cos cosR: CGFloat, sin sinR: CGFloat) -> CGPoint {
        CGPoint(
            x: vector.x * cosR - vector.y * sinR,
            y: vector.x * sinR + vector.y * cosR
        )
    }

    static func renderPoints(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .circle:
            if let circle = circleFromCardinalPoints(stroke.points) {
                return circlePoints(center: circle.center, radius: circle.radius, segments: 64)
            }
            return stroke.points
        case .ellipse:
            if let ellipse = ellipseFromCardinalPoints(stroke.points) {
                let rotation = stroke.resolvedShapeRotation
                let axisEnd = CGPoint(
                    x: ellipse.center.x + cos(rotation) * ellipse.rx,
                    y: ellipse.center.y + sin(rotation) * ellipse.rx
                )
                let secondAxisEnd = CGPoint(
                    x: ellipse.center.x + cos(rotation + .pi / 2) * ellipse.ry,
                    y: ellipse.center.y + sin(rotation + .pi / 2) * ellipse.ry
                )
                return ellipsePoints(
                    center: ellipse.center,
                    axisEnd: axisEnd,
                    secondAxisEnd: secondAxisEnd,
                    segments: 64
                )
            }
            return stroke.points
        case .arc:
            if let first = stroke.points.first,
               let last = stroke.points.last,
               let circle = arcCircle(for: stroke)
                ?? (stroke.points.count >= 3
                    ? arcCenter(start: first, end: last, through: stroke.points[1])
                    : nil),
               let sweep = signedCircularSweep(
                    of: stroke.points,
                    around: circle.center,
                    closed: false
               ),
               abs(sweep) > 0.0001 {
                return arcPoints(
                    center: circle.center,
                    start: first,
                    end: last,
                    sweep: sweep
                )
            }
            // Never stroke raw 3–4 rim anchors — those chords cut across the interior.
            if stroke.points.count >= 3,
               let first = stroke.points.first,
               let last = stroke.points.last {
                return arcPointsThrough(
                    start: first,
                    end: last,
                    through: stroke.points[stroke.points.count / 2]
                )
            }
            return stroke.points
        case .curve:
            if let handles = stroke.curveHandles, handles.count == stroke.points.count {
                return curvePoints(anchors: stroke.points, handles: handles, closed: stroke.isClosed)
            }
            return smoothCurvePoints(anchors: stroke.points, closed: stroke.isClosed)
        default:
            if let smooth = stroke.smoothCornerIndices, !smooth.isEmpty {
                return smoothedContourPoints(
                    points: stroke.points,
                    closed: stroke.isClosed,
                    smoothMiddles: smooth
                )
            }
            return stroke.points
        }
    }

    /// Expands baked fillet / circular-run midpoints into smooth circular arcs so the
    /// rendered/exported contour looks curved, while the stored anchor set stays minimal.
    /// Consecutive interiors (a 270° leftover after a circle quadrant trim) are one
    /// sweep — expanding each midpoint alone jumps backward and draws a chord.
    static func smoothedContourPoints(
        points: [CGPoint],
        closed: Bool,
        smoothMiddles: Set<Int>,
        segmentsPerArc: Int = 16
    ) -> [CGPoint] {
        let count = points.count
        guard count >= 3 else { return points }

        var result: [CGPoint] = []
        func append(_ point: CGPoint) {
            if let last = result.last, hypot(last.x - point.x, last.y - point.y) <= 0.0001 { return }
            result.append(point)
        }

        let runs = consecutiveSmoothRuns(count: count, smooth: smoothMiddles, closed: closed)
        var consumed = Set<Int>()
        var index = 0
        while index < count {
            if consumed.contains(index) {
                index += 1
                continue
            }
            if let run = runs.first(where: { $0.contains(index) }) {
                for point in expandedSmoothRunPoints(
                    points: points,
                    run: run,
                    closed: closed,
                    segmentsPerArc: segmentsPerArc
                ) {
                    append(point)
                }
                consumed.formUnion(run)
                index += 1
                continue
            }
            append(points[index])
            index += 1
        }

        if closed,
           result.count > 2,
           let first = result.first,
           let last = result.last,
           hypot(first.x - last.x, first.y - last.y) <= 0.0001 {
            result.removeLast()
        }
        return result
    }

    /// Groups consecutive smooth midpoints, merging a run that wraps the closed seam.
    static func consecutiveSmoothRuns(
        count: Int,
        smooth: Set<Int>,
        closed: Bool
    ) -> [[Int]] {
        guard count >= 3, !smooth.isEmpty else { return [] }

        func isSmooth(_ index: Int) -> Bool {
            if !closed, index == 0 || index == count - 1 { return false }
            return smooth.contains(index)
        }

        var runs: [[Int]] = []
        var current: [Int] = []
        for index in 0..<count {
            if isSmooth(index) {
                current.append(index)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }

        if closed,
           runs.count >= 2,
           let first = runs.first,
           let last = runs.last,
           first.first == 0,
           last.last == count - 1 {
            runs[0] = last + first
            runs.removeLast()
        }
        return runs
    }

    /// Samples the circular sweep from the vertex before `run` to the vertex after it.
    static func expandedSmoothRunPoints(
        points: [CGPoint],
        run: [Int],
        closed: Bool,
        segmentsPerArc: Int
    ) -> [CGPoint] {
        let count = points.count
        guard let first = run.first, let last = run.last, count >= 3 else {
            return run.map { points[$0] }
        }

        if closed, run.count == count {
            if let circle = fitCircle(from: points)
                ?? arcCenter(start: points[0], end: points[count / 3], through: points[(2 * count) / 3]) {
                return circlePoints(center: circle.center, radius: circle.radius, segments: 64)
            }
            return points
        }

        let prevIndex = (first - 1 + count) % count
        let nextIndex = (last + 1) % count
        var chain = [points[prevIndex]]
        chain.append(contentsOf: run.map { points[$0] })
        chain.append(points[nextIndex])

        if let circle = arcCenter(start: chain[0], end: chain[chain.count - 1], through: chain[chain.count / 2]),
           let sweep = signedCircularSweep(of: chain, around: circle.center, closed: false),
           abs(sweep) > 0.0001 {
            return arcPoints(
                center: circle.center,
                start: chain[0],
                end: chain[chain.count - 1],
                sweep: sweep,
                segments: max(segmentsPerArc, 16)
            )
        }
        return arcPointsThrough(
            start: chain[0],
            end: chain[chain.count - 1],
            through: chain[chain.count / 2],
            segments: segmentsPerArc
        )
    }

    static func circleFromCardinalPoints(_ points: [CGPoint]) -> (center: CGPoint, radius: CGFloat)? {
        guard points.count == 4 else { return nil }
        let center = CGPoint(x: (points[0].x + points[2].x) / 2, y: (points[0].y + points[2].y) / 2)
        let radius = hypot(points[0].x - center.x, points[0].y - center.y)
        guard radius > 0.001 else { return nil }
        return (center, radius)
    }

    /// Center and radius of the circle underlying a circle or arc stroke. Used by object
    /// snapping (center / on-rim) to locate curved geometry regardless of shape type.
    static func arcCircle(for stroke: VectorStroke) -> (center: CGPoint, radius: CGFloat)? {
        switch stroke.shapeType {
        case .circle:
            return circleFromCardinalPoints(stroke.points)
        case .arc:
            guard let center = arcControlCenter(from: stroke.points), !stroke.points.isEmpty else { return nil }
            let radius = stroke.points
                .map { hypot($0.x - center.x, $0.y - center.y) }
                .reduce(0, +) / CGFloat(stroke.points.count)
            guard radius > 0.001 else { return nil }
            return (center, radius)
        case .curve:
            guard stroke.points.count <= 4,
                  let handles = stroke.curveHandles,
                  handles.count == stroke.points.count else { return nil }
            let samples = renderPoints(for: stroke)
            guard samples.count >= 8, let circle = fitCircle(from: samples) else { return nil }
            let tolerance = max(0.75, circle.radius * 0.025)
            guard samples.allSatisfy({
                abs(hypot($0.x - circle.center.x, $0.y - circle.center.y) - circle.radius) <= tolerance
            }) else { return nil }
            return circle
        default:
            return nil
        }
    }

    static func updateCircleHandle(at index: Int, to point: CGPoint, stroke: VectorStroke) -> [CGPoint] {
        guard stroke.shapeType == .circle,
              let circle = circleFromCardinalPoints(stroke.points) else { return stroke.points }
        let center = circle.center
        let radius: CGFloat
        switch index {
        case 0, 2:
            radius = max(0.001, abs(point.y - center.y))
        case 1, 3:
            radius = max(0.001, abs(point.x - center.x))
        default:
            radius = max(0.001, hypot(point.x - center.x, point.y - center.y))
        }
        return circleCardinalPoints(center: center, radius: radius)
    }

    static func updateEllipseHandle(at index: Int, to point: CGPoint, stroke: VectorStroke) -> [CGPoint] {
        guard stroke.shapeType == .ellipse,
              let ellipse = ellipseFromCardinalPoints(stroke.points) else { return stroke.points }
        let center = ellipse.center
        var rx = ellipse.rx
        var ry = ellipse.ry
        switch index {
        case 0, 2:
            ry = max(0.001, abs(point.y - center.y))
        case 1, 3:
            rx = max(0.001, abs(point.x - center.x))
        default:
            break
        }
        return ellipseCardinalPoints(center: center, rx: rx, ry: ry)
    }

    private static func handlePointsForLegacyCircle(_ points: [CGPoint]) -> [CGPoint] {
        guard let circle = fitCircle(from: points) else { return points }
        return circleCardinalPoints(center: circle.center, radius: circle.radius)
    }

    static func fitCircle(from points: [CGPoint]) -> (center: CGPoint, radius: CGFloat)? {
        guard points.count >= 8 else { return nil }
        let center = CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
        let radius = points.map { hypot($0.x - center.x, $0.y - center.y) }.reduce(0, +) / CGFloat(points.count)
        guard radius > 0.001 else { return nil }
        return (center, radius)
    }

    static func circleCardinalPoints(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        guard radius > 0 else { return [center] }
        return [
            CGPoint(x: center.x, y: center.y - radius),
            CGPoint(x: center.x + radius, y: center.y),
            CGPoint(x: center.x, y: center.y + radius),
            CGPoint(x: center.x - radius, y: center.y)
        ]
    }

    static func ellipseCardinalPoints(center: CGPoint, rx: CGFloat, ry: CGFloat) -> [CGPoint] {
        guard rx > 0, ry > 0 else { return [center] }
        return [
            CGPoint(x: center.x, y: center.y - ry),
            CGPoint(x: center.x + rx, y: center.y),
            CGPoint(x: center.x, y: center.y + ry),
            CGPoint(x: center.x - rx, y: center.y)
        ]
    }

    static func ellipseCardinalPoints(from controlPoints: [CGPoint]) -> [CGPoint]? {
        guard controlPoints.count >= 3 else { return nil }
        let center = controlPoints[0]
        let rx = abs(controlPoints[1].x - center.x)
        let ry = abs(controlPoints[2].y - center.y)
        guard rx > 0, ry > 0 else { return nil }
        return ellipseCardinalPoints(center: center, rx: rx, ry: ry)
    }

    static func ellipseFromCardinalPoints(_ points: [CGPoint]) -> (center: CGPoint, rx: CGFloat, ry: CGFloat)? {
        guard points.count == 4 else { return nil }
        let center = CGPoint(x: (points[0].x + points[2].x) / 2, y: (points[0].y + points[2].y) / 2)
        let rx = abs(points[1].x - center.x)
        let ry = abs(points[0].y - center.y)
        guard rx > 0.001, ry > 0.001 else { return nil }
        return (center, rx, ry)
    }

    static func axisAlignedEllipsePoints(center: CGPoint, rx: CGFloat, ry: CGFloat, segments: Int = 64) -> [CGPoint] {
        guard rx > 0, ry > 0 else { return [center] }
        return (0..<segments).map { index in
            let angle = CGFloat(index) / CGFloat(segments) * 2 * .pi
            return CGPoint(
                x: center.x + cos(angle) * rx,
                y: center.y + sin(angle) * ry
            )
        }
    }

    // MARK: - Primitives

    static func circlePoints(center: CGPoint, radius: CGFloat, segments: Int = 64) -> [CGPoint] {
        guard radius > 0 else { return [center] }
        return (0..<segments).map { index in
            let angle = CGFloat(index) / CGFloat(segments) * 2 * .pi
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    static func ellipsePoints(center: CGPoint, axisEnd: CGPoint, secondAxisEnd: CGPoint, segments: Int = 64) -> [CGPoint] {
        let rx = hypot(axisEnd.x - center.x, axisEnd.y - center.y)
        let ry = hypot(secondAxisEnd.x - center.x, secondAxisEnd.y - center.y)
        let angle = atan2(axisEnd.y - center.y, axisEnd.x - center.x)
        guard rx > 0, ry > 0 else { return [center] }
        return (0..<segments).map { index in
            let t = CGFloat(index) / CGFloat(segments) * 2 * .pi
            let x = rx * cos(t)
            let y = ry * sin(t)
            let rotatedX = center.x + x * cos(angle) - y * sin(angle)
            let rotatedY = center.y + x * sin(angle) + y * cos(angle)
            return CGPoint(x: rotatedX, y: rotatedY)
        }
    }

    static func rectangleFromCenterDistances(_ center: CGPoint, halfWidth: CGFloat, halfHeight: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: center.x - halfWidth, y: center.y - halfHeight),
            CGPoint(x: center.x + halfWidth, y: center.y - halfHeight),
            CGPoint(x: center.x + halfWidth, y: center.y + halfHeight),
            CGPoint(x: center.x - halfWidth, y: center.y + halfHeight)
        ]
    }

    static func rectangleFromCenter(_ center: CGPoint, corner: CGPoint) -> [CGPoint] {
        let halfW = abs(corner.x - center.x)
        let halfH = abs(corner.y - center.y)
        return [
            CGPoint(x: center.x - halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y + halfH),
            CGPoint(x: center.x - halfW, y: center.y + halfH)
        ]
    }

    static func rectangleFromCorners(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        let rect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }

    static func arcPoints(
        center: CGPoint,
        start: CGPoint,
        end: CGPoint,
        sweep: CGFloat? = nil,
        segments: Int = 32
    ) -> [CGPoint] {
        let radius = hypot(start.x - center.x, start.y - center.y)
        guard radius > 0.001 else { return [start, end] }

        let projectedEnd = projectArcEndpoint(center: center, start: start, point: end)
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(projectedEnd.y - center.y, projectedEnd.x - center.x)
        let resolvedSweep = sweep ?? atan2(sin(endAngle - startAngle), cos(endAngle - startAngle))
        guard abs(resolvedSweep) > 0.0001 else { return [start, projectedEnd] }

        let adaptiveSegments = max(
            segments,
            min(128, max(12, Int(ceil(abs(resolvedSweep) / (.pi / 24)))))
        )
        var points: [CGPoint] = []
        points.reserveCapacity(adaptiveSegments + 1)
        for i in 0...adaptiveSegments {
            let t = CGFloat(i) / CGFloat(adaptiveSegments)
            let angle = startAngle + resolvedSweep * t
            points.append(CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            ))
        }
        return points
    }

    // MARK: - Curve (spline through drawn anchors)

    /// Builds a smooth polyline through `anchors` using a cardinal spline.
    /// The curvature at each anchor is derived from the direction (slope) of the
    /// adjacent drawn lines: gentle turns stay round and flowing, sharp turns
    /// tighten toward a crisp corner.
    static func smoothCurvePoints(anchors: [CGPoint], closed: Bool = false, samplesPerSegment: Int = 24) -> [CGPoint] {
        guard anchors.count >= 3 else { return anchors }

        var result: [CGPoint] = []
        let count = anchors.count
        let segmentCount = closed ? count : count - 1

        for index in 0..<segmentCount {
            let p1 = anchors[index]
            let p2 = anchors[(index + 1) % count]
            let p0: CGPoint
            let p3: CGPoint
            if closed {
                p0 = anchors[(index - 1 + count) % count]
                p3 = anchors[(index + 2) % count]
            } else {
                p0 = index > 0 ? anchors[index - 1] : p1
                p3 = index < count - 2 ? anchors[index + 2] : p2
            }

            let tension1 = curveTension(prev: p0, cur: p1, next: p2)
            let tension2 = curveTension(prev: p1, cur: p2, next: p3)

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * tension1 / 6,
                y: p1.y + (p2.y - p0.y) * tension1 / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * tension2 / 6,
                y: p2.y - (p3.y - p1.y) * tension2 / 6
            )

            let firstStep = index == 0 ? 0 : 1
            for step in firstStep...samplesPerSegment {
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                result.append(cubicBezierPoint(p1, control1, control2, p2, t: t))
            }
        }

        return result
    }

    /// Samples a curve through `anchors` using explicit, editable Bezier tangent handles.
    /// Each segment `i -> i+1` uses `anchors[i] + handles[i].outOffset` and
    /// `anchors[i+1] + handles[i+1].inOffset` as its two cubic control points.
    static func curvePoints(
        anchors: [CGPoint],
        handles: [CurveHandle],
        closed: Bool = false,
        samplesPerSegment: Int = 24
    ) -> [CGPoint] {
        guard anchors.count >= 2, handles.count == anchors.count else { return anchors }

        var result: [CGPoint] = []
        let count = anchors.count
        let segmentCount = closed ? count : count - 1

        for index in 0..<segmentCount {
            let nextIndex = (index + 1) % count
            let p1 = anchors[index]
            let p2 = anchors[nextIndex]
            let control1 = CGPoint(
                x: p1.x + handles[index].outOffset.x,
                y: p1.y + handles[index].outOffset.y
            )
            let control2 = CGPoint(
                x: p2.x + handles[nextIndex].inOffset.x,
                y: p2.y + handles[nextIndex].inOffset.y
            )

            let firstStep = index == 0 ? 0 : 1
            for step in firstStep...samplesPerSegment {
                let t = CGFloat(step) / CGFloat(samplesPerSegment)
                result.append(cubicBezierPoint(p1, control1, control2, p2, t: t))
            }
        }

        return result
    }

    /// Derives editable tangent handles from the auto-computed cardinal spline so a
    /// freshly committed curve keeps its current look but becomes reshapeable.
    static func defaultCurveHandles(anchors: [CGPoint], closed: Bool = false) -> [CurveHandle] {
        let count = anchors.count
        guard count >= 2 else {
            return anchors.map { _ in CurveHandle() }
        }

        var handles = anchors.map { _ in CurveHandle() }
        let segmentCount = closed ? count : count - 1

        for index in 0..<segmentCount {
            let nextIndex = (index + 1) % count
            let p1 = anchors[index]
            let p2 = anchors[nextIndex]
            let p0: CGPoint
            let p3: CGPoint
            if closed {
                p0 = anchors[(index - 1 + count) % count]
                p3 = anchors[(index + 2) % count]
            } else {
                p0 = index > 0 ? anchors[index - 1] : p1
                p3 = index < count - 2 ? anchors[index + 2] : p2
            }

            let tension1 = curveTension(prev: p0, cur: p1, next: p2)
            let tension2 = curveTension(prev: p1, cur: p2, next: p3)

            // Outgoing handle at p1 for this segment.
            handles[index].outOffset = CGPoint(
                x: (p2.x - p0.x) * tension1 / 6,
                y: (p2.y - p0.y) * tension1 / 6
            )
            // Incoming handle at p2 for this segment.
            handles[nextIndex].inOffset = CGPoint(
                x: -(p3.x - p1.x) * tension2 / 6,
                y: -(p3.y - p1.y) * tension2 / 6
            )
        }

        return handles
    }

    /// Roundness factor in `0...1` for the corner at `cur`.
    /// `1` (segments collinear) yields the roundest, most flowing curve;
    /// values approach `0` as the turn between the two lines becomes sharper,
    /// collapsing the handles so the corner reads as a crisp point.
    private static func curveTension(prev: CGPoint, cur: CGPoint, next: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: cur.x - prev.x, y: cur.y - prev.y)
        let v2 = CGPoint(x: next.x - cur.x, y: next.y - cur.y)
        let length1 = hypot(v1.x, v1.y)
        let length2 = hypot(v2.x, v2.y)
        guard length1 > 0.000001, length2 > 0.000001 else { return 1 }

        let cosAngle = max(-1, min(1, (v1.x * v2.x + v1.y * v2.y) / (length1 * length2)))
        let deflection = acos(cosAngle) // 0 = straight, .pi = full reversal
        return 1 - deflection / .pi
    }

    static func cubicBezierPoint(
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    static func projectArcEndpoint(center: CGPoint, start: CGPoint, point: CGPoint) -> CGPoint {
        let radius = hypot(start.x - center.x, start.y - center.y)
        guard radius > 0.001 else { return point }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance > 0.001 else { return start }
        let scale = radius / distance
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    static func projectCommandPoint(
        _ point: CGPoint,
        controlPoints: [CGPoint],
        category: ToolCategory,
        lineVariant: LineVariant = .line,
        circleVariant: CircleVariant,
        rectangleVariant: RectangleVariant
    ) -> CGPoint {
        guard let center = controlPoints.first else { return point }
        switch category {
        case .line where lineVariant == .arc:
            guard controlPoints.count >= 2 else { return point }
            return projectArcEndpoint(
                center: center,
                start: controlPoints[1],
                point: point
            )
        case .circle where circleVariant == .ellipse:
            if controlPoints.count == 1 {
                let rx = max(0.001, abs(point.x - center.x))
                return CGPoint(x: center.x + rx, y: center.y)
            }
            if controlPoints.count == 2 {
                let ry = max(0.001, abs(point.y - center.y))
                return CGPoint(x: center.x, y: center.y + ry)
            }
        case .rectangle where rectangleVariant == .center:
            if controlPoints.count == 1 {
                let halfW = max(0.001, abs(point.x - center.x))
                return CGPoint(x: center.x + halfW, y: center.y)
            }
            if controlPoints.count == 2 {
                let halfH = max(0.001, abs(point.y - center.y))
                return CGPoint(x: center.x, y: center.y + halfH)
            }
        default:
            break
        }
        return point
    }

    struct SemanticDimension: Identifiable {
        var id: String
        var label: String
        var midPoint: CGPoint
        var value: CGFloat
        var kind: Kind
        // The point on the shape this dimension references. Leader lines are drawn
        // from here to the (possibly dragged-away) label position.
        var anchor: CGPoint

        enum Kind {
            case segmentLength(segmentIndex: Int)
            case circleDiameter
            case ellipseRX
            case ellipseRY
            case rectangleWidth
            case rectangleHeight
        }
    }

    /// What stays put when a rectangle dimension changes. `.center` grows both sides
    /// equally; `.nearEdge` holds the side at the rectangle's local origin; `.farEdge`
    /// holds the opposite side.
    enum DimensionAnchor {
        case center
        case nearEdge
        case farEdge
    }

    /// A rectangle edge in the shape's local frame; raw values match the pill ids
    /// emitted by `semanticDimensions`.
    enum RectangleEdge: String {
        case top = "width-top"
        case bottom = "width-bottom"
        case left = "height-left"
        case right = "height-right"
    }

    /// Circles, ellipses, rectangles, and 4-point quads show every dimension on select.
    /// Multi-segment polylines and arcs reveal one edge at a time.
    static func showsDimensionsAutomatically(_ stroke: VectorStroke) -> Bool {
        switch stroke.shapeType {
        case .circle, .ellipse, .rectangle:
            return true
        default:
            return isEditableQuad(stroke)
        }
    }

    /// Nearest per-segment dimension on a complex stroke, using the same edges
    /// `semanticDimensions` emits so tap targets match visible labels.
    static func nearestSegmentDimension(
        on stroke: VectorStroke,
        to point: CGPoint,
        threshold: CGFloat
    ) -> (dimension: SemanticDimension, distance: CGFloat)? {
        let dims = semanticDimensions(for: stroke)
        var best: (SemanticDimension, CGFloat)?
        for dim in dims {
            guard case .segmentLength(let index) = dim.kind else { continue }
            let points = stroke.points
            guard points.indices.contains(index) else { continue }
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let distance = StrokeEditor.projectPointOnSegment(
                point: point,
                start: start,
                end: end
            ).distance
            if distance < threshold, best == nil || distance < best!.1 {
                best = (dim, distance)
            }
        }
        return best.map { (dimension: $0.0, distance: $0.1) }
    }

    /// Whether the stroke gets the paired quad dimension treatment: a true rectangle,
    /// or a closed four-corner polyline such as a trapezoid made by edge edits.
    static func isEditableQuad(_ stroke: VectorStroke) -> Bool {
        guard stroke.points.count == 4 else { return false }
        switch stroke.shapeType {
        case .rectangle:
            return true
        case .polyline:
            return stroke.isClosed && (stroke.curveHandles?.isEmpty ?? true)
        default:
            return false
        }
    }

    /// Resizes a single edge about its own midpoint along its own direction, leaving
    /// the opposite edge exactly where it is. Used when the opposite edge is pinned so
    /// the two can differ; a rectangle is demoted to a closed polyline once its
    /// opposite edges stop matching.
    static func applyEdgeLength(_ edge: RectangleEdge, newValue: CGFloat, to stroke: VectorStroke) -> VectorStroke? {
        guard isEditableQuad(stroke) else { return nil }
        let half = max(0.001, newValue) / 2
        var p = stroke.points

        let (startIndex, endIndex): (Int, Int)
        switch edge {
        case .top: (startIndex, endIndex) = (0, 1)
        case .bottom: (startIndex, endIndex) = (3, 2)
        case .left: (startIndex, endIndex) = (0, 3)
        case .right: (startIndex, endIndex) = (1, 2)
        }
        let vector = CGPoint(x: p[endIndex].x - p[startIndex].x, y: p[endIndex].y - p[startIndex].y)
        let length = hypot(vector.x, vector.y)
        guard length > 0.001 else { return nil }
        let dir = CGPoint(x: vector.x / length, y: vector.y / length)
        let m = midpoint(p[startIndex], p[endIndex])
        p[startIndex] = CGPoint(x: m.x - dir.x * half, y: m.y - dir.y * half)
        p[endIndex] = CGPoint(x: m.x + dir.x * half, y: m.y + dir.y * half)

        var updated = stroke
        updated.points = p
        if stroke.shapeType == .rectangle {
            let topLength = hypot(p[1].x - p[0].x, p[1].y - p[0].y)
            let bottomLength = hypot(p[2].x - p[3].x, p[2].y - p[3].y)
            let leftLength = hypot(p[3].x - p[0].x, p[3].y - p[0].y)
            let rightLength = hypot(p[2].x - p[1].x, p[2].y - p[1].y)
            let stillRectangle = abs(topLength - bottomLength) < 0.01 && abs(leftLength - rightLength) < 0.01
            if !stillRectangle {
                updated.shapeType = .polyline
                updated.shapeRotation = nil
                updated.rotationBasePoints = nil
                updated.rotationBaseCenter = nil
            }
        }
        return updated
    }

    /// Sets an edge's length by sliding the quad's two side groups apart along the
    /// axis between them, keeping the adjacent edges rigid. On a rectangle this is the
    /// familiar axis resize; on a trapezoid it keeps the shape symmetric, so editing
    /// one leg brings its unlocked partner along. The anchor picks which side group
    /// stays put (`.center` splits the motion evenly).
    static func applyQuadEdge(
        _ edge: RectangleEdge,
        newValue: CGFloat,
        to stroke: VectorStroke,
        anchor: DimensionAnchor
    ) -> VectorStroke? {
        guard isEditableQuad(stroke) else { return nil }
        var p = stroke.points

        // The edited edge runs from the near side group to the far side group.
        let nearGroup: [Int]
        let farGroup: [Int]
        let edgeStart: Int
        let edgeEnd: Int
        switch edge {
        case .top:
            (edgeStart, edgeEnd) = (0, 1)
            nearGroup = [0, 3]
            farGroup = [1, 2]
        case .bottom:
            (edgeStart, edgeEnd) = (3, 2)
            nearGroup = [0, 3]
            farGroup = [1, 2]
        case .left:
            (edgeStart, edgeEnd) = (0, 3)
            nearGroup = [0, 1]
            farGroup = [3, 2]
        case .right:
            (edgeStart, edgeEnd) = (1, 2)
            nearGroup = [0, 1]
            farGroup = [3, 2]
        }

        let nearMid = midpoint(p[nearGroup[0]], p[nearGroup[1]])
        let farMid = midpoint(p[farGroup[0]], p[farGroup[1]])
        let axisVector = CGPoint(x: farMid.x - nearMid.x, y: farMid.y - nearMid.y)
        let axisLength = hypot(axisVector.x, axisVector.y)
        guard axisLength > 0.001 else { return nil }
        let n = CGPoint(x: axisVector.x / axisLength, y: axisVector.y / axisLength)

        // Solve |w + t*n| = newValue for the far group's slide distance t.
        let w = CGPoint(x: p[edgeEnd].x - p[edgeStart].x, y: p[edgeEnd].y - p[edgeStart].y)
        let target = max(0.001, newValue)
        let along = w.x * n.x + w.y * n.y
        let discriminant = along * along - (w.x * w.x + w.y * w.y) + target * target
        // Negative: the edge cannot reach the target length by sliding, e.g. shorter
        // than the fixed perpendicular offset between the side groups.
        guard discriminant >= 0 else { return nil }
        let t = -along + sqrt(discriminant)

        let nearShift: CGFloat
        let farShift: CGFloat
        switch anchor {
        case .nearEdge:
            nearShift = 0
            farShift = t
        case .farEdge:
            nearShift = -t
            farShift = 0
        case .center:
            nearShift = -t / 2
            farShift = t / 2
        }
        for index in nearGroup {
            p[index] = CGPoint(x: p[index].x + n.x * nearShift, y: p[index].y + n.y * nearShift)
        }
        for index in farGroup {
            p[index] = CGPoint(x: p[index].x + n.x * farShift, y: p[index].y + n.y * farShift)
        }

        // Reject collapses and inversions: shrinking a trapezoid's top too far would
        // push the bottom edge through zero and out the other side as a bowtie.
        let edgePairs = [(0, 1), (1, 2), (3, 2), (0, 3)]
        for (a, b) in edgePairs {
            let old = CGPoint(x: stroke.points[b].x - stroke.points[a].x, y: stroke.points[b].y - stroke.points[a].y)
            let new = CGPoint(x: p[b].x - p[a].x, y: p[b].y - p[a].y)
            if hypot(new.x, new.y) < 0.001 || old.x * new.x + old.y * new.y <= 0 {
                return nil
            }
        }

        var updated = stroke
        updated.points = p
        return updated
    }

    /// Distance in document units between a dimension's anchor point on the shape and
    /// its resting label position. The overlay may push farther in view space so the
    /// on-screen label clears the stroke at any zoom.
    private static let labelStandoff: CGFloat = 28

    /// Unit normal of the edge `start→end` that points away from `reference` (typically
    /// the shape centroid). Falls back to the CCW perpendicular when the reference sits
    /// on the edge (e.g. a two-point line).
    private static func outwardNormal(
        from start: CGPoint,
        to end: CGPoint,
        awayFrom reference: CGPoint
    ) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return CGPoint(x: 0, y: -1) }
        let ccw = CGPoint(x: -dy / length, y: dx / length)
        let mid = midpoint(start, end)
        let away = CGPoint(x: mid.x - reference.x, y: mid.y - reference.y)
        if hypot(away.x, away.y) < 0.001 {
            return ccw
        }
        return ccw.x * away.x + ccw.y * away.y >= 0
            ? ccw
            : CGPoint(x: -ccw.x, y: -ccw.y)
    }

    private static func labelPlacement(
        edgeStart: CGPoint,
        edgeEnd: CGPoint,
        awayFrom reference: CGPoint,
        standoff: CGFloat = labelStandoff
    ) -> (anchor: CGPoint, midPoint: CGPoint) {
        let anchor = midpoint(edgeStart, edgeEnd)
        let normal = outwardNormal(from: edgeStart, to: edgeEnd, awayFrom: reference)
        let midPoint = CGPoint(
            x: anchor.x + normal.x * standoff,
            y: anchor.y + normal.y * standoff
        )
        return (anchor, midPoint)
    }

    private static func pointsCentroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let count = CGFloat(points.count)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    /// One editable pill per quad edge. Each pill shows its own edge's length (they
    /// differ on a trapezoid), placed just outside the shape past the edge midpoint.
    private static func quadDimensions(for stroke: VectorStroke) -> [SemanticDimension] {
        guard isEditableQuad(stroke) else { return [] }
        let p = stroke.points
        let centroid = pointsCentroid(p)
        let edges: [(edge: RectangleEdge, start: CGPoint, end: CGPoint, kind: SemanticDimension.Kind)] = [
            (.top, p[0], p[1], .rectangleWidth),
            (.bottom, p[3], p[2], .rectangleWidth),
            (.left, p[0], p[3], .rectangleHeight),
            (.right, p[1], p[2], .rectangleHeight)
        ]
        return edges.compactMap { entry in
            let length = hypot(entry.end.x - entry.start.x, entry.end.y - entry.start.y)
            guard length > 0.001 else { return nil }
            let placement = labelPlacement(
                edgeStart: entry.start,
                edgeEnd: entry.end,
                awayFrom: centroid
            )
            return SemanticDimension(
                id: entry.edge.rawValue,
                label: String(format: "%.3f", length),
                midPoint: placement.midPoint,
                value: length,
                kind: entry.kind,
                anchor: placement.anchor
            )
        }
    }

    static func semanticDimensions(for stroke: VectorStroke) -> [SemanticDimension] {
        switch stroke.shapeType {
        case .circle:
            guard let circle = circleFromCardinalPoints(stroke.points) else { return [] }
            let diameter = circle.radius * 2
            let top = CGPoint(x: circle.center.x, y: circle.center.y - circle.radius)
            return [SemanticDimension(
                id: "diameter",
                label: String(format: "%.3f", diameter),
                midPoint: CGPoint(x: top.x, y: top.y - labelStandoff),
                value: diameter,
                kind: .circleDiameter,
                anchor: top
            )]
        case .ellipse:
            guard let ellipse = ellipseFromCardinalPoints(stroke.points) else { return [] }
            let top = CGPoint(x: ellipse.center.x, y: ellipse.center.y - ellipse.ry)
            let left = CGPoint(x: ellipse.center.x - ellipse.rx, y: ellipse.center.y)
            return [
                SemanticDimension(
                    id: "rx",
                    label: String(format: "rx %.3f", ellipse.rx),
                    midPoint: CGPoint(x: top.x, y: top.y - labelStandoff),
                    value: ellipse.rx,
                    kind: .ellipseRX,
                    anchor: top
                ),
                SemanticDimension(
                    id: "ry",
                    label: String(format: "ry %.3f", ellipse.ry),
                    midPoint: CGPoint(x: left.x - labelStandoff, y: left.y),
                    value: ellipse.ry,
                    kind: .ellipseRY,
                    anchor: left
                )
            ]
        case .rectangle:
            return quadDimensions(for: stroke)
        default:
            if isEditableQuad(stroke) {
                return quadDimensions(for: stroke)
            }
            let points = stroke.points
            guard points.count >= 2 else { return [] }
            let centroid = pointsCentroid(points)
            let count = stroke.isClosed ? points.count : points.count - 1
            return (0..<count).compactMap { index in
                let start = points[index]
                let end = points[(index + 1) % points.count]
                let length = hypot(end.x - start.x, end.y - start.y)
                guard length > 0.001 else { return nil }
                let placement = labelPlacement(
                    edgeStart: start,
                    edgeEnd: end,
                    awayFrom: centroid
                )
                return SemanticDimension(
                    id: "seg-\(index)",
                    label: String(format: "%.3f", length),
                    midPoint: placement.midPoint,
                    value: length,
                    kind: .segmentLength(segmentIndex: index),
                    anchor: placement.anchor
                )
            }
        }
    }

    static func applyDimension(_ dimension: SemanticDimension, newValue: CGFloat, to stroke: VectorStroke) -> VectorStroke? {
        var updated = stroke
        switch dimension.kind {
        case .circleDiameter:
            guard let circle = circleFromCardinalPoints(stroke.points) else { return nil }
            let radius = max(0.001, newValue / 2)
            updated.points = circleCardinalPoints(center: circle.center, radius: radius)
        case .ellipseRX:
            guard let ellipse = ellipseFromCardinalPoints(stroke.points) else { return nil }
            updated.points = ellipseCardinalPoints(center: ellipse.center, rx: max(0.001, newValue), ry: ellipse.ry)
        case .ellipseRY:
            guard let ellipse = ellipseFromCardinalPoints(stroke.points) else { return nil }
            updated.points = ellipseCardinalPoints(center: ellipse.center, rx: ellipse.rx, ry: max(0.001, newValue))
        case .rectangleWidth, .rectangleHeight:
            // Quad edges are routed through applyQuadEdge/applyEdgeLength, which know
            // which specific edge is being edited.
            return nil
        case .segmentLength(let segmentIndex):
            let points = stroke.points
            guard points.count >= 2 else { return nil }
            let endIndex = stroke.isClosed ? (segmentIndex + 1) % points.count : segmentIndex + 1
            guard endIndex < points.count else { return nil }
            let start = points[segmentIndex]
            let end = points[endIndex]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let current = hypot(dx, dy)
            guard current > 0.001 else { return nil }
            let scale = newValue / current
            updated.points[endIndex] = CGPoint(x: start.x + dx * scale, y: start.y + dy * scale)
        }
        return updated
    }

    private static func stablePolylineCenter(for stroke: VectorStroke) -> CGPoint? {
        let points = normalizedPolylinePoints(stroke.points, isClosed: stroke.isClosed)
        guard !points.isEmpty else { return nil }
        if stroke.isClosed,
           points.count >= 3,
           let centroid = polygonCentroid(points) {
            return centroid
        }
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let count = CGFloat(points.count)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private static func normalizedPolylinePoints(_ points: [CGPoint], isClosed: Bool) -> [CGPoint] {
        var normalized = points
        if isClosed,
           normalized.count > 1,
           hypot(normalized[0].x - normalized[normalized.count - 1].x,
                 normalized[0].y - normalized[normalized.count - 1].y) <= 0.001 {
            normalized.removeLast()
        }
        return normalized
    }

    private static func polygonCentroid(_ points: [CGPoint]) -> CGPoint? {
        guard points.count >= 3 else { return nil }
        var twiceArea: CGFloat = 0
        var centroidX: CGFloat = 0
        var centroidY: CGFloat = 0

        for index in points.indices {
            let p0 = points[index]
            let p1 = points[(index + 1) % points.count]
            let cross = p0.x * p1.y - p1.x * p0.y
            twiceArea += cross
            centroidX += (p0.x + p1.x) * cross
            centroidY += (p0.y + p1.y) * cross
        }

        guard abs(twiceArea) > 0.0001 else { return nil }
        let scale = 1 / (3 * twiceArea)
        return CGPoint(x: centroidX * scale, y: centroidY * scale)
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Default editable anchors of an arc: start, end, and any cardinals the sweep
    /// crosses — 2, 3, or 4 points depending on length. Dense tessellations collapse
    /// back to that set. Very short arcs that cannot recover a circle keep start/end.
    static func arcAnchorPoints(_ points: [CGPoint]) -> [CGPoint]? {
        guard let first = points.first, let last = points.last else { return nil }
        if points.count < 8 { return points }
        guard points.count >= 3 else { return nil }
        let through = points[1]
        guard let circle = arcCenter(start: first, end: last, through: through) else {
            return [first, points[points.count / 2], last]
        }
        let tolerance = max(0.75, circle.radius * 0.025)
        let allOnCircle = points.allSatisfy {
            abs(hypot($0.x - circle.center.x, $0.y - circle.center.y) - circle.radius) <= tolerance
        }
        guard allOnCircle else { return [first, points[points.count / 2], last] }
        guard let sweep = signedCircularSweep(of: points, around: circle.center, closed: false) else {
            return [first, through, last]
        }
        return defaultCircularAnchors(
            center: circle.center,
            radius: circle.radius,
            start: first,
            end: last,
            sweep: sweep,
            closed: false
        )
    }

    /// Signed sweep along `points` about `center`, walking every consecutive pair so a
    /// 270° leftover after a quadrant trim is not collapsed to the 90° short arc
    /// that shares the same endpoints.
    static func signedCircularSweep(
        of points: [CGPoint],
        around center: CGPoint,
        closed: Bool = false
    ) -> CGFloat? {
        guard let first = points.first else { return nil }
        var total: CGFloat = 0
        var previous = atan2(first.y - center.y, first.x - center.x)
        let chain: [CGPoint]
        if closed {
            chain = Array(points.dropFirst()) + [first]
        } else {
            chain = Array(points.dropFirst())
        }
        guard !chain.isEmpty else { return nil }
        for point in chain {
            let angle = atan2(point.y - center.y, point.x - center.x)
            var step = angle - previous
            if step > .pi { step -= 2 * .pi }
            if step < -.pi { step += 2 * .pi }
            total += step
            previous = angle
        }
        if closed, abs(total) < 0.05 {
            return copysign(2 * .pi, total == 0 ? 1 : total)
        }
        return total
    }

    /// Cubic Bezier handles that approximate the circular arc through `start`, `mid`,
    /// and `end` as two segments (`start→mid`, `mid→end`). Used when an arc is joined
    /// into a `.curve` stroke so the circular geometry survives as editable tangents.
    static func curveHandlesApproximatingArc(
        start: CGPoint,
        mid: CGPoint,
        end: CGPoint
    ) -> [CurveHandle]? {
        guard let circle = arcCenter(start: start, end: end, through: mid) else { return nil }
        var handles = [CurveHandle(), CurveHandle(), CurveHandle()]
        let first = circularArcHandleOffsets(
            from: start,
            to: mid,
            center: circle.center,
            radius: circle.radius,
            through: mid
        )
        handles[0].outOffset = first.outFromStart
        handles[1].inOffset = first.inToEnd
        let second = circularArcHandleOffsets(
            from: mid,
            to: end,
            center: circle.center,
            radius: circle.radius,
            through: end
        )
        handles[1].outOffset = second.outFromStart
        handles[2].inOffset = second.inToEnd
        return handles
    }

    /// Standard cubic approximation of a circular arc: κ = 4/3 · tan(θ/4).
    static func circularArcHandleOffsets(
        from start: CGPoint,
        to end: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        through: CGPoint
    ) -> (outFromStart: CGPoint, inToEnd: CGPoint) {
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var sweep = endAngle - startAngle
        var testSweep = atan2(through.y - center.y, through.x - center.x) - startAngle
        while testSweep > .pi { testSweep -= 2 * .pi }
        while testSweep < -.pi { testSweep += 2 * .pi }
        while sweep > .pi { sweep -= 2 * .pi }
        while sweep < -.pi { sweep += 2 * .pi }
        // When `through` is the segment end itself, keep the short-arc sweep.
        if through != end, (testSweep > 0) != (sweep > 0) {
            sweep = testSweep > 0 ? sweep + 2 * .pi : sweep - 2 * .pi
        }
        guard abs(sweep) > 0.0001, radius > 0.001 else {
            return (.zero, .zero)
        }
        let kappa = (4.0 / 3.0) * tan(sweep / 4.0) * radius
        let outFromStart = CGPoint(
            x: -sin(startAngle) * kappa,
            y: cos(startAngle) * kappa
        )
        let inToEnd = CGPoint(
            x: sin(endAngle) * kappa,
            y: -cos(endAngle) * kappa
        )
        return (outFromStart, inToEnd)
    }

    private static func arcControlCenter(from arcPoints: [CGPoint]) -> CGPoint? {
        guard arcPoints.count >= 3 else { return nil }
        let start = arcPoints.first!
        let end = arcPoints.last!
        let through = arcPoints[arcPoints.count / 2]
        // Circumcenter of start/mid/end — stable for partial arcs. Do not use the
        // sample centroid (`fitCircle`), which shifts toward the remaining sweep.
        if let arc = arcCenter(start: start, end: end, through: through) {
            return arc.center
        }
        if let fitted = fitCircle(from: arcPoints), arcPoints.count >= 24 {
            // Dense near-full contours only; centroid is usable when coverage is high.
            let span = hypot(end.x - start.x, end.y - start.y)
            if span <= fitted.radius * 0.35 {
                return fitted.center
            }
        }
        return nil
    }

    /// Samples the circular arc that passes through `start`, `through`, and `end` (in that order).
    /// Used to re-expand baked fillet midpoints into smooth curves.
    static func arcPointsThrough(
        start: CGPoint,
        end: CGPoint,
        through: CGPoint,
        segments: Int = 32
    ) -> [CGPoint] {
        guard let arc = arcCenter(start: start, end: end, through: through) else {
            return [start, through, end]
        }
        var points: [CGPoint] = []
        let startAngle = atan2(start.y - arc.center.y, start.x - arc.center.x)
        let endAngle = atan2(end.y - arc.center.y, end.x - arc.center.x)
        var sweep = endAngle - startAngle
        let throughAngle = atan2(through.y - arc.center.y, through.x - arc.center.x)
        var testSweep = throughAngle - startAngle
        while testSweep > .pi { testSweep -= 2 * .pi }
        while testSweep < -.pi { testSweep += 2 * .pi }
        while sweep > .pi { sweep -= 2 * .pi }
        while sweep < -.pi { sweep += 2 * .pi }
        if (testSweep > 0) != (sweep > 0) {
            sweep = testSweep > 0 ? sweep + 2 * .pi : sweep - 2 * .pi
        }
        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let angle = startAngle + sweep * t
            points.append(CGPoint(
                x: arc.center.x + cos(angle) * arc.radius,
                y: arc.center.y + sin(angle) * arc.radius
            ))
        }
        return points
    }

    private static func arcCenter(start: CGPoint, end: CGPoint, through: CGPoint) -> (center: CGPoint, radius: CGFloat)? {
        let d = 2 * (start.x * (end.y - through.y) + end.x * (through.y - start.y) + through.x * (start.y - end.y))
        guard abs(d) > 0.001 else { return nil }
        let ux = ((start.x * start.x + start.y * start.y) * (end.y - through.y)
            + (end.x * end.x + end.y * end.y) * (through.y - start.y)
            + (through.x * through.x + through.y * through.y) * (start.y - end.y)) / d
        let uy = ((start.x * start.x + start.y * start.y) * (through.x - end.x)
            + (end.x * end.x + end.y * end.y) * (start.x - through.x)
            + (through.x * through.x + through.y * through.y) * (end.x - start.x)) / d
        let center = CGPoint(x: ux, y: uy)
        let radius = hypot(start.x - center.x, start.y - center.y)
        guard radius > 0.001 else { return nil }
        return (center, radius)
    }

    static func buildStrokeFromDrag(
        category: ToolCategory,
        circleVariant: CircleVariant,
        rectangleVariant: RectangleVariant,
        start: CGPoint,
        end: CGPoint,
        layerID: UUID,
        strokeWidth: CGFloat,
        strokeColor: CodableColor
    ) -> VectorStroke? {
        switch category {
        case .line:
            guard hypot(end.x - start.x, end.y - start.y) > 0.001 else { return nil }
            return VectorStroke(
                layerID: layerID,
                points: [start, end],
                strokeWidth: strokeWidth,
                strokeColor: strokeColor,
                shapeType: .polyline
            )
        case .circle:
            switch circleVariant {
            case .center:
                let radius = hypot(end.x - start.x, end.y - start.y)
                guard radius > 0.001 else { return nil }
                return VectorStroke(
                    layerID: layerID,
                    points: circleCardinalPoints(center: start, radius: radius),
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: true,
                    shapeType: .circle
                )
            case .edge:
                let diameter = hypot(end.x - start.x, end.y - start.y)
                guard diameter > 0.001 else { return nil }
                let center = CGPoint(
                    x: (start.x + end.x) / 2,
                    y: (start.y + end.y) / 2
                )
                return VectorStroke(
                    layerID: layerID,
                    points: circleCardinalPoints(center: center, radius: diameter / 2),
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: true,
                    shapeType: .circle
                )
            case .ellipse:
                let rx = max(0.001, abs(end.x - start.x))
                let ry = max(0.001, abs(end.y - start.y))
                return VectorStroke(
                    layerID: layerID,
                    points: ellipseCardinalPoints(center: start, rx: rx, ry: ry),
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: true,
                    shapeType: .ellipse
                )
            }
        case .rectangle:
            switch rectangleVariant {
            case .center:
                let halfW = max(0.001, abs(end.x - start.x))
                let halfH = max(0.001, abs(end.y - start.y))
                return VectorStroke(
                    layerID: layerID,
                    points: rectangleFromCenterDistances(start, halfWidth: halfW, halfHeight: halfH),
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: true,
                    shapeType: .rectangle
                )
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
