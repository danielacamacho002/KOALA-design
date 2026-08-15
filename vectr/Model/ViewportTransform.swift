//
//  ViewportTransform.swift
//  vectr
//

import CoreGraphics
import Foundation

struct ViewportTransform: Codable, Equatable {
    var scale: CGFloat = 1
    var translation: CGPoint = .zero

    static let minScale: CGFloat = 0.02
    static let maxScale: CGFloat = 8

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

    /// Constrains pan/zoom so the canvas stays framed: you can zoom out until the whole
    /// canvas is visible (surrounded by pasteboard) and can't scroll the canvas off-screen.
    mutating func clampToCanvasSize(in viewSize: CGSize, canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return }

        let minAllowedScale = Self.minimumScaleToFitCanvas(in: viewSize, canvasSize: canvasSize)
        scale = min(Self.maxScale, max(scale, minAllowedScale))

        let halfWidth = canvasSize.width / 2
        let halfHeight = canvasSize.height / 2

        // The two bounds swap roles depending on whether the scaled canvas is larger
        // (zoomed in: clamp so you can't pan past the canvas edges) or smaller than the
        // view (zoomed out: clamp so the canvas stays fully on-screen within the pasteboard).
        let boundA_X = viewSize.width - halfWidth * scale
        let boundB_X = halfWidth * scale
        translation.x = min(max(translation.x, min(boundA_X, boundB_X)), max(boundA_X, boundB_X))

        let boundA_Y = viewSize.height - halfHeight * scale
        let boundB_Y = halfHeight * scale
        translation.y = min(max(translation.y, min(boundA_Y, boundB_Y)), max(boundA_Y, boundB_Y))
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

    func viewToDocument(distance: CGFloat) -> CGFloat {
        distance / scale
    }

    func documentToView(distance: CGFloat) -> CGFloat {
        distance * scale
    }

    struct ChromeInsets: Equatable {
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
        chrome: ChromeInsets = ChromeInsets()
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
        scale = max(scale, 2)

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

    /// Frames the whole canvas sheet inside the visible drawing area and centers the document
    /// origin (and therefore the sheet, which is symmetric about the origin) in it.
    ///
    /// `viewSize` is the `GeometryReader` size, which is already reduced by the top toolbar
    /// (applied via `safeAreaInset`). The canvas surface itself uses `.ignoresSafeArea()`, so it
    /// draws the full window height with its origin at the very top — `topToolbar` above the
    /// visible area. That is why the vertical center adds `topToolbar`: the visible region is
    /// `[topToolbar, topToolbar + viewSize.height]` in surface coordinates. Horizontally the
    /// surface is not inset, so only the `leadingPanel` overlay needs to be cleared.
    ///
    /// `fillFactor` scales the fit: 1.0 fits the sheet exactly in the visible area, values above
    /// 1.0 zoom in so the sheet overflows it (more zoomed-in), below 1.0 leave a gap.
    mutating func frameCanvasInDrawableArea(
        canvasSize: CGSize,
        in viewSize: CGSize,
        leadingPanel: CGFloat,
        topToolbar: CGFloat,
        fillFactor: CGFloat = 1.2
    ) {
        guard canvasSize.width > 0, canvasSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return }
        let drawableWidth = max(1, viewSize.width - leadingPanel)
        let drawableHeight = max(1, viewSize.height)
        let fit = min(drawableWidth / canvasSize.width, drawableHeight / canvasSize.height) * fillFactor
        scale = min(Self.maxScale, max(Self.minScale, fit))
        translation = CGPoint(
            x: (viewSize.width + leadingPanel) / 2,
            y: viewSize.height / 2 + topToolbar
        )
    }

    /// Default view for a new empty project: reasonable zoom with origin centered.
    mutating func resetToDefaultView(in viewSize: CGSize, defaultScale: CGFloat = 1) {
        scale = defaultScale
        centerOnAxisOrigin(in: viewSize)
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
