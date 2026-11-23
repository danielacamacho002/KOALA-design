import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct UndoSnapshotTests {
    @Test func undoPreservesReferenceImageData() {
        let document = documentWithReferenceImage()
        let image = document.referenceImages[0].data

        document.addStroke(sampleStroke(layerID: document.activeLayerID))
        #expect(document.strokes.count == 1)
        #expect(document.undoRetainedReferenceImageBytes == 0)

        document.undo()
        #expect(document.strokes.isEmpty)
        #expect(document.referenceImages[0].data == image)
        #expect(document.undoRetainedReferenceImageBytes == 0)
    }

    @Test func undoStackNeverClearsReferenceImage() {
        let document = documentWithReferenceImage()
        let image = document.referenceImages[0].data

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
            #expect(document.referenceImages[0].data == image)
        }
        #expect(document.strokes.isEmpty)

        document.redo()
        #expect(document.referenceImages[0].data == image)
        #expect(document.undoRetainedReferenceImageBytes == 0)
    }

    @Test func codecRoundTripKeepsReferenceImageData() throws {
        let document = documentWithReferenceImage()
        let image = document.referenceImages[0].data
        let frame = document.referenceImages[0].frame

        let decoded = try DocumentCodec.decode(try DocumentCodec.encode(document))
        #expect(decoded.referenceImages[0].data == image)
        #expect(decoded.referenceImages[0].frame == frame)
    }

    @Test func undoOfImageMoveDoesNotRetainPayloadBytes() {
        let document = documentWithReferenceImage()
        let original = document.referenceImages[0].frame
        let image = document.referenceImages[0].data
        document.beginInteractiveEdit()
        document.setReferenceImageFrame(original.offsetBy(dx: 10, dy: 4), recordUndo: false)

        #expect(document.undoRetainedReferenceImageBytes == 0)
        document.undo()
        #expect(document.referenceImages[0].frame == original)
        #expect(document.referenceImages[0].data == image)
        #expect(document.undoRetainedReferenceImageBytes == 0)
    }

    @Test func undoRedoRemovePreservesReferenceImageBytes() {
        let document = documentWithReferenceImage()
        let image = document.referenceImages[0].data
        let id = document.referenceImages[0].id

        document.removeReferenceImage()
        #expect(document.referenceImages.isEmpty)
        #expect(document.undoRetainedReferenceImageBytes == 0)

        document.undo()
        #expect(document.referenceImages[0].id == id)
        #expect(document.referenceImages[0].data == image)
        #expect(document.undoRetainedReferenceImageBytes == 0)

        document.redo()
        #expect(document.referenceImages.isEmpty)
        #expect(document.undoRetainedReferenceImageBytes == 0)

        document.undo()
        #expect(document.referenceImages[0].data == image)
    }

    private func documentWithReferenceImage() -> KoalaDocument {
        let document = KoalaDocument()
        document.referenceImages = [
            ReferenceImage(
                layerID: document.activeLayerID,
                data: Data(repeating: 0xAB, count: 4096),
                frame: CGRect(x: 0, y: 0, width: 100, height: 80)
            )
        ]
        return document
    }

    private func sampleStroke(layerID: UUID, points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]) -> VectorStroke {
        VectorStroke(layerID: layerID, points: points)
    }
}
