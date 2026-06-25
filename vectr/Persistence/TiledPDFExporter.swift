//
//  TiledPDFExporter.swift
//  vectr
//

import UIKit

enum TiledPDFExporter {
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

                var viewport = ViewportTransform()
                viewport.scale = 1
                viewport.translation = .zero

                let printable = PrintPageGridEngine.printableRect(for: sheet.frame, settings: settings)
                cgContext.clip(to: printable)

                drawPrintStrokes(document: document, in: cgContext, viewport: viewport)

                cgContext.resetClip()
                for mark in document.registrationMarks where mark.isLocked {
                    if sheet.frame.contains(mark.position) {
                        RegistrationMarkRenderer.drawMark(mark, in: cgContext, viewport: viewport)
                    }
                }

                cgContext.restoreGState()
            }
        }
    }

    private static func drawPrintStrokes(
        document: VectrDocument,
        in context: CGContext,
        viewport: ViewportTransform
    ) {
        for stroke in document.visibleStrokes() {
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
                context.setFillColor(UIColor.systemGray.withAlphaComponent(0.25).cgColor)
                let fillMode: CGPathDrawingMode = stroke.cutoutPoints.isEmpty ? .fillStroke : .eoFillStroke
                context.drawPath(using: fillMode)
            } else {
                context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [])
        }
    }

    private static func strokeColor(for stroke: VectorStroke) -> CGColor {
        if stroke.isConstruction {
            return UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        }
        return stroke.cgColor
    }
}
