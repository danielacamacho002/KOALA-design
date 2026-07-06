//
//  CanvasOverlayView.swift
//  vectr
//

import SwiftUI

/// Handles node editing, multi-anchor move, scale, trim, fillet, and command-preview point dragging.
struct CanvasOverlayView: View {
    @Bindable var document: VectrDocument
    @Bindable var commandSession: ShapeCommandSession
    var onChanged: () -> Void

    @State private var nodeDragOriginPoints: [CGPoint] = []
    @State private var curveHandleDragActive = false
    @State private var moveDragOriginPoints: [CGPoint] = []
    @State private var commandDragOriginPoints: [CGPoint] = []
    @State private var scaleDragOriginPoints: [CGPoint] = []
    @State private var scaleDragOriginHandles: [CurveHandle]? = nil
    @State private var scaleDragOriginCenter: CGPoint = .zero
    @State private var scaleDragOriginCorner: CGPoint = .zero
    @State private var scaleDragOriginCornerDist: CGFloat = 1
    @State private var centerDragOriginPoints: [CGPoint] = []
    @State private var filletDragStrokeID: UUID?
    @State private var filletDragCornerIndex: Int?
    @State private var filletDragCornerPoint: CGPoint = .zero
    @State private var filletDragTargetCornerIndices: Set<Int> = []
    @State private var filletDragDidMove = false
    @State private var rotateDragOriginStroke: VectorStroke?
    @State private var rotateDragPreviousAngle: CGFloat = 0
    @State private var rotateDragAccumulated: CGFloat = 0
    @State private var rotateDragPivot: CGPoint = .zero

    private let handleSize: CGFloat = 22
    private let centerHandleSize: CGFloat = 16
    private let coordinateSpaceName = "editor"
    private let filletDragThreshold: CGFloat = 6
    private let rotateHandleOffset: CGFloat = 36
    /// Invisible finger/Pencil target around each anchor handle so small squares are easy to hit.
    private let anchorTouchTargetSize: CGFloat = 44
    /// Dead-zone before an individual anchor starts dragging, so taps/double-taps never nudge it.
    private let anchorDragThreshold: CGFloat = 6

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if commandSession.isActive {
                    commandPreviewHandles
                } else if document.activeCategory == .move {
                    strokeMoveOverlay
                } else if document.activeCategory == .scale {
                    scaleHandles
                } else if document.activeCategory == .trim {
                    trimOverlay
                } else if document.activeCategory == .fillet {
                    filletOverlay
                } else if document.activeCategory == .addAnchor {
                    addAnchorOverlay
                } else if document.selectedStrokeID != nil,
                          !document.dimensionsVisible,
                          document.activeCategory != .delete {
                    strokeNodeHandles
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .coordinateSpace(name: coordinateSpaceName)
    }

    // MARK: - Command preview

    @ViewBuilder
    private var commandPreviewHandles: some View {
        ForEach(Array(commandSession.controlPoints.enumerated()), id: \.offset) { index, point in
            handleView(style: .command)
                .position(document.viewport.documentToView(point))
                .highPriorityGesture(commandPointDrag(index: index))
        }
    }

