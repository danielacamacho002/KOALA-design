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
        guard major > 0 else {
            if let extent = canvasExtent, extent > 0 {
                drawCanvasExtent(in: context, viewport: viewport, extent: extent)
            }
            drawAxes(in: context, bounds: bounds, viewport: viewport)
            return
        }

        let snapDiv = max(1, grid.snapSubdivisions)

        // Largest power-of-2 subdivision that keeps minor lines from getting denser
        // than the on-screen pixel floor. This reveals finer lines as you zoom in,
        // and is the same value snapping uses so snap targets always match the grid.
        let subdiv = grid.visibleSubdivisions(for: documentSettings, scale: viewport.scale)
        let minor = major / CGFloat(subdiv)

        let majorColor = UIColor.separator
        let snapColor = UIColor.separator.withAlphaComponent(0.5)
        let fineColor = UIColor.separator.withAlphaComponent(0.22)

        // A line is a snap-increment line when the current subdivision has reached
        // the snap granularity, so the user can see exactly where points will land.
        func strokeColor(forStepIndex step: Int) -> UIColor {
            if step % subdiv == 0 { return majorColor }
            if subdiv >= snapDiv, snapDiv > 1, (step * snapDiv) % subdiv == 0 { return snapColor }
            return fineColor
        }

        let topLeft = viewport.viewToDocument(bounds.origin)
        let bottomRight = viewport.viewToDocument(CGPoint(x: bounds.maxX, y: bounds.maxY))

        let startStepX = Int(floor(topLeft.x / minor))
        let endStepX = Int(ceil(bottomRight.x / minor))
        let startStepY = Int(floor(topLeft.y / minor))
        let endStepY = Int(ceil(bottomRight.y / minor))

        context.saveGState()
        context.setLineWidth(1)

        var stepX = startStepX
        while stepX <= endStepX {
            context.setStrokeColor(strokeColor(forStepIndex: stepX).cgColor)
            let viewX = viewport.documentToView(CGPoint(x: CGFloat(stepX) * minor, y: 0)).x
            context.move(to: CGPoint(x: viewX, y: bounds.minY))
            context.addLine(to: CGPoint(x: viewX, y: bounds.maxY))
            context.strokePath()
            stepX += 1
        }

        var stepY = startStepY
        while stepY <= endStepY {
            context.setStrokeColor(strokeColor(forStepIndex: stepY).cgColor)
            let viewY = viewport.documentToView(CGPoint(x: 0, y: CGFloat(stepY) * minor)).y
            context.move(to: CGPoint(x: bounds.minX, y: viewY))
            context.addLine(to: CGPoint(x: bounds.maxX, y: viewY))
            context.strokePath()
            stepY += 1
        }

        context.restoreGState()

        if let extent = canvasExtent, extent > 0 {
            drawCanvasExtent(in: context, viewport: viewport, extent: extent)
        }

        drawAxes(in: context, bounds: bounds, viewport: viewport)
    }

    private static func drawCanvasExtent(in context: CGContext, viewport: ViewportTransform, extent: CGFloat) {
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
