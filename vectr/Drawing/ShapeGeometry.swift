//
//  ShapeGeometry.swift
//  vectr
//

import CoreGraphics
import Foundation

enum ShapeGeometry {
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
                return VectorStroke(
                    layerID: layerID,
                    points: points,
                    strokeWidth: strokeWidth,
                    strokeColor: strokeColor,
                    isClosed: false,
                    shapeType: .arc
                )
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
            return stroke.points.count == 4 ? stroke.points : handlePointsForLegacyCircle(stroke.points)
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
        case .rectangle:
            return stroke.points
        default:
            return stroke.points
        }
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
            return stroke.points
        case .curve:
            if let handles = stroke.curveHandles, handles.count == stroke.points.count {
                return curvePoints(anchors: stroke.points, handles: handles)
            }
            return smoothCurvePoints(anchors: stroke.points)
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

    /// Expands baked fillet corners (single midpoint anchors) into smooth circular arcs so the
    /// rendered/exported contour looks curved, while the stored anchor set stays minimal.
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

        for index in 0..<count {
            let isEndpoint = !closed && (index == 0 || index == count - 1)
            if smoothMiddles.contains(index), !isEndpoint {
                let prev = points[(index - 1 + count) % count]
                let next = points[(index + 1) % count]
                for point in arcPointsThrough(start: prev, end: next, through: points[index], segments: segmentsPerArc) {
                    append(point)
                }
            } else {
                append(points[index])
            }
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

    static func circleFromCardinalPoints(_ points: [CGPoint]) -> (center: CGPoint, radius: CGFloat)? {
        guard points.count == 4 else { return nil }
        let center = CGPoint(x: (points[0].x + points[2].x) / 2, y: (points[0].y + points[2].y) / 2)
        let radius = hypot(points[0].x - center.x, points[0].y - center.y)
        guard radius > 0.001 else { return nil }
        return (center, radius)
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

    private static func fitCircle(from points: [CGPoint]) -> (center: CGPoint, radius: CGFloat)? {
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
    static func smoothCurvePoints(anchors: [CGPoint], samplesPerSegment: Int = 24) -> [CGPoint] {
        guard anchors.count >= 3 else { return anchors }

        var result: [CGPoint] = []
        let count = anchors.count

        for index in 0..<(count - 1) {
            let p1 = anchors[index]
            let p2 = anchors[index + 1]
            let p0 = index > 0 ? anchors[index - 1] : p1
            let p3 = index < count - 2 ? anchors[index + 2] : p2

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
        samplesPerSegment: Int = 24
    ) -> [CGPoint] {
        guard anchors.count >= 2, handles.count == anchors.count else { return anchors }

        var result: [CGPoint] = []
        let count = anchors.count

        for index in 0..<(count - 1) {
            let p1 = anchors[index]
            let p2 = anchors[index + 1]
            let control1 = CGPoint(
                x: p1.x + handles[index].outOffset.x,
                y: p1.y + handles[index].outOffset.y
            )
            let control2 = CGPoint(
                x: p2.x + handles[index + 1].inOffset.x,
                y: p2.y + handles[index + 1].inOffset.y
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
    static func defaultCurveHandles(anchors: [CGPoint]) -> [CurveHandle] {
        let count = anchors.count
        guard count >= 2 else {
            return anchors.map { _ in CurveHandle() }
        }

        var handles = anchors.map { _ in CurveHandle() }

        for index in 0..<(count - 1) {
            let p1 = anchors[index]
            let p2 = anchors[index + 1]
            let p0 = index > 0 ? anchors[index - 1] : p1
            let p3 = index < count - 2 ? anchors[index + 2] : p2

            let tension1 = curveTension(prev: p0, cur: p1, next: p2)
            let tension2 = curveTension(prev: p1, cur: p2, next: p3)

            // Outgoing handle at p1 for this segment.
            handles[index].outOffset = CGPoint(
                x: (p2.x - p0.x) * tension1 / 6,
                y: (p2.y - p0.y) * tension1 / 6
            )
            // Incoming handle at p2 for this segment.
            handles[index + 1].inOffset = CGPoint(
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

    private static func cubicBezierPoint(
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

    static func semanticDimensions(for stroke: VectorStroke) -> [SemanticDimension] {
        switch stroke.shapeType {
        case .circle:
            guard let circle = circleFromCardinalPoints(stroke.points) else { return [] }
            let diameter = circle.radius * 2
            return [SemanticDimension(
                id: "diameter",
                label: String(format: "%.3f", diameter),
                midPoint: CGPoint(x: circle.center.x, y: circle.center.y - circle.radius - 20),
                value: diameter,
                kind: .circleDiameter,
                anchor: CGPoint(x: circle.center.x, y: circle.center.y - circle.radius)
            )]
        case .ellipse:
            guard let ellipse = ellipseFromCardinalPoints(stroke.points) else { return [] }
            return [
                SemanticDimension(
                    id: "rx",
                    label: String(format: "rx %.3f", ellipse.rx),
                    midPoint: CGPoint(x: ellipse.center.x + ellipse.rx / 2, y: ellipse.center.y - 24),
                    value: ellipse.rx,
                    kind: .ellipseRX,
                    anchor: CGPoint(x: ellipse.center.x + ellipse.rx / 2, y: ellipse.center.y)
                ),
                SemanticDimension(
                    id: "ry",
                    label: String(format: "ry %.3f", ellipse.ry),
                    midPoint: CGPoint(x: ellipse.center.x - ellipse.rx - 24, y: ellipse.center.y),
                    value: ellipse.ry,
                    kind: .ellipseRY,
                    anchor: CGPoint(x: ellipse.center.x - ellipse.rx, y: ellipse.center.y)
                )
            ]
        case .rectangle:
            guard stroke.points.count == 4 else { return [] }
            return (0..<4).map { index in
                let start = stroke.points[index]
                let end = stroke.points[(index + 1) % 4]
                let length = hypot(end.x - start.x, end.y - start.y)
                return SemanticDimension(
                    id: "side-\(index)",
                    label: String(format: "%.3f", length),
                    midPoint: midpoint(start, end),
                    value: length,
                    kind: .segmentLength(segmentIndex: index),
                    anchor: midpoint(start, end)
                )
            }
        default:
            let points = stroke.points
            guard points.count >= 2 else { return [] }
            let count = stroke.isClosed ? points.count : points.count - 1
            return (0..<count).map { index in
                let start = points[index]
                let end = points[(index + 1) % points.count]
                let length = hypot(end.x - start.x, end.y - start.y)
                return SemanticDimension(
                    id: "seg-\(index)",
                    label: String(format: "%.3f", length),
                    midPoint: midpoint(start, end),
                    value: length,
                    kind: .segmentLength(segmentIndex: index),
                    anchor: midpoint(start, end)
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
        case .rectangleWidth:
            guard stroke.points.count == 4 else { return nil }
            let center = CGPoint(x: (stroke.points[0].x + stroke.points[2].x) / 2, y: (stroke.points[0].y + stroke.points[2].y) / 2)
            let halfH = abs(stroke.points[2].y - center.y)
            updated.points = rectangleFromCenterDistances(center, halfWidth: max(0.001, newValue / 2), halfHeight: halfH)
        case .rectangleHeight:
            guard stroke.points.count == 4 else { return nil }
            let center = CGPoint(x: (stroke.points[0].x + stroke.points[2].x) / 2, y: (stroke.points[0].y + stroke.points[2].y) / 2)
            let halfW = abs(stroke.points[1].x - center.x)
            updated.points = rectangleFromCenterDistances(center, halfWidth: halfW, halfHeight: max(0.001, newValue / 2))
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

    private static func arcControlCenter(from arcPoints: [CGPoint]) -> CGPoint? {
        guard arcPoints.count >= 3 else { return nil }
        if let fitted = fitCircle(from: arcPoints) {
            return fitted.center
        }
        let start = arcPoints.first!
        let end = arcPoints.last!
        let through = arcPoints[arcPoints.count / 2]
        if let arc = arcCenter(start: start, end: end, through: through) {
            return arc.center
        }
        if let bbox = VectorStroke(layerID: UUID(), points: arcPoints).boundingBox() {
            return CGPoint(x: bbox.midX, y: bbox.midY)
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
