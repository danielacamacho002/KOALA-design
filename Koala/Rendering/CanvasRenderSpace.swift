//
//  CanvasRenderSpace.swift
//  Koala
//

import CoreGraphics
import Foundation

/// On-canvas layers cannot store a floor plan in raw document points.
///
/// Core Animation drops a shape once its path is wider than a few thousand
/// points, even when a parent transform would scale that path down to the
/// screen. A 324 in room is already past that, and the widest allowed sheet
/// (1,000 in) is several times past it. Live layers therefore keep geometry in
/// a compressed space, and the parent transform undoes the compression before
/// applying the viewport. Document points, hit testing, and export stay as they
/// are.
nonisolated enum CanvasRenderSpace: Sendable {
    /// Largest span a shape layer is asked to store. Kept under the size where
    /// older iPads stop painting a path.
    static let safeSpan: CGFloat = 4_096

    /// Document-point span this compression is built for: the widest allowed sheet.
    static var maxDocumentSpan: CGFloat {
        DocumentSettings.maximumCanvasExtent(for: .inches)
    }

    /// Multiply document points by this to land in the safe layer space.
    static var geometryScale: CGFloat {
        safeSpan / max(maxDocumentSpan, 1)
    }

    /// Viewport that writes document geometry into the compressed layer space.
    static var pathViewport: ViewportTransform {
        var viewport = ViewportTransform()
        viewport.scale = geometryScale
        return viewport
    }

    /// Parent-layer transform: undo `geometryScale`, then apply the viewport.
    static func layerTransform(for viewport: ViewportTransform) -> CGAffineTransform {
        let scale = viewport.scale / geometryScale
        return CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: viewport.translation.x,
            ty: viewport.translation.y
        )
    }

    static func compress(_ distance: CGFloat) -> CGFloat {
        distance * geometryScale
    }

    static func compress(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * geometryScale, y: point.y * geometryScale)
    }

    static func compress(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * geometryScale,
            y: rect.origin.y * geometryScale,
            width: rect.size.width * geometryScale,
            height: rect.size.height * geometryScale
        )
    }

    static func compress(_ path: CGPath) -> CGPath {
        var transform = CGAffineTransform(scaleX: geometryScale, y: geometryScale)
        return path.copy(using: &transform) ?? path
    }
}
