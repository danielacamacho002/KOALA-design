//
//  PathJoinEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Welds several open paths into a single continuous path by connecting their
/// nearest endpoints. Curve tangent handles are preserved: if any input path is
/// a curve the result stays a curve (straight segments get zero-offset handles),
/// otherwise the result is a plain polyline. Arc mid-curve anchors are preserved
/// either as Bezier handles (curve joins) or as baked smooth-corner indices
/// (polyline joins) so the circular geometry is not lost.
enum PathJoinEngine {
    private struct Path {
        var points: [CGPoint]
        var handles: [CurveHandle]
        /// Anchor indices that should render as circular arcs through (prev, self, next).
        var smoothMiddles: Set<Int>
    }

    static func join(_ strokes: [VectorStroke], tolerance: CGFloat) -> VectorStroke? {
        let usable = strokes.filter { $0.points.count >= 2 && !$0.isClosed }
        guard usable.count >= 2, let base = usable.first else { return nil }

        let anyCurve = usable.contains { $0.shapeType == .curve }

        var result = normalized(base)
        var remaining = Array(usable.dropFirst()).map { normalized($0) }

        while !remaining.isEmpty {
            guard let match = bestConnection(result: result, candidates: remaining) else { break }
            var candidate = remaining[match.index]
            if match.reversed { candidate = reverse(candidate) }
            result = match.attachToEnd
                ? append(result, candidate, tolerance: tolerance)
                : append(candidate, result, tolerance: tolerance)
            remaining.remove(at: match.index)
        }

        var joined = base
        joined.id = UUID()
        joined.points = result.points
        joined.isClosed = false
        joined.shapeType = anyCurve ? .curve : .polyline
        joined.curveHandles = anyCurve ? result.handles : nil
        joined.shapeRotation = nil
        joined.rotationBasePoints = nil
        joined.rotationBaseCenter = nil
        joined.cutoutPoints = []
        joined.cornerRadius = 0
        joined.cornerRadiiByIndex = nil
        // Curve joins already encode arc geometry in Bezier handles; polyline joins
        // keep the mid-curve anchors marked so rendering re-expands them to arcs.
        joined.smoothCornerIndices = anyCurve || result.smoothMiddles.isEmpty
            ? nil
            : result.smoothMiddles
        return joined
    }

    /// Converts a stroke into an anchor + handle path. Arcs contribute their three
    /// defining anchors (start / mid / end) with the mid marked as a smooth corner,
    /// plus circular Bezier handles for mixed joins with curves. Non-curve strokes
    /// receive zero-offset (straight) handles so mixed joins keep their curved parts.
    private static func normalized(_ stroke: VectorStroke) -> Path {
        if stroke.shapeType == .arc,
           let anchors = ShapeGeometry.arcAnchorPoints(stroke.points),
           anchors.count == 3 {
            let handles = ShapeGeometry.curveHandlesApproximatingArc(
                start: anchors[0],
                mid: anchors[1],
                end: anchors[2]
            ) ?? Array(repeating: CurveHandle(), count: 3)
            return Path(points: anchors, handles: handles, smoothMiddles: [1])
        }

        let points = stroke.points
        let existingSmooth = stroke.smoothCornerIndices ?? []
        if stroke.shapeType == .curve,
           let handles = stroke.curveHandles,
           handles.count == points.count {
            return Path(points: points, handles: handles, smoothMiddles: existingSmooth)
        }
        return Path(
            points: points,
            handles: Array(repeating: CurveHandle(), count: points.count),
            smoothMiddles: existingSmooth
        )
    }

    private static func reverse(_ path: Path) -> Path {
        let count = path.points.count
        return Path(
            points: path.points.reversed().map { $0 },
            handles: path.handles.reversed().map {
                CurveHandle(inOffset: $0.outOffset, outOffset: $0.inOffset)
            },
            smoothMiddles: Set(path.smoothMiddles.map { count - 1 - $0 })
        )
    }

    /// Appends `tail` after `head`, welding the shared endpoint when close enough.
    private static func append(_ head: Path, _ tail: Path, tolerance: CGFloat) -> Path {
        guard let last = head.points.last, let first = tail.points.first else {
            return Path(
                points: head.points + tail.points,
                handles: head.handles + tail.handles,
                smoothMiddles: head.smoothMiddles.union(
                    Set(tail.smoothMiddles.map { $0 + head.points.count })
                )
            )
        }
        var merged = head
        if hypot(last.x - first.x, last.y - first.y) <= tolerance {
            if !tail.handles.isEmpty {
                merged.handles[merged.handles.count - 1].outOffset = tail.handles[0].outOffset
            }
            let headCount = merged.points.count
            merged.points.append(contentsOf: tail.points.dropFirst())
            merged.handles.append(contentsOf: tail.handles.dropFirst())
            // Welded endpoint (tail index 0) is never a smooth mid; remap the rest.
            let remappedTail = Set(
                tail.smoothMiddles.compactMap { index -> Int? in
                    guard index > 0 else { return nil }
                    return headCount + index - 1
                }
            )
            merged.smoothMiddles.formUnion(remappedTail)
        } else {
            let headCount = merged.points.count
            merged.points.append(contentsOf: tail.points)
            merged.handles.append(contentsOf: tail.handles)
            merged.smoothMiddles.formUnion(Set(tail.smoothMiddles.map { $0 + headCount }))
        }
        return merged
    }

    private struct Connection {
        var index: Int
        var reversed: Bool
        var attachToEnd: Bool
        var gap: CGFloat
    }

    private static func bestConnection(result: Path, candidates: [Path]) -> Connection? {
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
            for option in options where best == nil || option.gap < best!.gap {
                best = option
            }
        }
        return best
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
