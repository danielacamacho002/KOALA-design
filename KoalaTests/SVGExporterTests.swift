import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct SVGExporterTests {
    @Test func closedPlaneKeepsTheCanvasFillOpacity() {
        let svg = exportClosedSquare()
        #expect(svg.contains("fill=\"#CCCCCC\""))
        #expect(svg.contains("fill-opacity=\"0.25\""))
        let strokes = SVGImporter.parse(xml: svg, layerID: UUID()).strokes
        #expect(strokes.count == 1)
        #expect(abs((strokes[0].fillOpacity ?? -1) - 0.25) < 0.001)
    }

    @Test func customFillOpacityRoundTripsThroughSVG() {
        let svg = exportClosedSquare(
            fillOpacity: 0.4,
            fillColor: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        )
        #expect(svg.contains("fill=\"#000000\""))
        #expect(svg.contains("fill-opacity=\"0.4\""))
        let strokes = SVGImporter.parse(xml: svg, layerID: UUID()).strokes
        #expect(strokes.count == 1)
        #expect(strokes[0].fillColor?.red == 0)
        #expect(abs((strokes[0].fillOpacity ?? -1) - 0.4) < 0.001)
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
