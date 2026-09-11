import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct UndoSnapshotTests {
    @Test func undoPreservesReferenceImageData() {
        let document = documentWithReferenceImage()
        let image = document.referenceImageData
        #expect(image != nil)

        document.addStroke(sampleStroke(layerID: document.activeLayerID))
        #expect(document.strokes.count == 1)
        #expect(document.undoRetainedReferenceImageBytes == 0)

        document.undo()
        #expect(document.strokes.isEmpty)
        #expect(document.referenceImageData == image)
        #expect(document.undoRetainedReferenceImageBytes == 0)
    }

    @Test func undoStackNeverClearsReferenceImage() {
        let document = documentWithReferenceImage()
        let image = document.referenceImageData

        for index in 0..<5 {
            document.addStroke(sampleStroke(
                layerID: document.activeLayerID,
                points: [CGPoint(x: CGFloat(index), y: 0), CGPoint(x: CGFloat(index), y: 10)]
            ))
        }
        #expect(document.strokes.count == 5)
        #expect(document.undoRetainedReferenceImageBytes == 0)

        while document.canUndo {
            document.undo()
            #expect(document.referenceImageData == image)
        }
        #expect(document.strokes.isEmpty)

        document.redo()
        #expect(document.referenceImageData == image)
        #expect(document.undoRetainedReferenceImageBytes == 0)
    }

    @Test func codecRoundTripKeepsReferenceImageData() throws {
        let document = documentWithReferenceImage()
        let image = document.referenceImageData
        let frame = document.referenceImageFrame

        let decoded = try DocumentCodec.decode(try DocumentCodec.encode(document))
        #expect(decoded.referenceImageData == image)
        #expect(decoded.referenceImageFrame == frame)
    }

    private func documentWithReferenceImage() -> VectrDocument {
        let document = VectrDocument()
        document.referenceImageData = Data(repeating: 0xAB, count: 4096)
        document.referenceImageFrame = CGRect(x: 0, y: 0, width: 100, height: 80)
        return document
    }

    private func sampleStroke(layerID: UUID, points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]) -> VectorStroke {
        VectorStroke(layerID: layerID, points: points)
    }
}
