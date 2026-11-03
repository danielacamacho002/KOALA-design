//
//  StrokeRenderer.swift
//  Koala
//

import UIKit

enum StrokeRenderer {
    static func makeShapeLayer(for stroke: VectorStroke, viewport: ViewportTransform) -> CAShapeLayer {
        makeShapeLayer(for: stroke, viewport: viewport, pointTransform: nil, opacity: 1)
    }

    static func updateShapeLayer(_ layer: CAShapeLayer, stroke: VectorStroke, viewport: ViewportTransform) {
        updateShapeLayer(layer, stroke: stroke, viewport: viewport, pointTransform: nil, opacity: 1)
    }

    nonisolated static func path(for stroke: VectorStroke, viewport: ViewportTransform) -> UIBezierPath {
        path(for: stroke, viewport: viewport, pointTransform: nil)
    }

    nonisolated static func path(
        for stroke: VectorStroke,
        viewport: ViewportTransform,
        pointTransform: PrintStrokeTransform?
    ) -> UIBezierPath {
        let renderStroke: VectorStroke
        if let pointTransform {
            renderStroke = PrintLayoutCoordinateSpace.transformedStroke(stroke, transform: pointTransform)
        } else {
            renderStroke = stroke
        }

        if renderStroke.isConstruction, renderStroke.points.count >= 2 {
            return constructionPath(for: renderStroke, viewport: viewport)
        }
        if renderStroke.hasAnyCornerFillets {
            return transformDocumentPath(
                FilletPathBuilder.path(for: renderStroke),
                viewport: viewport
            )
        }

        let path = UIBezierPath()
        appendContour(
            to: path,
            points: ShapeGeometry.renderPoints(for: renderStroke),
            closed: renderStroke.isClosed && renderStroke.shapeType != .arc,
            viewport: viewport
        )

        for cutout in renderStroke.cutoutPoints {
            let holeStroke = VectorStroke(
                layerID: renderStroke.layerID,
                points: cutout,
                strokeWidth: renderStroke.strokeWidth,
                isClosed: true,
                shapeType: .polyline
            )
            appendContour(
                to: path,
                points: ShapeGeometry.renderPoints(for: holeStroke),
                closed: true,
                viewport: viewport
            )
        }

        return path
    }

    static func makeShapeLayer(
        for stroke: VectorStroke,
        viewport: ViewportTransform,
        pointTransform: PrintStrokeTransform? = nil,
        opacity: CGFloat = 1,
        limitZoomedWidth: Bool = false
    ) -> CAShapeLayer {
        let layer = CAShapeLayer()
        configure(
            layer,
            stroke: stroke,
            viewport: viewport,
            pointTransform: pointTransform,
            opacity: opacity,
            limitZoomedWidth: limitZoomedWidth
        )
        return layer
    }

    static func updateShapeLayer(
        _ layer: CAShapeLayer,
        stroke: VectorStroke,
        viewport: ViewportTransform,
        pointTransform: PrintStrokeTransform? = nil,
        opacity: CGFloat = 1,
        limitZoomedWidth: Bool = false
    ) {
        configure(
            layer,
            stroke: stroke,
            viewport: viewport,
            pointTransform: pointTransform,
            opacity: opacity,
            limitZoomedWidth: limitZoomedWidth
        )
    }

    /// Viewport with scale 1 and no translation. Paths built with it are raw
    /// document points. On-canvas layers use `CanvasRenderSpace.pathViewport`
    /// instead: a floor-plan path in raw points is too large for Core Animation.
    static let documentSpaceViewport = ViewportTransform()

    static func rendersSeparateOutline(_ stroke: VectorStroke) -> Bool {
        hasCutEdges(stroke)
    }

    /// Screen-constant construction dashes, in `CanvasRenderSpace`, for a parent
    /// layer that undoes that compression and then applies `scale`.
    static func constructionDashPattern(scale: CGFloat) -> [NSNumber] {
        let inv = CanvasRenderSpace.geometryScale / max(scale, .leastNonzeroMagnitude)
        return [
            NSNumber(value: Double(10 * inv)),
            NSNumber(value: Double(6 * inv))
        ]
    }

    /// Updates stroke width and dashes on a layer whose path is already in
    /// `CanvasRenderSpace`. Does not replace the path.
    static func applyDocumentSpaceZoom(
        _ layer: CAShapeLayer,
        strokeWidth: CGFloat,
        isConstruction: Bool,
        rendersSeparateOutline: Bool,
        scale: CGFloat
    ) {
        let localWidth = CanvasRenderSpace.compress(
            CanvasOverlayGeometry.displayStrokeDocumentWidth(
                strokeWidth: strokeWidth,
                scale: scale
            )
        )
        if rendersSeparateOutline {
            if let outline = layer.sublayers?.first(where: { $0.name == outlineSublayerName }) as? CAShapeLayer,
               outline.lineWidth != localWidth {
                outline.lineWidth = localWidth
            }
        } else if layer.lineWidth != localWidth {
            layer.lineWidth = localWidth
        }
        guard isConstruction else { return }
        let dash = constructionDashPattern(scale: scale)
        if layer.lineDashPattern != dash {
            layer.lineDashPattern = dash
        }
    }

