//
//  DimensionLabelStyle.swift
//  vectr
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

extension View {
    /// Plain floating dimension text, similar to Shapr3D — no pill chrome.
    func dimensionLabelAppearance(locked: Bool = false) -> some View {
        font(DimensionLabelStyle.font)
            .foregroundStyle(DimensionLabelStyle.foregroundColor(locked: locked))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }
}
