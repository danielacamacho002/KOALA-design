//
//  MeasurementUnit.swift
//  vectr
//

import Foundation

nonisolated enum MeasurementUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case points
    case millimeters
    case centimeters
    case inches

    var id: String { rawValue }

    var label: String {
        switch self {
        case .points: return "Points (pt)"
        case .millimeters: return "Millimeters (mm)"
        case .centimeters: return "Centimeters (cm)"
        case .inches: return "Inches (in)"
        }
    }

    var shortLabel: String {
        switch self {
        case .points: return "pt"
        case .millimeters: return "mm"
        case .centimeters: return "cm"
        case .inches: return "in"
        }
    }

    func toDocumentUnits(_ value: CGFloat) -> CGFloat {
        UnitConversion.documentPoints(from: value, unit: self)
    }

    func fromDocumentUnits(_ value: CGFloat) -> CGFloat {
        UnitConversion.displayValue(from: value, unit: self)
    }
}
