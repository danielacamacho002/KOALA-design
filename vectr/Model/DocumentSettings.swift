//
//  DocumentSettings.swift
//  vectr
//

import CoreGraphics
import Foundation

struct DocumentSettings: Codable, Equatable {
    var units: MeasurementUnit = .inches
    /// Default corner fillet for new rectangles and fillet tool.
    var defaultCornerRadius: CGFloat = 0
    /// Absolute background canvas extent in document points.
    /// This is fixed by active unit (not user-adjustable from Settings UI).
    var canvasExtent: CGFloat = UnitConversion.documentPoints(from: 1_000, unit: .inches)
    var defaultGridSpacing: CGFloat = 72
    /// When false, finger taps/drags won't create drawing input; Apple Pencil still works.
    var allowsFingerDrawing: Bool = false

    var defaultGridSpacingInUnits: CGFloat {
        get { units.fromDocumentUnits(defaultGridSpacing) }
        set { defaultGridSpacing = units.toDocumentUnits(newValue) }
    }

    private enum CodingKeys: String, CodingKey {
        case units
        case defaultCornerRadius
        case canvasExtent
        case defaultGridSpacing
        case allowsFingerDrawing
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        units = try container.decodeIfPresent(MeasurementUnit.self, forKey: .units) ?? .inches
        defaultCornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .defaultCornerRadius) ?? 0
        canvasExtent = try container.decodeIfPresent(CGFloat.self, forKey: .canvasExtent)
            ?? Self.maximumCanvasExtent(for: units)
        defaultGridSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .defaultGridSpacing) ?? 72
        allowsFingerDrawing = try container.decodeIfPresent(Bool.self, forKey: .allowsFingerDrawing) ?? false
        syncCanvasExtentToMaximum()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(units, forKey: .units)
        try container.encode(defaultCornerRadius, forKey: .defaultCornerRadius)
        try container.encode(canvasExtent, forKey: .canvasExtent)
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

    mutating func syncCanvasExtentToMaximum() {
        canvasExtent = Self.maximumCanvasExtent(for: units)
    }
}
