//
//  StrokeBuilder.swift
//  vectr
//

import CoreGraphics
import Foundation

enum QuickShapeKind: String, Codable {
    case line
    case rectangle
    case circle
    case polygon
}

struct StrokeBuilder {
    private(set) var points: [CGPoint] = []
    private var startPoint: CGPoint?

    mutating func begin(at point: CGPoint) {
        points = [point]
        startPoint = point
    }

    mutating func append(_ point: CGPoint) {
        if let last = points.last, last == point { return }
        points.append(point)
    }

    mutating func replaceLast(with point: CGPoint) {
        guard !points.isEmpty else {
            points = [point]
            return
        }
        points[points.count - 1] = point
    }

    mutating func reset() {
        points = []
        startPoint = nil
    }

    func simplified(tolerance: CGFloat = 1.5) -> [CGPoint] {
        guard points.count > 2 else { return points }
        return ramerDouglas(points, epsilon: tolerance)
    }

    func makeStroke(
        layerID: UUID,
        strokeWidth: CGFloat,
        strokeColor: CodableColor,
        isClosed: Bool = false
    ) -> VectorStroke? {
        let finalPoints = simplified()
        guard finalPoints.count >= 2 else { return nil }
        return VectorStroke(
            layerID: layerID,
            points: finalPoints,
            strokeWidth: strokeWidth,
            strokeColor: strokeColor,
            isClosed: isClosed
        )
    }

    // MARK: - QuickShape

    func quickShapePoints(kind: QuickShapeKind) -> [CGPoint]? {
        guard let start = startPoint ?? points.first,
              let end = points.last,
              points.count >= 2 else { return nil }

        switch kind {
        case .line:
            return [start, end]
        case .rectangle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            return [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY)
            ]
        case .circle:
            let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let radius = hypot(end.x - start.x, end.y - start.y) / 2
            guard radius > 0 else { return nil }
            return circlePoints(center: center, radius: radius, segments: 64)
        case .polygon:
            return simplified()
        }
    }

    static func detectQuickShape(from points: [CGPoint]) -> QuickShapeKind? {
        guard points.count >= 2,
              let start = points.first,
              let end = points.last else { return nil }

        let dx = abs(end.x - start.x)
        let dy = abs(end.y - start.y)
        let bbox = pointsBoundingBox(points)
        let diagonal = hypot(bbox.width, bbox.height)
        guard diagonal > 4 else { return nil }

        let aspect = bbox.width > 0 ? bbox.height / bbox.width : 0
        let isRoughlyRectangular = aspect > 0.25 && aspect < 4
        let pathLength = polylineLength(points)
        let chord = hypot(end.x - start.x, end.y - start.y)

        if pathLength < chord * 1.15 {
            return .line
        }

        let closureDistance = hypot(end.x - start.x, end.y - start.y)
        let isClosedRoughly = closureDistance < diagonal * 0.2
        if isClosedRoughly {
            let circleRatio = pathLength / (2 * .pi * min(bbox.width, bbox.height) / 2)
            if circleRatio > 0.75 && circleRatio < 1.35 && abs(bbox.width - bbox.height) < diagonal * 0.35 {
                return .circle
            }
            if isRoughlyRectangular {
                return .rectangle
            }
        }

        return nil
    }

    private func circlePoints(center: CGPoint, radius: CGFloat, segments: Int) -> [CGPoint] {
        (0...segments).map { index in
            let angle = CGFloat(index) / CGFloat(segments) * 2 * .pi
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private func ramerDouglas(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var maxDistance: CGFloat = 0
        var index = 0
        let start = points.first!
        let end = points.last!
        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(points[i], lineStart: start, lineEnd: end)
            if d > maxDistance {
                maxDistance = d
                index = i
            }
        }
        if maxDistance > epsilon {
            let left = ramerDouglas(Array(points[0...index]), epsilon: epsilon)
            let right = ramerDouglas(Array(points[index...]), epsilon: epsilon)
            return left.dropLast() + right
        }
        return [start, end]
    }

    private func perpendicularDistance(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }
        let numerator = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        return numerator / sqrt(lengthSquared)
    }

    private static func pointsBoundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func polylineLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for i in 1..<points.count {
            length += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return length
    }
}
