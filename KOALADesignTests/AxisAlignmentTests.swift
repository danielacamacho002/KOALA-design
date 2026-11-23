import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct AxisAlignmentTests {
    private let tolerance: CGFloat = 10
    private let breakaway: CGFloat = 18
    private let joinGap: CGFloat = 16

    @Test func horizontalAlignCorrectsYOnly() {
        var session = AxisAlignmentSession()
        let update = session.update(
            proposed: [CGPoint(x: 0, y: 3)],
            targets: [CGPoint(x: 40, y: 0)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        #expect(update.correction == CGPoint(x: 0, y: -3))
        #expect(update.didLock)
        #expect(update.guides.count == 1)
        #expect(update.guides.first?.axis == .horizontal)
        #expect(update.guides.first?.moving == CGPoint(x: 0, y: 0))
        #expect(update.guides.first?.stationary == CGPoint(x: 40, y: 0))
    }

    @Test func verticalAlignCorrectsXOnly() {
        var session = AxisAlignmentSession()
        let update = session.update(
            proposed: [CGPoint(x: 4, y: 0)],
            targets: [CGPoint(x: 0, y: 50)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        #expect(update.correction == CGPoint(x: -4, y: 0))
        #expect(update.guides.first?.axis == .vertical)
        #expect(update.guides.first?.moving == CGPoint(x: 0, y: 0))
    }

    @Test func nearPointDoesNotJoin() {
        var session = AxisAlignmentSession()
        let update = session.update(
            proposed: [CGPoint(x: 10, y: 3)],
            targets: [CGPoint(x: 0, y: 0)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        #expect(update.correction == .zero)
        #expect(update.guides.isEmpty)
        #expect(!update.didLock)
    }

    @Test func sameTargetKeepsOnlyTheCloserAxis() {
        var session = AxisAlignmentSession()
        let update = session.update(
            proposed: [CGPoint(x: 4, y: 6)],
            targets: [CGPoint(x: 0, y: 0)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: 2,
            allowed: [.horizontal, .vertical]
        )

        #expect(update.correction == CGPoint(x: -4, y: 0))
        #expect(update.guides.count == 1)
        #expect(update.guides.first?.axis == .vertical)
        #expect(update.guides.first?.moving == CGPoint(x: 0, y: 6) as CGPoint?)
    }

    @Test func twoTargetsAlignBothAxes() {
        var session = AxisAlignmentSession()
        let update = session.update(
            proposed: [CGPoint(x: 0, y: 2)],
            targets: [CGPoint(x: 50, y: 0), CGPoint(x: 0.5, y: 80)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        #expect(update.correction == CGPoint(x: 0.5, y: -2))
        #expect(update.guides.count == 2)
    }

    @Test func outsideToleranceStaysFree() {
        var session = AxisAlignmentSession()
        let update = session.update(
            proposed: [CGPoint(x: 0, y: 30)],
            targets: [CGPoint(x: 40, y: 0)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        #expect(update.correction == .zero)
        #expect(update.guides.isEmpty)
    }

    @Test func lockStaysUntilBreakaway() {
        var session = AxisAlignmentSession()
        _ = session.update(
            proposed: [CGPoint(x: 0, y: 4)],
            targets: [CGPoint(x: 40, y: 0)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        let held = session.update(
            proposed: [CGPoint(x: 0, y: 5)],
            targets: [CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 4)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        #expect(held.correction == CGPoint(x: 0, y: -5))
        #expect(!held.didLock)
        #expect(held.guides.first?.stationary == CGPoint(x: 40, y: 0))
    }

    @Test func breakawayReleases() {
        var session = AxisAlignmentSession()
        _ = session.update(
            proposed: [CGPoint(x: 0, y: 4)],
            targets: [CGPoint(x: 40, y: 0)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        let released = session.update(
            proposed: [CGPoint(x: 0, y: 30)],
            targets: [CGPoint(x: 40, y: 0)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        #expect(released.correction == .zero)
        #expect(released.guides.isEmpty)
    }

    @Test func disallowedAxisIsIgnored() {
        var session = AxisAlignmentSession()
        let update = session.update(
            proposed: [CGPoint(x: 0, y: 3)],
            targets: [CGPoint(x: 40, y: 0)],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.vertical]
        )

        #expect(update.correction == .zero)
        #expect(update.guides.isEmpty)
    }

    @Test func emptyTargetsLeaveTheMoveFree() {
        var session = AxisAlignmentSession()
        let update = session.update(
            proposed: [CGPoint(x: 0, y: 3)],
            targets: [],
            tolerance: tolerance,
            breakaway: breakaway,
            joinGap: joinGap,
            allowed: [.horizontal, .vertical]
        )

        #expect(update.correction == .zero)
        #expect(!update.didLock)
    }

    @Test func rectanglePublishesCornersCenterAndMidpoints() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 0),
                CGPoint(x: 10, y: 10),
                CGPoint(x: 0, y: 10)
            ],
            isClosed: true,
            shapeType: .rectangle
        )

        let points = AxisAlignmentPoints.points(on: stroke)

        #expect(points.contains(CGPoint(x: 0, y: 0)))
        #expect(points.contains(CGPoint(x: 5, y: 5)))
        #expect(points.contains(CGPoint(x: 5, y: 0)))
        #expect(points.contains(CGPoint(x: 10, y: 5)))
    }

    @Test func angleSnapHonorsTheAllowedAxis() {
        let grid = GridSettings()
        let nearlyHorizontal = CGPoint(x: 100, y: 4)
        let nearlyVertical = CGPoint(x: 4, y: 100)

        let horizontal = snapDrawingAngle(
            nearlyHorizontal,
            origin: .zero,
            grid: grid,
            scale: 1,
            allowed: [.horizontal]
        )
        #expect(horizontal.isLocked)
        #expect(horizontal.point == CGPoint(x: 100, y: 0))

        let horizontalOff = snapDrawingAngle(
            nearlyHorizontal,
            origin: .zero,
            grid: grid,
            scale: 1,
            allowed: [.vertical]
        )
        #expect(!horizontalOff.isLocked)
        #expect(horizontalOff.point == nearlyHorizontal)

        let vertical = snapDrawingAngle(
            nearlyVertical,
            origin: .zero,
            grid: grid,
            scale: 1,
            allowed: [.vertical]
        )
        #expect(vertical.isLocked)
        #expect(vertical.point == CGPoint(x: 0, y: 100))

        let neither = snapDrawingAngle(
            nearlyHorizontal,
            origin: .zero,
            grid: grid,
            scale: 1,
            allowed: []
        )
        #expect(!neither.isLocked)
        #expect(neither.point == nearlyHorizontal)
    }

    @Test func drawingAxisMatchesPinnedSegments() {
        #expect(drawingAxis(from: .zero, to: CGPoint(x: 20, y: 0)) == .horizontal)
        #expect(drawingAxis(from: .zero, to: CGPoint(x: 0, y: 20)) == .vertical)
        #expect(drawingAxis(from: .zero, to: CGPoint(x: 20, y: 20)) == nil)
        #expect(drawingAxis(from: .zero, to: CGPoint(x: 4, y: 0), minimumLength: 12) == nil)
        #expect(drawingAxis(from: .zero, to: .zero) == nil)
    }
}
