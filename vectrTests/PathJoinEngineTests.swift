import CoreGraphics
import Foundation
import Testing
@testable import vectr

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