    private static let outlineSublayerName = "cutOutlineSublayer"

    /// Configures a stroke's shape layer. When the stroke carries cut edges
    /// (`openEdgeStarts`) the layer fills the full contour but draws no stroke; a child
    /// sublayer strokes only the retained (non-cut) edges, so the carved notch has no
    /// outline. Otherwise the layer fills and strokes the same path, as before.
    private static func configure(
        _ layer: CAShapeLayer,
        stroke: VectorStroke,
        viewport: ViewportTransform,
        pointTransform: PrintStrokeTransform?,
        opacity: CGFloat,
        limitZoomedWidth: Bool
    ) {
        let fillPath = path(for: stroke, viewport: viewport, pointTransform: pointTransform).cgPath
        let lineWidth = limitZoomedWidth
            ? CanvasOverlayGeometry.displayStrokeScreenWidth(
                strokeWidth: stroke.strokeWidth,
                scale: viewport.scale
            )
            : viewport.documentToView(distance: stroke.strokeWidth)
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.contentsScale = DisplayZoomCompensation.layerContentsScale
        layer.fillRule = stroke.resolvedCGFillRule == .evenOdd ? .evenOdd : .nonZero
        layer.opacity = Float(opacity)

        if hasCutEdges(stroke) {
            layer.path = fillPath
            layer.fillColor = fillColor(for: stroke)
            layer.strokeColor = UIColor.clear.cgColor
            layer.lineWidth = 0
            layer.lineDashPattern = nil

            let outline = outlineSublayer(for: layer)
            outline.path = outlinePath(for: stroke, viewport: viewport, pointTransform: pointTransform).cgPath
            outline.strokeColor = strokeColor(for: stroke)
            outline.fillColor = UIColor.clear.cgColor
            outline.lineWidth = lineWidth
            outline.lineCap = .round
            outline.lineJoin = .round
            outline.contentsScale = DisplayZoomCompensation.layerContentsScale
        } else {
            removeOutlineSublayer(from: layer)
            layer.path = fillPath
            layer.strokeColor = strokeColor(for: stroke)
            layer.fillColor = fillColor(for: stroke)
            layer.lineWidth = lineWidth
            layer.lineDashPattern = stroke.isConstruction ? [10, 6] : nil
        }
    }

    /// True when the stroke needs its fill and outline drawn from different paths:
    /// either it has cut edges on the outer contour, or it has punched (unstroked)
    /// holes. In both cases the outline must omit the cut geometry.
    private nonisolated static func hasCutEdges(_ stroke: VectorStroke) -> Bool {
        guard stroke.isClosed, !stroke.isConstruction else { return false }
        return (stroke.openEdgeStarts?.isEmpty == false) || (stroke.openCutoutIndices?.isEmpty == false)
    }

    private static func outlineSublayer(for layer: CAShapeLayer) -> CAShapeLayer {
        if let existing = layer.sublayers?.first(where: { $0.name == outlineSublayerName }) as? CAShapeLayer {
            return existing
        }
        let created = CAShapeLayer()
        created.name = outlineSublayerName
        layer.addSublayer(created)
        return created
    }

    private static func removeOutlineSublayer(from layer: CAShapeLayer) {
        layer.sublayers?
            .filter { $0.name == outlineSublayerName }
            .forEach { $0.removeFromSuperlayer() }
    }

