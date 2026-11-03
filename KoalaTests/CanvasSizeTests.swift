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

    @Test func anUnchangedCanvasSizeDoesNotRecordUndo() {
        let document = KoalaDocument()
        let size = document.settings.canvasSize

        #expect(document.setCanvasSize(width: size.width, height: size.height) == false)
        #expect(document.canUndo == false)
    }
}
