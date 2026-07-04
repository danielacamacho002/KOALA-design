//
//  TextRenderer.swift
//  vectr
//

import UIKit

/// Renders a `TextElement` as a crisp `CATextLayer` in view space.
enum TextRenderer {
    static func makeLayer(for element: TextElement, viewport: ViewportTransform) -> CATextLayer {
        let layer = CATextLayer()
        layer.contentsScale = UIScreen.main.scale
        layer.isWrapped = true
        layer.alignmentMode = .left
        layer.truncationMode = .none
        update(layer, for: element, viewport: viewport)
        return layer
    }

    static func update(_ layer: CATextLayer, for element: TextElement, viewport: ViewportTransform) {
        let scale = viewport.scale
        let font = element.fontRef.uiFont(size: element.fontSize * scale)
        let displayText = element.text.isEmpty ? " " : element.text
        layer.string = NSAttributedString(
            string: displayText,
            attributes: [
                .font: font,
                .foregroundColor: element.cgColor
            ]
        )

        let documentSize = element.textSize()
        let viewSize = CGSize(
            width: max(1, documentSize.width * scale),
            height: max(1, documentSize.height * scale)
        )
        let origin = viewport.documentToView(element.position)

        // Reset any rotation before repositioning; frame is undefined under a transform.
        layer.transform = CATransform3DIdentity
        layer.frame = CGRect(origin: origin, size: viewSize)
        if element.rotation != 0 {
            layer.transform = CATransform3DMakeRotation(element.rotation, 0, 0, 1)
        }
    }
}
