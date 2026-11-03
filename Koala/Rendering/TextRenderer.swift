//
//  TextRenderer.swift
//  Koala
//

import UIKit

/// Renders a `TextElement` as true vector glyph outlines in a filled
/// `CAShapeLayer`, so on-canvas text is a real shape that matches the exported
/// vectors exactly (same `TextOutline` path used for SVG/PDF/image export).
enum TextRenderer {
    /// Glyph outlines are stored in `CanvasRenderSpace`. The canvas parent layer
    /// undoes that compression and applies the viewport.
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
        layer.path = CanvasRenderSpace.compress(TextOutline.path(for: element))
        layer.opacity = Float(opacity)
        if element.isOutline {
            layer.fillColor = nil
            layer.strokeColor = element.strokeCGColor
            layer.lineWidth = CanvasRenderSpace.compress(
                CanvasOverlayGeometry.displayStrokeDocumentWidth(
                    strokeWidth: element.strokeWidth,
                    scale: scale
                )
            )
        } else {
            layer.fillColor = element.cgColor
            layer.strokeColor = nil
            layer.lineWidth = 0
        }
    }
}
