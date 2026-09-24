import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct CopyPastePlacementTests {
    @Test func duplicateStacksTheCopyOnTheOriginal() {
        let document = VectrDocument()
        let original = closedTriangle(on: document.activeLayerID)
        document.addStroke(original)
        document.setElementSelection(strokeIDs: [original.id], textIDs: [])

        document.duplicateSelectedElements(offset: .zero)

        #expect(document.strokes.count == 2)
        let copy = document.strokes.first { $0.id != original.id }
        #expect(copy?.points == original.points)
        #expect(copy.map { document.selectedStrokeIDs == Set([$0.id]) } == true)
        #expect(document.stroke(with: original.id)?.points == original.points)
    }

    @Test func pasteOffsetsByOneGridStep() {
        let document = VectrDocument()
        document.grid.spacing = 20
        let original = closedTriangle(on: document.activeLayerID)
        document.addStroke(original)
        document.setElementSelection(strokeIDs: [original.id], textIDs: [])
        #expect(document.copySelectedElementsToClipboard() == 1)

        let count = document.pasteClipboardToActiveLayer()

        #expect(count == 1)
        #expect(document.strokes.count == 2)
        let copy = document.strokes.first { $0.id != original.id }
        #expect(copy?.points == original.points.map {
            CGPoint(x: $0.x + 20, y: $0.y + 20)
        })
        #expect(document.stroke(with: original.id)?.points == original.points)
    }

    private func closedTriangle(on layerID: UUID) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 40, y: 0),
                CGPoint(x: 10, y: 30)
            ],
            strokeWidth: 1.5,
            isClosed: true,
            shapeType: .polyline
        )
    }
}
