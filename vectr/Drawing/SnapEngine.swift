//
//  SnapEngine.swift
//  vectr
//
//  Grid-snapping helpers and polar/axis tracking for in-progress lines.
//  Object snapping (endpoints/midpoints) lives in `PathSnapEngine.swift`.
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

/// Result of optional H/V assist for the free end of a drawn segment.
struct AngleSnapResult {
    var point: CGPoint
    var isLocked: Bool
}

/// Light assist only: if the stroke is already almost horizontal or vertical,
/// pin it to that axis. Anything else — including diagonals — stays free.
func snapDrawingAngle(
    _ point: CGPoint,
    origin: CGPoint,
    grid: GridSettings,
    scale: CGFloat?
) -> AngleSnapResult {
    _ = grid
    _ = scale
    let dx = point.x - origin.x
    let dy = point.y - origin.y
    let length = hypot(dx, dy)
    guard length > 1e-4 else {
        return AngleSnapResult(point: point, isLocked: false)
    }

    // ~10° from the axis. Wider than this and intentional diagonals get stolen.
    let maxAxisError = 10 * CGFloat.pi / 180
    let verticalError = abs(atan2(dx, dy))
    let horizontalError = abs(atan2(dy, dx))

    if verticalError <= maxAxisError {
        return AngleSnapResult(point: CGPoint(x: origin.x, y: point.y), isLocked: true)
    }
    if horizontalError <= maxAxisError {
        return AngleSnapResult(point: CGPoint(x: point.x, y: origin.y), isLocked: true)
    }
    return AngleSnapResult(point: point, isLocked: false)
}

/// Object snap first (so a real corner/end can be hit on a diagonal), then a
/// light H/V assist, then grid snap. Axis assist never overrides an object snap.
func snapDrawingEndpoint(
    _ point: CGPoint,
    origin: CGPoint?,
    applyAngleSnap: Bool,
    grid: GridSettings,
    settings: DocumentSettings,
    gridSnapEnabled: Bool,
    scale: CGFloat,
    objectSnap: (_ query: CGPoint, _ alignmentOrigin: CGPoint?, _ alignmentThrough: CGPoint?) -> CGPoint?
) -> CGPoint {
    if let snapped = objectSnap(point, nil, nil) {
        return snapped
    }

    let angle: AngleSnapResult
    if applyAngleSnap, let origin {
        angle = snapDrawingAngle(point, origin: origin, grid: grid, scale: scale)
    } else {
        angle = AngleSnapResult(point: point, isLocked: false)
    }

    let gridSnapped = snapDrawingPoint(
        angle.point,
        grid: grid,
        settings: settings,
        enabled: gridSnapEnabled,
        scale: scale
    )
    if angle.isLocked, let origin {
        return projectOntoRay(gridSnapped, origin: origin, through: angle.point)
    }
    return gridSnapped
}

func distanceFromPointToRay(_ point: CGPoint, origin: CGPoint, through: CGPoint) -> CGFloat {
    let dir = CGPoint(x: through.x - origin.x, y: through.y - origin.y)
    let length = hypot(dir.x, dir.y)
    guard length > 1e-9 else { return hypot(point.x - origin.x, point.y - origin.y) }
    let t = ((point.x - origin.x) * dir.x + (point.y - origin.y) * dir.y) / (length * length)
    let projected = CGPoint(x: origin.x + t * dir.x, y: origin.y + t * dir.y)
    return hypot(point.x - projected.x, point.y - projected.y)
}

private func projectOntoRay(_ point: CGPoint, origin: CGPoint, through: CGPoint) -> CGPoint {
    let dir = CGPoint(x: through.x - origin.x, y: through.y - origin.y)
    let length = hypot(dir.x, dir.y)
    guard length > 1e-9 else { return point }
    let t = ((point.x - origin.x) * dir.x + (point.y - origin.y) * dir.y) / (length * length)
    return CGPoint(x: origin.x + t * dir.x, y: origin.y + t * dir.y)
}
