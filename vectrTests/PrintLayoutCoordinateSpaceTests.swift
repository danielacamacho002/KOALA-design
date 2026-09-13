import CoreGraphics
import Testing
@testable import vectr

@MainActor
struct PrintLayoutCoordinateSpaceTests {
    @Test func emptyPointsHaveNullBounds() {
        #expect(PrintLayoutCoordinateSpace.boundingRect(for: []) == .null)
    }

    @Test func identityTransformLeavesPointsUnchanged() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 4)]
        let result = PrintLayoutCoordinateSpace.transformedPoints(points, transform: .identity)
        #expect(result == points)
    }

    @Test func translationOffsetsAllPoints() {
        let points = [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)]
        let transform = PrintStrokeTransform(translation: CGPoint(x: 5, y: -3))
        let result = PrintLayoutCoordinateSpace.transformedPoints(points, transform: transform)
        #expect(result == [CGPoint(x: 6, y: -1), CGPoint(x: 8, y: 1)])
    }
}
