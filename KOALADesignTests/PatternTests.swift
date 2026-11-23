import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct PatternTests {
    /// Two 10×10 squares, 10 apart, grouped. Selecting one member selects the group.
    private func groupedPair(in document: KoalaDocument) -> (VectorStroke, VectorStroke) {
        let left = square(layerID: document.activeLayerID, x: 0)
        let right = square(layerID: document.activeLayerID, x: 20)
        document.addStroke(left)
        document.addStroke(right)
        document.groups = [ObjectGroup(strokeIDs: [left.id, right.id])]
        document.setElementSelection(strokeIDs: [left.id], textIDs: [])
        return (left, right)
    }

    @Test func gridPatternsTheWholeGroupAndRegroupsEachCopy() {
        let document = KoalaDocument()
        let (left, right) = groupedPair(in: document)
        var settings = PatternSettings()
        settings.mode = .grid
        settings.rows = 1
        settings.columns = 3
        settings.spacingX = 5

        #expect(document.applyPattern(settings: settings) == .success(created: 3))

        #expect(document.strokes.count == 6)
        #expect(document.stroke(with: left.id) == nil)
        #expect(document.stroke(with: right.id) == nil)
        #expect(document.groups.count == 3)
        #expect(document.groups.allSatisfy { $0.strokeIDs.count == 2 })

        // Group is 30 wide, so copies step 35 apart and keep their internal spacing.
        let minXs = document.groups.compactMap { group -> CGFloat? in
            let members = group.strokeIDs.compactMap { document.stroke(with: $0) }
            let rect = PatternEngine.boundingRect(for: PatternEngine.Source(strokes: members))
            #expect(abs(rect.width - 30) < 0.001)
            return rect.minX
        }.sorted()
        #expect(minXs.count == 3)
        #expect(abs(minXs[0] - 0) < 0.001)
        #expect(abs(minXs[1] - 35) < 0.001)
        #expect(abs(minXs[2] - 70) < 0.001)
    }

    @Test func radialWithoutKeepOriginalMovesTheSourceGroupIntact() {
        let document = KoalaDocument()
        let (left, right) = groupedPair(in: document)
        var settings = PatternSettings()
        settings.mode = .radial
        settings.count = 3
        settings.keepOriginal = false
        settings.rotateCopies = true

        #expect(document.applyPattern(settings: settings) == .success(created: 3))

        #expect(document.strokes.count == 6)
        #expect(document.groups.count == 3)
        #expect(document.groups.contains { Set($0.strokeIDs) == [left.id, right.id] })
        #expect(document.selectedStrokeIDs == [left.id, right.id])
    }

    @Test func ungroupedShapeStillPatternsAlone() {
        let document = KoalaDocument()
        let shape = square(layerID: document.activeLayerID, x: 0)
        document.addStroke(shape)
        document.setElementSelection(strokeIDs: [shape.id], textIDs: [])
        var settings = PatternSettings()
        settings.mode = .linear
        settings.count = 2
        settings.spacingX = 5

        #expect(document.applyPattern(settings: settings) == .success(created: 2))
        #expect(document.strokes.count == 2)
        #expect(document.groups.isEmpty)
    }

    private func square(layerID: UUID, x: CGFloat) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: x, y: 0),
                CGPoint(x: x + 10, y: 0),
                CGPoint(x: x + 10, y: 10),
                CGPoint(x: x, y: 10)
            ],
            isClosed: true
        )
    }
}
