import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct SVGExporterTests {
    @Test func closedPlaneOmitsFillOpacitySoIllustratorCanRecolor() {
        let svg = exportClosedSquare()
        #expect(svg.contains("fill=\"#CCCCCC\""))
        #expect(!svg.contains("fill-opacity"))
    }

    @Test func blackFillStaysOpaqueEvenAtCanvasPreviewOpacity() {
        let svg = exportClosedSquare(
            fillOpacity: VectorStroke.defaultFillOpacity,
            fillColor: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        )
        #expect(svg.contains("fill=\"#000000\""))
        #expect(!svg.contains("fill-opacity"))
    }

    @Test func zeroFillOpacityExportsUnfilledPath() {
        let svg = exportClosedSquare(fillOpacity: 0)
        #expect(svg.contains("fill=\"none\""))
        #expect(!svg.contains("fill=\"#CCCCCC\""))
        #expect(!svg.contains("fill-opacity"))
    }

    private func exportClosedSquare(
        fillOpacity: CGFloat? = nil,
        fillColor: CodableColor? = nil
    ) -> String {
        let document = KoalaDocument()
        document.addStroke(
            VectorStroke(
                layerID: document.activeLayerID,
                points: [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 10, y: 0),
                    CGPoint(x: 10, y: 10),
                    CGPoint(x: 0, y: 10)
                ],
                isClosed: true,
                fillOpacity: fillOpacity,
                fillColor: fillColor
            )
        )
        return SVGExporter.export(document: document)
    }
}
