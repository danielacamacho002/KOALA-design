import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct FillColorEditingTests {
    @Test func selectedClosedShapeTakesFillColor() {
        let document = VectrDocument()
        let stroke = closedSquare(layerID: document.activeLayerID)
        document.addStroke(stroke)
        document.selectedStrokeID = stroke.id
        let before = document.geometryRevision

        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        #expect(document.setSelectedStrokesFillColor(red))
        #expect(document.stroke(with: stroke.id)?.fillColor == red)
        #expect(document.stroke(with: stroke.id)?.fillOpacity == nil)
        #expect(document.selectedFillColorSummary() == .uniform(red))
        #expect(document.geometryRevision == before + 1)
    }

    @Test func defaultGrayFillIsUniformUntilChanged() {
        let document = VectrDocument()
        let stroke = closedSquare(layerID: document.activeLayerID)
        document.addStroke(stroke)
        document.selectedStrokeID = stroke.id

        #expect(document.selectedFillColorSummary() == .uniform(nil))
        #expect(document.representativeSelectedFillColor() == nil)
    }

    @Test func openAndConstructionStrokesAreLeftUnfilled() {
        let document = VectrDocument()
        let open = VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
            isClosed: false
        )
        let construction = VectorStroke(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 8, y: 0),
                CGPoint(x: 8, y: 8),
                CGPoint(x: 0, y: 8)
            ],
            isClosed: true,
            isConstruction: true
        )
        let closed = closedSquare(layerID: document.activeLayerID, origin: CGPoint(x: 20, y: 0))
        document.addStroke(open)
        document.addStroke(construction)
        document.addStroke(closed)
        document.selectedStrokeID = closed.id
        document.selectedStrokeIDs = [open.id, construction.id, closed.id]

        let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        #expect(document.setSelectedStrokesFillColor(blue))
        #expect(document.stroke(with: open.id)?.fillColor == nil)
        #expect(document.stroke(with: construction.id)?.fillColor == nil)
        #expect(document.stroke(with: closed.id)?.fillColor == blue)
    }

    @Test func mixedSelectionBecomesOneColor() {
        let document = VectrDocument()
        let left = closedSquare(layerID: document.activeLayerID)
        let right = closedSquare(layerID: document.activeLayerID, origin: CGPoint(x: 30, y: 0))
        document.addStroke(left)
        document.addStroke(right)

        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let green = CodableColor(red: 0, green: 1, blue: 0, alpha: 1)
        document.selectedStrokeID = left.id
        document.setSelectedStrokesFillColor(red)
        document.selectedStrokeID = right.id
        document.setSelectedStrokesFillColor(green)

        document.selectedStrokeID = left.id
        document.selectedStrokeIDs = [left.id, right.id]
        #expect(document.selectedFillColorSummary() == .mixed)

        #expect(document.setSelectedStrokesFillColor(red))
        #expect(document.stroke(with: left.id)?.fillColor == red)
        #expect(document.stroke(with: right.id)?.fillColor == red)
        #expect(document.selectedFillColorSummary() == .uniform(red))
        #expect(document.setSelectedStrokesFillColor(red) == false)
    }

    @Test func emptySelectionDoesNotChangeFill() {
        let document = VectrDocument()
        let stroke = closedSquare(layerID: document.activeLayerID)
        document.addStroke(stroke)

        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        #expect(document.selectedFillColorSummary() == .none)
        #expect(document.setSelectedStrokesFillColor(red) == false)
        #expect(document.stroke(with: stroke.id)?.fillColor == nil)
    }

    @Test func undoRestoresPreviousFill() {
        let document = VectrDocument()
        let stroke = closedSquare(layerID: document.activeLayerID)
        document.addStroke(stroke)
        document.selectedStrokeID = stroke.id

        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        document.setSelectedStrokesFillColor(red)
        document.setSelectedStrokesFillColor(red)

        document.undo()
        #expect(document.stroke(with: stroke.id)?.fillColor == nil)
        #expect(document.strokes.contains(where: { $0.id == stroke.id }))
    }

    private func closedSquare(layerID: UUID, origin: CGPoint = .zero) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [
                origin,
                CGPoint(x: origin.x + 10, y: origin.y),
                CGPoint(x: origin.x + 10, y: origin.y + 10),
                CGPoint(x: origin.x, y: origin.y + 10)
            ],
            isClosed: true
        )
    }
}
