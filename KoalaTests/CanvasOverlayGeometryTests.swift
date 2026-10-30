import CoreGraphics
import Testing
@testable import Koala

@MainActor
struct CanvasOverlayGeometryTests {
    private let box = CGRect(x: 0, y: 0, width: 100, height: 60)

    @Test func cornerHandlesFollowTheOverlayDrawOrder() {
        #expect(CanvasOverlayGeometry.cornerHandles(of: box) == [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 60),
            CGPoint(x: 0, y: 60)
        ])
    }

    @Test func draggingACornerBackToItselfLeavesTheShapeUnscaled() {
        let center = CGPoint(x: box.midX, y: box.midY)
        let corner = CanvasOverlayGeometry.cornerHandles(of: box)[2]
        let distance = CanvasOverlayGeometry.cornerDistance(from: center, to: corner)

        for uniform in [true, false] {
            let factors = CanvasOverlayGeometry.scaleFactors(
                center: center,
                corner: corner,
                dragPoint: corner,
                uniform: uniform,
                originCornerDistance: distance
            )
            #expect(abs(factors.x - 1) < 1e-9)
            #expect(abs(factors.y - 1) < 1e-9)
        }
    }

    @Test func freeScaleTreatsEachAxisIndependently() {
        let center = CGPoint(x: 50, y: 30)
        let corner = CGPoint(x: 100, y: 60)
        let factors = CanvasOverlayGeometry.scaleFactors(
            center: center,
            corner: corner,
            dragPoint: CGPoint(x: 150, y: 45),
            uniform: false,
            originCornerDistance: CanvasOverlayGeometry.cornerDistance(from: center, to: corner)
        )
        #expect(abs(factors.x - 2) < 1e-9)
        #expect(abs(factors.y - 0.5) < 1e-9)
    }

    @Test func uniformScaleUsesRadialDistanceForBothAxes() {
        let center = CGPoint.zero
        let corner = CGPoint(x: 3, y: 4)
        let factors = CanvasOverlayGeometry.scaleFactors(
            center: center,
            corner: corner,
            dragPoint: CGPoint(x: 6, y: 8),
            uniform: true,
            originCornerDistance: CanvasOverlayGeometry.cornerDistance(from: center, to: corner)
        )
        #expect(abs(factors.x - 2) < 1e-9)
        #expect(factors.x == factors.y)
    }

    /// A zero-area box has no corner offset to divide by, so free scale must leave
    /// both axes alone instead of producing NaN.
    @Test func degenerateBoxDoesNotDivideByZero() {
        let point = CGPoint(x: 20, y: 20)
        let factors = CanvasOverlayGeometry.scaleFactors(
            center: point,
            corner: point,
            dragPoint: CGPoint(x: 90, y: 90),
            uniform: false,
            originCornerDistance: CanvasOverlayGeometry.cornerDistance(from: point, to: point)
        )
        #expect(factors.x == 1)
        #expect(factors.y == 1)
    }

    @Test func scalingPointsKeepsTheCenterFixed() {
        let center = CGPoint(x: 10, y: 10)
        let scaled = CanvasOverlayGeometry.scaled(
            points: [center, CGPoint(x: 20, y: 10), CGPoint(x: 10, y: 30)],
            about: center,
            x: 2,
            y: 3
        )
        #expect(scaled == [center, CGPoint(x: 30, y: 10), CGPoint(x: 10, y: 70)])
    }

    @Test func curveHandlesScaleAsOffsetsNotPositions() {
        let handles = [CurveHandle(inOffset: CGPoint(x: -4, y: 2), outOffset: CGPoint(x: 4, y: -2))]
        let scaled = CanvasOverlayGeometry.scaled(handles: handles, x: 2, y: 0.5)
        #expect(scaled == [CurveHandle(inOffset: CGPoint(x: -8, y: 1), outOffset: CGPoint(x: 8, y: -1))])
    }

    /// Dragging a reference-image handle past the center must grow the frame, not
    /// invert it into a negative-size rect.
    @Test func negativeFactorsGrowTheImageFrameInsteadOfFlippingIt() {
        let origin = CGRect(x: 0, y: 0, width: 40, height: 20)
        let frame = CanvasOverlayGeometry.scaledFrame(
            origin: origin,
            center: CGPoint(x: 20, y: 10),
            x: -2,
            y: -1
        )
        #expect(frame == CGRect(x: -20, y: 0, width: 80, height: 20))
    }

    @Test func textScaleIsFlooredSoTextStaysSelectable() {
        let size = CanvasOverlayGeometry.scaledFontSize(
            origin: 24,
            center: .zero,
            dragPoint: CGPoint(x: 0.01, y: 0),
            originDistance: 100
        )
        #expect(size == 4)
    }

    @Test func textScaleTracksTheRadialRatio() {
        let size = CanvasOverlayGeometry.scaledFontSize(
            origin: 24,
            center: CGPoint(x: 10, y: 10),
            dragPoint: CGPoint(x: 10, y: 60),
            originDistance: 25
        )
        #expect(abs(size - 48) < 1e-9)
    }

    @Test func marqueeIsNormalizedRegardlessOfDragDirection() {
        let forward = CanvasOverlayGeometry.marqueeRect(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 25, y: 35))
        let backward = CanvasOverlayGeometry.marqueeRect(from: CGPoint(x: 25, y: 35), to: CGPoint(x: 5, y: 5))
        #expect(forward == CGRect(x: 5, y: 5, width: 20, height: 30))
        #expect(forward == backward)
    }

    /// A tap wiggle is not a selection box.
    @Test func marqueeIsNilBelowTheMinimumSpan() {
        let rect = CanvasOverlayGeometry.marqueeRect(from: .zero, to: CGPoint(x: 0.4, y: 0.4))
        #expect(rect == nil)
    }

    @Test func anchorScreenLengthFloorsWhenZoomedOutAndCapsAtOneX() {
        let base: CGFloat = 6
        let floor = CanvasOverlayGeometry.anchorTrackScaleFloor
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 0) == base * floor)
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: floor) == base * floor)
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 0.75) == base * 0.75)
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 1) == base)
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 4) == base)
        let maxZoom = ViewportTransform.maxScale
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: maxZoom) == base)
    }

    /// A same-colored square has to stay wider than the stroke or it vanishes inside the line.
    /// Past the screen cap both the line and the square hold, so zooming in does not inflate them.
    @Test func anchorScreenLengthStaysWiderThanTheStrokeWhenZoomedIn() {
        let base: CGFloat = 6
        let stroke: CGFloat = 2
        let clearance = CanvasOverlayGeometry.anchorStrokeClearance
        let cap = CanvasOverlayGeometry.displayStrokeScreenCap
        #expect(CanvasOverlayGeometry.displayStrokeScreenWidth(strokeWidth: stroke, scale: 1) == stroke)
        #expect(CanvasOverlayGeometry.displayStrokeScreenWidth(strokeWidth: stroke, scale: 4) == stroke * 4)
        #expect(CanvasOverlayGeometry.displayStrokeScreenWidth(strokeWidth: stroke, scale: 24) == cap)
        #expect(CanvasOverlayGeometry.displayStrokeScreenWidth(strokeWidth: 20, scale: 1) == 20)
        #expect(CanvasOverlayGeometry.displayStrokeScreenWidth(strokeWidth: 20, scale: 24) == 20)
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 1, strokeWidth: stroke) == base)
        let capped = cap * clearance
        #expect(capped > base)
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 8, strokeWidth: stroke) == capped)
        let maxZoom = ViewportTransform.maxScale
        #expect(
            CanvasOverlayGeometry.anchorScreenLength(base: base, scale: maxZoom, strokeWidth: stroke) == capped
        )
    }

    @Test func missingTangentArmIsMirroredSoTheAnchorStaysCentered() {
        let fromOut = CanvasOverlayGeometry.centeredTangentPair(
            inOffset: .zero,
            outOffset: CGPoint(x: 40, y: 10)
        )
        #expect(fromOut.outOffset == CGPoint(x: 40, y: 10))
        #expect(fromOut.inOffset == CGPoint(x: -40, y: -10))

        let fromIn = CanvasOverlayGeometry.centeredTangentPair(
            inOffset: CGPoint(x: 0, y: 24),
            outOffset: .zero
        )
        #expect(fromIn.inOffset == CGPoint(x: 0, y: 24))
        #expect(fromIn.outOffset == CGPoint(x: 0, y: -24))
    }

    @Test func minimumTangentLengthIsAnEighthOfAnInch() {
        #expect(CanvasOverlayGeometry.minimumTangentLength == 9)
    }

    @Test func aShortTangentGrowsToTheMinimumWithoutStretchingALongArm() {
        let handles = CanvasOverlayGeometry.tangentHandlesObservingMinimum(
            anchors: [.zero, CGPoint(x: 100, y: 0)],
            handles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 2, y: 0)),
                CurveHandle(inOffset: CGPoint(x: -80, y: 0), outOffset: .zero)
            ],
            minimumLength: 9
        )
        #expect(abs(handles[0].outOffset.x - 9) < 0.01)
        #expect(handles[0].inOffset == .zero)
        #expect(handles[1].inOffset == CGPoint(x: -80, y: 0))
        #expect(handles[1].outOffset == .zero)
    }

    /// A corner stored with no tangents must stay a corner. Inventing arms along
    /// the chord, or mirroring a neighboring cubic, rounds the point.
    @Test func aCornerWithNoTangentsStaysACorner() {
        let handles = CanvasOverlayGeometry.tangentHandlesObservingMinimum(
            anchors: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 80)
            ],
            handles: [
                CurveHandle(inOffset: CGPoint(x: 40, y: -30), outOffset: .zero),
                CurveHandle(),
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 40, y: 30))
            ]
        )
        #expect(handles[1].inOffset == .zero)
        #expect(handles[1].outOffset == .zero)
        #expect(hypot(handles[0].inOffset.x, handles[0].inOffset.y) > 20)
        #expect(handles[0].outOffset == .zero)
        #expect(handles[2].inOffset == .zero)
        #expect(hypot(handles[2].outOffset.x, handles[2].outOffset.y) > 20)
    }

    @Test func nearestGrabPrefersTheCloserCircle() {
        let index = CanvasOverlayGeometry.nearestGrab(
            at: CGPoint(x: 10, y: 0),
            centers: [.zero, CGPoint(x: 12, y: 0)],
            radii: [30, 30]
        )
        #expect(index == 1)
    }

    @Test func nearestGrabIgnoresACircleThePointIsOutside() {
        let index = CanvasOverlayGeometry.nearestGrab(
            at: CGPoint(x: 100, y: 0),
            centers: [.zero],
            radii: [10]
        )
        #expect(index == nil)
    }

    @Test func aShortHandleIsPushedOutToTheGapAndStaysCentered() {
        let pair = CanvasOverlayGeometry.centeredTangentPair(
            inOffset: CGPoint(x: -2, y: 0),
            outOffset: CGPoint(x: 3, y: 0),
            minimumLength: 36
        )
        #expect(abs(pair.outOffset.x - 36) < 0.01)
        #expect(abs(pair.outOffset.y) < 0.01)
        #expect(pair.inOffset == CGPoint(x: -pair.outOffset.x, y: -pair.outOffset.y))
    }

    @Test func aHandleWithNoDirectionUsesTheFallbackAndClearsTheAnchor() {
        let pair = CanvasOverlayGeometry.centeredTangentPair(
            inOffset: .zero,
            outOffset: .zero,
            minimumLength: 36,
            fallbackDirection: CGPoint(x: 0, y: 8)
        )
        #expect(abs(pair.outOffset.y - 36) < 0.01)
        #expect(abs(pair.outOffset.x) < 0.01)
        #expect(pair.inOffset == CGPoint(x: 0, y: -36))
    }

    @Test func aPairThatAlreadyHasTwoArmsIsNotRewritten() {
        let inOffset = CGPoint(x: -12, y: 4)
        let outOffset = CGPoint(x: 30, y: 8)
        let pair = CanvasOverlayGeometry.centeredTangentPair(inOffset: inOffset, outOffset: outOffset)
        #expect(pair.inOffset == inOffset)
        #expect(pair.outOffset == outOffset)
    }

    @Test func shortTangentDragStopsAtTheMinimumLength() {
        let offset = CanvasOverlayGeometry.separatedTangentOffset(
            proposed: CGPoint(x: 4, y: 0),
            anchor: .zero,
            obstacles: [],
            minimumLength: 36,
            fallbackDirection: CGPoint(x: 0, y: 80)
        )
        #expect(offset == CGPoint(x: 36, y: 0))
    }

    @Test func collapsedTangentUsesTheFallbackDirection() {
        let offset = CanvasOverlayGeometry.separatedTangentOffset(
            proposed: .zero,
            anchor: CGPoint(x: 10, y: 10),
            obstacles: [],
            minimumLength: 36,
            fallbackDirection: CGPoint(x: 0, y: 12)
        )
        #expect(offset == CGPoint(x: 0, y: 36))
    }

    @Test func tangentDragAlreadyClearOfNeighborsIsUnchanged() {
        let proposed = CGPoint(x: 80, y: 0)
        let offset = CanvasOverlayGeometry.separatedTangentOffset(
            proposed: proposed,
            anchor: .zero,
            obstacles: [(point: CGPoint(x: 0, y: 200), clearance: 36)],
            minimumLength: 36,
            fallbackDirection: proposed
        )
        #expect(offset == proposed)
    }

    /// A handle aimed at another grab point stops on the near side of that point's clearance.
    @Test func tangentDragStopsShortOfAnotherHandle() {
        let offset = CanvasOverlayGeometry.separatedTangentOffset(
            proposed: CGPoint(x: 90, y: 0),
            anchor: .zero,
            obstacles: [(point: CGPoint(x: 90, y: 0), clearance: 30)],
            minimumLength: 20,
            fallbackDirection: CGPoint(x: 1, y: 0)
        )
        #expect(abs(offset.x - 60) < 0.01)
        #expect(abs(offset.y) < 0.01)
        #expect(hypot(offset.x - 90, offset.y) >= 30 - 0.01)
    }

    @Test func tangentObstaclesSkipTheDraggedAnchorAndHiddenEndpointHandles() {
        let anchors = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 0)]
        let handles = [
            CurveHandle(inOffset: CGPoint(x: -5, y: 0), outOffset: CGPoint(x: 30, y: 10)),
            CurveHandle(inOffset: CGPoint(x: -20, y: 0), outOffset: CGPoint(x: 20, y: 0)),
            CurveHandle(inOffset: CGPoint(x: -15, y: 8), outOffset: CGPoint(x: 9, y: 0))
        ]
        let obstacles = CanvasOverlayGeometry.tangentObstacles(
            anchors: anchors,
            handles: handles,
            excluding: 1,
            anchorClearance: 36,
            handleClearance: 28
        )
        let points = obstacles.map(\.point)
        #expect(points.contains(anchors[0]))
        #expect(points.contains(CGPoint(x: 30, y: 10)))
        #expect(points.contains(anchors[2]))
        #expect(points.contains(CGPoint(x: 185, y: 8)))
        #expect(!points.contains(anchors[1]))
        #expect(!points.contains(CGPoint(x: -5, y: 0)))
        #expect(!points.contains(CGPoint(x: 209, y: 0)))
    }

    @Test func anchorDragCannotCloseAnExistingGapBelowTheMinimum() {
        let separated = CanvasOverlayGeometry.separatedPoint(
            proposed: CGPoint(x: 80, y: 0),
            current: .zero,
            obstacles: [CGPoint(x: 100, y: 0)],
            minimumDistance: 40
        )
        #expect(abs(separated.x - 60) < 0.01)
        #expect(separated.y == 0)
    }

    /// A pair that is already stacked can be pulled apart. The drag cannot pack it tighter.
    @Test func anchorDragKeepsAnAlreadyTightPairFromGettingTighter() {
        let held = CanvasOverlayGeometry.separatedPoint(
            proposed: CGPoint(x: 95, y: 0),
            current: CGPoint(x: 90, y: 0),
            obstacles: [CGPoint(x: 100, y: 0)],
            minimumDistance: 40
        )
        #expect(abs(held.x - 90) < 0.01)

        let opened = CanvasOverlayGeometry.separatedPoint(
            proposed: CGPoint(x: 50, y: 0),
            current: CGPoint(x: 90, y: 0),
            obstacles: [CGPoint(x: 100, y: 0)],
            minimumDistance: 40
        )
        #expect(opened == CGPoint(x: 50, y: 0))
    }

    /// One axis clearing the threshold is enough: a thin horizontal band is a valid marquee.
    @Test func marqueeSurvivesWhenOnlyOneAxisClearsTheMinimum() {
        let rect = CanvasOverlayGeometry.marqueeRect(from: .zero, to: CGPoint(x: 30, y: 0.1))
        #expect(rect == CGRect(x: 0, y: 0, width: 30, height: 0.1))
    }
}