    /// The path to *stroke* for a shape: identical to `path(for:)` unless the stroke
    /// has cut edges, in which case the outer contour is split into open subpaths that
    /// omit the cut edges (nested cutout contours remain stroked as closed loops).
    nonisolated static func outlinePath(
        for stroke: VectorStroke,
        viewport: ViewportTransform,
        pointTransform: PrintStrokeTransform? = nil
    ) -> UIBezierPath {
        guard hasCutEdges(stroke) else {
            return path(for: stroke, viewport: viewport, pointTransform: pointTransform)
        }
        let renderStroke: VectorStroke
        if let pointTransform {
            renderStroke = PrintLayoutCoordinateSpace.transformedStroke(stroke, transform: pointTransform)
        } else {
            renderStroke = stroke
        }

        let contour = ShapeGeometry.renderPoints(for: renderStroke)
        let count = contour.count
        let path = UIBezierPath()
        guard count >= 2 else { return path }
        let cut = Set(renderStroke.openEdgeStarts ?? [])

        if let firstCut = (0..<count).first(where: { cut.contains($0) }) {
            var subpathOpen = false
            // Walk all edges once, starting right after a cut edge so retained runs
            // never straddle the wrap-around seam.
            for step in 1...count {
                let edge = (firstCut + step) % count
                if cut.contains(edge) {
                    subpathOpen = false
                } else {
                    let start = contour[edge]
                    let end = contour[(edge + 1) % count]
                    if !subpathOpen {
                        path.move(to: viewport.documentToView(start))
                        subpathOpen = true
                    }
                    path.addLine(to: viewport.documentToView(end))
                }
            }
        } else {
            appendContour(
                to: path,
                points: contour,
                closed: renderStroke.isClosed && renderStroke.shapeType != .arc,
                viewport: viewport
            )
        }

        let unstroked = renderStroke.openCutoutIndices ?? []
        for (index, cutout) in renderStroke.cutoutPoints.enumerated() where !unstroked.contains(index) {
            let holeStroke = VectorStroke(
                layerID: renderStroke.layerID,
                points: cutout,
                strokeWidth: renderStroke.strokeWidth,
                isClosed: true,
                shapeType: .polyline
            )
            appendContour(
                to: path,
                points: ShapeGeometry.renderPoints(for: holeStroke),
                closed: true,
                viewport: viewport
            )
        }
        return path
    }

    nonisolated static func transformedPath(for stroke: VectorStroke, viewport: ViewportTransform) -> UIBezierPath {
        path(for: stroke, viewport: viewport)
    }

    static func livePath(
        points: [CGPoint],
        viewport: ViewportTransform,
        closed: Bool = false,
        cornerRadius: CGFloat = 0,
        isConstruction: Bool = false,
        shapeType: StrokeShapeType? = nil
    ) -> UIBezierPath {
        if isConstruction, points.count >= 2 {
            let stroke = VectorStroke(
                layerID: UUID(),
                points: points,
                strokeWidth: 1.5,
                isConstruction: true
            )
            return constructionPath(for: stroke, viewport: viewport)
        }
        if cornerRadius > 0, points.count >= 3 {
            return transformDocumentPath(
                FilletPathBuilder.path(points: points, cornerRadius: cornerRadius, closed: closed),
                viewport: viewport
            )
        }

        let contourPoints = contourPointsForLivePreview(
            points: points,
            closed: closed,
            shapeType: shapeType
        )

        let path = UIBezierPath()
        appendContour(to: path, points: contourPoints, closed: closed, viewport: viewport)
        return path
    }

    private static func contourPointsForLivePreview(
        points: [CGPoint],
        closed: Bool,
        shapeType: StrokeShapeType?
    ) -> [CGPoint] {
        guard closed, let shapeType else { return points }
        switch shapeType {
        case .circle, .ellipse:
            let stroke = VectorStroke(
                layerID: UUID(),
                points: points,
                strokeWidth: 1,
                isClosed: true,
                shapeType: shapeType
            )
            return ShapeGeometry.renderPoints(for: stroke)
        default:
            return points
        }
    }

    private nonisolated static func appendContour(
        to path: UIBezierPath,
        points: [CGPoint],
        closed: Bool,
        viewport: ViewportTransform
    ) {
        guard let first = points.first else { return }
        path.move(to: viewport.documentToView(first))
        for point in points.dropFirst() {
            path.addLine(to: viewport.documentToView(point))
        }
        if closed, points.count > 2 {
            path.close()
        }
    }

    private nonisolated static func constructionPath(for stroke: VectorStroke, viewport: ViewportTransform) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = stroke.points.first, let last = stroke.points.last else { return path }
        guard hypot(last.x - first.x, last.y - first.y) > 0.001 else { return path }
        path.move(to: viewport.documentToView(first))
        path.addLine(to: viewport.documentToView(last))
        return path
    }

    private static func strokeColor(for stroke: VectorStroke) -> CGColor {
        if stroke.isConstruction {
            return UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        }
        return stroke.cgColor
    }

    private static func fillColor(for stroke: VectorStroke) -> CGColor {
        stroke.resolvedFillCGColor
    }

    private nonisolated static func transformDocumentPath(_ documentPath: CGPath, viewport: ViewportTransform) -> UIBezierPath {
        let result = UIBezierPath()
        documentPath.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                result.move(to: viewport.documentToView(points[0]))
            case .addLineToPoint:
                result.addLine(to: viewport.documentToView(points[0]))
            case .addQuadCurveToPoint:
                result.addQuadCurve(
                    to: viewport.documentToView(points[1]),
                    controlPoint: viewport.documentToView(points[0])
                )
            case .addCurveToPoint:
                result.addCurve(
                    to: viewport.documentToView(points[2]),
                    controlPoint1: viewport.documentToView(points[0]),
                    controlPoint2: viewport.documentToView(points[1])
                )
            case .closeSubpath:
                result.close()
            @unknown default:
                break
            }
        }
        return result
    }
}
