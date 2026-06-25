//
//  PrintBorderRenderer.swift
//  vectr
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

    // MARK: - Border paths (one dashed rect per sheet)

    static func borderPath(for printableRect: CGRect, viewport: ViewportTransform) -> UIBezierPath {
        UIBezierPath(rect: viewRect(for: printableRect, viewport: viewport))
    }

    /// Builds a path containing one inset printable border per sheet in the grid.
    static func combinedBorderPath(settings: PrintLayoutSettings, viewport: ViewportTransform) -> CGPath {
        let path = UIBezierPath()
        for sheet in PrintPageGridEngine.sheets(for: settings) {
            let printable = printableRect(for: sheet, settings: settings)
            path.append(borderPath(for: printable, viewport: viewport))
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
        layer.contentsScale = UIScreen.main.scale
        return layer
    }

    // MARK: - Per-sheet dead-zone shading (margin within each sheet only)

    /// Shades the non-printable margin inside every individual sheet.
    static func perSheetDimPath(settings: PrintLayoutSettings, viewport: ViewportTransform) -> CGPath {
        let path = UIBezierPath()
        for sheet in PrintPageGridEngine.sheets(for: settings) {
            let sheetView = viewRect(for: sheet.frame, viewport: viewport)
            let printableView = viewRect(for: printableRect(for: sheet, settings: settings), viewport: viewport)
            path.append(UIBezierPath(rect: sheetView))
            path.append(UIBezierPath(rect: printableView))
        }
        path.usesEvenOddFillRule = true
        return path.cgPath
    }

    static func makeDimOverlayLayer(settings: PrintLayoutSettings, viewport: ViewportTransform) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.systemRed.withAlphaComponent(0.08).cgColor
        layer.fillRule = .evenOdd
        layer.path = perSheetDimPath(settings: settings, viewport: viewport)
        layer.contentsScale = UIScreen.main.scale
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
        guard settings.isPrintBorderVisible else { return 1 }
        let points = ShapeGeometry.renderPoints(for: stroke)
        let hasUnprintablePoint = points.contains { !isPointInsideAnyPrintableArea($0, settings: settings) }
        return hasUnprintablePoint ? 0.3 : 1
    }
}
