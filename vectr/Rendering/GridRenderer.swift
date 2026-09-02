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
        canvasSize: CGSize? = nil
    ) {
        // When a canvas rectangle is present, grid lines and axes are clipped to it so the
        // surrounding pasteboard stays clean. The boundary stroke is drawn afterwards, unclipped.
        let canvasViewRect: CGRect? = canvasSize.flatMap { size in
            guard size.width > 0, size.height > 0 else { return nil }
            return canvasRectInView(viewport: viewport, canvasSize: size)
        }

        context.saveGState()
        if let canvasViewRect {
            context.clip(to: canvasViewRect)
        }
        drawGridLines(in: context, bounds: bounds, viewport: viewport, grid: grid, documentSettings: documentSettings)
        drawAxes(in: context, bounds: bounds, viewport: viewport)
        context.restoreGState()

        if let canvasSize, canvasSize.width > 0, canvasSize.height > 0 {
            drawCanvasBoundary(in: context, viewport: viewport, canvasSize: canvasSize)
        }
    }

    private static func drawGridLines(
        in context: CGContext,
        bounds: CGRect,
        viewport: ViewportTransform,
        grid: GridSettings,
        documentSettings: DocumentSettings
    ) {
        let major = grid.visualSpacing(for: documentSettings)
        guard major > 0 else { return }

        // Largest power-of-2 subdivision that keeps minor lines from getting denser
        // than the on-screen pixel floor. This reveals finer lines as you zoom in,
        // and is the same value snapping uses so snap targets always match the grid.
        let subdiv = grid.visibleSubdivisions(for: documentSettings, scale: viewport.scale)
        let minor = major / CGFloat(subdiv)

        func strokeColor(forStepIndex step: Int) -> UIColor {
            lineColor(rank: lineRank(step: step, subdiv: subdiv))
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
    }

    /// 0 = major square, 1 = half, 2 = quarter, and so on. Coarser ranks stay
    /// stronger at every zoom so the big squares never flatten into a uniform field.
    private static func lineRank(step: Int, subdiv: Int) -> Int {
        var rank = 0
        var stride = max(1, subdiv)
        while stride > 1 && step % stride != 0 {
            stride /= 2
            rank += 1
        }
        return rank
    }

    private static func lineColor(rank: Int) -> UIColor {
        switch rank {
        case 0:
            return UIColor.label.withAlphaComponent(0.58)
        case 1:
            return UIColor.label.withAlphaComponent(0.38)
        case 2:
            return UIColor.separator.withAlphaComponent(0.32)
        case 3:
            return UIColor.separator.withAlphaComponent(0.22)
        default:
            return UIColor.separator.withAlphaComponent(0.16)
        }
    }

    /// Canvas rectangle (document space centered on origin) mapped into view space.
    private static func canvasRectInView(viewport: ViewportTransform, canvasSize: CGSize) -> CGRect {
        let halfWidth = canvasSize.width / 2
        let halfHeight = canvasSize.height / 2
        let topLeft = viewport.documentToView(CGPoint(x: -halfWidth, y: -halfHeight))
        let bottomRight = viewport.documentToView(CGPoint(x: halfWidth, y: halfHeight))
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    private static func drawCanvasBoundary(in context: CGContext, viewport: ViewportTransform, canvasSize: CGSize) {
        let viewRect = canvasRectInView(viewport: viewport, canvasSize: canvasSize)
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
