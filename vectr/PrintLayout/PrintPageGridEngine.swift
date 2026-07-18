//
//  PrintPageGridEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

enum PrintPageGridEngine {
    struct Sheet: Identifiable, Equatable {
        var id: Int
        var column: Int
        var row: Int
        var frame: CGRect
    }

    static func pageSize(for settings: PrintLayoutSettings) -> CGSize {
        settings.pageSizeInPoints
    }

    static func sheets(for settings: PrintLayoutSettings) -> [Sheet] {
        let pageSize = pageSize(for: settings)
        let columns = settings.clampedColumns
        let rows = settings.clampedRows
        // Pages are laid out edge-to-edge, with no overlap between sheets:
        // column `c` starts at exactly `c * pageWidth` and row `r` at `r * pageHeight`.
        let stepX = pageSize.width
        let stepY = pageSize.height

        var result: [Sheet] = []
        var index = 0
        for row in 0..<rows {
            for column in 0..<columns {
                let origin = CGPoint(x: CGFloat(column) * stepX, y: CGFloat(row) * stepY)
                let frame = CGRect(origin: origin, size: pageSize)
                result.append(Sheet(id: index, column: column, row: row, frame: frame))
                index += 1
            }
        }
        return result
    }

    static func sheetFrames(for settings: PrintLayoutSettings) -> [CGRect] {
        sheets(for: settings).map(\.frame)
    }

    static func printableRect(for sheetFrame: CGRect, settings: PrintLayoutSettings) -> CGRect {
        sheetFrame.insetBy(
            dx: settings.printableMargin,
            dy: settings.printableMargin
        )
    }

    static func printableRects(for settings: PrintLayoutSettings) -> [CGRect] {
        PrintBorderRenderer.perSheetPrintableRects(settings: settings)
    }

    static func gridBounds(for settings: PrintLayoutSettings) -> CGRect {
        let frames = sheetFrames(for: settings)
        guard !frames.isEmpty else { return .zero }
        var bounds = frames[0]
        for frame in frames.dropFirst() {
            bounds = bounds.union(frame)
        }
        return bounds
    }

    static func printableUnion(for settings: PrintLayoutSettings) -> CGRect {
        let rects = printableRects(for: settings)
        guard !rects.isEmpty else { return .zero }
        var union = rects[0]
        for rect in rects.dropFirst() {
            union = union.union(rect)
        }
        return union
    }

    static func isPointInsidePrintableArea(_ point: CGPoint, settings: PrintLayoutSettings) -> Bool {
        PrintBorderRenderer.isPointInsideAnyPrintableArea(point, settings: settings)
    }
}
