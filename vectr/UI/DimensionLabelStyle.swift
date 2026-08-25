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
