//
//  PathJoinEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Permanently welds strokes that share touching anchors into as few shapes as
/// possible.
///
/// Unlike grouping (structural only), joining collapses coincident anchors onto
/// one shared coordinate and fuses the connected strokes into a single path
/// whenever topology allows. Open and closed shapes are both eligible — Join is
/// available whenever any two anchors from different selected strokes sit within
/// tolerance of each other.
///
/// Fidelity: closed shapes fuse using their *true rendered contour* (dense
/// samples from `ShapeGeometry.renderPoints`) rather than a handful of anchor
/// points, so circles, ellipses, arcs, beziers and baked fillets keep their real
/// geometry through a join instead of collapsing into a few straight segments.
enum PathJoinEngine {
    private struct Path {
        var points: [CGPoint]
        var handles: [CurveHandle]
        var isClosed: Bool
        var isCurve: Bool
        /// True rendered outline (dense) used for boolean-union fusion so curved
        /// geometry survives. Equals `points` for non-curve shapes.
        var contour: [CGPoint]
        /// Inner holes (even-odd) carried through the join so complex shapes keep
        /// their cutouts.
        var cutouts: [[CGPoint]] = []
    }

    // MARK: - Public API

    /// True when any anchor on one stroke sits within `tolerance` of an anchor
    /// on a different stroke. Uses the same handle points the move tool shows.
    static func hasTouchingAnchors(_ strokes: [VectorStroke], tolerance: CGFloat) -> Bool {
        let pointSets = strokes.map { ShapeGeometry.handlePoints(for: $0) }
            .filter { $0.count >= 2 }
        guard pointSets.count >= 2 else { return false }

        for i in 0..<pointSets.count {
            for j in (i + 1)..<pointSets.count {
                for a in pointSets[i] {
                    for b in pointSets[j] {
                        if distance(a, b) <= tolerance { return true }
                    }
                }
            }
        }
        return false
    }

    /// True when Join can do something: any two selected shapes either share a
    /// touching anchor or (for closed shapes) overlap. Open vs closed doesn't
    /// matter for the anchor case — Join appears whenever a weld/fuse is possible.
    static func canJoin(_ strokes: [VectorStroke], tolerance: CGFloat) -> Bool {
        let usable = strokes.filter { ShapeGeometry.handlePoints(for: $0).count >= 2 }
        guard usable.count >= 2 else { return false }
        if usable.allSatisfy(isOutlineChainable) {
            return canChainOpenContours(usable, tolerance: tolerance)
        }
        if hasTouchingAnchors(usable, tolerance: tolerance) { return true }

        // Closed shapes that overlap (edges cross or one contains the other) can
        // be unioned even without a shared anchor.
        let closed = usable.map { normalized($0) }.filter { $0.isClosed && $0.contour.count >= 3 }
        for i in closed.indices {
            for j in (i + 1)..<closed.count where closedContoursOverlap(closed[i].contour, closed[j].contour) {
                return true
            }
        }
        return false
    }

    /// Welds touching anchors and fuses each connected group (linked by a shared
    /// anchor or by overlapping closed contours) into one path. Returns `nil`
    /// when nothing can be fused.
    static func join(_ strokes: [VectorStroke], tolerance: CGFloat) -> [VectorStroke]? {
        let usable = strokes.filter { ShapeGeometry.handlePoints(for: $0).count >= 2 }
        guard usable.count >= 2, let base = usable.first else { return nil }

        // Lines, arcs, and curves — including ones that were auto-marked closed
        // (a star point becomes a triangle) — join by chaining outlines at
        // endpoints. Boolean-union / centroid-weld of those pieces collapses
        // stars and hearts into a blob.
        if usable.allSatisfy(isOutlineChainable) {
            return joinOpenContours(usable, tolerance: tolerance, base: base)
        }

        var paths = usable.map { normalized($0) }
        _ = weldCoincidentAnchors(in: &paths, tolerance: tolerance)

        // Fuse every connected component (paths linked by a shared welded point or
        // by overlapping closed contours) down to a single stroke so the weld is
        // permanent, not just coincident.
        let components = connectedComponents(paths, tolerance: tolerance)
        guard components.contains(where: { $0.count >= 2 }) else { return nil }
        let fused = components.map { fuseComponent($0, tolerance: tolerance) }

        return fused.map { stroke(from: $0, base: base) }
    }

    private static func isOutlineChainable(_ stroke: VectorStroke) -> Bool {
        switch stroke.shapeType {
        case .polyline, .arc, .curve:
            return true
        default:
            return false
        }
    }

    // MARK: - Normalization

