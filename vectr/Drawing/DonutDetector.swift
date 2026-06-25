//
//  DonutDetector.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Detects concentric circles and merges inner rings into outer strokes as cutout holes.
enum DonutDetector {
    static func reconcile(document: VectrDocument) {
        let centerTolerance = document.grid.visualSpacing(for: document.settings) * 0.5
        var removed = Set<UUID>()

        let circleIDs = document.strokes.filter {
            $0.shapeType == .circle && $0.isClosed
        }.map(\.id)

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

                if hostCircle.radius > candidateCircle.radius + centerTolerance {
                    var host = document.strokes[hostIndex]
                    host.cutoutPoints.append(document.strokes[candidateIndex].points)
                    document.strokes[hostIndex] = host
                    removed.insert(candidateID)
                } else if candidateCircle.radius > hostCircle.radius + centerTolerance {
                    var candidate = document.strokes[candidateIndex]
                    candidate.cutoutPoints.append(document.strokes[hostIndex].points)
                    document.strokes[candidateIndex] = candidate
                    removed.insert(hostID)
                    break
                }
            }
        }

        guard !removed.isEmpty else { return }
        document.strokes.removeAll { removed.contains($0.id) }
    }

    private static func areConcentric(
        _ a: (center: CGPoint, radius: CGFloat),
        _ b: (center: CGPoint, radius: CGFloat),
        tolerance: CGFloat
    ) -> Bool {
        hypot(a.center.x - b.center.x, a.center.y - b.center.y) <= tolerance
    }
}
