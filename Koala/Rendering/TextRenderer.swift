//
//  TextRenderer.swift
//  Koala
//

import UIKit

/// Renders a `TextElement` as true vector glyph outlines in a filled
/// `CAShapeLayer`, so on-canvas text is a real shape that matches the exported
/// vectors exactly (same `TextOutline` path used for SVG/PDF/image export).
enum TextRenderer {
    static func makeLayer(
        for element: TextElement,
        viewport: ViewportTransform,
        opacity: CGFloat = 1
    ) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillRule = .nonZero
        layer.lineJoin = .round
        layer.lineCap = .round
        update(layer, for: element, viewport: viewport, opacity: opacity)
        return layer
    }

    static func update(
        _ layer: CAShapeLayer,
        for element: TextElement,
        viewport: ViewportTransform,
        opacity: CGFloat = 1
    ) {
        var transform = documentToView(viewport)
        let documentPath = TextOutline.path(for: element)
        layer.path = documentPath.copy(using: &transform) ?? documentPath
        layer.opacity = Float(opacity)
        if element.isOutline {
            layer.fillColor = nil
            layer.strokeColor = element.strokeCGColor
            layer.lineWidth = viewport.documentToView(distance: element.strokeWidth)
        } else {
            layer.fillColor = element.cgColor
            layer.strokeColor = nil
        }
    }

    /// Affine map from document space to on-screen view space.
    private static func documentToView(_ viewport: ViewportTransform) -> CGAffineTransform {
        CGAffineTransform(
            a: viewport.scale, b: 0, c: 0, d: viewport.scale,
            tx: viewport.translation.x, ty: viewport.translation.y
        )
    }
}