    /// Converts a stroke into an editable anchor path plus its dense rendered
    /// contour. Curve handles are kept when the stroke is already a curve.
    /// Arcs, circles, ellipses and baked fillets store their *rendered* outline
    /// as the point list so fusion follows the real curve instead of a handful
    /// of defining anchors (which collapse into straight chords).
    private static func normalized(_ stroke: VectorStroke) -> Path {
        let contour = ShapeGeometry.renderPoints(for: stroke)
        let cutouts = stroke.cutoutPoints

        if stroke.shapeType == .curve,
           let handles = stroke.curveHandles,
           handles.count == stroke.points.count {
            return Path(
                points: stroke.points, handles: handles,
                isClosed: stroke.isClosed, isCurve: true,
                contour: contour, cutouts: cutouts
            )
        }

        // Circles / ellipses / rectangles / polylines: use the dense rendered
        // outline as the anchor list so fusion follows the real curve.
        let points = contour
        return Path(
            points: points,
            handles: Array(repeating: CurveHandle(), count: points.count),
            isClosed: stroke.isClosed || stroke.shapeType == .rectangle
                || stroke.shapeType == .circle || stroke.shapeType == .ellipse,
            isCurve: false,
            contour: contour,
            cutouts: cutouts
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
        result.cutoutPoints = path.cutouts
        result.cornerRadius = 0
        result.cornerRadiiByIndex = nil
        result.smoothCornerIndices = nil
        result.isConstruction = false
        return ShapeGeometry.withCompactedCircularAnchors(result)
    }

    // MARK: - Open contour join

    /// Walks lines/arcs/curves as chains of exclusive endpoint pairs and
    /// concatenates each stroke's outline. Points are never moved.
    /// Returns every fused component plus leftover originals that did not join.
    private static func joinOpenContours(
        _ strokes: [VectorStroke],
        tolerance: CGFloat,
        base: VectorStroke
    ) -> [VectorStroke]? {
        let pairing = outlineEndpointPairing(strokes, tolerance: tolerance)
        guard pairing.pairOf.contains(where: { $0 >= 0 }) else { return nil }

        let contours = pairing.contours
        let endpoints = pairing.endpoints
        let pairOf = pairing.pairOf
        let lengths = pairing.lengths

        func otherEnd(of endpoint: Int) -> Int {
            endpoints[endpoint].isStart ? endpoint + 1 : endpoint - 1
        }

        func walk(from startIndex: Int, usedStrokes: inout Set<Int>) -> [(stroke: Int, forward: Bool)] {
            var ordered: [(stroke: Int, forward: Bool)] = []
            var current = startIndex
            while true {
                let strokeIndex = endpoints[current].stroke
                if usedStrokes.contains(strokeIndex) { break }
                usedStrokes.insert(strokeIndex)
                ordered.append((strokeIndex, endpoints[current].isStart))
                let next = pairOf[otherEnd(of: current)]
                if next < 0 { break }
                current = next
            }
            return ordered
        }

        func polyline(from ordered: [(stroke: Int, forward: Bool)]) -> VectorStroke? {
            guard ordered.count >= 2 else { return nil }
            var merged: [CGPoint] = []
            var previousStroke = -1
            for step in ordered {
                let contour = contours[step.stroke]
                let segment = step.forward ? contour : Array(contour.reversed())
                if merged.isEmpty {
                    merged.append(contentsOf: segment)
                } else if let last = merged.last, let first = segment.first {
                    let joint = joinGapLimit(
                        lengthA: previousStroke >= 0 ? lengths[previousStroke] : lengths[step.stroke],
                        lengthB: lengths[step.stroke],
                        tolerance: tolerance
                    )
                    if distance(last, first) <= joint {
                        merged.append(contentsOf: segment.dropFirst())
                    } else {
                        merged.append(contentsOf: segment)
                    }
                }
                previousStroke = step.stroke
            }
            guard merged.count >= 2 else { return nil }
            var closed = false
            if shouldCloseJoinedContour(merged, tolerance: tolerance) {
                merged.removeLast()
                closed = true
            }
            guard merged.count >= (closed ? 3 : 2) else { return nil }
            var path = Path(
                points: merged,
                handles: Array(repeating: CurveHandle(), count: merged.count),
                isClosed: closed,
                isCurve: false,
                contour: merged
            )
            path.cutouts = ordered.flatMap { strokes[$0.stroke].cutoutPoints }
            return stroke(from: path, base: base)
        }

        var unused = Set(strokes.indices)
        var fused: [VectorStroke] = []
        while !unused.isEmpty {
            let unusedEndpoints = endpoints.indices.filter { unused.contains(endpoints[$0].stroke) }
            let start = unusedEndpoints.first(where: { pairOf[$0] < 0 })
                ?? unusedEndpoints.first(where: { pairOf[$0] >= 0 })
            guard let start else { break }
            var used = Set<Int>()
            let ordered = walk(from: start, usedStrokes: &used)
            unused.subtract(used)
            if let piece = polyline(from: ordered) {
                fused.append(piece)
            } else {
                for index in used {
                    fused.append(strokes[index])
                }
            }
        }
        for index in unused {
            fused.append(strokes[index])
        }

        return fused.isEmpty ? nil : fused
    }

    private static func canChainOpenContours(_ strokes: [VectorStroke], tolerance: CGFloat) -> Bool {
        outlineEndpointPairing(strokes, tolerance: tolerance).pairOf.contains { $0 >= 0 }
    }

    private struct JoinEndpoint {
        var stroke: Int
        var isStart: Bool
        var point: CGPoint
    }

    /// Exclusive nearest-endpoint matches, capped so a short star/heart edge is
    /// not welded to a different nearby vertex just because both sit in the same
    /// grid cell (join tolerance is often half an inch).
    private static func outlineEndpointPairing(
        _ strokes: [VectorStroke],
        tolerance: CGFloat
    ) -> (contours: [[CGPoint]], endpoints: [JoinEndpoint], pairOf: [Int], lengths: [CGFloat]) {
        let contours = strokes.map { joinContour(for: $0) }
        let lengths = contours.map { contourLength($0) }

        var endpoints: [JoinEndpoint] = []
        endpoints.reserveCapacity(strokes.count * 2)
        for (index, contour) in contours.enumerated() {
            guard let first = contour.first, let last = contour.last, contour.count >= 2 else {
                continue
            }
            endpoints.append(JoinEndpoint(stroke: index, isStart: true, point: first))
            endpoints.append(JoinEndpoint(stroke: index, isStart: false, point: last))
        }

        var pairOf = Array(repeating: -1, count: endpoints.count)
        var pairs: [(Int, Int, CGFloat)] = []
        for i in 0..<endpoints.count {
            for j in (i + 1)..<endpoints.count {
                guard endpoints[i].stroke != endpoints[j].stroke else { continue }
                let gap = distance(endpoints[i].point, endpoints[j].point)
                let limit = joinGapLimit(
                    lengthA: lengths[endpoints[i].stroke],
                    lengthB: lengths[endpoints[j].stroke],
                    tolerance: tolerance
                )
                if gap <= limit { pairs.append((i, j, gap)) }
            }
        }
        pairs.sort { $0.2 < $1.2 }
        for (i, j, _) in pairs {
            if pairOf[i] == -1, pairOf[j] == -1 {
                pairOf[i] = j
                pairOf[j] = i
            }
        }
        return (contours, endpoints, pairOf, lengths)
    }

    /// Polylines join at drawn anchors. Arcs/curves use the rendered outline so
    /// a lobe stays a curve instead of collapsing to its three handles.
    private static func joinContour(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .arc, .curve:
            return ShapeGeometry.renderPoints(for: stroke)
        default:
            return stroke.points
        }
    }

