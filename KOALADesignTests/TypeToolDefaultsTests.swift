import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct TypeToolDefaultsTests {
    @Test func makeTextElementUsesFillDefaults() {
        let document = KoalaDocument()
        let point = CGPoint(x: 10, y: 20)

        let element = document.makeTextElement(at: point)

        #expect(element.position == point)
        #expect(element.layerID == document.activeLayerID)
        #expect(element.fontRef == document.activeFontRef)
        #expect(element.fontSize == document.activeFontSize)
        #expect(element.color == document.strokeColor)
        #expect(element.isOutline == false)
        #expect(element.strokeWidth == TextElement.defaultStrokeWidth)
    }

    @Test func makeTextElementUsesActiveOutlineAndStroke() {
        let document = KoalaDocument()
        document.activeTextIsOutline = true
        document.activeTextStrokeWidth = 3
        document.activeFontSize = 48

        let element = document.makeTextElement(at: .zero)

        #expect(element.isOutline)
        #expect(element.strokeWidth == 3)
        #expect(element.fontSize == 48)
        #expect(element.strokeColor == document.strokeColor)
    }
}
