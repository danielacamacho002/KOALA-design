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

    /// A boundary cut used to rebuild the whole outline from straight samples and
    /// then drop the shallow ones, so a bend that was nowhere near the cutter came
    /// back as a run of corners.
    @Test func cuttingACurveKeepsTheUntouchedBendSmooth() {
        let document = KoalaDocument()
        let base = bulgingOutline(layerID: document.activeLayerID)
        let circle = VectorStroke(
            layerID: document.activeLayerID,
            points: ShapeGeometry.circleCardinalPoints(center: CGPoint(x: 200, y: -30), radius: 80),
            isClosed: true,
            shapeType: .circle
        )
        document.addStroke(base)
        document.addStroke(circle)

        let originalTop = ShapeGeometry.renderPoints(for: base).filter { $0.y > 250 }
        #expect(originalTop.count > 4)
        #expect(maxStepTurn(originalTop) < 12 * .pi / 180)

        #expect(document.punchOverlapHole(at: CGPoint(x: 200, y: 10)))
        let result = document.strokes[0]
        let rendered = ShapeGeometry.renderPoints(for: result)
        let top = rendered.filter { $0.y > 250 }
        #expect(top.count > 4)
        #expect(maxStepTurn(top) < 12 * .pi / 180)
        #expect(maxDistance(from: originalTop, to: rendered) < 5)
        #expect(result.contains(CGPoint(x: 200, y: 160)))
        #expect(!result.contains(CGPoint(x: 200, y: 2)))
    }

    @Test func cuttingWithAnEllipseKeepsTheUntouchedBendSmooth() {
        let document = KoalaDocument()
        let base = bulgingOutline(layerID: document.activeLayerID)
        let ellipse = VectorStroke(
            layerID: document.activeLayerID,
            points: ShapeGeometry.ellipseCardinalPoints(
                center: CGPoint(x: 400, y: 90),
                rx: 90,
                ry: 28
            ),
            isClosed: true,
            shapeType: .ellipse
        )
        document.addStroke(base)
        document.addStroke(ellipse)

        let originalTop = ShapeGeometry.renderPoints(for: base).filter { $0.y > 250 }
        #expect(document.punchOverlapHole(at: CGPoint(x: 360, y: 90)))
        let result = document.strokes[0]
        let rendered = ShapeGeometry.renderPoints(for: result)
        let top = rendered.filter { $0.y > 250 }
        #expect(top.count > 4)
        #expect(maxStepTurn(top) < 12 * .pi / 180)
        #expect(maxDistance(from: originalTop, to: rendered) < 5)
        #expect(!result.contains(CGPoint(x: 400, y: 90)))
    }

    private func bulgingOutline(layerID: UUID) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 400, y: 0),
                CGPoint(x: 400, y: 180),
                CGPoint(x: 0, y: 180)
            ],
            isClosed: true,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(),
                CurveHandle(),
                CurveHandle(outOffset: CGPoint(x: -130, y: 160)),
                CurveHandle(inOffset: CGPoint(x: 130, y: 160))
            ]
        )
    }

    /// Largest turn between consecutive samples. A faceted bend spikes here; a
    /// cubic sampled at the usual rate stays shallow.
    private func maxStepTurn(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var worst: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let incoming = CGPoint(
                x: points[index].x - points[index - 1].x,
                y: points[index].y - points[index - 1].y
            )
            let outgoing = CGPoint(
                x: points[index + 1].x - points[index].x,
                y: points[index + 1].y - points[index].y
            )
            let inLength = hypot(incoming.x, incoming.y)
            let outLength = hypot(outgoing.x, outgoing.y)
            guard inLength > 0.001, outLength > 0.001 else { continue }
            let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
            let dot = incoming.x * outgoing.x + incoming.y * outgoing.y
            worst = max(worst, abs(atan2(cross, dot)))
        }
        return worst
    }

    private func maxDistance(from samples: [CGPoint], to outline: [CGPoint]) -> CGFloat {
        guard outline.count >= 2 else { return .greatestFiniteMagnitude }
        var worst: CGFloat = 0
        for sample in samples {
            var best = CGFloat.greatestFiniteMagnitude
            for index in 0..<outline.count {
                let start = outline[index]
                let end = outline[(index + 1) % outline.count]
                let dx = end.x - start.x
                let dy = end.y - start.y
                let lengthSquared = dx * dx + dy * dy
                let t: CGFloat
                if lengthSquared <= 1e-8 {
                    t = 0
                } else {
                    t = max(0, min(1, ((sample.x - start.x) * dx + (sample.y - start.y) * dy) / lengthSquared))
                }
                let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
                best = min(best, hypot(sample.x - projection.x, sample.y - projection.y))
            }
            worst = max(worst, best)
        }
        return worst
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
