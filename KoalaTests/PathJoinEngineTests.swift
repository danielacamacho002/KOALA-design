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

    /// Mirrored open halves whose boundary lines sit on the same line, shifted so
    /// no endpoints meet. Join has to see that stacked run and close the outline.
    @Test func joiningStackedOverlapClosesTheOutline() {
        let left = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: -100, y: 0),
                CGPoint(x: -100, y: 100),
                CGPoint(x: 0, y: 100)
            ],
            isClosed: false,
            shapeType: .polyline
        )
        let right = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: -20, y: 0),
                CGPoint(x: 80, y: 0),
                CGPoint(x: 80, y: 100),
                CGPoint(x: -20, y: 100)
            ],
            isClosed: false,
            shapeType: .polyline
        )

        #expect(PathJoinEngine.canJoin([left, right], tolerance: joinTolerance))
        let joined = PathJoinEngine.join([left, right], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        #expect(stroke.isClosed)
        #expect(stroke.points.contains { hypot($0.x + 100, $0.y) < 1 })
        #expect(stroke.points.contains { hypot($0.x + 100, $0.y - 100) < 1 })
        #expect(stroke.points.contains { hypot($0.x - 80, $0.y - 100) < 1 })
        #expect(stroke.points.contains { hypot($0.x - 80, $0.y) < 1 })
    }

    /// A sleeve outline: gentle cubics, straight lines, and one deep concave cubic.
    /// Join used to close the loop and replace that concavity with its chord.
    @Test func joiningAClosedSleeveKeepsTheConcaveCubic() {
        let top = cubic(
            from: CGPoint(x: 0, y: 160),
            to: CGPoint(x: 400, y: 180),
            out: CGPoint(x: 80, y: 30),
            inn: CGPoint(x: -80, y: 20)
        )
        let right = line(CGPoint(x: 400, y: 180), CGPoint(x: 420, y: 70))
        let bottom = cubic(
            from: CGPoint(x: 420, y: 70),
            to: CGPoint(x: 80, y: 30),
            out: CGPoint(x: -40, y: -25),
            inn: CGPoint(x: 60, y: -20)
        )
        let step = line(CGPoint(x: 80, y: 30), CGPoint(x: 50, y: 70))
        let underarm = cubic(
            from: CGPoint(x: 50, y: 70),
            to: CGPoint(x: 0, y: 160),
            out: CGPoint(x: 70, y: 10),
            inn: CGPoint(x: 40, y: -50)
        )
        let bulge = ShapeGeometry.cubicBezierPoint(
            CGPoint(x: 50, y: 70),
            CGPoint(x: 120, y: 80),
            CGPoint(x: 40, y: 110),
            CGPoint(x: 0, y: 160),
            t: 0.5
        )
        #expect(bulge.x > 60, "fixture bulge is \(bulge)")

        let joined = PathJoinEngine.join([top, right, bottom, step, underarm], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        #expect(
            rendered.contains { hypot($0.x - bulge.x, $0.y - bulge.y) < 12 },
            "joined \(stroke.shapeType) closed=\(stroke.isClosed) points=\(stroke.points.count) missed bulge \(bulge)"
        )
        #expect(rendered.contains { hypot($0.x - 400, $0.y - 180) < 8 })
    }

    /// Sleeve armhole: a sharp notch vertex and a cubic that swings well clear of
    /// the shoulder-to-step chord. Join must keep both, including when another
    /// edge is stacked and when the armhole is one multi-anchor curve.
    @Test func joiningASleeveNotchKeepsTheHook() {
        let shoulder = CGPoint(x: 0, y: 200)
        let tip = CGPoint(x: -80, y: 150)
        let stepTop = CGPoint(x: 70, y: 40)
        let stepBottom = CGPoint(x: 70, y: 10)
        let topEnd = CGPoint(x: 400, y: 210)
        let rightEnd = CGPoint(x: 420, y: 80)

        let top = cubic(from: shoulder, to: topEnd, out: CGPoint(x: 90, y: 24), inn: CGPoint(x: -80, y: 12))
        let right = line(topEnd, rightEnd)
        let bottom = cubic(from: rightEnd, to: stepBottom, out: CGPoint(x: -50, y: -28), inn: CGPoint(x: 60, y: -16))
        let step = line(stepBottom, stepTop)
        let notch = line(shoulder, tip)
        let underarm = cubic(
            from: tip,
            to: stepTop,
            out: CGPoint(x: 30, y: -80),
            inn: CGPoint(x: -110, y: 20)
        )
        let bulge = ShapeGeometry.cubicBezierPoint(
            tip,
            CGPoint(x: tip.x + 30, y: tip.y - 80),
            CGPoint(x: stepTop.x - 110, y: stepTop.y + 20),
            stepTop,
            t: 0.5
        )
        #expect(distanceFromChord(bulge, shoulder, stepTop) > 40, "fixture bulge \(bulge)")

        let pieces = [top, right, bottom, step, notch, underarm]
        expectHook(PathJoinEngine.join(pieces, tolerance: joinTolerance) ?? [], named: "separate edges", tip: tip, bulge: bulge)

        let overlapped = pieces + [line(CGPoint(x: 404, y: 184), CGPoint(x: 416, y: 106))]
        expectHook(PathJoinEngine.join(overlapped, tolerance: joinTolerance) ?? [], named: "stacked edge", tip: tip, bulge: bulge)

        let armhole = VectorStroke(
            layerID: layerID,
            points: [shoulder, tip, stepTop],
            isClosed: false,
            shapeType: .curve,
            curveHandles: ShapeGeometry.defaultCurveHandles(anchors: [shoulder, tip, stepTop])
        )
        let asOneCurve = [top, right, bottom, step, armhole]
        expectHook(PathJoinEngine.join(asOneCurve, tolerance: joinTolerance) ?? [], named: "one curve", tip: tip, bulge: tip)

        let smooth = VectorStroke(
            layerID: layerID,
            points: [shoulder, tip, stepTop],
            isClosed: false,
            smoothCornerIndices: [1]
        )
        expectHook(
            PathJoinEngine.join([top, right, bottom, step, smooth], tolerance: joinTolerance) ?? [],
            named: "smooth notch",
            tip: tip,
            bulge: tip
        )

        let arcArm = VectorStroke(
            layerID: layerID,
            points: [shoulder, tip, stepTop],
            isClosed: false,
            shapeType: .arc
        )
        expectHook(
            PathJoinEngine.join([top, right, bottom, step, arcArm], tolerance: joinTolerance) ?? [],
            named: "arc armhole",
            tip: tip,
            bulge: tip
        )

        let document = KoalaDocument()
        let layer = document.activeLayerID
        func onLayer(_ stroke: VectorStroke) -> VectorStroke {
            var copy = stroke
            copy.layerID = layer
            return copy
        }
        for stroke in [top, right, bottom, step, notch, underarm].map(onLayer) {
            document.addStroke(stroke)
        }
        document.setElementSelection(
            strokeIDs: Set(document.strokes.map(\.id)),
            textIDs: [],
            compactAnchors: false
        )
        #expect(document.joinSelectedShapes())
        expectHook(document.strokes, named: "document join", tip: tip, bulge: bulge)
    }

    /// A notch tucked against a nearly straight circular run must survive Join.
    /// Circle fitting used a tolerance of 2.5% of the radius, so a huge, almost
    /// flat circle swallowed an armhole notch and replaced it with the chord.
    @Test func joiningANotchOnAShallowArcKeepsTheTip() {
        let center = CGPoint(x: 0, y: -5000)
        let radius: CGFloat = 5000
        func onRim(_ theta: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + sin(theta) * radius,
                y: center.y + cos(theta) * radius
            )
        }
        var samples = (0...15).map { onRim(-0.04 + 0.08 * CGFloat($0) / 15) }
        let mid = samples[8]
        let tip = CGPoint(x: mid.x, y: mid.y + 80)
        samples[8] = tip
        #expect(abs(hypot(tip.x - center.x, tip.y - center.y) - radius) > 70)
        #expect(abs(hypot(tip.x - center.x, tip.y - center.y) - radius) < radius * 0.025)

        let armhole = VectorStroke(
            layerID: layerID,
            points: samples,
            isClosed: false,
            shapeType: .polyline
        )
        let tailEnd = CGPoint(x: samples[15].x + 30, y: samples[15].y - 80)
        let tail = line(samples[15], tailEnd)
        let hook = VectorStroke(
            layerID: layerID,
            points: [
                tailEnd,
                CGPoint(x: tailEnd.x + 18, y: tailEnd.y - 24),
                CGPoint(x: tailEnd.x + 40, y: tailEnd.y - 6)
            ],
            isClosed: false,
            shapeType: .arc
        )
        let topStart = samples[0]
        let topEnd = CGPoint(x: topStart.x - 160, y: topStart.y + 30)
        let topPeak = CGPoint(x: topStart.x - 80, y: topStart.y + 70)
        let top = VectorStroke(
            layerID: layerID,
            points: [topStart, topPeak, topEnd],
            isClosed: false,
            smoothCornerIndices: [1]
        )

        let compacted = ShapeGeometry.withCompactedCircularAnchors(
            armhole,
            rewritingPartialRuns: true,
            preservingBezierHandles: false
        )
        let compactedRender = ShapeGeometry.renderPoints(for: compacted)
        #expect(
            compactedRender.contains { hypot($0.x - tip.x, $0.y - tip.y) < 8 },
            "compaction ate the notch; type=\(compacted.shapeType) n=\(compacted.points.count)"
        )

        let joined = PathJoinEngine.join([top, armhole, tail, hook], tolerance: joinTolerance) ?? []
        #expect(joined.count == 1, "joined into \(joined.count)")
        expectHook(joined, named: "shallow arc", tip: tip, bulge: topPeak)
    }

    /// The notch, the short vertical, and the underarm are one polyline that also
    /// owns a stacked edge. Fusion has to keep those anchors, not the chord.
    @Test func joiningAZigzagOwnedByAStackedEdgeKeepsTheTip() {
        let shoulder = CGPoint(x: 0, y: 200)
        let tip = CGPoint(x: -80, y: 150)
        let vert = CGPoint(x: -80, y: 110)
        let stepTop = CGPoint(x: 70, y: 40)
        let stepBottom = CGPoint(x: 70, y: 10)
        let topEnd = CGPoint(x: 400, y: 210)
        let rightEnd = CGPoint(x: 420, y: 80)

        let sleeve = VectorStroke(
            layerID: layerID,
            points: [topEnd, shoulder, tip, vert, stepTop, stepBottom, rightEnd],
            isClosed: false,
            shapeType: .polyline
        )
        // Lies on the topEnd→shoulder edge so stacked-line fusion atomizes the sleeve.
        let stackedTop = line(CGPoint(x: 360, y: 209), CGPoint(x: 40, y: 201))
        let bottom = cubic(
            from: rightEnd,
            to: stepBottom,
            out: CGPoint(x: -40, y: -36),
            inn: CGPoint(x: 50, y: -18)
        )

        let joined = PathJoinEngine.join([sleeve, stackedTop, bottom], tolerance: joinTolerance) ?? []
        expectHook(joined, named: "stacked zigzag", tip: tip, bulge: vert)
    }

    /// Straight edges that sit on each other must not throw away a cubic that
    /// shares the outline. Stacked-line fusion used to trace only the chords.
    @Test func joiningStackedLinesBesideACubicKeepsTheBulge() {
        let top = line(CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100))
        let overlappingTop = line(CGPoint(x: 40, y: 100), CGPoint(x: 160, y: 100))
        let right = line(CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 0))
        let bottom = line(CGPoint(x: 200, y: 0), CGPoint(x: 0, y: 0))
        let underarm = cubic(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 0, y: 100),
            out: CGPoint(x: 80, y: 0),
            inn: CGPoint(x: 80, y: 0)
        )

        let joined = PathJoinEngine.join(
            [top, overlappingTop, right, bottom, underarm],
            tolerance: joinTolerance
        )
        let rendered = (joined ?? []).flatMap { ShapeGeometry.renderPoints(for: $0) }
        #expect(rendered.contains { hypot($0.x - 60, $0.y - 50) < 12 })
    }

    /// Parallel lines a short distance apart are not the same edge.
    @Test func nearbyParallelLinesDoNotJoin() {
        let top = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            isClosed: false,
            shapeType: .polyline
        )
        let bottom = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 20), CGPoint(x: 100, y: 20)],
            isClosed: false,
            shapeType: .polyline
        )
        #expect(!PathJoinEngine.canJoin([top, bottom], tolerance: joinTolerance))
    }

    /// A line that ends on a corner of a closed shape, not on that shape's
    /// first or last point, is still a join.
    @Test func lineEndingOnAMiddleCornerCanJoin() {
        let shape = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 100),
                CGPoint(x: 0, y: 100)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        let spur = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 100, y: 0), CGPoint(x: 140, y: 40)],
            isClosed: false,
            shapeType: .polyline
        )

        #expect(PathJoinEngine.canJoin([shape, spur], tolerance: joinTolerance))
        let joined = PathJoinEngine.join([shape, spur], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        let points = joined?.first?.points ?? []
        #expect(points.contains { hypot($0.x - 140, $0.y - 40) < 0.01 })
        #expect(points.contains { hypot($0.x - 100, $0.y - 100) < 0.01 })
    }

    /// A closed lens whose bulges are baked smooth corners must stay curved
    /// after it is welded into the outline. Dropping those midpoints draws a diamond.
    @Test func joiningASmoothLensIntoAShapeKeepsTheBulge() {
        let shape = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 120, y: 0),
                CGPoint(x: 120, y: 80),
                CGPoint(x: 0, y: 80)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        var lens = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 60, y: -30),
                CGPoint(x: 120, y: 0),
                CGPoint(x: 60, y: 30)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        lens.smoothCornerIndices = [1, 3]

        let joined = PathJoinEngine.join([shape, lens], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        #expect(stroke.smoothCornerIndices?.isEmpty == false)
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        #expect(rendered.count > stroke.points.count)
        #expect(rendered.contains { hypot($0.x - 60, $0.y - 30) < 1 })
    }

    /// Curves that only sit inside a selected outline join to each other.
    /// Splicing them into the outline traced each cubic twice and drew a diamond.
    @Test func joiningCurvesInsideAShapeDoesNotCopyThemIntoTheOutline() {
        let outline = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 200, y: 0),
                CGPoint(x: 200, y: 80),
                CGPoint(x: 200, y: 160),
                CGPoint(x: 0, y: 160),
                CGPoint(x: 0, y: 80)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        let left = cubic(
            from: CGPoint(x: 0, y: 80),
            to: CGPoint(x: 100, y: 80),
            out: CGPoint(x: 0, y: 40),
            inn: CGPoint(x: 0, y: 40)
        )
        let right = cubic(
            from: CGPoint(x: 100, y: 80),
            to: CGPoint(x: 200, y: 80),
            out: CGPoint(x: 0, y: 40),
            inn: CGPoint(x: 0, y: 40)
        )

        #expect(PathJoinEngine.canJoin([outline, left, right], tolerance: joinTolerance))
        let joined = PathJoinEngine.join([outline, left, right], tolerance: joinTolerance)
        #expect(joined?.count == 2)

        let container = joined?.first { $0.isClosed }
        #expect(container?.points.count == outline.points.count)

        let curve = joined?.first { !$0.isClosed }
        #expect(curve?.shapeType == .curve)
        #expect(curve?.curveHandles?.count == curve?.points.count)
        let rendered = ShapeGeometry.renderPoints(for: curve ?? left)
        #expect(rendered.contains { abs($0.y - 110) < 12 && $0.x > 20 && $0.x < 180 })
        let containerRendered = ShapeGeometry.renderPoints(for: container ?? outline)
        #expect(!containerRendered.contains { abs($0.y - 110) < 8 && $0.x > 20 && $0.x < 180 })
    }

    /// A neckline whose ends sit on the outline is a join. The curve replaces
    /// that edge once — walking it back used to draw a flipped second copy.
    @Test func joiningANecklineIntoAnOutlineInsertsTheCurveOnce() {
        let outline = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 200, y: 0),
                CGPoint(x: 200, y: 80),
                CGPoint(x: 200, y: 160),
                CGPoint(x: 0, y: 160),
                CGPoint(x: 0, y: 80)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        let neckline = cubic(
            from: CGPoint(x: 0, y: 80),
            to: CGPoint(x: 200, y: 80),
            out: CGPoint(x: 0, y: 40),
            inn: CGPoint(x: 0, y: 40)
        )

        #expect(PathJoinEngine.canJoin([outline, neckline], tolerance: joinTolerance))
        let joined = PathJoinEngine.join([outline, neckline], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        #expect(stroke.points.count == 4)
        #expect(stroke.points.contains { abs($0.y) < 1 })
        #expect(!stroke.points.contains { abs($0.y - 160) < 1 })
        let rendered = ShapeGeometry.renderPoints(for: stroke)
        #expect(rendered.contains { abs($0.x - 100) < 15 && abs($0.y - 110) < 12 })
        #expect(!rendered.contains { abs($0.x - 100) < 15 && abs($0.y - 50) < 12 })
    }

    /// A closed curve that shares anchors with the outline welds in once.
    /// Each inner anchor is inserted a single time, and its handles stay put.
    @Test func joiningAClosedCurveInsideAShapeWeldsOnce() {
        let outline = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 200, y: 0),
                CGPoint(x: 200, y: 80),
                CGPoint(x: 200, y: 160),
                CGPoint(x: 0, y: 160),
                CGPoint(x: 0, y: 80)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        let lens = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 80),
                CGPoint(x: 100, y: 40),
                CGPoint(x: 200, y: 80),
                CGPoint(x: 100, y: 120)
            ],
            isClosed: true,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: CGPoint(x: 0, y: 20), outOffset: CGPoint(x: 30, y: -10)),
                CurveHandle(inOffset: CGPoint(x: -20, y: 10), outOffset: CGPoint(x: 20, y: 10)),
                CurveHandle(inOffset: CGPoint(x: -30, y: -10), outOffset: CGPoint(x: 0, y: 20)),
                CurveHandle(inOffset: CGPoint(x: 20, y: -10), outOffset: CGPoint(x: -20, y: -10))
            ]
        )

        #expect(PathJoinEngine.canJoin([outline, lens], tolerance: joinTolerance))
        let joined = PathJoinEngine.join([outline, lens], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        #expect(stroke.points.filter { hypot($0.x - 100, $0.y - 40) < 0.01 }.count == 1)
        #expect(stroke.points.filter { hypot($0.x - 100, $0.y - 120) < 0.01 }.count == 1)
        let handles = stroke.curveHandles ?? []
        #expect(handles.count == stroke.points.count)
        #expect(handles.contains {
            hypot($0.outOffset.x, $0.outOffset.y) > 5 || hypot($0.inOffset.x, $0.inOffset.y) > 5
        })
    }

    /// A curve drawn without stored handles renders as a spline. Joining it used
    /// to give it zero handles, so the lens became a straight diamond.
    @Test func joiningAHandlelessCurveKeepsTheSpline() {
        let outline = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 200, y: 0),
                CGPoint(x: 200, y: 80),
                CGPoint(x: 200, y: 160),
                CGPoint(x: 0, y: 160),
                CGPoint(x: 0, y: 80)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        let lens = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 80),
                CGPoint(x: 100, y: 40),
                CGPoint(x: 200, y: 80),
                CGPoint(x: 100, y: 120)
            ],
            isClosed: true,
            shapeType: .curve
        )
        let before = ShapeGeometry.renderPoints(for: lens)

        let joined = PathJoinEngine.join([outline, lens], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let after = ShapeGeometry.renderPoints(for: stroke)
        let lost = stride(from: 0, to: before.count, by: 6).map { before[$0] }.filter { sample in
            !after.contains { hypot($0.x - sample.x, $0.y - sample.y) < 3 }
        }
        #expect(lost.isEmpty, "lens samples missing after join: \(lost.prefix(4))")
    }

    /// A rounded lens stored as smooth midpoints on a polyline, joined to a
    /// Bézier outline. The result is a `.curve`, which used to drop those
    /// midpoints and draw the lens as straight chords.
    @Test func joiningASmoothLensIntoACurvedOutlineKeepsTheBulge() {
        let outline = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 120, y: 0),
                CGPoint(x: 120, y: 80),
                CGPoint(x: 0, y: 80)
            ],
            isClosed: true,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(),
                CurveHandle(),
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: 30)),
                CurveHandle(inOffset: CGPoint(x: 0, y: 30), outOffset: .zero)
            ]
        )
        var lens = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 60, y: -30),
                CGPoint(x: 120, y: 0),
                CGPoint(x: 60, y: 30)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        lens.smoothCornerIndices = [1, 3]
        let before = ShapeGeometry.renderPoints(for: lens)

        let joined = PathJoinEngine.join([outline, lens], tolerance: joinTolerance)
        #expect(joined?.count == 1)
        guard let stroke = joined?.first else { return }
        let after = ShapeGeometry.renderPoints(for: stroke)
        let lost = stride(from: 0, to: before.count, by: 4).map { before[$0] }.filter { sample in
            !after.contains { hypot($0.x - sample.x, $0.y - sample.y) < 3 }
        }
        #expect(lost.isEmpty, "lens samples missing after join: \(lost.prefix(4))")
        #expect(after.contains { $0.y > 95 })
    }

    /// A cubic that meets another curve at a mid-anchor, not an endpoint, keeps
    /// its bulge. Anchor welding must not boolean-union the rendered contour.
    @Test func joiningACubicAtAMiddleAnchorKeepsTheBulge() {
        let host = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: 40)),
                CurveHandle(),
                CurveHandle(inOffset: .zero, outOffset: .zero)
            ]
        )
        let spur = cubic(
            from: CGPoint(x: 50, y: 0),
            to: CGPoint(x: 50, y: 80),
            out: CGPoint(x: 30, y: 0),
            inn: CGPoint(x: 30, y: 0)
        )

        #expect(PathJoinEngine.canJoin([host, spur], tolerance: joinTolerance))
        let joined = PathJoinEngine.join([host, spur], tolerance: joinTolerance)
        let rendered = (joined ?? []).flatMap { ShapeGeometry.renderPoints(for: $0) }
        #expect(rendered.contains { hypot($0.x - 25, $0.y - 20) < 8 })
        #expect(rendered.contains { hypot($0.x - 65, $0.y - 40) < 12 })
    }

    private func distanceFromChord(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return hypot(point.x - a.x, point.y - a.y) }
        let area = abs((point.x - a.x) * dy - (point.y - a.y) * dx)
        return area / length
    }

    private func expectHook(
        _ joined: [VectorStroke],
        named name: String,
        tip: CGPoint,
        bulge: CGPoint
    ) {
        let rendered = joined.flatMap { ShapeGeometry.renderPoints(for: $0) }
        let summary = joined.map { stroke in
            "\(stroke.shapeType) n=\(stroke.points.count) closed=\(stroke.isClosed) handles=\(stroke.curveHandles?.count ?? -1)"
        }.joined(separator: "; ")
        #expect(
            rendered.contains { hypot($0.x - tip.x, $0.y - tip.y) < 8 },
            "\(name) lost notch \(tip); \(summary)"
        )
        #expect(
            rendered.contains { hypot($0.x - bulge.x, $0.y - bulge.y) < 14 },
            "\(name) lost bulge \(bulge); \(summary)"
        )
    }

    private func line(_ start: CGPoint, _ end: CGPoint) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [start, end],
            isClosed: false,
            shapeType: .polyline
        )
    }

    private func cubic(from start: CGPoint, to end: CGPoint, out: CGPoint, inn: CGPoint) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [start, end],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: .zero, outOffset: out),
                CurveHandle(inOffset: inn, outOffset: .zero)
            ]
        )
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
