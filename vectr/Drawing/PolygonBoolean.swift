//
//  PolygonBoolean.swift
//  vectr
//

import CoreGraphics
import Foundation

/// General polygon Boolean difference for arbitrary (convex or concave) simple
/// polygons, implemented with the Greiner–Hormann clipping algorithm.
///
/// `ShapeBooleanEngine` only computes intersections against a convex clip; that is
/// enough to punch an interior hole, but it cannot carve a notch out of an edge
/// (where the cut shape crosses the base boundary). This engine returns the true
/// `subject − clip` contours so the base's *outer* outline is reshaped rather than
/// leaving an even-odd hole with a seam across its mouth.
enum PolygonBoolean {
    /// A result contour of a Boolean operation, tagged per edge with whether that edge
    /// originated from the clip polygon (a "cut" edge along the carved notch).
    struct Contour {
        var points: [CGPoint]
        /// `cutEdges[i]` marks the edge `points[i] → points[(i + 1) % count]` as a clip
        /// (cut) edge. Aligned 1:1 with `points`.
        var cutEdges: [Bool]

        /// Indices `i` whose edge `points[i] → points[i+1]` is a cut edge.
        var cutEdgeStarts: [Int] {
            cutEdges.enumerated().compactMap { $0.element ? $0.offset : nil }
        }
    }

    /// Result contours of `subject − clip`. Empty when the subject is fully removed;
    /// returns the subject unchanged when the two polygons do not overlap.
    static func difference(subject: [CGPoint], clip: [CGPoint]) -> [Contour] {
        let subj = normalized(subject)
        let clp = normalized(clip)
        guard subj.count >= 3, clp.count >= 3 else {
            return [Contour(points: subject, cutEdges: Array(repeating: false, count: subject.count))]
        }

        // Retry with a tiny per-vertex jitter of the clip polygon when a degenerate
        // configuration (a clip vertex/edge lying exactly on a subject edge, or
        // collinear overlap) makes a pass find no clean crossing set. The jitter is
        // scaled to the geometry so it reliably nudges points off an edge while staying
        // far below anything visible.
        let diagonal = boundingDiagonal(subj + clp)
        let base = max(diagonal, 1) * 1e-5
        let magnitudes: [CGFloat] = [0, base, 3 * base, 10 * base, 30 * base]
        for magnitude in magnitudes {
            let clipTry = magnitude == 0 ? clp : jittered(clp, by: magnitude)
            if let result = differenceOnce(subject: subj, clip: clipTry) {
                return result
            }
        }
        // All attempts failed: leave the base untouched rather than corrupt it.
        return [Contour(points: subj, cutEdges: Array(repeating: false, count: subj.count))]
    }

    /// Where the cut curve attaches to the polygon boundary.
    private struct BoundaryAttach {
        var point: CGPoint
        var edge: Int      // polygon edge index it lands on
        var u: CGFloat     // parameter along that edge
    }

