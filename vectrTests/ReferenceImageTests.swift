import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct ReferenceImageTests {
    @Test func translatingReferenceImageMovesFrame() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        document.translateReferenceImage(by: CGPoint(x: 10, y: -5), recordUndo: false)
        #expect(document.referenceImageFrame == CGRect(x: 10, y: -5, width: 100, height: 50))
    }

    @Test func scaleReferenceImageAboutCenter() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        document.scaleReferenceImage(sx: 2, sy: 2, about: CGPoint(x: 50, y: 25), recordUndo: false)
        #expect(document.referenceImageFrame == CGRect(x: -50, y: -25, width: 200, height: 100))
    }

    @Test func elementHitPrefersStrokeOverReferenceImage() {
        let document = documentWithImage(frame: CGRect(x: -50, y: -50, width: 100, height: 100))
        let stroke = VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        )
        document.strokes = [stroke]

        #expect(document.elementHit(near: CGPoint(x: 5, y: 0), threshold: 4) == .stroke(stroke.id))
        #expect(document.elementHit(near: CGPoint(x: 0, y: 40), threshold: 4) == .referenceImage)
    }

    @Test func selectingStrokeClearsReferenceImageSelection() {
        let document = documentWithImage(frame: CGRect(x: -50, y: -50, width: 100, height: 100))
        let stroke = VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        )
        document.strokes = [stroke]
        document.selectReferenceImage()
        #expect(document.isReferenceImageSelected)

        document.selectStrokeConsideringGroups(stroke.id)
        #expect(!document.isReferenceImageSelected)
        #expect(document.selectedStrokeID == stroke.id)
    }

    @Test func deletingSelectedImageClearsReferenceData() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        document.selectReferenceImage()
        document.deleteSelectedElements()
        #expect(document.referenceImageData == nil)
        #expect(document.referenceImageFrame == nil)
        #expect(!document.isReferenceImageSelected)
    }

    @Test func codecRoundTripsReferenceImageFrame() throws {
        let document = documentWithImage(frame: CGRect(x: -12, y: 8, width: 64, height: 32))
        let decoded = try DocumentCodec.decode(DocumentCodec.encode(document))
        #expect(decoded.referenceImageData == document.referenceImageData)
        #expect(decoded.referenceImageFrame == CGRect(x: -12, y: 8, width: 64, height: 32))
    }

    @Test func placedReferenceFrameShrinksOversizedImage() {
        let canvas = CGSize(width: 200, height: 100)
        let frame = ImportRouter.placedReferenceFrame(
            imageSize: CGSize(width: 400, height: 400),
            canvasSize: canvas
        )
        #expect(frame.width == 85)
        #expect(frame.height == 85)
        #expect(frame.origin == CGPoint(x: -42.5, y: -42.5))
    }

    @Test func placedReferenceFrameDoesNotUpscale() {
        let frame = ImportRouter.placedReferenceFrame(
            imageSize: CGSize(width: 40, height: 20),
            canvasSize: CGSize(width: 200, height: 100)
        )
        #expect(frame == CGRect(x: -20, y: -10, width: 40, height: 20))
    }

    private func documentWithImage(frame: CGRect) -> VectrDocument {
        let document = VectrDocument()
        document.referenceImageData = Data([0xFF, 0xD8, 0xFF])
        document.referenceImageFrame = frame
        return document
    }
}
