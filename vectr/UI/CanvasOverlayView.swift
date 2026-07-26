//
//  CanvasOverlayView.swift
//  vectr
//

import SwiftUI

/// Handles node editing, multi-anchor move, scale, trim, fillet, and command-preview point dragging.
struct CanvasOverlayView: View {
    @Bindable var document: VectrDocument
    @Bindable var commandSession: ShapeCommandSession
    var patternPreviewStrokes: [VectorStroke] = []
    var onChanged: () -> Void
    var onEditText: (UUID) -> Void = { _ in }

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
    @State private var textMoveOrigin: CGPoint?
    @State private var textScaleOrigin: TextElement?
    @State private var textScaleOriginCenter: CGPoint = .zero
    @State private var textScaleOriginDist: CGFloat = 1
    @State private var textRotateOrigin: TextElement?
    @State private var textRotatePivot: CGPoint = .zero
    @State private var textRotatePreviousAngle: CGFloat = 0
    @State private var textRotateAccumulated: CGFloat = 0

    // Object snapping (endpoints/midpoints) for the Move tool. Shares the same decoupled
    // engine as the drawing canvas; the lock session + haptics + indicator are per-overlay.
    private let snapEngine = PathSnapEngine.makeDefault()
    @State private var snapSession = SnapInteractionSession()
    @State private var snapHaptics = SnapHaptics()
    @State private var activeSnap: SnapCandidate?

