//
//  ViewportTransform.swift
//  Koala
//

import CoreGraphics
import Foundation

nonisolated struct ViewportTransform: Codable, Equatable, Sendable {
    var scale: CGFloat = 1
    var translation: CGPoint = .zero

    static let minScale: CGFloat = 0.02
    static let maxScale: CGFloat = 24

    mutating func clampScale() {
        scale = min(Self.maxScale, max(Self.minScale, scale))
    }

    mutating func zoom(to newScale: CGFloat, anchorViewPoint: CGPoint) {
        let docBefore = viewToDocument(anchorViewPoint)
        scale = min(Self.maxScale, max(Self.minScale, newScale))
        translation = CGPoint(
            x: anchorViewPoint.x - docBefore.x * scale,
            y: anchorViewPoint.y - docBefore.y * scale
        )
    }

    /// Fraction of the fit-to-view scale allowed as the zoom-out floor. Lower values let
    /// you zoom further out, leaving more pasteboard around the canvas.
    static let canvasFitPadding: CGFloat = 0.4

    /// Smallest scale that still shows the whole canvas within the view (with a little margin).
    static func minimumScaleToFitCanvas(in viewSize: CGSize, canvasSize: CGSize) -> CGFloat {
        guard canvasSize.width > 0, canvasSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return minScale }
        let fitScale = min(viewSize.width / canvasSize.width, viewSize.height / canvasSize.height)
        return max(minScale, fitScale * canvasFitPadding)
    }

    /// Constrains the zoom level to the supported range. Panning is intentionally left free so the
    /// canvas can be dragged anywhere on (or off) screen, behaving identically when zoomed in or
    /// out; the two-finger gesture is what naturally limits how far it travels.
    ///
    /// When `anchorViewPoint` is set and the scale actually changes, translation is rebuilt so
    /// that same view point stays over the same document point. Raising the scale alone would
    /// slide content toward the bottom-right wherever the document point is far from the origin
    /// (the print page grid).
    mutating func clampToCanvasSize(
        in viewSize: CGSize,
        canvasSize: CGSize,
        preserving anchorViewPoint: CGPoint? = nil
    ) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return }

        let minAllowedScale = Self.minimumScaleToFitCanvas(in: viewSize, canvasSize: canvasSize)
        let clamped = min(Self.maxScale, max(scale, minAllowedScale))
        guard clamped != scale else { return }

        if let anchorViewPoint {
            let docAtAnchor = viewToDocument(anchorViewPoint)
            scale = clamped
            translation = CGPoint(
                x: anchorViewPoint.x - docAtAnchor.x * scale,
                y: anchorViewPoint.y - docAtAnchor.y * scale
            )
        } else {
            scale = clamped
        }
    }

    /// Shifts translation so the same document point stays at the view center after a resize.
    /// Used during device rotation so the sheet does not sit in the old landscape position
    /// and then slide into portrait a beat later.
    mutating func preserveCenter(from oldSize: CGSize, to newSize: CGSize) {
        guard oldSize.width > 0, oldSize.height > 0,
              newSize.width > 0, newSize.height > 0 else { return }
        translation.x += (newSize.width - oldSize.width) / 2
        translation.y += (newSize.height - oldSize.height) / 2
    }

    func viewToDocument(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - translation.x) / scale,
            y: (point.y - translation.y) / scale
        )
    }

    func documentToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + translation.x,
            y: point.y * scale + translation.y
        )
    }

    /// Affine map from document space into view space: `p * scale + translation`.
    var affineTransform: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: translation.x, ty: translation.y)
    }

    func viewToDocument(distance: CGFloat) -> CGFloat {
        distance / scale
    }

    func documentToView(distance: CGFloat) -> CGFloat {
        distance * scale
    }

    nonisolated struct ChromeInsets: Equatable, Sendable {
        var left: CGFloat = 280
        var right: CGFloat = 120
        var top: CGFloat = 56
        var bottom: CGFloat = 24
    }

    /// Frames document points in the drawable canvas area.
    mutating func fitToPoints(
        _ points: [CGPoint],
        in viewSize: CGSize,
        margin: CGFloat = 48,
        chrome: ChromeInsets = ChromeInsets(),
        minScale: CGFloat = 2
    ) {
        let leftInset = chrome.left
        let topInset = chrome.top
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let bounds = Self.boundingRect(for: points)
        let drawableWidth = max(120, viewSize.width - leftInset - chrome.right - margin)
        let drawableHeight = max(120, viewSize.height - topInset - chrome.bottom - margin)

        let scaleX = drawableWidth / max(bounds.width, 1)
        let scaleY = drawableHeight / max(bounds.height, 1)
        scale = min(scaleX, scaleY, Self.maxScale)
        scale = max(scale, max(minScale, Self.minScale))

        let documentCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let viewCenter = CGPoint(
            x: leftInset + margin + (drawableWidth - margin) / 2,
            y: topInset + margin + (drawableHeight - margin) / 2
        )
        translation = CGPoint(
            x: viewCenter.x - documentCenter.x * scale,
            y: viewCenter.y - documentCenter.y * scale
        )
    }

    /// Places document origin in the center of the drawable canvas when starting a command.
    mutating func centerOrigin(in viewSize: CGSize, chrome: ChromeInsets = ChromeInsets()) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        scale = 5
        let drawableWidth = viewSize.width - chrome.left - chrome.right
        let drawableHeight = viewSize.height - chrome.top - chrome.bottom
        let viewCenter = CGPoint(
            x: chrome.left + drawableWidth / 2,
            y: chrome.top + drawableHeight / 2
        )
        translation = viewCenter
    }

    /// Pans so document origin (0, 0) sits at the geometric center of the view bounds, preserving zoom.
    mutating func centerOnAxisOrigin(in viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        translation = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
    }

    /// Frames the whole canvas sheet inside `visibleRect` and places the document origin
    /// (the X/Y axis intersection) on the midpoint of that rect.
    ///
    /// `visibleRect` is in canvas-view coordinates — the area of the UIView that is not
    /// covered by the top toolbar. `fillFactor` scales the fit: 1.0 fits the sheet exactly,
    /// values above 1.0 zoom in so the sheet overflows the visible area.
    mutating func frameCanvasInDrawableArea(
        canvasSize: CGSize,
        visibleRect: CGRect,
        fillFactor: CGFloat = 1.2
    ) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              visibleRect.width > 0, visibleRect.height > 0 else { return }
        let fit = min(visibleRect.width / canvasSize.width, visibleRect.height / canvasSize.height) * fillFactor
        scale = min(Self.maxScale, max(Self.minScale, fit))
        translation = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
    }

    /// Default view for a new empty project: reasonable zoom with origin centered.
    mutating func resetToDefaultView(in viewSize: CGSize, defaultScale: CGFloat = 1) {
        scale = defaultScale
        centerOnAxisOrigin(in: viewSize)
    }

    static func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    func interpolated(toward target: ViewportTransform, t: CGFloat) -> ViewportTransform {
        ViewportTransform(
            scale: scale + (target.scale - scale) * t,
            translation: CGPoint(
                x: translation.x + (target.translation.x - translation.x) * t,
                y: translation.y + (target.translation.y - translation.y) * t
            )
        )
    }

    private static func boundingRect(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        if points.count == 1 {
            return CGRect(x: first.x - 10, y: first.y - 10, width: 20, height: 20)
        }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        let pad = max(16, max(rect.width, rect.height) * 0.35)
        return rect.insetBy(dx: -pad, dy: -pad)
    }
}
