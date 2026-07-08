//
//  GridSettings.swift
//  vectr
//

import CoreGraphics
import Foundation

struct GridSettings: Codable, Equatable {
    var isVisible: Bool = true
    var spacing: CGFloat = 20
    // Kept for backward compatibility with old documents.
    // The app now treats each visible grid square as one full spacing unit.
    var subdivisions: Int = 1
    var snapEnabled: Bool = true
    /// Snap granularity as a fraction of a grid square: 1 = corners, 2 = halves, 4 = quarters.
    var snapSubdivisions: Int = 1
    var angleSnapEnabled: Bool = true
    var angleSnapDegrees: [CGFloat] = [0, 45, 90, 135, 180]

    var minorSpacing: CGFloat {
        spacing
    }

    /// Major grid spacing in document points derived from settings slider + unit.
    func visualSpacing(for settings: DocumentSettings) -> CGFloat {
        UnitConversion.visualGridSpacing(
            sliderValue: settings.defaultGridSpacingInUnits,
            unit: settings.units
        )
    }

    /// Effective snap spacing accounting for sub-grid subdivisions (halves/quarters).
    func effectiveSnapSpacing(for settings: DocumentSettings) -> CGFloat {
        visualSpacing(for: settings) / CGFloat(max(1, snapSubdivisions))
    }

    func minorSpacing(for settings: DocumentSettings) -> CGFloat {
        visualSpacing(for: settings)
    }
}
