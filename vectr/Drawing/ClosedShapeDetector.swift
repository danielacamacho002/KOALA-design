//
//  ClosedShapeDetector.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Marks single strokes closed when their endpoints meet, and merges multi-stroke
/// loops (e.g. a trimmed circle arc attached to a polyline) into one closed shape.
enum ClosedShapeDetector {
    static func reconcile(document: VectrDocument) {
        let tolerance = document.grid.spacing * 0.5

        closeSingleStrokeLoops(in: document, tolerance: tolerance)
        mergeMultiStrokeLoops(in: document, tolerance: tolerance)
    }

    // MARK: - Single stroke

    private static func closeSingleStrokeLoops(in document: VectrDocument, tolerance: CGFloat) {
        for index in document.strokes.indices {
            guard isLoopCandidate(document.strokes[index]) else { continue }
            // Arcs are open curves. Closing one when its endpoints sit within a grid
            // cell draws a chord across the pie, then immediately re-closes it after
            // trim — the chord looks impossible to remove.
            guard document.strokes[index].shapeType != .arc else { continue }

            let points = ShapeGeometry.renderPoints(for: document.strokes[index])
            guard points.count >= 3 else { continue }

            if shouldCloseOpenContour(points, tolerance: tolerance) {
                document.strokes[index].isClosed = true
                if document.strokes[index].shapeType == .polyline,
                   document.strokes[index].points.count >= 3,
                   let strokeFirst = document.strokes[index].points.first,
                   let strokeLast = document.strokes[index].points.last,
                   pointsConnect(strokeFirst, strokeLast, tolerance: tolerance),
                   document.strokes[index].points.last != document.strokes[index].points.first {
                    document.strokes[index].points.removeLast()
                }
            }
        }
    }

    // MARK: - Multi-stroke loops

    private static func mergeMultiStrokeLoops(in document: VectrDocument, tolerance: CGFloat) {
        let layerIDs = Set(document.strokes.map(\.layerID))

        for layerID in layerIDs {
            while mergeOneLoop(on: layerID, in: document, tolerance: tolerance) {}
        }
    }

    @discardableResult
    private static func mergeOneLoop(on layerID: UUID, in document: VectrDocument, tolerance: CGFloat) -> Bool {
        let candidates = document.strokes.compactMap { stroke -> VectorStroke? in
            guard stroke.layerID == layerID, isLoopCandidate(stroke) else { return nil }
            let points = ShapeGeometry.renderPoints(for: stroke)
            guard points.count >= 2,
                  let start = points.first,
                  let end = points.last else { return nil }
            guard !pointsConnect(start, end, tolerance: tolerance) || points.count >= 3 else { return nil }
            return stroke
        }

        guard candidates.count >= 2 else { return false }

        let endpointCount = candidates.count * 2
        var parent = Array(0..<endpointCount)

        func cluster(of endpoint: Int) -> Int {
            var node = endpoint
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }

        func unionEndpoints(_ a: Int, _ b: Int) {
            let rootA = cluster(of: a)
            let rootB = cluster(of: b)
            guard rootA != rootB else { return }
            parent[rootB] = rootA
        }

        func endpointPoint(_ endpointIndex: Int) -> CGPoint {
            let candidate = candidates[endpointIndex / 2]
            let points = ShapeGeometry.renderPoints(for: candidate)
            return endpointIndex.isMultiple(of: 2) ? points.first! : points.last!
        }

        for left in 0..<endpointCount {
            for right in (left + 1)..<endpointCount {
                if pointsConnect(endpointPoint(left), endpointPoint(right), tolerance: tolerance) {
                    unionEndpoints(left, right)
                }
            }
        }

        var adjacency: [Int: [Int]] = [:]
        for candidateSlot in candidates.indices {
            let startEndpoint = candidateSlot * 2
            let endEndpoint = candidateSlot * 2 + 1
            let startCluster = cluster(of: startEndpoint)
            let endCluster = cluster(of: endEndpoint)
            guard startCluster != endCluster else { continue }

            adjacency[startCluster, default: []].append(startEndpoint)
            adjacency[endCluster, default: []].append(endEndpoint)
        }

        for startCluster in adjacency.keys.sorted() {
            guard let clusterEndpoints = adjacency[startCluster], clusterEndpoints.count == 2 else { continue }
            guard let loop = traceLoop(from: startCluster, adjacency: adjacency, parent: parent) else {
                continue
            }

            guard loop.count >= 2 else { continue }

            let componentClusters = loopComponentClusters(
                startingAt: startCluster,
                adjacency: adjacency,
                parent: parent
            )
            guard componentClusters.allSatisfy({ adjacency[$0]?.count == 2 }),
                  loop.count == componentClusters.count,
                  Set(loop.map(\.candidateSlot)).count == loop.count else { continue }

            guard let mergedPoints = mergeLoopPoints(
                loop: loop,
                candidates: candidates,
                tolerance: tolerance
            ) else { continue }

            let template = candidates[loop[0].candidateSlot]
            let mergedStroke = VectorStroke(
                layerID: layerID,
                points: mergedPoints,
                strokeWidth: template.strokeWidth,
                strokeColor: template.strokeColor,
                isClosed: true,
                shapeType: .polyline
            )

            let removedIDs = Set(loop.map { candidates[$0.candidateSlot].id })
            document.strokes.removeAll { removedIDs.contains($0.id) }
            document.strokes.append(mergedStroke)
            if let selected = document.selectedStrokeID, removedIDs.contains(selected) {
                document.selectedStrokeID = mergedStroke.id
            }
            return true
        }

        return false
    }

