//
//  PrintLayoutCoordinateSpace.swift
//  Koala
//

import CoreGraphics
import Foundation

nonisolated enum PrintLayoutCoordinateSpace: Sendable {
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
        transformedPoints(points, around: center(of: points), transform: transform)
    }

    /// Mirror around `pivot` first, then rotate, then translate. `pivot` is shared
    /// by every contour of a stroke so an offset hole orbits with the outline.
    static func transformedPoints(
        _ points: [CGPoint],
        around pivot: CGPoint,
        transform: PrintStrokeTransform
    ) -> [CGPoint] {
        guard !points.isEmpty else { return points }
        let cosR = cos(transform.rotation)
        let sinR = sin(transform.rotation)
        let scaleX: CGFloat = transform.flipHorizontal ? -1 : 1
        let scaleY: CGFloat = transform.flipVertical ? -1 : 1
        return points.map { point in
            let dx = (point.x - pivot.x) * scaleX
            let dy = (point.y - pivot.y) * scaleY
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

    /// Flip and rotate a free offset (a Bezier handle). Translation does not apply:
    /// the anchor it hangs off already moved.
    static func transformedOffset(_ offset: CGPoint, transform: PrintStrokeTransform) -> CGPoint {
        let cosR = cos(transform.rotation)
        let sinR = sin(transform.rotation)
        let scaleX: CGFloat = transform.flipHorizontal ? -1 : 1
        let scaleY: CGFloat = transform.flipVertical ? -1 : 1
        let dx = offset.x * scaleX
        let dy = offset.y * scaleY
        return CGPoint(
            x: dx * cosR - dy * sinR,
            y: dx * sinR + dy * cosR
        )
    }

    static func offsetPoints(_ points: [CGPoint], by offset: CGPoint) -> [CGPoint] {
        guard offset != .zero else { return points }
        return points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    }

    static func transformedStroke(_ stroke: VectorStroke, transform: PrintStrokeTransform) -> VectorStroke {
        var copy = stroke
        let pivot = outlinePivot(for: stroke)
        copy.points = transformedPoints(stroke.points, around: pivot, transform: transform)
        if !stroke.cutoutPoints.isEmpty {
            copy.cutoutPoints = stroke.cutoutPoints.map {
                transformedPoints($0, around: pivot, transform: transform)
            }
        }
        if let handles = stroke.curveHandles {
            copy.curveHandles = handles.map { handle in
                CurveHandle(
                    inOffset: transformedOffset(handle.inOffset, transform: transform),
                    outOffset: transformedOffset(handle.outOffset, transform: transform)
                )
            }
        }
        return copy
    }

    /// Center of the visible outline. Arcs and curves store a few anchors whose
    /// box is smaller than the shape you see; rotating around that box swings
    /// the outline off the selection.
    private static func outlinePivot(for stroke: VectorStroke) -> CGPoint {
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        return center(of: rendered.isEmpty ? stroke.points : rendered)
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

    #if canImport(UIKit)
    // MARK: - Text elements

    /// Affine transform placing a text element on the print grid: rotates around
    /// the element's bounding-box center, then translates. Strokes rotate around
    /// the visible outline's center the same way. `transform.translation`
    /// should already include the global `contentOffset` when built from
    /// `effectivePrintTransform`.
    static func textPrintTransform(
        for element: TextElement,
        transform: PrintStrokeTransform
    ) -> CGAffineTransform {
        let bbox = element.boundingBox()
        let pivot = CGPoint(x: bbox.midX, y: bbox.midY)
        let scaleX: CGFloat = transform.flipHorizontal ? -1 : 1
        let scaleY: CGFloat = transform.flipVertical ? -1 : 1
        return CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .concatenating(CGAffineTransform(rotationAngle: transform.rotation))
            .concatenating(CGAffineTransform(
                translationX: pivot.x + transform.translation.x,
                y: pivot.y + transform.translation.y
            ))
    }

    /// The element's four corners after applying its print transform, in
    /// document space. Used for selection bounds and printable-area checks.
    static func transformedTextCorners(
        _ element: TextElement,
        transform: PrintStrokeTransform
    ) -> [CGPoint] {
        let affine = textPrintTransform(for: element, transform: transform)
        return element.corners().map { $0.applying(affine) }
    }
    #endif
}
