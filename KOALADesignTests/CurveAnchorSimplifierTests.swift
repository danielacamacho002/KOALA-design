import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

/// Sampled curves used to keep every render vertex as an anchor. Selecting or
/// joining then wrote that chain back, so thinning the curve never stuck.
@MainActor
struct CurveAnchorSimplifierTests {
    private let layerID = UUID()

    @Test func sampledCubicCollapsesToAFewAnchors() {
        let anchors = [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)]
        let handles = [
            CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 80, y: 120)),
            CurveHandle(inOffset: CGPoint(x: -80, y: 120), outOffset: .zero)
        ]
        let samples = ShapeGeometry.curvePoints(anchors: anchors, handles: handles, closed: false)
        let dense = VectorStroke(
            layerID: layerID,
            points: samples,
            isClosed: false,
            shapeType: .polyline
        )
        #expect(dense.points.count > 20)

        let simplified = ShapeGeometry.withSimplifiedDenseAnchors(dense)
        #expect(simplified.points.count <= 6)
        #expect(simplified.shapeType == .curve)
        #expect(simplified.curveHandles?.count == simplified.points.count)
        let rendered = ShapeGeometry.renderPoints(for: simplified)
        #expect((rendered.map(\.y).max() ?? 0) > 80)
        #expect(maxDistance(from: samples, to: simplified) < 4)

        let again = ShapeGeometry.withCompactedCircularAnchors(simplified)
        #expect(again.points.count <= simplified.points.count)
    }

    @Test func closedOutlineKeepsCornersAndDropsStraightSamples() {
        let top = ShapeGeometry.curvePoints(
            anchors: [CGPoint(x: 0, y: 80), CGPoint(x: 200, y: 80)],
            handles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 60, y: 70)),
                CurveHandle(inOffset: CGPoint(x: -60, y: 70), outOffset: .zero)
            ],
            closed: false
        )
        var points = top
        points.append(contentsOf: samples(from: CGPoint(x: 200, y: 80), to: CGPoint(x: 200, y: 0), count: 18))
        points.append(contentsOf: samples(from: CGPoint(x: 200, y: 0), to: CGPoint(x: 0, y: 0), count: 18).dropFirst())
        points.append(contentsOf: samples(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 80), count: 18).dropFirst())
        let dense = VectorStroke(
            layerID: layerID,
            points: points,
            isClosed: true,
            shapeType: .polyline
        )
        #expect(dense.points.count > 50)

        let simplified = ShapeGeometry.withSimplifiedDenseAnchors(dense)
        #expect(simplified.points.count < 12)
        #expect(simplified.isClosed)
        let rendered = ShapeGeometry.renderPoints(for: simplified)
        #expect((rendered.map(\.y).max() ?? 0) > 100)
        #expect(rendered.contains { hypot($0.x - 200, $0.y) < 1.5 && abs($0.y) < 1.5 })
        #expect(maxDistance(from: points, to: simplified) < 4)
    }

    @Test func authoredCurveIsLeftAlone() {
        let curve = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 40), CGPoint(x: 160, y: 0)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(outOffset: CGPoint(x: 20, y: 30)),
                CurveHandle(inOffset: CGPoint(x: -16, y: 10), outOffset: CGPoint(x: 16, y: 10)),
                CurveHandle(inOffset: CGPoint(x: -20, y: 30))
            ]
        )
        let simplified = ShapeGeometry.withSimplifiedDenseAnchors(curve)
        #expect(simplified.points == curve.points)
        #expect(simplified.curveHandles == curve.curveHandles)
    }

    @Test func denseSquareKeepsFourSharpCorners() {
        var points: [CGPoint] = []
        func add(_ start: CGPoint, _ end: CGPoint) {
            for step in 0..<12 {
                let t = CGFloat(step) / 12
                points.append(CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                ))
            }
        }
        add(CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0))
        add(CGPoint(x: 200, y: 0), CGPoint(x: 200, y: 120))
        add(CGPoint(x: 200, y: 120), CGPoint(x: 0, y: 120))
        add(CGPoint(x: 0, y: 120), CGPoint(x: 0, y: 0))
        let dense = VectorStroke(
            layerID: layerID,
            points: points,
            isClosed: true,
            shapeType: .polyline
        )

        let simplified = ShapeGeometry.withSimplifiedDenseAnchors(dense)
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 200, y: 0),
            CGPoint(x: 200, y: 120),
            CGPoint(x: 0, y: 120)
        ]
        #expect(simplified.points.count == corners.count)
        for corner in corners {
            #expect(simplified.points.contains { hypot($0.x - corner.x, $0.y - corner.y) < 0.05 })
        }
        let handles = simplified.curveHandles ?? []
        #expect(handles.allSatisfy { handle in
            hypot(handle.inOffset.x, handle.inOffset.y) < 0.05
                && hypot(handle.outOffset.x, handle.outOffset.y) < 0.05
        })
    }

    @Test func sharpZigzagKeepsItsCorners() {
        var points: [CGPoint] = []
        for index in 0..<18 {
            let x = CGFloat(index) * 20
            points.append(CGPoint(x: x, y: index.isMultiple(of: 2) ? 0 : 30))
        }
        let zigzag = VectorStroke(
            layerID: layerID,
            points: points,
            isClosed: false,
            shapeType: .polyline
        )
        let simplified = ShapeGeometry.withSimplifiedDenseAnchors(zigzag)
        #expect(simplified.points.count == zigzag.points.count)
    }

    @Test func selectingASampledCurvePersistsTheReduction() {
        let samples = ShapeGeometry.curvePoints(
            anchors: [CGPoint(x: 0, y: 0), CGPoint(x: 180, y: 0)],
            handles: [
                CurveHandle(outOffset: CGPoint(x: 40, y: 90)),
                CurveHandle(inOffset: CGPoint(x: -70, y: 90))
            ],
            closed: false
        )
        let dense = VectorStroke(
            layerID: layerID,
            points: samples,
            isClosed: false,
            shapeType: .polyline
        )
        let document = KoalaDocument()
        var stroke = dense
        stroke.layerID = document.activeLayerID
        document.strokes = [stroke]
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])

        let stored = document.strokes[0]
        #expect(stored.points.count <= 4)
        #expect(stored.shapeType == .curve)

        document.compactCircularAnchors(for: [stroke.id])
        #expect(document.strokes[0].points.count == stored.points.count)
    }

    @Test func bakedSmoothSamplesCollapseWithoutRedrawing() {
        let samples = ShapeGeometry.curvePoints(
            anchors: [CGPoint(x: 0, y: 0), CGPoint(x: 220, y: 0)],
            handles: [
                CurveHandle(outOffset: CGPoint(x: 70, y: 110)),
                CurveHandle(inOffset: CGPoint(x: -70, y: 110))
            ],
            closed: false
        )
        var dense = VectorStroke(
            layerID: layerID,
            points: samples,
            isClosed: false,
            smoothCornerIndices: Set(samples.indices.dropFirst().dropLast()),
            shapeType: .polyline
        )
        #expect(dense.hasBakedSmoothCorners)
        #expect(dense.points.count > 20)

        let simplified = ShapeGeometry.withSimplifiedDenseAnchors(dense)
        #expect(simplified.points.count <= 6)
        #expect(!simplified.hasBakedSmoothCorners)
        #expect((ShapeGeometry.renderPoints(for: simplified).map(\.y).max() ?? 0) > 70)

        let document = KoalaDocument()
        dense.layerID = document.activeLayerID
        document.strokes = [dense]
        #expect(document.simplifyStoredDenseAnchors())
        #expect(document.strokes[0].points.count <= 6)
        #expect(!document.simplifyStoredDenseAnchors())
    }

    private func samples(from start: CGPoint, to end: CGPoint, count: Int) -> [CGPoint] {
        (0..<count).map { step in
            let t = CGFloat(step) / CGFloat(count - 1)
            return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }

    private func maxDistance(from samples: [CGPoint], to stroke: VectorStroke) -> CGFloat {
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        guard rendered.count >= 2 else { return .greatestFiniteMagnitude }
        let segmentCount = stroke.isClosed ? rendered.count : rendered.count - 1
        var worst: CGFloat = 0
        for sample in samples {
            var best = CGFloat.greatestFiniteMagnitude
            for index in 0..<segmentCount {
                let start = rendered[index]
                let end = rendered[(index + 1) % rendered.count]
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
}
