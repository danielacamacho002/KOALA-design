import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct DimensionLabelCollisionTests {
    private let half = CGSize(width: 50, height: 13)

    /// Top-width and right-height labels on a small 60×40 rectangle in view space.
    private func cornerItems(rightFixed: Bool = false) -> [DimensionLabelCollision.Item] {
        [
            DimensionLabelCollision.Item(
                id: "top",
                geometry: .linear(start: .zero, end: CGPoint(x: 60, y: 0)),
                placement: CGPoint(x: 30, y: -23),
                halfSize: half,
                isFixed: false
            ),
            DimensionLabelCollision.Item(
                id: "right",
                geometry: .linear(start: CGPoint(x: 60, y: 0), end: CGPoint(x: 60, y: 40)),
                placement: CGPoint(x: 83, y: 20),
                halfSize: half,
                isFixed: rightFixed
            )
        ]
    }

    /// Two labels fighting for exactly the same spot.
    private func stackedItems(secondPriority: CGFloat = 0, canHide: Bool = true) -> [DimensionLabelCollision.Item] {
        let edge = DimensionGeometry.linear(start: .zero, end: CGPoint(x: 200, y: 0))
        return [
            DimensionLabelCollision.Item(
                id: "a",
                geometry: edge,
                placement: CGPoint(x: 100, y: -29),
                halfSize: half,
                isFixed: false
            ),
            DimensionLabelCollision.Item(
                id: "b",
                geometry: edge,
                placement: CGPoint(x: 100, y: -29),
                halfSize: half,
                isFixed: false,
                canHide: canHide,
                priority: secondPriority
            )
        ]
    }

    private func footprints(
        _ items: [DimensionLabelCollision.Item],
        _ placements: [String: DimensionLabelCollision.Placement]
    ) throws -> [DimensionLabelCollision.Footprint] {
        try items.map { item in
            try #require(DimensionLabelCollision.footprint(
                item,
                at: placements[item.id]?.point ?? item.placement,
                padding: 2
            ))
        }
    }

    @Test func crowdedCornerLabelsAreNudgedApart() throws {
        let items = cornerItems()
        let before = try footprints(items, [:])
        #expect(DimensionLabelCollision.collides(before[1], with: [before[0]]))

        let placements = DimensionLabelCollision.resolve(items)
        let after = try footprints(items, placements)
        #expect(!DimensionLabelCollision.collides(after[1], with: [after[0]]))
        #expect(placements["top"] == .at(items[0].placement))
        let moved = try #require(placements["right"]?.point)
        #expect(moved.x > 83)
        #expect(abs(moved.y - 20) < 0.01)
    }

    @Test func draggedLabelStaysAndOthersAvoidIt() throws {
        let items = cornerItems(rightFixed: true)
        let placements = DimensionLabelCollision.resolve(items)
        #expect(placements["right"] == .at(items[1].placement))
        let top = try #require(placements["top"]?.point)
        #expect(top.y < -23)
        let after = try footprints(items, placements)
        #expect(!DimensionLabelCollision.collides(after[0], with: [after[1]]))
    }

    /// A label is nudged at most about its own height; past that it hides instead of
    /// stretching its extension lines across the canvas.
    @Test func labelWithNoRoomNearbyIsHidden() {
        let placements = DimensionLabelCollision.resolve(stackedItems())
        #expect(placements["a"] == .at(CGPoint(x: 100, y: -29)))
        #expect(placements["b"] == .hidden)
    }

    @Test func higherPriorityLabelKeepsTheSpot() {
        let placements = DimensionLabelCollision.resolve(stackedItems(secondPriority: 10))
        #expect(placements["b"] == .at(CGPoint(x: 100, y: -29)))
        #expect(placements["a"] == .hidden)
    }

    @Test func labelInUseIsNeverHidden() {
        let placements = DimensionLabelCollision.resolve(stackedItems(canHide: false))
        #expect(placements["b"]?.point != nil)
    }

    @Test func edgeTooSmallOnScreenIsHidden() {
        let items = [
            DimensionLabelCollision.Item(
                id: "tiny",
                geometry: .linear(start: .zero, end: CGPoint(x: 6, y: 0)),
                placement: CGPoint(x: 3, y: -29),
                halfSize: half,
                isFixed: true
            )
        ]
        #expect(DimensionLabelCollision.resolve(items)["tiny"] == .hidden)
    }

    @Test func separatedLabelsAreLeftAlone() {
        let items = [
            DimensionLabelCollision.Item(
                id: "a",
                geometry: .linear(start: .zero, end: CGPoint(x: 200, y: 0)),
                placement: CGPoint(x: 100, y: -29),
                halfSize: half,
                isFixed: false
            ),
            DimensionLabelCollision.Item(
                id: "b",
                geometry: .linear(start: CGPoint(x: 0, y: 400), end: CGPoint(x: 200, y: 400)),
                placement: CGPoint(x: 100, y: 429),
                halfSize: half,
                isFixed: false
            )
        ]
        let placements = DimensionLabelCollision.resolve(items)
        #expect(placements["a"] == .at(items[0].placement))
        #expect(placements["b"] == .at(items[1].placement))
    }

    @Test func segmentCrossingABoxCountsAsOverlap() {
        let box = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        #expect(DimensionLabelCollision.polygonsOverlap([CGPoint(x: -5, y: 5), CGPoint(x: 15, y: 5)], box))
        #expect(!DimensionLabelCollision.polygonsOverlap([CGPoint(x: -5, y: 15), CGPoint(x: 15, y: 15)], box))
    }
}
