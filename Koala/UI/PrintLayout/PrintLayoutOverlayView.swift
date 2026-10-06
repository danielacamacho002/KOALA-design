//
//  PrintLayoutOverlayView.swift
//  Koala
//

import SwiftUI

private enum DragAxis {
    case free
    case horizontal
    case vertical
}

struct PrintLayoutOverlayView: View {
    @Bindable var document: KoalaDocument
    var rotateModeActive: Bool = false
    /// When true, a drag locks onto the dominant axis after a short threshold.
    var axisLockEnabled: Bool = false
    var onChanged: () -> Void
    var onSelectTap: (() -> Void)? = nil

    @State private var moveDragOriginTransforms: [UUID: PrintStrokeTransform] = [:]
    @State private var rotateDragOriginAngle: CGFloat = 0
    @State private var rotateDragOriginTransforms: [UUID: PrintStrokeTransform] = [:]
    @State private var rotateDragOriginCenters: [UUID: CGPoint] = [:]
    @State private var rotateGroupPivot: CGPoint = .zero

    @State private var isMoveDragging = false
    @State private var dragAxis: DragAxis = .free
    @State private var dragStartBounds: CGRect = .null
    @State private var dragDecided = false
    @State private var dragIsMarquee = false
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    private let handleSize: CGFloat = 22
    private let rotateHandleOffset: CGFloat = 36
    private let coordinateSpaceName = "printLayout"

