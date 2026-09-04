//
//  CurveDraftSession.swift
//  vectr
//

import CoreGraphics
import Foundation
import Observation

/// In-progress Bézier curve, kept off the document undo stack until the curve is finished.
/// Each Pencil stroke is one undoable segment (one or two anchors).
@Observable
final class CurveDraftSession {
    private(set) var anchors: [CGPoint] = []
    private(set) var revision = 0

    private var segmentPointCounts: [Int] = []
    private var redoSegments: [[CGPoint]] = []
    private var isDragging = false
    private var prefersDraftRedo = false

    weak var canvas: DrawingCanvasUIView?

    var canUndo: Bool {
        isDragging || !segmentPointCounts.isEmpty || !anchors.isEmpty
    }

    var canRedo: Bool {
        prefersDraftRedo && !redoSegments.isEmpty
    }

    func attachCanvas(_ canvas: DrawingCanvasUIView) {
        self.canvas = canvas
    }

    func detachCanvas(_ canvas: DrawingCanvasUIView) {
        if self.canvas === canvas {
            self.canvas = nil
        }
    }

    func beginDrag() {
        isDragging = true
        revision += 1
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        revision += 1
    }

    func appendSegment(start: CGPoint, end: CGPoint, connectTolerance: CGFloat) {
        let before = anchors.count
        if anchors.isEmpty {
            anchors.append(start)
        } else if let last = anchors.last,
                  hypot(start.x - last.x, start.y - last.y) > connectTolerance {
            anchors.append(start)
        }
        if let last = anchors.last,
           hypot(end.x - last.x, end.y - last.y) > 0.0001 {
            anchors.append(end)
        }
        recordAddedPoints(anchors.count - before)
    }

    @discardableResult
    func performUndo() -> Bool {
        if let canvas {
            guard canvas.undoLastCurveSegment() else { return false }
            prefersDraftRedo = true
            revision += 1
            return true
        }
        guard undoCommittedSegment() else { return false }
        prefersDraftRedo = true
        return true
    }

    @discardableResult
    func performRedo() -> Bool {
        if let canvas {
            guard canvas.redoLastCurveSegment() else { return false }
            return true
        }
        return redoCommittedSegment()
    }

    @discardableResult
    func undoCommittedSegment() -> Bool {
        if segmentPointCounts.isEmpty {
            guard !anchors.isEmpty else { return false }
            redoSegments.append(anchors)
            anchors.removeAll()
            revision += 1
            return true
        }
        let count = min(segmentPointCounts.removeLast(), anchors.count)
        redoSegments.append(Array(anchors.suffix(count)))
        anchors.removeLast(count)
        revision += 1
        return true
    }

    @discardableResult
    func redoCommittedSegment() -> Bool {
        guard let points = redoSegments.popLast() else { return false }
        anchors.append(contentsOf: points)
        segmentPointCounts.append(points.count)
        revision += 1
        return true
    }

    func discardRedo() {
        guard !redoSegments.isEmpty || prefersDraftRedo else { return }
        redoSegments.removeAll()
        prefersDraftRedo = false
        revision += 1
    }

    func reset() {
        anchors.removeAll()
        segmentPointCounts.removeAll()
        redoSegments.removeAll()
        isDragging = false
        prefersDraftRedo = false
        revision += 1
    }

    private func recordAddedPoints(_ added: Int) {
        isDragging = false
        guard added > 0 else { return }
        segmentPointCounts.append(added)
        redoSegments.removeAll()
        prefersDraftRedo = false
        revision += 1
    }
}
