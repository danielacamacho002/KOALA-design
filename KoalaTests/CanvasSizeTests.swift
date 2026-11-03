import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct CanvasSizeTests {
    @Test func resizingTheCanvasUpdatesTheSheetAndUndo() {
        let document = KoalaDocument()
        let original = document.settings.canvasSize
        let width = UnitConversion.documentPoints(from: 12, unit: .inches)
        let height = UnitConversion.documentPoints(from: 8, unit: .inches)

        #expect(document.setCanvasSize(width: width, height: height))
        #expect(document.settings.canvasWidth == width)
        #expect(document.settings.canvasHeight == height)
        #expect(document.canUndo)

        document.undo()
        #expect(document.settings.canvasSize == original)

        document.redo()
        #expect(document.settings.canvasWidth == width)
        #expect(document.settings.canvasHeight == height)
    }

    @Test func canvasSizeClampsToTheUnitLimits() {
        let document = KoalaDocument()
        document.settings.units = .inches
        let maximum = DocumentSettings.maximumCanvasExtent(for: .inches)

        #expect(document.setCanvasSize(width: maximum * 4, height: 0))
        #expect(document.settings.canvasWidth == maximum)
        #expect(document.settings.canvasHeight == 1)
    }

    @Test func canvasSizeRoundTripsThroughTheFile() throws {
        let document = KoalaDocument()
        let width = UnitConversion.documentPoints(from: 48, unit: .inches)
        let height = UnitConversion.documentPoints(from: 36, unit: .inches)
        document.setCanvasSize(width: width, height: height)

        let decoded = try DocumentCodec.decode(try DocumentCodec.encode(document))
        #expect(decoded.settings.canvasWidth == width)
        #expect(decoded.settings.canvasHeight == height)
    }

    @Test func openingGrowsTheSheetUntilThePatternFits() {
        let document = KoalaDocument()
        document.addStroke(VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 2_000, y: 10), CGPoint(x: 2_100, y: 40)]
        ))
        var snapshot = document.makeSnapshot()
        snapshot.settings.canvasWidth = DocumentSettings.defaultCanvasWidth
        snapshot.settings.canvasHeight = DocumentSettings.defaultCanvasHeight

        let opened = KoalaDocument(snapshot: snapshot)
        let canvas = CGRect(
            x: -opened.settings.canvasWidth / 2,
            y: -opened.settings.canvasHeight / 2,
            width: opened.settings.canvasWidth,
            height: opened.settings.canvasHeight
        )
        #expect(canvas.contains(CGPoint(x: 2_100, y: 40)))
        #expect(opened.settings.canvasWidth > DocumentSettings.defaultCanvasWidth)
        #expect(opened.settings.canvasHeight == DocumentSettings.defaultCanvasHeight)
    }

    @Test func aSheetThatAlreadyContainsThePatternDoesNotGrow() {
        let document = KoalaDocument()
        document.addStroke(VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: -20, y: -20), CGPoint(x: 20, y: 20)]
        ))
        let width = document.settings.canvasWidth
        let height = document.settings.canvasHeight

        #expect(document.expandCanvasToFitContents() == false)
        #expect(document.settings.canvasWidth == width)
        #expect(document.settings.canvasHeight == height)
    }

    @Test func anUnchangedCanvasSizeDoesNotRecordUndo() {
        let document = KoalaDocument()
        let size = document.settings.canvasSize

        #expect(document.setCanvasSize(width: size.width, height: size.height) == false)
        #expect(document.canUndo == false)
    }
}
