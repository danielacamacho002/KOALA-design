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
        settings.paperSize.sizeInPoints
    }

    static func sheets(for settings: PrintLayoutSettings) -> [Sheet] {
        let pageSize = pageSize(for: settings)
        let columns = settings.clampedColumns
        let rows = settings.clampedRows
        let stepX = max(pageSize.width - settings.overlap, 1)
        let stepY = max(pageSize.height - settings.overlap, 1)

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

    static func suggestedRegistrationMarks(for settings: PrintLayoutSettings) -> [RegistrationMark] {
        var marks: [RegistrationMark] = []
        let allSheets = sheets(for: settings)
        let pageSize = pageSize(for: settings)

        for sheet in allSheets {
            let printable = printableRect(for: sheet.frame, settings: settings)
            let label = "R\(sheet.row + 1) C\(sheet.column + 1)"
            marks.append(
                RegistrationMark(
                    position: CGPoint(x: printable.minX + 12, y: printable.minY + 12),
                    kind: .pageNumber,
                    pageLabel: label,
                    isLocked: false
                )
            )
        }

        for sheet in allSheets {
            if sheet.column + 1 < settings.clampedColumns {
                let neighbor = allSheets.first {
                    $0.row == sheet.row && $0.column == sheet.column + 1
                }
                if let neighbor {
                    let overlap = sheet.frame.intersection(neighbor.frame)
                    if overlap.width > 0, overlap.height > 0 {
                        marks.append(
                            RegistrationMark(
                                position: CGPoint(x: overlap.midX, y: overlap.midY),
                                kind: .crosshair,
                                pageLabel: "\(sheet.row + 1)-\(sheet.column + 1)/\(sheet.row + 1)-\(sheet.column + 2)",
                                isLocked: false
                            )
                        )
                    }
                }
            }

            if sheet.row + 1 < settings.clampedRows {
                let neighbor = allSheets.first {
                    $0.column == sheet.column && $0.row == sheet.row + 1
                }
                if let neighbor {
                    let overlap = sheet.frame.intersection(neighbor.frame)
                    if overlap.width > 0, overlap.height > 0 {
                        marks.append(
                            RegistrationMark(
                                position: CGPoint(x: overlap.midX, y: overlap.midY),
                                kind: .crosshair,
                                pageLabel: "\(sheet.row + 1)-\(sheet.column + 1)/\(sheet.row + 2)-\(sheet.column + 1)",
                                isLocked: false
                            )
                        )
                    }
                }
            }
        }

        // Corner overlaps where four sheets meet.
        for sheet in allSheets where sheet.column + 1 < settings.clampedColumns && sheet.row + 1 < settings.clampedRows {
            let right = allSheets.first { $0.row == sheet.row && $0.column == sheet.column + 1 }
            let bottom = allSheets.first { $0.row == sheet.row + 1 && $0.column == sheet.column }
            let bottomRight = allSheets.first { $0.row == sheet.row + 1 && $0.column == sheet.column + 1 }
            if let right, let bottom, let bottomRight {
                var overlap = sheet.frame
                overlap = overlap.intersection(right.frame)
                overlap = overlap.intersection(bottom.frame)
                overlap = overlap.intersection(bottomRight.frame)
                if overlap.width > 0, overlap.height > 0 {
                    marks.append(
                        RegistrationMark(
                            position: CGPoint(x: overlap.midX, y: overlap.midY),
                            kind: .crosshair,
                            pageLabel: "4-way",
                            isLocked: false
                        )
                    )
                }
            }
        }

        _ = pageSize
        return deduplicatedMarks(marks, tolerance: 4)
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

    static func refreshRegistrationMarks(
        locked: [RegistrationMark],
        settings: PrintLayoutSettings,
        tolerance: CGFloat = 8
    ) -> [RegistrationMark] {
        let suggestions = suggestedRegistrationMarks(for: settings)
        let filtered = suggestions.filter { suggestion in
            !locked.contains { lockedMark in
                hypot(lockedMark.position.x - suggestion.position.x,
                      lockedMark.position.y - suggestion.position.y) < tolerance
                    && lockedMark.kind == suggestion.kind
            }
        }
        return locked + filtered
    }

    private static func deduplicatedMarks(_ marks: [RegistrationMark], tolerance: CGFloat) -> [RegistrationMark] {
        var result: [RegistrationMark] = []
        for mark in marks {
            let duplicate = result.contains { existing in
                existing.kind == mark.kind
                    && hypot(existing.position.x - mark.position.x,
                             existing.position.y - mark.position.y) < tolerance
            }
            if !duplicate {
                result.append(mark)
            }
        }
        return result
    }
}
