//
//  TextRenderer.swift
//  Koala
//

import UIKit

/// Renders a `TextElement` as true vector glyph outlines in a filled
/// `CAShapeLayer`, so on-canvas text is a real shape that matches the exported
/// vectors exactly (same `TextOutline` path used for SVG/PDF/image export).
enum TextRenderer {
    /// Glyph outlines stay in document space. The canvas parent layer carries the viewport.
    static func makeDocumentSpaceLayer(
        for element: TextElement,
        scale: CGFloat,
        opacity: CGFloat = 1
    ) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillRule = .nonZero
        layer.lineJoin = .round
        layer.lineCap = .round
        updateDocumentSpace(layer, for: element, scale: scale, opacity: opacity)
        return layer
    }

    static func updateDocumentSpace(
        _ layer: CAShapeLayer,
        for element: TextElement,
        scale: CGFloat,
        opacity: CGFloat = 1
    ) {
        layer.path = TextOutline.path(for: element)
        layer.opacity = Float(opacity)
        if element.isOutline {
            layer.fillColor = nil
            layer.strokeColor = element.strokeCGColor
            layer.lineWidth = CanvasOverlayGeometry.displayStrokeDocumentWidth(
                strokeWidth: element.strokeWidth,
                scale: scale
            )
        } else {
            layer.fillColor = element.cgColor
            layer.strokeColor = nil
            layer.lineWidth = 0
        }
    }
}
