//
//  DocumentSettings.swift
//  vectr
//

import CoreGraphics
import Foundation

struct DocumentSettings: Codable, Equatable {
    /// Default canvas dimensions applied to brand-new projects (24" × 18").
    static let defaultCanvasWidth: CGFloat = UnitConversion.documentPoints(from: 24, unit: .inches)
    static let defaultCanvasHeight: CGFloat = UnitConversion.documentPoints(from: 18, unit: .inches)

    var units: MeasurementUnit = .inches
    /// Default corner fillet for new rectangles and fillet tool.
    var defaultCornerRadius: CGFloat = 0
    /// Absolute canvas width in document points (the hard drawable boundary).
    var canvasWidth: CGFloat = defaultCanvasWidth
    /// Absolute canvas height in document points (the hard drawable boundary).
    var canvasHeight: CGFloat = defaultCanvasHeight
    var defaultGridSpacing: CGFloat = 72
    /// When false, finger taps/drags won't create drawing input; Apple Pencil still works.
    var allowsFingerDrawing: Bool = false

    /// Canvas dimensions as a size in document points.
    var canvasSize: CGSize {
        CGSize(width: canvasWidth, height: canvasHeight)
    }

    var defaultGridSpacingInUnits: CGFloat {
        get { units.fromDocumentUnits(defaultGridSpacing) }
        set { defaultGridSpacing = units.toDocumentUnits(newValue) }
    }

    private enum CodingKeys: String, CodingKey {
        case units
        case defaultCornerRadius
        case canvasWidth
        case canvasHeight
        case canvasExtent
        case defaultGridSpacing
        case allowsFingerDrawing
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        units = try container.decodeIfPresent(MeasurementUnit.self, forKey: .units) ?? .inches
        defaultCornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .defaultCornerRadius) ?? 0
        if let width = try container.decodeIfPresent(CGFloat.self, forKey: .canvasWidth),
           let height = try container.decodeIfPresent(CGFloat.self, forKey: .canvasHeight) {
            canvasWidth = width
            canvasHeight = height
        } else if let legacyExtent = try container.decodeIfPresent(CGFloat.self, forKey: .canvasExtent) {
            // Older projects stored a single square extent.
            canvasWidth = legacyExtent
            canvasHeight = legacyExtent
        }
        defaultGridSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .defaultGridSpacing) ?? 72
        allowsFingerDrawing = try container.decodeIfPresent(Bool.self, forKey: .allowsFingerDrawing) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(units, forKey: .units)
        try container.encode(defaultCornerRadius, forKey: .defaultCornerRadius)
        try container.encode(canvasWidth, forKey: .canvasWidth)
        try container.encode(canvasHeight, forKey: .canvasHeight)
        try container.encode(defaultGridSpacing, forKey: .defaultGridSpacing)
        try container.encode(allowsFingerDrawing, forKey: .allowsFingerDrawing)
    }

    static func maximumCanvasExtentInSelectedUnits(for unit: MeasurementUnit) -> CGFloat {
        switch unit {
        case .inches:
            return 1_000
        case .centimeters:
            return 2_500
        case .millimeters:
            return 25_000
        case .points:
            return UnitConversion.documentPoints(from: 1_000, unit: .inches)
        }
    }

    static func maximumCanvasExtent(for unit: MeasurementUnit) -> CGFloat {
        UnitConversion.documentPoints(
            from: maximumCanvasExtentInSelectedUnits(for: unit),
            unit: unit
        )
    }
}
