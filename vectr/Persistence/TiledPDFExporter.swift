//
//  TiledPDFExporter.swift
//  vectr
//

import UIKit

enum TiledPDFExporter {
    /// Writes one PDF page per print-layout sheet.
    static func write(document: VectrDocument, to url: URL) throws {
        let settings = document.printLayout
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

                // Map document coordinates onto this page.
                cgContext.translateBy(x: -sheet.frame.origin.x, y: -sheet.frame.origin.y)

                let printable = PrintPageGridEngine.printableRect(for: sheet.frame, settings: settings)
                cgContext.clip(to: printable)

                drawPrintContent(document: document, in: cgContext)

                cgContext.resetClip()
                drawMarginGuide(settings.marginMode.printedStyle, in: printable, context: cgContext)
                drawPageNumber(sheet.id + 1, in: printable, context: cgContext)

                cgContext.restoreGState()
            }
        }
    }

    private static func drawPrintContent(document: VectrDocument, in context: CGContext) {
        var viewport = ViewportTransform()
        viewport.scale = 1
        viewport.translation = .zero
        drawPrintStrokes(document: document, in: context, viewport: viewport)
        drawPrintText(document: document, in: context)
    }

    private static func drawPrintStrokes(
        document: VectrDocument,
        in context: CGContext,
        viewport: ViewportTransform
    ) {
        for stroke in document.printLayoutStrokes() {
            let transform = document.effectivePrintTransform(for: stroke.id)
            let path = StrokeRenderer.path(
                for: stroke,
                viewport: viewport,
                pointTransform: transform
            ).cgPath
            context.addPath(path)
            context.setStrokeColor(strokeColor(for: stroke))
            context.setLineWidth(stroke.strokeWidth)
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
    }

    /// Draws text as filled vector glyph outlines, positioned by each element's
    /// print transform (which includes the global `contentOffset`) so exports
    /// match the on-screen print layout.
    private static func drawPrintText(document: VectrDocument, in context: CGContext) {
        for element in document.visibleTextElements() {
            var transform = PrintLayoutCoordinateSpace.textPrintTransform(
                for: element,
                transform: document.effectivePrintTransform(for: element.id)
            )
            guard let path = TextOutline.path(for: element).copy(using: &transform) else { continue }
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
        }
    }

    /// Draws the printable-area outline as a trim/alignment guide when enabled,
    /// so the margin lines seen on screen also appear on the printed page.
    private static func drawMarginGuide(_ style: PrintMarginGuideStyle, in printable: CGRect, context: CGContext) {
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

    /// Draws the page number in the bottom-right corner of the printable area so
    /// it lands inside what the printer can actually render.
    private static func drawPageNumber(_ number: Int, in printable: CGRect, context: CGContext) {
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

    private static func strokeColor(for stroke: VectorStroke) -> CGColor {
        if stroke.isConstruction {
            return UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        }
        return stroke.cgColor
    }
}