    private struct LoopStep {
        var candidateSlot: Int
        var forward: Bool
    }

    private static func loopComponentClusters(
        startingAt startCluster: Int,
        adjacency: [Int: [Int]],
        parent: [Int]
    ) -> Set<Int> {
        func cluster(of endpoint: Int) -> Int {
            var node = endpoint
            while parent[node] != node {
                node = parent[node]
            }
            return node
        }

        var visited = Set<Int>()
        var queue = [startCluster]
        visited.insert(startCluster)

        while let current = queue.popLast() {
            guard let endpoints = adjacency[current] else { continue }
            for endpoint in endpoints {
                let partner = endpoint.isMultiple(of: 2) ? endpoint + 1 : endpoint - 1
                let neighbor = cluster(of: partner)
                if visited.insert(neighbor).inserted {
                    queue.append(neighbor)
                }
            }
        }

        return visited
    }

    private static func traceLoop(
        from startCluster: Int,
        adjacency: [Int: [Int]],
        parent: [Int]
    ) -> [LoopStep]? {
        guard let clusterEndpoints = adjacency[startCluster], clusterEndpoints.count == 2 else { return nil }

        func cluster(of endpoint: Int) -> Int {
            var node = endpoint
            while parent[node] != node {
                node = parent[node]
            }
            return node
        }

        var steps: [LoopStep] = []
        var visitedEndpoints = Set<Int>()

        var currentEndpoint = clusterEndpoints[0]
        let startEndpoint = currentEndpoint

        while true {
            guard !visitedEndpoints.contains(currentEndpoint) else { return nil }
            visitedEndpoints.insert(currentEndpoint)

            let candidateSlot = currentEndpoint / 2
            let enteredAtStart = currentEndpoint.isMultiple(of: 2)
            steps.append(LoopStep(candidateSlot: candidateSlot, forward: enteredAtStart))

            let partnerEndpoint = enteredAtStart ? currentEndpoint + 1 : currentEndpoint - 1
            let nextCluster = cluster(of: partnerEndpoint)
            guard let nextEndpoints = adjacency[nextCluster], nextEndpoints.count == 2 else { return nil }

            let nextEndpoint = nextEndpoints.first { $0 != partnerEndpoint } ?? nextEndpoints[0]
            if nextEndpoint == startEndpoint {
                return steps
            }

            currentEndpoint = nextEndpoint
        }
    }

    private static func mergeLoopPoints(
        loop: [LoopStep],
        candidates: [VectorStroke],
        tolerance: CGFloat
    ) -> [CGPoint]? {
        var merged: [CGPoint] = []

        for step in loop {
            let points = ShapeGeometry.renderPoints(for: candidates[step.candidateSlot])
            let segment = step.forward ? points : Array(points.reversed())

            if merged.isEmpty {
                merged.append(contentsOf: segment)
            } else if let last = merged.last, let first = segment.first,
                      pointsConnect(last, first, tolerance: tolerance) {
                merged.append(contentsOf: segment.dropFirst())
            } else {
                merged.append(contentsOf: segment)
            }
        }

        guard merged.count >= 3 else { return nil }

        if let first = merged.first, let last = merged.last,
           pointsConnect(first, last, tolerance: tolerance) {
            merged.removeLast()
        }

        return merged.count >= 3 ? merged : nil
    }

    // MARK: - Helpers

    /// True when an open contour should be marked closed. A V / star-point whose
    /// feet sit in the same grid cell is not a loop — only close when the gap is
    /// tiny next to the drawn length.
    private static func shouldCloseOpenContour(_ points: [CGPoint], tolerance: CGFloat) -> Bool {
        guard points.count >= 3, let first = points.first, let last = points.last else { return false }
        let gap = hypot(first.x - last.x, first.y - last.y)
        guard gap <= tolerance else { return false }
        var length: CGFloat = 0
        for index in 0..<(points.count - 1) {
            length += hypot(points[index + 1].x - points[index].x, points[index + 1].y - points[index].y)
        }
        return gap <= max(1, min(tolerance, length * 0.05))
    }

    private static func isLoopCandidate(_ stroke: VectorStroke) -> Bool {
        guard !stroke.isClosed, !stroke.isConstruction else { return false }
        switch stroke.shapeType {
        case .polyline, .arc:
            return stroke.points.count >= 2
        default:
            return false
        }
    }

    private static func pointsConnect(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= tolerance
    }
}
