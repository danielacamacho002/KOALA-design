//
//  DimensionLabelStyle.swift
//  Koala
//

import SwiftUI

enum DimensionLabelStyle {
    static let font: Font = .caption.weight(.semibold).monospacedDigit()

    /// Gap between the stroke and the inward face of the label cluster.
    static let edgeClearance: CGFloat = 10
    /// Fallback half-size before the cluster has been measured (value + lock).
    static let labeledHalfSize = CGSize(width: 80, height: 18)
    /// Fallback half-size for plain measurement text (live draw / text dims).
    static let textOnlyHalfSize = CGSize(width: 52, height: 12)

    static func foregroundColor(locked: Bool) -> Color {
        locked ? Color.secondary : Color.accentColor
    }

    /// Unit outward direction from `anchor` toward `preferred`, falling back to up.
    static func outwardUnit(preferred: CGPoint, from anchor: CGPoint) -> CGPoint {
        let dx = preferred.x - anchor.x
        let dy = preferred.y - anchor.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return CGPoint(x: 0, y: -1) }
        return CGPoint(x: dx / length, y: dy / length)
    }

    /// Places the **center** of a label so its inward face clears the stroke.
    /// Distance is view-space only (ignores document standoff magnitude) so wide
    /// side labels — especially right-edge value+lock rows — never sit on the border.
    static func outsideLabelCenter(
        preferred: CGPoint,
        from anchor: CGPoint,
        halfSize: CGSize = labeledHalfSize
    ) -> CGPoint {
        let n = outwardUnit(preferred: preferred, from: anchor)
        let halfExtent = abs(n.x) * halfSize.width + abs(n.y) * halfSize.height
        let distance = edgeClearance + halfExtent
        return CGPoint(
            x: anchor.x + n.x * distance,
            y: anchor.y + n.y * distance
        )
    }

    /// Leader endpoint on the label box, on the same side as the label. Uses the
    /// actual AABB hit so the line stops at the number instead of a padded gap,
    /// and never overshoots the anchor (which used to flip the line inside).
    static func leaderEnd(
        from anchor: CGPoint,
        to labelCenter: CGPoint,
        halfSize: CGSize
    ) -> CGPoint {
        let dx = labelCenter.x - anchor.x
        let dy = labelCenter.y - anchor.y
        let distance = hypot(dx, dy)
        guard distance > 0.001 else { return labelCenter }

        let nx = dx / distance
        let ny = dy / distance
        let toBoxEdge = aabbDistance(halfSize: halfSize, along: CGPoint(x: nx, y: ny))
        let gap: CGFloat = 1
        // Stay between the anchor and the label so a close drag cannot cross the edge.
        let maxPullback = max(0, distance - 2)
        let pullback = min(toBoxEdge + gap, maxPullback)
        return CGPoint(
            x: labelCenter.x - nx * pullback,
            y: labelCenter.y - ny * pullback
        )
    }

    /// Center of a linear dimension label, offset from an edge along `preferred`.
    /// Distance is the clearance plus the label's half-height perpendicular to the edge.
    static func linearPlacement(
        midpoint: CGPoint,
        preferred: CGPoint,
        perpendicularHalf: CGFloat
    ) -> CGPoint {
        let n = outwardUnit(preferred: preferred, from: midpoint)
        let distance = edgeClearance + perpendicularHalf
        return CGPoint(
            x: midpoint.x + n.x * distance,
            y: midpoint.y + n.y * distance
        )
    }

    /// Distance from a box center to its boundary along a unit direction.
    private static func aabbDistance(halfSize: CGSize, along direction: CGPoint) -> CGFloat {
        let tx = abs(direction.x) > 0.001
            ? halfSize.width / abs(direction.x)
            : CGFloat.greatestFiniteMagnitude
        let ty = abs(direction.y) > 0.001
            ? halfSize.height / abs(direction.y)
            : CGFloat.greatestFiniteMagnitude
        return min(tx, ty)
    }
}

/// CAD linear dimension in view space: extension lines from both endpoints,
/// a parallel dimension line with arrowheads, and a gap for the measurement.
struct LinearDimensionLayout: Equatable {
    struct Segment: Equatable {
        var start: CGPoint
        var end: CGPoint
    }

    struct Arrow: Equatable {
        var tip: CGPoint
        var upper: CGPoint
        var lower: CGPoint
    }

    var extensions: [Segment]
    var shafts: [Segment]
    var arrows: [Arrow]
    /// Center of the measurement, on the dimension line.
    var textCenter: CGPoint
    /// Rotation that keeps the measurement upright along the dimension line.
    var textAngle: CGFloat