    // Marquee + group transform (move tool)
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var dragDecided = false
    @State private var dragIsMarquee = false
    @State private var groupMoveStrokeOrigins: [UUID: VectorStroke] = [:]
    @State private var groupMoveTextOrigins: [UUID: CGPoint] = [:]
    @State private var groupRotateStrokeOrigins: [UUID: VectorStroke] = [:]
    @State private var groupRotateTextOrigins: [UUID: TextElement] = [:]
    @State private var groupRotatePivot: CGPoint = .zero
    @State private var groupRotatePreviousAngle: CGFloat = 0
    @State private var groupRotateAccumulated: CGFloat = 0
    @State private var groupRotateActive = false

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
                    moveToolOverlay
                } else if document.activeCategory == .scale {
                    if document.selectedTextID != nil {
                        textScaleOverlay
                    } else {
                        scaleHandles
                    }
                } else if document.activeCategory == .type {
                    textTypeOverlay
                } else if document.activeCategory == .trim {
                    trimOverlay
                } else if document.activeCategory == .fillet {
                    filletOverlay
                } else if document.activeCategory == .addAnchor {
                    addAnchorOverlay
                } else if document.activeCategory == .pattern {
                    patternPreviewOverlay
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
            lineVariant: commandSession.lineVariant,
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

            if let activeSnap {
                snapMarker(activeSnap)
            }
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
                let rawPoint = document.viewport.viewToDocument(value.location)
                if stroke.shapeType == .circle {
                    // Radius handles move radially; absolute object snapping doesn't apply.
                    stroke.points = ShapeGeometry.updateCircleHandle(at: index, to: rawPoint, stroke: stroke)
                } else if stroke.shapeType == .ellipse {
                    stroke.points = ShapeGeometry.updateEllipseHandle(at: index, to: rawPoint, stroke: stroke)
                } else {
                    stroke.points[index] = resolveNodeSnap(rawPoint: rawPoint, stroke: stroke, index: index, strokeID: strokeID)
                }
                document.updateStroke(stroke, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                let didEdit = !nodeDragOriginPoints.isEmpty
                nodeDragOriginPoints = []
                clearMoveSnap()
                guard didEdit else { return }
                document.reconcileIntersectionAnchors(around: [strokeID])
                onChanged()
            }
    }

    /// Snaps a node-edit vertex to nearby object geometry (endpoints/center/quadrant/intersection),
    /// and for straight segmented paths lets it go tangent to circles/arcs using the vertex's
    /// stationary neighbors as the tangent anchors. Returns the raw point when nothing snaps.
    private func resolveNodeSnap(rawPoint: CGPoint, stroke: VectorStroke, index: Int, strokeID: UUID) -> CGPoint {
        let references: [CGPoint] = (stroke.shapeType == .polyline || stroke.shapeType == .construction)
            ? neighborReferenceStarts(movingAnchor: index, points: nodeDragOriginPoints, isClosed: stroke.isClosed)
            : []
        return resolveMoveSnap(reference: rawPoint, excluding: strokeID, referenceStarts: references)
    }

    // MARK: - Move tool routing

    @ViewBuilder
    private var moveToolOverlay: some View {
        ZStack {
            if document.usesGroupTransform {
                multiSelectionMoveOverlay
            } else if document.selectedTextID != nil {
                textMoveOverlay
            } else if document.selectedStrokeID != nil {
                strokeMoveOverlay
            } else {
                emptyMoveOverlay
            }

            if let rect = marqueeViewRect {
                marqueeBox(rect)
            }
        }
    }

    /// Background layer shown when nothing is selected: a drag draws a marquee and
    /// a tap selects (or toggles) the element underneath.
    @ViewBuilder
    private var emptyMoveOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                backgroundDrag(
                    canMove: { _ in false },
                    onMoveBegan: {},
                    onMoveChanged: { _ in },
                    onMoveEnded: {}
                )
            )
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                    .onEnded { value in handleMoveTap(at: value.location) }
            )
    }

    // MARK: - Multi-selection group transform

    @ViewBuilder
    private var multiSelectionMoveOverlay: some View {
        if let bbox = document.selectionBoundingBox() {
            let center = CGPoint(x: bbox.midX, y: bbox.midY)
            let viewCorners = [
                CGPoint(x: bbox.minX, y: bbox.minY),
                CGPoint(x: bbox.maxX, y: bbox.minY),
                CGPoint(x: bbox.maxX, y: bbox.maxY),
                CGPoint(x: bbox.minX, y: bbox.maxY)
            ].map { document.viewport.documentToView($0) }

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    backgroundDrag(
                        canMove: { point in
                            document.selectionContains(point: point, threshold: moveHitThreshold)
                                || (document.selectedGroup != nil
                                    && document.selectionBoundingBox()?.contains(point) == true)
                        },
                        onMoveBegan: { beginGroupMove() },
                        onMoveChanged: { value in
                            applyGroupMove(delta: documentDelta(from: value.translation))
                        },
                        onMoveEnded: { finishGroupMove() }
                    )
                )
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                        .onEnded { value in handleMoveTap(at: value.location) }
                )

            boxPath(viewCorners)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .allowsHitTesting(false)

            pivotMarker(at: center)
            groupRotationHandle(pivot: center)
        }
    }

    @ViewBuilder
    private func groupRotationHandle(pivot: CGPoint) -> some View {
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
            .highPriorityGesture(groupRotateGesture(pivot: pivot))
    }

    private func beginGroupMove() {
        // Guarantee every group member is included before capturing origins so
        // a partial selection never translates one child independently.
        document.expandSelectionToGroupsIfNeeded()
        groupMoveStrokeOrigins = [:]
        for id in document.selectedStrokeIDs {
            if let stroke = document.stroke(with: id) {
                groupMoveStrokeOrigins[id] = stroke
            }
        }
        groupMoveTextOrigins = [:]
        for id in document.selectedTextIDs {
            if let position = document.textElement(with: id)?.position {
                groupMoveTextOrigins[id] = position
            }
        }
        document.beginInteractiveEdit()
    }

    private func applyGroupMove(delta: CGPoint) {
        // Translate each child independently from its captured origin. Overlapping
        // anchors may coincide visually but are never welded or merged.
        for (_, origin) in groupMoveStrokeOrigins {
            var updated = origin
            updated.points = origin.points.map {
                CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
            }
            updated.cutoutPoints = origin.cutoutPoints.map { contour in
                contour.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            }
            if let base = origin.rotationBasePoints {
                updated.rotationBasePoints = base.map {
                    CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
                }
            }
            if let center = origin.rotationBaseCenter {
                updated.rotationBaseCenter = CGPoint(x: center.x + delta.x, y: center.y + delta.y)
            }
            document.updateStroke(updated, recordUndo: false)
        }
        for (id, origin) in groupMoveTextOrigins {
            document.setTextPosition(
                id: id,
                position: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                recordUndo: false
            )
        }
        onChanged()
    }

    private func finishGroupMove() {
        groupMoveStrokeOrigins = [:]
        groupMoveTextOrigins = [:]
        // Skip intersection-anchor reconciliation so overlapping vertices inside a
        // group stay independent (no weld/merge of coordinate arrays).
        onChanged()
    }

    private func groupRotateGesture(pivot: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let currentDoc = document.viewport.viewToDocument(value.location)
                if !groupRotateActive {
                    groupRotateActive = true
                    document.expandSelectionToGroupsIfNeeded()
                    groupRotatePivot = pivot
                    groupRotatePreviousAngle = atan2(currentDoc.y - pivot.y, currentDoc.x - pivot.x)
                    groupRotateAccumulated = 0
                    groupRotateStrokeOrigins = [:]
                    for id in document.selectedStrokeIDs {
                        if let stroke = document.stroke(with: id) {
                            groupRotateStrokeOrigins[id] = stroke
                        }
                    }
                    groupRotateTextOrigins = [:]
                    for id in document.selectedTextIDs {
                        if let text = document.textElement(with: id) {
                            groupRotateTextOrigins[id] = text
                        }
                    }
                    document.beginInteractiveEdit()
                }
                let angle = atan2(currentDoc.y - groupRotatePivot.y, currentDoc.x - groupRotatePivot.x)
                let rawStep = angle - groupRotatePreviousAngle
                let step = atan2(sin(rawStep), cos(rawStep))
                groupRotateAccumulated += step
                groupRotatePreviousAngle = angle

                for (_, origin) in groupRotateStrokeOrigins {
                    let rotated = ShapeGeometry.rotatedStroke(
                        origin,
                        around: groupRotatePivot,
                        by: groupRotateAccumulated
                    )
                    document.updateStroke(rotated, recordUndo: false)
                }
                for (_, origin) in groupRotateTextOrigins {
                    var updated = origin
                    let rotatedCenter = ShapeGeometry.rotatePoints(
                        [origin.center],
                        around: groupRotatePivot,
                        by: groupRotateAccumulated
                    ).first ?? origin.center
                    updated.rotation = origin.rotation + groupRotateAccumulated
                    let size = updated.textSize()
                    updated.position = CGPoint(
                        x: rotatedCenter.x - size.width / 2,
                        y: rotatedCenter.y - size.height / 2
                    )
                    document.updateTextElement(updated, recordUndo: false)
                }
                onChanged()
            }
            .onEnded { _ in
                groupRotateActive = false
                groupRotateStrokeOrigins = [:]
                groupRotateTextOrigins = [:]
                groupRotatePreviousAngle = 0
                groupRotateAccumulated = 0
                // Skip intersection-anchor reconciliation so overlapping vertices
                // inside a group remain independent after rotation.
                onChanged()
            }
    }

    // MARK: - Marquee

    private var moveHitThreshold: CGFloat {
        document.viewport.viewToDocument(distance: 12)
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

    /// Shared background drag that either moves the current selection (when the
    /// drag starts over it) or draws a marquee (when it starts on empty canvas).
    private func backgroundDrag(
        canMove: @escaping (CGPoint) -> Bool,
        onMoveBegan: @escaping () -> Void,
        onMoveChanged: @escaping (DragGesture.Value) -> Void,
        onMoveEnded: @escaping () -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if !dragDecided {
                    dragDecided = true
                    let startDoc = document.viewport.viewToDocument(value.startLocation)
                    dragIsMarquee = !canMove(startDoc)
                    if dragIsMarquee {
                        marqueeStart = value.startLocation
                    } else {
                        onMoveBegan()
                    }
                }
                if dragIsMarquee {
                    marqueeCurrent = value.location
                    onChanged()
                } else {
                    onMoveChanged(value)
                }
            }
            .onEnded { value in
                if dragIsMarquee {
                    if let rect = marqueeDocRect(start: value.startLocation, current: value.location) {
                        document.selectElements(in: rect)
                    }
                    marqueeStart = nil
                    marqueeCurrent = nil
                } else {
                    onMoveEnded()
                }
                dragDecided = false
                dragIsMarquee = false
                onChanged()
            }
    }

    /// Move-tool tap: toggles the element under the tap in/out of the selection,
    /// or clears the selection when tapping empty canvas. A single already-selected
    /// element stays selected so a simple tap never deselects it.
    private func handleMoveTap(at viewPoint: CGPoint) {
        let documentPoint = document.viewport.viewToDocument(viewPoint)
        let threshold = document.viewport.viewToDocument(distance: 16)
        switch document.elementHit(near: documentPoint, threshold: threshold) {
        case .stroke(let id):
            if let group = document.group(containingStroke: id) {
                document.selectGroup(group)
            } else if document.selectedStrokeIDs.contains(id) {
                if document.selectionCount > 1 { document.toggleStrokeSelection(id) }
            } else {
                document.toggleStrokeSelection(id)
            }
        case .text(let id):
            if let group = document.group(containingText: id) {
                document.selectGroup(group)
            } else if document.selectedTextIDs.contains(id) {
                if document.selectionCount > 1 { document.toggleTextSelection(id) }
            } else {
                document.toggleTextSelection(id)
            }
        case .none:
            if let group = document.group(at: documentPoint) {
                document.selectGroup(group)
            } else {
                document.clearElementSelection()
            }
        }
        onChanged()
    }

    // MARK: - Move (multi-anchor)

    @ViewBuilder
    private var strokeMoveOverlay: some View {
        if let strokeID = document.selectedStrokeID,
           let stroke = document.stroke(with: strokeID) {
            let handles = ShapeGeometry.handlePoints(for: stroke)
            let computedPivot = ShapeGeometry.rotationPivot(
                for: stroke,
                anchorIndex: document.moveRotationPivotAnchorIndex
            )
            let pivot = rotateDragOriginStroke != nil ? rotateDragPivot : computedPivot

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    backgroundDrag(
                        canMove: { document.selectionContains(point: $0, threshold: moveHitThreshold) },
                        onMoveBegan: {},
                        onMoveChanged: { value in
                            handleMoveDragChanged(
                                strokeID: strokeID,
                                stroke: stroke,
                                value: value,
                                anchorIndex: nil
                            )
                        },
                        onMoveEnded: { finishMoveDrag(strokeID: strokeID) }
                    )
                )
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                        .onEnded { value in
                            handleMoveTap(at: value.location)
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

            centerHandle(
                strokeID: strokeID,
                stroke: stroke,
                centerOverride: rotateDragOriginStroke != nil ? rotateDragPivot : nil
            )

            if let activeSnap {
                snapMarker(activeSnap)
            }
        }
    }

    /// High-contrast snap indicator: a square for endpoints, a triangle for midpoints,
    /// drawn at the locked coordinate. Mirrors the drawing-canvas marker styling.
    @ViewBuilder
    private func snapMarker(_ candidate: SnapCandidate) -> some View {
        let size: CGFloat = 13
        let position = document.viewport.documentToView(candidate.point)
        Group {
            switch candidate.kind {
            case .endpoint:
                Rectangle()
                    .fill(Color.pink.opacity(0.95))
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: size, height: size)
            case .midpoint:
                SnapTriangle()
                    .fill(Color.pink.opacity(0.95))
                    .overlay(SnapTriangle().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: size, height: size)
            case .intersection:
                SnapCross()
                    .fill(Color.pink.opacity(0.95))
                    .overlay(SnapCross().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: size, height: size)
            case .center:
                SnapConcentric()
                    .fill(Color.pink.opacity(0.95), style: FillStyle(eoFill: true))
                    .frame(width: size, height: size)
            case .quadrant:
                SnapDiamond()
                    .fill(Color.pink.opacity(0.95))
                    .overlay(SnapDiamond().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: size, height: size)
            case .tangent:
                SnapTangent()
                    .fill(Color.pink.opacity(0.95))
                    .frame(width: size, height: size)
            }
        }
        .position(position)
        .allowsHitTesting(false)
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
            snapHaptics.prepare()
            document.beginInteractiveEdit()
        }
        let rawDelta = documentDelta(from: value.translation)
        let delta = snapAdjustedDelta(
            strokeID: strokeID,
            stroke: stroke,
            rawDelta: rawDelta,
            anchorIndex: anchorIndex,
            cursorViewPoint: value.location
        )
        applyMove(strokeID: strokeID, stroke: stroke, delta: delta)
        onChanged()
    }

    private func finishMoveDrag(strokeID: UUID) {
        let didEdit = !moveDragOriginPoints.isEmpty
        moveDragOriginPoints = []
        clearMoveSnap()
        guard didEdit else { return }
        document.reconcileIntersectionAnchors(around: [strokeID])
        onChanged()
    }

    // MARK: - Move-tool object snapping

    /// Corrects a raw move delta so the moving reference point magnetically locks onto a
    /// nearby endpoint/midpoint of another stroke. Returns the delta unchanged when snapping
    /// is disabled, unsupported, or nothing is in range.
    ///
    /// Reference point selection:
    /// - dragging a single anchor handle → that anchor,
    /// - dragging with a multi-anchor selection → the first selected anchor,
    /// - whole-object background drag → the pencil/cursor position.
    private func snapAdjustedDelta(
        strokeID: UUID,
        stroke: VectorStroke,
        rawDelta: CGPoint,
        anchorIndex: Int?,
        cursorViewPoint: CGPoint
    ) -> CGPoint {
        guard !document.enabledSnapKinds.isEmpty, moveSnapSupported(stroke, anchorIndex: anchorIndex) else {
            clearMoveSnap()
            return rawDelta
        }

        let raw: CGPoint
        if let anchorIndex, moveDragOriginPoints.indices.contains(anchorIndex) {
            let origin = moveDragOriginPoints[anchorIndex]
            raw = CGPoint(x: origin.x + rawDelta.x, y: origin.y + rawDelta.y)
        } else if let first = document.selectedAnchorIndices.sorted().first,
                  moveDragOriginPoints.indices.contains(first) {
            let origin = moveDragOriginPoints[first]
            raw = CGPoint(x: origin.x + rawDelta.x, y: origin.y + rawDelta.y)
        } else {
            raw = document.viewport.viewToDocument(cursorViewPoint)
        }

        let snapped = resolveMoveSnap(
            reference: raw,
            excluding: strokeID,
            referenceStarts: tangentReferenceStarts(stroke: stroke, movingAnchor: anchorIndex)
        )
        return CGPoint(x: rawDelta.x + (snapped.x - raw.x), y: rawDelta.y + (snapped.y - raw.y))
    }

    /// Fixed neighbor anchor(s) of the vertex being dragged, used as tangent anchors. A dragged
    /// endpoint has one stationary neighbor; a dragged middle anchor has two, so its adjacent
    /// segments can each go tangent. Only straight segmented paths qualify, and only neighbors
    /// that are themselves stationary (not part of the same multi-anchor move) are included.
    private func tangentReferenceStarts(stroke: VectorStroke, movingAnchor: Int?) -> [CGPoint] {
        guard let movingAnchor,
              stroke.points.count >= 2,
              stroke.shapeType == .polyline || stroke.shapeType == .construction else { return [] }
        return neighborReferenceStarts(
            movingAnchor: movingAnchor,
            points: moveDragOriginPoints,
            isClosed: stroke.isClosed
        )
    }

    /// Shared neighbor lookup: the stationary anchors adjacent to `movingAnchor` in `points`.
    /// Skips neighbors also included in the current anchor selection so a tangent reference is
    /// always a truly fixed point.
    private func neighborReferenceStarts(
        movingAnchor: Int,
        points: [CGPoint],
        isClosed: Bool
    ) -> [CGPoint] {
        guard points.indices.contains(movingAnchor) else { return [] }
        let count = points.count
        var neighborIndices: [Int] = []
        if movingAnchor - 1 >= 0 {
            neighborIndices.append(movingAnchor - 1)
        } else if isClosed {
            neighborIndices.append(count - 1)
        }
        if movingAnchor + 1 < count {
            neighborIndices.append(movingAnchor + 1)
        } else if isClosed {
            neighborIndices.append(0)
        }
        return neighborIndices.compactMap { index in
            guard index != movingAnchor,
                  points.indices.contains(index),
                  !document.selectedAnchorIndices.contains(index) else { return nil }
            return points[index]
        }
    }

    /// Radius handles on circles/ellipses move radially rather than translating, so absolute
    /// point snapping would feel wrong there; skip them. Everything else (including whole-object
    /// circle/ellipse moves) is supported.
    private func moveSnapSupported(_ stroke: VectorStroke, anchorIndex: Int?) -> Bool {
        if anchorIndex != nil, stroke.shapeType == .circle || stroke.shapeType == .ellipse {
            return false
        }
        return true
    }

    /// Runs the shared snapping engine for a live move reference point, driving the indicator
    /// and haptics. Returns the locked point (or the raw point when nothing snaps).
    private func resolveMoveSnap(
        reference raw: CGPoint,
        excluding strokeID: UUID,
        referenceStarts: [CGPoint] = []
    ) -> CGPoint {
        let scale = max(document.viewport.scale, 0.0001)
        let update = snapSession.update(
            rawPoint: raw,
            engine: snapEngine,
            strokes: document.strokes,
            enabledKinds: document.enabledSnapKinds,
            snapRadius: SnapTuning.snapRadiusPoints / scale,
            breakawayRadius: SnapTuning.breakawayRadiusPoints / scale,
            breakawayVelocity: SnapTuning.breakawayVelocityPoints / scale,
            excludedStrokeID: strokeID,
            referenceStarts: referenceStarts
        )
        if let candidate = update.candidate {
            activeSnap = candidate
            if update.didLock { snapHaptics.play() }
            return candidate.point
        }
        activeSnap = nil
        return raw
    }

    private func clearMoveSnap() {
        snapSession.reset()
        activeSnap = nil
    }

    // MARK: - Trim

    @ViewBuilder
    private var trimOverlay: some View {
        if let strokeID = document.selectedStrokeID,
           let stroke = document.stroke(with: strokeID) {
            let usesCADTrim = stroke.shapeType == .circle
                || stroke.shapeType == .ellipse
                || stroke.shapeType == .arc
            let cutPoints = trimCutMarkers(for: stroke)
            let edgeCount = stroke.isClosed ? cutPoints.count : max(cutPoints.count - 1, 0)
            let trimThreshold = document.viewport.viewToDocument(distance: 16)

            // Cut markers (quadrants / vertices). For circles these are cut boundaries,
            // not delete targets — tapping trims the nearest adjacent span.
            ForEach(Array(cutPoints.enumerated()), id: \.offset) { index, point in
                handleView(style: .trim)
                    .position(document.viewport.documentToView(point))
                    .onTapGesture {
                        if usesCADTrim {
                            _ = document.trimAt(point, threshold: trimThreshold)
                        } else {
                            document.deleteStrokePoint(at: index)
                        }
                        onChanged()
                    }
            }

            ForEach(0..<edgeCount, id: \.self) { edgeIndex in
                let start = cutPoints[edgeIndex]
                let end = cutPoints[(edgeIndex + 1) % cutPoints.count]
                let mid = trimEdgeMidpoint(stroke: stroke, start: start, end: end)
                Capsule()
                    .fill(Color.red.opacity(0.45))
                    .frame(width: 28, height: 10)
                    .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
                    .position(document.viewport.documentToView(mid))
                    .onTapGesture {
                        if usesCADTrim {
                            _ = document.trimAt(mid, threshold: trimThreshold)
                        } else {
                            document.deleteStrokeEdge(at: edgeIndex)
                        }
                        onChanged()
                    }
            }

            centerHandle(strokeID: strokeID, stroke: stroke)
        }
    }

    /// Sparse cut markers for trim UI: cardinals for circles, endpoints + on-arc
    /// cardinals for arcs, otherwise editable handles.
    private func trimCutMarkers(for stroke: VectorStroke) -> [CGPoint] {
        switch stroke.shapeType {
        case .circle, .ellipse:
            return ShapeGeometry.handlePoints(for: stroke)
        case .arc:
            var markers: [CGPoint] = []
            if let first = stroke.points.first { markers.append(first) }
            if let last = stroke.points.last,
               markers.last.map({ hypot($0.x - last.x, $0.y - last.y) > 0.001 }) ?? true {
                markers.append(last)
            }
            if let circle = ShapeGeometry.arcCircle(for: stroke) {
                for cardinal in ShapeGeometry.circleCardinalPoints(
                    center: circle.center,
                    radius: circle.radius
                ) where stroke.distance(to: cardinal) <= 0.5 {
                    if markers.contains(where: { hypot($0.x - cardinal.x, $0.y - cardinal.y) <= 0.5 }) {
                        continue
                    }
                    markers.append(cardinal)
                }
            }
            // Keep contour order so open-arc edge markers stay on the remaining geometry.
            let contour = ShapeGeometry.renderPoints(for: stroke)
            return markers.sorted { a, b in
                contourProjectionDistance(a, on: contour) < contourProjectionDistance(b, on: contour)
            }
        default:
            return ShapeGeometry.handlePoints(for: stroke)
        }
    }

    private func contourProjectionDistance(_ point: CGPoint, on points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var bestParam = CGFloat.greatestFiniteMagnitude
        var accrued: CGFloat = 0
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lenSq = dx * dx + dy * dy
            let t: CGFloat
            if lenSq <= 0 {
                t = 0
            } else {
                t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lenSq))
            }
            let projected = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
            let distance = hypot(point.x - projected.x, point.y - projected.y)
            let length = hypot(dx, dy)
            if distance < bestDistance {
                bestDistance = distance
                bestParam = accrued + length * t
            }
            accrued += length
        }
        return bestParam
    }

    /// For circles/ellipses, place the marker on the curved rim (not the chord midpoint).
    private func trimEdgeMidpoint(stroke: VectorStroke, start: CGPoint, end: CGPoint) -> CGPoint {
        let chord = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        if let circle = ShapeGeometry.arcCircle(for: stroke)
            ?? ShapeGeometry.circleFromCardinalPoints(ShapeGeometry.handlePoints(for: stroke)) {
            let dx = chord.x - circle.center.x
            let dy = chord.y - circle.center.y
            let length = hypot(dx, dy)
            if length > 0.0001 {
                return CGPoint(
                    x: circle.center.x + dx / length * circle.radius,
                    y: circle.center.y + dy / length * circle.radius
                )
            }
        }
        return chord
    }

    // MARK: - Pattern preview

    @ViewBuilder
    private var patternPreviewOverlay: some View {
        ZStack {
            ForEach(patternPreviewStrokes) { stroke in
                patternPreviewPath(for: stroke)
                    .stroke(
                        Color.accentColor.opacity(0.45),
                        style: StrokeStyle(
                            lineWidth: max(stroke.strokeWidth * document.viewport.scale, 1),
                            dash: [6, 4]
                        )
                    )
            }

            if let strokeID = document.selectedStrokeID,
               let stroke = document.stroke(with: strokeID) {
                centerHandle(strokeID: strokeID, stroke: stroke)
            }
        }
    }

    private func patternPreviewPath(for stroke: VectorStroke) -> Path {
        let points = ShapeGeometry.renderPoints(for: stroke)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: document.viewport.documentToView(first))
        for point in points.dropFirst() {
            path.addLine(to: document.viewport.documentToView(point))
        }
        if stroke.isClosed {
            path.closeSubpath()
        }
        return path
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
                    .frame(width: anchorTouchTargetSize, height: anchorTouchTargetSize)
                    .contentShape(Rectangle())
                    .position(document.viewport.documentToView(point))
                    .highPriorityGesture(
                        filletCornerDrag(
                            strokeID: strokeID,
                            cornerIndex: index,
                            cornerPoint: point
                        )
                    )
                    .onTapGesture(count: 2) {
                        document.toggleFilletCornerSelection(at: index)
                        onChanged()
                    }
                    .onTapGesture {
                        document.selectSingleFilletCorner(at: index)
                        onChanged()
                    }
            }

            centerHandle(strokeID: strokeID, stroke: stroke)
        }
    }

    private func filletCornerDrag(strokeID: UUID, cornerIndex: Int, cornerPoint: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: filletDragThreshold, coordinateSpace: .named(coordinateSpaceName))
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
                    filletDragDidMove = true
                    document.beginInteractiveEdit()
                    document.selectedFilletCornerIndices = filletDragTargetCornerIndices
                }

                guard filletDragStrokeID == strokeID,
                      filletDragCornerIndex == cornerIndex else { return }

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
                    onChanged()
                }
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
    private func centerHandle(strokeID: UUID, stroke: VectorStroke, centerOverride: CGPoint? = nil) -> some View {
        if let center = centerOverride ?? ShapeGeometry.shapeCenter(for: stroke) {
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

    // MARK: - Text (move / rotate via Move tool, scale via Scale tool)

    /// Type tool overlay for a selected text element: tap the box to edit,
    /// drag it to move, and use corner handles to scale. No rotation here —
    /// rotation is reserved for the Move tool.
    @ViewBuilder
    private var textTypeOverlay: some View {
        if let id = document.selectedTextID,
           let element = document.textElement(with: id) {
            let viewCorners = element.corners().map { document.viewport.documentToView($0) }

            Color.clear
                .contentShape(boxPath(viewCorners))
                .gesture(textMoveDrag(id: id))
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                        .onEnded { _ in onEditText(id) }
                )

            boxPath(viewCorners)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .allowsHitTesting(false)

            ForEach(Array(viewCorners.enumerated()), id: \.offset) { index, corner in
                handleView(style: .edit)
                    .position(corner)
                    .highPriorityGesture(textScaleDrag(id: id, cornerIndex: index))
            }
        }
    }

    /// Move tool overlay for a selected text element: drag anywhere to move,
    /// plus a rotation handle. Mirrors the shape move overlay behavior.
    @ViewBuilder
    private var textMoveOverlay: some View {
        if let id = document.selectedTextID,
           let element = document.textElement(with: id) {
            let viewCorners = element.corners().map { document.viewport.documentToView($0) }
            let viewCenter = document.viewport.documentToView(element.center)

            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    backgroundDrag(
                        canMove: { document.selectionContains(point: $0, threshold: moveHitThreshold) },
                        onMoveBegan: {
                            textMoveOrigin = document.textElement(with: id)?.position
                            document.beginInteractiveEdit()
                        },
                        onMoveChanged: { value in
                            guard let origin = textMoveOrigin else { return }
                            let delta = documentDelta(from: value.translation)
                            document.setTextPosition(
                                id: id,
                                position: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                                recordUndo: false
                            )
                            onChanged()
                        },
                        onMoveEnded: {
                            textMoveOrigin = nil
                            onChanged()
                        }
                    )
                )
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                        .onEnded { value in
                            handleMoveTap(at: value.location)
                        }
                )

            boxPath(viewCorners)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .allowsHitTesting(false)

            textRotationHandle(id: id, viewCorners: viewCorners, viewCenter: viewCenter)
        }
    }

    /// Scale tool overlay for a selected text element: corner handles resize the
    /// font about the element's center.
    @ViewBuilder
    private var textScaleOverlay: some View {
        if let id = document.selectedTextID,
           let element = document.textElement(with: id) {
            let viewCorners = element.corners().map { document.viewport.documentToView($0) }

            boxPath(viewCorners)
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .allowsHitTesting(false)

            ForEach(Array(viewCorners.enumerated()), id: \.offset) { index, corner in
                handleView(style: .edit)
                    .position(corner)
                    .highPriorityGesture(textScaleDrag(id: id, cornerIndex: index))
            }
        }
    }

    private func boxPath(_ corners: [CGPoint]) -> Path {
        Path { path in
            guard corners.count == 4 else { return }
            path.move(to: corners[0])
            path.addLine(to: corners[1])
            path.addLine(to: corners[2])
            path.addLine(to: corners[3])
            path.closeSubpath()
        }
    }

    private func textMoveDrag(id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if textMoveOrigin == nil {
                    textMoveOrigin = document.textElement(with: id)?.position
                    document.beginInteractiveEdit()
                }
                guard let origin = textMoveOrigin else { return }
                let delta = documentDelta(from: value.translation)
                document.setTextPosition(
                    id: id,
                    position: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                    recordUndo: false
                )
                onChanged()
            }
            .onEnded { _ in
                textMoveOrigin = nil
                onChanged()
            }
    }

    private func textScaleDrag(id: UUID, cornerIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if textScaleOrigin == nil {
                    guard let element = document.textElement(with: id) else { return }
                    textScaleOrigin = element
                    textScaleOriginCenter = element.center
                    let corner = element.corners()[cornerIndex]
                    textScaleOriginDist = max(
                        hypot(corner.x - element.center.x, corner.y - element.center.y),
                        0.001
                    )
                    document.beginInteractiveEdit()
                }
                guard let origin = textScaleOrigin else { return }
                let dragPoint = document.viewport.viewToDocument(value.location)
                let newDist = hypot(
                    dragPoint.x - textScaleOriginCenter.x,
                    dragPoint.y - textScaleOriginCenter.y
                )
                let factor = newDist / textScaleOriginDist
                let newSize = max(4, origin.fontSize * factor)
                var updated = origin
                updated.fontSize = newSize
                let size = updated.textSize()
                updated.position = CGPoint(
                    x: textScaleOriginCenter.x - size.width / 2,
                    y: textScaleOriginCenter.y - size.height / 2
                )
                document.updateTextElement(updated, recordUndo: false)
                document.activeFontSize = newSize
                onChanged()
            }
            .onEnded { _ in
                textScaleOrigin = nil
                onChanged()
            }
    }

    @ViewBuilder
    private func textRotationHandle(id: UUID, viewCorners: [CGPoint], viewCenter: CGPoint) -> some View {
        if viewCorners.count == 4 {
            let topMid = CGPoint(
                x: (viewCorners[0].x + viewCorners[1].x) / 2,
                y: (viewCorners[0].y + viewCorners[1].y) / 2
            )
            let dx = topMid.x - viewCenter.x
            let dy = topMid.y - viewCenter.y
            let length = max(hypot(dx, dy), 0.001)
            let handlePosition = CGPoint(
                x: topMid.x + dx / length * rotateHandleOffset,
                y: topMid.y + dy / length * rotateHandleOffset
            )

            Path { path in
                path.move(to: topMid)
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
                .highPriorityGesture(textRotateDrag(id: id))
        }
    }

    private func textRotateDrag(id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let currentDoc = document.viewport.viewToDocument(value.location)
                if textRotateOrigin == nil {
                    guard let element = document.textElement(with: id) else { return }
                    textRotateOrigin = element
                    textRotatePivot = element.center
                    textRotatePreviousAngle = atan2(
                        currentDoc.y - element.center.y,
                        currentDoc.x - element.center.x
                    )
                    textRotateAccumulated = 0
                    document.beginInteractiveEdit()
                }
                guard let origin = textRotateOrigin else { return }
                let angle = atan2(currentDoc.y - textRotatePivot.y, currentDoc.x - textRotatePivot.x)
                let rawStep = angle - textRotatePreviousAngle
                let step = atan2(sin(rawStep), cos(rawStep))
                textRotateAccumulated += step
                textRotatePreviousAngle = angle
                document.setTextRotation(id: id, radians: origin.rotation + textRotateAccumulated, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                textRotateOrigin = nil
                textRotatePreviousAngle = 0
                textRotateAccumulated = 0
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

/// Upward-pointing triangle used for the midpoint snap indicator.
private struct SnapTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Solid "X" used for the intersection snap indicator. Shares vertex math with the canvas
/// indicator via `SnapMarkerGeometry` so both glyphs match.
private struct SnapCross: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for (index, vertex) in SnapMarkerGeometry.crossVertices(size: size).enumerated() {
            let placed = CGPoint(x: center.x + vertex.x, y: center.y + vertex.y)
            if index == 0 { path.move(to: placed) } else { path.addLine(to: placed) }
        }
        path.closeSubpath()
        return path
    }
}

/// Concentric-circle glyph (⊙) for the center snap indicator: an outer ring plus a center dot.
private struct SnapConcentric: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        let mid = outer * 0.55
        path.addEllipse(in: CGRect(x: center.x - mid, y: center.y - mid, width: mid * 2, height: mid * 2))
        let dot = outer * 0.24
        path.addEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
        return path
    }
}

/// Diamond glyph (⋄) for the quadrant snap indicator.
private struct SnapDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// A disc with a line kissing its top edge, used for the tangent snap indicator.
private struct SnapTangent: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let discRadius = size * 0.36
        let discCenterY = center.y + size * 0.12
        var path = Path()
        path.addEllipse(in: CGRect(
            x: center.x - discRadius,
            y: discCenterY - discRadius,
            width: discRadius * 2,
            height: discRadius * 2
        ))
        let barHeight: CGFloat = 2.4
        let barY = discCenterY - discRadius - barHeight / 2
        path.addRect(CGRect(x: center.x - size / 2, y: barY, width: size, height: barHeight))
        return path
    }
}
