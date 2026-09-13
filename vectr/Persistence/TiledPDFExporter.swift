//
//  TiledPDFExporter.swift
//  vectr
//

import UIKit

enum TiledPDFExporter {
    /// Writes one PDF page per print-layout sheet.
    static func write(document: VectrDocument, to url: URL) throws {
        try write(snapshot: document.makeSnapshot(), to: url)
    }

    nonisolated static func write(snapshot: DocumentSnapshot, to url: URL) throws {
        let settings = snapshot.printLayout
        let pageSize = PrintPageGridEngine.pageSize(for: settings)
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let sheets = PrintPageGridEngine.sheets(for: settings)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            for sheet in sheets {
                context.beginPage(withBounds: pageRect, pageInfo: [:])
                let cgContext = context.cgContext

                cgContext.saveGState()
                cgContext.setFillColor(UIColor.white.cgColor)
                cgContext.fill(pageRect)

                cgContext.translateBy(x: -sheet.frame.origin.x, y: -sheet.frame.origin.y)

                let printable = PrintPageGridEngine.printableRect(for: sheet.frame, settings: settings)
                cgContext.clip(to: printable)

                drawPrintContent(snapshot: snapshot, in: cgContext)

                cgContext.resetClip()
                drawMarginGuide(settings.marginMode.printedStyle, in: printable, context: cgContext)
                drawPageNumber(sheet.id + 1, in: printable, context: cgContext)

                cgContext.restoreGState()
            }
        }
    }

    private nonisolated static func drawPrintContent(snapshot: DocumentSnapshot, in context: CGContext) {
        var viewport = ViewportTransform()
        viewport.scale = 1
        viewport.translation = .zero
        drawPrintStrokes(snapshot: snapshot, in: context, viewport: viewport)
        drawPrintText(snapshot: snapshot, in: context)
    }

    private nonisolated static func drawPrintStrokes(
        snapshot: DocumentSnapshot,
        in context: CGContext,
        viewport: ViewportTransform
    ) {
        for stroke in snapshot.printLayoutStrokes() {
            let transform = snapshot.effectivePrintTransform(for: stroke.id)
            context.saveGState()
            context.setAlpha(snapshot.opacity(forLayerID: stroke.layerID))
            if stroke.isClosed, !stroke.isConstruction {
                context.addPath(StrokeRenderer.path(for: stroke, viewport: viewport, pointTransform: transform).cgPath)
                context.setFillColor(UIColor.systemGray.withAlphaComponent(stroke.resolvedFillOpacity).cgColor)
                context.fillPath(using: stroke.cutoutPoints.isEmpty ? .winding : .evenOdd)
            }
            context.addPath(StrokeRenderer.outlinePath(for: stroke, viewport: viewport, pointTransform: transform).cgPath)
            context.setStrokeColor(strokeColor(for: stroke))
            context.setLineWidth(stroke.strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            if stroke.isConstruction {
                context.setLineDash(phase: 0, lengths: [10, 6])
            }
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            context.restoreGState()
        }
    }

    private nonisolated static func drawPrintText(snapshot: DocumentSnapshot, in context: CGContext) {
        for element in snapshot.visibleTextElements() {
            var transform = PrintLayoutCoordinateSpace.textPrintTransform(
                for: element,
                transform: snapshot.effectivePrintTransform(for: element.id)
            )
            guard let path = TextOutline.path(for: element).copy(using: &transform) else { continue }
            context.saveGState()
            context.setAlpha(snapshot.opacity(forLayerID: element.layerID))
            context.addPath(path)
            if element.isOutline {
                context.setStrokeColor(element.strokeCGColor)
                context.setLineWidth(element.strokeWidth)
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

    private nonisolated static func drawMarginGuide(_ style: PrintMarginGuideStyle, in printable: CGRect, context: CGContext) {
        guard style != .off else { return }
        context.saveGState()
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.75)
        if style == .dashed {
            context.setLineDash(phase: 0, lengths: [6, 4])
        }
        context.stroke(printable)
        context.setLineDash(phase: 0, lengths: [])
        context.restoreGState()
    }

    private nonisolated static func drawPageNumber(_ number: Int, in printable: CGRect, context: CGContext) {
        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        let size = text.size(withAttributes: attributes)
        let inset: CGFloat = 4
        let origin = CGPoint(
            x: printable.maxX - size.width - inset,
            y: printable.maxY - size.height - inset
        )
        text.draw(at: origin, withAttributes: attributes)
    }

    private nonisolated static func strokeColor(for stroke: VectorStroke) -> CGColor {
        if stroke.isConstruction {
            return UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        }
        return stroke.cgColor
    }
}
