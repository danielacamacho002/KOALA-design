//
//  GridRenderer.swift
//  vectr
//

import UIKit

enum GridRenderer {
    static func drawGrid(
        in context: CGContext,
        bounds: CGRect,
        viewport: ViewportTransform,
        grid: GridSettings,
        documentSettings: DocumentSettings,
        canvasExtent: CGFloat? = nil
    ) {
        let major = grid.visualSpacing(for: documentSettings)
        let minor = grid.minorSpacing(for: documentSettings)

        let topLeft = viewport.viewToDocument(bounds.origin)
        let bottomRight = viewport.viewToDocument(CGPoint(x: bounds.maxX, y: bounds.maxY))

        let startX = floor(topLeft.x / minor) * minor
        let endX = ceil(bottomRight.x / minor) * minor
        let startY = floor(topLeft.y / minor) * minor
        let endY = ceil(bottomRight.y / minor) * minor

        context.saveGState()
        context.setLineWidth(1)

        var x = startX
        while x <= endX {
            let isMajor = abs((x / major).rounded() * major - x) < 0.01
            context.setStrokeColor((isMajor ? UIColor.separator : UIColor.separator.withAlphaComponent(0.35)).cgColor)
            let viewX = viewport.documentToView(CGPoint(x: x, y: 0)).x
            context.move(to: CGPoint(x: viewX, y: bounds.minY))
            context.addLine(to: CGPoint(x: viewX, y: bounds.maxY))
            context.strokePath()
            x += minor
        }

        var y = startY
        while y <= endY {
            let isMajor = abs((y / major).rounded() * major - y) < 0.01
            context.setStrokeColor((isMajor ? UIColor.separator : UIColor.separator.withAlphaComponent(0.35)).cgColor)
            let viewY = viewport.documentToView(CGPoint(x: 0, y: y)).y
            context.move(to: CGPoint(x: bounds.minX, y: viewY))
            context.addLine(to: CGPoint(x: bounds.maxX, y: viewY))
            context.strokePath()
            y += minor
        }

        context.restoreGState()

        if let extent = canvasExtent, extent > 0 {
            let half = extent / 2
            let canvasRect = CGRect(x: -half, y: -half, width: extent, height: extent)
            let topLeft = viewport.documentToView(canvasRect.origin)
            let bottomRight = viewport.documentToView(CGPoint(x: canvasRect.maxX, y: canvasRect.maxY))
            let viewRect = CGRect(
                x: topLeft.x,
                y: topLeft.y,
                width: bottomRight.x - topLeft.x,
                height: bottomRight.y - topLeft.y
            )
            context.saveGState()
            context.setStrokeColor(UIColor.systemOrange.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [8, 6])
            context.stroke(viewRect)
            context.restoreGState()
        }

        drawAxes(in: context, bounds: bounds, viewport: viewport)
    }

    private static func drawAxes(in context: CGContext, bounds: CGRect, viewport: ViewportTransform) {
        let origin = viewport.documentToView(.zero)
        context.saveGState()
        context.setLineWidth(1.5)

        context.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.55).cgColor)
        context.move(to: CGPoint(x: origin.x, y: bounds.minY))
        context.addLine(to: CGPoint(x: origin.x, y: bounds.maxY))
        context.strokePath()

        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.55).cgColor)
        context.move(to: CGPoint(x: bounds.minX, y: origin.y))
        context.addLine(to: CGPoint(x: bounds.maxX, y: origin.y))
        context.strokePath()

        context.restoreGState()
    }
}
