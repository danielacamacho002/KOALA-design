//
//  StrokeRenderer.swift
//  vectr
//

import UIKit

enum StrokeRenderer {
    static func makeShapeLayer(for stroke: VectorStroke, viewport: ViewportTransform) -> CAShapeLayer {
        makeShapeLayer(for: stroke, viewport: viewport, pointTransform: nil, opacity: 1)
    }

    static func updateShapeLayer(_ layer: CAShapeLayer, stroke: VectorStroke, viewport: ViewportTransform) {
        updateShapeLayer(layer, stroke: stroke, viewport: viewport, pointTransform: nil, opacity: 1)
    }

    static func path(for stroke: VectorStroke, viewport: ViewportTransform) -> UIBezierPath {
        path(for: stroke, viewport: viewport, pointTransform: nil)
    }

    static func path(
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
            closed: renderStroke.isClosed,
            viewport: viewport
        )

        for cutout in renderStroke.cutoutPoints {
            let holeStroke = VectorStroke(
                layerID: renderStroke.layerID,
                points: cutout,
                strokeWidth: renderStroke.strokeWidth,
                isClosed: true,
                shapeType: .circle
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
        opacity: CGFloat = 1
    ) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path(for: stroke, viewport: viewport, pointTransform: pointTransform).cgPath
        layer.strokeColor = strokeColor(for: stroke)
        layer.fillColor = fillColor(for: stroke)
        layer.lineWidth = viewport.documentToView(distance: stroke.strokeWidth)
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.contentsScale = UIScreen.main.scale
        layer.fillRule = usesEvenOddFill(stroke) ? .evenOdd : .nonZero
        layer.opacity = Float(opacity)
        if stroke.isConstruction {
            layer.lineDashPattern = [10, 6]
        }
        return layer
    }

    static func updateShapeLayer(
        _ layer: CAShapeLayer,
        stroke: VectorStroke,
        viewport: ViewportTransform,
        pointTransform: PrintStrokeTransform? = nil,
        opacity: CGFloat = 1
    ) {
        layer.path = path(for: stroke, viewport: viewport, pointTransform: pointTransform).cgPath
        layer.strokeColor = strokeColor(for: stroke)
        layer.fillColor = fillColor(for: stroke)
        layer.lineWidth = viewport.documentToView(distance: stroke.strokeWidth)
        layer.lineDashPattern = stroke.isConstruction ? [10, 6] : nil
        layer.fillRule = usesEvenOddFill(stroke) ? .evenOdd : .nonZero
        layer.opacity = Float(opacity)
    }

    static func transformedPath(for stroke: VectorStroke, viewport: ViewportTransform) -> UIBezierPath {
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

    private static func appendContour(
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

    private static func usesEvenOddFill(_ stroke: VectorStroke) -> Bool {
        stroke.isClosed && !stroke.cutoutPoints.isEmpty
    }

    private static func constructionPath(for stroke: VectorStroke, viewport: ViewportTransform) -> UIBezierPath {
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
        if stroke.isClosed, !stroke.isConstruction {
            return UIColor.systemGray.withAlphaComponent(stroke.resolvedFillOpacity).cgColor
        }
        return UIColor.clear.cgColor
    }

    private static func transformDocumentPath(_ documentPath: CGPath, viewport: ViewportTransform) -> UIBezierPath {
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
