import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import KOALADesign

/// A filleted square with a punched hole, a triangle drawn against its right edge,
/// Join, then Trim on the shared edge. Neither step should drop the fillets or the hole.
@MainActor
struct JoinTrimKeepsModifiersTests {
    private static let holeCenter = CGPoint(x: 100, y: 100)
    private static let insideTriangle = CGPoint(x: 260, y: 100)
    private static let roundedOffCorner = CGPoint(x: 4, y: 4)

    @Test func joiningATriangleOntoAFilletedHoledSquareKeepsBoth() throws {
        let document = try Self.filletedHoledSquareWithTriangle()

        #expect(document.joinSelectedShapes())

        #expect(document.strokes.count == 1)
        let joined = try #require(document.strokes.first)
        #expect(joined.isClosed)
        #expect(joined.cutoutPoints.count == 1)
        #expect(joined.resolvedFilletCornerRadii().values.sorted() == [60, 60])
        #expect(!joined.contains(Self.holeCenter))
        #expect(joined.contains(Self.insideTriangle))
        #expect(!Self.filledPath(joined).contains(Self.roundedOffCorner, using: joined.resolvedCGFillRule))
    }

    @Test func trimmingTheSharedEdgeKeepsTheFilledOutlineHoleAndFillets() throws {
        let document = try Self.filletedHoledSquareWithTriangle()
        #expect(document.joinSelectedShapes())
        document.setElementSelection(strokeIDs: [], textIDs: [])
        document.selectedStrokeID = document.strokes.first?.id

        #expect(document.trimAt(CGPoint(x: 200, y: 100), threshold: 4))

        #expect(document.strokes.count == 1)
        let trimmed = try #require(document.strokes.first)
        #expect(trimmed.isClosed)
        #expect(trimmed.cutoutPoints.count == 1)
        #expect(!trimmed.contains(Self.holeCenter))
        #expect(trimmed.contains(Self.insideTriangle))
        #expect(trimmed.contains(CGPoint(x: 190, y: 100)))
        #expect(!Self.filledPath(trimmed).contains(Self.roundedOffCorner, using: trimmed.resolvedCGFillRule))
    }

    private static func filledPath(_ stroke: VectorStroke) -> CGPath {
        StrokeRenderer.path(for: stroke, viewport: ViewportTransform()).cgPath
    }

    private static func filletedHoledSquareWithTriangle() throws -> KoalaDocument {
        let document = KoalaDocument()
        let layer = document.activeLayerID
        let square = VectorStroke(
            layerID: layer,
            points: ShapeGeometry.rectangleFromCenterDistances(
                CGPoint(x: 100, y: 100),
                halfWidth: 100,
                halfHeight: 100
            ),
            isClosed: true,
            shapeType: .rectangle
        )
        document.addStroke(square)
        let cutter = VectorStroke(
            layerID: layer,
            points: ShapeGeometry.circleCardinalPoints(center: holeCenter, radius: 30),
            isClosed: true,
            shapeType: .circle
        )
        document.addStroke(cutter)
        #expect(document.applyOverlapCut(baseID: square.id, cutterID: cutter.id))

        document.selectedStrokeID = square.id
        let cut = try #require(document.stroke(with: square.id))
        let leftCorners = Set(cut.points.indices.filter { cut.points[$0].x < 1 })
        document.applyFilletToSelected(radius: 60, cornerIndices: leftCorners)

        document.addStroke(VectorStroke(layerID: layer, points: [CGPoint(x: 200, y: 0), CGPoint(x: 330, y: 80)]))
        document.addStroke(VectorStroke(layerID: layer, points: [CGPoint(x: 330, y: 80), CGPoint(x: 200, y: 200)]))
        document.setElementSelection(strokeIDs: Set(document.strokes.map(\.id)), textIDs: [])
        return document
    }
}
