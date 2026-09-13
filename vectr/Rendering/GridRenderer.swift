//
//  GridRenderer.swift
//  vectr
//

import UIKit

enum GridRenderer {
    static let gridLineWidth: CGFloat = 1
    static let axisLineWidth: CGFloat = 1.5
    static let boundaryLineWidth: CGFloat = 1.5
    static let boundaryDash: [CGFloat] = [8, 6]

    /// Document-space geometry for the live canvas layers and the CPU export path.
    struct LayerPaths {
        /// Document region the grid lines were generated for (padded visible ∩ canvas).
        var coverage: CGRect
        /// One path per line rank (0 = major). Same-color lines are batched together.
        var rankPaths: [CGPath]
        var axisX: CGPath
        var axisY: CGPath
        var boundary: CGPath?
        var canvasRect: CGRect?
    }

    static func drawGrid(
        in context: CGContext,
        bounds: CGRect,
        viewport: ViewportTransform,
        grid: GridSettings,
        documentSettings: DocumentSettings,
        canvasSize: CGSize? = nil
    ) {
        let paths = makeLayerPaths(
            viewBounds: bounds,
            viewport: viewport,
            grid: grid,
            documentSettings: documentSettings,
            canvasSize: canvasSize,
            padScreens: 0
        )

        let inv = 1 / max(viewport.scale, .leastNonzeroMagnitude)

        context.saveGState()
        context.concatenate(viewport.affineTransform)
        if let canvasRect = paths.canvasRect {
            context.clip(to: canvasRect)
        }

        context.setLineWidth(gridLineWidth * inv)
        for (rank, path) in paths.rankPaths.enumerated() {
            guard !path.isEmpty else { continue }
            context.setStrokeColor(lineColor(rank: rank).cgColor)
            context.addPath(path)
            context.strokePath()
        }

        context.setLineWidth(axisLineWidth * inv)
        context.setStrokeColor(axisXColor.cgColor)
        context.addPath(paths.axisX)
        context.strokePath()
        context.setStrokeColor(axisYColor.cgColor)
        context.addPath(paths.axisY)
        context.strokePath()
        context.restoreGState()

        if let boundary = paths.boundary {
            context.saveGState()
            context.concatenate(viewport.affineTransform)
            context.setStrokeColor(boundaryColor.cgColor)
            context.setLineWidth(boundaryLineWidth * inv)
            context.setLineDash(phase: 0, lengths: boundaryDash.map { $0 * inv })
            context.addPath(boundary)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// Batched document-space paths covering the visible view (plus optional screen padding).
    static func makeLayerPaths(
        viewBounds: CGRect,
        viewport: ViewportTransform,
        grid: GridSettings,
        documentSettings: DocumentSettings,
        canvasSize: CGSize?,
        padScreens: CGFloat = 1
    ) -> LayerPaths {
        let canvas = canvasSize.flatMap { canvasRect(size: $0) }
        var coverage = documentRect(fromViewBounds: viewBounds, viewport: viewport)
        if padScreens > 0, viewport.scale > 0 {
            let padX = viewBounds.width / viewport.scale * padScreens
            let padY = viewBounds.height / viewport.scale * padScreens
            coverage = coverage.insetBy(dx: -padX, dy: -padY)
        }
        if let canvas {
            coverage = coverage.intersection(canvas)
        }

        let rankPaths: [CGPath]
        if coverage.isNull || coverage.isEmpty {
            rankPaths = []
        } else {
            rankPaths = makeRankPaths(
                coverage: coverage,
                grid: grid,
                documentSettings: documentSettings,
                scale: viewport.scale
            )
        }

        let axisSpan = canvas ?? (coverage.isNull || coverage.isEmpty ? nil : coverage)
        let axisX = CGMutablePath()
        let axisY = CGMutablePath()
        if let axisSpan, !axisSpan.isNull, !axisSpan.isEmpty {
            axisX.move(to: CGPoint(x: 0, y: axisSpan.minY))
            axisX.addLine(to: CGPoint(x: 0, y: axisSpan.maxY))
            axisY.move(to: CGPoint(x: axisSpan.minX, y: 0))
            axisY.addLine(to: CGPoint(x: axisSpan.maxX, y: 0))
        }

        return LayerPaths(
            coverage: coverage,
            rankPaths: rankPaths,
            axisX: axisX,
            axisY: axisY,
            boundary: canvas.map { CGPath(rect: $0, transform: nil) },
            canvasRect: canvas
        )
    }

    /// Visible document rectangle corresponding to `viewBounds` (no padding).
    static func documentRect(fromViewBounds bounds: CGRect, viewport: ViewportTransform) -> CGRect {
        let a = viewport.viewToDocument(bounds.origin)
        let b = viewport.viewToDocument(CGPoint(x: bounds.maxX, y: bounds.maxY))
        return CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    /// Canvas rectangle in document space, centered on the origin.
    static func canvasRect(size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Canvas rectangle (document space centered on origin) mapped into view space.
    static func canvasRectInView(viewport: ViewportTransform, canvasSize: CGSize) -> CGRect {
        guard let rect = canvasRect(size: canvasSize) else { return .null }
        let topLeft = viewport.documentToView(CGPoint(x: rect.minX, y: rect.minY))
        let bottomRight = viewport.documentToView(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    static func lineColor(rank: Int) -> UIColor {
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

    static var axisXColor: UIColor { UIColor.systemRed.withAlphaComponent(0.55) }
    static var axisYColor: UIColor { UIColor.systemBlue.withAlphaComponent(0.55) }
    static var boundaryColor: UIColor { UIColor.systemOrange.withAlphaComponent(0.45) }

    private static func makeRankPaths(
        coverage: CGRect,
        grid: GridSettings,
        documentSettings: DocumentSettings,
        scale: CGFloat
    ) -> [CGPath] {
        let major = grid.visualSpacing(for: documentSettings)
        guard major > 0 else { return [] }

        let subdiv = grid.visibleSubdivisions(for: documentSettings, scale: scale)
        let minor = major / CGFloat(subdiv)
        guard minor > 0 else { return [] }

        let rankCount = max(1, Int(log2(Double(subdiv)).rounded(.down)) + 1)
        var builders = (0..<rankCount).map { _ in CGMutablePath() }

        let startStepX = Int(floor(coverage.minX / minor))
        let endStepX = Int(ceil(coverage.maxX / minor))
        let startStepY = Int(floor(coverage.minY / minor))
        let endStepY = Int(ceil(coverage.maxY / minor))

        var stepX = startStepX
        while stepX <= endStepX {
            let rank = min(lineRank(step: stepX, subdiv: subdiv), rankCount - 1)
            let x = CGFloat(stepX) * minor
            builders[rank].move(to: CGPoint(x: x, y: coverage.minY))
            builders[rank].addLine(to: CGPoint(x: x, y: coverage.maxY))
            stepX += 1
        }

        var stepY = startStepY
        while stepY <= endStepY {
            let rank = min(lineRank(step: stepY, subdiv: subdiv), rankCount - 1)
            let y = CGFloat(stepY) * minor
            builders[rank].move(to: CGPoint(x: coverage.minX, y: y))
            builders[rank].addLine(to: CGPoint(x: coverage.maxX, y: y))
            stepY += 1
        }

        return builders
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
}