    private func commandPointDrag(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if commandDragOriginPoints.isEmpty {
                    commandDragOriginPoints = commandSession.controlPoints
                }
                let docPoint = document.viewport.viewToDocument(value.location)
                let final = snapCommandControlPoint(docPoint)
                commandSession.movePoint(at: index, to: final)
                onChanged()
            }
            .onEnded { _ in
                commandDragOriginPoints = []
            }
    }

    private var drawingSnapEnabled: Bool {
        document.snapEnabled && document.grid.snapEnabled
    }

    private func snapCommandControlPoint(_ raw: CGPoint) -> CGPoint {
        let snapped = snapDrawingPoint(
            raw,
            grid: document.grid,
            settings: document.settings,
            enabled: drawingSnapEnabled
        )
        let projected = ShapeGeometry.projectCommandPoint(
            snapped,
            controlPoints: commandSession.controlPoints,
            category: commandSession.category,
            circleVariant: commandSession.circleVariant,
            rectangleVariant: commandSession.rectangleVariant
        )
        return snapDrawingControlPoint(
            raw: snapped,
            projected: projected,
            grid: document.grid,
            settings: document.settings,
            enabled: drawingSnapEnabled
        )
    }

    // MARK: - Selected stroke (edit nodes)

    @ViewBuilder
    private var strokeNodeHandles: some View {
        if let strokeID = document.selectedStrokeID,
           let stroke = document.stroke(with: strokeID) {
            let handles = ShapeGeometry.handlePoints(for: stroke)
            if stroke.shapeType == .curve,
               let curveHandles = stroke.curveHandles,
               curveHandles.count == stroke.points.count {
                curveTangentHandles(strokeID: strokeID, stroke: stroke, curveHandles: curveHandles)
            }
            ForEach(Array(handles.enumerated()), id: \.offset) { index, point in
                handleView(style: .edit)
                    .position(document.viewport.documentToView(point))
                    .highPriorityGesture(strokeNodeDrag(strokeID: strokeID, index: index))
            }
            centerHandle(strokeID: strokeID, stroke: stroke)
        }
    }

    // MARK: - Curve tangent handles

    @ViewBuilder
    private func curveTangentHandles(
        strokeID: UUID,
        stroke: VectorStroke,
        curveHandles: [CurveHandle]
    ) -> some View {
        let count = stroke.points.count
        ForEach(Array(stroke.points.indices), id: \.self) { index in
            let anchor = stroke.points[index]
            let anchorView = document.viewport.documentToView(anchor)

            if index < count - 1 {
                let out = CGPoint(
                    x: anchor.x + curveHandles[index].outOffset.x,
                    y: anchor.y + curveHandles[index].outOffset.y
                )
                let outView = document.viewport.documentToView(out)
                tangentConnector(from: anchorView, to: outView)
                tangentDot()
                    .position(outView)
                    .highPriorityGesture(curveTangentDrag(strokeID: strokeID, index: index, isOut: true))
            }

            if index > 0 {
                let inControl = CGPoint(
                    x: anchor.x + curveHandles[index].inOffset.x,
                    y: anchor.y + curveHandles[index].inOffset.y
                )
                let inView = document.viewport.documentToView(inControl)
                tangentConnector(from: anchorView, to: inView)
                tangentDot()
                    .position(inView)
                    .highPriorityGesture(curveTangentDrag(strokeID: strokeID, index: index, isOut: false))
            }
        }
    }

    @ViewBuilder
    private func tangentConnector(from: CGPoint, to: CGPoint) -> some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(Color.teal.opacity(0.7), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func tangentDot() -> some View {
        Circle()
            .fill(Color.teal)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .frame(width: anchorTouchTargetSize, height: anchorTouchTargetSize)
            .contentShape(Rectangle())
    }

    private func curveTangentDrag(strokeID: UUID, index: Int, isOut: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                guard var stroke = document.stroke(with: strokeID),
                      stroke.shapeType == .curve,
                      var handles = stroke.curveHandles,
                      handles.indices.contains(index),
                      stroke.points.indices.contains(index) else { return }
                if !curveHandleDragActive {
                    curveHandleDragActive = true
                    document.beginInteractiveEdit()
                }
                // Tangent handles are exempt from grid snapping so curvature can be tuned freely.
                let docPoint = document.viewport.viewToDocument(value.location)
                let anchor = stroke.points[index]
                let offset = CGPoint(x: docPoint.x - anchor.x, y: docPoint.y - anchor.y)
                // Mirror the opposite handle so the pair stays a single straight tangent line.
                let mirrored = CGPoint(x: -offset.x, y: -offset.y)
                if isOut {
                    handles[index].outOffset = offset
                    handles[index].inOffset = mirrored
                } else {
                    handles[index].inOffset = offset
                    handles[index].outOffset = mirrored
                }
                stroke.curveHandles = handles
                document.updateStroke(stroke, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                let didEdit = curveHandleDragActive
                curveHandleDragActive = false
                guard didEdit else { return }
                onChanged()
            }
    }

    private func strokeNodeDrag(strokeID: UUID, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if nodeDragOriginPoints.isEmpty {
                    nodeDragOriginPoints = document.stroke(with: strokeID)?.points ?? []
                    document.beginInteractiveEdit()
                }
                guard var stroke = document.stroke(with: strokeID) else { return }
                let docPoint = document.viewport.viewToDocument(value.location)
                if stroke.shapeType == .circle {
                    stroke.points = ShapeGeometry.updateCircleHandle(at: index, to: docPoint, stroke: stroke)
                } else if stroke.shapeType == .ellipse {
                    stroke.points = ShapeGeometry.updateEllipseHandle(at: index, to: docPoint, stroke: stroke)
                } else {
                    stroke.points[index] = docPoint
                }
                document.updateStroke(stroke, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                let didEdit = !nodeDragOriginPoints.isEmpty
                nodeDragOriginPoints = []
                guard didEdit else { return }
                document.reconcileIntersectionAnchors(around: [strokeID])
                onChanged()
            }
    }

    // MARK: - Move (multi-anchor)

    @ViewBuilder
    private var strokeMoveOverlay: some View {
        if let strokeID = document.selectedStrokeID,
           let stroke = document.stroke(with: strokeID) {
            let handles = ShapeGeometry.handlePoints(for: stroke)
            let pivot = ShapeGeometry.rotationPivot(
                for: stroke,
                anchorIndex: document.moveRotationPivotAnchorIndex
            )

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName))
                        .onChanged { value in
                            handleMoveDragChanged(
                                strokeID: strokeID,
                                stroke: stroke,
                                value: value,
                                anchorIndex: nil
                            )
                        }
                        .onEnded { _ in
                            finishMoveDrag(strokeID: strokeID)
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                        .onEnded { value in
                            handleMoveBackgroundTap(at: value.location)
                        }
                )

            if let pivot {
                pivotMarker(at: pivot)
                rotationHandle(strokeID: strokeID, pivot: pivot)
            }

            ForEach(Array(handles.enumerated()), id: \.offset) { index, point in
                let selected = document.selectedAnchorIndices.contains(index)
                let isPivot = document.moveRotationPivotAnchorIndex == index
                ZStack {
                    handleView(style: selected ? .selectedAnchor : .move)
                    if isPivot {
                        Circle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: handleSize + 6, height: handleSize + 6)
                    }
                }
                .frame(width: anchorTouchTargetSize, height: anchorTouchTargetSize)
                .contentShape(Rectangle())
                .position(document.viewport.documentToView(point))
                .highPriorityGesture(anchorMoveDrag(strokeID: strokeID, stroke: stroke, anchorIndex: index))
                .onTapGesture(count: 2) {
                    document.toggleAnchorSelection(at: index)
                    onChanged()
                }
                .onTapGesture {
                    document.selectSingleAnchor(at: index)
                    onChanged()
                }
            }

            if stroke.shapeType == .curve,
               let curveHandles = stroke.curveHandles,
               curveHandles.count == stroke.points.count {
                curveTangentHandles(strokeID: strokeID, stroke: stroke, curveHandles: curveHandles)
            }

            centerHandle(strokeID: strokeID, stroke: stroke)
        }
    }

    @ViewBuilder
    private func pivotMarker(at pivot: CGPoint) -> some View {
        Circle()
            .stroke(Color.yellow.opacity(0.8), lineWidth: 1.5)
            .frame(width: 10, height: 10)
            .position(document.viewport.documentToView(pivot))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func rotationHandle(strokeID: UUID, pivot: CGPoint) -> some View {
        let viewPivot = document.viewport.documentToView(pivot)
        let handlePosition = CGPoint(
            x: viewPivot.x,
            y: viewPivot.y - document.viewport.documentToView(distance: rotateHandleOffset)
        )

        Path { path in
            path.move(to: viewPivot)
            path.addLine(to: handlePosition)
        }
        .stroke(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)

        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: handleSize, height: handleSize)
            .background(Circle().fill(Color.orange))
            .position(handlePosition)
            .highPriorityGesture(rotateDrag(strokeID: strokeID, pivot: pivot))
    }

    private func rotateDrag(strokeID: UUID, pivot: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let currentDoc = document.viewport.viewToDocument(value.location)
                if rotateDragOriginStroke == nil {
                    rotateDragOriginStroke = document.stroke(with: strokeID)
                    rotateDragPivot = pivot
                    rotateDragPreviousAngle = atan2(currentDoc.y - pivot.y, currentDoc.x - pivot.x)
                    rotateDragAccumulated = 0
                    document.beginInteractiveEdit()
                }
                guard let originStroke = rotateDragOriginStroke else { return }
                let angle = atan2(currentDoc.y - rotateDragPivot.y, currentDoc.x - rotateDragPivot.x)
                // Accumulate the shortest-arc increment each frame so crossing the
                // -pi/pi boundary does not snap the rotation by ~360 degrees.
                let rawStep = angle - rotateDragPreviousAngle
                let step = atan2(sin(rawStep), cos(rawStep))
                rotateDragAccumulated += step
                rotateDragPreviousAngle = angle
                let rotated = ShapeGeometry.rotatedStroke(
                    originStroke,
                    around: rotateDragPivot,
                    by: rotateDragAccumulated
                )
                document.updateStroke(rotated, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                let didEdit = rotateDragOriginStroke != nil
                rotateDragOriginStroke = nil
                rotateDragPreviousAngle = 0
                rotateDragAccumulated = 0
                guard didEdit else { return }
                document.reconcileIntersectionAnchors(around: [strokeID])
                onChanged()
            }
    }

    private func applyMove(strokeID: UUID, stroke: VectorStroke, delta: CGPoint) {
        guard !moveDragOriginPoints.isEmpty else { return }
        let indices = document.selectedAnchorIndices

        if indices.isEmpty {
            let moved = moveDragOriginPoints.map {
                CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
            }
            document.setStrokePoints(id: strokeID, points: moved, recordUndo: false)
            return
        }

        var updated = stroke
        for index in indices.sorted() where moveDragOriginPoints.indices.contains(index) {
            let origin = moveDragOriginPoints[index]
            let moved = CGPoint(x: origin.x + delta.x, y: origin.y + delta.y)
            if updated.shapeType == .circle {
                updated.points = ShapeGeometry.updateCircleHandle(at: index, to: moved, stroke: updated)
            } else if updated.shapeType == .ellipse {
                updated.points = ShapeGeometry.updateEllipseHandle(at: index, to: moved, stroke: updated)
            } else {
                updated.points[index] = moved
            }
        }
        document.updateStroke(updated, recordUndo: false)
    }

    private func anchorMoveDrag(strokeID: UUID, stroke: VectorStroke, anchorIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: anchorDragThreshold, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                handleMoveDragChanged(
                    strokeID: strokeID,
                    stroke: stroke,
                    value: value,
                    anchorIndex: anchorIndex
                )
            }
            .onEnded { _ in
                finishMoveDrag(strokeID: strokeID)
            }
    }

    private func handleMoveDragChanged(
        strokeID: UUID,
        stroke: VectorStroke,
        value: DragGesture.Value,
        anchorIndex: Int?
    ) {
        if moveDragOriginPoints.isEmpty {
            moveDragOriginPoints = ShapeGeometry.handlePoints(for: stroke)
            if let anchorIndex, document.selectedAnchorIndices.isEmpty {
                document.selectedAnchorIndices = [anchorIndex]
            }
            document.beginInteractiveEdit()
        }
        let delta = documentDelta(from: value.translation)
        applyMove(strokeID: strokeID, stroke: stroke, delta: delta)
        onChanged()
    }

    private func finishMoveDrag(strokeID: UUID) {
        let didEdit = !moveDragOriginPoints.isEmpty
        moveDragOriginPoints = []
        guard didEdit else { return }
        document.reconcileIntersectionAnchors(around: [strokeID])
        onChanged()
    }

    /// A quick tap on the empty canvas (not on an anchor handle) clears every anchor
    /// selection and re-runs stroke hit testing so nothing stays stuck selected.
    private func handleMoveBackgroundTap(at viewPoint: CGPoint) {
        document.clearAnchorSelection()
        let threshold = document.viewport.viewToDocument(distance: 16)
        let documentPoint = document.viewport.viewToDocument(viewPoint)
        _ = document.selectStroke(near: documentPoint, threshold: threshold)
        onChanged()
    }

    // MARK: - Trim

    @ViewBuilder
    private var trimOverlay: some View {
        if let strokeID = document.selectedStrokeID,
           let stroke = document.stroke(with: strokeID) {
            let handles = ShapeGeometry.handlePoints(for: stroke)
            let edgeCount = stroke.isClosed ? handles.count : max(handles.count - 1, 0)

            ForEach(Array(handles.enumerated()), id: \.offset) { index, point in
                handleView(style: .trim)
                    .position(document.viewport.documentToView(point))
                    .onTapGesture {
                        document.deleteStrokePoint(at: index)
                        onChanged()
                    }
            }

            ForEach(0..<edgeCount, id: \.self) { edgeIndex in
                let start = handles[edgeIndex]
                let end = handles[(edgeIndex + 1) % handles.count]
                let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                if stroke.shapeType != .circle, stroke.shapeType != .ellipse {
                    Capsule()
                        .fill(Color.red.opacity(0.45))
                        .frame(width: 28, height: 10)
                        .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
                        .position(document.viewport.documentToView(mid))
                        .onTapGesture {
                            document.deleteStrokeEdge(at: edgeIndex)
                            onChanged()
                        }
                }
            }

            centerHandle(strokeID: strokeID, stroke: stroke)
        }
    }

    // MARK: - Add Anchor

    @ViewBuilder
    private var addAnchorOverlay: some View {
        if let strokeID = document.selectedStrokeID,
           let stroke = document.stroke(with: strokeID),
           AnchorPointEngine.canEditAnchors(on: stroke) {
            let handles = ShapeGeometry.handlePoints(for: stroke)

            ForEach(Array(handles.enumerated()), id: \.offset) { _, point in
                handleView(style: .addAnchor)
                    .position(document.viewport.documentToView(point))
            }

            centerHandle(strokeID: strokeID, stroke: stroke)
        }
    }

    // MARK: - Fillet

    @ViewBuilder
    private var filletOverlay: some View {
        if let strokeID = document.selectedStrokeID,
           let stroke = document.stroke(with: strokeID) {
            let handles = ShapeGeometry.handlePoints(for: stroke)
            let cornerIndices = ShapeGeometry.filletCornerIndices(for: stroke)
            ForEach(cornerIndices, id: \.self) { index in
                let point = handles[index]
                let selected = document.selectedFilletCornerIndices.contains(index)
                handleView(style: selected ? .selectedAnchor : .fillet)
                    .position(document.viewport.documentToView(point))
                    .highPriorityGesture(
                        filletCornerGesture(
                            strokeID: strokeID,
                            cornerIndex: index,
                            cornerPoint: point
                        )
                    )
            }

            centerHandle(strokeID: strokeID, stroke: stroke)
        }
    }

    private func filletCornerGesture(strokeID: UUID, cornerIndex: Int, cornerPoint: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if filletDragCornerIndex == nil {
                    filletDragStrokeID = strokeID
                    filletDragCornerIndex = cornerIndex
                    filletDragCornerPoint = cornerPoint
                    if document.selectedFilletCornerIndices.contains(cornerIndex),
                       !document.selectedFilletCornerIndices.isEmpty {
                        filletDragTargetCornerIndices = document.selectedFilletCornerIndices
                    } else {
                        filletDragTargetCornerIndices = [cornerIndex]
                    }
                }

                guard filletDragStrokeID == strokeID,
                      filletDragCornerIndex == cornerIndex else { return }

                let moved = hypot(value.translation.width, value.translation.height)
                guard moved >= filletDragThreshold else { return }

                if !filletDragDidMove {
                    filletDragDidMove = true
                    document.beginInteractiveEdit()
                    document.selectedFilletCornerIndices = filletDragTargetCornerIndices
                }

                let docPoint = document.viewport.viewToDocument(value.location)
                let radius = hypot(
                    docPoint.x - filletDragCornerPoint.x,
                    docPoint.y - filletDragCornerPoint.y
                )
                document.applyFilletToSelected(
                    radius: radius,
                    cornerIndices: filletDragTargetCornerIndices,
                    recordUndo: false
                )
                onChanged()
            }
            .onEnded { _ in
                guard filletDragStrokeID == strokeID,
                      filletDragCornerIndex == cornerIndex else {
                    resetFilletDragState()
                    return
                }

                if filletDragDidMove {
                    document.selectedFilletCornerIndices = filletDragTargetCornerIndices
                } else {
                    document.toggleFilletCornerSelection(at: cornerIndex)
                }
                onChanged()
                resetFilletDragState()
            }
    }

    private func resetFilletDragState() {
        filletDragStrokeID = nil
        filletDragCornerIndex = nil
        filletDragCornerPoint = .zero
        filletDragTargetCornerIndices = []
        filletDragDidMove = false
    }

    // MARK: - Scale

    @ViewBuilder
    private var scaleHandles: some View {
        if let strokeID = document.selectedStrokeID,
           let stroke = document.stroke(with: strokeID),
           let bbox = stroke.boundingBox() {
            let corners = [
                CGPoint(x: bbox.minX, y: bbox.minY),
                CGPoint(x: bbox.maxX, y: bbox.minY),
                CGPoint(x: bbox.maxX, y: bbox.maxY),
                CGPoint(x: bbox.minX, y: bbox.maxY)
            ]
            ForEach(Array(corners.enumerated()), id: \.offset) { index, corner in
                handleView(style: .edit)
                    .position(document.viewport.documentToView(corner))
                    .highPriorityGesture(scaleDrag(strokeID: strokeID, cornerIndex: index, bbox: bbox))
            }
        }
    }

    private func scaleDrag(strokeID: UUID, cornerIndex: Int, bbox: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if scaleDragOriginPoints.isEmpty {
                    scaleDragOriginPoints = document.stroke(with: strokeID)?.points ?? []
                    scaleDragOriginHandles = document.stroke(with: strokeID)?.curveHandles
                    scaleDragOriginCenter = CGPoint(x: bbox.midX, y: bbox.midY)
                    let corners = [
                        CGPoint(x: bbox.minX, y: bbox.minY),
                        CGPoint(x: bbox.maxX, y: bbox.minY),
                        CGPoint(x: bbox.maxX, y: bbox.maxY),
                        CGPoint(x: bbox.minX, y: bbox.maxY)
                    ]
                    let corner = corners[cornerIndex]
                    scaleDragOriginCorner = corner
                    scaleDragOriginCornerDist = max(
                        hypot(corner.x - scaleDragOriginCenter.x, corner.y - scaleDragOriginCenter.y),
                        0.001
                    )
                    document.beginInteractiveEdit()
                }
                guard !scaleDragOriginPoints.isEmpty else { return }
                let center = scaleDragOriginCenter
                let dragPoint = document.viewport.viewToDocument(value.location)
                let corner = scaleDragOriginCorner
                let sx: CGFloat
                let sy: CGFloat
                if document.scaleUniform {
                    let newDist = hypot(dragPoint.x - center.x, dragPoint.y - center.y)
                    let factor = newDist / scaleDragOriginCornerDist
                    sx = factor
                    sy = factor
                } else {
                    sx = abs(corner.x - center.x) > 0.001
                        ? (dragPoint.x - center.x) / (corner.x - center.x)
                        : 1
                    sy = abs(corner.y - center.y) > 0.001
                        ? (dragPoint.y - center.y) / (corner.y - center.y)
                        : 1
                }
                let scaled = scaleDragOriginPoints.map { point in
                    CGPoint(
                        x: center.x + (point.x - center.x) * sx,
                        y: center.y + (point.y - center.y) * sy
                    )
                }
                if let originHandles = scaleDragOriginHandles,
                   var stroke = document.stroke(with: strokeID) {
                    stroke.points = scaled
                    stroke.curveHandles = originHandles.map { handle in
                        CurveHandle(
                            inOffset: CGPoint(x: handle.inOffset.x * sx, y: handle.inOffset.y * sy),
                            outOffset: CGPoint(x: handle.outOffset.x * sx, y: handle.outOffset.y * sy)
                        )
                    }
                    document.updateStroke(stroke, recordUndo: false)
                } else {
                    document.setStrokePoints(id: strokeID, points: scaled, recordUndo: false)
                }
                onChanged()
            }
            .onEnded { _ in
                let didEdit = !scaleDragOriginPoints.isEmpty
                scaleDragOriginPoints = []
                scaleDragOriginHandles = nil
                guard didEdit else { return }
                document.reconcileIntersectionAnchors(around: [strokeID])
                onChanged()
            }
    }

    // MARK: - Center anchor

    @ViewBuilder
    private func centerHandle(strokeID: UUID, stroke: VectorStroke) -> some View {
        if let center = ShapeGeometry.shapeCenter(for: stroke) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.cyan)
                .frame(width: centerHandleSize, height: centerHandleSize)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .position(document.viewport.documentToView(center))
                .highPriorityGesture(centerHandleDrag(strokeID: strokeID))
        }
    }

    private func centerHandleDrag(strokeID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if centerDragOriginPoints.isEmpty {
                    centerDragOriginPoints = document.stroke(with: strokeID)?.points ?? []
                    document.beginInteractiveEdit()
                }
                let delta = documentDelta(from: value.translation)
                let moved = centerDragOriginPoints.map {
                    CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
                }
                document.setStrokePoints(id: strokeID, points: moved, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                let didEdit = !centerDragOriginPoints.isEmpty
                centerDragOriginPoints = []
                guard didEdit else { return }
                document.reconcileIntersectionAnchors(around: [strokeID])
                onChanged()
            }
    }

    // MARK: - Handle appearance

    private enum HandleStyle {
        case edit, move, command, selectedAnchor, trim, fillet, addAnchor
    }

    private func handleView(style: HandleStyle) -> some View {
        let fill: Color = switch style {
        case .edit: .accentColor
        case .move: .orange
        case .command: .blue
        case .selectedAnchor: .mint
        case .trim: .red
        case .fillet: .purple
        case .addAnchor: .green
        }
        return Circle()
            .fill(fill)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }

    private func documentDelta(from translation: CGSize) -> CGPoint {
        CGPoint(
            x: document.viewport.viewToDocument(distance: translation.width),
            y: document.viewport.viewToDocument(distance: translation.height)
        )
    }
}
