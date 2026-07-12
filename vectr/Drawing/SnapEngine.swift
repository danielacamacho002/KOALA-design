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

func snapDrawingPoint(
    _ point: CGPoint,
    grid: GridSettings,
    settings: DocumentSettings,
    enabled: Bool
) -> CGPoint {
    guard enabled, grid.snapEnabled else { return point }
    let spacing = grid.effectiveSnapSpacing(for: settings)
    return snapPointToGrid(point, gridSpacing: spacing)
}

func snapDrawingControlPoint(
    raw: CGPoint,
    projected: CGPoint,
    grid: GridSettings,
    settings: DocumentSettings,
    enabled: Bool
) -> CGPoint {
    snapDrawingPoint(projected, grid: grid, settings: settings, enabled: enabled)
}
