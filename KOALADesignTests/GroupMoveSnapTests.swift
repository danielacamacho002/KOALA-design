import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct GroupMoveSnapTests {
    @Test func aShortAnchorListKeepsPerAnchorSnap() {
        #expect(!GroupMoveSnap.usesSelectionBounds(anchorCount: 0))
        #expect(!GroupMoveSnap.usesSelectionBounds(anchorCount: GroupMoveSnap.boundsSnapAnchorLimit))
    }

    @Test func aLongAnchorListSnapsTheSelectionBox() {
        #expect(GroupMoveSnap.usesSelectionBounds(anchorCount: GroupMoveSnap.boundsSnapAnchorLimit + 1))
    }

    @Test func selectionReferencesAreTheCornersAndCenter() {
        let bounds = CGRect(x: 0, y: 10, width: 40, height: 20)
        let references = GroupMoveSnap.selectionReferences(in: bounds)
        #expect(references?.center == CGPoint(x: 20, y: 20))
        #expect(references?.origins == [
            CGPoint(x: 0, y: 10),
            CGPoint(x: 40, y: 10),
            CGPoint(x: 40, y: 30),
            CGPoint(x: 0, y: 30),
            CGPoint(x: 20, y: 20)
        ])
    }

    @Test func aNullOrInfiniteBoxHasNoSnapReferences() {
        #expect(GroupMoveSnap.selectionReferences(in: .null) == nil)
        #expect(GroupMoveSnap.selectionReferences(in: .infinite) == nil)
    }
}
