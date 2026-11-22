import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct FilletedOverlapCutTests {
    @Test func circleBiteKeepsTheBaseFillets() throws {
        let document = KoalaDocument()
        let base = Self.filletedRectangle(layerID: document.activeLayerID)
        document.addStroke(base)
        let bite = Self.circle(layerID: document.activeLayerID, center: CGPoint(x: 200, y: 50))
        document.addStroke(bite)

        #expect(document.applyOverlapCut(baseID: base.id, cutterID: bite.id))

        let cut = try #require(document.stroke(with: base.id))
        let outline = ShapeGeometry.renderPoints(for: cut)
        #expect(!(cut.smoothCornerIndices ?? []).isEmpty)
        for corner in Self.sharpCorners {
            #expect(!ShapeBooleanEngine.polygon(outline, contains: corner))
        }
        for inside in Self.insideFillets {
            #expect(ShapeBooleanEngine.polygon(outline, contains: inside))
        }
        #expect(!ShapeBooleanEngine.polygon(outline, contains: CGPoint(x: 195, y: 50)))
    }

    @Test func secondCutKeepsFilletsBakedByTheFirst() throws {
        let document = KoalaDocument()
        let base = Self.filletedRectangle(layerID: document.activeLayerID)
        document.addStroke(base)
        let right = Self.circle(layerID: document.activeLayerID, center: CGPoint(x: 200, y: 50))
        document.addStroke(right)
        #expect(document.applyOverlapCut(baseID: base.id, cutterID: right.id))

        let left = Self.circle(layerID: document.activeLayerID, center: CGPoint(x: 0, y: 50))
        document.addStroke(left)
        #expect(document.applyOverlapCut(baseID: base.id, cutterID: left.id))

        let cut = try #require(document.stroke(with: base.id))
        let outline = ShapeGeometry.renderPoints(for: cut)
        for corner in Self.sharpCorners {
            #expect(!ShapeBooleanEngine.polygon(outline, contains: corner))
        }
        for inside in Self.insideFillets {
            #expect(ShapeBooleanEngine.polygon(outline, contains: inside))
        }
        #expect(!ShapeBooleanEngine.polygon(outline, contains: CGPoint(x: 5, y: 50)))
    }

    /// Just inside each sharp corner of the 200×100 rectangle, outside its radius-20 fillet.
    private static let sharpCorners = [
        CGPoint(x: 1, y: 1), CGPoint(x: 199, y: 1), CGPoint(x: 199, y: 99), CGPoint(x: 1, y: 99)
    ]

    /// Just inside each fillet arc.
    private static let insideFillets = [
        CGPoint(x: 8, y: 8), CGPoint(x: 192, y: 8), CGPoint(x: 192, y: 92), CGPoint(x: 8, y: 92)
    ]

    private static func filletedRectangle(layerID: UUID) -> VectorStroke {
        var rect = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 200, y: 0),
                CGPoint(x: 200, y: 100),
                CGPoint(x: 0, y: 100)
            ],
            isClosed: true,
            shapeType: .rectangle
        )
        rect.cornerRadius = 20
        return rect
    }

    private static func circle(layerID: UUID, center: CGPoint) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.circleCardinalPoints(center: center, radius: 20),
            isClosed: true,
            shapeType: .circle
        )
    }
}
