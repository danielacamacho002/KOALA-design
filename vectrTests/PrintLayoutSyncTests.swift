import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct PrintLayoutSyncTests {
    @Test func deleteAfterCutRemovesPrintPieces() {
        let document = VectrDocument()
        let stroke = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 100), CGPoint(x: 80, y: 100)]
        )
        document.addStroke(stroke)

        let cut = document.cutAlongNearestPrintBorder(near: CGPoint(x: 18, y: 100), threshold: 40)
        #expect(cut)
        #expect(!document.printPieces.isEmpty)
        #expect(document.printHiddenStrokeIDs.contains(stroke.id))

        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])
        document.deleteSelectedElements()

        #expect(document.printPieces.isEmpty)
        #expect(document.printHiddenStrokeIDs.isEmpty)
        #expect(!document.printLayoutStrokes().contains { $0.id == stroke.id })
        #expect(document.printPieceSourceIDs.isEmpty)
    }

    @Test func joinAfterCutReplacesPrintPiecesWithFusedStroke() {
        let document = VectrDocument()
        let left = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 100), CGPoint(x: 40, y: 100)]
        )
        let right = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 40, y: 100), CGPoint(x: 80, y: 100)]
        )
        document.addStroke(left)
        document.addStroke(right)

        #expect(document.cutAlongNearestPrintBorder(near: CGPoint(x: 18, y: 100), threshold: 40))
        let pieceIDsBeforeJoin = Set(document.printPieces.map(\.id))
        #expect(!pieceIDsBeforeJoin.isEmpty)

        document.setElementSelection(strokeIDs: [left.id, right.id], textIDs: [])
        #expect(document.joinSelectedShapes())

        #expect(document.printPieces.isEmpty)
        #expect(document.printHiddenStrokeIDs.isEmpty)
        #expect(document.strokes.contains { pieceIDsBeforeJoin.contains($0.id) } == false)
        #expect(document.printLayoutStrokes().count == 1)
        #expect(document.printLayoutStrokes().contains { $0.id == left.id } == false)
        #expect(document.printLayoutStrokes().contains { $0.id == right.id } == false)
    }

    @Test func printPieceSourceIDsRoundTripAndMissingKey() throws {
        let document = VectrDocument()
        let source = UUID()
        let piece = UUID()
        document.printPieceSourceIDs = [piece: source]

        let encoded = try DocumentCodec.encode(document)
        let decoded = try DocumentCodec.decode(encoded)
        #expect(decoded.printPieceSourceIDs[piece] == source)

        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "printPieceSourceIDs")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let legacy = try DocumentCodec.decode(stripped)
        #expect(legacy.printPieceSourceIDs.isEmpty)
    }

    @Test func cutOnlySlicesTheTappedStroke() {
        let document = VectrDocument()
        let near = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 100), CGPoint(x: 80, y: 100)]
        )
        let far = makePolyline(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 400), CGPoint(x: 80, y: 400)]
        )
        document.addStroke(near)
        document.addStroke(far)
        var settings = document.printLayout
        settings.activeTool = .cut
        document.printLayout = settings

        #expect(document.cutAlongNearestPrintBorder(near: CGPoint(x: 18, y: 100), threshold: 40))

        #expect(document.printHiddenStrokeIDs.contains(near.id))
        #expect(!document.printHiddenStrokeIDs.contains(far.id))
        #expect(document.printLayoutStrokes().contains { $0.id == far.id })
        #expect(document.printPieces.count == 2)
        #expect(document.printPieces.allSatisfy { document.printPieceSourceIDs[$0.id] == near.id })
        #expect(document.printLayout.activeTool == .cut)
        #expect(document.printSelectedStrokeIDs.count == 2)
    }

    private func makePolyline(layerID: UUID, points: [CGPoint]) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: points,
            strokeWidth: 1.5,
            isClosed: false,
            shapeType: .polyline
        )
    }
}

@MainActor
struct PrintSliceEngineTests {
    @Test func nearestCrossingSplitsOnlyTheTappedIntersection() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 50),
                CGPoint(x: 0, y: 50)
            ],
            strokeWidth: 1.5,
            isClosed: false,
            shapeType: .polyline
        )

        let all = PrintSliceEngine.slice(stroke, axis: .vertical, coordinate: 18)
        #expect(all?.count == 3)

        let nearest = PrintSliceEngine.slice(
            stroke,
            axis: .vertical,
            coordinate: 18,
            nearestCrossingTo: CGPoint(x: 18, y: 0)
        )
        #expect(nearest?.count == 2)

        let spansSecondCrossing = nearest?.contains { piece in
            let xs = piece.points.map(\.x)
            guard let minX = xs.min(), let maxX = xs.max() else { return false }
            return minX < 18 && maxX > 18 && piece.points.contains { abs($0.y - 50) < 0.01 }
        }
        #expect(spansSecondCrossing == true)
    }

    @Test func sliceReturnsNilWhenStrokeDoesNotCross() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [CGPoint(x: 40, y: 0), CGPoint(x: 80, y: 0)],
            strokeWidth: 1.5,
            isClosed: false,
            shapeType: .polyline
        )
        #expect(PrintSliceEngine.slice(stroke, axis: .vertical, coordinate: 18) == nil)
    }
}
