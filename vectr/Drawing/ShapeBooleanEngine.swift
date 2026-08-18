//
//  ShapeBooleanEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Pure-geometry Boolean helpers for closed polygon contours (document space).
///
/// Used by the Delete tool to punch a hole into a base shape by subtracting an
/// overlapping target shape: the cutout stored on the base is the intersection
/// `(base ∩ target)`, which renders as an even-odd hole via `cutoutPoints`.
///
/// Intersection uses the Sutherland–Hodgman polygon clipper, which is exact when
/// the clip polygon is convex (circles, ellipses, rectangles). When the target is
/// fully contained by the base the target contour is used verbatim so the cutout
/// keeps the target's exact geometry (quad, ellipse, Bézier path, or circle).
enum ShapeBooleanEngine {
    /// A reshaped outer contour plus the vertex indices whose outgoing edge is a cut
    /// edge (bounds the carved notch and should be filled through but not stroked).
    struct CutContour: Equatable {
        var points: [CGPoint]
        var cutEdgeStarts: [Int]
    }

    /// Outcome of subtracting a target shape from a base shape.
    enum Subtraction: Equatable {
        /// Target sits entirely inside the base: punch an even-odd hole by appending
        /// these contours to `base.cutoutPoints`.
        case interiorHole([[CGPoint]])
        /// Target crosses the base boundary: the base's *outer* outline must be
        /// reshaped. These are the resulting `base − target` contours (largest first).
        case boundaryCut([CutContour])
        /// Target fully covers the base: the base is consumed and should be removed.
        case baseRemoved
    }

    /// Classifies how `target` subtracts from `base` and returns the geometry needed
    /// to apply it, or `nil` when the two shapes do not meaningfully overlap.
    ///
    /// Both contours are expected to be fully expanded render geometry (tessellated
    /// circles/ellipses, sampled Béziers, quads), so the result preserves the drawn
    /// shapes rather than re-approximating them.
    static func subtract(baseContour: [CGPoint], targetContour: [CGPoint]) -> Subtraction? {
        let base = normalized(baseContour)
        let target = normalized(targetContour)
        guard base.count >= 3, target.count >= 3 else { return nil }

        let baseArea = abs(signedArea(base))
        let targetArea = abs(signedArea(target))
        guard baseArea > .ulpOfOne, targetArea > .ulpOfOne else { return nil }
        let minArea = max(1e-4, min(baseArea, targetArea) * 0.0005)

        // Target fully contained → interior hole preserving the target's boundary.
        if target.allSatisfy({ polygon(base, contains: $0) }) {
            return .interiorHole([literalPolygonContour(target)])
        }

        // Base fully contained → the cut swallows the whole base.
        if base.allSatisfy({ polygon(target, contains: $0) }) {
            return .baseRemoved
        }

        // Must genuinely overlap (crossing edges or partial containment) to subtract.
        guard PolygonBoolean.polygonsOverlap(base, target) else { return nil }

        let contours = PolygonBoolean.difference(subject: base, clip: target)
            .filter { $0.points.count >= 3 && abs(signedArea($0.points)) > minArea }
            .sorted { abs(signedArea($0.points)) > abs(signedArea($1.points)) }
            .map { CutContour(points: $0.points, cutEdgeStarts: $0.cutEdgeStarts) }

        guard !contours.isEmpty else { return .baseRemoved }
        return .boundaryCut(contours)
    }

    /// Contours of `(base ∩ target)` to append to `base.cutoutPoints`, or `nil`
    /// when the two shapes do not meaningfully overlap.
    ///
    /// `targetContour` is expected to already be the target's fully expanded render
    /// geometry (e.g. a tessellated circle/ellipse or sampled Bézier path), so the
    /// hole preserves the drawn shape rather than being re-approximated.
    static func subtractionCutouts(baseContour: [CGPoint], targetContour: [CGPoint]) -> [[CGPoint]]? {
        let base = normalized(baseContour)
        let target = normalized(targetContour)
        guard base.count >= 3, target.count >= 3 else { return nil }

        let baseArea = abs(signedArea(base))
        let targetArea = abs(signedArea(target))
        guard baseArea > .ulpOfOne, targetArea > .ulpOfOne else { return nil }
        // Reject mere edge-touching / numeric slivers relative to the smaller shape.
        let minArea = max(1e-4, min(baseArea, targetArea) * 0.0005)

        // Fast, exact path: target fully inside base → the hole is the target itself,
        // preserving its precise vector boundary.
        if target.allSatisfy({ polygon(base, contains: $0) }) {
            return [literalPolygonContour(target)]
        }

        // General case: clip against whichever contour is convex for an exact result.
        let subject: [CGPoint]
        let clip: [CGPoint]
        if isConvex(target) {
            subject = base
            clip = target
        } else if isConvex(base) {
            subject = target
            clip = base
        } else {
            // Neither is convex: best-effort clip against the target.
            subject = base
            clip = target
        }

        let intersection = normalized(convexClip(subject: subject, clip: clip))
        guard intersection.count >= 3, abs(signedArea(intersection)) > minArea else { return nil }
        return [literalPolygonContour(intersection)]
    }

