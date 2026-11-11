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
nonisolated enum PathJoinEngine {
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
        let usable = strokes.map(withoutFillets).filter { ShapeGeometry.handlePoints(for: $0).count >= 2 }
        guard usable.count >= 2 else { return false }
        let groups = containedGroups(usable)
        if groups.count > 1 {
            // Inner curves that meet each other still join on their own.
            if groups.contains(where: { $0.count >= 2 && canJoin($0, tolerance: tolerance) }) {
                return true
            }
            // A neckline or lens that only meets the outline is still a weld.
            // Containment alone is not — that used to boolean-union the inner shape.
            return sharesAnchorAcross(groups, tolerance: tolerance)
        }
        if usable.allSatisfy(isOutlineChainable) {
            if canChainOpenContours(usable, tolerance: tolerance) { return true }
            // Mirrored halves often overlap so a boundary lies on itself instead
            // of meeting at the endpoints. That stacked run is still one outline.
            if hasStackedLineOverlap(usable, tolerance: tolerance) { return true }
            // A line that ends on an edge, not on a corner, is still one outline.
            if usable.allSatisfy(isStraightPolyline),
               uniteTouchingOutlines(usable, tolerance: tolerance, base: usable[0]) != nil {
                return true
            }
            // A spur that leaves the outline can still meet a corner or mid-edge
            // anchor rather than the other path's endpoints.
            return hasTouchingAnchors(usable, tolerance: tolerance)
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
        // Fillets are a modifier over sharp corners. Join the sharp outlines, then put
        // each radius back on the corner that is still there, so Join does not round
        // or un-round anything the user did not touch.
        let fillets = strokes.flatMap(filletedCorners)
        let sharp = strokes.map(withoutFillets)
        guard let joined = fuse(sharp, tolerance: tolerance) else { return nil }
        return joined.map { output in
            if let index = sharp.firstIndex(where: { $0.id == output.id }),
               sharp[index].points == output.points,
               sharp[index].cutoutPoints == output.cutoutPoints {
                return strokes[index]
            }
            return restoringFillets(fillets, on: output)
        }
    }

    private struct FilletedCorner {
        var point: CGPoint
        var radius: CGFloat
    }

    private static func filletedCorners(of stroke: VectorStroke) -> [FilletedCorner] {
        stroke.resolvedFilletCornerRadii().compactMap { index, radius in
            guard stroke.points.indices.contains(index) else { return nil }
            return FilletedCorner(point: stroke.points[index], radius: radius)
        }
    }

    /// Sharp-cornered copy. A rectangle is four corner points, so it joins as a
    /// plain polygon instead of falling through to the dense-contour fuse.
    private static func withoutFillets(_ stroke: VectorStroke) -> VectorStroke {
        var sharp = stroke
        sharp.cornerRadius = 0
        sharp.cornerRadiiByIndex = nil
        if sharp.shapeType == .rectangle, sharp.points.count == 4 {
            sharp.shapeType = .polyline
        }
        return sharp
    }

    private static func restoringFillets(_ fillets: [FilletedCorner], on stroke: VectorStroke) -> VectorStroke {
        guard !fillets.isEmpty, stroke.shapeType == .polyline else { return stroke }
        let corners = stroke.filletCornerIndices()
        let smooth = stroke.smoothCornerIndices ?? []
        var restored = stroke
        var radii: [Int: CGFloat] = [:]
        for fillet in fillets {
            guard let index = corners.first(where: {
                !smooth.contains($0) && radii[$0] == nil && distance(stroke.points[$0], fillet.point) <= 0.5
            }) else { continue }
            let radius = FilletPathBuilder.clampedFilletRadius(
                for: restored,
                cornerIndex: index,
                requested: fillet.radius
            )
            guard radius > 0 else { continue }
            radii[index] = radius
            restored.cornerRadiiByIndex = radii
        }
        return restored
    }

    private static func fuse(_ strokes: [VectorStroke], tolerance: CGFloat) -> [VectorStroke]? {
        let usable = strokes.filter { ShapeGeometry.handlePoints(for: $0).count >= 2 }
        guard usable.count >= 2, let base = usable.first else { return nil }

        // Curves that meet each other inside an outline join to each other and
        // stay out of that outline. A curve that only shares an anchor with the
        // outline is welded below; an open one replaces the boundary between its
        // ends once, instead of being walked out and back.
        let groups = containedGroups(usable)
        if groups.count > 1 {
            let joinsWithin = groups.contains { $0.count >= 2 && canJoin($0, tolerance: tolerance) }
            if joinsWithin {
                var output: [VectorStroke] = []
                var didJoin = false
                for group in groups {
                    if group.count < 2 {
                        output.append(contentsOf: group)
                        continue
                    }
                    if let joined = fuse(group, tolerance: tolerance) {
                        output.append(contentsOf: joined)
                        didJoin = true
                    } else {
                        output.append(contentsOf: group)
                    }
                }
                return didJoin ? output : nil
            }
            guard sharesAnchorAcross(groups, tolerance: tolerance) else { return nil }
            if !usable.allSatisfy(isOutlineChainable) {
                guard hasTouchingAnchors(usable, tolerance: tolerance) else { return nil }
                return joinAtSharedAnchors(usable, tolerance: tolerance, base: base)
            }
        }

        // Lines, arcs, and curves — including ones that were auto-marked closed
        // (a star point becomes a triangle) — join by chaining outlines at
        // endpoints. Boolean-union / centroid-weld of those pieces collapses
        // stars and hearts into a blob.
        if usable.allSatisfy(isOutlineChainable) {
            if let fused = fuseStackedOpenLines(usable, tolerance: tolerance, base: base) {
                return fused
            }
            // Closed triangles (and open sides that land on them) share an edge.
            // Chaining those at one corner leaves the other region open, so the
            // seam never meets the base and the added area does not fill.
            if usable.allSatisfy(isStraightPolyline),
               let united = uniteTouchingOutlines(usable, tolerance: tolerance, base: base) {
                return united
            }
            if let chained = joinOpenContours(usable, tolerance: tolerance, base: base) {
                return chained
            }
            // Endpoints didn't pair, but an anchor on one stroke sits on an anchor
            // of another (a line ending on a corner of the shape around it).
            // Stitch stored anchors only — boolean-union would replace cubics
            // with the rendered contour and collapse the curve.
            guard hasTouchingAnchors(usable, tolerance: tolerance) else { return nil }
            return joinAtSharedAnchors(usable, tolerance: tolerance, base: base)
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

    /// Splits strokes that sit inside another selected closed stroke out of that
    /// container so they can join to each other without being unioned into it.
    private static func containedGroups(_ strokes: [VectorStroke]) -> [[VectorStroke]] {
        guard strokes.count >= 2 else { return [strokes] }
        let rendered = strokes.map { ShapeGeometry.renderPoints(for: $0) }
        var contained = Set<Int>()
        for index in strokes.indices {
            for container in strokes.indices where container != index && strokes[container].isClosed {
                guard rendered[container].count >= 3 else { continue }
                if isStrictlyContained(rendered[index], in: rendered[container]) {
                    contained.insert(index)
                    break
                }
            }
        }
        guard !contained.isEmpty else { return [strokes] }
        let inside = strokes.indices.filter { contained.contains($0) }.map { strokes[$0] }
        let outside = strokes.indices.filter { !contained.contains($0) }.map { strokes[$0] }
        return [outside, inside].filter { !$0.isEmpty }
    }

    /// True when every sample of `inner` is inside or on `outer`, and at least
    /// one sample is strictly inside. A spur that leaves the outline is not contained.
    private static func isStrictlyContained(_ inner: [CGPoint], in outer: [CGPoint]) -> Bool {
        guard outer.count >= 3, inner.count >= 2 else { return false }
        let snap: CGFloat = 2
        var sawInside = false
        for point in inner {
            if strictlyInsidePolygon(point, outer, snap: snap) || pointInsidePolygon(point, outer) {
                sawInside = true
                continue
            }
            let onBoundary = outer.indices.contains { index in
                let start = outer[index]
                let end = outer[(index + 1) % outer.count]
                return distance(point, start) <= snap || pointOnSegment(point, start, end, snap: snap)
            }
            if !onBoundary { return false }
        }
        return sawInside
    }

    /// True when a stroke in one containment group shares an anchor with a
    /// stroke in another. That is a real weld (a neckline ending on the
    /// outline), not merely one shape sitting inside the other.
    private static func sharesAnchorAcross(
        _ groups: [[VectorStroke]],
        tolerance: CGFloat
    ) -> Bool {
        for i in groups.indices {
            for j in (i + 1)..<groups.count {
                for stroke in groups[i] {
                    for other in groups[j] where hasTouchingAnchors([stroke, other], tolerance: tolerance) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func isOutlineChainable(_ stroke: VectorStroke) -> Bool {
        switch stroke.shapeType {
        case .polyline, .arc, .curve:
            return true
        default:
            return false
        }
    }

    /// Straight anchors only. Curves and arcs stay on the chain path so a cubic
    /// is not rewritten as the union of its chords.
    private static func isStraightPolyline(_ stroke: VectorStroke) -> Bool {
        guard stroke.shapeType == .polyline else { return false }
        if let smooth = stroke.smoothCornerIndices, !smooth.isEmpty { return false }
        if let handles = stroke.curveHandles {
            for handle in handles {
                if hypot(handle.inOffset.x, handle.inOffset.y) > 0.01 { return false }
                if hypot(handle.outOffset.x, handle.outOffset.y) > 0.01 { return false }
            }
        }
        return stroke.points.count >= 2
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
        if path.isCurve, let smooth = path.smoothCornerIndices, !smooth.isEmpty {
            result.curveHandles = ShapeGeometry.curveHandlesBakingSmoothCorners(
                points: path.points,
                handles: path.handles,
                closed: path.isClosed,
                smooth: smooth
            )
        } else {
            result.curveHandles = path.isCurve ? path.handles : nil
        }
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

    /// Welds strokes that meet at a shared anchor which is not both paths'
    /// endpoints. Uses the same splice as endpoint chaining so Bézier handles
    /// stay attached. A closed curve inside another shape is left alone unless
    /// an anchor actually touches — containment is not a union.
    private static func joinAtSharedAnchors(
        _ strokes: [VectorStroke],
        tolerance: CGFloat,
        base: VectorStroke
    ) -> [VectorStroke]? {
        var paths = strokes.map { joinablePath(for: $0) }
        for index in paths.indices {
            paths[index].structural = Array(paths[index].points.indices)
        }
        let components = connectedComponents(paths, tolerance: tolerance, includingOverlap: false)
        guard components.contains(where: { $0.count >= 2 }) else { return nil }

        let rewrite = shouldRewritePartialCircularRuns(strokes)
        var result: [VectorStroke] = []
        var used = Array(repeating: false, count: paths.count)
        func takeIndex(matching path: Path) -> Int? {
            for index in paths.indices where !used[index]
                && paths[index].points == path.points
                && paths[index].isClosed == path.isClosed {
                used[index] = true
                return index
            }
            return nil
        }
        for component in components {
            let indices = component.compactMap { takeIndex(matching: $0) }
            if component.count < 2 {
                if let index = indices.first {
                    result.append(strokes[index])
                }
                continue
            }
            let stitched = stitchPaths(component, tolerance: tolerance)
            result.append(stroke(from: stitched, base: base, rewritingPartialRuns: rewrite))
        }
        for index in strokes.indices where !used[index] {
            result.append(strokes[index])
        }
        return result.isEmpty ? nil : result
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
        guard stroke.shapeType == .curve else { return nil }
        if let handles = stroke.curveHandles, handles.count == stroke.points.count {
            return handles
        }
        return ShapeGeometry.defaultCurveHandles(anchors: stroke.points, closed: stroke.isClosed)
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
            // A curve without stored handles renders as a spline through its
            // anchors. Zero handles would join it as straight edges (a diamond).
            let handles = stroke.curveHandles?.count == stroke.points.count
                ? stroke.curveHandles!
                : ShapeGeometry.defaultCurveHandles(anchors: stroke.points, closed: stroke.isClosed)
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

    /// Baked fillet midpoints of a spliced guest, shifted to where the walk
    /// inserted them. Without this the inner curve falls back to straight edges.
    private static func remappedSmoothCorners(
        _ indices: Set<Int>?,
        sources: [Int?],
        insertAt: Int
    ) -> Set<Int>? {
        guard let indices else { return nil }
        var mapped = Set<Int>()
        for (offset, source) in sources.enumerated() {
            if let source, indices.contains(source) {
                mapped.insert(insertAt + offset)
            }
        }
        return mapped.isEmpty ? nil : mapped
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

    /// Groups paths that share at least one welded point. Overlap links closed
    /// contours that contain each other; anchor-only joins turn that off so a
    /// curve inside a shape is not boolean-unioned into the outline.
    private static func connectedComponents(
        _ paths: [Path],
        tolerance: CGFloat,
        includingOverlap: Bool = true
    ) -> [[Path]] {
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
            || (includingOverlap && pathsOverlap(paths[i], paths[j])) {
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
        host.cutouts = paths.flatMap(\.cutouts)
        return host
    }

    private static func sharedPoint(_ a: Path, _ b: Path, tolerance: CGFloat) -> CGPoint? {
        for p in structuralPoints(a) {
            for q in structuralPoints(b) where distance(p, q) <= tolerance { return p }
        }
        return nil
    }

    /// Replaces the host boundary between an open guest's endpoints with that
    /// guest, once. The boundary replaced is the one the curve actually bows
    /// toward, so a neckline takes the place of the edge it sits on.
    private static func replacingHostSpan(
        _ host: Path,
        with guest: Path,
        tolerance: CGFloat
    ) -> Path? {
        // A straight chord is a divider: replacing the shorter side with it
        // deletes the rest of the outline. Only a curve bows toward one edge.
        guard host.isClosed, !guest.isClosed,
              guest.points.count >= 2, host.points.count >= 3,
              guest.isCurve || guest.smoothCornerIndices?.isEmpty == false
        else { return nil }

        var normalizedGuest = guest
        normalizedGuest.handles = guest.handles.count == guest.points.count
            ? guest.handles
            : Array(repeating: CurveHandle(), count: guest.points.count)

        let guestEnd = normalizedGuest.points[normalizedGuest.points.count - 1]
        guard let startOnHost = host.points.firstIndex(where: {
            distance($0, normalizedGuest.points[0]) <= tolerance
        }) else { return nil }
        guard let endOnHost = host.points.indices.first(where: { index in
            index != startOnHost && distance(host.points[index], guestEnd) <= tolerance
        }), startOnHost != endOnHost else { return nil }

        let count = host.points.count
        let forward = forwardSpan(from: startOnHost, to: endOnHost, count: count)
        let backward = forwardSpan(from: endOnHost, to: startOnHost, count: count)
        let samples = cubicMidpoints(normalizedGuest)
        let forwardDistance = averageDistance(of: samples, toSpan: forward, points: host.points)
        let backwardDistance = averageDistance(of: samples, toSpan: backward, points: host.points)

        let replaceForward: Bool
        if abs(forwardDistance - backwardDistance) > 1 {
            replaceForward = forwardDistance < backwardDistance
        } else {
            let forwardLength = spanLength(forward, points: host.points)
            let backwardLength = spanLength(backward, points: host.points)
            if abs(forwardLength - backwardLength) > 1 {
                replaceForward = forwardLength < backwardLength
            } else {
                replaceForward = forward.count <= backward.count
            }
        }

        let fromIndex = replaceForward ? startOnHost : endOnHost
        let toIndex = replaceForward ? endOnHost : startOnHost
        var oriented = replaceForward ? normalizedGuest : reverse(normalizedGuest)
        oriented.points[0] = host.points[fromIndex]
        oriented.points[oriented.points.count - 1] = host.points[toIndex]

        let hostHandles = host.handles.count == host.points.count
            ? host.handles
            : Array(repeating: CurveHandle(), count: host.points.count)
        if !oriented.handles.isEmpty {
            oriented.handles[0].inOffset = hostHandles[fromIndex].inOffset
            oriented.handles[oriented.handles.count - 1].outOffset = hostHandles[toIndex].outOffset
        }

        var points = oriented.points
        var handles = oriented.handles
        var keptHost: [(hostIndex: Int, resultIndex: Int)] = [
            (fromIndex, 0),
            (toIndex, oriented.points.count - 1)
        ]
        var index = (toIndex + 1) % count
        var steps = 0
        while index != fromIndex && steps <= count {
            keptHost.append((index, points.count))
            points.append(host.points[index])
            handles.append(hostHandles[index])
            index = (index + 1) % count
            steps += 1
        }
        guard points.count >= 3, handles.count == points.count else { return nil }

        var smooth = oriented.smoothCornerIndices ?? []
        if let hostSmooth = host.smoothCornerIndices {
            for (hostIndex, resultIndex) in keptHost where hostSmooth.contains(hostIndex) {
                smooth.insert(resultIndex)
            }
        }

        return Path(
            points: points,
            handles: handles,
            isClosed: true,
            isCurve: host.isCurve || oriented.isCurve,
            contour: points,
            cutouts: host.cutouts + oriented.cutouts,
            structural: remappedSpanStructural(
                host: host,
                oriented: oriented,
                keptHost: keptHost,
                resultCount: points.count
            ),
            smoothCornerIndices: smooth.isEmpty ? nil : smooth
        )
    }

    private static func remappedSpanStructural(
        host: Path,
        oriented: Path,
        keptHost: [(hostIndex: Int, resultIndex: Int)],
        resultCount: Int
    ) -> [Int]? {
        let hostFullyStructural = host.structural.map { $0.count == host.points.count }
            ?? (host.points.count <= 8)
        if hostFullyStructural {
            return Array(0..<resultCount)
        }
        guard let hostStructural = host.structural else { return nil }
        var mapped = Set(oriented.structural ?? Array(oriented.points.indices))
        let hostSet = Set(hostStructural)
        for (hostIndex, resultIndex) in keptHost where hostSet.contains(hostIndex) {
            mapped.insert(resultIndex)
        }
        return mapped.sorted()
    }

    private static func forwardSpan(from start: Int, to end: Int, count: Int) -> [Int] {
        var indices = [start]
        var index = start
        var steps = 0
        while index != end && steps <= count {
            index = (index + 1) % count
            indices.append(index)
            steps += 1
        }
        return indices
    }

    private static func spanLength(_ indices: [Int], points: [CGPoint]) -> CGFloat {
        guard indices.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for index in 0..<(indices.count - 1) {
            length += distance(points[indices[index]], points[indices[index + 1]])
        }
        return length
    }

    private static func cubicMidpoints(_ path: Path) -> [CGPoint] {
        guard path.points.count >= 2 else { return path.points }
        let handles = path.handles.count == path.points.count
            ? path.handles
            : Array(repeating: CurveHandle(), count: path.points.count)
        var samples: [CGPoint] = []
        for edge in 0..<(path.points.count - 1) {
            let start = path.points[edge]
            let end = path.points[edge + 1]
            let c1 = CGPoint(
                x: start.x + handles[edge].outOffset.x,
                y: start.y + handles[edge].outOffset.y
            )
            let c2 = CGPoint(
                x: end.x + handles[edge + 1].inOffset.x,
                y: end.y + handles[edge + 1].inOffset.y
            )
            let t: CGFloat = 0.5
            let u = 1 - t
            samples.append(CGPoint(
                x: u * u * u * start.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                y: u * u * u * start.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y
            ))
        }
        return samples
    }

    private static func averageDistance(
        of samples: [CGPoint],
        toSpan indices: [Int],
        points: [CGPoint]
    ) -> CGFloat {
        guard !samples.isEmpty, indices.count >= 2 else { return .greatestFiniteMagnitude }
        let total = samples.reduce(CGFloat(0)) { partial, sample in
            var best = CGFloat.greatestFiniteMagnitude
            for index in 0..<(indices.count - 1) {
                best = min(
                    best,
                    distanceToSegment(sample, points[indices[index]], points[indices[index + 1]])
                )
            }
            return partial + best
        }
        return total / CGFloat(samples.count)
    }

    private static func distanceToSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        if lengthSquared < 1e-9 { return distance(point, a) }
        let t = max(0, min(1, ((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / lengthSquared))
        return distance(point, CGPoint(x: a.x + t * ab.x, y: a.y + t * ab.y))
    }

    /// Inserts `guest` into `host` at a shared anchor. Closed guests are walked
    /// as a loop that returns to the join point. Open guests chained at the end of
    /// an open host extend it; an open guest with both ends on a closed host
    /// replaces that span once. Anything else double-backs so a spur keeps every
    /// cubic. The host tangent that used to leave the weld is parked on the
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

        // An open curve whose ends both lie on a closed outline replaces the
        // boundary between those ends once. Doubling back traces the cubic in
        // reverse and draws a second, flipped copy (a diamond on the inner shape).
        if let replaced = replacingHostSpan(host, with: guest, tolerance: tolerance) {
            return replaced
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
        // Guest anchor each walk step came from, so baked fillet midpoints stay
        // smooth after they are inserted. Synthetic return points have no source.
        var walkSources: [Int?] = []
        // Tangent leaving the shared anchor into the guest walk, so the first
        // spliced segment keeps its curvature at the weld.
        var junctionOut = CGPoint.zero
        let count = guest.points.count
        let last = count - 1

        func addStep(_ index: Int, handle: CurveHandle) {
            walkPoints.append(guest.points[index])
            walkHandles.append(handle)
            walkSources.append(index)
        }

        if guest.isClosed {
            // Walk the whole loop starting just after the shared anchor and ending
            // back on it, so the loop closes before continuing along the host.
            junctionOut = guestHandles[guestIndex].outOffset
            let order = Array((guestIndex + 1)..<count) + Array(0...guestIndex)
            for i in order {
                addStep(i, handle: guestHandles[i])
            }
        } else if guestIndex == 0, last >= 1 {
            junctionOut = guestHandles[0].outOffset
            for i in 1..<last {
                addStep(i, handle: guestHandles[i])
            }
            var tip = guestHandles[last]
            tip.outOffset = tip.inOffset
            addStep(last, handle: tip)
            for i in stride(from: last - 1, through: 0, by: -1) {
                addStep(i, handle: flip(guestHandles[i]))
            }
        } else if guestIndex == last, last >= 1 {
            junctionOut = guestHandles[last].inOffset
            for i in stride(from: last - 1, through: 1, by: -1) {
                addStep(i, handle: flip(guestHandles[i]))
            }
            var tip = flip(guestHandles[0])
            tip.outOffset = tip.inOffset
            addStep(0, handle: tip)
            for i in 1...last {
                addStep(i, handle: guestHandles[i])
            }
        } else {
            junctionOut = guestHandles[guestIndex].inOffset
            // Mid-path join: walk to one far end and double back through the join,
            // then walk the other side and return — covers every guest edge.
            for i in stride(from: guestIndex - 1, through: 0, by: -1) {
                addStep(i, handle: flip(guestHandles[i]))
            }
            walkPoints.append(shared)
            walkHandles.append(CurveHandle())
            walkSources.append(nil)
            for i in (guestIndex + 1)..<count {
                addStep(i, handle: guestHandles[i])
            }
            walkPoints.append(shared)
            walkHandles.append(CurveHandle())
            walkSources.append(nil)
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
            smoothCornerIndices: unionSmoothCorners(
                smoothCornersInserting(
                    host.smoothCornerIndices,
                    at: hostIndex,
                    count: walkPoints.count
                ),
                remappedSmoothCorners(
                    guest.smoothCornerIndices,
                    sources: walkSources,
                    insertAt: hostIndex + 1
                )
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

    // MARK: - Closed outlines that share an edge

    /// Unions straight polygons that overlap or that an open chain closes against,
    /// including a chain that lands in the middle of an edge. A near miss within
    /// the join gap is pulled onto that edge first, so a side that stops just
    /// short of the base still closes and fills.
    private static func uniteTouchingOutlines(
        _ strokes: [VectorStroke],
        tolerance: CGFloat,
        base: VectorStroke
    ) -> [VectorStroke]? {
        guard strokes.allSatisfy(isStraightPolyline) else { return nil }
        let closedStrokes = strokes.filter { $0.isClosed && $0.points.count >= 3 }
        guard !closedStrokes.isEmpty else { return nil }
        let openStrokes = strokes.filter { !$0.isClosed && $0.points.count >= 2 }

        var polygons = closedStrokes.map { closedRing($0.points) }.filter { $0.count >= 3 }
        guard !polygons.isEmpty else { return nil }
        snapSmallerRings(&polygons, tolerance: tolerance)

        let atoms = openStrokes.enumerated().flatMap { index, stroke in
            lineAtoms(of: stroke, owner: index, slop: 0.5)
        }
        let chains = junctionChains(atoms, slop: tolerance)

        var bumps: [[CGPoint]] = []
        var pending: [[CGPoint]] = []
        for chain in chains {
            if chain.count >= 4,
               let first = chain.first,
               let last = chain.last,
               distance(first, last) <= tolerance {
                let ring = closedRing(chain)
                if ring.count >= 3 {
                    polygons.append(ring)
                }
                continue
            }
            let split = splitChain(chain, against: polygons, tolerance: tolerance)
            pending.append(contentsOf: split.loose)
            for bridge in split.bridges {
                switch bridgeRole(bridge, polygons: polygons, tolerance: tolerance) {
                case .bump:
                    if let bump = makeBump(bridge, on: &polygons, tolerance: tolerance) {
                        bumps.append(bump)
                    } else {
                        pending.append(bridge)
                    }
                case .divider:
                    pending.append(bridge)
                case .ignore:
                    break
                }
            }
        }
        let addedOutline = !bumps.isEmpty || polygons.count > closedStrokes.count
        polygons.append(contentsOf: bumps)
        guard polygons.count >= 2, addedOutline || bumps.count > 0 || closedStrokes.count >= 2 else {
            return nil
        }

        let paths = polygons.map { closedPath($0) }
        var merged = mergeClosedContours(paths, tolerance: tolerance)
        guard merged.count < paths.count, merged.contains(where: { $0.isClosed && $0.points.count >= 3 }) else {
            return nil
        }
        // The union outline fills the shape. Edges that ended up inside it were
        // real strokes — put them back so Join does not delete a line.
        spliceInteriorEdges(of: polygons, into: &merged, tolerance: tolerance)

        let cutouts = closedStrokes.flatMap(\.cutoutPoints)
        if !cutouts.isEmpty,
           let outer = merged.indices.max(by: {
               abs(signedArea(merged[$0].points)) < abs(signedArea(merged[$1].points))
           }) {
            merged[outer].cutouts += cutouts
        }

        var loose: [[CGPoint]] = []
        for chain in pending {
            if !spliceDivider(chain, into: &merged, tolerance: tolerance) {
                loose.append(chain)
            }
        }

        var results = merged.map { stroke(from: $0, base: base, rewritingPartialRuns: false) }
        let looseStrokes = loose.compactMap { openStroke(from: $0, base: base) }
        if looseStrokes.isEmpty { return results }
        if let chained = joinOpenContours(results + looseStrokes, tolerance: tolerance, base: base) {
            return chained
        }
        return results + looseStrokes
    }

    private enum BridgeRole {
        case bump
        case divider
        case ignore
    }

    /// A bridge whose middle sits outside every polygon extends the outline.
    /// One whose middle sits inside is a divider and must stay stroked.
    /// A bridge that already lies on the boundary adds nothing.
    private static func bridgeRole(
        _ chain: [CGPoint],
        polygons: [[CGPoint]],
        tolerance: CGFloat
    ) -> BridgeRole {
        guard chain.count >= 2, let sample = chainSample(chain) else { return .ignore }
        if polygons.contains(where: { pointInsidePolygon(sample, $0) }) {
            return .divider
        }
        if let host = hostRing(for: chain, polygons: polygons, tolerance: tolerance),
           abs(bumpArea(chain, on: host, tolerance: tolerance)) <= 1 {
            return .ignore
        }
        return .bump
    }

    private static func chainSample(_ chain: [CGPoint]) -> CGPoint? {
        guard let first = chain.first, let last = chain.last else { return nil }
        if chain.count == 2 {
            return CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        }
        return chain[chain.count / 2]
    }

    private struct ChainSplit {
        var bridges: [[CGPoint]]
        var loose: [[CGPoint]]
    }

    /// Cuts a chain wherever a vertex lands on a closed outline. The span between
    /// two landings is a bridge; a tail with only one landing stays loose.
    private static func splitChain(
        _ chain: [CGPoint],
        against polygons: [[CGPoint]],
        tolerance: CGFloat
    ) -> ChainSplit {
        guard chain.count >= 2 else { return ChainSplit(bridges: [], loose: []) }
        let hits = chain.indices.filter { index in
            polygons.contains { ring in
                let limit = joinGapLimit(
                    lengthA: ringLength(ring),
                    lengthB: contourLength(chain),
                    tolerance: tolerance
                )
                return nearestBoundaryHit(chain[index], on: ring, limit: limit) != nil
            }
        }
        guard hits.count >= 2 else {
            return ChainSplit(bridges: [], loose: [chain])
        }
        var bridges: [[CGPoint]] = []
        for pair in zip(hits, hits.dropFirst()) where pair.1 > pair.0 {
            bridges.append(Array(chain[pair.0...pair.1]))
        }
        var loose: [[CGPoint]] = []
        if let first = hits.first, first > 0 {
            loose.append(Array(chain[0...first]))
        }
        if let last = hits.last, last < chain.count - 1 {
            loose.append(Array(chain[last...]))
        }
        return ChainSplit(bridges: bridges, loose: loose)
    }

    private static func hostRing(
        for chain: [CGPoint],
        polygons: [[CGPoint]],
        tolerance: CGFloat
    ) -> [CGPoint]? {
        guard let start = chain.first, let end = chain.last else { return nil }
        var best: (ring: [CGPoint], gap: CGFloat)?
        for ring in polygons {
            let limit = joinGapLimit(
                lengthA: ringLength(ring),
                lengthB: contourLength(chain),
                tolerance: tolerance
            )
            guard let hit0 = nearestBoundaryHit(start, on: ring, limit: limit),
                  let hit1 = nearestBoundaryHit(end, on: ring, limit: limit),
                  distance(hit0.point, hit1.point) > 0.05
            else { continue }
            let gap = hit0.distance + hit1.distance
            if best == nil || gap < best!.gap {
                best = (ring, gap)
            }
        }
        return best?.ring
    }

    private static func bumpArea(
        _ chain: [CGPoint],
        on ring: [CGPoint],
        tolerance: CGFloat
    ) -> CGFloat {
        guard let bump = bumpPolygon(chain, on: ring, tolerance: tolerance) else { return 0 }
        return abs(signedArea(bump))
    }

    /// Inserts the chain's landings into `polygons` and returns the smaller loop
    /// the chain closes against that outline.
    private static func makeBump(
        _ chain: [CGPoint],
        on polygons: inout [[CGPoint]],
        tolerance: CGFloat
    ) -> [CGPoint]? {
        guard let start = chain.first, let end = chain.last else { return nil }
        var bestIndex: Int?
        var bestGap = CGFloat.greatestFiniteMagnitude
        for index in polygons.indices {
            let ring = polygons[index]
            let limit = joinGapLimit(
                lengthA: ringLength(ring),
                lengthB: contourLength(chain),
                tolerance: tolerance
            )
            guard let hit0 = nearestBoundaryHit(start, on: ring, limit: limit),
                  let hit1 = nearestBoundaryHit(end, on: ring, limit: limit),
                  distance(hit0.point, hit1.point) > 0.05
            else { continue }
            let gap = hit0.distance + hit1.distance
            if gap < bestGap {
                bestGap = gap
                bestIndex = index
            }
        }
        guard let bestIndex else { return nil }
        let limit = joinGapLimit(
            lengthA: ringLength(polygons[bestIndex]),
            lengthB: contourLength(chain),
            tolerance: tolerance
        )
        guard let hit0 = nearestBoundaryHit(start, on: polygons[bestIndex], limit: limit),
              let hit1 = nearestBoundaryHit(end, on: polygons[bestIndex], limit: limit),
              let bump = insertedBump(chain, hit0: hit0, hit1: hit1, into: &polygons[bestIndex])
        else { return nil }
        return bump
    }

    private static func insertedBump(
        _ chain: [CGPoint],
        hit0: BoundaryHit,
        hit1: BoundaryHit,
        into ring: inout [CGPoint]
    ) -> [CGPoint]? {
        ring = inserting([hit0, hit1], into: ring)
        guard let startIndex = ring.firstIndex(where: { distance($0, hit0.point) <= 0.05 }),
              let endIndex = ring.firstIndex(where: { distance($0, hit1.point) <= 0.05 }),
              startIndex != endIndex
        else { return nil }
        return bumpPolygon(chain, from: startIndex, to: endIndex, on: ring, hit0: hit0, hit1: hit1)
    }

    private static func bumpPolygon(
        _ chain: [CGPoint],
        on ring: [CGPoint],
        tolerance: CGFloat
    ) -> [CGPoint]? {
        guard let start = chain.first, let end = chain.last else { return nil }
        let limit = joinGapLimit(
            lengthA: ringLength(ring),
            lengthB: contourLength(chain),
            tolerance: tolerance
        )
        guard let hit0 = nearestBoundaryHit(start, on: ring, limit: limit),
              let hit1 = nearestBoundaryHit(end, on: ring, limit: limit)
        else { return nil }
        var working = inserting([hit0, hit1], into: ring)
        guard let startIndex = working.firstIndex(where: { distance($0, hit0.point) <= 0.05 }),
              let endIndex = working.firstIndex(where: { distance($0, hit1.point) <= 0.05 }),
              startIndex != endIndex
        else { return nil }
        return bumpPolygon(chain, from: startIndex, to: endIndex, on: working, hit0: hit0, hit1: hit1)
    }

    private static func bumpPolygon(
        _ chain: [CGPoint],
        from startIndex: Int,
        to endIndex: Int,
        on ring: [CGPoint],
        hit0: BoundaryHit,
        hit1: BoundaryHit
    ) -> [CGPoint]? {
        var oriented = chain
        if distance(oriented[0], hit0.point) > distance(oriented[0], hit1.point) {
            oriented.reverse()
        }
        oriented[0] = ring[startIndex]
        oriented[oriented.count - 1] = ring[endIndex]
        let back = ringArc(ring, from: endIndex, to: startIndex)
        let other = Array(ringArc(ring, from: startIndex, to: endIndex).reversed())
        let loop1 = closedRing(oriented + back.dropFirst().dropLast())
        let loop2 = closedRing(oriented + other.dropFirst().dropLast())
        let area1 = abs(signedArea(loop1))
        let area2 = abs(signedArea(loop2))
        let bump = area1 <= area2 ? loop1 : loop2
        guard min(area1, area2) > 1, bump.count >= 3 else { return nil }
        return bump
    }

    /// Puts back every input edge whose middle sits inside the filled outline.
    /// Those edges are the lines the union would otherwise delete.
    private static func spliceInteriorEdges(
        of polygons: [[CGPoint]],
        into paths: inout [Path],
        tolerance: CGFloat
    ) {
        guard let outline = paths.first(where: { $0.isClosed && $0.points.count >= 3 })?.points else { return }
        var seen = Set<String>()
        for ring in polygons {
            guard ring.count >= 2 else { continue }
            for index in ring.indices {
                let start = ring[index]
                let end = ring[(index + 1) % ring.count]
                guard distance(start, end) > 0.05 else { continue }
                let key = undirectedEdgeKey(start, end)
                guard seen.insert(key).inserted else { continue }
                let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                if liesOnRing(middle, outline) { continue }
                guard pointInsidePolygon(middle, outline) else { continue }
                _ = spliceDivider([start, end], into: &paths, tolerance: tolerance)
            }
        }
    }

    private static func undirectedEdgeKey(_ a: CGPoint, _ b: CGPoint) -> String {
        let ka = unionKey(a)
        let kb = unionKey(b)
        return ka < kb ? ka + "|" + kb : kb + "|" + ka
    }

    private static func liesOnRing(_ point: CGPoint, _ ring: [CGPoint]) -> Bool {
        guard ring.count >= 2 else { return false }
        for index in ring.indices {
            let start = ring[index]
            let end = ring[(index + 1) % ring.count]
            if distance(point, start) <= 0.5 || distance(point, end) <= 0.5 { return true }
            if pointOnSegment(point, start, end, snap: 0.5) { return true }
        }
        return false
    }

    /// Draws a divider that now lands on the united outline, out and back, so the
    /// line meets the base without opening the fill.
    private static func spliceDivider(
        _ chain: [CGPoint],
        into paths: inout [Path],
        tolerance: CGFloat
    ) -> Bool {
        guard chain.count >= 2, let start = chain.first, let end = chain.last else { return false }
        for index in paths.indices where paths[index].isClosed {
            let ring = paths[index].points
            let limit = joinGapLimit(
                lengthA: ringLength(ring),
                lengthB: contourLength(chain),
                tolerance: tolerance
            )
            guard let hit0 = nearestBoundaryHit(start, on: ring, limit: limit),
                  let hit1 = nearestBoundaryHit(end, on: ring, limit: limit),
                  distance(hit0.point, hit1.point) > 0.05,
                  let sample = chainSample(chain)
            else { continue }
            let landsOnEdge = hit0.vertexIndex == nil || hit1.vertexIndex == nil
            guard pointInsidePolygon(sample, ring) || landsOnEdge else { continue }
            var points = chain
            let anchorHit: BoundaryHit
            let farHit: BoundaryHit
            if hit0.vertexIndex == nil, hit1.vertexIndex != nil {
                points.reverse()
                anchorHit = hit1
                farHit = hit0
            } else {
                anchorHit = hit0
                farHit = hit1
            }
            points[0] = anchorHit.point
            points[points.count - 1] = farHit.point
            var host = paths[index]
            host.points = inserting([hit0, hit1], into: host.points)
            host.handles = Array(repeating: CurveHandle(), count: host.points.count)
            host.contour = host.points
            let guest = Path(
                points: points,
                handles: Array(repeating: CurveHandle(), count: points.count),
                isClosed: false,
                isCurve: false,
                contour: points
            )
            paths[index] = splice(host, guest, at: points[0], tolerance: max(limit, 0.5))
            return true
        }
        return false
    }

    private struct BoundaryHit {
        var point: CGPoint
        var distance: CGFloat
        var vertexIndex: Int?
        var edgeIndex: Int?
        var edgeT: CGFloat
    }

    private static func nearestBoundaryHit(
        _ point: CGPoint,
        on ring: [CGPoint],
        limit: CGFloat
    ) -> BoundaryHit? {
        guard ring.count >= 2, limit >= 0 else { return nil }
        var best: BoundaryHit?
        func consider(_ hit: BoundaryHit) {
            if best == nil || hit.distance < best!.distance - 0.001 {
                best = hit
            }
        }
        for index in ring.indices {
            let gap = distance(point, ring[index])
            if gap <= limit {
                consider(BoundaryHit(
                    point: ring[index],
                    distance: gap,
                    vertexIndex: index,
                    edgeIndex: nil,
                    edgeT: 0
                ))
            }
        }
        for index in ring.indices {
            let start = ring[index]
            let end = ring[(index + 1) % ring.count]
            let axis = CGPoint(x: end.x - start.x, y: end.y - start.y)
            let lengthSquared = axis.x * axis.x + axis.y * axis.y
            let length = sqrt(lengthSquared)
            guard length > 0.05 else { continue }
            let t = ((point.x - start.x) * axis.x + (point.y - start.y) * axis.y) / lengthSquared
            guard t > 0.001, t < 0.999 else { continue }
            let projected = CGPoint(x: start.x + t * axis.x, y: start.y + t * axis.y)
            let gap = distance(point, projected)
            let edgeLimit = min(limit, max(1.5, length * 0.35))
            guard gap <= edgeLimit else { continue }
            consider(BoundaryHit(
                point: projected,
                distance: gap,
                vertexIndex: nil,
                edgeIndex: index,
                edgeT: t
            ))
        }
        return best
    }

    /// Pulls vertices of a smaller outline onto a larger one it already touches,
    /// so a corner that stops just short of a shared edge becomes that edge.
    private static func snapSmallerRings(_ polygons: inout [[CGPoint]], tolerance: CGFloat) {
        let snapshot = polygons
        let areas = snapshot.map { abs(signedArea($0)) }
        var touching = Array(repeating: Set<Int>(), count: polygons.count)
        for index in snapshot.indices {
            for point in snapshot[index] {
                for other in snapshot.indices where other != index {
                    let limit = joinGapLimit(
                        lengthA: ringLength(snapshot[index]),
                        lengthB: ringLength(snapshot[other]),
                        tolerance: tolerance
                    )
                    if nearestBoundaryHit(point, on: snapshot[other], limit: limit) != nil {
                        touching[index].insert(other)
                    }
                }
            }
        }
        for index in polygons.indices {
            for vertex in polygons[index].indices {
                let point = snapshot[index][vertex]
                var best: BoundaryHit?
                for other in touching[index] {
                    let otherIsHost = areas[other] > areas[index] + 0.5
                        || (abs(areas[other] - areas[index]) <= 0.5 && other < index)
                    guard otherIsHost else { continue }
                    let limit = joinGapLimit(
                        lengthA: ringLength(snapshot[index]),
                        lengthB: ringLength(snapshot[other]),
                        tolerance: tolerance
                    )
                    guard let hit = nearestBoundaryHit(point, on: snapshot[other], limit: limit) else { continue }
                    if best == nil || hit.distance < best!.distance {
                        best = hit
                    }
                }
                if let best, best.distance > 0.05 {
                    polygons[index][vertex] = best.point
                }
            }
        }
    }

    private static func inserting(_ hits: [BoundaryHit], into ring: [CGPoint]) -> [CGPoint] {
        var extras: [Int: [(t: CGFloat, point: CGPoint)]] = [:]
        for hit in hits {
            guard hit.vertexIndex == nil, let edge = hit.edgeIndex else { continue }
            extras[edge, default: []].append((hit.edgeT, hit.point))
        }
        var result: [CGPoint] = []
        for index in ring.indices {
            result.append(ring[index])
            let additions = (extras[index] ?? []).sorted { $0.t < $1.t }
            for addition in additions {
                if let last = result.last, distance(last, addition.point) <= 0.05 { continue }
                let next = ring[(index + 1) % ring.count]
                if distance(next, addition.point) <= 0.05 { continue }
                result.append(addition.point)
            }
        }
        return result
    }

    private static func ringArc(_ points: [CGPoint], from start: Int, to end: Int) -> [CGPoint] {
        guard points.indices.contains(start), points.indices.contains(end) else { return [] }
        var arc = [points[start]]
        var index = start
        var guardCount = 0
        while index != end, guardCount <= points.count {
            index = (index + 1) % points.count
            arc.append(points[index])
            guardCount += 1
        }
        return arc
    }

    private static func closedRing(_ points: [CGPoint]) -> [CGPoint] {
        var ring: [CGPoint] = []
        for point in points {
            if let last = ring.last, distance(last, point) <= 0.05 { continue }
            ring.append(point)
        }
        if ring.count >= 2,
           let first = ring.first,
           let last = ring.last,
           distance(first, last) <= 0.05 {
            ring.removeLast()
        }
        return ring
    }

    private static func ringLength(_ points: [CGPoint]) -> CGFloat {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return 0 }
        return contourLength(points) + distance(first, last)
    }

    private static func closedPath(_ points: [CGPoint]) -> Path {
        let ring = closedRing(points)
        return Path(
            points: ring,
            handles: Array(repeating: CurveHandle(), count: ring.count),
            isClosed: true,
            isCurve: false,
            contour: ring
        )
    }

    private static func openStroke(from points: [CGPoint], base: VectorStroke) -> VectorStroke? {
        let ring = closedRing(points)
        guard ring.count >= 2 else { return nil }
        var path = closedPath(ring)
        path.isClosed = false
        return stroke(from: path, base: base, rewritingPartialRuns: false)
    }

    /// Chains straight edges through ordinary corners and stops at a fork, so a
    /// line that leaves the outline is not swallowed into the outline chain.
    private static func junctionChains(_ atoms: [LineAtom], slop: CGFloat) -> [[CGPoint]] {
        let welded = weldingEndpoints(atoms, slop: slop).filter { distance($0.from, $0.to) > 0.05 }
        guard !welded.isEmpty else { return [] }
        func key(_ point: CGPoint) -> String {
            let scale: CGFloat = 1000
            return "\((point.x * scale).rounded() / scale)|\((point.y * scale).rounded() / scale)"
        }
        var at: [String: [Int]] = [:]
        for (index, atom) in welded.enumerated() {
            at[key(atom.from), default: []].append(index)
            at[key(atom.to), default: []].append(index)
        }
        func degree(_ point: CGPoint) -> Int { at[key(point)]?.count ?? 0 }
        var used = [Bool](repeating: false, count: welded.count)

        func walk(from atomIndex: Int, forward: Bool) -> [CGPoint] {
            var points: [CGPoint] = []
            var index = atomIndex
            var forward = forward
            while !used[index] {
                used[index] = true
                let atom = welded[index]
                let start = forward ? atom.from : atom.to
                let end = forward ? atom.to : atom.from
                if points.isEmpty { points.append(start) }
                points.append(end)
                if degree(end) != 2 { break }
                guard let next = (at[key(end)] ?? []).first(where: { !used[$0] }) else { break }
                let nextAtom = welded[next]
                forward = distance(nextAtom.from, end) <= slop
                index = next
            }
            return points
        }

        var chains: [[CGPoint]] = []
        for index in welded.indices where !used[index] {
            let atom = welded[index]
            if degree(atom.from) == 2, degree(atom.to) == 2 { continue }
            let points = walk(from: index, forward: degree(atom.from) != 2)
            if points.count >= 2 { chains.append(points) }
        }
        for index in welded.indices where !used[index] {
            let points = walk(from: index, forward: true)
            if points.count >= 2 { chains.append(points) }
        }
        return chains
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
