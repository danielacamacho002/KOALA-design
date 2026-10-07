import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct PathJoinEngineTests {
    private let layerID = UUID()
    private let joinTolerance: CGFloat = 10

    /// Two open cubic lobes that meet at one endpoint. Import used to tessellate
    /// them; Join then rewrote those samples as circular arcs and the S collapsed.
    @Test func joiningImportedOpenCubicsKeepsTheBezierLobes() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path fill="none" stroke="black" d="M 0 0 C 0 100 50 100 50 0"/>
          <path fill="none" stroke="black" d="M 50 0 C 50 -100 100 -100 100 0"/>
        </svg>
        """
        let imported = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(imported.count == 2)
        #expect(imported.allSatisfy { $0.shapeType == .curve })

        let joined = PathJoinEngine.join(imported, tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let after = ShapeGeometry.renderPoints(for: stroke)
        #expect((after.map(\.y).max() ?? 0) > 60)
        #expect((after.map(\.y).min() ?? 0) < -60)
        #expect(!stroke.isClosed)
        #expect(stroke.shapeType == .curve)
        #expect((stroke.curveHandles?.count ?? 0) == stroke.points.count)
        #expect(stroke.points.count == 3)
    }

    /// An open cubic C joined to a straight tail must keep the C's bulge, not
    /// flatten into a chord or a short circular arc.
    @Test func joiningImportedOpenCubicToALineKeepsTheBulge() {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg">
          <path fill="none" stroke="black" d="M 0 0 C 0 100 50 100 50 0"/>
          <path fill="none" stroke="black" d="M 50 0 L 120 0"/>
        </svg>
        """
        let imported = SVGImporter.parse(xml: xml, layerID: layerID).strokes
        #expect(imported.count == 2)

        let joined = PathJoinEngine.join(imported, tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let after = ShapeGeometry.renderPoints(for: stroke)
        #expect((after.map(\.y).max() ?? 0) > 60)
        #expect(stroke.shapeType != .arc)
        #expect(!stroke.isClosed)
    }

    /// Documents imported before curves kept their handles still tessellate to a
    /// dense polyline. Join must not rewrite those samples as a collapsed arc.
    @Test func joiningLegacyTessellatedOpenCubicsKeepsTheBezierLobes() {
        let leftAnchors = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0)]
        let leftHandles = [
            CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: 100)),
            CurveHandle(inOffset: CGPoint(x: 0, y: 100), outOffset: .zero)
        ]
        let rightAnchors = [CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)]
        let rightHandles = [
            CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: -100)),
            CurveHandle(inOffset: CGPoint(x: 0, y: -100), outOffset: .zero)
        ]
        let left = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.curvePoints(anchors: leftAnchors, handles: leftHandles, closed: false),
            isClosed: false,
            shapeType: .polyline
        )
        let right = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.curvePoints(anchors: rightAnchors, handles: rightHandles, closed: false),
            isClosed: false,
            shapeType: .polyline
        )

        let joined = PathJoinEngine.join([left, right], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let after = ShapeGeometry.renderPoints(for: stroke)
        #expect((after.map(\.y).max() ?? 0) > 60)
        #expect((after.map(\.y).min() ?? 0) < -60)
        #expect(stroke.shapeType != .arc)
        #expect(stroke.shapeType != .circle)
    }

    /// Native open curves (not SVG) must also keep their tessellated lobes
    /// through Join instead of collapsing to a few circular anchors.
    @Test func joiningOpenCurvesKeepsBezierGeometry() {
        let left = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: 100)),
                CurveHandle(inOffset: CGPoint(x: 0, y: 100), outOffset: .zero)
            ]
        )
        let right = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: -100)),
                CurveHandle(inOffset: CGPoint(x: 0, y: -100), outOffset: .zero)
            ]
        )

        let joined = PathJoinEngine.join([left, right], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let after = ShapeGeometry.renderPoints(for: stroke)
        #expect((after.map(\.y).max() ?? 0) > 60)
        #expect((after.map(\.y).min() ?? 0) < -60)
        #expect(stroke.shapeType == .curve)
        #expect(stroke.points.count == 3)
    }

    /// A Bézier welded to a straight run and a closed shape must keep its bulge.
    /// Mixing in a rectangle leaves the outline-chain path, and compaction used to
    /// drop the cubic handles so the lobe fell back to a chord.
    @Test func joiningBezierWithLineAndRectangleKeepsTheBulge() {
        let curve = openBulge()
        let line = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)],
            isClosed: false,
            shapeType: .polyline
        )
        let rectangle = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 100, y: 0),
                CGPoint(x: 160, y: 0),
                CGPoint(x: 160, y: 40),
                CGPoint(x: 100, y: 40)
            ],
            isClosed: true,
            shapeType: .rectangle
        )

        let joined = PathJoinEngine.join([curve, line, rectangle], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        #expect(rendered.contains { hypot($0.x - 25, $0.y - 75) < 8 })
        #expect(rendered.contains { hypot($0.x - 160, $0.y - 40) < 1 })
    }

    /// A quarter-circle cubic used to be demoted to a smooth midpoint, which then
    /// drew as an arc. Joining that arc to another line flattened the sweep.
    @Test func joiningNearCircularCubicToLinesKeepsTheCubic() {
        let radius: CGFloat = 100
        let kappa = radius * 4 / 3 * tan(.pi / 8)
        let curve = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: radius, y: 0), CGPoint(x: 0, y: radius)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: kappa)),
                CurveHandle(inOffset: CGPoint(x: kappa, y: 0), outOffset: .zero)
            ]
        )
        let line = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: radius), CGPoint(x: 0, y: 170)],
            isClosed: false,
            shapeType: .polyline
        )

        let joined = PathJoinEngine.join([curve, line], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        #expect(stroke.shapeType == .curve)
        #expect(stroke.curveHandles?.count == stroke.points.count)
        #expect(rendersQuarterCirclePeak(stroke))

        let tail = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 170), CGPoint(x: 40, y: 170)],
            isClosed: false,
            shapeType: .polyline
        )
        let extended = PathJoinEngine.join([stroke, tail], tolerance: joinTolerance)
        #expect(extended?.count == 1)
        guard let again = extended?.first else { return }
        #expect(again.shapeType == .curve)
        #expect(again.curveHandles?.count == again.points.count)
        #expect(rendersQuarterCirclePeak(again))
        let rendered = ShapeGeometry.renderPoints(for: again)
        #expect(rendered.contains { hypot($0.x - 40, $0.y - 170) < 1 })
    }

    /// Demotion stores a quarter-circle cubic as a polyline with one smooth midpoint.
    /// Joining that to a straight line must keep the sweep, not the chord.
    @Test func joiningDemotedCircularPolylineToALineKeepsTheSweep() {
        let radius: CGFloat = 100
        let kappa = radius * 4 / 3 * tan(.pi / 8)
        let start = CGPoint(x: radius, y: 0)
        let end = CGPoint(x: 0, y: radius)
        let mid = ShapeGeometry.cubicBezierPoint(
            start,
            CGPoint(x: start.x, y: kappa),
            CGPoint(x: kappa, y: end.y),
            end,
            t: 0.5
        )
        let demoted = VectorStroke(
            layerID: layerID,
            points: [start, mid, end],
            isClosed: false,
            smoothCornerIndices: [1]
        )
        let line = VectorStroke(
            layerID: layerID,
            points: [end, CGPoint(x: 0, y: 170)],
            isClosed: false,
            shapeType: .polyline
        )

        let joined = PathJoinEngine.join([demoted, line], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        #expect(stroke.shapeType == .polyline)
        #expect(stroke.smoothCornerIndices?.contains(1) == true)
        #expect(rendersQuarterCirclePeak(stroke))
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        #expect(rendered.contains { hypot($0.x, $0.y - 170) < 1 })
    }

    /// A native arc welded to a straight run keeps its radius instead of falling to the chord.
    @Test func joiningArcToALineKeepsTheSweep() {
        let quarter = arc(startDegrees: 0, sweepDegrees: 90)
        let line = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 170)],
            isClosed: false,
            shapeType: .polyline
        )

        let joined = PathJoinEngine.join([quarter, line], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        #expect(rendersQuarterCirclePeak(stroke))
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        #expect(rendered.contains { hypot($0.x, $0.y - 170) < 1 })
        #expect(stroke.shapeType != .curve || (stroke.curveHandles?.count == stroke.points.count))
    }

    /// Touching a circle at a cardinal is a real weld. The cubic must survive
    /// beside the circle instead of being flattened when the rim is compacted.
    @Test func joiningBezierWithCircleKeepsTheBulge() {
        let curve = openBulge(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 0))
        let circle = VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.circleCardinalPoints(center: CGPoint(x: 150, y: 0), radius: 100),
            isClosed: true,
            shapeType: .circle
        )

        let joined = PathJoinEngine.join([curve, circle], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        #expect(rendered.contains { hypot($0.x - 25, $0.y - 75) < 8 })
        #expect((rendered.map(\.x).max() ?? 0) > 240)
    }

    /// Two quarter-circles that meet at a cardinal still join into a semicircle.
    @Test func joiningOpenArcsKeepsTheSweep() {
        let first = arc(startDegrees: 0, sweepDegrees: 90)
        let second = arc(startDegrees: 90, sweepDegrees: 90)

        let joined = PathJoinEngine.join([first, second], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let after = ShapeGeometry.renderPoints(for: stroke)
        #expect((after.map(\.y).max() ?? 0) > 90)
        #expect((after.map(\.x).min() ?? 0) < -90)
        #expect(!stroke.isClosed)
    }

    /// The 45° point of a radius-100 quarter circle. A collapsed chord sits near (50, 50).
    private func rendersQuarterCirclePeak(_ stroke: VectorStroke) -> Bool {
        let peak = CGPoint(x: 100 * cos(CGFloat.pi / 4), y: 100 * sin(CGFloat.pi / 4))
        return ShapeGeometry.renderPoints(for: stroke).contains { hypot($0.x - peak.x, $0.y - peak.y) < 8 }
    }

    private func openBulge(
        from start: CGPoint = CGPoint(x: 0, y: 0),
        to end: CGPoint = CGPoint(x: 50, y: 0)
    ) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [start, end],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: 100)),
                CurveHandle(inOffset: CGPoint(x: 0, y: 100), outOffset: .zero)
            ]
        )
    }

    private func arc(startDegrees: CGFloat, sweepDegrees: CGFloat) -> VectorStroke {
        let radius: CGFloat = 100
        func onCircle(_ degrees: CGFloat) -> CGPoint {
            let radians = degrees * .pi / 180
            return CGPoint(x: cos(radians) * radius, y: sin(radians) * radius)
        }
        let start = onCircle(startDegrees)
        let end = onCircle(startDegrees + sweepDegrees)
        let anchors = ShapeGeometry.defaultCircularAnchors(
            center: .zero,
            radius: radius,
            start: start,
            end: end,
            sweep: sweepDegrees * .pi / 180,
            closed: false
        )
        return VectorStroke(
            layerID: layerID,
            points: anchors,
            isClosed: false,
            shapeType: .arc
        )
    }
}
