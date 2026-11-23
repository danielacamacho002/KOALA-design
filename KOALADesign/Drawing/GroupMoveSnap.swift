//
//  GroupMoveSnap.swift
//  Koala
//
//  Which points a group translation offers to snap and axis alignment.
//  A large selection snaps as one box so the drag does not test every vertex.
//

import CoreGraphics
import Foundation

struct GroupMoveSnapReferences: Equatable, Sendable {
    var origins: [CGPoint]
    var center: CGPoint
}

enum GroupMoveSnap {
    /// Anchor samples past this count snap and align on the selection box only.
    static let boundsSnapAnchorLimit = 48

    static func usesSelectionBounds(anchorCount: Int) -> Bool {
        anchorCount > boundsSnapAnchorLimit
    }

    /// Four corners plus the center. `nil` when `bounds` cannot be used.
    static func selectionReferences(in bounds: CGRect) -> GroupMoveSnapReferences? {
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.size.width.isFinite, bounds.size.height.isFinite,
              !bounds.isNull, !bounds.isInfinite else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return GroupMoveSnapReferences(
            origins: [
                CGPoint(x: bounds.minX, y: bounds.minY),
                CGPoint(x: bounds.maxX, y: bounds.minY),
                CGPoint(x: bounds.maxX, y: bounds.maxY),
                CGPoint(x: bounds.minX, y: bounds.maxY),
                center
            ],
            center: center
        )
    }
}