    /// Splits a closed `polygon` into two pieces along an open `path` (an arc/knife).
    ///
    /// Two configurations are supported, both meaning "on the edge":
    /// - The path pokes through the boundary (its ends lie outside): the first and last
    ///   boundary crossings become the attach points.
    /// - The path lies inside with its endpoints on/near the boundary: the endpoints are
    ///   snapped to the nearest edge, provided they are within `maxEndpointAttach`.
    ///
    /// Returns the two closed contours, or `nil` when the path does not divide the shape.
    static func split(
        polygon: [CGPoint],
        byOpenPath rawPath: [CGPoint],
        maxEndpointAttach: CGFloat = .greatestFiniteMagnitude
    ) -> [[CGPoint]]? {
        let poly = normalized(polygon)
        let path = normalizedOpen(rawPath)
        guard poly.count >= 3, path.count >= 2 else { return nil }
        let n = poly.count

        struct Crossing { var point: CGPoint; var tPath: CGFloat; var edge: Int; var u: CGFloat }
        var crossings: [Crossing] = []
        for i in 0..<(path.count - 1) {
            let a1 = path[i], a2 = path[i + 1]
            for j in 0..<n {
                let b1 = poly[j], b2 = poly[(j + 1) % n]
                guard let hit = segmentIntersection(a1, a2, b1, b2) else { continue }
                crossings.append(Crossing(
                    point: hit.point,
                    tPath: CGFloat(i) + hit.alphaA,
                    edge: j,
                    u: hit.alphaB
                ))
            }
        }

        let entry: BoundaryAttach
        let exit: BoundaryAttach
        var cutInterior: [CGPoint] = []

        if crossings.count >= 2 {
            // Poke-through: use the outermost crossings and the path between them.
            crossings.sort { $0.tPath < $1.tPath }
            let first = crossings.first!
            let last = crossings.last!
            guard first.tPath + 1e-9 < last.tPath else { return nil }
            entry = BoundaryAttach(point: first.point, edge: first.edge, u: first.u)
            exit = BoundaryAttach(point: last.point, edge: last.edge, u: last.u)
            for k in 0..<path.count {
                let t = CGFloat(k)
                if t > first.tPath + 1e-9, t < last.tPath - 1e-9 { cutInterior.append(path[k]) }
            }
        } else {
            // Endpoints-on-edge: snap the open path's ends to the nearest boundary edge.
            guard let a = nearestBoundary(path.first!, poly),
                  let b = nearestBoundary(path.last!, poly),
                  hypot(path.first!.x - a.point.x, path.first!.y - a.point.y) <= maxEndpointAttach,
                  hypot(path.last!.x - b.point.x, path.last!.y - b.point.y) <= maxEndpointAttach,
                  hypot(a.point.x - b.point.x, a.point.y - b.point.y) > 1e-6 else { return nil }
            entry = a
            exit = b
            if path.count > 2 { cutInterior = Array(path[1..<(path.count - 1)]) }
        }

        // Cut curve A → interior → B.
        var cut: [CGPoint] = [entry.point]
        cut.append(contentsOf: cutInterior)
        cut.append(exit.point)

        // Ordered boundary nodes: polygon vertices at integer positions plus the two
        // attach points at their fractional positions, sorted around the ring.
        struct BNode { var pos: CGFloat; var pt: CGPoint; var isA: Bool; var isB: Bool }
        var nodes: [BNode] = (0..<n).map { BNode(pos: CGFloat($0), pt: poly[$0], isA: false, isB: false) }
        nodes.append(BNode(pos: CGFloat(entry.edge) + entry.u, pt: entry.point, isA: true, isB: false))
        nodes.append(BNode(pos: CGFloat(exit.edge) + exit.u, pt: exit.point, isA: false, isB: true))
        nodes.sort { $0.pos < $1.pos }
        guard let ia = nodes.firstIndex(where: { $0.isA }),
              let ib = nodes.firstIndex(where: { $0.isB }) else { return nil }

        let m = nodes.count
        func vertsBetween(_ from: Int, _ to: Int) -> [CGPoint] {
            var result: [CGPoint] = []
            var k = (from + 1) % m
            while k != to {
                if !nodes[k].isA, !nodes[k].isB { result.append(nodes[k].pt) }
                k = (k + 1) % m
            }
            return result
        }
        // Piece 1: knife A→B, then the boundary walked forward from B back to A.
        var piece1 = cut
        piece1.append(contentsOf: vertsBetween(ib, ia))
        // Piece 2: knife A→B, then the other boundary arc traversed B→A (reversed).
        var piece2 = cut
        piece2.append(contentsOf: vertsBetween(ia, ib).reversed())

        let p1 = normalized(piece1)
        let p2 = normalized(piece2)
        guard p1.count >= 3, p2.count >= 3 else { return nil }
        return [p1, p2]
    }

    /// Nearest point on the polygon boundary to `point`, with its edge index and param.
    private static func nearestBoundary(_ point: CGPoint, _ poly: [CGPoint]) -> BoundaryAttach? {
        let n = poly.count
        guard n >= 2 else { return nil }
        var best: BoundaryAttach?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for j in 0..<n {
            let a = poly[j], b = poly[(j + 1) % n]
            let dx = b.x - a.x, dy = b.y - a.y
            let lenSq = dx * dx + dy * dy
            var u: CGFloat = 0
            if lenSq > .ulpOfOne {
                u = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq
                u = max(0, min(1, u))
            }
            let proj = CGPoint(x: a.x + u * dx, y: a.y + u * dy)
            let d = hypot(point.x - proj.x, point.y - proj.y)
            if d < bestDist {
                bestDist = d
                best = BoundaryAttach(point: proj, edge: j, u: u)
            }
        }
        return best
    }

