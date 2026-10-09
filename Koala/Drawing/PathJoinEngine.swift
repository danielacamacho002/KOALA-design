//
//  PathJoinEngine.swift
//  Koala
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
/// tolerance of each other, or two open lines lie perfectly on top of each other.
///
/// Fidelity: closed shapes fuse using their *true rendered contour* (dense
/// samples from `ShapeGeometry.renderPoints`) rather than a handful of anchor
/// points, so circles, ellipses, arcs, beziers and baked fillets keep their real
/// geometry through a join instead of collapsing into a few straight segments.
/// Open curves keep their Bézier handles; only native arcs are tessellated and
/// then compacted back to circular anchors.
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
        /// Contour indices that may weld. Set for dense circles, ellipses, and arcs
        /// so a curve can meet a cardinal without every rim sample becoming an anchor.
        var structural: [Int]? = nil
        /// Midpoints of a demoted circular cubic. Rendering expands these back into
        /// the sweep; dropping them on join flattens that arc to a chord.
        var smoothCornerIndices: Set<Int>? = nil
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
            if canChainOpenContours(usable, tolerance: tolerance) { return true }
            // Mirrored halves often overlap so a boundary lies on itself instead
            // of meeting at the endpoints. That stacked run is still one outline.
            return hasStackedLineOverlap(usable, tolerance: tolerance)
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
            if let fused = fuseStackedOpenLines(usable, tolerance: tolerance, base: base) {
                return fused
            }
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

        return fused.map { stroke(from: $0, base: base, rewritingPartialRuns: true) }
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
        var structural: [Int]? = nil
        switch stroke.shapeType {
        case .circle, .ellipse, .arc:
            let indices = weldIndices(
                matching: ShapeGeometry.handlePoints(for: stroke),
                in: points
            )
            if !indices.isEmpty { structural = indices }
        default:
            break
        }
        return Path(
            points: points,
            handles: Array(repeating: CurveHandle(), count: points.count),
            isClosed: stroke.isClosed || stroke.shapeType == .rectangle
                || stroke.shapeType == .circle || stroke.shapeType == .ellipse,
            isCurve: false,
            contour: contour,
            cutouts: cutouts,
            structural: structural
        )
    }

    /// Nearest contour sample for each defining anchor. Dense rims are not all
    /// weldable — only these anchors — so a lobe is not chained into the junction.
    private static func weldIndices(matching anchors: [CGPoint], in contour: [CGPoint]) -> [Int] {
        var used = Set<Int>()
        var indices: [Int] = []
        for anchor in anchors {
            var best: Int?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for index in contour.indices where !used.contains(index) {
                let gap = distance(contour[index], anchor)
                if gap < bestDistance {
                    bestDistance = gap
                    best = index
                }
            }
            if let best, bestDistance <= 4 {
                used.insert(best)
                indices.append(best)
            }
        }
        return indices
    }

    private static func stroke(
        from path: Path,
        base: VectorStroke,
        rewritingPartialRuns: Bool = true
    ) -> VectorStroke {
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
        result.smoothCornerIndices = path.isCurve ? nil : path.smoothCornerIndices
        result.isConstruction = false
        let keepCubics = ShapeGeometry.hasUserCubicHandles(result)
        return ShapeGeometry.withCompactedCircularAnchors(
            result,
            rewritingPartialRuns: rewritingPartialRuns,
            preservingBezierHandles: keepCubics
        )
    }

    // MARK: - Open contour join

    /// Walks lines/arcs/curves as chains of exclusive endpoint pairs and
    /// concatenates stored geometry. Curve handles stay attached so imported
    /// Béziers do not flatten into tessellated polylines that compaction then
    /// mistakes for circular arcs. Arcs still use the rendered outline so a
    /// lobe is not reduced to a few chorded anchors. Points are never moved.
    /// Returns every fused component plus leftover originals that did not join.
    private static func joinOpenContours(
        _ strokes: [VectorStroke],
        tolerance: CGFloat,
        base: VectorStroke
    ) -> [VectorStroke]? {
        let pairing = outlineEndpointPairing(strokes, tolerance: tolerance)
        guard pairing.pairOf.contains(where: { $0 >= 0 }) else { return nil }

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
            var merged: Path?
            var previousStroke = -1
            for step in ordered {
                var segment = joinablePath(for: strokes[step.stroke])
                if let current = merged {
                    let joint = joinGapLimit(
                        lengthA: previousStroke >= 0 ? lengths[previousStroke] : lengths[step.stroke],
                        lengthB: lengths[step.stroke],
                        tolerance: tolerance
                    )
                    // A closed curve or polygon keeps every edge, including the one
                    // that wraps from the last anchor to the first. Concatenating it
                    // as an open chain drops that cubic and the lobe collapses.
                    if segment.isClosed || current.isClosed {
                        if !segment.isClosed, !step.forward { segment = reverse(segment) }
                        let anchor = segment.isClosed
                            ? (step.forward ? segment.points[0] : segment.points[segment.points.count - 1])
                            : segment.points[0]
                        merged = splice(current, segment, at: anchor, tolerance: joint)
                    } else {
                        if !step.forward { segment = reverse(segment) }
                        merged = append(current, segment, tolerance: joint)
                    }
                } else {
                    if !segment.isClosed, !step.forward { segment = reverse(segment) }
                    merged = segment
                }
                previousStroke = step.stroke
            }
            guard var path = merged, path.points.count >= 2 else { return nil }
            path = closeJoinedPath(path, tolerance: tolerance)
            guard path.points.count >= (path.isClosed ? 3 : 2) else { return nil }
            path.cutouts = ordered.flatMap { strokes[$0.stroke].cutoutPoints }
            let pieces = ordered.map { strokes[$0.stroke] }
            return stroke(
                from: path,
                base: base,
                rewritingPartialRuns: shouldRewritePartialCircularRuns(pieces)
            )
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

    // MARK: - Stacked open lines

    /// Perpendicular budget for “these edges are the same line”. Join’s anchor
    /// tolerance is often half a grid cell, which would fuse nearby parallels.
    private static func stackedLineSlop(_ tolerance: CGFloat) -> CGFloat {
        min(max(tolerance, 0), 1.5)
    }

    /// True when two open polylines or curves have a straight run lying on the
    /// same line for a real span. A shared endpoint, a crossing, or a parallel
    /// line a grid cell away does not count.
    private static func hasStackedLineOverlap(_ strokes: [VectorStroke], tolerance: CGFloat) -> Bool {
        !stackedOverlaps(in: strokes, slop: stackedLineSlop(tolerance)).isEmpty
    }

    /// Drops a doubled interior seam and keeps a single copy of a doubled
    /// boundary, then traces what’s left. A mirrored pair whose edges sit on
    /// each other becomes one outline, closed when that outline loops.
    private static func fuseStackedOpenLines(
        _ strokes: [VectorStroke],
        tolerance: CGFloat,
        base: VectorStroke
    ) -> [VectorStroke]? {
        guard strokes.allSatisfy({ !$0.isClosed }) else { return nil }
        let slop = stackedLineSlop(tolerance)
        let overlaps = stackedOverlaps(in: strokes, slop: slop)
        guard !overlaps.isEmpty else { return nil }

        var involved = Set<Int>()
        for overlap in overlaps {
            involved.insert(overlap.ownerA)
            involved.insert(overlap.ownerB)
        }

        var atoms = strokes.enumerated().flatMap { index, stroke -> [LineAtom] in
            guard involved.contains(index) else { return [] }
            return lineAtoms(of: stroke, owner: index, slop: slop)
        }
        var cutsByAtom = Array(repeating: [CGPoint](), count: atoms.count)
        for overlap in overlaps {
            guard let atomA = atoms.firstIndex(where: { $0.owner == overlap.ownerA && $0.edge == overlap.edgeA }),
                  let atomB = atoms.firstIndex(where: { $0.owner == overlap.ownerB && $0.edge == overlap.edgeB })
            else { continue }
            cutsByAtom[atomA].append(contentsOf: [overlap.start, overlap.end])
            cutsByAtom[atomB].append(contentsOf: [overlap.start, overlap.end])
        }

        var split: [LineAtom] = []
        for (atom, cuts) in zip(atoms, cutsByAtom) {
            split.append(contentsOf: splitAtom(atom, cuts: cuts, slop: slop))
        }
        let kept = droppingStackedDuplicates(split, slop: slop)
        let welded = weldingEndpoints(kept, slop: slop)
        let chains = traceAtoms(welded)

        var closed: [VectorStroke] = []
        var open: [VectorStroke] = []
        for chain in chains {
            let stroke = stroke(from: chain, base: base)
            if stroke.isClosed {
                closed.append(stroke)
            } else {
                open.append(stroke)
            }
        }
        let untouched = strokes.enumerated().compactMap { index, stroke -> VectorStroke? in
            involved.contains(index) ? nil : stroke
        }
        open.append(contentsOf: untouched)
        if open.count >= 2, let chained = joinOpenContours(open, tolerance: tolerance, base: base) {
            return closed + chained
        }
        let combined = closed + open
        return combined.isEmpty ? nil : combined
    }

    private struct StackedOverlap {
        var ownerA: Int
        var edgeA: Int
        var ownerB: Int
        var edgeB: Int
        var start: CGPoint
        var end: CGPoint
    }

    private struct LineAtom {
        var from: CGPoint
        var to: CGPoint
        var outOffset: CGPoint
        var inOffset: CGPoint
        var curved: Bool
        var owner: Int
        var edge: Int
        /// Which side of this directed edge the rest of the stroke leaves toward.
        /// `0` when the edge is the whole stroke.
        var side: CGFloat
    }

    private static func stackedOverlaps(in strokes: [VectorStroke], slop: CGFloat) -> [StackedOverlap] {
        struct StraightEdge {
            var owner: Int
            var edge: Int
            var a: CGPoint
            var b: CGPoint
        }
        var edges: [StraightEdge] = []
        for (owner, stroke) in strokes.enumerated() where !stroke.isClosed {
            guard stroke.shapeType == .polyline || stroke.shapeType == .curve else { continue }
            let handles = curveHandles(of: stroke)
            let count = stroke.points.count
            guard count >= 2 else { continue }
            for edge in 0..<(count - 1) {
                if let handles, !isStraightSpan(handles, edge: edge, slop: slop) { continue }
                edges.append(StraightEdge(
                    owner: owner,
                    edge: edge,
                    a: stroke.points[edge],
                    b: stroke.points[edge + 1]
                ))
            }
        }

        var found: [StackedOverlap] = []
        for i in edges.indices {
            for j in (i + 1)..<edges.count {
                guard edges[i].owner != edges[j].owner else { continue }
                guard let span = collinearOverlap(edges[i].a, edges[i].b, edges[j].a, edges[j].b, slop: slop)
                else { continue }
                found.append(StackedOverlap(
                    ownerA: edges[i].owner,
                    edgeA: edges[i].edge,
                    ownerB: edges[j].owner,
                    edgeB: edges[j].edge,
                    start: span.start,
                    end: span.end
                ))
            }
        }
        return found
    }

    /// Overlap of two straight segments that lie on one line, longer than `slop`.
    private static func collinearOverlap(
        _ a0: CGPoint, _ a1: CGPoint,
        _ b0: CGPoint, _ b1: CGPoint,
        slop: CGFloat
    ) -> (start: CGPoint, end: CGPoint)? {
        let axis = CGPoint(x: a1.x - a0.x, y: a1.y - a0.y)
        let length = hypot(axis.x, axis.y)
        guard length > slop else { return nil }
        let dir = CGPoint(x: axis.x / length, y: axis.y / length)
        func perp(_ p: CGPoint) -> CGFloat {
            let dx = p.x - a0.x
            let dy = p.y - a0.y
            return abs(dx * dir.y - dy * dir.x)
        }
        guard perp(b0) <= slop, perp(b1) <= slop else { return nil }
        func proj(_ p: CGPoint) -> CGFloat {
            (p.x - a0.x) * dir.x + (p.y - a0.y) * dir.y
        }
        let start = max(0, min(proj(b0), proj(b1)))
        let end = min(length, max(proj(b0), proj(b1)))
        guard end - start > slop else { return nil }
        return (
            CGPoint(x: a0.x + dir.x * start, y: a0.y + dir.y * start),
            CGPoint(x: a0.x + dir.x * end, y: a0.y + dir.y * end)
        )
    }

    private static func curveHandles(of stroke: VectorStroke) -> [CurveHandle]? {
        guard stroke.shapeType == .curve,
              let handles = stroke.curveHandles,
              handles.count == stroke.points.count else { return nil }
        return handles
    }

    private static func isStraightSpan(_ handles: [CurveHandle], edge: Int, slop: CGFloat) -> Bool {
        guard handles.indices.contains(edge), handles.indices.contains(edge + 1) else { return false }
        return hypot(handles[edge].outOffset.x, handles[edge].outOffset.y) <= slop
            && hypot(handles[edge + 1].inOffset.x, handles[edge + 1].inOffset.y) <= slop
    }

    private static func lineAtoms(of stroke: VectorStroke, owner: Int, slop: CGFloat) -> [LineAtom] {
        let points = stroke.points
        guard points.count >= 2 else { return [] }
        let handles = curveHandles(of: stroke)
        var atoms: [LineAtom] = []
        for edge in 0..<(points.count - 1) {
            let outOffset = handles?[edge].outOffset ?? .zero
            let inOffset = handles?[edge + 1].inOffset ?? .zero
            let curved = handles != nil && !isStraightSpan(handles!, edge: edge, slop: slop)
            atoms.append(LineAtom(
                from: points[edge],
                to: points[edge + 1],
                outOffset: curved ? outOffset : .zero,
                inOffset: curved ? inOffset : .zero,
                curved: curved,
                owner: owner,
                edge: edge,
                side: departureSide(points, edge: edge, slop: slop)
            ))
        }
        return atoms
    }

    /// +1 when the stroke leaves this directed edge to its left, −1 to its right.
    private static func departureSide(_ points: [CGPoint], edge: Int, slop: CGFloat) -> CGFloat {
        guard points.indices.contains(edge + 1) else { return 0 }
        let a = points[edge]
        let b = points[edge + 1]
        let edgeX = b.x - a.x
        let edgeY = b.y - a.y
        let length = hypot(edgeX, edgeY)
        guard length > slop else { return 0 }
        if points.indices.contains(edge + 2) {
            let nextX = points[edge + 2].x - b.x
            let nextY = points[edge + 2].y - b.y
            let cross = edgeX * nextY - edgeY * nextX
            if abs(cross) > slop * length { return cross > 0 ? 1 : -1 }
        }
        if edge > 0 {
            let prevX = points[edge - 1].x - a.x
            let prevY = points[edge - 1].y - a.y
            let cross = edgeX * prevY - edgeY * prevX
            if abs(cross) > slop * length { return cross > 0 ? 1 : -1 }
        }
        return 0
    }

    private static func splitAtom(_ atom: LineAtom, cuts: [CGPoint], slop: CGFloat) -> [LineAtom] {
        guard !atom.curved, !cuts.isEmpty else { return [atom] }
        let axis = CGPoint(x: atom.to.x - atom.from.x, y: atom.to.y - atom.from.y)
        let lengthSquared = axis.x * axis.x + axis.y * axis.y
        guard lengthSquared > slop * slop else { return [atom] }
        func parameter(_ p: CGPoint) -> CGFloat {
            ((p.x - atom.from.x) * axis.x + (p.y - atom.from.y) * axis.y) / lengthSquared
        }
        var points = [atom.from, atom.to]
        for cut in cuts {
            let t = parameter(cut)
            guard t > 0.002, t < 0.998 else { continue }
            let projected = CGPoint(x: atom.from.x + t * axis.x, y: atom.from.y + t * axis.y)
            guard distance(projected, cut) <= slop else { continue }
            if points.contains(where: { distance($0, projected) <= slop }) { continue }
            points.append(projected)
        }
        points.sort { parameter($0) < parameter($1) }
        var pieces: [LineAtom] = []
        for index in 0..<(points.count - 1) where distance(points[index], points[index + 1]) > 0.05 {
            pieces.append(LineAtom(
                from: points[index],
                to: points[index + 1],
                outOffset: .zero,
                inOffset: .zero,
                curved: false,
                owner: atom.owner,
                edge: atom.edge,
                side: atom.side
            ))
        }
        return pieces.isEmpty ? [atom] : pieces
    }

    /// An interior seam (the two strokes leave toward opposite sides) is removed.
    /// A doubled boundary (both strokes leave toward the same side) keeps one copy.
    private static func droppingStackedDuplicates(_ atoms: [LineAtom], slop: CGFloat) -> [LineAtom] {
        var parent = Array(atoms.indices)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root { root = parent[root] }
            var node = index
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        func sameSegment(_ a: LineAtom, _ b: LineAtom) -> Bool {
            let forward = distance(a.from, b.from) <= slop && distance(a.to, b.to) <= slop
            let backward = distance(a.from, b.to) <= slop && distance(a.to, b.from) <= slop
            return forward || backward
        }
        for i in atoms.indices where !atoms[i].curved {
            for j in (i + 1)..<atoms.count where !atoms[j].curved && atoms[i].owner != atoms[j].owner {
                if sameSegment(atoms[i], atoms[j]) {
                    parent[find(j)] = find(i)
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for index in atoms.indices where !atoms[index].curved {
            groups[find(index), default: []].append(index)
        }
        var drop = Set<Int>()
        for members in groups.values where members.count >= 2 {
            let first = atoms[members[0]]
            let second = atoms[members[1]]
            let aligned = (first.to.x - first.from.x) * (second.to.x - second.from.x)
                + (first.to.y - first.from.y) * (second.to.y - second.from.y) >= 0
            let secondSide = aligned ? second.side : -second.side
            let opposite = first.side * secondSide < 0
                && abs(first.side) > 0.5
                && abs(secondSide) > 0.5
            if opposite {
                drop.formUnion(members)
            } else {
                drop.formUnion(members.dropFirst())
            }
        }
        return atoms.enumerated().compactMap { index, atom in
            drop.contains(index) ? nil : atom
        }
    }

    private static func weldingEndpoints(_ atoms: [LineAtom], slop: CGFloat) -> [LineAtom] {
        var canon: [CGPoint] = []
        func snap(_ point: CGPoint) -> CGPoint {
            if let existing = canon.first(where: { distance($0, point) <= slop }) {
                return existing
            }
            canon.append(point)
            return point
        }
        return atoms.map { atom in
            var atom = atom
            atom.from = snap(atom.from)
            atom.to = snap(atom.to)
            return atom
        }.filter { distance($0.from, $0.to) > 0.05 }
    }

    private static func traceAtoms(_ atoms: [LineAtom]) -> [Path] {
        guard !atoms.isEmpty else { return [] }
        func key(_ point: CGPoint) -> String {
            let scale: CGFloat = 1000
            let x = (point.x * scale).rounded() / scale
            let y = (point.y * scale).rounded() / scale
            return "\(x)|\(y)"
        }
        struct Outgoing {
            var atom: Int
            var forward: Bool
        }
        var at: [String: [Outgoing]] = [:]
        for (index, atom) in atoms.enumerated() {
            at[key(atom.from), default: []].append(Outgoing(atom: index, forward: true))
            at[key(atom.to), default: []].append(Outgoing(atom: index, forward: false))
        }
        var used = Array(repeating: false, count: atoms.count)

        func unused(from pointKey: String, except atom: Int) -> [Outgoing] {
            (at[pointKey] ?? []).filter { !used[$0.atom] && $0.atom != atom }
        }

        func walk(start: Outgoing) -> Path? {
            var points: [CGPoint] = []
            var handles: [CurveHandle] = []
            var curved = false
            var current = start
            var guardCount = 0
            let origin = start.forward ? atoms[start.atom].from : atoms[start.atom].to
            let startKey = key(origin)
            while guardCount <= atoms.count {
                guardCount += 1
                let atom = atoms[current.atom]
                used[current.atom] = true
                curved = curved || atom.curved
                let from = current.forward ? atom.from : atom.to
                let to = current.forward ? atom.to : atom.from
                let outOffset = current.forward ? atom.outOffset : atom.inOffset
                let inOffset = current.forward ? atom.inOffset : atom.outOffset
                if points.isEmpty {
                    points.append(from)
                    handles.append(CurveHandle(inOffset: .zero, outOffset: outOffset))
                } else {
                    handles[handles.count - 1].outOffset = outOffset
                }
                let options = unused(from: key(to), except: current.atom)
                let arrivedHome = key(to) == startKey && points.count >= 2
                if options.isEmpty {
                    if arrivedHome, points.count >= 3 {
                        handles[0].inOffset = inOffset
                        let curve = curved && handles.contains { handle in
                            handle.inOffset != .zero || handle.outOffset != .zero
                        }
                        return Path(
                            points: points,
                            handles: handles,
                            isClosed: true,
                            isCurve: curve,
                            contour: points
                        )
                    }
                    points.append(to)
                    handles.append(CurveHandle(inOffset: inOffset, outOffset: .zero))
                    break
                }
                points.append(to)
                handles.append(CurveHandle(inOffset: inOffset, outOffset: .zero))
                let incoming = CGPoint(x: to.x - from.x, y: to.y - from.y)
                let next = options.min { lhs, rhs in
                    signedTurn(incoming, destinationVector(lhs)) < signedTurn(incoming, destinationVector(rhs))
                } ?? options[0]
                current = next
            }
            guard points.count >= 2, handles.count == points.count else { return nil }
            let curve = curved && handles.contains { $0.inOffset != .zero || $0.outOffset != .zero }
            return Path(points: points, handles: handles, isClosed: false, isCurve: curve, contour: points)
        }

        func destinationVector(_ outgoing: Outgoing) -> CGPoint {
            let atom = atoms[outgoing.atom]
            if outgoing.forward {
                return CGPoint(x: atom.to.x - atom.from.x, y: atom.to.y - atom.from.y)
            }
            return CGPoint(x: atom.from.x - atom.to.x, y: atom.from.y - atom.to.y)
        }
        func signedTurn(_ incoming: CGPoint, _ outgoing: CGPoint) -> CGFloat {
            atan2(
                incoming.x * outgoing.y - incoming.y * outgoing.x,
                incoming.x * outgoing.x + incoming.y * outgoing.y
            )
        }

        var chains: [Path] = []
        let degreeOne = at.filter { $0.value.count == 1 }.map(\.key)
        for pointKey in degreeOne {
            guard let start = (at[pointKey] ?? []).first(where: { !used[$0.atom] }) else { continue }
            if let chain = walk(start: start) { chains.append(chain) }
        }
        for index in atoms.indices where !used[index] {
            if let chain = walk(start: Outgoing(atom: index, forward: true)) {
                chains.append(chain)
            }
        }
        return chains
    }

    private static func stroke(from chain: Path, base: VectorStroke) -> VectorStroke {
        stroke(from: chain, base: base, rewritingPartialRuns: false)
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

    /// Polylines and curves join at drawn anchors so Bézier handles can be
    /// carried through. Arcs use the rendered outline so a lobe is not reduced
    /// to a handful of chorded handles.
    private static func joinContour(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .arc:
            return ShapeGeometry.renderPoints(for: stroke)
        default:
            return stroke.points
        }
    }

    private static func joinablePath(for stroke: VectorStroke) -> Path {
        switch stroke.shapeType {
        case .curve:
            let handles = stroke.curveHandles?.count == stroke.points.count
                ? stroke.curveHandles!
                : Array(repeating: CurveHandle(), count: stroke.points.count)
            return Path(
                points: stroke.points,
                handles: handles,
                isClosed: stroke.isClosed,
                isCurve: true,
                contour: ShapeGeometry.renderPoints(for: stroke),
                cutouts: stroke.cutoutPoints
            )
        case .arc:
            let contour = ShapeGeometry.renderPoints(for: stroke)
            return Path(
                points: contour,
                handles: Array(repeating: CurveHandle(), count: contour.count),
                isClosed: false,
                isCurve: false,
                contour: contour,
                cutouts: stroke.cutoutPoints
            )
        default:
            return Path(
                points: stroke.points,
                handles: Array(repeating: CurveHandle(), count: stroke.points.count),
                isClosed: stroke.isClosed,
                isCurve: false,
                contour: stroke.points,
                cutouts: stroke.cutoutPoints,
                smoothCornerIndices: stroke.smoothCornerIndices
            )
        }
    }

    private static func shouldRewritePartialCircularRuns(_ strokes: [VectorStroke]) -> Bool {
        strokes.contains { stroke in
            switch stroke.shapeType {
            case .arc, .circle, .ellipse:
                return true
            default:
                return false
            }
        }
    }

    private static func closeJoinedPath(_ path: Path, tolerance: CGFloat) -> Path {
        var path = path
        guard shouldCloseJoinedContour(path.points, tolerance: tolerance) else { return path }
        if path.isCurve, let incoming = path.handles.last, !path.handles.isEmpty {
            path.handles[0].inOffset = incoming.inOffset
        }
        let removed = path.points.count - 1
        path.points.removeLast()
        if !path.handles.isEmpty { path.handles.removeLast() }
        if var smooth = path.smoothCornerIndices {
            smooth.remove(removed)
            path.smoothCornerIndices = smooth.isEmpty ? nil : smooth
        }
        path.isClosed = true
        path.contour = path.points
        return path
    }

    /// Smooth midpoints ride along when anchors are concatenated or reversed.
    private static func shiftedSmoothCorners(
        _ indices: Set<Int>?,
        by offset: Int,
        dropping indexToDrop: Int? = nil
    ) -> Set<Int>? {
        guard let indices else { return nil }
        let shifted = Set(indices.compactMap { index -> Int? in
            if index == indexToDrop { return nil }
            let adjusted = indexToDrop.map { index > $0 ? index - 1 : index } ?? index
            return adjusted + offset
        })
        return shifted.isEmpty ? nil : shifted
    }

    private static func unionSmoothCorners(_ head: Set<Int>?, _ tail: Set<Int>?) -> Set<Int>? {
        let merged = (head ?? []).union(tail ?? [])
        return merged.isEmpty ? nil : merged
    }

    /// Anchors after `hostIndex` move forward when a spur is inserted there.
    private static func smoothCornersInserting(
        _ indices: Set<Int>?,
        at hostIndex: Int,
        count inserted: Int
    ) -> Set<Int>? {
        guard let indices, inserted > 0 else { return indices }
        let shifted = Set(indices.map { $0 > hostIndex ? $0 + inserted : $0 })
        return shifted.isEmpty ? nil : shifted
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
        if let structural = path.structural { return structural }
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
    /// as a loop that returns to the join point. Open guests chained at the end of
    /// an open host extend it; otherwise they double back so a closed curve keeps
    /// every cubic. The host tangent that used to leave the weld is parked on the
    /// returning anchor — leaving it on the junction bends the next host edge and
    /// flattens the cubic that followed.
    private static func splice(
        _ host: Path,
        _ guest: Path,
        at shared: CGPoint,
        tolerance: CGFloat,
        flippingStart: Bool = true
    ) -> Path {
        guard let hostIndex = host.points.firstIndex(where: { distance($0, shared) <= tolerance }),
              let guestIndex = guest.points.firstIndex(where: { distance($0, shared) <= tolerance })
        else {
            return append(host, guest, tolerance: tolerance)
        }

        let hostAtStart = !host.isClosed && hostIndex == 0
        let hostAtEnd = !host.isClosed && hostIndex == host.points.count - 1
        let guestAtStart = !guest.isClosed && guestIndex == 0
        let guestAtEnd = !guest.isClosed && guestIndex == guest.points.count - 1

        if hostAtEnd, guestAtStart || guestAtEnd {
            var oriented = guest
            if guestAtEnd { oriented = reverse(oriented) }
            return append(host, oriented, tolerance: tolerance)
        }
        if hostAtStart, guestAtStart || guestAtEnd {
            var oriented = guest
            if guestAtStart { oriented = reverse(oriented) }
            return append(oriented, host, tolerance: tolerance)
        }
        if flippingStart, hostAtStart, guest.isClosed {
            return reverse(splice(
                reverse(host), guest, at: shared, tolerance: tolerance, flippingStart: false
            ))
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
        let count = guest.points.count
        let last = count - 1

        if guest.isClosed {
            // Walk the whole loop starting just after the shared anchor and ending
            // back on it, so the loop closes before continuing along the host.
            junctionOut = guestHandles[guestIndex].outOffset
            let order = Array((guestIndex + 1)..<count) + Array(0...guestIndex)
            for i in order {
                walkPoints.append(guest.points[i])
                walkHandles.append(guestHandles[i])
            }
        } else if guestIndex == 0, last >= 1 {
            junctionOut = guestHandles[0].outOffset
            for i in 1..<last {
                walkPoints.append(guest.points[i])
                walkHandles.append(guestHandles[i])
            }
            var tip = guestHandles[last]
            tip.outOffset = tip.inOffset
            walkPoints.append(guest.points[last])
            walkHandles.append(tip)
            for i in stride(from: last - 1, through: 0, by: -1) {
                walkPoints.append(guest.points[i])
                walkHandles.append(flip(guestHandles[i]))
            }
        } else if guestIndex == last, last >= 1 {
            junctionOut = guestHandles[last].inOffset
            for i in stride(from: last - 1, through: 1, by: -1) {
                walkPoints.append(guest.points[i])
                walkHandles.append(flip(guestHandles[i]))
            }
            var tip = flip(guestHandles[0])
            tip.outOffset = tip.inOffset
            walkPoints.append(guest.points[0])
            walkHandles.append(tip)
            for i in 1...last {
                walkPoints.append(guest.points[i])
                walkHandles.append(guestHandles[i])
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
            for i in (guestIndex + 1)..<count {
                walkPoints.append(guest.points[i])
                walkHandles.append(guestHandles[i])
            }
            walkPoints.append(shared)
            walkHandles.append(CurveHandle())
        }

        guard !walkPoints.isEmpty else { return host }

        var points = host.points
        var handles = host.handles.count == host.points.count
            ? host.handles
            : Array(repeating: CurveHandle(), count: host.points.count)
        let originalOut = handles[hostIndex].outOffset
        walkHandles[walkHandles.count - 1].outOffset = originalOut
        handles[hostIndex].outOffset = junctionOut
        points.insert(contentsOf: walkPoints, at: hostIndex + 1)
        handles.insert(contentsOf: walkHandles, at: hostIndex + 1)

        return Path(
            points: points,
            handles: handles,
            isClosed: host.isClosed,
            isCurve: host.isCurve || guest.isCurve,
            contour: points,
            structural: host.structural,
            smoothCornerIndices: smoothCornersInserting(
                host.smoothCornerIndices,
                at: hostIndex,
                count: walkPoints.count
            )
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
        let last = max(0, path.points.count - 1)
        return Path(
            points: path.points.reversed(),
            handles: path.handles.reversed().map {
                CurveHandle(inOffset: $0.outOffset, outOffset: $0.inOffset)
            },
            isClosed: path.isClosed,
            isCurve: path.isCurve,
            contour: path.contour.reversed(),
            cutouts: path.cutouts,
            structural: path.structural.map { $0.map { last - $0 } },
            smoothCornerIndices: path.smoothCornerIndices.map { indices in
                Set(indices.map { last - $0 })
            }
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
                contour: points,
                smoothCornerIndices: unionSmoothCorners(
                    head.smoothCornerIndices,
                    shiftedSmoothCorners(tail.smoothCornerIndices, by: head.points.count)
                )
            )
        }
        var merged = head
        merged.isClosed = false
        merged.isCurve = head.isCurve || tail.isCurve
        let droppingFirst = distance(last, first) <= tolerance
        if droppingFirst {
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
        merged.smoothCornerIndices = unionSmoothCorners(
            head.smoothCornerIndices,
            shiftedSmoothCorners(
                tail.smoothCornerIndices,
                by: head.points.count,
                dropping: droppingFirst ? 0 : nil
            )
        )
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
