//
//  MeasurementUnit.swift
//  Koala
//

import Foundation

nonisolated enum MeasurementUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case millimeters
    case meters
    case inches
    case feet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .millimeters: return "Millimeters"
        case .meters: return "Meters"
        case .inches: return "Inches"
        case .feet: return "Feet"
        }
    }

    var shortLabel: String {
        switch self {
        case .millimeters: return "mm"
        case .meters: return "m"
        case .inches: return "in"
        case .feet: return "ft"
        }
    }

    /// Decimal places for displayed lengths; larger units need more to stay about as precise.
    var fractionDigits: Int {
        switch self {
        case .millimeters, .inches: return 2
        case .feet: return 3
        case .meters: return 4
        }
    }

    /// Fixed-decimal display string; `extraDigits` shifts precision relative to `fractionDigits`.
    func formatted(_ value: CGFloat, extraDigits: Int = 0) -> String {
        String(format: "%.\(max(0, fractionDigits + extraDigits))f", Double(value))
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "centimeters": self = .millimeters
        case "points": self = .inches
        default: self = MeasurementUnit(rawValue: raw) ?? .inches
        }
    }

    func toDocumentUnits(_ value: CGFloat) -> CGFloat {
        UnitConversion.documentPoints(from: value, unit: self)
    }

    func fromDocumentUnits(_ value: CGFloat) -> CGFloat {
        UnitConversion.displayValue(from: value, unit: self)
    }
}
