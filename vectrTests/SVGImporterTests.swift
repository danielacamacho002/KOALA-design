import CoreGraphics
import Foundation
import Testing
@testable import vectr

@MainActor
struct SVGImporterTests {
    private let layerID = UUID()

    @Test func pathIdDoesNotStealPathData() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <path id="line" d="M 0 0 L 10 0"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        #expect(points(of: strokes[0]) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
    }

    @Test func compactDecimalsSplitIntoSeparateCoordinates() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M0.5.5L10.5.5"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        #expect(points(of: strokes[0]) == [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 10.5, y: 0.5)])
    }

    @Test func scientificNotationKeepsCoordinates() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M0,1.5e1 L2.0e1,1.5e1"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        #expect(points(of: strokes[0]) == [CGPoint(x: 0, y: 15), CGPoint(x: 20, y: 15)])
    }

    @Test func groupTranslateMovesPath() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <g transform="translate(10,20)">
            <path d="M 0 0 L 5 0"/>
          </g>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        #expect(points(of: strokes[0]) == [CGPoint(x: 10, y: 20), CGPoint(x: 15, y: 20)])
    }

    @Test func rotateTransformRotatesLine() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M 10 0 L 20 0" transform="rotate(90)"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        let imported = points(of: strokes[0])
        #expect(imported.count == 2)
        #expect(isNear(imported[0], CGPoint(x: 0, y: 10)))
        #expect(isNear(imported[1], CGPoint(x: 0, y: 20)))
    }

    @Test func cubicPathFollowsBezierMidpoint() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <g transform="translate(8,4)">
            <path d="M 0 0 C 10 0 10 10 0 10"/>
          </g>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard let stroke = strokes.first else { return }
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        #expect(rendered.contains { isNear($0, CGPoint(x: 15.5, y: 9), epsilon: 0.6) })
    }

    @Test func defsPathsAreNotImported() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <defs>
            <path d="M 0 0 L 100 0"/>
          </defs>
          <path d="M 0 0 L 4 0"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        #expect(points(of: strokes[0]) == [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0)])
    }

    @Test func viewBoxOriginIsAppliedBeforeCentering() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="10 20 10 10" width="10" height="10">
          <path d="M 10 20 L 20 20"/>
        </svg>
        """
        let raw = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(raw.count == 1)
        #expect(points(of: raw[0]) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])

        let centered = SVGImporter.centeredStrokes(raw)
        #expect(points(of: centered[0]) == [CGPoint(x: -5, y: 0), CGPoint(x: 5, y: 0)])
    }

    @Test func textUsesNamedFontAndDoesNotBecomeAPath() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text x="10" y="40" font-family="Georgia" font-size="24" fill="#111111">Hello</text>
        </svg>
        """
        let parsed = SVGImporter.parse(xml: xml, layerID: layerID)
        #expect(parsed.strokes.isEmpty)
        #expect(parsed.textElements.count == 1)
        let text = parsed.textElements[0]
        #expect(text.text == "Hello")
        #expect(text.fontRef == .builtin("Georgia"))
        #expect(text.fontSize == 24)
        #expect(text.color.red < 0.1)
        #expect(text.isOutline == false)
    }

    @Test func tspanInheritsFontFromText() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <text x="0" y="20" font-family="Courier New" font-size="18">
            <tspan>Vectr</tspan>
          </text>
        </svg>
        """
        let parsed = SVGImporter.parse(xml: xml, layerID: layerID)
        #expect(parsed.textElements.count == 1)
        #expect(parsed.textElements[0].text == "Vectr")
        #expect(parsed.textElements[0].fontRef == .builtin("Courier New"))
    }

    @Test func filledTextPathKeepsFillAndOmitsDefaultStroke() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path fill="#000000" stroke="none" d="M 0 0 L 10 0 L 10 10 L 0 10 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        #expect(strokes[0].strokeWidth == 0)
        #expect(strokes[0].fillOpacity == 1)
        #expect(strokes[0].fillColor?.red == 0)
        #expect(strokes[0].fillColor?.green == 0)
        #expect(strokes[0].fillColor?.blue == 0)
    }

    @Test func groupStrokeNoneIsInherited() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <g fill="#ff0000" stroke="none">
            <path d="M 0 0 L 8 0 L 8 8 L 0 8 Z"/>
          </g>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        #expect(strokes[0].strokeWidth == 0)
        #expect(strokes[0].fillColor?.red == 1)
    }

    @Test func closePathDoesNotEatFollowingMove() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M 0 0 L 4 0 L 4 8 L 0 8 Z M 10 0 C 12 0 14 2 14 4 L 14 8 L 10 8 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard let stroke = strokes.first else { return }
        #expect(points(of: stroke).first == CGPoint(x: 0, y: 0))
        #expect(stroke.cutoutPoints.count == 1)
        #expect(stroke.cutoutPoints.first?.first == CGPoint(x: 10, y: 0))
        #expect(!(stroke.cutoutPoints.first ?? []).contains(CGPoint(x: 0, y: 0)))
    }

    @Test func disjointClosedContoursStayFilledInOnePath() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M 0 0 L 6 0 L 6 6 L 0 6 Z M 20 0 L 26 0 L 26 6 L 20 6 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard let stroke = strokes.first else { return }
        #expect(stroke.cutoutPoints.count == 1)
        #expect(stroke.fillRule == .nonzero)
        #expect(stroke.contains(CGPoint(x: 3, y: 3)))
        #expect(stroke.contains(CGPoint(x: 23, y: 3)))
        #expect(!stroke.contains(CGPoint(x: 12, y: 3)))
    }

    @Test func nestedContourBecomesAHole() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M 0 0 L 10 0 L 10 10 L 0 10 Z M 3 3 L 7 3 L 7 7 L 3 7 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard strokes.count == 1 else { return }
        #expect(strokes[0].cutoutPoints.count == 1)
        #expect(strokes[0].cutoutPoints[0].first == CGPoint(x: 3, y: 3))
    }

    @Test func cubicDonutKeepsARoundHoleNotABar() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path fill="none" stroke="#000" d="M 10 0 C 10 5.5228 5.5228 10 0 10 C -5.5228 10 -10 5.5228 -10 0 C -10 -5.5228 -5.5228 -10 0 -10 C 5.5228 -10 10 -5.5228 10 0 Z M 5 0 C 5 2.7614 2.7614 5 0 5 C -2.7614 5 -5 2.7614 -5 0 C -5 -2.7614 -2.7614 -5 0 -5 C 2.7614 -5 5 -2.7614 5 0 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard strokes.count == 1 else { return }
        #expect(strokes[0].cutoutPoints.count == 1)
        #expect((strokes[0].cutoutPoints.first?.count ?? 0) > 8)
        #expect(points(of: strokes[0]).count > 2)
    }

    @Test func concatenatedArcFlagsStaySeparate() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M 10 0 A 10 10 0 01 0 10"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard strokes.count == 1 else { return }
        #expect(points(of: strokes[0]).count > 3)
        #expect(isNear(points(of: strokes[0]).last ?? .zero, CGPoint(x: 0, y: 10), epsilon: 0.05))
    }

    @Test func cubicCircleKeepsItsDiagonalRadius() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path fill="none" stroke="black" d="M 40 0 C 40 22.09139 22.09139 40 0 40 C -22.09139 40 -40 22.09139 -40 0 C -40 -22.09139 -22.09139 -40 0 -40 C 22.09139 -40 40 -22.09139 40 0 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard let stroke = strokes.first else { return }
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        let diagonal = rendered.filter { abs($0.x) > 15 && abs($0.y) > 15 }
        #expect(!diagonal.isEmpty)
        #expect(diagonal.contains { hypot($0.x, $0.y) > 35 })
    }

    @Test func cubicEllipseDoesNotFlattenToADiamond() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path fill="none" stroke="black" d="M 40 0 C 40 5.5228 22.09139 10 0 10 C -22.09139 10 -40 5.5228 -40 0 C -40 -5.5228 -22.09139 -10 0 -10 C 22.09139 -10 40 -5.5228 40 0 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard let stroke = strokes.first else { return }
        let interactive = ShapeGeometry.withCompactedCircularAnchors(stroke, rewritingPartialRuns: false)
        let rendered = ShapeGeometry.renderPoints(for: interactive)
        let band = rendered.filter { $0.x > 26 && $0.x < 30 }
        #expect((band.map { abs($0.y) }.max() ?? 0) > 5)
        let height = (rendered.map(\.y).max() ?? 0) - (rendered.map(\.y).min() ?? 0)
        #expect(height < 25)
        #expect(height > 18)
        #expect(interactive.shapeType != .circle)
        #expect(interactive.shapeType != .arc)
        #expect(ShapeGeometry.renderPoints(for: interactive).count > 8)
    }

    @Test func rotatedEllipseKeepsItsLongAxis() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <ellipse cx="0" cy="0" rx="40" ry="10" transform="rotate(45)" fill="none" stroke="black"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard strokes.count == 1 else { return }
        let ys = points(of: strokes[0]).map(\.y)
        let height = (ys.max() ?? 0) - (ys.min() ?? 0)
        #expect(height > 40)
    }

    @Test func overlappingClosedContoursKeepNonzeroOverlap() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path d="M 10 0 A 10 10 0 1 1 -10 0 A 10 10 0 1 1 10 0 Z M 18 0 A 10 10 0 1 1 -2 0 A 10 10 0 1 1 18 0 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard let stroke = strokes.first else { return }
        #expect(stroke.cutoutPoints.count == 1)
        #expect(stroke.fillRule == .nonzero)
        #expect(stroke.contains(CGPoint(x: 4, y: 0)))
    }

    @Test func evenOddOverlappingContoursPunchTheOverlap() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path fill-rule="evenodd" d="M 10 0 A 10 10 0 1 1 -10 0 A 10 10 0 1 1 10 0 Z M 18 0 A 10 10 0 1 1 -2 0 A 10 10 0 1 1 18 0 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard let stroke = strokes.first else { return }
        #expect(stroke.fillRule == .evenodd)
        #expect(!stroke.contains(CGPoint(x: 4, y: 0)))
        #expect(stroke.contains(CGPoint(x: -5, y: 0)))
    }

    @Test func outlinedLetterOKeepsARoundHole() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path fill="#000" fill-rule="nonzero" d="M 214.17 -7.56 Q 214.17 -17.07 216.70 -24.46 Q 219.23 -31.85 223.69 -36.91 Q 228.14 -41.97 234.11 -44.60 Q 240.08 -47.23 246.76 -47.23 Q 253.44 -47.23 259.41 -44.60 Q 265.38 -41.97 269.84 -36.91 Q 274.29 -31.85 276.82 -24.46 Q 279.35 -17.07 279.35 -7.56 Q 279.35 1.95 276.82 9.34 Q 274.29 16.73 269.84 21.69 Q 265.38 26.65 259.41 29.28 Q 253.44 31.91 246.76 31.91 Q 240.08 31.91 234.11 29.28 Q 228.14 26.65 223.69 21.69 Q 219.23 16.73 216.70 9.34 Q 214.17 1.95 214.17 -7.56 Z M 195.95 -7.56 Q 195.95 3.98 199.19 13.90 Q 202.43 23.81 208.91 31.20 Q 215.39 38.59 224.90 42.74 Q 234.41 46.89 246.76 46.89 Q 259.31 46.89 268.72 42.74 Q 278.14 38.59 284.61 31.20 Q 291.09 23.81 294.33 13.90 Q 297.57 3.98 297.57 -7.56 Q 297.57 -19.10 294.33 -29.12 Q 291.09 -39.14 284.61 -46.53 Q 278.14 -53.91 268.72 -58.17 Q 259.31 -62.42 246.76 -62.42 Q 234.41 -62.42 224.90 -58.17 Q 215.39 -53.91 208.91 -46.53 Q 202.43 -39.14 199.19 -29.12 Q 195.95 -19.10 195.95 -7.56 Z"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        guard let stroke = strokes.first else { return }
        #expect(stroke.cutoutPoints.count == 1)
        #expect((stroke.cutoutPoints.first?.count ?? 0) > 8)
        #expect(points(of: stroke).count > 8)
        #expect(stroke.contains(CGPoint(x: 246.76, y: -55)))
        #expect(!stroke.contains(CGPoint(x: 246.76, y: -7.56)))
        let afterMove = ShapeGeometry.withCompactedCircularAnchors(stroke, rewritingPartialRuns: false)
        #expect(afterMove.cutoutPoints.count == 1)
        #expect(afterMove.contains(CGPoint(x: 246.76, y: -55)))
        #expect(!afterMove.contains(CGPoint(x: 246.76, y: -7.56)))
    }

    @Test func namedStrokeColorKeepsAVisibleStroke() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <line x1="0" y1="0" x2="10" y2="0" stroke="black"/>
        </svg>
        """
        let strokes = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(strokes.count == 1)
        #expect(strokes[0].strokeWidth > 0)
        #expect(strokes[0].strokeColor.red == 0)
        #expect(strokes[0].strokeColor.green == 0)
        #expect(strokes[0].strokeColor.blue == 0)
    }

    private func points(of stroke: VectorStroke) -> [CGPoint] {
        stroke.points
    }

    private func isNear(_ a: CGPoint, _ b: CGPoint, epsilon: CGFloat = 0.0001) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < epsilon
    }
}
