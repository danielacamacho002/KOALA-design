//
//  MoveAxisLock.swift
//  Koala
//
//  Pure axis-lock math for Move-tool translation. Shared by the design canvas
//  overlay and unit tests; print layout keeps an equivalent private copy.
//

import CoreGraphics
import Foundation

/// Axis a Move drag is constrained to after the lock threshold.
enum MoveDragAxis: Equatable, Sendable {
    case free
    case horizontal
    case vertical
}

enum MoveAxisLock {
    /// View-space movement (points) before the drag locks onto an axis.
    static let thresholdPoints: CGFloat = 10

    /// Sticky axis resolution from a finger/Pencil translation in view points.
    /// Once horizontal or vertical is chosen, it stays for the rest of the drag.
    /// An exact |dx| == |dy| tie prefers vertical (matches print layout).
    static func resolvedAxis(
        current: MoveDragAxis,
        viewTranslation: CGSize,
        enabled: Bool
    ) -> MoveDragAxis {
        guard enabled else { return .free }
        if current != .free { return current }
        let distance = hypot(viewTranslation.width, viewTranslation.height)
        guard distance > thresholdPoints else { return .free }
        return abs(viewTranslation.width) > abs(viewTranslation.height)
            ? .horizontal
            : .vertical
    }

    /// Zeros the off-axis component of a document-space translation delta.
    static func constrainedDelta(_ delta: CGPoint, axis: MoveDragAxis) -> CGPoint {
        switch axis {
        case .free:
            return delta
        case .horizontal:
            return CGPoint(x: delta.x, y: 0)
        case .vertical:
            return CGPoint(x: 0, y: delta.y)
        }
    }
}
