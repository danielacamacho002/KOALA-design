//
//  PrintLayoutOverlayView.swift
//  vectr
//

import SwiftUI

private enum DragAxis {
    case free
    case horizontal
    case vertical
}

struct PrintLayoutOverlayView: View {
    @Bindable var document: VectrDocument
    var rotateModeActive: Bool = false
    /// When true, a drag locks onto the dominant axis after a short threshold.
    var axisLockEnabled: Bool = false
    var onChanged: () -> Void

    @State private var moveDragOriginTransform = PrintStrokeTransform.identity
    @State private var rotateDragOriginAngle: CGFloat = 0
    @State private var rotateDragOriginRotation: CGFloat = 0

    @State private var isMoveDragging = false
    @State private var dragAxis: DragAxis = .free
    @State private var dragStartBounds: CGRect = .null

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
                    if axisLockEnabled, isMoveDragging, dragAxis != .free, let bounds = selectedElementBounds() {
                        axisGuideline(
                            axis: dragAxis,
                            center: document.viewport.documentToView(CGPoint(x: bounds.midX, y: bounds.midY)),
                            size: geo.size
                        )
                    }
                    if let strokeID = document.printSelectedStrokeID,
                       let stroke = document.printLayoutStroke(with: strokeID) {
                        strokeSelectionOverlay(strokeID: strokeID, stroke: stroke)
                    } else if let textID = document.printSelectedTextID,
                              let element = document.textElement(with: textID) {
                        textSelectionOverlay(element: element)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .coordinateSpace(name: coordinateSpaceName)
    }

    @ViewBuilder
    private func strokeSelectionOverlay(strokeID: UUID, stroke: VectorStroke) -> some View {
        let transformed = document.transformedPrintStroke(stroke)
        let points = ShapeGeometry.renderPoints(for: transformed)
        selectionOverlay(
            elementID: strokeID,
            bbox: PrintLayoutCoordinateSpace.boundingRect(for: points)
        )
    }

    @ViewBuilder
    private func textSelectionOverlay(element: TextElement) -> some View {
        let corners = PrintLayoutCoordinateSpace.transformedTextCorners(
            element,
            transform: document.effectivePrintTransform(for: element.id)
        )
        selectionOverlay(
            elementID: element.id,
            bbox: PrintLayoutCoordinateSpace.boundingRect(for: corners)
        )
    }

    @ViewBuilder
    private func selectionOverlay(elementID: UUID, bbox: CGRect) -> some View {
        let center = CGPoint(x: bbox.midX, y: bbox.midY)
        let viewCenter = document.viewport.documentToView(center)
        let boxViewWidth = document.viewport.documentToView(distance: bbox.width)
        let boxViewHeight = document.viewport.documentToView(distance: bbox.height)

        // Draggable body: dragging anywhere inside the shape's bounds moves it.
        // A small minimum distance lets simple taps fall through for (de)selection.
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .contentShape(Rectangle())
            .frame(width: max(boxViewWidth, 24), height: max(boxViewHeight, 24))
            .position(viewCenter)
            .gesture(moveDrag(elementID: elementID, minimumDistance: 8))

        // Bounding box
        RoundedRectangle(cornerRadius: 2)
            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
            .frame(
                width: boxViewWidth,
                height: boxViewHeight
            )
            .position(viewCenter)
            .allowsHitTesting(false)

        // Move handle (center)
        Circle()
            .fill(Color.accentColor)
            .frame(width: centerHandleSize, height: centerHandleSize)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .position(viewCenter)
            .gesture(moveDrag(elementID: elementID))

        // Rotation handle — only shown when the user has explicitly entered
        // rotate mode from the command panel (not an always-on handle).
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
                .gesture(rotateDrag(elementID: elementID, center: center))
        }
    }

    private var centerHandleSize: CGFloat { 18 }

    private func moveDrag(elementID: UUID, minimumDistance: CGFloat = 0) -> some Gesture {
        DragGesture(minimumDistance: minimumDistance, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if !isMoveDragging {
                    isMoveDragging = true
                    moveDragOriginTransform = document.printTransform(for: elementID)
                    dragStartBounds = boundsForElement(elementID)
                    dragAxis = .free
                    document.beginInteractiveEdit()
                }

                // When axis lock is on, lock to a single axis once the drag
                // passes the threshold, then stay locked for the gesture.
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

                var transform = moveDragOriginTransform
                transform.translation = CGPoint(
                    x: moveDragOriginTransform.translation.x + delta.x,
                    y: moveDragOriginTransform.translation.y + delta.y
                )
                document.setPrintTransform(transform, for: elementID, recordUndo: false)
            }
            .onEnded { _ in
                moveDragOriginTransform = .identity
                isMoveDragging = false
                dragAxis = .free
                dragStartBounds = .null
                onChanged()
            }
    }

    private func rotateDrag(elementID: UUID, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let currentDoc = document.viewport.viewToDocument(value.location)
                if rotateDragOriginRotation == 0, rotateDragOriginAngle == 0 {
                    rotateDragOriginRotation = document.printTransform(for: elementID).rotation
                    rotateDragOriginAngle = atan2(currentDoc.y - center.y, currentDoc.x - center.x)
                    document.beginInteractiveEdit()
                }
                let angle = atan2(currentDoc.y - center.y, currentDoc.x - center.x)
                var transform = document.printTransform(for: elementID)
                transform.rotation = rotateDragOriginRotation + (angle - rotateDragOriginAngle)
                document.setPrintTransform(transform, for: elementID, recordUndo: false)
            }
            .onEnded { _ in
                rotateDragOriginAngle = 0
                rotateDragOriginRotation = 0
                onChanged()
            }
    }

    // MARK: - Axis lock + snapping

    private func boundsForElement(_ id: UUID) -> CGRect {
        if let stroke = document.printLayoutStroke(with: id) {
            let transformed = document.transformedPrintStroke(stroke)
            return PrintLayoutCoordinateSpace.boundingRect(
                for: ShapeGeometry.renderPoints(for: transformed)
            )
        }
        if let element = document.textElement(with: id) {
            let corners = PrintLayoutCoordinateSpace.transformedTextCorners(
                element,
                transform: document.effectivePrintTransform(for: id)
            )
            return PrintLayoutCoordinateSpace.boundingRect(for: corners)
        }
        return .null
    }

    private func selectedElementBounds() -> CGRect? {
        guard let id = document.printSelectedStrokeID ?? document.printSelectedTextID else { return nil }
        let bounds = boundsForElement(id)
        return bounds.isNull ? nil : bounds
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
