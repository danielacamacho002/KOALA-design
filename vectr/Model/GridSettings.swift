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
    /// Snap granularity as a fraction of a grid square: 1 = corners, 2 = halves,
    /// 4 = quarters, 8 = eighths, 16 = sixteenths.
    var snapSubdivisions: Int = 8
    /// Kept for document compatibility. Live drawing only nudges a stroke onto
    /// H/V when it is already within ~10° of that axis.
    var angleSnapEnabled: Bool = true
    var angleSnapDegrees: [CGFloat] = [0, 90]

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

    /// On-screen pixel floor for the finest visible sub-grid line. Snap precision
    /// tracks the same value so snapping never gets finer than what is drawn.
    static let minorLinePixelFloor: CGFloat = 9

    /// Largest power-of-2 subdivision of the grid square whose minor lines stay at
    /// least `minorLinePixelFloor` apart on screen at the given zoom `scale`.
    /// This is what makes finer lines reveal (and snapping tighten) as you zoom in.
    func visibleSubdivisions(for settings: DocumentSettings, scale: CGFloat) -> Int {
        let major = visualSpacing(for: settings)
        guard major > 0, scale > 0 else { return 1 }
        var subdiv = 1
        while major * scale / CGFloat(subdiv * 2) >= Self.minorLinePixelFloor {
            subdiv *= 2
        }
        return subdiv
    }

    /// Zoom-aware snap spacing: the finer of the user's snap setting and the finest
    /// currently-visible sub-grid line. Precision increases as you zoom in but never
    /// gets coarser than the user's chosen `snapSubdivisions`.
    func adaptiveSnapSpacing(for settings: DocumentSettings, scale: CGFloat) -> CGFloat {
        let userDiv = max(1, snapSubdivisions)
        let effective = max(userDiv, visibleSubdivisions(for: settings, scale: scale))
        return visualSpacing(for: settings) / CGFloat(effective)
    }

    func minorSpacing(for settings: DocumentSettings) -> CGFloat {
        visualSpacing(for: settings)
    }
}
