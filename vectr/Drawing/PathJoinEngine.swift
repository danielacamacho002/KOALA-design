//
//  PathJoinEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Permanently welds several strokes together at their coincident anchors.
///
/// Unlike grouping (which keeps every shape independent and only moves them as a
/// unit), joining is destructive: any anchors that sit within `tolerance` of each
/// other are collapsed onto a single shared coordinate, and open paths that now
/// meet at a shared endpoint are chained into one continuous path. Closed shapes
/// keep their own contour but adopt the welded coordinate wherever an anchor
/// touched a neighbour, so seams line up exactly.
///
/// Curve tangent handles are preserved: if any welded input is a curve the
/// resulting path stays a curve (straight segments get zero-offset handles),
/// otherwise the result is a plain polyline.
enum PathJoinEngine {
    private struct Path {
        var points: [CGPoint]
        var handles: [CurveHandle]
        var isClosed: Bool
        var isCurve: Bool
    }

    /// Welds `strokes` at coincident anchors and chains open paths that meet.
    /// Returns the resulting strokes (always fewer than, or as many as, the
    /// input once welding is possible), or `nil` when nothing could be welded
    /// or chained (i.e. no two anchors from different strokes touch).
    static func join(_ strokes: [VectorStroke], tolerance: CGFloat) -> [VectorStroke]? {
        let usable = strokes.filter { $0.points.count >= 2 }
        guard usable.count >= 2, let base = usable.first else { return nil }

        var paths = usable.map { normalized($0) }
        let welded = weldCoincidentAnchors(in: &paths, tolerance: tolerance)

        // Chain open paths (some may auto-close into loops), then fuse any closed
        // contours that now share an edge into a single union outline.
        let chained = chainOpenPaths(paths, tolerance: tolerance)
        let open = chained.filter { !$0.isClosed }
        let closed = chained.filter { $0.isClosed }
        let mergedClosed = mergeClosedContours(closed, tolerance: tolerance)
        let result = open + mergedClosed

        // If nothing touched (no welds and no structural merge) there is nothing to
        // join – tell the caller so it can leave the selection alone.
        guard welded || result.count < paths.count else { return nil }

        return result.map { stroke(from: $0, base: base) }
    }

    // MARK: - Normalization

    /// Converts a stroke into an anchor + handle path. Non-curve strokes receive
    /// zero-offset (straight) handles so mixed joins keep their curved parts.
    private static func normalized(_ stroke: VectorStroke) -> Path {
        let points = stroke.points
        let isCurve = stroke.shapeType == .curve
        if isCurve, let handles = stroke.curveHandles, handles.count == points.count {
            return Path(points: points, handles: handles, isClosed: stroke.isClosed, isCurve: true)
        }
        return Path(
            points: points,
            handles: Array(repeating: CurveHandle(), count: points.count),
            isClosed: stroke.isClosed,
            isCurve: isCurve
        )
    }

    private static func stroke(from path: Path, base: VectorStroke) -> VectorStroke {
        var result = base
        result.id = UUID()
        result.points = path.points
        result.isClosed = path.isClosed
        result.shapeType = path.isCurve ? .curve : .polyline
        result.curveHandles = path.isCurve ? path.handles : nil
        result.shapeRotation = nil
        result.rotationBasePoints = nil
        result.rotationBaseCenter = nil
        result.cutoutPoints = []
        result.cornerRadius = 0
        result.cornerRadiiByIndex = nil
        result.smoothCornerIndices = nil
        return result
    }

    // MARK: - Anchor welding