    /// View-space movement (points) before the drag locks onto an axis.
    private let axisLockThreshold: CGFloat = 10
    /// View-space distance (points) within which an edge snaps to a print border.
    private let snapThreshold: CGFloat = 15

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if document.printLayout.activeTool == .select {
                    SingleTouchCanvasCatcher(
                        onTap: { handleSelectTap(at: $0) },
                        onDragChanged: { handleBackgroundDragChanged($0) },
                        onDragEnded: { handleBackgroundDragEnded($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let rect = marqueeViewRect {
                        marqueeBox(rect)
                    }

                    if axisLockEnabled, isMoveDragging, dragAxis != .free, let bounds = selectedElementBounds() {
                        axisGuideline(
                            axis: dragAxis,
                            center: document.viewport.documentToView(CGPoint(x: bounds.midX, y: bounds.midY)),
                            size: geo.size
                        )
                    }

                    if let bbox = selectedElementBounds() {
                        selectionChrome(bbox: bbox)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .coordinateSpace(name: coordinateSpaceName)
    }

    @ViewBuilder
    private func selectionChrome(bbox: CGRect) -> some View {
        let center = CGPoint(x: bbox.midX, y: bbox.midY)
        let viewCenter = document.viewport.documentToView(center)
        let boxViewWidth = document.viewport.documentToView(distance: bbox.width)
        let boxViewHeight = document.viewport.documentToView(distance: bbox.height)

        RoundedRectangle(cornerRadius: 2)
            .stroke(
                Color.accentColor.opacity(document.printSelectionCount > 1 ? 0.85 : 0.5),
                style: StrokeStyle(
                    lineWidth: document.printSelectionCount > 1 ? 1.5 : 1,
                    dash: document.printSelectionCount > 1 ? [5, 3] : []
                )
            )
            .frame(width: boxViewWidth, height: boxViewHeight)
            .position(viewCenter)
            .allowsHitTesting(false)

        Circle()
            .fill(Color.accentColor)
            .frame(width: centerHandleSize, height: centerHandleSize)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .position(viewCenter)
            .allowsHitTesting(false)

        if rotateModeActive {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: handleSize, height: handleSize)
                .background(Circle().fill(Color.orange))
                .position(
                    x: viewCenter.x,
                    y: viewCenter.y - document.viewport.documentToView(distance: rotateHandleOffset)
                )
                .gesture(rotateDrag(center: center))
        }
    }

    private var centerHandleSize: CGFloat { 18 }

    private func handleSelectTap(at viewPoint: CGPoint) {
        onSelectTap?()
        let documentPoint = document.viewport.viewToDocument(viewPoint)
        let threshold = document.viewport.viewToDocument(distance: 16)
        document.handlePrintSelectTap(near: documentPoint, threshold: threshold)
    }

    /// Background drag that either moves the current selection (when it starts over
    /// it) or draws a marquee (when it starts on empty grid).
    private func handleBackgroundDragChanged(_ value: OverlayPointerValue) {
        if !dragDecided {
            dragDecided = true
            let startDoc = document.viewport.viewToDocument(value.startLocation)
            let threshold = document.viewport.viewToDocument(distance: 12)
            dragIsMarquee = !document.printSelectionContains(point: startDoc, threshold: threshold)
            if dragIsMarquee {
                marqueeStart = value.startLocation
            } else {
                beginMoveDrag()
            }
        }
        if dragIsMarquee {
            marqueeCurrent = value.location
        } else {
            applyMoveDrag(value)
        }
    }

    private func handleBackgroundDragEnded(_ value: OverlayPointerValue) {
        if dragIsMarquee {
            if let rect = marqueeDocRect(start: value.startLocation, current: value.location) {
                document.selectPrintElements(in: rect)
            }
            marqueeStart = nil
            marqueeCurrent = nil
        } else {
            finishMoveDrag()
        }
        dragDecided = false
        dragIsMarquee = false
        onChanged()
    }

    private func beginMoveDrag() {
        isMoveDragging = true
        moveDragOriginTransforms = Dictionary(
            uniqueKeysWithValues: document.printSelectedIDs.map { ($0, document.printTransform(for: $0)) }
        )
        dragStartBounds = selectedElementBounds() ?? .null
        dragAxis = .free
        document.beginInteractiveEdit()
    }

    private func applyMoveDrag(_ value: OverlayPointerValue) {
        if axisLockEnabled, dragAxis == .free {
            let moved = value.translation
            if hypot(moved.width, moved.height) > axisLockThreshold {
                dragAxis = abs(moved.width) > abs(moved.height) ? .horizontal : .vertical
            }
        }

        let startDoc = document.viewport.viewToDocument(value.startLocation)
        let currentDoc = document.viewport.viewToDocument(value.location)
        var delta = CGPoint(
            x: currentDoc.x - startDoc.x,
            y: currentDoc.y - startDoc.y
        )

        if axisLockEnabled {
            switch dragAxis {
            case .horizontal: delta.y = 0
            case .vertical: delta.x = 0
            case .free: break
            }

            if dragAxis != .free, !dragStartBounds.isNull {
                delta = snappedDelta(delta, axis: dragAxis)
            }
        }

        var updates: [UUID: PrintStrokeTransform] = [:]
        for (id, origin) in moveDragOriginTransforms {
            var transform = origin
            transform.translation = CGPoint(
                x: origin.translation.x + delta.x,
                y: origin.translation.y + delta.y
            )
            updates[id] = transform
        }
        document.setPrintTransforms(updates, recordUndo: false)
    }

    private func finishMoveDrag() {
        moveDragOriginTransforms = [:]
        isMoveDragging = false
        dragAxis = .free
        dragStartBounds = .null
    }

    private func rotateDrag(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let currentDoc = document.viewport.viewToDocument(value.location)
                if rotateDragOriginTransforms.isEmpty {
                    rotateGroupPivot = center
                    rotateDragOriginAngle = atan2(currentDoc.y - center.y, currentDoc.x - center.x)
                    rotateDragOriginTransforms = Dictionary(
                        uniqueKeysWithValues: document.printSelectedIDs.map { ($0, document.printTransform(for: $0)) }
                    )
                    rotateDragOriginCenters = Dictionary(
                        uniqueKeysWithValues: document.printSelectedIDs.compactMap { id in
                            let bounds = boundsForElement(id)
                            guard !bounds.isNull else { return nil }
                            return (id, CGPoint(x: bounds.midX, y: bounds.midY))
                        }
                    )
                    document.beginInteractiveEdit()
                }
                let angle = atan2(currentDoc.y - rotateGroupPivot.y, currentDoc.x - rotateGroupPivot.x)
                let delta = angle - rotateDragOriginAngle
                document.rotatePrintSelection(
                    by: delta,
                    around: rotateGroupPivot,
                    originTransforms: rotateDragOriginTransforms,
                    originCenters: rotateDragOriginCenters,
                    recordUndo: false
                )
            }
            .onEnded { _ in
                rotateDragOriginAngle = 0
                rotateDragOriginTransforms = [:]
                rotateDragOriginCenters = [:]
                rotateGroupPivot = .zero
                onChanged()
            }
    }

    // MARK: - Axis lock + snapping

    private func boundsForElement(_ id: UUID) -> CGRect {
        document.printBounds(for: id)
    }

    private func selectedElementBounds() -> CGRect? {
        document.printSelectionBoundingBox()
    }

    private var marqueeViewRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    private func marqueeDocRect(start: CGPoint, current: CGPoint) -> CGRect? {
        let a = document.viewport.viewToDocument(start)
        let b = document.viewport.viewToDocument(current)
        let rect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
        guard rect.width > 0.5 || rect.height > 0.5 else { return nil }
        return rect
    }

    @ViewBuilder
    private func marqueeBox(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.08))
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    /// Snaps the dragged element's bounding-box edges flush to the nearest inner
    /// print-limit border along the locked axis, when within the snap threshold.
    private func snappedDelta(_ delta: CGPoint, axis: DragAxis) -> CGPoint {
        let rects = PrintPageGridEngine.printableRects(for: document.printLayout)
        guard !rects.isEmpty else { return delta }
        let tolerance = document.viewport.viewToDocument(distance: snapThreshold)

        var delta = delta
        var bestDistance = tolerance
        var bestAdjust: CGFloat = 0

        switch axis {
        case .horizontal:
            let edges = [dragStartBounds.minX + delta.x, dragStartBounds.maxX + delta.x]
            let lines = rects.flatMap { [$0.minX, $0.maxX] }
            for edge in edges {
                for line in lines where abs(line - edge) <= bestDistance {
                    bestDistance = abs(line - edge)
                    bestAdjust = line - edge
                }
            }
            delta.x += bestAdjust
        case .vertical:
            let edges = [dragStartBounds.minY + delta.y, dragStartBounds.maxY + delta.y]
            let lines = rects.flatMap { [$0.minY, $0.maxY] }
            for edge in edges {
                for line in lines where abs(line - edge) <= bestDistance {
                    bestDistance = abs(line - edge)
                    bestAdjust = line - edge
                }
            }
            delta.y += bestAdjust
        case .free:
            break
        }
        return delta
    }

    @ViewBuilder
    private func axisGuideline(axis: DragAxis, center: CGPoint, size: CGSize) -> some View {
        Path { path in
            switch axis {
            case .horizontal:
                path.move(to: CGPoint(x: 0, y: center.y))
                path.addLine(to: CGPoint(x: size.width, y: center.y))
            case .vertical:
                path.move(to: CGPoint(x: center.x, y: 0))
                path.addLine(to: CGPoint(x: center.x, y: size.height))
            case .free:
                break
            }
        }
        .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        .allowsHitTesting(false)
    }
}
