import CoreGraphics
import Foundation
import Testing
@testable import Koala

/// Cutting a square with a circle must leave the square's corners as corners.
/// Only the boundary that lies on the circle becomes an arc.
@MainActor
struct BooleanCutCornerTests {
    @Test func cuttingACornerKeepsTheOtherCornersSharp() {
        let document = KoalaDocument()
        let square = rectangle(layerID: document.activeLayerID, width: 400, height: 300)
        let circle = VectorStroke(
            layerID: document.activeLayerID,
            points: ShapeGeometry.circleCardinalPoints(center: CGPoint(x: 400, y: 300), radius: 80),
            isClosed: true,
            shapeType: .circle
        )
        document.addStroke(square)
        document.addStroke(circle)

        #expect(document.punchOverlapHole(at: CGPoint(x: 360, y: 260)))
        #expect(document.strokes.count == 1)
        let result = document.strokes[0]

        #expect(result.shapeType == .polyline)
        #expect(result.curveHandles == nil)
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 0), CGPoint(x: 0, y: 300)]
        let smooth = result.smoothCornerIndices ?? []
        #expect(!smooth.isEmpty)
        for corner in corners {
            let index = result.points.firstIndex { hypot($0.x - corner.x, $0.y - corner.y) < 0.5 }
            #expect(index != nil)
            if let index {
                #expect(!smooth.contains(index))
            }
        }
        for index in smooth {
            let point = result.points[index]
            #expect(point.x > 0 && point.x < 400 && point.y > 0 && point.y < 300)
            #expect(abs(hypot(point.x - 400, point.y - 300) - 80) < 2)
        }

        let junctions = result.points.enumerated().compactMap { index, point -> CGPoint? in
            guard !smooth.contains(index) else { return nil }
            let isOriginalCorner = corners.contains { hypot(point.x - $0.x, point.y - $0.y) < 0.5 }
            return isOriginalCorner ? nil : point
        }
        #expect(junctions.count == 2)
        #expect(junctions.contains { abs($0.x - 400) < 1 && abs($0.y - 220) < 2 })
        #expect(junctions.contains { abs($0.y - 300) < 1 && abs($0.x - 320) < 2 })

        let rendered = ShapeGeometry.renderPoints(for: result)
        let arc = rendered.filter { hypot($0.x - 400, $0.y - 300) < 90 }
        #expect(arc.count > 4)
        #expect(arc.allSatisfy { abs(hypot($0.x - 400, $0.y - 300) - 80) < 1.5 })
        #expect(arc.allSatisfy { $0.x <= 400.5 && $0.y <= 300.5 })

        #expect(result.contains(CGPoint(x: 20, y: 20)))
        #expect(!result.contains(CGPoint(x: 390, y: 290)))
    }

    @Test func cuttingAnEdgeDoesNotRoundTheSquaresCorners() {
        let document = KoalaDocument()
        let square = rectangle(layerID: document.activeLayerID, width: 400, height: 300)
        let circle = VectorStroke(
            layerID: document.activeLayerID,
            points: ShapeGeometry.circleCardinalPoints(center: CGPoint(x: 200, y: -30), radius: 80),
            isClosed: true,
            shapeType: .circle
        )
        document.addStroke(square)
        document.addStroke(circle)

        #expect(document.punchOverlapHole(at: CGPoint(x: 200, y: 10)))
        let result = document.strokes[0]
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 400, y: 0),
            CGPoint(x: 400, y: 300),
            CGPoint(x: 0, y: 300)
        ]
        let smooth = result.smoothCornerIndices ?? []
        for corner in corners {
            let index = result.points.firstIndex { hypot($0.x - corner.x, $0.y - corner.y) < 0.5 }
            #expect(index != nil)
            if let index {
                #expect(!smooth.contains(index))
            }
        }
        #expect(result.curveHandles == nil)
        #expect(result.contains(CGPoint(x: 200, y: 80)))
        #expect(!result.contains(CGPoint(x: 200, y: 2)))
    }

    private func rectangle(layerID: UUID, width: CGFloat, height: CGFloat) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: width, y: 0),
                CGPoint(x: width, y: height),
                CGPoint(x: 0, y: height)
            ],
            isClosed: true,
            shapeType: .rectangle
        )
    }
}
