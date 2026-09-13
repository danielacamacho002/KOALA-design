//
//  DocumentRenderer.swift
//  vectr
//

import CoreGraphics
import UIKit

enum DocumentRenderer {
    nonisolated struct Options: Sendable {
        var size: CGSize = CGSize(width: 400, height: 300)
        var drawGrid: Bool = false
        var padding: CGFloat = 24
    }

    static func renderImage(document: VectrDocument, options: Options = Options()) -> UIImage? {
        renderImage(snapshot: document.makeSnapshot(), options: options)
    }

    static func draw(
        document: VectrDocument,
        in context: CGContext,
        bounds: CGRect,
        options: Options = Options()
    ) {
        draw(snapshot: document.makeSnapshot(), in: context, bounds: bounds, options: options)
    }

    static func boundingRect(for document: VectrDocument) -> CGRect {
        boundingRect(for: document.makeSnapshot())
    }

    nonisolated static func renderImage(snapshot: DocumentSnapshot, options: Options = Options()) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: options.size)
        return renderer.image { ctx in
            draw(
                snapshot: snapshot,
                in: ctx.cgContext,
                bounds: CGRect(origin: .zero, size: options.size),
                options: options
            )
        }
    }

    nonisolated static func draw(
        snapshot: DocumentSnapshot,
        in context: CGContext,
        bounds: CGRect,
        options: Options = Options()
    ) {
        context.setFillColor(UIColor.white.cgColor)
        context.fill(bounds)

        var viewport = ViewportTransform()
        let points = allPoints(in: snapshot)
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

        if let data = snapshot.referenceImageData,
           let image = UIImage(data: data) {
            let frame = snapshot.referenceImageFrame ?? defaultReferenceFrame(for: image)
            let viewFrame = CGRect(
                origin: viewport.documentToView(frame.origin),
                size: CGSize(
                    width: viewport.documentToView(distance: frame.width),
                    height: viewport.documentToView(distance: frame.height)
                )
            )
            image.draw(in: viewFrame)
        }

        for stroke in snapshot.visibleStrokes() {
            context.saveGState()
            context.setAlpha(snapshot.opacity(forLayerID: stroke.layerID))
            if stroke.isClosed, !stroke.isConstruction {
                context.addPath(StrokeRenderer.path(for: stroke, viewport: viewport).cgPath)
                context.setFillColor(UIColor.systemGray.withAlphaComponent(stroke.resolvedFillOpacity).cgColor)
                context.fillPath(using: stroke.cutoutPoints.isEmpty ? .winding : .evenOdd)
            }
            context.addPath(StrokeRenderer.outlinePath(for: stroke, viewport: viewport).cgPath)
            context.setStrokeColor(strokeColor(for: stroke))
            context.setLineWidth(viewport.documentToView(distance: stroke.strokeWidth))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if stroke.isConstruction {
                context.setLineDash(phase: 0, lengths: [10, 6])
            }
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            context.restoreGState()
        }

        let documentToView = CGAffineTransform(
            a: viewport.scale, b: 0, c: 0, d: viewport.scale,
            tx: viewport.translation.x, ty: viewport.translation.y
        )
        for element in snapshot.visibleTextElements() {
            var transform = documentToView
            guard let viewPath = TextOutline.path(for: element).copy(using: &transform) else { continue }
            context.saveGState()
            context.setAlpha(snapshot.opacity(forLayerID: element.layerID))
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
            context.restoreGState()
        }
    }

    nonisolated static func boundingRect(for snapshot: DocumentSnapshot) -> CGRect {
        let points = allPoints(in: snapshot)
        guard !points.isEmpty else {
            let size = snapshot.settings.canvasSize
            return CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        }
        var rect = CGRect.null
        for point in points { rect = rect.union(CGRect(origin: point, size: .zero)) }
        let strokePad = snapshot.visibleStrokes().map(\.strokeWidth).max() ?? 0
        let textPad = snapshot.visibleTextElements().map { $0.isOutline ? $0.strokeWidth : 0 }.max() ?? 0
        return rect.insetBy(dx: -(20 + max(strokePad, textPad) / 2), dy: -(20 + max(strokePad, textPad) / 2))
    }

    private nonisolated static func allPoints(in snapshot: DocumentSnapshot) -> [CGPoint] {
        var points = snapshot.visibleStrokes().flatMap { ShapeGeometry.renderPoints(for: $0) }
        for element in snapshot.visibleTextElements() {
            points.append(contentsOf: element.corners())
        }
        return points
    }

    private nonisolated static func defaultReferenceFrame(for image: UIImage) -> CGRect {
        let width = CGFloat(image.size.width)
        let height = CGFloat(image.size.height)
        return CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    }

    private nonisolated static func strokeColor(for stroke: VectorStroke) -> CGColor {
        if stroke.isConstruction {
            return UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        }
        return stroke.cgColor
    }
}
