import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct PencilLiftEndPointTests {
    @Test func keepsPointWithinThreshold() {
        let last = CGPoint(x: 10, y: 20)
        let proposed = CGPoint(x: 10 + 7, y: 20)
        let kept = pencilLiftEndPoint(proposed: proposed, lastPreview: last, scale: 1)
        #expect(kept == proposed)
    }

    @Test func rejectsSidewaysJumpBeyondThreshold() {
        let last = CGPoint(x: 10, y: 20)
        let proposed = CGPoint(x: 10 + 20, y: 20)
        let kept = pencilLiftEndPoint(proposed: proposed, lastPreview: last, scale: 1)
        #expect(kept == last)
    }

    @Test func shortStrokeWithoutPreviewUsesEndedPoint() {
        let proposed = CGPoint(x: 40, y: 5)
        let kept = pencilLiftEndPoint(proposed: proposed, lastPreview: nil, scale: 2)
        #expect(kept == proposed)
    }
}
