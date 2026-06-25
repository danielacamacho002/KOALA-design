//
//  FilletPathBuilder.swift
//  vectr
//

import CoreGraphics

enum FilletPathBuilder {
    static func axisAlignedRectangle(from points: [CGPoint]) -> CGRect? {
        axisAlignedRect(from: points)
    }

    /// Builds a stroked outline path with filleted corners.
    static func path(for stroke: VectorStroke) -> CGPath {
        let normalized = normalizedClosedPath(points: stroke.points, closed: stroke.isClosed)
        guard normalized.points.count >= 3 else {
            return stroke.cgPath()
        }

        let cornerRadii = stroke.resolvedFilletCornerRadii().reduce(into: [Int: CGFloat]()) { partial, entry in
            let (index, radius) = entry
            guard index < normalized.points.count else { return }
            partial[index] = radius
        }
        guard !cornerRadii.isEmpty else {
            return plainPath(points: normalized.points, closed: normalized.closed)
        }

        return filletedPolyline(
            points: normalized.points,
            radiiByCorner: cornerRadii,
            closed: normalized.closed
        )
    }

    static func path(points: [CGPoint], cornerRadius: CGFloat, closed: Bool) -> CGPath {
        let normalized = normalizedClosedPath(points: points, closed: closed)
        guard cornerRadius > 0, normalized.points.count >= 3 else {
            return plainPath(points: normalized.points, closed: normalized.closed)
        }

        var radiiByCorner: [Int: CGFloat] = [:]
        if normalized.closed {
            for index in 0..<normalized.points.count {
                radiiByCorner[index] = cornerRadius
            }
        } else if normalized.points.count > 2 {
            for index in 1..<(normalized.points.count - 1) {
                radiiByCorner[index] = cornerRadius
            }
        }
        return filletedPolyline(points: normalized.points, radiiByCorner: radiiByCorner, closed: normalized.closed)
    }

    // MARK: - Private

