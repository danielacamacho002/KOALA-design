import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct ScaleSelectionTests {
    @Test func uniformScaleDoublesAShapeAboutItsCenter() {
        let document = KoalaDocument()
        let stroke = rectangle(layerID: document.activeLayerID)
        var withModifiers = stroke
        withModifiers.cornerRadius = 4
        withModifiers.cornerRadiiByIndex = [1: 6]
        withModifiers.curveHandles = [CurveHandle(inOffset: CGPoint(x: 3, y: 0), outOffset: CGPoint(x: 0, y: 4))]
        withModifiers.cutoutPoints = [[CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 2)]]
        document.addStroke(withModifiers)
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])

        #expect(document.scaleSelectedElements(factorX: 2, factorY: 2))

        let scaled = document.stroke(with: stroke.id)
        #expect(pointsMatch(scaled?.points ?? [], [
            CGPoint(x: -5, y: -5),
            CGPoint(x: 15, y: -5),
            CGPoint(x: 15, y: 15),
            CGPoint(x: -5, y: 15)
        ]))
        #expect(scaled?.cornerRadius == 8)
        #expect(scaled?.cornerRadiiByIndex?[1] == 12)
        #expect(scaled?.curveHandles?.first?.inOffset == CGPoint(x: 6, y: 0))
        #expect(scaled?.curveHandles?.first?.outOffset == CGPoint(x: 0, y: 8))
        #expect(pointsMatch(scaled?.cutoutPoints.first ?? [], [
            CGPoint(x: -1, y: -1),
            CGPoint(x: 1, y: -1)
        ]))
    }

    @Test func freeScaleStretchesWidthAndLeavesHeight() {
        let document = KoalaDocument()
        let stroke = rectangle(layerID: document.activeLayerID)
        document.addStroke(stroke)
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])

        #expect(document.scaleSelectedElements(factorX: 2, factorY: 1))

        #expect(pointsMatch(document.stroke(with: stroke.id)?.points ?? [], [
            CGPoint(x: -5, y: 0),
            CGPoint(x: 15, y: 0),
            CGPoint(x: 15, y: 10),
            CGPoint(x: -5, y: 10)
        ]))
    }

    @Test func multiSelectionScalesAboutTheCombinedCenter() {
        let document = KoalaDocument()
        let left = rectangle(layerID: document.activeLayerID)
        var right = rectangle(layerID: document.activeLayerID)
        right.points = right.points.map { CGPoint(x: $0.x + 20, y: $0.y) }
        document.addStroke(left)
        document.addStroke(right)
        document.setElementSelection(strokeIDs: [left.id, right.id], textIDs: [])

        #expect(document.scaleSelectedElements(factorX: 2, factorY: 2))

        #expect(pointsMatch(document.stroke(with: left.id)?.points ?? [], [
            CGPoint(x: -15, y: -5),
            CGPoint(x: 5, y: -5),
            CGPoint(x: 5, y: 15),
            CGPoint(x: -15, y: 15)
        ]))
        #expect(pointsMatch(document.stroke(with: right.id)?.points ?? [], [
            CGPoint(x: 25, y: -5),
            CGPoint(x: 45, y: -5),
            CGPoint(x: 45, y: 15),
            CGPoint(x: 25, y: 15)
        ]))
    }

    @Test func scalingOneGroupedShapeScalesTheWholeGroup() {
        let document = KoalaDocument()
        let left = rectangle(layerID: document.activeLayerID)
        var right = rectangle(layerID: document.activeLayerID)
        right.points = right.points.map { CGPoint(x: $0.x + 20, y: $0.y) }
        var outsider = rectangle(layerID: document.activeLayerID)
        outsider.points = outsider.points.map { CGPoint(x: $0.x + 80, y: $0.y) }
        document.addStroke(left)
        document.addStroke(right)
        document.addStroke(outsider)
        document.setElementSelection(strokeIDs: [left.id, right.id], textIDs: [])
        document.groupSelectedElements()
        document.setElementSelection(strokeIDs: [left.id], textIDs: [])

        #expect(document.scaleSelectedElements(factorX: 2, factorY: 2))

        #expect(document.selectedStrokeIDs == Set([left.id, right.id]))
        #expect(pointsMatch(document.stroke(with: left.id)?.points ?? [], [
            CGPoint(x: -15, y: -5),
            CGPoint(x: 5, y: -5),
            CGPoint(x: 5, y: 15),
            CGPoint(x: -15, y: 15)
        ]))
        #expect(pointsMatch(document.stroke(with: right.id)?.points ?? [], [
            CGPoint(x: 25, y: -5),
            CGPoint(x: 45, y: -5),
            CGPoint(x: 45, y: 15),
            CGPoint(x: 25, y: 15)
        ]))
        #expect(document.stroke(with: outsider.id)?.points == outsider.points)
    }

    @Test func groupedTextScalesAboutTheSharedCenter() {
        let document = KoalaDocument()
        let stroke = rectangle(layerID: document.activeLayerID)
        document.addStroke(stroke)
        var element = document.makeTextElement(at: CGPoint(x: 40, y: 0))
        element.text = "Hi"
        element.fontSize = 12
        document.addTextElement(element)
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [element.id])
        document.groupSelectedElements()
        let textCenter = document.textElement(with: element.id)?.center ?? .zero
        let box = document.selectionBoundingBox()
        let groupCenter = CGPoint(x: box?.midX ?? 0, y: box?.midY ?? 0)

        #expect(document.scaleSelectedElements(factorX: 2, factorY: 2))

        let scaled = document.textElement(with: element.id)
        let expected = CGPoint(
            x: groupCenter.x + (textCenter.x - groupCenter.x) * 2,
            y: groupCenter.y + (textCenter.y - groupCenter.y) * 2
        )
        #expect(scaled?.fontSize == 24)
        #expect(abs((scaled?.center.x ?? 0) - expected.x) < 0.5)
        #expect(abs((scaled?.center.y ?? 0) - expected.y) < 0.5)
        #expect(pointsMatch(document.stroke(with: stroke.id)?.points ?? [], [
            CGPoint(x: groupCenter.x + (0 - groupCenter.x) * 2, y: groupCenter.y + (0 - groupCenter.y) * 2),
            CGPoint(x: groupCenter.x + (10 - groupCenter.x) * 2, y: groupCenter.y + (0 - groupCenter.y) * 2),
            CGPoint(x: groupCenter.x + (10 - groupCenter.x) * 2, y: groupCenter.y + (10 - groupCenter.y) * 2),
            CGPoint(x: groupCenter.x + (0 - groupCenter.x) * 2, y: groupCenter.y + (10 - groupCenter.y) * 2)
        ]))
    }

    @Test func uniformScaleDoublesTextFontAndKeepsTheCenter() {
        let document = KoalaDocument()
        var element = document.makeTextElement(at: CGPoint(x: 10, y: 20))
        element.text = "Hi"
        element.fontSize = 24
        document.addTextElement(element)
        document.setElementSelection(strokeIDs: [], textIDs: [element.id])
        let center = document.textElement(with: element.id)?.center ?? .zero

        #expect(document.scaleSelectedElements(factorX: 2, factorY: 2))

        let scaled = document.textElement(with: element.id)
        #expect(scaled?.fontSize == 48)
        #expect(document.activeFontSize == 48)
        #expect(abs((scaled?.center.x ?? 0) - center.x) < 0.01)
        #expect(abs((scaled?.center.y ?? 0) - center.y) < 0.01)
    }

    @Test func widthOnlyScaleLeavesTextSizeAlone() {
        let document = KoalaDocument()
        var element = document.makeTextElement(at: CGPoint(x: 10, y: 20))
        element.text = "Hi"
        element.fontSize = 24
        document.addTextElement(element)
        document.setElementSelection(strokeIDs: [], textIDs: [element.id])

        #expect(document.scaleSelectedElements(factorX: 2, factorY: 1))

        #expect(document.textElement(with: element.id)?.fontSize == 24)
    }

    @Test func referenceImageScalesAboutItsCenter() {
        let document = KoalaDocument()
        document.referenceImages = [
            ReferenceImage(
                layerID: document.activeLayerID,
                data: Data([0xFF]),
                frame: CGRect(x: 0, y: 0, width: 100, height: 50)
            )
        ]
        document.selectReferenceImage()

        #expect(document.scaleSelectedElements(factorX: 2, factorY: 2))

        #expect(document.referenceImages[0].frame == CGRect(x: -50, y: -25, width: 200, height: 100))
    }

    @Test func undoRestoresTheScaledShape() {
        let document = KoalaDocument()
        let stroke = rectangle(layerID: document.activeLayerID)
        document.addStroke(stroke)
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])

        document.scaleSelectedElements(factorX: 2, factorY: 2)
        document.undo()

        #expect(document.stroke(with: stroke.id)?.points == stroke.points)
    }

    @Test func identityAndEmptySelectionDoNotScale() {
        let document = KoalaDocument()
        let stroke = rectangle(layerID: document.activeLayerID)
        document.addStroke(stroke)
        let untouched = document.undoRevision

        #expect(!document.scaleSelectedElements(factorX: 2, factorY: 2))
        #expect(document.undoRevision == untouched)
        #expect(document.strokes[0].points == stroke.points)

        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])
        let selected = document.undoRevision
        #expect(!document.scaleSelectedElements(factorX: 1, factorY: 1))
        #expect(!document.scaleSelectedElements(factorX: 0, factorY: 2))
        #expect(document.undoRevision == selected)
        #expect(document.strokes[0].points == stroke.points)
    }

    private func rectangle(layerID: UUID) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 0),
                CGPoint(x: 10, y: 10),
                CGPoint(x: 0, y: 10)
            ],
            strokeWidth: 1.5,
            isClosed: true,
            shapeType: .polyline
        )
    }

    private func pointsMatch(_ actual: [CGPoint], _ expected: [CGPoint], tolerance: CGFloat = 0.001) -> Bool {
        guard actual.count == expected.count else { return false }
        return zip(actual, expected).allSatisfy { point, target in
            abs(point.x - target.x) <= tolerance && abs(point.y - target.y) <= tolerance
        }
    }
}
