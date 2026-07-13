//
//  PathJoinEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Welds several open paths into a single continuous path by connecting their
/// nearest endpoints. Curve tangent handles are preserved: if any input path is
/// a curve the result stays a curve (straight segments get zero-offset handles),
/// otherwise the result is a plain polyline.
enum PathJoinEngine {
    private struct Path {
        var points: [CGPoint]
        var handles: [CurveHandle]
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
        joined.smoothCornerIndices = nil
        return joined
    }

    /// Converts a stroke into an anchor + handle path. Non-curve strokes receive
    /// zero-offset (straight) handles so mixed joins keep their curved parts.
    private static func normalized(_ stroke: VectorStroke) -> Path {
        let points = stroke.points
        if stroke.shapeType == .curve,
           let handles = stroke.curveHandles,
           handles.count == points.count {
            return Path(points: points, handles: handles)
        }
        return Path(points: points, handles: Array(repeating: CurveHandle(), count: points.count))
    }

    private static func reverse(_ path: Path) -> Path {
        Path(
            points: path.points.reversed().map { $0 },
            handles: path.handles.reversed().map {
                CurveHandle(inOffset: $0.outOffset, outOffset: $0.inOffset)
            }
        )
    }

    /// Appends `tail` after `head`, welding the shared endpoint when close enough.
    private static func append(_ head: Path, _ tail: Path, tolerance: CGFloat) -> Path {
        guard let last = head.points.last, let first = tail.points.first else {
            return Path(points: head.points + tail.points, handles: head.handles + tail.handles)
        }
        var merged = head
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
