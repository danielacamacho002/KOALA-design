//
//  DimensionLabelStyle.swift
//  Koala
//

import SwiftUI

enum DimensionLabelStyle {
    static let font: Font = .caption.weight(.semibold).monospacedDigit()

    /// Gap between the stroke and the inward face of the label cluster.
    static let edgeClearance: CGFloat = 10
    /// Fallback half-size before the cluster has been measured (value + lock + eye).
    static let labeledHalfSize = CGSize(width: 96, height: 18)
    /// Fallback half-size for plain measurement text (live draw / text dims).
    static let textOnlyHalfSize = CGSize(width: 52, height: 12)
    /// Edges shorter than this on screen draw no dimension at all.
    static let minimumDrawableLength: CGFloat = 12

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

/// CAD linear dimension in view space, drawn the same way at every size: extension
/// lines from both endpoints, one unbroken dimension line with arrowheads inside
/// it, and the measurement just past the line on the side away from the edge.
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
    var textCenter: CGPoint
    /// Rotation that keeps the measurement upright along the dimension line.
    var textAngle: CGFloat

    /// `placement` picks the side and the text's distance from the edge.
    /// `textHalfHeight` is the label's half extent perpendicular to the dimension line.
    /// Feeding `textCenter` back in as `placement` reproduces the same layout.
    static func layout(
        start: CGPoint,
        end: CGPoint,
        placement: CGPoint,
        textHalfHeight: CGFloat,
        gap: CGFloat = 3,
        overshoot: CGFloat = 4,
        arrowLength: CGFloat = 8,
        arrowHalfWidth: CGFloat = 3.1,
        minimumLineOffset: CGFloat = DimensionLabelStyle.edgeClearance
    ) -> LinearDimensionLayout? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return nil }

        let along = CGPoint(x: dx / length, y: dy / length)
        let ccw = CGPoint(x: -along.y, y: along.x)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let signed = (placement.x - mid.x) * ccw.x + (placement.y - mid.y) * ccw.y
        let normal = signed >= -0.5 ? ccw : CGPoint(x: -ccw.x, y: -ccw.y)

        let lift = textHalfHeight + overshoot + 2
        let textOffset = max(abs(signed), minimumLineOffset + lift)
        let lineOffset = textOffset - lift

        let dimStart = offsetPoint(start, by: normal, lineOffset)
        let dimEnd = offsetPoint(end, by: normal, lineOffset)
        let center = CGPoint(x: (dimStart.x + dimEnd.x) / 2, y: (dimStart.y + dimEnd.y) / 2)

        let resolvedGap = min(gap, lineOffset * 0.45)
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

        // Arrowheads shrink on short lines so the pair never takes more than half of it.
        let scale = min(1, length / (arrowLength * 4))
        let outward = CGPoint(x: -along.x, y: -along.y)
        let arrows = [
            arrow(tip: dimStart, pointing: outward, length: arrowLength * scale, halfWidth: arrowHalfWidth * scale),
            arrow(tip: dimEnd, pointing: along, length: arrowLength * scale, halfWidth: arrowHalfWidth * scale)
        ]

        var radians = atan2(along.y, along.x)
        if radians > .pi / 2 {
            radians -= .pi
        } else if radians < -.pi / 2 {
            radians += .pi
        }

        return LinearDimensionLayout(
            extensions: extensions,
            shafts: [Segment(start: dimStart, end: dimEnd)],
            arrows: arrows,
            textCenter: offsetPoint(center, by: normal, lift),
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
}

/// Arc-length dimension, same rules as `LinearDimensionLayout`: radial extension
/// lines, one unbroken concentric arc with arrowheads inside it, text just past the arc.
struct ArcDimensionLayout: Equatable {
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
    var arcRuns: [[CGPoint]]
    var arrows: [Arrow]
    var textCenter: CGPoint
    var textAngle: CGFloat

