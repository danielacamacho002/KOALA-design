//
//  ViewportTransform.swift
//  vectr
//

import CoreGraphics
import Foundation

struct ViewportTransform: Codable, Equatable {
    var scale: CGFloat = 1
    var translation: CGPoint = .zero

    static let minScale: CGFloat = 0.1
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

    /// Constrains pan/zoom so the canvas extent acts as a hard viewport boundary.
    mutating func clampToCanvasExtent(in viewSize: CGSize, canvasExtent: CGFloat) {
        guard canvasExtent > 0, viewSize.width > 0, viewSize.height > 0 else { return }

        let minScaleToFillView = max(
            viewSize.width / canvasExtent,
            viewSize.height / canvasExtent
        )
        scale = min(Self.maxScale, max(scale, minScaleToFillView))

        let half = canvasExtent / 2

        let minTranslationX = viewSize.width - half * scale
        let maxTranslationX = half * scale
        if minTranslationX <= maxTranslationX {
            translation.x = min(max(translation.x, minTranslationX), maxTranslationX)
        } else {
            translation.x = viewSize.width / 2
        }

        let minTranslationY = viewSize.height - half * scale
        let maxTranslationY = half * scale
        if minTranslationY <= maxTranslationY {
            translation.y = min(max(translation.y, minTranslationY), maxTranslationY)
        } else {
            translation.y = viewSize.height / 2
        }
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

    /// Default view for a new empty project: reasonable zoom with origin centered.
    mutating func resetToDefaultView(in viewSize: CGSize, defaultScale: CGFloat = 5) {
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