    /// Like `normalized` but preserves the open path (does not drop the closing point).
    private static func normalizedOpen(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 1 else { return points }
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            if let last = result.last, hypot(last.x - point.x, last.y - point.y) <= 1e-6 { continue }
            result.append(point)
        }
        return result
    }

    private static func boundingDiagonal(_ points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return 0 }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return hypot(maxX - minX, maxY - minY)
    }

    /// True when the two closed polygons share any interior area, either by edge
    /// crossings or by one polygon containing a vertex of the other.
    static func polygonsOverlap(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        let pa = normalized(a)
        let pb = normalized(b)
        guard pa.count >= 3, pb.count >= 3 else { return false }
        if edgesCross(pa, pb) { return true }
        if pa.contains(where: { pointInPolygon($0, pb) }) { return true }
        if pb.contains(where: { pointInPolygon($0, pa) }) { return true }
        return false
    }

    /// True when any edge of `a` properly crosses any edge of `b`.
    static func edgesCross(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        let pa = normalized(a)
        let pb = normalized(b)
        guard pa.count >= 3, pb.count >= 3 else { return false }
        let na = pa.count
        let nb = pb.count
        for i in 0..<na {
            let a1 = pa[i]
            let a2 = pa[(i + 1) % na]
            for j in 0..<nb {
                let b1 = pb[j]
                let b2 = pb[(j + 1) % nb]
                if segmentIntersection(a1, a2, b1, b2) != nil { return true }
            }
        }
        return false
    }

    /// Even-odd ray-cast point containment.
    static func pointInPolygon(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
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

    // MARK: - Greiner–Hormann

    private final class Node {
        var point: CGPoint
        var next: Node!
        var prev: Node!
        var isIntersection = false
        var isClip = false
        var neighbour: Node?
        var alpha: CGFloat = 0
        var isEntry = false
        var visited = false

        init(_ point: CGPoint, isClip: Bool = false) {
            self.point = point
            self.isClip = isClip
        }
    }

    /// One Greiner–Hormann pass. Returns `nil` when the crossing set is degenerate
    /// (odd count on either polygon), signalling the caller to retry with a nudge.
    private static func differenceOnce(subject: [CGPoint], clip: [CGPoint]) -> [Contour]? {
        let subjectNodes = makeRing(subject, isClip: false)
        let clipNodes = makeRing(clip, isClip: true)

        var crossingCount = 0
        let subjCount = subjectNodes.count
        let clipCount = clipNodes.count

        for i in 0..<subjCount {
            let s1 = subjectNodes[i]
            let s2 = subjectNodes[(i + 1) % subjCount]
            for j in 0..<clipCount {
                let c1 = clipNodes[j]
                let c2 = clipNodes[(j + 1) % clipCount]
                guard let hit = segmentIntersection(s1.point, s2.point, c1.point, c2.point) else {
                    continue
                }
                let onSubject = Node(hit.point, isClip: false)
                onSubject.isIntersection = true
                onSubject.alpha = hit.alphaA
                let onClip = Node(hit.point, isClip: true)
                onClip.isIntersection = true
                onClip.alpha = hit.alphaB
                onSubject.neighbour = onClip
                onClip.neighbour = onSubject
                insert(onSubject, between: s1, and: s2)
                insert(onClip, between: c1, and: c2)
                crossingCount += 1
            }
        }

        // No proper crossings found. Because callers only invoke `difference` once the
        // shapes are known to overlap (and non-containment is handled separately), zero
        // crossings means a degenerate configuration (a clip vertex sits exactly on a
        // subject edge, so the crossing collapsed onto an endpoint). Signal a retry so
        // the caller re-runs with a jittered clip that produces clean crossings.
        guard crossingCount > 0 else { return nil }

        // A clean crossing set enters and exits an even number of times.
        guard countIntersections(subjectNodes[0]).isMultiple(of: 2),
              countIntersections(clipNodes[0]).isMultiple(of: 2) else { return nil }

        markEntryExit(
            ring: subjectNodes[0],
            other: clip,
            initialForward: false
        )
        markEntryExit(
            ring: clipNodes[0],
            other: subject,
            initialForward: true
        )

        return trace(subjectRingHead: subjectNodes[0])
    }

    /// Builds a circular doubly linked list and returns the original vertices in order.
    private static func makeRing(_ points: [CGPoint], isClip: Bool) -> [Node] {
        let nodes = points.map { Node($0, isClip: isClip) }
        let count = nodes.count
        for i in 0..<count {
            nodes[i].next = nodes[(i + 1) % count]
            nodes[i].prev = nodes[(i + count - 1) % count]
        }
        return nodes
    }

    /// Inserts an intersection node into the segment `start → end`, keeping nodes on
    /// that edge sorted by their `alpha` parameter.
    private static func insert(_ node: Node, between start: Node, and end: Node) {
        var current = start.next!
        while current !== end, current.isIntersection, current.alpha < node.alpha {
            current = current.next!
        }
        node.prev = current.prev
        node.next = current
        current.prev.next = node
        current.prev = node
    }

    private static func countIntersections(_ head: Node) -> Int {
        var count = 0
        var current: Node = head
        repeat {
            if current.isIntersection { count += 1 }
            current = current.next
        } while current !== head
        return count
    }

    /// Labels each intersection on `ring` as an entry or exit relative to `other`.
    /// `initialForward` encodes the Boolean operation (difference uses `false` for the
    /// subject ring and `true` for the clip ring, matching `clip(A, B, false, true)`).
    private static func markEntryExit(ring head: Node, other: [CGPoint], initialForward: Bool) {
        var status = initialForward
        if pointInPolygon(head.point, other) {
            status.toggle()
        }
        var current: Node = head
        repeat {
            if current.isIntersection {
                current.isEntry = status
                status.toggle()
            }
            current = current.next
        } while current !== head
    }

    private static func trace(subjectRingHead head: Node) -> [Contour] {
        var results: [Contour] = []
        let safetyLimit = 100_000
        while let start = firstUnvisited(head) {
            var points: [CGPoint] = [start.point]
            // `edgeIsCut[k]` describes the edge points[k] → points[k+1].
            var edgeIsCut: [Bool] = []
            var current = start
            var steps = 0
            repeat {
                visit(current)
                // Every vertex reached during this run lies on `current`'s ring, so
                // the edges into them are clip edges exactly when that ring is the clip.
                let runIsCut = current.isClip
                if current.isEntry {
                    repeat {
                        current = current.next
                        points.append(current.point)
                        edgeIsCut.append(runIsCut)
                        steps += 1
                    } while !current.isIntersection && steps < safetyLimit
                } else {
                    repeat {
                        current = current.prev
                        points.append(current.point)
                        edgeIsCut.append(runIsCut)
                        steps += 1
                    } while !current.isIntersection && steps < safetyLimit
                }
                guard let neighbour = current.neighbour else { break }
                current = neighbour
            } while !current.visited && steps < safetyLimit

            // The trace closes back onto the start point; drop the duplicate vertex but
            // keep its edge flag, which becomes the wrap-around edge (last → first).
            if points.count >= 2,
               let first = points.first,
               let last = points.last,
               hypot(first.x - last.x, first.y - last.y) <= 1e-6 {
                points.removeLast()
            }
            // Align edge flags to the point count (one edge per vertex on a closed ring).
            if edgeIsCut.count > points.count {
                edgeIsCut.removeLast(edgeIsCut.count - points.count)
            } else if edgeIsCut.count < points.count {
                edgeIsCut.append(contentsOf: Array(repeating: false, count: points.count - edgeIsCut.count))
            }
            // Collinear overlaps between the polygons (common for axis-aligned
            // rectangles) can make the trace walk out and back along the same line,
            // leaving a zero-width spur that renders as a dangling edge. Collapse those
            // spikes and any duplicate vertices before emitting the contour.
            let cleaned = collapseSpikes(points: points, cutEdges: edgeIsCut)
            if cleaned.points.count >= 3 {
                results.append(Contour(points: cleaned.points, cutEdges: cleaned.cutEdges))
            }
        }
        return results
    }

    /// Removes zero-width spurs and duplicate vertices from a traced closed contour.
    /// A spur is a vertex whose incoming and outgoing edges are (near) antiparallel —
    /// the path goes out to a tip and immediately doubles back, which draws as a line
    /// with a dangling free end. `cutEdges` is kept aligned 1:1 with `points`; removing
    /// vertex `i` drops its outgoing edge flag and merges into the previous edge.
    private static func collapseSpikes(points: [CGPoint], cutEdges: [Bool]) -> (points: [CGPoint], cutEdges: [Bool]) {
        var pts = points
        var cuts = cutEdges
        var didChange = true
        while didChange && pts.count > 3 {
            didChange = false
            let n = pts.count
            for i in 0..<n {
                let prev = pts[(i + n - 1) % n]
                let cur = pts[i]
                let next = pts[(i + 1) % n]
                let v1x = cur.x - prev.x, v1y = cur.y - prev.y
                let v2x = next.x - cur.x, v2y = next.y - cur.y
                let len1 = hypot(v1x, v1y)
                let len2 = hypot(v2x, v2y)
                // Drop degenerate (zero-length) edges outright.
                if len2 <= 1e-9 || len1 <= 1e-9 {
                    pts.remove(at: i)
                    if i < cuts.count { cuts.remove(at: i) }
                    didChange = true
                    break
                }
                // Antiparallel incoming/outgoing edges ⇒ `cur` is a spur tip.
                let cosTheta = (v1x * v2x + v1y * v2y) / (len1 * len2)
                if cosTheta < -0.9999 {
                    pts.remove(at: i)
                    if i < cuts.count { cuts.remove(at: i) }
                    didChange = true
                    break
                }
            }
        }
        return (pts, cuts)
    }

    private static func firstUnvisited(_ head: Node) -> Node? {
        var current: Node = head
        repeat {
            if current.isIntersection && !current.visited { return current }
            current = current.next
        } while current !== head
        return nil
    }

    private static func visit(_ node: Node) {
        node.visited = true
        node.neighbour?.visited = true
    }

    // MARK: - Geometry primitives

    /// Proper segment intersection returning the crossing point and both edge
    /// parameters. Returns `nil` for parallel segments or intersections at an
    /// endpoint (parameters must fall strictly inside both segments).
    private static func segmentIntersection(
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ q1: CGPoint,
        _ q2: CGPoint
    ) -> (point: CGPoint, alphaA: CGFloat, alphaB: CGFloat)? {
        let dPx = p2.x - p1.x
        let dPy = p2.y - p1.y
        let dQx = q2.x - q1.x
        let dQy = q2.y - q1.y
        let determinant = dPx * (-dQy) - (-dQx) * dPy
        guard abs(determinant) > 1e-12 else { return nil }
        let tx = q1.x - p1.x
        let ty = q1.y - p1.y
        let s = (tx * (-dQy) - (-dQx) * ty) / determinant
        let t = (dPx * ty - tx * dPy) / determinant
        let lower: CGFloat = 1e-9
        let upper: CGFloat = 1 - 1e-9
        guard s > lower, s < upper, t > lower, t < upper else { return nil }
        return (CGPoint(x: p1.x + s * dPx, y: p1.y + s * dPy), s, t)
    }

    /// Nudges each vertex by `magnitude` in a per-vertex-varying direction, breaking
    /// degeneracies where a vertex or edge lies exactly on the other polygon's edge.
    private static func jittered(_ polygon: [CGPoint], by magnitude: CGFloat) -> [CGPoint] {
        polygon.enumerated().map { index, point in
            // Golden-angle stepping spreads directions so no two nearby vertices move
            // the same way (which would preserve a collinear overlap).
            let angle = CGFloat(index) * 2.399963229728653
            return CGPoint(x: point.x + magnitude * cos(angle), y: point.y + magnitude * sin(angle))
        }
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