    private static func contourLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for index in 0..<(points.count - 1) {
            length += distance(points[index], points[index + 1])
        }
        return length
    }

    private static func joinGapLimit(lengthA: CGFloat, lengthB: CGFloat, tolerance: CGFloat) -> CGFloat {
        let shortest = min(lengthA, lengthB)
        return min(tolerance, max(1.5, shortest * 0.35))
    }

    /// Close a joined outline only when the remaining gap is tiny next to the
    /// drawn length. Half a grid cell would otherwise close a small V / star
    /// point into a triangle (or a blob) just because its feet share a cell.
    private static func shouldCloseJoinedContour(_ points: [CGPoint], tolerance: CGFloat) -> Bool {
        guard points.count > 2, let first = points.first, let last = points.last else { return false }
        let gap = distance(first, last)
        guard gap <= tolerance else { return false }
        return gap <= max(1, min(tolerance, contourLength(points) * 0.05))
    }

    // MARK: - Anchor welding

    /// Snaps *structural* anchors that lie within `tolerance` of anchors on
    /// *other* paths onto a single shared coordinate (the cluster centroid).
    ///
    /// Tessellated interiors (arc/circle samples) are not welded: adjacent
    /// samples sit closer than a grid-cell tolerance, and union-find would then
    /// chain a whole lobe into the junction and collapse the shape.
    @discardableResult
    private static func weldCoincidentAnchors(in paths: inout [Path], tolerance: CGFloat) -> Bool {
        struct Ref { let path: Int; let point: Int }

        var refs: [Ref] = []
        for (p, path) in paths.enumerated() {
            for i in structuralIndices(path) { refs.append(Ref(path: p, point: i)) }
        }
        guard refs.count >= 2 else { return false }

        var parent = Array(0..<refs.count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        for a in 0..<refs.count {
            let pa = paths[refs[a].path].points[refs[a].point]
            for b in (a + 1)..<refs.count {
                // Only weld anchors from *different* shapes. Welding two points of
                // the same shape is never intended, and dense contours (e.g. a
                // circle's 64 samples) can sit closer than tolerance to their own
                // neighbors, which would otherwise chain a whole shape into one
                // point and collapse it.
                guard refs[a].path != refs[b].path else { continue }
                let pb = paths[refs[b].path].points[refs[b].point]
                if distance(pa, pb) <= tolerance { union(a, b) }
            }
        }

        var clusters: [Int: [Int]] = [:]
        for i in refs.indices { clusters[find(i), default: []].append(i) }

        var didWeld = false
        for (_, members) in clusters where members.count > 1 {
            if Set(members.map { refs[$0].path }).count > 1 { didWeld = true }
            var sum = CGPoint.zero
            for m in members {
                let pt = paths[refs[m].path].points[refs[m].point]
                sum.x += pt.x
                sum.y += pt.y
            }
            let centroid = CGPoint(
                x: sum.x / CGFloat(members.count),
                y: sum.y / CGFloat(members.count)
            )
            for m in members {
                paths[refs[m].path].points[refs[m].point] = centroid
            }
        }
        return didWeld
    }

    // MARK: - Connected components

    /// Groups paths that share at least one welded point.
    private static func connectedComponents(_ paths: [Path], tolerance: CGFloat) -> [[Path]] {
        guard !paths.isEmpty else { return [] }
        var parent = Array(0..<paths.count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        for i in 0..<paths.count {
            for j in (i + 1)..<paths.count {
                if sharesPoint(paths[i], paths[j], tolerance: tolerance)
                    || pathsOverlap(paths[i], paths[j]) {
                    union(i, j)
                }
            }
        }

        var groups: [Int: [Path]] = [:]
        for i in paths.indices {
            groups[find(i), default: []].append(paths[i])
        }
        return Array(groups.values)
    }

    private static func sharesPoint(_ a: Path, _ b: Path, tolerance: CGFloat) -> Bool {
        for p in structuralPoints(a) {
            for q in structuralPoints(b) where distance(p, q) <= tolerance { return true }
        }
        return false
    }

    /// Anchors that may participate in a weld / connection test.
    /// Open paths: endpoints only. Sparse closed polygons: every vertex.
    /// Dense closed tessellations (circles, pies): none — overlap is handled
    /// by boolean union, not point welding.
    private static func structuralIndices(_ path: Path) -> [Int] {
        let count = path.points.count
        guard count >= 1 else { return [] }
        if !path.isClosed {
            return count == 1 ? [0] : [0, count - 1]
        }
        if count > 8 { return [] }
        return Array(0..<count)
    }

    private static func structuralPoints(_ path: Path) -> [CGPoint] {
        structuralIndices(path).map { path.points[$0] }
    }

    /// True when two closed paths overlap (their rendered contours cross or one
    /// contains the other), so they can be unioned without sharing an anchor.
    private static func pathsOverlap(_ a: Path, _ b: Path) -> Bool {
        guard a.isClosed, b.isClosed else { return false }
        return closedContoursOverlap(a.contour, b.contour)
    }

    private static func closedContoursOverlap(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        guard a.count >= 3, b.count >= 3 else { return false }
        for i in a.indices {
            let a1 = a[i]
            let a2 = a[(i + 1) % a.count]
            for j in b.indices {
                let b1 = b[j]
                let b2 = b[(j + 1) % b.count]
                if segmentIntersection(a1, a2, b1, b2) != nil { return true }
            }
        }
        if let p = a.first, pointInsidePolygon(p, b) { return true }
        if let p = b.first, pointInsidePolygon(p, a) { return true }
        return false
    }

    // MARK: - Fuse a connected component into one path

    /// Merges every path in a touching group into a single stroke, carrying any
    /// cutouts through so holes survive the weld.
    private static func fuseComponent(_ paths: [Path], tolerance: CGFloat) -> Path {
        guard let first = paths.first else {
            return Path(points: [], handles: [], isClosed: false, isCurve: false, contour: [])
        }

        let cutouts = paths.flatMap(\.cutouts)

        guard paths.count >= 2 else {
            var only = first
            only.cutouts = cutouts
            return only
        }

        var result: Path

        // Closed-only: prefer a clean boolean-union outline when shapes share an
        // edge or overlap. Falls through to stitching when they only share a point.
        if paths.allSatisfy(\.isClosed) {
            let merged = mergeClosedContours(paths, tolerance: tolerance)
            if merged.count == 1 {
                result = merged[0]
                // Preserve pre-existing holes from the inputs *and* any hole the
                // union itself carved out.
                result.cutouts = cutouts + result.cutouts
                return result
            }
        }

        // Open-only: chain at shared endpoints first.
        if paths.allSatisfy({ !$0.isClosed }) {
            let chained = chainOpenPaths(paths, tolerance: tolerance)
            result = chained.count == 1 ? chained[0] : stitchPaths(chained, tolerance: tolerance)
            result.cutouts = cutouts
            return result
        }

        // Mixed open/closed, or closed shapes that only touch at a point.
        result = stitchPaths(paths, tolerance: tolerance)
        result.cutouts = cutouts
        return result
    }

    /// Stitches paths that share vertices into one polyline by splicing each
    /// remaining path into the host at a shared anchor (spur / figure-8 style).
    /// Guarantees a single path so the weld is permanent.
    private static func stitchPaths(_ paths: [Path], tolerance: CGFloat) -> Path {
        var remaining = paths
        // Prefer a closed path as the host so its loop survives the weld, then
        // fall back to the path with the most anchors for a stable host.
        remaining.sort { lhs, rhs in
            if lhs.isClosed != rhs.isClosed { return lhs.isClosed }
            return lhs.points.count > rhs.points.count
        }
        var host = remaining.removeFirst()

        while !remaining.isEmpty {
            var attached = false
            for (index, guest) in remaining.enumerated() {
                if let shared = sharedPoint(host, guest, tolerance: tolerance) {
                    host = splice(host, guest, at: shared, tolerance: tolerance)
                    remaining.remove(at: index)
                    attached = true
                    break
                }
            }
            if !attached {
                // Shouldn't happen inside a connected component; force-append.
                let guest = remaining.removeFirst()
                host = append(host, guest, tolerance: tolerance)
            }
        }

        // Close the result when its ends coincide (or every input was closed).
        if host.points.count > 2,
           let first = host.points.first,
           let last = host.points.last,
           distance(first, last) <= tolerance {
            host.points.removeLast()
            if !host.handles.isEmpty { host.handles.removeLast() }
            host.isClosed = true
        } else if paths.allSatisfy(\.isClosed) {
            host.isClosed = true
        }

        host.isCurve = paths.contains(where: \.isCurve)
        if !host.isCurve {
            host.handles = Array(repeating: CurveHandle(), count: host.points.count)
        }
        host.contour = host.points
        return host
    }

    private static func sharedPoint(_ a: Path, _ b: Path, tolerance: CGFloat) -> CGPoint? {
        for p in structuralPoints(a) {
            for q in structuralPoints(b) where distance(p, q) <= tolerance { return p }
        }
        return nil
    }

    /// Inserts `guest` into `host` at a shared anchor. Closed guests are walked
    /// as a loop that returns to the join point; open guests become a spur that
    /// doubles back when the join is mid-path. Curve handles are carried through
    /// the walk so arcs and curves keep their shape, and the host's closedness is
    /// preserved so welding a spur onto a closed shape leaves it closed.
    private static func splice(
        _ host: Path,
        _ guest: Path,
        at shared: CGPoint,
        tolerance: CGFloat
    ) -> Path {
        guard let hostIndex = host.points.firstIndex(where: { distance($0, shared) <= tolerance }),
              let guestIndex = guest.points.firstIndex(where: { distance($0, shared) <= tolerance })
        else {
            return append(host, guest, tolerance: tolerance)
        }

        let guestHandles = guest.handles.count == guest.points.count
            ? guest.handles
            : Array(repeating: CurveHandle(), count: guest.points.count)

        // Walking an anchor in reverse swaps its incoming/outgoing tangents.
        func flip(_ handle: CurveHandle) -> CurveHandle {
            CurveHandle(inOffset: handle.outOffset, outOffset: handle.inOffset)
        }

        var walkPoints: [CGPoint] = []
        var walkHandles: [CurveHandle] = []
        // Tangent leaving the shared anchor into the guest walk, so the first
        // spliced segment keeps its curvature at the weld.
        var junctionOut = CGPoint.zero

        if guest.isClosed {
            // Walk the whole loop starting just after the shared anchor and ending
            // back on it, so the spur closes before continuing along the host.
            junctionOut = guestHandles[guestIndex].outOffset
            let order = Array((guestIndex + 1)..<guest.points.count) + Array(0...guestIndex)
            for i in order {
                walkPoints.append(guest.points[i])
                walkHandles.append(guestHandles[i])
            }
        } else if guestIndex == 0 {
            junctionOut = guestHandles[0].outOffset
            for i in 1..<guest.points.count {
                walkPoints.append(guest.points[i])
                walkHandles.append(guestHandles[i])
            }
        } else if guestIndex == guest.points.count - 1 {
            junctionOut = guestHandles[guestIndex].inOffset
            for i in stride(from: guest.points.count - 2, through: 0, by: -1) {
                walkPoints.append(guest.points[i])
                walkHandles.append(flip(guestHandles[i]))
            }
        } else {
            junctionOut = guestHandles[guestIndex].inOffset
            // Mid-path join: walk to one far end and double back through the join,
            // then walk the other side and return — covers every guest edge.
            for i in stride(from: guestIndex - 1, through: 0, by: -1) {
                walkPoints.append(guest.points[i])
                walkHandles.append(flip(guestHandles[i]))
            }
            walkPoints.append(shared)
            walkHandles.append(CurveHandle())
            for i in (guestIndex + 1)..<guest.points.count {
                walkPoints.append(guest.points[i])
                walkHandles.append(guestHandles[i])
            }
            walkPoints.append(shared)
            walkHandles.append(CurveHandle())
        }

        var points = host.points
        var handles = host.handles.count == host.points.count
            ? host.handles
            : Array(repeating: CurveHandle(), count: host.points.count)
        // Only steer the host's junction tangent when the guest actually curves,
        // so a straight guest never flattens a curved host at the weld.
        if guest.isCurve {
            handles[hostIndex].outOffset = junctionOut
        }
        points.insert(contentsOf: walkPoints, at: hostIndex + 1)
        handles.insert(contentsOf: walkHandles, at: hostIndex + 1)

        return Path(
            points: points,
            handles: handles,
            isClosed: host.isClosed,
            isCurve: host.isCurve || guest.isCurve,
            contour: points
        )
    }

    // MARK: - Open-path chaining

    private static func chainOpenPaths(_ paths: [Path], tolerance: CGFloat) -> [Path] {
        var open = paths.filter { !$0.isClosed }
        let closed = paths.filter(\.isClosed)
        var chains: [Path] = []

        while let current = open.first {
            open.removeFirst()
            var chain = current

            var madeProgress = true
            while madeProgress {
                madeProgress = false
                guard let match = bestConnection(result: chain, candidates: open, tolerance: tolerance)
                else { break }
                var candidate = open[match.index]
                if match.reversed { candidate = reverse(candidate) }
                chain = match.attachToEnd
                    ? append(chain, candidate, tolerance: tolerance)
                    : append(candidate, chain, tolerance: tolerance)
                open.remove(at: match.index)
                madeProgress = true
            }

            if chain.points.count > 2,
               let first = chain.points.first,
               let last = chain.points.last,
               distance(first, last) <= tolerance {
                chain.points.removeLast()
                if !chain.handles.isEmpty { chain.handles.removeLast() }
                chain.isClosed = true
            }
            chains.append(chain)
        }

        return chains + closed
    }

    private static func reverse(_ path: Path) -> Path {
        Path(
            points: path.points.reversed(),
            handles: path.handles.reversed().map {
                CurveHandle(inOffset: $0.outOffset, outOffset: $0.inOffset)
            },
            isClosed: path.isClosed,
            isCurve: path.isCurve,
            contour: path.contour.reversed(),
            cutouts: path.cutouts
        )
    }

    private static func append(_ head: Path, _ tail: Path, tolerance: CGFloat) -> Path {
        guard let last = head.points.last, let first = tail.points.first else {
            let points = head.points + tail.points
            return Path(
                points: points,
                handles: head.handles + tail.handles,
                isClosed: false,
                isCurve: head.isCurve || tail.isCurve,
                contour: points
            )
        }
        var merged = head
        merged.isClosed = false
        merged.isCurve = head.isCurve || tail.isCurve
        if distance(last, first) <= tolerance {
            if !tail.handles.isEmpty, !merged.handles.isEmpty {
                merged.handles[merged.handles.count - 1].outOffset = tail.handles[0].outOffset
            }
            merged.points.append(contentsOf: tail.points.dropFirst())
            if !tail.handles.isEmpty {
                merged.handles.append(contentsOf: tail.handles.dropFirst())
            }
        } else {
            merged.points.append(contentsOf: tail.points)
            merged.handles.append(contentsOf: tail.handles)
        }
        // Handles that no longer line up with anchors would render as straight
        // segments through those anchors — an arc becomes two chords through its
        // midpoint and the shape looks collapsed. Rebuild from tessellated
        // outlines instead of flattening.
        if merged.handles.count != merged.points.count {
            return appendContours(head, tail, tolerance: tolerance)
        }
        merged.contour = merged.points
        return merged
    }

    /// Chains two paths using their tessellated outlines so curvature survives
    /// even when Bezier handles cannot be spliced.
    private static func appendContours(_ head: Path, _ tail: Path, tolerance: CGFloat) -> Path {
        let headPoints = head.contour.count >= 2 ? head.contour : head.points
        let tailPoints = tail.contour.count >= 2 ? tail.contour : tail.points
        guard let last = headPoints.last, let first = tailPoints.first else {
            let points = headPoints + tailPoints
            return Path(
                points: points,
                handles: Array(repeating: CurveHandle(), count: points.count),
                isClosed: false,
                isCurve: false,
                contour: points
            )
        }
        var points = headPoints
        if distance(last, first) <= tolerance {
            points.append(contentsOf: tailPoints.dropFirst())
        } else {
            points.append(contentsOf: tailPoints)
        }
        return Path(
            points: points,
            handles: Array(repeating: CurveHandle(), count: points.count),
            isClosed: false,
            isCurve: false,
            contour: points
        )
    }

    private struct Connection {
        var index: Int
        var reversed: Bool
        var attachToEnd: Bool
        var gap: CGFloat
    }

    private static func bestConnection(
        result: Path,
        candidates: [Path],
        tolerance: CGFloat
    ) -> Connection? {
        guard let resultStart = result.points.first, let resultEnd = result.points.last else {
            return nil
        }
        var best: Connection?

        for (index, candidate) in candidates.enumerated() {
            guard let candStart = candidate.points.first, let candEnd = candidate.points.last else {
                continue
            }
            let options = [
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

    // MARK: - Closed-contour union

    private struct DirectedEdge {
        var from: CGPoint
        var to: CGPoint
        var poly: Int
    }

    /// Boolean-unions closed contours that share an edge or overlap, operating on
    /// each path's *dense rendered contour* so curved outlines fuse faithfully.
    /// Contours that only touch at a point are returned unchanged so the caller
    /// can stitch them instead.
    private static func mergeClosedContours(_ paths: [Path], tolerance: CGFloat) -> [Path] {
        guard paths.count >= 2, paths.allSatisfy({ $0.contour.count >= 3 }) else { return paths }

        let polygons: [[CGPoint]] = paths.map(\.contour)
        let snap = max(tolerance * 0.1, 1e-4)

        // Only union contours that genuinely overlap (share 2D area or a collinear
        // boundary run). Contours that merely touch at a point are returned
        // unchanged so the caller can stitch them instead.
        guard contoursOverlap(polygons, snap: snap) else { return paths }

        // 1. Split every edge at intersections and at on-edge vertices of the
        //    other contours, projecting each cut *exactly* onto the edge so a
        //    subsegment endpoint never drifts off the true boundary (a nearby
        //    vertex within `snap` would otherwise bend the outline sideways).
        var subsegments: [DirectedEdge] = []
        for (i, polygon) in polygons.enumerated() {
            for k in polygon.indices {
                let a = polygon[k]
                let b = polygon[(k + 1) % polygon.count]
                let axis = CGPoint(x: b.x - a.x, y: b.y - a.y)
                let lengthSquared = axis.x * axis.x + axis.y * axis.y
                func parameter(_ p: CGPoint) -> CGFloat {
                    lengthSquared > 0 ? ((p.x - a.x) * axis.x + (p.y - a.y) * axis.y) / lengthSquared : 0
                }
                func projectOntoEdge(_ p: CGPoint) -> CGPoint {
                    let t = Swift.max(0, Swift.min(1, parameter(p)))
                    return CGPoint(x: a.x + t * axis.x, y: a.y + t * axis.y)
                }
                var cuts: [CGPoint] = [a, b]
                for (j, other) in polygons.enumerated() where j != i {
                    for m in other.indices {
                        let c = other[m]
                        let d = other[(m + 1) % other.count]
                        if let hit = segmentIntersection(a, b, c, d) { cuts.append(projectOntoEdge(hit)) }
                        if pointExactlyOnSegment(c, a, b) { cuts.append(projectOntoEdge(c)) }
                    }
                }
                let ordered = cuts.sorted { parameter($0) < parameter($1) }
                // Merge only genuinely-coincident cuts (float noise); a small
                // threshold keeps short-but-real subsegments (e.g. a small
                // circle's chords) instead of dropping the whole contour.
                var deduped: [CGPoint] = []
                for p in ordered where deduped.last.map({ distance($0, p) > 1e-4 }) ?? true {
                    deduped.append(p)
                }
                for s in 0..<max(0, deduped.count - 1) where distance(deduped[s], deduped[s + 1]) > 1e-4 {
                    subsegments.append(DirectedEdge(from: deduped[s], to: deduped[s + 1], poly: i))
                }
            }
        }
        guard !subsegments.isEmpty else { return paths }

        // 2. Drop duplicate coincident subsegments (a shared edge is produced by
        //    both contours), keeping one representative.
        var seen = Set<String>()
        var unique: [DirectedEdge] = []
        for edge in subsegments {
            let ka = unionKey(edge.from), kb = unionKey(edge.to)
            let id = ka < kb ? ka + "|" + kb : kb + "|" + ka
            if seen.insert(id).inserted { unique.append(edge) }
        }

        // 3. Keep a subsegment only where it separates the union interior from the
        //    exterior, orienting it so the interior lies on its left. Probing just
        //    off the midpoint (instead of testing the midpoint) stays robust near
        //    crossings where an edge runs within `snap` of another contour.
        func insideUnion(_ p: CGPoint) -> Bool {
            polygons.contains { pointInsidePolygon(p, $0) }
        }
        var directed: [DirectedEdge] = []
        for edge in unique {
            let d = CGPoint(x: edge.to.x - edge.from.x, y: edge.to.y - edge.from.y)
            let length = hypot(d.x, d.y)
            guard length > 1e-9 else { continue }
            let leftNormal = CGPoint(x: -d.y / length, y: d.x / length)
            let mid = CGPoint(x: (edge.from.x + edge.to.x) / 2, y: (edge.from.y + edge.to.y) / 2)
            let offset = Swift.min(length * 0.25, 1e-3)
            let left = CGPoint(x: mid.x + leftNormal.x * offset, y: mid.y + leftNormal.y * offset)
            let right = CGPoint(x: mid.x - leftNormal.x * offset, y: mid.y - leftNormal.y * offset)
            let leftInside = insideUnion(left)
            let rightInside = insideUnion(right)
            if leftInside == rightInside { continue }
            directed.append(leftInside
                ? edge
                : DirectedEdge(from: edge.to, to: edge.from, poly: edge.poly))
        }
        guard !directed.isEmpty else { return paths }

        // Fuse coincident endpoints *across* contours so tracing connects
        // subsegments at shared crossings, never merging a contour's own dense
        // vertices (which can sit closer than `snap`, e.g. a small circle).
        var endpoints: [CGPoint] = []
        var owners: [Int] = []
        for edge in directed {
            endpoints.append(edge.from); endpoints.append(edge.to)
            owners.append(edge.poly); owners.append(edge.poly)
        }
        let fused = fuseCrossContourVertices(endpoints, owners: owners, snap: snap)
        for index in directed.indices {
            directed[index].from = fused[2 * index]
            directed[index].to = fused[2 * index + 1]
        }

        // 4. Trace boundary loops. At branch vertices pick the most-clockwise
        //    outgoing edge so the fill stays on the left and the outline hugs the
        //    boundary.
        var outgoing: [String: [Int]] = [:]
        for (index, edge) in directed.enumerated() {
            outgoing[unionKey(edge.from), default: []].append(index)
        }
        var used = [Bool](repeating: false, count: directed.count)
        var rawLoops: [[CGPoint]] = []
        for startIndex in directed.indices where !used[startIndex] {
            var points: [CGPoint] = []
            var current = startIndex
            var guardCount = 0
            while !used[current], guardCount <= directed.count {
                guardCount += 1
                used[current] = true
                let edge = directed[current]
                points.append(edge.from)
                let candidates = (outgoing[unionKey(edge.to)] ?? []).filter { !used[$0] }
                guard var next = candidates.first else { break }
                if candidates.count > 1 {
                    let incoming = unitDirection(edge)
                    func turn(_ idx: Int) -> CGFloat {
                        signedAngle(incoming, unitDirection(directed[idx]))
                    }
                    next = candidates.reduce(candidates[0]) { best, cand in
                        turn(cand) < turn(best) ? cand : best
                    }
                }
                current = next
            }
            if points.count >= 3 { rawLoops.append(points) }
        }

        // Discard degenerate slivers that can appear at crossings, then take the
        // largest loop as the outer shell; smaller enclosed loops become holes.
        let areaEpsilon = max(snap * snap * 4, 1e-6)
        let loops = rawLoops.filter { abs(signedArea($0)) > areaEpsilon }
        guard !loops.isEmpty else { return paths }
        var outerIndex = 0
        for i in loops.indices where abs(signedArea(loops[i])) > abs(signedArea(loops[outerIndex])) {
            outerIndex = i
        }
        let outer = loops[outerIndex]
        var holes: [[CGPoint]] = []
        for (i, loop) in loops.enumerated() where i != outerIndex {
            if pointInsidePolygon(polygonCentroid(loop), outer) { holes.append(loop) }
        }

        var result = Path(
            points: outer,
            handles: Array(repeating: CurveHandle(), count: outer.count),
            isClosed: true,
            isCurve: false,
            contour: outer
        )
        result.cutouts = holes
        return [result]
    }

    /// True when two or more contours share interior area or a run of collinear
    /// boundary — i.e. a boolean union is warranted. A single shared point is not
    /// enough (those are left to the stitcher).
    private static func contoursOverlap(_ polygons: [[CGPoint]], snap: CGFloat) -> Bool {
        for i in polygons.indices {
            let pi = polygons[i]
            for k in pi.indices {
                let a = pi[k]
                let b = pi[(k + 1) % pi.count]
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                for j in polygons.indices where j != i {
                    if strictlyInsidePolygon(mid, polygons[j], snap: snap) { return true }
                    if j > i {
                        let pj = polygons[j]
                        for m in pj.indices {
                            if collinearSegmentsOverlap(a, b, pj[m], pj[(m + 1) % pj.count], snap: snap) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    private static func collinearSegmentsOverlap(
        _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, snap: CGFloat
    ) -> Bool {
        guard pointNearLine(c, a, b, snap: snap), pointNearLine(d, a, b, snap: snap) else { return false }
        let axis = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let length = hypot(axis.x, axis.y)
        guard length > 1e-9 else { return false }
        func parameter(_ p: CGPoint) -> CGFloat { ((p.x - a.x) * axis.x + (p.y - a.y) * axis.y) / length }
        let lo = max(0, min(parameter(c), parameter(d)))
        let hi = min(length, max(parameter(c), parameter(d)))
        return hi - lo > snap
    }

    private static func pointNearLine(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, snap: CGFloat) -> Bool {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
        let length = hypot(ab.x, ab.y)
        guard length > 1e-9 else { return false }
        return abs(ab.x * ap.y - ab.y * ap.x) / length <= snap
    }

    /// Vertex-on-edge test with a *tight* lateral tolerance so only vertices
    /// essentially on the edge (shared/collinear boundaries, exact T-junctions)
    /// split it — a vertex that merely grazes within `snap` does not.
    private static func pointExactlyOnSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Bool {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
        let length = hypot(ab.x, ab.y)
        guard length > 1e-9 else { return false }
        guard abs(ab.x * ap.y - ab.y * ap.x) / length <= 1e-4 else { return false }
        let t = (ap.x * ab.x + ap.y * ab.y) / (length * length)
        return t > 1e-4 / length && t < 1 - 1e-4 / length
    }

    private static func unionKey(_ p: CGPoint) -> String {
        "\(Int((p.x / 1e-4).rounded()))_\(Int((p.y / 1e-4).rounded()))"
    }

    private static func fuseCrossContourVertices(
        _ points: [CGPoint], owners: [Int], snap: CGFloat
    ) -> [CGPoint] {
        var parent = Array(points.indices)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root { let next = parent[node]; parent[node] = root; node = next }
            return root
        }
        for i in points.indices {
            for j in (i + 1)..<points.count where owners[i] != owners[j] && distance(points[i], points[j]) <= snap {
                parent[find(i)] = find(j)
            }
        }
        var sums: [Int: (CGFloat, CGFloat, Int)] = [:]
        for i in points.indices {
            let root = find(i)
            let current = sums[root] ?? (0, 0, 0)
            sums[root] = (current.0 + points[i].x, current.1 + points[i].y, current.2 + 1)
        }
        var representative: [Int: CGPoint] = [:]
        for (root, sum) in sums {
            representative[root] = CGPoint(x: sum.0 / CGFloat(sum.2), y: sum.1 / CGFloat(sum.2))
        }
        return points.indices.map { representative[find($0)]! }
    }

    private static func polygonCentroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for p in points { x += p.x; y += p.y }
        return CGPoint(x: x / CGFloat(points.count), y: y / CGFloat(points.count))
    }

    private static func segmentIntersection(
        _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint
    ) -> CGPoint? {
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

    /// True when `p` lies on the open segment `a`–`b` (collinear within `snap` and
    /// strictly between the endpoints).
    private static func pointOnSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, snap: CGFloat) -> Bool {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
        let len = hypot(ab.x, ab.y)
        guard len > 1e-9 else { return false }
        let cross = abs(ab.x * ap.y - ab.y * ap.x) / len
        guard cross <= snap else { return false }
        let t = (ap.x * ab.x + ap.y * ab.y) / (len * len)
        return t > snap / len && t < 1 - snap / len
    }

    private static func pointInsidePolygon(_ point: CGPoint, _ polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let x = a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if point.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Strictly-inside test: a point sitting on the polygon boundary counts as NOT
    /// inside, so shared collinear edges are preserved (they are deduped instead).
    private static func strictlyInsidePolygon(_ point: CGPoint, _ polygon: [CGPoint], snap: CGFloat) -> Bool {
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            if distance(point, a) <= snap { return false }
            if pointOnSegment(point, a, b, snap: snap) { return false }
        }
        return pointInsidePolygon(point, polygon)
    }

    private static func unitDirection(_ e: DirectedEdge) -> CGPoint {
        let d = CGPoint(x: e.to.x - e.from.x, y: e.to.y - e.from.y)
        let len = hypot(d.x, d.y)
        return len > 0 ? CGPoint(x: d.x / len, y: d.y / len) : d
    }

    /// Signed angle (counterclockwise positive) turning from vector `a` to `b`.
    private static func signedAngle(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
    }

    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        var area: CGFloat = 0
        for i in points.indices {
            let j = (i + 1) % points.count
            area += points[i].x * points[j].y - points[j].x * points[i].y
        }
        return area / 2
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