    /// Same contract as `LinearDimensionLayout.layout`; `textHalfHeight` is radial.
    static func layout(
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        sweep: CGFloat,
        placement: CGPoint,
        textHalfHeight: CGFloat,
        gap: CGFloat = 3,
        overshoot: CGFloat = 4,
        arrowLength: CGFloat = 8,
        arrowHalfWidth: CGFloat = 3.1,
        minimumLineOffset: CGFloat = DimensionLabelStyle.edgeClearance
    ) -> ArcDimensionLayout? {
        guard radius > 0.5, abs(sweep) > 0.02 else { return nil }

        let lift = textHalfHeight + overshoot + 2
        let placeRadius = hypot(placement.x - center.x, placement.y - center.y)
        let innerLimit = radius - minimumLineOffset - lift
        let inside = placeRadius + 0.5 < radius && innerLimit >= 12
        let textRadius: CGFloat
        let dimRadius: CGFloat
        if inside {
            textRadius = max(12, min(placeRadius, innerLimit))
            dimRadius = textRadius + lift
        } else {
            textRadius = radius + max(placeRadius - radius, minimumLineOffset + lift)
            dimRadius = textRadius - lift
        }

        let endAngle = startAngle + sweep
        let midAngle = startAngle + sweep / 2
        let radialSign: CGFloat = inside ? -1 : 1
        let resolvedGap = min(gap, abs(dimRadius - radius) * 0.45)
        let innerRadius = max(1, radius + radialSign * resolvedGap)
        let outerRadius = max(1, dimRadius + radialSign * overshoot)

        let extensions = [
            Segment(
                start: point(center, startAngle, innerRadius),
                end: point(center, startAngle, outerRadius)
            ),
            Segment(
                start: point(center, endAngle, innerRadius),
                end: point(center, endAngle, outerRadius)
            )
        ]

        let scale = min(1, abs(sweep) * dimRadius / (arrowLength * 4))
        let arrows = [
            arrow(
                tip: point(center, startAngle, dimRadius),
                pointing: tangent(at: startAngle, along: -sweep),
                length: arrowLength * scale,
                halfWidth: arrowHalfWidth * scale
            ),
            arrow(
                tip: point(center, endAngle, dimRadius),
                pointing: tangent(at: endAngle, along: sweep),
                length: arrowLength * scale,
                halfWidth: arrowHalfWidth * scale
            )
        ]

        let runs = [
            arcRun(center: center, radius: dimRadius, from: startAngle, to: endAngle, sweepDirection: sweep)
        ].compactMap { $0 }

        let tangentMid = tangent(at: midAngle, along: sweep)
        var radians = atan2(tangentMid.y, tangentMid.x)
        if radians > .pi / 2 {
            radians -= .pi
        } else if radians < -.pi / 2 {
            radians += .pi
        }

        return ArcDimensionLayout(
            extensions: extensions,
            arcRuns: runs,
            arrows: arrows,
            textCenter: point(center, midAngle, textRadius),
            textAngle: radians
        )
    }

    private static func point(_ center: CGPoint, _ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    /// Unit tangent. `along` positive walks counterclockwise.
    private static func tangent(at angle: CGFloat, along sweep: CGFloat) -> CGPoint {
        let sign: CGFloat = sweep >= 0 ? 1 : -1
        return CGPoint(x: -sin(angle) * sign, y: cos(angle) * sign)
    }

    private static func arrow(
        tip: CGPoint,
        pointing: CGPoint,
        length: CGFloat,
        halfWidth: CGFloat
    ) -> Arrow {
        let back = CGPoint(x: tip.x - pointing.x * length, y: tip.y - pointing.y * length)
        let perp = CGPoint(x: -pointing.y, y: pointing.x)
        return Arrow(
            tip: tip,
            upper: CGPoint(x: back.x + perp.x * halfWidth, y: back.y + perp.y * halfWidth),
            lower: CGPoint(x: back.x - perp.x * halfWidth, y: back.y - perp.y * halfWidth)
        )
    }

    /// Samples the dimension arc only when `from` still leads `to` along the sweep.
    private static func arcRun(
        center: CGPoint,
        radius: CGFloat,
        from start: CGFloat,
        to end: CGFloat,
        sweepDirection: CGFloat
    ) -> [CGPoint]? {
        let sweep = end - start
        guard sweep * sweepDirection > 0, abs(sweep) * radius > 1 else { return nil }
        let count = max(2, Int(ceil(abs(sweep) * radius / 6)))
        return (0...count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            return point(center, start + sweep * t, radius)
        }
    }
}

extension View {
    /// Plain floating dimension text, similar to Shapr3D — no pill chrome.
    func dimensionLabelAppearance() -> some View {
        font(DimensionLabelStyle.font)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }
}
