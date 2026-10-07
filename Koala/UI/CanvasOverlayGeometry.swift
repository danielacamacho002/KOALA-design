//
//  CanvasOverlayGeometry.swift
//  Koala
//

import CoreGraphics
import Foundation

/// Pure drag math behind `CanvasOverlayView`'s scale and marquee handles. The stroke,
/// reference-image, and text handles all resolve their factors here so the three paths
/// cannot drift apart.
nonisolated enum CanvasOverlayGeometry: Sendable {
    /// Guards every division against a degenerate (zero-area) bounding box.
    static let epsilon: CGFloat = 0.001

    /// Corner handles in the order the overlay draws and indexes them:
    /// top-left, top-right, bottom-right, bottom-left.
    static func cornerHandles(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }

    /// Radius captured when a uniform scale begins. Floored so a zero-area box cannot
    /// produce an infinite factor on the first drag sample.
    static func cornerDistance(from center: CGPoint, to corner: CGPoint) -> CGFloat {
        max(hypot(corner.x - center.x, corner.y - center.y), epsilon)
    }

    /// Scale factors for dragging `corner` to `dragPoint` about `center`. Uniform mode
    /// uses the radial distance ratio against the captured `originCornerDistance`; free
    /// mode scales each axis on its own and leaves an axis at 1 when the corner sits on
    /// that center line, where the ratio would be meaningless.
    static func scaleFactors(
        center: CGPoint,
        corner: CGPoint,
        dragPoint: CGPoint,
        uniform: Bool,
        originCornerDistance: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        if uniform {
            let distance = hypot(dragPoint.x - center.x, dragPoint.y - center.y)
            let factor = distance / max(originCornerDistance, epsilon)
            return (factor, factor)
        }
        let sx = abs(corner.x - center.x) > epsilon
            ? (dragPoint.x - center.x) / (corner.x - center.x)
            : 1
        let sy = abs(corner.y - center.y) > epsilon
            ? (dragPoint.y - center.y) / (corner.y - center.y)
            : 1
        return (sx, sy)
    }

    static func scaled(points: [CGPoint], about center: CGPoint, x sx: CGFloat, y sy: CGFloat) -> [CGPoint] {
        points.map { point in
            CGPoint(
                x: center.x + (point.x - center.x) * sx,
                y: center.y + (point.y - center.y) * sy
            )
        }
    }

    /// Curve handles are offsets from their anchor, so they scale without recentering.
    static func scaled(handles: [CurveHandle], x sx: CGFloat, y sy: CGFloat) -> [CurveHandle] {
        handles.map { handle in
            CurveHandle(
                inOffset: CGPoint(x: handle.inOffset.x * sx, y: handle.inOffset.y * sy),
                outOffset: CGPoint(x: handle.outOffset.x * sx, y: handle.outOffset.y * sy)
            )
        }
    }

    /// Reference-image frame after a corner drag. The frame stays centered and takes the
    /// magnitude of each factor, so dragging a handle past the center grows the image
    /// instead of inverting it.
    static func scaledFrame(origin: CGRect, center: CGPoint, x sx: CGFloat, y sy: CGFloat) -> CGRect {
        let width = abs(origin.width * sx)
        let height = abs(origin.height * sy)
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    /// Font size for a uniform text-scale drag, floored so text stays legible and selectable.
    static func scaledFontSize(origin: CGFloat, center: CGPoint, dragPoint: CGPoint, originDistance: CGFloat) -> CGFloat {
        let distance = hypot(dragPoint.x - center.x, dragPoint.y - center.y)
        return max(4, origin * (distance / max(originDistance, epsilon)))
    }

    /// Screen length of an anchor that measures `base` points at 1× zoom.
    /// Below 1× the mark stays `base` so zooming out does not shrink it.
    /// Above 1× it grows with the design through the full zoom range, matching stroke width.
    static func anchorScreenLength(base: CGFloat, scale: CGFloat) -> CGFloat {
        base * max(scale, 1)
    }

    /// Marquee rectangle from two document-space points. `nil` while the drag is still
    /// small enough to be a tap rather than a deliberate selection box.
    static func marqueeRect(from start: CGPoint, to current: CGPoint, minimumSpan: CGFloat = 0.5) -> CGRect? {
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
        guard rect.width > minimumSpan || rect.height > minimumSpan else { return nil }
        return rect
    }
}
