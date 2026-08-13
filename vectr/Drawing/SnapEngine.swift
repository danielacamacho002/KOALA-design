//
//  SnapEngine.swift
//  vectr
//
//  Grid-snapping helpers. Object snapping (endpoints/midpoints) lives in
//  `PathSnapEngine.swift`.
//

import CoreGraphics
import Foundation

func snapPointToGrid(_ point: CGPoint, gridSpacing: CGFloat) -> CGPoint {
    guard gridSpacing > 0 else { return point }
    return CGPoint(
        x: (point.x / gridSpacing).rounded() * gridSpacing,
        y: (point.y / gridSpacing).rounded() * gridSpacing
    )
}

/// Snaps a drawing point to the grid. Pass `scale` (the viewport zoom) for
/// direct-manipulation input so snapping tightens as you zoom in (hybrid mode);
/// leave it `nil` for typed/precise entry to use the fixed user snap setting.
func snapDrawingPoint(
    _ point: CGPoint,
    grid: GridSettings,
    settings: DocumentSettings,
    enabled: Bool,
    scale: CGFloat? = nil
) -> CGPoint {
    guard enabled, grid.snapEnabled else { return point }
    let spacing: CGFloat
    if let scale {
        spacing = grid.adaptiveSnapSpacing(for: settings, scale: scale)
    } else {
        spacing = grid.effectiveSnapSpacing(for: settings)
    }
    return snapPointToGrid(point, gridSpacing: spacing)
}

func snapDrawingControlPoint(
    raw: CGPoint,
    projected: CGPoint,
    grid: GridSettings,
    settings: DocumentSettings,
    enabled: Bool,
    scale: CGFloat? = nil
) -> CGPoint {
    snapDrawingPoint(projected, grid: grid, settings: settings, enabled: enabled, scale: scale)
}
