//
//  UnitConversion.swift
//  Koala
//

import CoreGraphics
import Foundation

nonisolated enum UnitConversion: Sendable {
    /// Typographic points per inch (screen/document base unit).
    static let pointsPerInch: CGFloat = 72

    /// Document points represented by one unit of the given measurement.
    static func pointsPerUnit(for unit: MeasurementUnit) -> CGFloat {
        switch unit {
        case .inches: return pointsPerInch
        case .feet: return pointsPerInch * 12
        case .millimeters: return pointsPerInch / 25.4
        case .meters: return pointsPerInch / 0.0254
        }
    }

    /// Converts a value in the selected measurement unit to document points.
    static func documentPoints(from value: CGFloat, unit: MeasurementUnit) -> CGFloat {
        value * pointsPerUnit(for: unit)
    }

    /// Converts document points to the selected measurement unit.
    static func displayValue(from documentPoints: CGFloat, unit: MeasurementUnit) -> CGFloat {
        documentPoints / pointsPerUnit(for: unit)
    }

    /// Major grid line spacing in document points from the settings slider value.
    static func visualGridSpacing(sliderValue: CGFloat, unit: MeasurementUnit) -> CGFloat {
        documentPoints(from: sliderValue, unit: unit)
    }
}