    static func layout(
        start: CGPoint,
        end: CGPoint,
        placement: CGPoint,
        textGap: CGFloat,
        minimumOffset: CGFloat,
        gap: CGFloat = 3,
        overshoot: CGFloat = 5,
        arrowLength: CGFloat = 8,
        arrowHalfWidth: CGFloat = 3.1
    ) -> LinearDimensionLayout? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return nil }

        let along = CGPoint(x: dx / length, y: dy / length)
        let ccw = CGPoint(x: -along.y, y: along.x)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let toPlacement = CGPoint(x: placement.x - mid.x, y: placement.y - mid.y)
        let signed = toPlacement.x * ccw.x + toPlacement.y * ccw.y

        let normal: CGPoint
        let offset: CGFloat
        if abs(signed) < 0.5 {
            normal = ccw
            offset = minimumOffset
        } else if signed > 0 {
            normal = ccw
            offset = max(signed, minimumOffset)
        } else {
            normal = CGPoint(x: -ccw.x, y: -ccw.y)
            offset = max(-signed, minimumOffset)
        }

        let dimStart = offsetPoint(start, by: normal, offset)
        let dimEnd = offsetPoint(end, by: normal, offset)
        let center = CGPoint(x: (dimStart.x + dimEnd.x) / 2, y: (dimStart.y + dimEnd.y) / 2)

        let resolvedGap = min(gap, offset * 0.45)
        let extensions = [
            Segment(
                start: offsetPoint(start, by: normal, resolvedGap),
                end: offsetPoint(dimStart, by: normal, overshoot)
            ),
            Segment(
                start: offsetPoint(end, by: normal, resolvedGap),
                end: offsetPoint(dimEnd, by: normal, overshoot)
            )
        ]

        let inward = along
        let outward = CGPoint(x: -along.x, y: -along.y)
        let gapStart = offsetPoint(center, by: inward, -textGap)
        let gapEnd = offsetPoint(center, by: inward, textGap)
        let arrowsOutside = length < textGap * 2 + arrowLength * 2 + 8

        let arrows: [Arrow]
        let shafts: [Segment]
        if arrowsOutside {
            arrows = [
                arrow(tip: dimStart, pointing: inward, length: arrowLength, halfWidth: arrowHalfWidth),
                arrow(tip: dimEnd, pointing: outward, length: arrowLength, halfWidth: arrowHalfWidth)
            ]
            shafts = [
                shaft(from: dimStart, to: gapStart, along: inward),
                shaft(from: gapEnd, to: dimEnd, along: inward)
            ].compactMap { $0 }
        } else {
            arrows = [
                arrow(tip: dimStart, pointing: outward, length: arrowLength, halfWidth: arrowHalfWidth),
                arrow(tip: dimEnd, pointing: inward, length: arrowLength, halfWidth: arrowHalfWidth)
            ]
            shafts = [
                shaft(from: offsetPoint(dimStart, by: inward, arrowLength), to: gapStart, along: inward),
                shaft(from: gapEnd, to: offsetPoint(dimEnd, by: inward, -arrowLength), along: inward)
            ].compactMap { $0 }
        }

        var radians = atan2(along.y, along.x)
        if radians > .pi / 2 {
            radians -= .pi
        } else if radians < -.pi / 2 {
            radians += .pi
        }

        return LinearDimensionLayout(
            extensions: extensions,
            shafts: shafts,
            arrows: arrows,
            textCenter: center,
            textAngle: radians
        )
    }

    private static func offsetPoint(_ point: CGPoint, by direction: CGPoint, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + direction.x * distance, y: point.y + direction.y * distance)
    }

    private static func arrow(
        tip: CGPoint,
        pointing: CGPoint,
        length: CGFloat,
        halfWidth: CGFloat
    ) -> Arrow {
        let back = offsetPoint(tip, by: pointing, -length)
        let perp = CGPoint(x: -pointing.y, y: pointing.x)
        return Arrow(
            tip: tip,
            upper: offsetPoint(back, by: perp, halfWidth),
            lower: offsetPoint(back, by: perp, -halfWidth)
        )
    }

    private static func shaft(from: CGPoint, to: CGPoint, along: CGPoint) -> Segment? {
        let vx = to.x - from.x
        let vy = to.y - from.y
        guard vx * along.x + vy * along.y > 1 else { return nil }
        return Segment(start: from, end: to)
    }
}

extension View {
    /// Plain floating dimension text, similar to Shapr3D — no pill chrome.
    func dimensionLabelAppearance(locked: Bool = false) -> some View {
        font(DimensionLabelStyle.font)
            .foregroundStyle(DimensionLabelStyle.foregroundColor(locked: locked))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }
}
