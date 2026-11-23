//
//  SnapEngine.swift
//  Koala
//
//  Grid-snapping helpers and polar/axis tracking for in-progress lines.
//  Object snapping (endpoints/midpoints) lives in `PathSnapEngine.swift`.
//

import CoreGraphics
import Foundation

/// Document-space budget for “these two anchors are the same point”.
/// Screen-constant so zoom-in stays tight; capped so zoom-out cannot weld
/// nearby verticals that merely share a grid cell.
func coincidentAnchorTolerance(viewport: ViewportTransform, grid: GridSettings) -> CGFloat {
    let screen = viewport.viewToDocument(distance: SnapTuning.coincidentAnchorPoints)
    let documentCap = max(1.5, grid.spacing * 0.1)
    return min(screen, documentCap)
}

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
///
/// Short ticks use an on-screen deadzone as well as the 10° cone. A 10pt
/// horizontal with a couple points of wobble is ~15° — enough to miss the
/// cone and then jump onto a nearby vertical endpoint.
func snapDrawingAngle(
    _ point: CGPoint,
    origin: CGPoint,
    grid: GridSettings,
    scale: CGFloat?,
    allowed: Set<DrawingAxis> = [.horizontal, .vertical]
) -> AngleSnapResult {
    _ = grid
    let dx = point.x - origin.x
    let dy = point.y - origin.y
    let length = hypot(dx, dy)
    guard length > 1e-4, !allowed.isEmpty else {
        return AngleSnapResult(point: point, isLocked: false)
    }

    // ~10° from the axis. Wider than this and intentional diagonals get stolen.
    let maxAxisError = 10 * CGFloat.pi / 180
    let maxOffAxis = 8 / max(scale ?? 1, 0.0001)
    let verticalError = abs(atan2(dx, dy))
    let horizontalError = abs(atan2(dy, dx))

    let lockVertical = allowed.contains(.vertical)
        && abs(dy) > abs(dx)
        && (verticalError <= maxAxisError || abs(dx) <= maxOffAxis)
    let lockHorizontal = allowed.contains(.horizontal)
        && abs(dx) > abs(dy)
        && (horizontalError <= maxAxisError || abs(dy) <= maxOffAxis)

    if lockVertical {
        return AngleSnapResult(point: CGPoint(x: origin.x, y: point.y), isLocked: true)
    }
    if lockHorizontal {
        return AngleSnapResult(point: CGPoint(x: point.x, y: origin.y), isLocked: true)
    }
    return AngleSnapResult(point: point, isLocked: false)
}

/// Axis of a segment that is already horizontal or vertical, such as a line
/// the angle assist has pinned. `nil` for diagonals and for segments shorter
/// than `minimumLength` (document units).
enum DrawingAxis: Equatable, Sendable, Hashable {
    case horizontal
    case vertical
}

func drawingAxis(from start: CGPoint, to end: CGPoint, minimumLength: CGFloat = 0.001) -> DrawingAxis? {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = hypot(dx, dy)
    guard length >= minimumLength else { return nil }
    let slack = max(1e-3, length * 1e-4)
    if abs(dy) <= slack { return .horizontal }
    if abs(dx) <= slack { return .vertical }
    return nil
}

/// When the stroke is already almost H/V, keep object snap on that axis so a
/// short horizontal cannot jump onto a nearby vertical's endpoint. Free
/// (off-axis) strokes still snap to any nearby corner so intentional
/// diagonals work.
func snapDrawingEndpoint(
    _ point: CGPoint,
    origin: CGPoint?,
    applyAngleSnap: Bool,
    grid: GridSettings,
    settings: DocumentSettings,
    gridSnapEnabled: Bool,
    scale: CGFloat,
    allowedAxes: Set<DrawingAxis> = [.horizontal, .vertical],
    objectSnap: (_ query: CGPoint, _ alignmentOrigin: CGPoint?, _ alignmentThrough: CGPoint?) -> CGPoint?
) -> CGPoint {
    let angle: AngleSnapResult
    if applyAngleSnap, let origin {
        angle = snapDrawingAngle(point, origin: origin, grid: grid, scale: scale, allowed: allowedAxes)
    } else {
        angle = AngleSnapResult(point: point, isLocked: false)
    }

    if angle.isLocked, let origin {
        if let snapped = objectSnap(point, origin, angle.point),
           snapDrawingAngle(snapped, origin: origin, grid: grid, scale: scale, allowed: allowedAxes).isLocked {
            return snapped
        }
    } else if let snapped = objectSnap(point, nil, nil) {
        return snapped
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

/// Apple Pencil's lift sample can leap off the stroke the preview was showing.
/// Keep `lastPreview` when the proposed end is farther than `thresholdPoints`
/// of screen space. A nil preview (the stroke never moved) keeps `proposed`,
/// so a short tap-drag that only reports `.ended` still lands on the lift.
func pencilLiftEndPoint(
    proposed: CGPoint,
    lastPreview: CGPoint?,
    scale: CGFloat,
    thresholdPoints: CGFloat = 8
) -> CGPoint {
    guard let lastPreview else { return proposed }
    let limit = thresholdPoints / max(scale, 0.0001)
    let jump = hypot(proposed.x - lastPreview.x, proposed.y - lastPreview.y)
    if jump > limit {
        return lastPreview
    }
    return proposed
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