    /// Snaps every anchor that lies within `tolerance` of anchors on *other*
    /// paths onto a single shared coordinate (the cluster centroid). Returns
    /// true when at least one cross-path weld happened.
    private static func weldCoincidentAnchors(in paths: inout [Path], tolerance: CGFloat) -> Bool {
        struct Ref { let path: Int; let point: Int }

        var refs: [Ref] = []
        for (p, path) in paths.enumerated() {
            for i in path.points.indices { refs.append(Ref(path: p, point: i)) }
        }
        guard refs.count >= 2 else { return false }

        // Union-find over anchors that fall within tolerance.
        var parent = Array(0..<refs.count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root { let next = parent[node]; parent[node] = root; node = next }
            return root
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        for a in 0..<refs.count {
            let pa = paths[refs[a].path].points[refs[a].point]
            for b in (a + 1)..<refs.count {
                let pb = paths[refs[b].path].points[refs[b].point]
                if hypot(pa.x - pb.x, pa.y - pb.y) <= tolerance { union(a, b) }
            }
        }

        // Group anchors by cluster and detect cross-path welds.
        var clusters: [Int: [Int]] = [:]
        for i in refs.indices { clusters[find(i), default: []].append(i) }

        var didWeld = false
        for (_, members) in clusters where members.count > 1 {
            let touchesMultiplePaths = Set(members.map { refs[$0].path }).count > 1
            if touchesMultiplePaths { didWeld = true }
            // Collapse the whole cluster onto its centroid so seams match exactly.
            var sum = CGPoint.zero
            for m in members {
                let pt = paths[refs[m].path].points[refs[m].point]
                sum.x += pt.x
                sum.y += pt.y
            }
            let centroid = CGPoint(x: sum.x / CGFloat(members.count), y: sum.y / CGFloat(members.count))
            for m in members {
                paths[refs[m].path].points[refs[m].point] = centroid
            }
        }
        return didWeld
    }

    // MARK: - Chaining

    /// Greedily chains open paths that share an exact endpoint (after welding)
    /// into single continuous paths. Closed paths pass through untouched.
    private static func chainOpenPaths(_ paths: [Path], tolerance: CGFloat) -> [Path] {
        let closed = paths.filter { $0.isClosed }
        var open = paths.filter { !$0.isClosed }
        var chains: [Path] = []

        while let current = open.first {
            open.removeFirst()
            var chain = current

            var madeProgress = true
            while madeProgress {
                madeProgress = false
                guard let match = bestConnection(result: chain, candidates: open, tolerance: tolerance) else { break }
                var candidate = open[match.index]
                if match.reversed { candidate = reverse(candidate) }
                chain = match.attachToEnd
                    ? append(chain, candidate, tolerance: tolerance)
                    : append(candidate, chain, tolerance: tolerance)
                open.remove(at: match.index)
                madeProgress = true
            }

            // If the chain's two ends now coincide, close it into a loop.
            if chain.points.count > 2,
               let first = chain.points.first,
               let last = chain.points.last,
               hypot(first.x - last.x, first.y - last.y) <= tolerance {
                chain.points.removeLast()
                chain.handles.removeLast()
                chain.isClosed = true
            }
            chains.append(chain)
        }

        // Closed shapes keep their welded coordinates but stay separate contours.
        return chains + closed
    }

    // MARK: - Closed-contour union

    private struct DirectedEdge {
        var from: CGPoint
        var to: CGPoint
        var poly: Int
    }

    /// Boolean-unions closed contours into their combined outline(s). Handles
    /// butted (shared-edge), overlapping, nested, and point-touching shapes:
    ///
    /// 1. Every contour is oriented counter-clockwise and its edges are split at
    ///    all crossings with the other contours.
    /// 2. Sub-edges shared by two contours (coincident seams) cancel against
    ///    their reverse twin.
    /// 3. Any sub-edge whose midpoint lies inside another contour is interior to
    ///    the union and dropped.
    /// 4. The surviving boundary is re-traced into closed loops.
    ///
    /// The union is computed on the anchor polygons, so the result is a polyline
    /// outline (closed-curve handles are not preserved). Non-touching contours
    /// are returned unchanged.
    private static func mergeClosedContours(_ paths: [Path], tolerance: CGFloat) -> [Path] {
        guard paths.count >= 2, paths.allSatisfy({ $0.points.count >= 3 }) else { return paths }

        // Orient every polygon counter-clockwise so shared seams run opposite ways.
        let polygons: [[CGPoint]] = paths.map { path in
            signedArea(path.points) < 0 ? Array(path.points.reversed()) : path.points
        }

        let snap = max(tolerance * 0.1, 1e-4)

        // Split each polygon edge at its intersections with every other polygon.
        var directed: [DirectedEdge] = []
        for (i, polygon) in polygons.enumerated() {
            for k in polygon.indices {
                let a = polygon[k]
                let b = polygon[(k + 1) % polygon.count]
                var cuts: [CGPoint] = [a, b]
                for (j, other) in polygons.enumerated() where j != i {
                    for m in other.indices {
                        let c = other[m]
                        let d = other[(m + 1) % other.count]
                        if let hit = segmentIntersection(a, b, c, d) { cuts.append(hit) }
                    }
                }
                let ordered = orderedAlong(a, b, points: cuts, snap: snap)
                for s in 0..<(ordered.count - 1) {
                    let from = ordered[s]
                    let to = ordered[s + 1]
                    if distance(from, to) > snap {
                        directed.append(DirectedEdge(from: from, to: to, poly: i))
                    }
                }
            }
        }
        guard !directed.isEmpty else { return paths }

        // Cancel each sub-edge against a coincident reverse twin (shared seams).
        var alive = [Bool](repeating: true, count: directed.count)
        for x in directed.indices where alive[x] {
            for y in (x + 1)..<directed.count where alive[y] {
                if distance(directed[x].from, directed[y].to) <= snap
                    && distance(directed[x].to, directed[y].from) <= snap {
                    alive[x] = false
                    alive[y] = false
                    break
                }
            }
        }

        // Drop sub-edges that lie inside another contour (interior to the union).
        var boundary: [DirectedEdge] = []
        for (index, edge) in directed.enumerated() where alive[index] {
            let midpoint = CGPoint(x: (edge.from.x + edge.to.x) / 2, y: (edge.from.y + edge.to.y) / 2)
            let insideOther = polygons.indices.contains { j in
                j != edge.poly && pointInsidePolygon(midpoint, polygons[j])
            }
            if !insideOther { boundary.append(edge) }
        }

        let changed = boundary.count < directed.count || directed.count != totalEdges(polygons)
        guard !boundary.isEmpty, changed else { return paths }

        // Re-trace the surviving boundary into closed loops.
        var adjacency: [String: [Int]] = [:]
        for (index, edge) in boundary.enumerated() {
            adjacency[snappedKey(edge.from, snap: snap), default: []].append(index)
        }
        var used = [Bool](repeating: false, count: boundary.count)
        var loops: [Path] = []
        for startIndex in boundary.indices where !used[startIndex] {
            var points: [CGPoint] = []
            var current: Int? = startIndex
            while let index = current, !used[index] {
                used[index] = true
                let edge = boundary[index]
                points.append(edge.from)
                let candidates = adjacency[snappedKey(edge.to, snap: snap)] ?? []
                current = candidates.first { !used[$0] }
            }
            if points.count >= 3 {
                loops.append(Path(
                    points: points,
                    handles: Array(repeating: CurveHandle(), count: points.count),
                    isClosed: true,
                    isCurve: false
                ))
            }
        }

        return loops.isEmpty ? paths : loops
    }

    private static func totalEdges(_ polygons: [[CGPoint]]) -> Int {
        polygons.reduce(0) { $0 + $1.count }
    }

    /// Proper intersection point of segments `a→b` and `c→d`, or nil when they
    /// are parallel or don't cross within both segments.
    private static func segmentIntersection(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let r = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let s = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let denom = r.x * s.y - r.y * s.x
        let scale = hypot(r.x, r.y) * hypot(s.x, s.y)
        guard abs(denom) > 1e-9 * max(scale, 1) else { return nil }
        let qp = CGPoint(x: c.x - a.x, y: c.y - a.y)
        let t = (qp.x * s.y - qp.y * s.x) / denom
        let u = (qp.x * r.y - qp.y * r.x) / denom
        let eps: CGFloat = 1e-6
        guard t >= -eps, t <= 1 + eps, u >= -eps, u <= 1 + eps else { return nil }
        let clamped = Swift.max(0, Swift.min(1, t))
        return CGPoint(x: a.x + clamped * r.x, y: a.y + clamped * r.y)
    }

    /// De-duplicates `points` and sorts them by distance along `a→b`.
    private static func orderedAlong(_ a: CGPoint, _ b: CGPoint, points: [CGPoint], snap: CGFloat) -> [CGPoint] {
        let axis = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = axis.x * axis.x + axis.y * axis.y
        func projection(_ p: CGPoint) -> CGFloat {
            guard lengthSquared > 0 else { return 0 }
            return ((p.x - a.x) * axis.x + (p.y - a.y) * axis.y) / lengthSquared
        }
        let sorted = points.sorted { projection($0) < projection($1) }
        var result: [CGPoint] = []
        for point in sorted where result.last.map({ distance($0, point) > snap }) ?? true {
            result.append(point)
        }
        return result
    }

    /// Strict point-in-polygon test (ray casting); boundary points count as out.
    private static func pointInsidePolygon(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let slope = (point.y - a.y) / (b.y - a.y)
                let x = a.x + slope * (b.x - a.x)
                if point.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func snappedKey(_ p: CGPoint, snap: CGFloat) -> String {
        let q = max(snap, 1e-4)
        return "\(Int((p.x / q).rounded()))_\(Int((p.y / q).rounded()))"
    }

    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        var area: CGFloat = 0
        for i in points.indices {
            let j = (i + 1) % points.count
            area += points[i].x * points[j].y - points[j].x * points[i].y
        }
        return area / 2
    }

    private static func reverse(_ path: Path) -> Path {
        Path(
            points: path.points.reversed().map { $0 },
            handles: path.handles.reversed().map {
                CurveHandle(inOffset: $0.outOffset, outOffset: $0.inOffset)
            },
            isClosed: path.isClosed,
            isCurve: path.isCurve
        )
    }

    /// Appends `tail` after `head`, welding the shared endpoint when close enough.
    private static func append(_ head: Path, _ tail: Path, tolerance: CGFloat) -> Path {
        guard let last = head.points.last, let first = tail.points.first else {
            return Path(
                points: head.points + tail.points,
                handles: head.handles + tail.handles,
                isClosed: false,
                isCurve: head.isCurve || tail.isCurve
            )
        }
        var merged = head
        merged.isClosed = false
        merged.isCurve = head.isCurve || tail.isCurve
        if hypot(last.x - first.x, last.y - first.y) <= tolerance {
            if !tail.handles.isEmpty {
                merged.handles[merged.handles.count - 1].outOffset = tail.handles[0].outOffset
            }
            merged.points.append(contentsOf: tail.points.dropFirst())
            merged.handles.append(contentsOf: tail.handles.dropFirst())
        } else {
            merged.points.append(contentsOf: tail.points)
            merged.handles.append(contentsOf: tail.handles)
        }
        return merged
    }

    private struct Connection {
        var index: Int
        var reversed: Bool
        var attachToEnd: Bool
        var gap: CGFloat
    }

    /// Finds the closest connectable candidate whose endpoint touches `result`'s
    /// start or end within `tolerance`. Returns nil when nothing touches.
    private static func bestConnection(result: Path, candidates: [Path], tolerance: CGFloat) -> Connection? {
        guard let resultStart = result.points.first, let resultEnd = result.points.last else { return nil }
        var best: Connection?

        for (index, candidate) in candidates.enumerated() {
            guard let candStart = candidate.points.first, let candEnd = candidate.points.last else { continue }
            let options: [Connection] = [
                Connection(index: index, reversed: false, attachToEnd: true, gap: distance(resultEnd, candStart)),
                Connection(index: index, reversed: true, attachToEnd: true, gap: distance(resultEnd, candEnd)),
                Connection(index: index, reversed: false, attachToEnd: false, gap: distance(resultStart, candEnd)),
                Connection(index: index, reversed: true, attachToEnd: false, gap: distance(resultStart, candStart))
            ]
            for option in options where option.gap <= tolerance && (best == nil || option.gap < best!.gap) {
                best = option
            }
        }
        return best
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
