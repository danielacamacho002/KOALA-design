//
//  CurveDraftSession.swift
//  vectr
//

import CoreGraphics
import Foundation
import Observation

/// An open curve the draft is extending. Anchors in the session run toward the live end.
nonisolated struct CurveContinuation: Equatable, Sendable {
    var strokeID: UUID
    /// Handles aligned with the seeded anchors, already flipped when `reversed` is true.
    var originalHandles: [CurveHandle]
    var reversed: Bool
    /// Seeded anchors undo must not remove.
    var protectedCount: Int
}

/// Finished draft, including the stroke it extends when the pencil added points.
nonisolated struct CurveDraftFinish: Equatable, Sendable {
    var anchors: [CGPoint]
    var continuation: CurveContinuation?
}

/// In-progress Bézier curve, kept off the document undo stack until the curve is finished.
/// Each Pencil stroke is one undoable segment (one or two anchors).
@Observable
final class CurveDraftSession {
    private(set) var anchors: [CGPoint] = []
    private(set) var continuation: CurveContinuation?
    private(set) var revision = 0

    private var segmentPointCounts: [Int] = []
    private var redoSegments: [[CGPoint]] = []
    private var isDragging = false
    private var prefersDraftRedo = false

    weak var canvas: DrawingCanvasUIView?

    var canUndo: Bool {
        isDragging || !segmentPointCounts.isEmpty || (continuation == nil && !anchors.isEmpty)
    }

    /// True when a tap may load an open curve. A tail already drawn in this session still finishes.
    var canResume: Bool {
        !isDragging && segmentPointCounts.isEmpty
    }

    var continuationStrokeID: UUID? {
        continuation?.strokeID
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

    /// Loads an open curve so the next pencil stroke appends at `anchors.last`.
    func beginContinuation(
        strokeID: UUID,
        anchors: [CGPoint],
        handles: [CurveHandle],
        reversed: Bool
    ) {
        self.anchors = anchors
        continuation = CurveContinuation(
            strokeID: strokeID,
            originalHandles: handles,
            reversed: reversed,
            protectedCount: anchors.count
        )
        segmentPointCounts.removeAll()
        redoSegments.removeAll()
        isDragging = false
        prefersDraftRedo = false
        revision += 1
        canvas?.refreshCurvePreview()
    }

    /// Nil when the draft is empty, or when a resumed curve gained no new points.
    func makeFinish() -> CurveDraftFinish? {
        let protected = continuation?.protectedCount ?? 0
        if continuation != nil, anchors.count <= protected {
            return nil
        }
        guard anchors.count >= 2 else { return nil }
        return CurveDraftFinish(anchors: anchors, continuation: continuation)
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
            guard continuation == nil, !anchors.isEmpty else { return false }
            redoSegments.append(anchors)
            anchors.removeAll()
            revision += 1
            return true
        }
        let protected = continuation?.protectedCount ?? 0
        let available = anchors.count - protected
        guard available > 0 else { return false }
        let count = min(segmentPointCounts.removeLast(), available)
        guard count > 0 else { return false }
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
        continuation = nil
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
