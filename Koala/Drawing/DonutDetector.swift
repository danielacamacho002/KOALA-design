//
//  DonutDetector.swift
//  Koala
//

import CoreGraphics
import Foundation

/// Detects concentric circles and nested quads, and merges the inner shape into the
/// outer stroke as a cutout hole. Shapes only merge within a single layer; other layers
/// stay independent until merged.
enum DonutDetector {
    static func reconcile(document: KoalaDocument) {
        let centerTolerance = document.grid.visualSpacing(for: document.settings) * 0.5
        var removed = Set<UUID>()

        let circlesByLayer = Dictionary(
            grouping: document.strokes.filter { $0.shapeType == .circle && $0.isClosed },
            by: \.layerID
        )

        for circleIDs in circlesByLayer.values.map({ $0.map(\.id) }) {
            mergeConcentricRings(
                circleIDs: circleIDs,
                in: document,
                centerTolerance: centerTolerance,
                removed: &removed
            )
        }

        let quadsByLayer = Dictionary(
            grouping: document.strokes.filter(isQuadCandidate),
            by: \.layerID
        )

        for quadIDs in quadsByLayer.values.map({ $0.map(\.id) }) {
            mergeNestedQuads(quadIDs: quadIDs, in: document, removed: &removed)
        }

        guard !removed.isEmpty else { return }
        document.strokes.removeAll { removed.contains($0.id) }
    }

    // MARK: - Quads

    private static func isQuadCandidate(_ stroke: VectorStroke) -> Bool {
        ShapeGeometry.isEditableQuad(stroke)
            && !stroke.isConstruction
            && !stroke.hasAnyCornerFillets
            && (stroke.openEdgeStarts?.isEmpty ?? true)
    }

    private static func mergeNestedQuads(
        quadIDs: [UUID],
        in document: KoalaDocument,
        removed: inout Set<UUID>
    ) {
        for i in 0..<quadIDs.count {
            for j in (i + 1)..<quadIDs.count {
                guard !removed.contains(quadIDs[i]) else { break }
                guard !removed.contains(quadIDs[j]),
                      let first = document.strokes.first(where: { $0.id == quadIDs[i] }),
                      let second = document.strokes.first(where: { $0.id == quadIDs[j] })
                else { continue }

                if canHost(first, hole: second) {
                    absorb(second, into: first, in: document, removed: &removed)
                } else if canHost(second, hole: first) {
                    absorb(first, into: second, in: document, removed: &removed)
                }
            }
        }
    }

    /// True when `hole` sits strictly inside `host`'s outer contour, clear of its edges,
    /// and does not touch any hole `host` already has.
    private static func canHost(_ host: VectorStroke, hole: VectorStroke) -> Bool {
        guard hole.cutoutPoints.isEmpty else { return false }
        let outer = ShapeGeometry.renderPoints(for: host)
        let inner = ShapeGeometry.renderPoints(for: hole)
        guard outer.count >= 3, inner.count >= 3 else { return false }

        let clearance = max(host.strokeWidth, hole.strokeWidth) * 0.5
        guard !PolygonBoolean.edgesCross(outer, inner),
              inner.allSatisfy({
                  PolygonBoolean.pointInPolygon($0, outer)
                      && distance(from: $0, toContour: outer) > clearance
              })
        else { return false }

        return !host.cutoutPoints.contains { PolygonBoolean.polygonsOverlap($0, inner) }
    }

    private static func absorb(
        _ hole: VectorStroke,
        into host: VectorStroke,
        in document: KoalaDocument,
        removed: inout Set<UUID>
    ) {
        guard let hostIndex = document.strokes.firstIndex(where: { $0.id == host.id }) else { return }
        document.strokes[hostIndex].cutoutPoints.append(ShapeGeometry.renderPoints(for: hole))
        removed.insert(hole.id)
        if document.selectedStrokeID == hole.id {
            document.selectedStrokeID = host.id
        }
    }

    private static func distance(from point: CGPoint, toContour contour: [CGPoint]) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for index in contour.indices {
            let start = contour[index]
            let end = contour[(index + 1) % contour.count]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0
                ? min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
                : 0
            best = min(best, hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy)))
        }
        return best
    }

    // MARK: - Circles

    private static func mergeConcentricRings(
        circleIDs: [UUID],
        in document: KoalaDocument,
        centerTolerance: CGFloat,
        removed: inout Set<UUID>
    ) {
        for i in 0..<circleIDs.count {
            let hostID = circleIDs[i]
            guard !removed.contains(hostID),
                  let hostIndex = document.strokes.firstIndex(where: { $0.id == hostID }),
                  let hostCircle = ShapeGeometry.circleFromCardinalPoints(document.strokes[hostIndex].points)
            else { continue }

            for j in (i + 1)..<circleIDs.count {
                let candidateID = circleIDs[j]
                guard !removed.contains(candidateID),
                      let candidateIndex = document.strokes.firstIndex(where: { $0.id == candidateID }),
                      let candidateCircle = ShapeGeometry.circleFromCardinalPoints(document.strokes[candidateIndex].points)
                else { continue }

                guard areConcentric(hostCircle, candidateCircle, tolerance: centerTolerance) else { continue }

                // Cutouts render as polylines, so store the sampled rim, not the 4 cardinal points.
                if hostCircle.radius > candidateCircle.radius + centerTolerance {
                    var host = document.strokes[hostIndex]
                    host.cutoutPoints.append(ShapeGeometry.renderPoints(for: document.strokes[candidateIndex]))
                    document.strokes[hostIndex] = host
                    removed.insert(candidateID)
                } else if candidateCircle.radius > hostCircle.radius + centerTolerance {
                    var candidate = document.strokes[candidateIndex]
                    candidate.cutoutPoints.append(ShapeGeometry.renderPoints(for: document.strokes[hostIndex]))
                    document.strokes[candidateIndex] = candidate
                    removed.insert(hostID)
                    break
                }
            }
        }
    }

    private static func areConcentric(
        _ a: (center: CGPoint, radius: CGFloat),
        _ b: (center: CGPoint, radius: CGFloat),
        tolerance: CGFloat
    ) -> Bool {
        hypot(a.center.x - b.center.x, a.center.y - b.center.y) <= tolerance
    }
}
