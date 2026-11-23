//
//  LayerThumbnailRenderer.swift
//  Koala
//

import CoreGraphics
import UIKit

/// Renders small per-layer previews for the layers panel, zoomed to fit the
/// layer's own content rather than the whole canvas extent.
enum LayerThumbnailRenderer {
    static func render(
        document: KoalaDocument,
        layerID: UUID,
        size: CGSize
    ) -> UIImage? {
        let strokes = document.strokes(for: layerID).filter { !$0.isHiddenFromCanvas }
        let texts = document.textElements.filter { $0.layerID == layerID && !$0.isHidden }
        let images = document.referenceImages(for: layerID).filter { !$0.isHiddenFromCanvas }

        var points = strokes.flatMap { ShapeGeometry.renderPoints(for: $0) }
        for element in texts {
            points.append(contentsOf: element.corners())
        }
        for image in images {
            points.append(contentsOf: image.corners())
        }
        guard !points.isEmpty, size.width > 0, size.height > 0 else { return nil }

        var bounds = CGRect.null
        for point in points {
            bounds = bounds.union(CGRect(origin: point, size: .zero))
        }
        // Proportional padding so content doesn't touch the thumbnail edges.
        let pad = max(bounds.width, bounds.height, 1) * 0.1
        bounds = bounds.insetBy(dx: -pad, dy: -pad)

        var viewport = ViewportTransform()
        viewport.scale = min(size.width / bounds.width, size.height / bounds.height)
        viewport.translation = CGPoint(
            x: size.width / 2 - bounds.midX * viewport.scale,
            y: size.height / 2 - bounds.midY * viewport.scale
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let context = ctx.cgContext

            for item in images {
                guard let raster = UIImage(data: item.data) else { continue }
                DocumentRenderer.drawReferenceImage(
                    item,
                    image: raster,
                    in: context,
                    viewport: viewport,
                    alpha: document.opacity(forLayerID: item.layerID) * item.opacity
                )
            }

            for stroke in strokes {
                if stroke.isClosed, !stroke.isConstruction {
                    context.addPath(StrokeRenderer.path(for: stroke, viewport: viewport).cgPath)
                    context.setFillColor(stroke.resolvedFillCGColor)
                    context.fillPath(using: stroke.resolvedCGFillRule)
                }
                context.addPath(StrokeRenderer.outlinePath(for: stroke, viewport: viewport).cgPath)
                context.setStrokeColor(thumbnailStrokeColor(for: stroke))
                // Clamp so hairlines stay visible at thumbnail scale.
                context.setLineWidth(max(0.75, viewport.documentToView(distance: stroke.strokeWidth)))
                context.setLineCap(.round)
                context.setLineJoin(.round)
                if stroke.isConstruction {
                    context.setLineDash(phase: 0, lengths: [3, 2])
                }
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
            }

            let documentToView = CGAffineTransform(
                a: viewport.scale, b: 0, c: 0, d: viewport.scale,
                tx: viewport.translation.x, ty: viewport.translation.y
            )
            for element in texts {
                var transform = documentToView
                guard let viewPath = TextOutline.path(for: element).copy(using: &transform) else { continue }
                context.addPath(viewPath)
                if element.isOutline {
                    context.setStrokeColor(element.strokeCGColor)
                    context.setLineWidth(max(0.5, viewport.documentToView(distance: element.strokeWidth)))
                    context.setLineCap(.round)
                    context.setLineJoin(.round)
                    context.strokePath()
                } else {
                    context.setFillColor(element.cgColor)
                    context.fillPath()
                }
            }
        }
    }

    private static func thumbnailStrokeColor(for stroke: VectorStroke) -> CGColor {
        if stroke.isConstruction {
            return UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        }
        return stroke.cgColor
    }
}
