import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct ReferenceImageTransformTests {
    @Test func tapInsideFrameSelectsImage() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        let id = document.referenceImages[0].id

        #expect(document.elementHit(near: CGPoint(x: 40, y: 20), threshold: 4) == .referenceImage(id))
        #expect(document.selectElement(near: CGPoint(x: 40, y: 20), threshold: 4) == .referenceImage(id))
        #expect(document.isReferenceImageSelected)
        #expect(document.selectedReferenceImageID == id)
        #expect(document.selectedStrokeID == nil)
    }

    @Test func strokeOverImageWinsHitTest() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let imageID = document.referenceImages[0].id
        let stroke = VectorStroke(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 10, y: 10),
                CGPoint(x: 40, y: 10),
                CGPoint(x: 40, y: 40),
                CGPoint(x: 10, y: 40)
            ],
            isClosed: true
        )
        document.addStroke(stroke)

        let hit = document.elementHit(near: CGPoint(x: 25, y: 25), threshold: 4)
        #expect(hit == .stroke(stroke.id))
        #expect(document.elementHit(near: CGPoint(x: 80, y: 80), threshold: 4) == .referenceImage(imageID))
    }

    @Test func laterImageWinsWhenOverlapping() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let backID = document.referenceImages[0].id
        document.referenceImages.append(
            ReferenceImage(
                layerID: document.activeLayerID,
                data: Data([0x02]),
                frame: CGRect(x: 20, y: 20, width: 40, height: 40)
            )
        )
        let frontID = document.referenceImages[1].id

        #expect(document.elementHit(near: CGPoint(x: 30, y: 30), threshold: 4) == .referenceImage(frontID))
        #expect(document.elementHit(near: CGPoint(x: 10, y: 10), threshold: 4) == .referenceImage(backID))
    }

    @Test func secondImportAppendsInsteadOfReplacing() throws {
        let document = KoalaDocument()
        let first = ImportRouter.ImportedContent(
            referenceImages: [ReferenceImage(data: Data([0x01]), frame: CGRect(x: 0, y: 0, width: 10, height: 10))]
        )
        let second = ImportRouter.ImportedContent(
            referenceImages: [ReferenceImage(data: Data([0x02]), frame: CGRect(x: 0, y: 0, width: 20, height: 8))]
        )

        #expect(try document.importContent(first) == 0)
        #expect(try document.importContent(second) == 0)
        #expect(document.referenceImages.count == 2)
        #expect(document.referenceImages[0].data == Data([0x01]))
        #expect(document.referenceImages[1].data == Data([0x02]))
        #expect(document.selectedReferenceImageID == document.referenceImages[1].id)
        #expect(document.referenceImages[0].id != document.referenceImages[1].id)
        #expect(document.referenceImages[0].layerID == document.activeLayerID)
        #expect(document.referenceImages[1].layerID == document.activeLayerID)
    }

    @Test func moveOffsetsFrame() {
        let document = documentWithImage(frame: CGRect(x: 10, y: 20, width: 80, height: 40))
        document.selectReferenceImage()
        document.setReferenceImageFrame(
            CGRect(x: 30, y: 50, width: 80, height: 40),
            recordUndo: true
        )

        #expect(document.referenceImages[0].frame == CGRect(x: 30, y: 50, width: 80, height: 40))
        #expect(document.isReferenceImageSelected)
    }

    @Test func uniformScaleAboutCenterDoublesSize() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        document.scaleReferenceImage(factorX: 2, factorY: 2, about: CGPoint(x: 50, y: 25))

        #expect(document.referenceImages[0].frame == CGRect(x: -50, y: -25, width: 200, height: 100))
    }

    @Test func identityScaleLeavesFrameUnchanged() {
        let frame = CGRect(x: -20, y: -10, width: 40, height: 20)
        let document = documentWithImage(frame: frame)
        document.scaleReferenceImage(factorX: 1, factorY: 1, about: CGPoint(x: 0, y: 0))

        #expect(document.referenceImages[0].frame == frame)
    }

    @Test func missingImageIsNotHittable() {
        let document = KoalaDocument()
        #expect(document.elementHit(near: .zero, threshold: 8) == .none)
        document.selectReferenceImage()
        #expect(!document.isReferenceImageSelected)
    }

    @Test func rotationUpdatesCornersAndHitTesting() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        document.selectReferenceImage()
        document.setReferenceImageRotation(radians: .pi / 2)

        let image = document.referenceImages[0]
        let topRight = image.corners()[1]
        #expect(abs(topRight.x - 60) < 0.01)
        #expect(abs(topRight.y - 60) < 0.01)
        #expect(image.contains(CGPoint(x: 50, y: 10)))
        #expect(image.contains(CGPoint(x: 50, y: 40)))
        #expect(!image.contains(CGPoint(x: 90, y: 10)))
    }

    @Test func opacityClampsAndSurvivesCodec() throws {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        document.selectReferenceImage()
        document.setReferenceImageRotation(radians: 0.4)
        document.setReferenceImageOpacity(1.5)
        #expect(document.referenceImages[0].opacity == 1)
        document.setReferenceImageOpacity(-0.2)
        #expect(document.referenceImages[0].opacity == 0)
        document.setReferenceImageOpacity(0.4)

        let decoded = try DocumentCodec.decode(DocumentCodec.encode(document))
        #expect(abs(decoded.referenceImages[0].opacity - 0.4) < 0.001)
        #expect(abs(decoded.referenceImages[0].rotation - 0.4) < 0.001)
    }

    @Test func missingRotationAndOpacityDecodeAsIdentity() throws {
        let image = ReferenceImage(data: Data([0x01]), frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        let data = try JSONEncoder().encode(image)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "rotation")
        object.removeValue(forKey: "opacity")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ReferenceImage.self, from: stripped)
        #expect(decoded.rotation == 0)
        #expect(decoded.opacity == 1)
        #expect(decoded.frame == image.frame)
    }

    @Test func undoRestoresRotationAndOpacity() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        document.selectReferenceImage()
        document.beginInteractiveEdit()
        document.setReferenceImageRotation(radians: 1.2, recordUndo: false)
        document.setReferenceImageOpacity(0.25, recordUndo: false)

        #expect(abs(document.referenceImages[0].rotation - 1.2) < 0.001)
        #expect(abs(document.referenceImages[0].opacity - 0.25) < 0.001)
        document.undo()
        #expect(document.referenceImages[0].rotation == 0)
        #expect(document.referenceImages[0].opacity == 1)
    }

    @Test func undoRestoresMovedFrame() {
        let original = CGRect(x: 0, y: 0, width: 60, height: 30)
        let document = documentWithImage(frame: original)
        document.selectReferenceImage()
        document.beginInteractiveEdit()
        document.setReferenceImageFrame(
            original.offsetBy(dx: 15, dy: -8),
            recordUndo: false
        )

        #expect(document.referenceImages[0].frame == CGRect(x: 15, y: -8, width: 60, height: 30))
        document.undo()
        #expect(document.referenceImages[0].frame == original)
    }

    @Test func legacySingleImageSnapshotStillLoads() {
        var snapshot = KoalaDocument().makeSnapshot()
        snapshot.referenceImages = nil
        snapshot.referenceImageData = Data([0x01])
        snapshot.referenceImageFrame = CGRect(x: 1, y: 2, width: 12, height: 8)

        let document = KoalaDocument(snapshot: snapshot)
        #expect(document.referenceImages.count == 1)
        #expect(document.referenceImages[0].data == Data([0x01]))
        #expect(document.referenceImages[0].frame == CGRect(x: 1, y: 2, width: 12, height: 8))
        #expect(document.referenceImages[0].layerID == document.activeLayerID)
    }

    @Test func twoImagesSurviveCodecRoundTrip() throws {
        let document = KoalaDocument()
        document.referenceImages = [
            ReferenceImage(data: Data([0x01]), frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            ReferenceImage(data: Data([0x02]), frame: CGRect(x: 20, y: 4, width: 8, height: 6))
        ]

        let decoded = try DocumentCodec.decode(DocumentCodec.encode(document))
        #expect(decoded.referenceImages.count == 2)
        #expect(decoded.referenceImages[0].data == Data([0x01]))
        #expect(decoded.referenceImages[1].frame == CGRect(x: 20, y: 4, width: 8, height: 6))
        #expect(decoded.referenceImages[0].layerID == decoded.activeLayerID)
        #expect(decoded.referenceImages[1].layerID == decoded.activeLayerID)
    }

    @Test func importPlacesImageOnActiveLayer() throws {
        let document = KoalaDocument()
        let firstLayer = document.activeLayerID
        let content = ImportRouter.ImportedContent(
            referenceImages: [ReferenceImage(data: Data([0x01]), frame: CGRect(x: 0, y: 0, width: 10, height: 10))]
        )

        #expect(try document.importContent(content) == 0)
        #expect(document.referenceImages[0].layerID == firstLayer)
        #expect(document.visibleReferenceImages().map(\.id) == [document.referenceImages[0].id])
    }

    @Test func hidingLayerHidesItsImage() throws {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        let imageID = document.referenceImages[0].id
        document.selectReferenceImage(id: imageID)

        document.toggleLayerVisibility(id: document.activeLayerID)

        #expect(document.visibleReferenceImages().isEmpty)
        #expect(document.elementHit(near: CGPoint(x: 10, y: 10), threshold: 4) == .none)
        #expect(document.selectedReferenceImageID == nil)
    }

    @Test func importOntoNewLayerStaysWhenOtherLayerHides() throws {
        let document = KoalaDocument()
        let backLayer = document.activeLayerID
        let frontLayer = document.addLayer()
        #expect(document.activeLayerID == frontLayer.id)

        let content = ImportRouter.ImportedContent(
            referenceImages: [ReferenceImage(data: Data([0x03]), frame: CGRect(x: 0, y: 0, width: 12, height: 8))]
        )
        #expect(try document.importContent(content) == 0)
        #expect(document.referenceImages[0].layerID == frontLayer.id)

        document.toggleLayerVisibility(id: backLayer)
        #expect(document.visibleReferenceImages().map(\.id) == [document.referenceImages[0].id])

        document.toggleLayerVisibility(id: frontLayer.id)
        #expect(document.visibleReferenceImages().isEmpty)
        #expect(document.elementHit(near: CGPoint(x: 4, y: 4), threshold: 4) == .none)
    }

    @Test func hideSelectedImageOmitsItUntilShown() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        let id = document.referenceImages[0].id
        document.selectReferenceImage(id: id)

        #expect(document.canToggleElementVisibility)
        #expect(document.visibilityToolbarImage == "eye")
        #expect(document.visibilityToolbarAccessibilityLabel == "Hide selection")

        document.toggleSelectedElementsHidden()

        #expect(document.referenceImages[0].isHiddenFromCanvas)
        #expect(document.selectedReferenceImageID == id)
        #expect(document.visibleReferenceImages().isEmpty)
        #expect(document.elementHit(near: CGPoint(x: 40, y: 20), threshold: 4) == .none)
        #expect(document.visibilityToolbarImage == "eye.slash")
        #expect(document.visibilityToolbarAccessibilityLabel == "Show selection")

        document.toggleSelectedElementsHidden()

        #expect(document.referenceImages[0].isHiddenFromCanvas == false)
        #expect(document.visibleReferenceImages().map(\.id) == [id])
        #expect(document.elementHit(near: CGPoint(x: 40, y: 20), threshold: 4) == .referenceImage(id))
    }

    @Test func hiddenFrontImageYieldsToImageBehindIt() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let backID = document.referenceImages[0].id
        document.referenceImages.append(
            ReferenceImage(
                layerID: document.activeLayerID,
                data: Data([0x02]),
                frame: CGRect(x: 0, y: 0, width: 40, height: 40)
            )
        )
        let frontID = document.referenceImages[1].id
        document.selectReferenceImage(id: frontID)
        document.hideSelectedElements()

        #expect(document.visibleReferenceImages().map(\.id) == [backID])
        #expect(document.elementHit(near: CGPoint(x: 10, y: 10), threshold: 4) == .referenceImage(backID))
        #expect(document.selectedReferenceImageID == frontID)
    }

    @Test func undoRestoresAHiddenImage() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        let id = document.referenceImages[0].id
        document.selectReferenceImage(id: id)
        document.hideSelectedElements()

        document.undo()

        #expect(document.referenceImages[0].isHiddenFromCanvas == false)
        #expect(document.visibleReferenceImages().map(\.id) == [id])
        #expect(document.referenceImages[0].data == Data([0xFF]))
    }

    @Test func showHiddenObjectsRevealsImageWhenNothingIsSelected() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        document.selectReferenceImage()
        document.hideSelectedElements()
        document.clearElementSelection()

        #expect(document.selectedReferenceImageID == nil)
        #expect(document.canToggleElementVisibility)
        #expect(document.visibilityToolbarAccessibilityLabel == "Show hidden objects")

        document.toggleSelectedElementsHidden()

        #expect(document.referenceImages[0].isHiddenFromCanvas == false)
        #expect(document.visibleReferenceImages().count == 1)
    }

    @Test func imageHiddenFlagRoundTripsAndOlderFilesStayVisible() throws {
        var image = ReferenceImage(
            data: Data([0x01]),
            frame: CGRect(x: 1, y: 2, width: 3, height: 4),
            isHidden: true
        )
        let encoded = try JSONEncoder().encode(image)
        let decoded = try JSONDecoder().decode(ReferenceImage.self, from: encoded)
        #expect(decoded.isHiddenFromCanvas)
        #expect(decoded.data == image.data)

        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isHidden")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let legacy = try JSONDecoder().decode(ReferenceImage.self, from: stripped)
        #expect(legacy.isHidden == nil)
        #expect(legacy.isHiddenFromCanvas == false)
        image.isHidden = nil
        #expect(legacy.frame == image.frame)
    }

    @Test func imageOnFrontLayerBlocksTapThroughToActiveLayer() {
        let document = documentWithImage(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let backID = document.referenceImages[0].id
        let front = document.addLayer()
        document.referenceImages.append(
            ReferenceImage(
                layerID: front.id,
                data: Data([0x02]),
                frame: CGRect(x: 0, y: 0, width: 50, height: 50)
            )
        )
        document.setActiveLayer(id: document.layers[0].id)

        #expect(document.isHitOnInactiveLayer(near: CGPoint(x: 10, y: 10), threshold: 4))
        #expect(document.elementHit(near: CGPoint(x: 10, y: 10), threshold: 4) == .none)
        #expect(document.selectElement(near: CGPoint(x: 10, y: 10), threshold: 4) == .none)
        #expect(document.selectedReferenceImageID != backID)
    }

    private func documentWithImage(frame: CGRect) -> KoalaDocument {
        let document = KoalaDocument()
        document.referenceImages = [
            ReferenceImage(layerID: document.activeLayerID, data: Data([0xFF]), frame: frame)
        ]
        return document
    }
}
