//
//  PatternSettings.swift
//  vectr
//

import CoreGraphics
import Foundation

enum PatternMode: String, CaseIterable, Codable, Identifiable {
    case grid
    case linear
    case radial
    case spiral

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: return "Grid"
        case .linear: return "Linear"
        case .radial: return "Radial"
        case .spiral: return "Spiral"
        }
    }
}

enum LinearDirection: String, CaseIterable, Codable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

struct PatternSettings: Equatable {
    static let maxCount = 100

    var mode: PatternMode = .grid
    var count: Int = 4
    var rows: Int = 2
    var columns: Int = 2
    var spacingX: CGFloat = 50
    var spacingY: CGFloat = 50
    var rotateCopies: Bool = false
    /// Radial and spiral only. When on, count is the number of new copies and the source stays put.
    /// When off, count is the total number of shapes after apply and the source moves to the first slot.
    var keepOriginal: Bool = true
    /// Center-to-center distance between copies along the curved path.
    var tightness: CGFloat = 10
    var linearDirection: LinearDirection = .horizontal
    /// When true, radial copies are evenly distributed around 360°. When false, angle step comes from tightness.
    var radialSpreadEven: Bool = true

    static func defaults(for stroke: VectorStroke) -> PatternSettings {
        var settings = PatternSettings()
        let spacing = PatternEngine.defaultSpacing(for: stroke)
        settings.spacingX = spacing.x
        settings.spacingY = spacing.y
        settings.tightness = max(spacing.x, spacing.y)
        return settings
    }
}

enum PatternApplyResult: Equatable {
    case success(created: Int)
    case noSelection
    case layerLocked
    case nothingToCreate
}
