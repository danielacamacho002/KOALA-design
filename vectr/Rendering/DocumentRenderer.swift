//
//  DocumentRenderer.swift
//  vectr
//

import CoreGraphics
import UIKit

enum DocumentRenderer {
    struct Options {
        var size: CGSize = CGSize(width: 400, height: 300)
        var backgroundColor: UIColor = .white
        var drawGrid: Bool = false
        var padding: CGFloat = 24
    }

    static func renderImage(document: VectrDocument, options: Options = Options()) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: options.size)
        return renderer.image { ctx in
            draw(document: document, in: ctx.cgContext, bounds: CGRect(origin: .zero, size: options.size), options: options)
        }
    }

    static func draw(
        document: VectrDocument,
        in context: CGContext,
        bounds: CGRect,
        options: Options = Options()
    ) {
        context.setFillColor(options.backgroundColor.cgColor)
        context.fill(bounds)

        var viewport = ViewportTransform()
        let points = allPoints(in: document)
        if points.isEmpty {
            viewport.centerOrigin(
                in: bounds.size,
                chrome: ViewportTransform.ChromeInsets(
                    left: options.padding,
                    right: options.padding,
                    top: options.padding,
                    bottom: options.padding
                )
            )
        } else {
            viewport.fitToPoints(
                points,
                in: bounds.size,
                chrome: ViewportTransform.ChromeInsets(
                    left: options.padding,
                    right: options.padding,
                    top: options.padding,
                    bottom: options.padding
                )
            )
        }

        if options.drawGrid {
            GridRenderer.drawGrid(
                in: context,
                bounds: bounds,
                viewport: viewport,
                grid: document.grid,
                documentSettings: document.settings,
                canvasExtent: document.settings.canvasExtent
            )
        }

        if let data = document.referenceImageData,
           let image = UIImage(data: data) {
            let frame = document.referenceImageFrame ?? defaultReferenceFrame(for: image, document: document)
            let viewFrame = CGRect(
                origin: viewport.documentToView(frame.origin),
                size: CGSize(
                    width: viewport.documentToView(distance: frame.width),
                    height: viewport.documentToView(distance: frame.height)
                )
            )
            image.draw(in: viewFrame)
        }

        for stroke in document.visibleStrokes() {
            let path = StrokeRenderer.path(for: stroke, viewport: viewport).cgPath
            context.addPath(path)
            context.setStrokeColor(strokeColor(for: stroke))
            context.setLineWidth(viewport.documentToView(distance: stroke.strokeWidth))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if stroke.isConstruction {
                context.setLineDash(phase: 0, lengths: [10, 6])
            }
            if stroke.isClosed, !stroke.isConstruction {
                context.setFillColor(UIColor.systemGray.withAlphaComponent(stroke.resolvedFillOpacity).cgColor)
                let fillMode: CGPathDrawingMode = stroke.cutoutPoints.isEmpty ? .fillStroke : .eoFillStroke
                context.drawPath(using: fillMode)
            } else {
                context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [])
        }

        let documentToView = CGAffineTransform(
            a: viewport.scale, b: 0, c: 0, d: viewport.scale,
            tx: viewport.translation.x, ty: viewport.translation.y
        )
        for element in document.visibleTextElements() {
            var transform = documentToView
            guard let viewPath = TextOutline.path(for: element).copy(using: &transform) else { continue }
            context.addPath(viewPath)
            if element.isOutline {
                context.setStrokeColor(element.strokeCGColor)
                context.setLineWidth(viewport.documentToView(distance: element.strokeWidth))
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.strokePath()
            } else {
                context.setFillColor(element.cgColor)
                context.fillPath()
            }
        }
    }

    static func boundingRect(for document: VectrDocument) -> CGRect {
        let points = allPoints(in: document)
        guard !points.isEmpty else {
            let extent = document.settings.canvasExtent
            return CGRect(x: -extent / 2, y: -extent / 2, width: extent, height: extent)
        }
        var rect = CGRect.null
        for point in points { rect = rect.union(CGRect(origin: point, size: .zero)) }
        return rect.insetBy(dx: -20, dy: -20)
    }

    private static func allPoints(in document: VectrDocument) -> [CGPoint] {
        var points = document.visibleStrokes().flatMap { ShapeGeometry.renderPoints(for: $0) }
        for element in document.visibleTextElements() {
            points.append(contentsOf: element.corners())
        }
        return points
    }

    private static func defaultReferenceFrame(for image: UIImage, document: VectrDocument) -> CGRect {
        let width = CGFloat(image.size.width)
        let height = CGFloat(image.size.height)
        return CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    }

    private static func strokeColor(for stroke: VectorStroke) -> CGColor {
        if stroke.isConstruction {
            return UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        }
        return stroke.cgColor
    }
}
