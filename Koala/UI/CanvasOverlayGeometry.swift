//
//  CanvasOverlayGeometry.swift
//  Koala
//

import CoreGraphics
import Foundation

/// Pure drag math behind `CanvasOverlayView`'s scale and marquee handles. The stroke,
/// reference-image, and text handles all resolve their factors here so the three paths
/// cannot drift apart.
nonisolated enum CanvasOverlayGeometry: Sendable {
    /// Guards every division against a degenerate (zero-area) bounding box.
    static let epsilon: CGFloat = 0.001

    /// On-screen side of an anchor mark at 1×. Matches the overlay's visible square.
    static let anchorMarkSize: CGFloat = 6
    /// On-screen side of an anchor's grab square. Two anchors closer than this stack.
    static let curveAnchorHitExtent: CGFloat = 44
    /// On-screen diameter of a Bézier tangent handle's grab circle.
    static let curveTangentHitDiameter: CGFloat = 28
    /// Shortest real tangent arm, in document points. An eighth of an inch.
    /// Zoom scales it with the pattern instead of stretching the picture.
    static let minimumTangentLength: CGFloat = UnitConversion.documentPoints(from: 0.125, unit: .inches)

    /// Corner handles in the order the overlay draws and indexes them:
    /// top-left, top-right, bottom-right, bottom-left.
    static func cornerHandles(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }

    /// Radius captured when a uniform scale begins. Floored so a zero-area box cannot
    /// produce an infinite factor on the first drag sample.
    static func cornerDistance(from center: CGPoint, to corner: CGPoint) -> CGFloat {
        max(hypot(corner.x - center.x, corner.y - center.y), epsilon)
    }

    /// Scale factors for dragging `corner` to `dragPoint` about `center`. Uniform mode
    /// uses the radial distance ratio against the captured `originCornerDistance`; free
    /// mode scales each axis on its own and leaves an axis at 1 when the corner sits on
    /// that center line, where the ratio would be meaningless.
    static func scaleFactors(
        center: CGPoint,
        corner: CGPoint,
        dragPoint: CGPoint,
        uniform: Bool,
        originCornerDistance: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        if uniform {
            let distance = hypot(dragPoint.x - center.x, dragPoint.y - center.y)
            let factor = distance / max(originCornerDistance, epsilon)
            return (factor, factor)
        }
        let sx = abs(corner.x - center.x) > epsilon
            ? (dragPoint.x - center.x) / (corner.x - center.x)
            : 1
        let sy = abs(corner.y - center.y) > epsilon
            ? (dragPoint.y - center.y) / (corner.y - center.y)
            : 1
        return (sx, sy)
    }

    static func scaled(points: [CGPoint], about center: CGPoint, x sx: CGFloat, y sy: CGFloat) -> [CGPoint] {
        points.map { point in
            CGPoint(
                x: center.x + (point.x - center.x) * sx,
                y: center.y + (point.y - center.y) * sy
            )
        }
    }

    /// Curve handles are offsets from their anchor, so they scale without recentering.
    static func scaled(handles: [CurveHandle], x sx: CGFloat, y sy: CGFloat) -> [CurveHandle] {
        handles.map { handle in
            CurveHandle(
                inOffset: CGPoint(x: handle.inOffset.x * sx, y: handle.inOffset.y * sy),
                outOffset: CGPoint(x: handle.outOffset.x * sx, y: handle.outOffset.y * sy)
            )
        }
    }

    /// Reference-image frame after a corner drag. The frame stays centered and takes the
    /// magnitude of each factor, so dragging a handle past the center grows the image
    /// instead of inverting it.
    static func scaledFrame(origin: CGRect, center: CGPoint, x sx: CGFloat, y sy: CGFloat) -> CGRect {
        let width = abs(origin.width * sx)
        let height = abs(origin.height * sy)
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    /// Font size for a uniform text-scale drag, floored so text stays legible and selectable.
    static func scaledFontSize(origin: CGFloat, center: CGPoint, dragPoint: CGPoint, originDistance: CGFloat) -> CGFloat {
        let distance = hypot(dragPoint.x - center.x, dragPoint.y - center.y)
        return max(4, origin * (distance / max(originDistance, epsilon)))
    }

    /// Lowest zoom factor an anchor mark tracks. Below this the square holds at half
    /// its 1× size so a zoomed-out shape stays the subject and the mark stays visible.
    static let anchorTrackScaleFloor: CGFloat = 0.5

    /// How many times the on-screen stroke an anchor square must cover. The mark is
    /// the same color as the line, so once the stroke grows past the 1× size the
    /// square has to stay a little wider or it vanishes inside the stroke.
    static let anchorStrokeClearance: CGFloat = 1.5

    /// Largest on-screen stroke width while zoomed in. A stroke that is already
    /// thicker than this at 1× keeps that width and does not grow further.
    static let displayStrokeScreenCap: CGFloat = 12

    /// On-screen stroke width. Grows with zoom until `displayStrokeScreenCap`, then holds,
    /// so the line and the anchor on it stay a readable size instead of filling the view.
    static func displayStrokeScreenWidth(strokeWidth: CGFloat, scale: CGFloat) -> CGFloat {
        let width = max(strokeWidth, 0)
        let trueScreen = width * max(scale, 0)
        return min(trueScreen, max(width, displayStrokeScreenCap))
    }

    /// Screen length of an anchor that measures `base` points at 1× zoom.
    /// From the floor up to 1× the mark shrinks with the viewport, then holds at `base`.
    /// When `strokeWidth` is set, the square also stays `anchorStrokeClearance` times
    /// the capped on-screen stroke so zooming in does not bury it in the line.
    static func anchorScreenLength(base: CGFloat, scale: CGFloat, strokeWidth: CGFloat = 0) -> CGFloat {
        let designed = base * min(1, max(anchorTrackScaleFloor, scale))
        let strokeScreen = displayStrokeScreenWidth(strokeWidth: strokeWidth, scale: scale)
        return max(designed, strokeScreen * anchorStrokeClearance)
    }

    /// Marquee rectangle from two document-space points. `nil` while the drag is still
    /// small enough to be a tap rather than a deliberate selection box.
    static func marqueeRect(from start: CGPoint, to current: CGPoint, minimumSpan: CGFloat = 0.5) -> CGRect? {
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
        guard rect.width > minimumSpan || rect.height > minimumSpan else { return nil }
        return rect
    }

    /// Puts the anchor at the midpoint of its tangent handle and keeps each arm at least
    /// `minimumLength` away, so a short handle cannot sit on the anchor.
    /// An arm that already clears the gap is kept. A missing or short arm mirrors the
    /// longer one. When both are inside the gap they are pushed out along their tangent,
    /// or along `fallbackDirection` when the handle has no direction yet.
    static func centeredTangentPair(
        inOffset: CGPoint,
        outOffset: CGPoint,
        minimumLength: CGFloat = 0,
        fallbackDirection: CGPoint = .zero
    ) -> (inOffset: CGPoint, outOffset: CGPoint) {
        let minimum = max(minimumLength, 0)
        let inLength = hypot(inOffset.x, inOffset.y)
        let outLength = hypot(outOffset.x, outOffset.y)
        let floor = max(minimum, epsilon)
        if inLength >= floor && outLength >= floor {
            return (inOffset, outOffset)
        }

        let longer = max(inLength, outLength)
        let primary: CGPoint
        if longer >= floor {
            primary = outLength >= inLength
                ? outOffset
                : CGPoint(x: -inOffset.x, y: -inOffset.y)
            return (CGPoint(x: -primary.x, y: -primary.y), primary)
        }

        var direction: CGPoint
        if outLength >= inLength && outLength >= epsilon {
            direction = outOffset
        } else if inLength >= epsilon {
            direction = CGPoint(x: -inOffset.x, y: -inOffset.y)
        } else {
            direction = fallbackDirection
        }
        var directionLength = hypot(direction.x, direction.y)
        if directionLength < epsilon {
            direction = CGPoint(x: 1, y: 0)
            directionLength = 1
        }
        let length = max(longer, minimum)
        let scale = length / directionLength
        let out = CGPoint(x: direction.x * scale, y: direction.y * scale)
        return (CGPoint(x: -out.x, y: -out.y), out)
    }

    /// Direction along the curve through `index`, from the previous anchor toward the next.
    static func tangentAxis(anchors: [CGPoint], index: Int) -> CGPoint {
        guard anchors.indices.contains(index) else { return CGPoint(x: 1, y: 0) }
        let anchor = anchors[index]
        let previous = anchors[max(index - 1, 0)]
        let next = anchors[min(index + 1, anchors.count - 1)]
        let along = CGPoint(x: next.x - previous.x, y: next.y - previous.y)
        if hypot(along.x, along.y) > epsilon {
            return along
        }
        let fromAnchor = CGPoint(x: next.x - anchor.x, y: next.y - anchor.y)
        if hypot(fromAnchor.x, fromAnchor.y) > epsilon {
            return fromAnchor
        }
        return CGPoint(x: 1, y: 0)
    }

    /// Lengthens each arm that is already shorter than `minimumLength`, along its own
    /// direction. A zero arm is a corner and stays zero. Filling it with the opposite
    /// of the other arm would bend a straight edge into the curve it was joined to.
    /// Arms that are already long enough stay put.
    static func tangentHandlesObservingMinimum(
        anchors: [CGPoint],
        handles: [CurveHandle],
        minimumLength: CGFloat = minimumTangentLength
    ) -> [CurveHandle] {
        guard anchors.count == handles.count else { return handles }
        let minimum = max(minimumLength, 0)
        return handles.map { handle in
            CurveHandle(
                inOffset: lengthenedExistingOffset(handle.inOffset, minimum: minimum),
                outOffset: lengthenedExistingOffset(handle.outOffset, minimum: minimum)
            )
        }
    }

    /// Lengthens a tangent that already points somewhere. A zero offset stays zero.
    static func lengthenedExistingOffset(_ offset: CGPoint, minimum: CGFloat) -> CGPoint {
        let length = hypot(offset.x, offset.y)
        if length < epsilon { return .zero }
        if length >= minimum { return offset }
        let scale = minimum / length
        return CGPoint(x: offset.x * scale, y: offset.y * scale)
    }

    /// Lengthens `offset` to `minimum` along its own direction. A zero offset uses `fallback`.
    static func extendedTangentOffset(_ offset: CGPoint, minimum: CGFloat, fallback: CGPoint) -> CGPoint {
        let length = hypot(offset.x, offset.y)
        if length >= minimum && length >= epsilon {
            return offset
        }
        var direction = length >= epsilon ? offset : fallback
        var directionLength = hypot(direction.x, direction.y)
        if directionLength < epsilon {
            direction = CGPoint(x: 1, y: 0)
            directionLength = 1
        }
        let scale = max(minimum, 0) / directionLength
        return CGPoint(x: direction.x * scale, y: direction.y * scale)
    }

    /// Index of the grab circle closest to `point`. Circles that do not contain `point` are skipped.
    /// An equal distance keeps the earlier candidate.
    static func nearestGrab(at point: CGPoint, centers: [CGPoint], radii: [CGFloat]) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for index in centers.indices {
            let radius = index < radii.count ? radii[index] : 0
            guard radius > 0 else { continue }
            let distance = hypot(centers[index].x - point.x, centers[index].y - point.y)
            guard distance <= radius else { continue }
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    /// Screen size of a grab target: at least `minimum`, and wider when the visible
    /// mark is larger so the target never clips the dot.
    static func screenGrabExtent(
        minimum: CGFloat,
        mark: CGFloat,
        scale: CGFloat,
        strokeWidth: CGFloat = 0
    ) -> CGFloat {
        max(minimum, anchorScreenLength(base: mark, scale: scale, strokeWidth: strokeWidth))
    }

    /// A dragged tangent offset that stays `minimumLength` from its anchor and keeps both
    /// the handle and its mirrored opposite outside every obstacle's clearance.
    /// The pair stays one straight line through the anchor. Length is the closest allowed
    /// value to what the finger asked for; a tie keeps the shorter handle.
    static func separatedTangentOffset(
        proposed: CGPoint,
        anchor: CGPoint,
        obstacles: [(point: CGPoint, clearance: CGFloat)],
        minimumLength: CGFloat,
        fallbackDirection: CGPoint
    ) -> CGPoint {
        let minimum = max(minimumLength, 0)
        let proposedLength = hypot(proposed.x, proposed.y)
        var direction = proposedLength >= epsilon ? proposed : fallbackDirection
        var directionLength = hypot(direction.x, direction.y)
        if directionLength < epsilon {
            direction = CGPoint(x: 1, y: 0)
            directionLength = 1
        }
        let ux = direction.x / directionLength
        let uy = direction.y / directionLength
        let target = max(proposedLength, minimum)

        var forbidden: [(CGFloat, CGFloat)] = []
        if minimum > 0 {
            forbidden.append((-.infinity, minimum))
        }
        for obstacle in obstacles {
            let clearance = max(obstacle.clearance, 0)
            guard clearance > 0 else { continue }
            let vx = obstacle.point.x - anchor.x
            let vy = obstacle.point.y - anchor.y
            forbidTangentLength(
                alongX: ux,
                y: uy,
                offsetX: vx,
                offsetY: vy,
                clearance: clearance,
                into: &forbidden
            )
            forbidTangentLength(
                alongX: ux,
                y: uy,
                offsetX: -vx,
                offsetY: -vy,
                clearance: clearance,
                into: &forbidden
            )
        }

        let length = nearestAllowedTangentLength(target, avoiding: forbidden, minimum: minimum)
        return CGPoint(x: ux * length, y: uy * length)
    }

    /// Other anchors and the tangent dots actually drawn for them. The dragged anchor's
    /// own pair is omitted; that pair is the offset being solved.
    static func tangentObstacles(
        anchors: [CGPoint],
        handles: [CurveHandle],
        excluding index: Int,
        anchorClearance: CGFloat,
        handleClearance: CGFloat
    ) -> [(point: CGPoint, clearance: CGFloat)] {
        guard anchors.count == handles.count else { return [] }
        var obstacles: [(point: CGPoint, clearance: CGFloat)] = []
        for (other, anchor) in anchors.enumerated() where other != index {
            obstacles.append((anchor, anchorClearance))
            let handle = handles[other]
            if other > 0 {
                obstacles.append((
                    CGPoint(x: anchor.x + handle.inOffset.x, y: anchor.y + handle.inOffset.y),
                    handleClearance
                ))
            }
            if other < anchors.count - 1 {
                obstacles.append((
                    CGPoint(x: anchor.x + handle.outOffset.x, y: anchor.y + handle.outOffset.y),
                    handleClearance
                ))
            }
        }
        return obstacles
    }

    /// Pulls `proposed` out to the grab floor around each obstacle.
    /// An obstacle the point already overlaps uses that current distance as the floor,
    /// so an existing tight pair can move apart but cannot stack tighter.
    static func separatedPoint(
        proposed: CGPoint,
        current: CGPoint,
        obstacles: [CGPoint],
        minimumDistance: CGFloat
    ) -> CGPoint {
        guard minimumDistance > 0 else { return proposed }
        var point = proposed
        for _ in 0..<4 {
            var changed = false
            for obstacle in obstacles {
                let existing = hypot(current.x - obstacle.x, current.y - obstacle.y)
                let floor = min(existing, minimumDistance)
                guard floor > epsilon else { continue }
                let dx = point.x - obstacle.x
                let dy = point.y - obstacle.y
                let distance = hypot(dx, dy)
                guard distance + epsilon < floor else { continue }
                if distance < epsilon {
                    let fallbackX = current.x - obstacle.x
                    let fallbackY = current.y - obstacle.y
                    let fallback = hypot(fallbackX, fallbackY)
                    if fallback < epsilon {
                        point = CGPoint(x: obstacle.x + floor, y: obstacle.y)
                    } else {
                        point = CGPoint(
                            x: obstacle.x + fallbackX / fallback * floor,
                            y: obstacle.y + fallbackY / fallback * floor
                        )
                    }
                } else {
                    let scale = floor / distance
                    point = CGPoint(x: obstacle.x + dx * scale, y: obstacle.y + dy * scale)
                }
                changed = true
            }
            if !changed { break }
        }
        return point
    }

    private static func forbidTangentLength(
        alongX ux: CGFloat,
        y uy: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat,
        clearance: CGFloat,
        into forbidden: inout [(CGFloat, CGFloat)]
    ) {
        let projection = offsetX * ux + offsetY * uy
        let perpendicular = max(0, offsetX * offsetX + offsetY * offsetY - projection * projection)
        let clearance2 = clearance * clearance
        guard perpendicular < clearance2 else { return }
        let half = sqrt(clearance2 - perpendicular)
        forbidden.append((projection - half, projection + half))
    }

    private static func nearestAllowedTangentLength(
        _ proposed: CGFloat,
        avoiding forbidden: [(CGFloat, CGFloat)],
        minimum: CGFloat
    ) -> CGFloat {
        let blocked = mergedIntervals(forbidden)
        if !intervals(blocked, contain: proposed) {
            return proposed
        }
        var best = CGFloat.infinity
        var bestDistance = CGFloat.infinity
        for interval in blocked where intervals([interval], contain: proposed) {
            for edge in [interval.0, interval.1] where edge.isFinite && edge + epsilon >= minimum {
                let distance = abs(edge - proposed)
                let closer = distance < bestDistance - epsilon
                let tiePrefersShorter = abs(distance - bestDistance) <= epsilon && edge < best
                if closer || tiePrefersShorter {
                    bestDistance = distance
                    best = edge
                }
            }
        }
        return best.isFinite ? best : max(minimum, proposed)
    }

    private static func intervals(_ intervals: [(CGFloat, CGFloat)], contain value: CGFloat) -> Bool {
        intervals.contains { value > $0.0 + epsilon && value < $0.1 - epsilon }
    }

    private static func mergedIntervals(_ intervals: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] {
        var merged: [(CGFloat, CGFloat)] = []
        for interval in intervals.sorted(by: { $0.0 < $1.0 }) where interval.0 < interval.1 {
            if var last = merged.last, interval.0 <= last.1 + epsilon {
                last.1 = max(last.1, interval.1)
                merged[merged.count - 1] = last
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
