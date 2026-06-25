//
//  PrintLayoutCoordinateSpace.swift
//  vectr
//

import CoreGraphics
import Foundation

enum PrintLayoutCoordinateSpace {
    static func boundingRect(for points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .null }
        var rect = CGRect.null
        for point in points {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    static func center(of points: [CGPoint]) -> CGPoint {
        let rect = boundingRect(for: points)
        guard !rect.isNull else { return .zero }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    static func transformedPoints(_ points: [CGPoint], transform: PrintStrokeTransform) -> [CGPoint] {
        guard !points.isEmpty else { return points }
        let pivot = center(of: points)
        let cosR = cos(transform.rotation)
        let sinR = sin(transform.rotation)
        return points.map { point in
            let dx = point.x - pivot.x
            let dy = point.y - pivot.y
            let rotated = CGPoint(
                x: pivot.x + dx * cosR - dy * sinR,
                y: pivot.y + dx * sinR + dy * cosR
            )
            return CGPoint(
                x: rotated.x + transform.translation.x,
                y: rotated.y + transform.translation.y
            )
        }
    }

    static func offsetPoints(_ points: [CGPoint], by offset: CGPoint) -> [CGPoint] {
        guard offset != .zero else { return points }
        return points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    }

    static func transformedStroke(_ stroke: VectorStroke, transform: PrintStrokeTransform) -> VectorStroke {
        var copy = stroke
        copy.points = transformedPoints(stroke.points, transform: transform)
        if !stroke.cutoutPoints.isEmpty {
            copy.cutoutPoints = stroke.cutoutPoints.map {
                transformedPoints($0, transform: transform)
            }
        }
        return copy
    }

    static func transformedStroke(
        _ stroke: VectorStroke,
        transform: PrintStrokeTransform,
        contentOffset: CGPoint
    ) -> VectorStroke {
        var copy = transformedStroke(stroke, transform: transform)
        if contentOffset != .zero {
            copy.points = offsetPoints(copy.points, by: contentOffset)
            copy.cutoutPoints = copy.cutoutPoints.map { offsetPoints($0, by: contentOffset) }
        }
        return copy
    }
}
