import CoreGraphics
import Foundation
import Testing
@testable import Koala

/// Translating a shape must move it and change nothing else.
///
/// Curvature can live in three different places depending on how a shape was produced —
/// `curveHandles` on a `.curve`, `smoothCornerIndices` on a `.polyline`, or the anchor
/// positions of an `.arc` — so each is covered separately. Measurements are taken from
/// `renderPoints`, not from a stored sweep, because only `.arc` has one to read.
@MainActor
struct TrimmedGeometrySurvivesMoveTests {
    private static let delta = CGPoint(x: 250, y: -150)

    private static func renderedLength(_ stroke: VectorStroke) -> CGFloat {
        let points = ShapeGeometry.renderPoints(for: stroke)
        guard points.count >= 2 else { return 0 }
        let segments = stroke.isClosed ? points.count : points.count - 1
        var total: CGFloat = 0
        for index in 0..<segments {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            total += hypot(b.x - a.x, b.y - a.y)
        }
        return total
    }

    private static func renderedBox(_ stroke: VectorStroke) -> CGRect {
        ShapeGeometry.renderPoints(for: stroke)
            .reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// Translating a stroke by moving every one of its anchors, the way a body drag does
    /// when anchors happen to be selected.
    private static func movesTranslatingEveryAnchor(_ stroke: VectorStroke) -> [Int: CGPoint] {
        Dictionary(uniqueKeysWithValues: stroke.points.enumerated().map { index, point in
            (index, CGPoint(x: point.x + delta.x, y: point.y + delta.y))
        })
    }

    // MARK: - Curvature stored as Bézier handles

    /// Cubic control offsets reproducing the clockwise circular arc `from`→`to` about
    /// `center`, via the standard k = 4/3·tan(sweep/4)·r approximation.
    private static func arcHandles(
        from: CGPoint,
        to: CGPoint,
        center: CGPoint
    ) -> (out: CGPoint, into: CGPoint) {
        let radius = hypot(from.x - center.x, from.y - center.y)
        let startAngle = atan2(from.y - center.y, from.x - center.x)
        let endAngle = atan2(to.y - center.y, to.x - center.x)
        var sweep = endAngle - startAngle
        while sweep > 0 { sweep -= 2 * .pi }
        while sweep <= -2 * .pi { sweep += 2 * .pi }
        let k = 4.0 / 3.0 * tan(sweep / 4) * radius
        let tangentStart = CGPoint(x: -sin(startAngle), y: cos(startAngle))
        let tangentEnd = CGPoint(x: -sin(endAngle), y: cos(endAngle))
        return (
            out: CGPoint(x: tangentStart.x * k, y: tangentStart.y * k),
            into: CGPoint(x: -tangentEnd.x * k, y: -tangentEnd.y * k)
        )
    }

    /// A lens as a Bézier: two tips joined by arcs of radius 100 on different circles.
    private static func bezierPetal() -> VectorStroke {
        let top = CGPoint(x: 0, y: 80)
        let bottom = CGPoint(x: 0, y: -80)
        var stroke = VectorStroke(
            layerID: UUID(),
            points: [top, bottom],
            isClosed: true,
            shapeType: .curve
        )
        let rightEdge = arcHandles(from: top, to: bottom, center: CGPoint(x: -60, y: 0))
        let leftEdge = arcHandles(from: bottom, to: top, center: CGPoint(x: 60, y: 0))
        var topHandle = CurveHandle()
        var bottomHandle = CurveHandle()
        topHandle.outOffset = rightEdge.out
        bottomHandle.inOffset = rightEdge.into
        bottomHandle.outOffset = leftEdge.out
        topHandle.inOffset = leftEdge.into
        stroke.curveHandles = [topHandle, bottomHandle]
        return stroke
    }

    /// The same lens as a polyline whose curvature lives in `smoothCornerIndices`, which
    /// is what `CircularAnchorCompactor.rebuildStroke` emits.
    private static func smoothCornerPetal() -> VectorStroke {
        var stroke = VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: 0, y: 60),
                CGPoint(x: 35, y: 0),
                CGPoint(x: 0, y: -60),
                CGPoint(x: -35, y: 0)
            ],
            isClosed: true,
            shapeType: .polyline
        )
        stroke.smoothCornerIndices = [1, 3]
        return stroke
    }

    @Test func translatingEveryAnchorKeepsBezierCurvature() {
        let petal = Self.bezierPetal()
        let curvedLength = Self.renderedLength(petal)
        // Guard the fixture: writing anchors point-by-point zeroed the handles, so the
        // curved lens must measurably outrun the same lens with its handles cleared.
        var flattened = petal
        flattened.curveHandles = [CurveHandle(), CurveHandle()]
        #expect(curvedLength > Self.renderedLength(flattened) + 5)

        let moved = ShapeGeometry.applyingMovedAnchors(
            petal,
            moves: Self.movesTranslatingEveryAnchor(petal)
        )

        #expect(abs(Self.renderedLength(moved) - curvedLength) < 1)
        #expect(moved.curveHandles?.count == 2)
        for handle in moved.curveHandles ?? [] {
            #expect(hypot(handle.inOffset.x, handle.inOffset.y) > 1)
            #expect(hypot(handle.outOffset.x, handle.outOffset.y) > 1)
        }
        for (before, after) in zip(petal.points, moved.points) {
            #expect(abs(after.x - (before.x + Self.delta.x)) < 0.001)
            #expect(abs(after.y - (before.y + Self.delta.y)) < 0.001)
        }
    }

    @Test func translatingEveryAnchorKeepsBakedSmoothCorners() {
        let petal = Self.smoothCornerPetal()
        let curvedLength = Self.renderedLength(petal)
        var flattened = petal
        flattened.smoothCornerIndices = nil
        #expect(curvedLength > Self.renderedLength(flattened) + 5)

        let moved = ShapeGeometry.applyingMovedAnchors(
            petal,
            moves: Self.movesTranslatingEveryAnchor(petal)
        )

        #expect(moved.smoothCornerIndices == [1, 3])
        #expect(abs(Self.renderedLength(moved) - curvedLength) < 1)
        let box = Self.renderedBox(moved)
        let original = Self.renderedBox(petal)
        #expect(abs(box.minX - (original.minX + Self.delta.x)) < 0.001)
        #expect(abs(box.minY - (original.minY + Self.delta.y)) < 0.001)
    }

    /// Edge case: moving only *some* anchors is a genuine reshape, so it must keep taking
    /// the anchor-rewrite path rather than being mistaken for a translation.
    @Test func movingASubsetOfAnchorsStillReshapes() {
        let petal = Self.smoothCornerPetal()
        let moved = ShapeGeometry.applyingMovedAnchors(
            petal,
            moves: [0: CGPoint(x: 0, y: 200)]
        )
        #expect(moved.points[0] == CGPoint(x: 0, y: 200))
        #expect(moved.points[2] == petal.points[2])
    }

    // MARK: - Parametric invariant for a multi-selection of unjoined arcs

    /// An arc has no stored `(cx, cy, r, θ1, θ2)` — it is 3–6 anchors on the rim, and those
    /// values are re-derived per render. So the translation contract is stated in derived
    /// terms: the centre shifts by exactly the drag delta while radius, start angle and end
    /// angle stay untouched.
    private struct ArcParameters {
        var center: CGPoint
        var radius: CGFloat
        var startAngle: CGFloat
        var endAngle: CGFloat
        var sweep: CGFloat
    }

    private static func parameters(of stroke: VectorStroke) -> ArcParameters? {
        guard let circle = ShapeGeometry.arcCircle(for: stroke),
              let first = stroke.points.first,
              let last = stroke.points.last,
              let sweep = ShapeGeometry.signedCircularSweep(
                  of: stroke.points, around: circle.center
              ) else { return nil }
        return ArcParameters(
            center: circle.center,
            radius: circle.radius,
            startAngle: atan2(first.y - circle.center.y, first.x - circle.center.x),
            endAngle: atan2(last.y - circle.center.y, last.x - circle.center.x),
            sweep: sweep
        )
    }

    private static func angularGap(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        abs(atan2(sin(a - b), cos(a - b)))
    }

    private static func arc(
        center: CGPoint, radius: CGFloat, startDeg: CGFloat, sweepDeg: CGFloat, layerID: UUID
    ) -> VectorStroke {
        let start = startDeg * .pi / 180
        let sweep = sweepDeg * .pi / 180
        func point(_ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        return VectorStroke(
            layerID: layerID,
            points: ShapeGeometry.defaultCircularAnchors(
                center: center,
                radius: radius,
                start: point(start),
                end: point(start + sweep),
                sweep: sweep,
                closed: false
            ),
            isClosed: false,
            shapeType: .arc
        )
    }

    @Test func groupMovingUnjoinedArcsTranslatesCentresAndLeavesRadiiAndAnglesAlone() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        document.strokes = [
            Self.arc(center: .zero, radius: 100, startDeg: 20, sweepDeg: 95, layerID: layerID),
            Self.arc(center: CGPoint(x: 180, y: 40), radius: 70,
                     startDeg: -140, sweepDeg: 260, layerID: layerID),
            Self.arc(center: CGPoint(x: -120, y: -90), radius: 45,
                     startDeg: 200, sweepDeg: -70, layerID: layerID)
        ]
        let before = document.strokes.map { (id: $0.id, params: Self.parameters(of: $0)) }
        #expect(before.allSatisfy { $0.params != nil })

        // What `beginGroupMove()` + `applyGroupMove(delta:)` do: compact anchors on the
        // first frame, then offset every member from its captured origin by one delta.
        document.selectedStrokeIDs = Set(document.strokes.map(\.id))
        document.beginInteractiveEdit()
        for stroke in document.strokes {
            document.updateStroke(stroke.offsettingGeometry(by: Self.delta), recordUndo: false)
        }

        for entry in before {
            guard let original = entry.params,
                  let moved = document.stroke(with: entry.id).flatMap(Self.parameters(of:)) else {
                Issue.record("arc \(entry.id) lost its circular parameters")
                continue
            }
            #expect(abs(moved.center.x - (original.center.x + Self.delta.x)) < 0.001)
            #expect(abs(moved.center.y - (original.center.y + Self.delta.y)) < 0.001)
            #expect(abs(moved.radius - original.radius) < 0.001)
            #expect(Self.angularGap(moved.startAngle, original.startAngle) < 0.0001)
            #expect(Self.angularGap(moved.endAngle, original.endAngle) < 0.0001)
            #expect(abs(moved.sweep - original.sweep) < 0.0001)
        }
    }
}
