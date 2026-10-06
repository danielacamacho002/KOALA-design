import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct MirrorSelectionTests {
    @Test func horizontalMirrorReflectsAcrossTheRightEdge() {
        let document = KoalaDocument()
        let original = VectorStroke(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 40, y: 0),
                CGPoint(x: 10, y: 30)
            ],
            strokeWidth: 1.5,
            isClosed: true,
            shapeType: .polyline
        )
        document.addStroke(original)
        document.setElementSelection(strokeIDs: [original.id], textIDs: [])

        document.mirrorSelectedElements()

        #expect(document.strokes.count == 2)
        let kept = document.stroke(with: original.id)
        #expect(kept?.points == original.points)
        let copy = document.strokes.first { $0.id != original.id }
        #expect(copy.map { document.selectedStrokeIDs == Set([$0.id]) } == true)
        #expect(pointsMatch(copy?.points ?? [], [
            CGPoint(x: 80, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 70, y: 30)
        ]))
    }

    @Test func mirrorWithNothingSelectedLeavesTheDocumentAlone() {
        let document = KoalaDocument()
        let line = VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)],
            strokeWidth: 1.5,
            isClosed: false,
            shapeType: .polyline
        )
        document.addStroke(line)

        document.mirrorSelectedElements()

        #expect(document.strokes.count == 1)
        #expect(document.strokes[0].points == line.points)
    }

    @Test func undoRemovesTheMirroredCopy() {
        let document = KoalaDocument()
        let original = VectorStroke(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 40, y: 0),
                CGPoint(x: 10, y: 30)
            ],
            strokeWidth: 1.5,
            isClosed: true,
            shapeType: .polyline
        )
        document.addStroke(original)
        document.setElementSelection(strokeIDs: [original.id], textIDs: [])

        document.mirrorSelectedElements()
        document.undo()

        #expect(document.strokes.count == 1)
        #expect(document.strokes[0].id == original.id)
        #expect(document.strokes[0].points == original.points)
    }

    private func pointsMatch(_ actual: [CGPoint], _ expected: [CGPoint], tolerance: CGFloat = 0.001) -> Bool {
        guard actual.count == expected.count else { return false }
        return zip(actual, expected).allSatisfy { point, target in
            abs(point.x - target.x) <= tolerance && abs(point.y - target.y) <= tolerance
        }
    }
}
