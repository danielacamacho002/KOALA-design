//
//  PrintLayoutSettings.swift
//  vectr
//

import CoreGraphics
import Foundation

struct PrintLayoutSettings: Codable, Equatable {
    var paperSize: PaperSize = .letter
    var columns: Int = 3
    var rows: Int = 3
    /// Overlap between adjacent sheets in document points (~0.5 in default).
    var overlap: CGFloat = 36
    /// Unprintable margin per sheet edge in document points (~0.25 in default).
    var printableMargin: CGFloat = 18
    var isPrintBorderVisible: Bool = false
    var activeTool: PrintLayoutTool = .select
    /// Shifts all artwork onto the paper grid (applied before per-stroke transforms).
    var contentOffset: CGPoint = .zero

    var clampedColumns: Int { min(max(columns, 1), 10) }
    var clampedRows: Int { min(max(rows, 1), 10) }

    private enum CodingKeys: String, CodingKey {
        case paperSize, columns, rows, overlap, printableMargin
        case isPrintBorderVisible
        case showPrintBorders
        case activeTool, contentOffset
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paperSize = try container.decodeIfPresent(PaperSize.self, forKey: .paperSize) ?? .letter
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? 3
        rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? 3
        overlap = try container.decodeIfPresent(CGFloat.self, forKey: .overlap) ?? 36
        printableMargin = try container.decodeIfPresent(CGFloat.self, forKey: .printableMargin) ?? 18
        if let visible = try container.decodeIfPresent(Bool.self, forKey: .isPrintBorderVisible) {
            isPrintBorderVisible = visible
        } else {
            isPrintBorderVisible = try container.decodeIfPresent(Bool.self, forKey: .showPrintBorders) ?? false
        }
        // Tolerate tool cases that no longer exist (e.g. a removed registration
        // mark tool) by falling back to `.select` instead of failing to decode.
        activeTool = (try? container.decode(PrintLayoutTool.self, forKey: .activeTool)) ?? .select
        contentOffset = try container.decodeIfPresent(CGPoint.self, forKey: .contentOffset) ?? .zero
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paperSize, forKey: .paperSize)
        try container.encode(columns, forKey: .columns)
        try container.encode(rows, forKey: .rows)
        try container.encode(overlap, forKey: .overlap)
        try container.encode(printableMargin, forKey: .printableMargin)
        try container.encode(isPrintBorderVisible, forKey: .isPrintBorderVisible)
        try container.encode(activeTool, forKey: .activeTool)
        try container.encode(contentOffset, forKey: .contentOffset)
    }
}