    /// Guarantees a cutout contour is rendered literally as a polygon.
    ///
    /// `cutoutPoints` are ambiguous in the model: consumers (`StrokeRenderer`,
    /// `VectorStroke.contains`) treat an *exactly* 4-point contour as a circle's
    /// cardinal points (the legacy donut-hole convention) and re-expand it into a
    /// circle. A quadrilateral/clipped-rectangle cutout also has 4 points and would
    /// wrongly become a circle. Subdividing each edge with its midpoint keeps the
    /// identical straight-edged outline while making the vertex count != 4, so the
    /// contour is drawn verbatim.
    private static func literalPolygonContour(_ contour: [CGPoint]) -> [CGPoint] {
        guard contour.count == 4 else { return contour }
        var result: [CGPoint] = []
        result.reserveCapacity(contour.count * 2)
        let count = contour.count
        for index in 0..<count {
            let current = contour[index]
            let next = contour[(index + 1) % count]
            result.append(current)
            result.append(CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2))
        }
        return result
    }

    // MARK: - Sutherland–Hodgman

    /// Clips `subject` against the convex `clip` polygon, returning the intersection.
    /// Exact only when `clip` is convex.
    static func convexClip(subject: [CGPoint], clip: [CGPoint]) -> [CGPoint] {
        guard subject.count >= 3, clip.count >= 3 else { return [] }
        let clipCCW = signedArea(clip) < 0 ? Array(clip.reversed()) : clip
        var output = subject
        let clipCount = clipCCW.count

        for i in 0..<clipCount {
            guard !output.isEmpty else { break }
            let edgeStart = clipCCW[i]
            let edgeEnd = clipCCW[(i + 1) % clipCount]
            let input = output
            output = []
            let inputCount = input.count
            for j in 0..<inputCount {
                let current = input[j]
                let previous = input[(j + inputCount - 1) % inputCount]
                let currentInside = isLeft(edgeStart, edgeEnd, current) >= 0
                let previousInside = isLeft(edgeStart, edgeEnd, previous) >= 0
                if currentInside {
                    if !previousInside {
                        output.append(lineIntersection(previous, current, edgeStart, edgeEnd))
                    }
                    output.append(current)
                } else if previousInside {
                    output.append(lineIntersection(previous, current, edgeStart, edgeEnd))
                }
            }
        }
        return output
    }

    // MARK: - Geometry primitives

    /// Signed area (positive/negative depending on winding under this convention).
    static func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        let count = polygon.count
        for i in 0..<count {
            let a = polygon[i]
            let b = polygon[(i + 1) % count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// True when the polygon turns in a single direction at every vertex.
    static func isConvex(_ polygon: [CGPoint]) -> Bool {
        let pts = normalized(polygon)
        let count = pts.count
        guard count >= 3 else { return false }
        var sign = 0
        for i in 0..<count {
            let a = pts[i]
            let b = pts[(i + 1) % count]
            let c = pts[(i + 2) % count]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-9 { continue }
            let current = cross > 0 ? 1 : -1
            if sign == 0 {
                sign = current
            } else if current != sign {
                return false
            }
        }
        return true
    }

    /// Even-odd ray-cast point containment for a polygon contour.
    static func polygon(_ polygon: [CGPoint], contains point: CGPoint) -> Bool {
        let count = polygon.count
        guard count >= 3 else { return false }
        var inside = false
        var j = count - 1
        for i in 0..<count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y) {
                let denominator = pj.y - pi.y
                if abs(denominator) > .ulpOfOne {
                    let xCross = pi.x + (point.y - pi.y) / denominator * (pj.x - pi.x)
                    if point.x < xCross { inside.toggle() }
                }
            }
            j = i
        }
        return inside
    }

    // MARK: - Private helpers

    /// Cross product of `(b - a)` and `(p - a)`; > 0 when `p` is left of a→b.
    private static func isLeft(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> CGFloat {
        (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    }

    /// Intersection of segment `p1→p2` with the infinite line through `a` and `b`.
    private static func lineIntersection(_ p1: CGPoint, _ p2: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let normalX = b.y - a.y
        let normalY = a.x - b.x
        let lineConstant = normalX * a.x + normalY * a.y
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let denominator = normalX * dx + normalY * dy
        guard abs(denominator) > 1e-12 else { return p1 }
        let t = (lineConstant - (normalX * p1.x + normalY * p1.y)) / denominator
        return CGPoint(x: p1.x + t * dx, y: p1.y + t * dy)
    }

    /// Drops repeated consecutive points and a duplicate closing point.
    private static func normalized(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            if let last = result.last, hypot(last.x - point.x, last.y - point.y) <= 1e-6 { continue }
            result.append(point)
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           hypot(first.x - last.x, first.y - last.y) <= 1e-6 {
            result.removeLast()
        }
        return result
    }
}
