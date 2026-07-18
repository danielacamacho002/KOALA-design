//
//  PrintLayoutSettings.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Line style for the printable-area margin outline drawn into exported pages.
enum PrintMarginGuideStyle: String, Codable, CaseIterable, Identifiable {
    case off
    case dashed
    case solid

    var id: String { rawValue }
}

/// Unified control for the print margin / border. Chooses whether the printable
/// area is shown only on screen, or additionally drawn onto the printed pages.
enum PrintMarginMode: String, Codable, CaseIterable, Identifiable {
    /// Nothing shown.
    case off
    /// On-screen red dashed border + dimmed margins; not printed.
    case displayOnly
    /// Dashed outline shown on screen and printed onto the pages.
    case printDashed
    /// Solid outline shown on screen and printed onto the pages.
    case printSolid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .displayOnly: return "Display only"
        case .printDashed: return "Dashed (printed)"
        case .printSolid: return "Solid (printed)"
        }
    }

    /// Any on-screen affordance (border/guide + dimmed margins) is shown.
    var showsOverlay: Bool { self != .off }

    /// The red dashed screen-only border (display-only mode).
    var showsScreenBorder: Bool { self == .displayOnly }

    /// Line style drawn onto printed pages (`.off` when not printed).
    var printedStyle: PrintMarginGuideStyle {
        switch self {
        case .printDashed: return .dashed
        case .printSolid: return .solid
        case .off, .displayOnly: return .off
        }
    }
}

struct PrintLayoutSettings: Codable, Equatable {
    var paperSize: PaperSize = .letter
    /// Dimensions (document points) used when `paperSize == .custom`.
    var customPaperSize: CGSize = CGSize(width: 612, height: 792)
    var columns: Int = 3
    var rows: Int = 3
    /// Overlap between adjacent sheets in document points (~0.5 in default).
    var overlap: CGFloat = 36
    /// Unprintable margin per sheet edge in document points (~0.25 in default).
    var printableMargin: CGFloat = 18
    /// Unified margin/border display + print mode.
    var marginMode: PrintMarginMode = .off
    var activeTool: PrintLayoutTool = .select
    /// Shifts all artwork onto the paper grid (applied before per-stroke transforms).
    var contentOffset: CGPoint = .zero

    var clampedColumns: Int { min(max(columns, 1), 10) }
    var clampedRows: Int { min(max(rows, 1), 10) }

    /// Resolved page size in document points, honoring a custom paper size.
    var pageSizeInPoints: CGSize {
        paperSize == .custom ? customPaperSize : paperSize.sizeInPoints
    }

    private enum CodingKeys: String, CodingKey {
        case paperSize, customPaperSize, columns, rows, overlap, printableMargin
        case marginMode
        case isPrintBorderVisible
        case showPrintBorders
        case printMarginGuide
        case activeTool, contentOffset
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paperSize = try container.decodeIfPresent(PaperSize.self, forKey: .paperSize) ?? .letter
        customPaperSize = try container.decodeIfPresent(CGSize.self, forKey: .customPaperSize) ?? CGSize(width: 612, height: 792)
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? 3
        rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? 3
        overlap = try container.decodeIfPresent(CGFloat.self, forKey: .overlap) ?? 36
        printableMargin = try container.decodeIfPresent(CGFloat.self, forKey: .printableMargin) ?? 18
        if let mode = try container.decodeIfPresent(PrintMarginMode.self, forKey: .marginMode) {
            marginMode = mode
        } else {
            // Backward compatibility: derive the unified mode from the previous
            // separate border-visibility flag and printed-guide style.
            let legacyBorder = try (container.decodeIfPresent(Bool.self, forKey: .isPrintBorderVisible)
                ?? container.decodeIfPresent(Bool.self, forKey: .showPrintBorders)) ?? false
            let legacyGuide = try container.decodeIfPresent(PrintMarginGuideStyle.self, forKey: .printMarginGuide) ?? .off
            switch legacyGuide {
            case .dashed: marginMode = .printDashed
            case .solid: marginMode = .printSolid
            case .off: marginMode = legacyBorder ? .displayOnly : .off
            }
        }
        // Tolerate tool cases that no longer exist (e.g. a removed registration
        // mark tool) by falling back to `.select` instead of failing to decode.
        activeTool = (try? container.decode(PrintLayoutTool.self, forKey: .activeTool)) ?? .select
        contentOffset = try container.decodeIfPresent(CGPoint.self, forKey: .contentOffset) ?? .zero
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(paperSize, forKey: .paperSize)
        try container.encode(customPaperSize, forKey: .customPaperSize)
        try container.encode(columns, forKey: .columns)
        try container.encode(rows, forKey: .rows)
        try container.encode(overlap, forKey: .overlap)
        try container.encode(printableMargin, forKey: .printableMargin)
        try container.encode(marginMode, forKey: .marginMode)
        try container.encode(activeTool, forKey: .activeTool)
        try container.encode(contentOffset, forKey: .contentOffset)
    }
}
