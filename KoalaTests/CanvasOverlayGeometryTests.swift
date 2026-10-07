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

    @Test func anchorScreenLengthFloorsBelowOneXAndKeepsGrowingAtMaxZoom() {
        let base: CGFloat = 6
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 0) == base)
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 0.5) == base)
        #expect(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 1) == base)
        #expect(abs(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: 4) - 24) < 1e-9)
        let maxZoom = ViewportTransform.maxScale
        #expect(abs(CanvasOverlayGeometry.anchorScreenLength(base: base, scale: maxZoom) - base * maxZoom) < 1e-9)
    }

    /// One axis clearing the threshold is enough: a thin horizontal band is a valid marquee.
    @Test func marqueeSurvivesWhenOnlyOneAxisClearsTheMinimum() {
        let rect = CanvasOverlayGeometry.marqueeRect(from: .zero, to: CGPoint(x: 30, y: 0.1))
        #expect(rect == CGRect(x: 0, y: 0, width: 30, height: 0.1))
    }
}