    private static func plainPath(points: [CGPoint], closed: Bool) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        if closed, points.count > 2 { path.closeSubpath() }
        return path
    }

    private static func filletedPolyline(points: [CGPoint], radiiByCorner: [Int: CGFloat], closed: Bool) -> CGPath {
        let count = points.count
        guard count >= 2 else { return CGMutablePath() }
        guard !radiiByCorner.isEmpty else { return plainPath(points: points, closed: closed) }

        if closed {
            return filletedClosedPolyline(points: points, radiiByCorner: radiiByCorner)
        }
        return filletedOpenPolyline(points: points, radiiByCorner: radiiByCorner)
    }

    private static func filletedOpenPolyline(points: [CGPoint], radiiByCorner: [Int: CGFloat]) -> CGPath {
        let count = points.count
        guard count >= 2 else { return CGMutablePath() }

        let path = CGMutablePath()
        path.move(to: points[0])

        if count >= 3 {
            for cornerIndex in 1..<(count - 1) {
                let radius = max(0, radiiByCorner[cornerIndex] ?? 0)
                guard radius > 0,
                      let fillet = filletArc(
                        prev: points[cornerIndex - 1],
                        corner: points[cornerIndex],
                        next: points[cornerIndex + 1],
                        radius: radius
                      ) else {
                    path.addLine(to: points[cornerIndex])
                    continue
                }
                path.addLine(to: fillet.start)
                path.addArc(
                    center: fillet.center,
                    radius: fillet.radius,
                    startAngle: fillet.startAngle,
                    endAngle: fillet.endAngle,
                    clockwise: fillet.clockwise
                )
            }
        }

        path.addLine(to: points[count - 1])
        return path
    }

    private static func filletedClosedPolyline(points: [CGPoint], radiiByCorner: [Int: CGFloat]) -> CGPath {
        let count = points.count
        guard count >= 3 else { return plainPath(points: points, closed: true) }

        var arcsByCorner: [Int: FilletArc] = [:]
        for cornerIndex in 0..<count {
            let radius = max(0, radiiByCorner[cornerIndex] ?? 0)
            guard radius > 0 else { continue }
            let prevIndex = (cornerIndex - 1 + count) % count
            let nextIndex = (cornerIndex + 1) % count
            if let arc = filletArc(
                prev: points[prevIndex],
                corner: points[cornerIndex],
                next: points[nextIndex],
                radius: radius
            ) {
                arcsByCorner[cornerIndex] = arc
            }
        }

        let path = CGMutablePath()
        if let firstArc = arcsByCorner[0] {
            path.move(to: firstArc.start)
        } else {
            path.move(to: points[0])
        }

        for cornerIndex in 0..<count {
            if cornerIndex > 0 {
                if let arc = arcsByCorner[cornerIndex] {
                    path.addLine(to: arc.start)
                } else {
                    path.addLine(to: points[cornerIndex])
                }
            }
            if let arc = arcsByCorner[cornerIndex] {
                path.addArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle,
                    clockwise: arc.clockwise
                )
            }
        }

        path.closeSubpath()
        return path
    }

    private struct FilletArc {
        var start: CGPoint
        var center: CGPoint
        var radius: CGFloat
        var startAngle: CGFloat
        var endAngle: CGFloat
        var clockwise: Bool
    }

    private static func filletArc(prev: CGPoint, corner: CGPoint, next: CGPoint, radius: CGFloat) -> FilletArc? {
        let v1 = CGPoint(x: prev.x - corner.x, y: prev.y - corner.y)
        let v2 = CGPoint(x: next.x - corner.x, y: next.y - corner.y)
        let len1 = hypot(v1.x, v1.y)
        let len2 = hypot(v2.x, v2.y)
        guard len1 > 0.001, len2 > 0.001 else { return nil }

        let u1 = CGPoint(x: v1.x / len1, y: v1.y / len1)
        let u2 = CGPoint(x: v2.x / len2, y: v2.y / len2)

        let dot = max(-1, min(1, u1.x * u2.x + u1.y * u2.y))
        let angle = acos(dot)
        guard angle > 0.01, angle < .pi - 0.01 else { return nil }

        let tanHalf = tan(angle / 2)
        guard tanHalf > 0.001 else { return nil }

        var trim = radius / tanHalf
        let maxTrim = min(len1, len2) * 0.45
        trim = min(trim, maxTrim)
        let effectiveRadius = trim * tanHalf
        guard effectiveRadius > 0.1 else { return nil }

        let start = CGPoint(x: corner.x + u1.x * trim, y: corner.y + u1.y * trim)
        let end = CGPoint(x: corner.x + u2.x * trim, y: corner.y + u2.y * trim)

        let bisector = CGPoint(x: u1.x + u2.x, y: u1.y + u2.y)
        let bisLen = hypot(bisector.x, bisector.y)
        guard bisLen > 0.001 else { return nil }

        let interior = CGPoint(x: bisector.x / bisLen, y: bisector.y / bisLen)
        let centerDist = effectiveRadius / sin(angle / 2)
        let center = CGPoint(
            x: corner.x + interior.x * centerDist,
            y: corner.y + interior.y * centerDist
        )

        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var delta = endAngle - startAngle
        while delta <= -.pi { delta += 2 * .pi }
        while delta > .pi { delta -= 2 * .pi }
        let clockwise = delta < 0

        return FilletArc(
            start: start,
            center: center,
            radius: effectiveRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
    }

    private static func axisAlignedRect(from points: [CGPoint]) -> CGRect? {
        var unique = points
        if unique.count > 1, unique.first == unique.last {
            unique.removeLast()
        }
        guard unique.count == 4 else { return nil }

        let xs = unique.map(\.x)
        let ys = unique.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!

        for point in unique {
            let onEdgeX = abs(point.x - minX) < 0.01 || abs(point.x - maxX) < 0.01
            let onEdgeY = abs(point.y - minY) < 0.01 || abs(point.y - maxY) < 0.01
            guard onEdgeX || onEdgeY else { return nil }
        }

        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private static func normalizedClosedPath(points: [CGPoint], closed: Bool) -> (points: [CGPoint], closed: Bool) {
        guard closed, points.count > 1 else { return (points, closed) }
        var normalized = points
        let first = normalized[0]
        let last = normalized[normalized.count - 1]
        if hypot(first.x - last.x, first.y - last.y) <= 0.001 {
            normalized.removeLast()
        }
        return (normalized, closed)
    }
}
