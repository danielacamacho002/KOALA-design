//
//  PrintBorderRenderer.swift
//  Koala
//

import CoreGraphics
import UIKit

enum PrintBorderRenderer {
    static let borderColor = UIColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0)

    // MARK: - Per-sheet geometry

    static func printableRect(for sheetFrame: CGRect, margin: CGFloat) -> CGRect {
        sheetFrame.insetBy(dx: margin, dy: margin)
    }

    static func printableRect(for sheet: PrintPageGridEngine.Sheet, settings: PrintLayoutSettings) -> CGRect {
        printableRect(for: sheet.frame, margin: settings.printableMargin)
    }

    static func perSheetPrintableRects(settings: PrintLayoutSettings) -> [CGRect] {
        PrintPageGridEngine.sheets(for: settings).map { printableRect(for: $0, settings: settings) }
    }

    static func viewRect(for documentRect: CGRect, viewport: ViewportTransform) -> CGRect {
        CGRect(
            origin: viewport.documentToView(documentRect.origin),
            size: CGSize(
                width: viewport.documentToView(distance: documentRect.width),
                height: viewport.documentToView(distance: documentRect.height)
            )
        )
    }

    // MARK: - Dashed printable border (one per page)

    /// One dashed printable-area outline per page. Because pages are laid out
    /// edge-to-edge, each page's printable rect is separated from its neighbours
    /// by the combined margins, so borders never overlap or double up.
    static func combinedBorderPath(settings: PrintLayoutSettings, viewport: ViewportTransform) -> CGPath {
        let path = UIBezierPath()
        for sheet in PrintPageGridEngine.sheets(for: settings) {
            let printable = printableRect(for: sheet, settings: settings)
            path.append(UIBezierPath(rect: viewRect(for: printable, viewport: viewport)))
        }
        return path.cgPath
    }

    static func makeBorderLayer(settings: PrintLayoutSettings, viewport: ViewportTransform) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = combinedBorderPath(settings: settings, viewport: viewport)
        layer.strokeColor = borderColor.cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        layer.lineDashPattern = [6, 4]
        layer.contentsScale = DisplayZoomCompensation.layerContentsScale
        return layer
    }

    // MARK: - Printable margin guide (drawn into the print/export output)

    /// Screen preview of the margin guide that will be printed. Rendered in a
    /// neutral ink color (distinct from the orange on-screen print border) so it
    /// reads as "this will appear on paper".
    static func makeMarginGuideLayer(
        style: PrintMarginGuideStyle,
        settings: PrintLayoutSettings,
        viewport: ViewportTransform
    ) -> CAShapeLayer? {
        guard style != .off else { return nil }
        let layer = CAShapeLayer()
        layer.path = combinedBorderPath(settings: settings, viewport: viewport)
        layer.strokeColor = UIColor.label.cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1
        layer.lineDashPattern = style == .dashed ? [6, 4] : nil
        layer.contentsScale = DisplayZoomCompensation.layerContentsScale
        return layer
    }

    // MARK: - Non-printable shading (per-page margin)

    /// Shades the non-printable margin inside each page (the ring between the
    /// page edge and its printable area). Pages no longer overlap, so a simple
    /// per-page even-odd fill is exact with no XOR artifacts between sheets.
    static func nonPrintablePath(settings: PrintLayoutSettings, viewport: ViewportTransform) -> CGPath {
        let path = UIBezierPath()
        for sheet in PrintPageGridEngine.sheets(for: settings) {
            path.append(UIBezierPath(rect: viewRect(for: sheet.frame, viewport: viewport)))
            path.append(UIBezierPath(rect: viewRect(for: printableRect(for: sheet, settings: settings), viewport: viewport)))
        }
        path.usesEvenOddFillRule = true
        return path.cgPath
    }

    static func makeDimOverlayLayer(settings: PrintLayoutSettings, viewport: ViewportTransform) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.systemRed.withAlphaComponent(0.08).cgColor
        layer.fillRule = .evenOdd
        layer.path = nonPrintablePath(settings: settings, viewport: viewport)
        layer.contentsScale = DisplayZoomCompensation.layerContentsScale
        return layer
    }

    // MARK: - Stroke visibility against per-page printable bounds

    static func isPointInsideAnyPrintableArea(_ point: CGPoint, settings: PrintLayoutSettings) -> Bool {
        for sheet in PrintPageGridEngine.sheets(for: settings) {
            if printableRect(for: sheet, settings: settings).contains(point) {
                return true
            }
        }
        return false
    }

    static func strokeOpacity(for stroke: VectorStroke, settings: PrintLayoutSettings) -> CGFloat {
        guard settings.activeTool == .cut else { return 1 }
        let points = ShapeGeometry.renderPoints(for: stroke)
        let hasUnprintablePoint = points.contains { !isPointInsideAnyPrintableArea($0, settings: settings) }
        return hasUnprintablePoint ? 0.3 : 1
    }
}
