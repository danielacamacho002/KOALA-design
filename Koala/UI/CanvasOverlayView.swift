//
//  CanvasOverlayView.swift
//  Koala
//

import SwiftUI

/// Handles node editing, multi-anchor move, scale, fillet, and command-preview point dragging.
struct CanvasOverlayView: View {
    @Bindable var document: KoalaDocument
    @Bindable var commandSession: ShapeCommandSession
    var patternPreviewStrokes: [VectorStroke] = []
    var onChanged: () -> Void
    var onEditText: (UUID) -> Void = { _ in }
    var onDismissTool: () -> Void = {}

    @State private var nodeDragOriginPoints: [CGPoint] = []
    @State private var nodeDragOriginStroke: VectorStroke?
    @State private var curveHandleDragActive = false
    /// Curve control chosen at the start of a grab. The closest dot keeps the touch.
    @State private var curveGrab: CurveGrab?
    @State private var curveGrabMoved = false

    private enum CurveGrab: Equatable {
        case anchor(Int)
        case tangent(index: Int, isOut: Bool)
    }

    private struct CurveGrabCircle {
        var kind: CurveGrab
        var center: CGPoint
        var radius: CGFloat
    }
    @State private var moveDragOriginPoints: [CGPoint] = []
    @State private var moveDragOriginStroke: VectorStroke?
    @State private var commandDragOriginPoints: [CGPoint] = []
    @State private var scaleDragOriginPoints: [CGPoint] = []
    @State private var scaleDragOriginHandles: [CurveHandle]? = nil
    @State private var scaleDragOriginCutouts: [[CGPoint]] = []
    @State private var scaleDragOriginCenter: CGPoint = .zero
    @State private var scaleDragOriginCorner: CGPoint = .zero
    @State private var scaleDragOriginCornerDist: CGFloat = 1
    @State private var centerDragOriginPoints: [CGPoint] = []
    @State private var centerDragOriginStroke: VectorStroke?
    /// Anchor snap references (handle points) captured when a center-handle drag begins.
    @State private var centerDragSnapOrigins: [CGPoint] = []
    /// The shape center captured when a center-handle drag begins (center-to-center priority).
    @State private var centerDragSnapCenter: CGPoint?
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
    @State private var imageMoveOrigin: CGRect?
    @State private var imageScaleOrigin: CGRect?
    @State private var imageScaleOriginCenter: CGPoint = .zero
    @State private var imageScaleOriginCorner: CGPoint = .zero
    @State private var imageScaleOriginCornerDist: CGFloat = 1
    @State private var imageScaleOriginRotation: CGFloat = 0
    @State private var imageRotateOriginRadians: CGFloat?
    @State private var imageRotatePivot: CGPoint = .zero
    @State private var imageRotatePreviousAngle: CGFloat = 0
    @State private var imageRotateAccumulated: CGFloat = 0

    /// The last tap on an anchor handle, and on a fillet-corner handle. Attaching both a
    /// `count: 2` and a `count: 1` tap gesture to a handle makes SwiftUI hold the single
    /// tap until the double-tap window lapses, so selecting a different handle lagged by
    /// ~0.3s. Instead the single tap applies immediately and a second tap inside the
    /// window rewinds it — hence the pre-tap selection recorded here.
    @State private var lastAnchorTap: HandleTap?
    @State private var lastFilletCornerTap: HandleTap?

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
    /// Anchor reference points (document space) of every group member, captured at the
    /// start of a group move so whole-group translation can snap onto other geometry.
    @State private var groupMoveSnapOrigins: [CGPoint] = []
    /// Center reference points of every group member (center-to-center priority).
    @State private var groupMoveSnapCenters: [CGPoint] = []
    @State private var groupRotateStrokeOrigins: [UUID: VectorStroke] = [:]
    @State private var groupRotateTextOrigins: [UUID: TextElement] = [:]
    @State private var groupRotatePivot: CGPoint = .zero
    @State private var groupRotatePreviousAngle: CGFloat = 0
    @State private var groupRotateAccumulated: CGFloat = 0
    @State private var groupRotateReadoutBaseline: Double = 0
    @State private var groupRotateActive = false
    /// Dominant axis chosen for the current whole-object Move drag. Resets on end.
    @State private var moveTranslationAxis: MoveDragAxis = .free

    private let handleSize: CGFloat = 22
    /// Visible side length of path anchors and the center handle at 1× zoom.
    /// Above 1× this grows with the viewport via `anchorScreenLength`. Hit testing uses `anchorTouchTargetSize`.
    private let anchorHandleSize = CanvasOverlayGeometry.anchorMarkSize
    private let coordinateSpaceName = "editor"
    private let filletDragThreshold: CGFloat = 6
    private let rotateHandleOffset: CGFloat = 36
    /// Invisible finger/Pencil target around each anchor handle so small squares are easy to hit.
    private let anchorTouchTargetSize = CanvasOverlayGeometry.curveAnchorHitExtent
    /// Dead-zone before an individual anchor starts dragging, so taps/double-taps never nudge it.
    private let anchorDragThreshold: CGFloat = 6
    /// Window in which a second tap on the same handle counts as a double-tap.
    private let handleDoubleTapWindow: TimeInterval = 0.3

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if commandSession.isActive {
                    commandPreviewHandles
                } else if document.activeCategory == .move || document.activeCategory == nil {
                    moveToolOverlay(canvasSize: geo.size)
                } else if document.activeCategory == .scale {
                    emptyToolDismissOverlay
                    if document.selectedTextID != nil {
                        textScaleOverlay
                    } else if document.isReferenceImageSelected {
                        imageScaleOverlay
                    } else {
                        scaleHandles
                    }
                } else if document.activeCategory == .type {
                    textTypeOverlay
                } else if document.activeCategory == .fillet {
                    emptyToolDismissOverlay
                    filletOverlay
                } else if document.activeCategory == .addAnchor {
                    addAnchorOverlay
                } else if document.activeCategory == .pattern {
                    patternPreviewOverlay
                } else if document.activeCategory == .copy {
                    copySelectionOverlay
                } else if document.activeCategory == .dimensions {
                    // Measurement labels only — never show edit anchors in this mode.
                    EmptyView()
                } else if document.activeCategory != nil,
                          document.selectedStrokeID != nil,
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
            handleView(style: .command, strokeColor: document.strokeColor)
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
                let final = snapCommandControlPoint(docPoint, draggingIndex: index)
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

    private func snapCommandControlPoint(_ raw: CGPoint, draggingIndex: Int) -> CGPoint {
        let scale = document.viewport.scale
        let isStraightLine = commandSession.category == .line && commandSession.lineVariant != .arc
        if isStraightLine {
            let otherIndex = draggingIndex == 0 ? 1 : 0
            let origin = commandSession.controlPoints.indices.contains(otherIndex)
                ? commandSession.controlPoints[otherIndex]
                : nil
            return snapDrawingEndpoint(
                raw,
                origin: origin,
                applyAngleSnap: origin != nil,
                grid: document.grid,
                settings: document.settings,
                gridSnapEnabled: drawingSnapEnabled,
                scale: scale,
                objectSnap: { _, _, _ in nil }
            )
        }
        let snapped = snapDrawingPoint(
            raw,
            grid: document.grid,
            settings: document.settings,
            enabled: drawingSnapEnabled,
            scale: scale
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
            enabled: drawingSnapEnabled,
            scale: scale
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
                curveTangentConnectors(stroke: stroke, curveHandles: curveHandles)
            }
            ForEach(Array(handles.enumerated()), id: \.offset) { index, point in
                handleView(style: .edit, strokeColor: stroke.strokeColor)
                    .position(document.viewport.documentToView(point))
                    .allowsHitTesting(stroke.shapeType != .curve)
                    .highPriorityGesture(strokeNodeDrag(strokeID: strokeID, index: index))
            }
            // Dots sit above the anchor so a handle can be grabbed. The bar is drawn
            // underneath, with the anchor at its midpoint.
            if stroke.shapeType == .curve,
               let curveHandles = stroke.curveHandles,
               curveHandles.count == stroke.points.count {
                curveTangentDots(curveHandles: curveHandles, anchors: stroke.points)
                curveGrabLayer(strokeID: strokeID, stroke: stroke, curveHandles: curveHandles, nodeEdit: true)
            }
            centerHandle(strokeID: strokeID, stroke: stroke)

            if let activeSnap {
                snapMarker(activeSnap)
            }
        }
    }

    // MARK: - Curve tangent handles

    /// Writes an eighth-inch floor into any short tangent so the drawn curve and the
    /// handles are the same length. A second call is a no-op once the arms already clear it.
    private func commitMinimumTangentLength(strokeID: UUID) {
        guard let current = document.stroke(with: strokeID),
              current.shapeType == .curve,
              let handles = current.curveHandles,
              handles.count == current.points.count else { return }
        let normalized = CanvasOverlayGeometry.tangentHandlesObservingMinimum(
            anchors: current.points,
            handles: handles
        )
        guard tangentsDiffer(normalized, handles) else { return }
        document.beginInteractiveEdit()
        guard var stroke = document.stroke(with: strokeID) else { return }
        let refreshed = CanvasOverlayGeometry.tangentHandlesObservingMinimum(
            anchors: stroke.points,
            handles: stroke.curveHandles ?? handles
        )
        stroke.curveHandles = refreshed
        document.updateStroke(stroke, recordUndo: false)
        onChanged()
    }

    private func tangentsDiffer(_ updated: [CurveHandle], _ stored: [CurveHandle]) -> Bool {
        guard updated.count == stored.count else { return true }
        for (left, right) in zip(updated, stored) {
            if hypot(left.inOffset.x - right.inOffset.x, left.inOffset.y - right.inOffset.y) > 0.01 {
                return true
            }
            if hypot(left.outOffset.x - right.outOffset.x, left.outOffset.y - right.outOffset.y) > 0.01 {
                return true
            }
        }
        return false
    }

    @ViewBuilder
    private func curveTangentConnectors(
        stroke: VectorStroke,
        curveHandles: [CurveHandle]
    ) -> some View {
        let count = stroke.points.count
        ForEach(Array(stroke.points.indices), id: \.self) { index in
            let anchor = stroke.points[index]
            let anchorView = document.viewport.documentToView(anchor)
            let handle = curveHandles[index]
            let out = CGPoint(x: anchor.x + handle.outOffset.x, y: anchor.y + handle.outOffset.y)
            let incoming = CGPoint(x: anchor.x + handle.inOffset.x, y: anchor.y + handle.inOffset.y)
            let hasOut = index < count - 1 || hypot(handle.outOffset.x, handle.outOffset.y) > CanvasOverlayGeometry.epsilon
            let hasIn = index > 0 || hypot(handle.inOffset.x, handle.inOffset.y) > CanvasOverlayGeometry.epsilon

            if hasIn && hasOut {
                tangentConnector(
                    from: document.viewport.documentToView(incoming),
                    to: document.viewport.documentToView(out)
                )
            } else if hasOut {
                tangentConnector(from: anchorView, to: document.viewport.documentToView(out))
            } else if hasIn {
                tangentConnector(from: anchorView, to: document.viewport.documentToView(incoming))
            }
        }
    }

    @ViewBuilder
    private func curveTangentDots(
        curveHandles: [CurveHandle],
        anchors: [CGPoint]
    ) -> some View {
        let count = anchors.count
        ForEach(Array(anchors.indices), id: \.self) { index in
            let anchor = anchors[index]
            let handle = curveHandles[index]
            let hasOut = index < count - 1 || hypot(handle.outOffset.x, handle.outOffset.y) > CanvasOverlayGeometry.epsilon
            let hasIn = index > 0 || hypot(handle.inOffset.x, handle.inOffset.y) > CanvasOverlayGeometry.epsilon

            if hasOut {
                let out = CGPoint(x: anchor.x + handle.outOffset.x, y: anchor.y + handle.outOffset.y)
                tangentDot()
                    .position(document.viewport.documentToView(out))
                    .allowsHitTesting(false)
            }

            if hasIn {
                let incoming = CGPoint(x: anchor.x + handle.inOffset.x, y: anchor.y + handle.inOffset.y)
                tangentDot()
                    .position(document.viewport.documentToView(incoming))
                    .allowsHitTesting(false)
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
        let side = anchorScreenLength(base: anchorHandleSize)
        let hit = curveTangentHitExtent
        return Circle()
            .fill(Color.teal)
            .frame(width: side, height: side)
            .shadow(color: .white.opacity(0.85), radius: 0.5)
            .frame(width: hit, height: hit)
            .contentShape(Circle())
    }

    private func performTangentDrag(strokeID: UUID, index: Int, isOut: Bool, location: CGPoint) {
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
        let docPoint = document.viewport.viewToDocument(location)
        let anchor = stroke.points[index]
        let proposed = CGPoint(x: docPoint.x - anchor.x, y: docPoint.y - anchor.y)
        let stored = isOut ? handles[index].outOffset : handles[index].inOffset
        let separated = CanvasOverlayGeometry.separatedTangentOffset(
            proposed: proposed,
            anchor: anchor,
            obstacles: [],
            minimumLength: CanvasOverlayGeometry.minimumTangentLength,
            fallbackDirection: tangentFallbackDirection(
                anchors: stroke.points,
                index: index,
                isOut: isOut,
                stored: stored
            )
        )
        // Mirror the opposite handle so the pair stays a single straight tangent line.
        let mirrored = CGPoint(x: -separated.x, y: -separated.y)
        if isOut {
            handles[index].outOffset = separated
            handles[index].inOffset = mirrored
        } else {
            handles[index].inOffset = separated
            handles[index].outOffset = mirrored
        }
        stroke.curveHandles = handles
        document.updateStroke(stroke, recordUndo: false)
        onChanged()
    }

    private func finishTangentDrag() {
        let didEdit = curveHandleDragActive
        curveHandleDragActive = false
        guard didEdit else { return }
        onChanged()
    }

    /// One hit target over every curve anchor and tangent dot. Overlapping circles
    /// resolve to whichever center is closest, so zooming out does not stack grabs.
    @ViewBuilder
    private func curveGrabLayer(
        strokeID: UUID,
        stroke: VectorStroke,
        curveHandles: [CurveHandle],
        nodeEdit: Bool
    ) -> some View {
        let circles = curveGrabCircles(anchors: stroke.points, handles: curveHandles)
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(curveGrabPath(circles))
            .highPriorityGesture(curveGrabGesture(strokeID: strokeID, circles: circles, nodeEdit: nodeEdit))
            .onAppear { commitMinimumTangentLength(strokeID: strokeID) }
    }

    private func curveGrabCircles(anchors: [CGPoint], handles: [CurveHandle]) -> [CurveGrabCircle] {
        guard anchors.count == handles.count else { return [] }
        let anchorRadius = anchorHitTarget(visible: anchorScreenLength(base: anchorHandleSize)) / 2
        let tangentRadius = curveTangentHitExtent / 2
        let count = anchors.count
        var circles: [CurveGrabCircle] = []
        for index in anchors.indices {
            let anchor = anchors[index]
            circles.append(CurveGrabCircle(
                kind: .anchor(index),
                center: document.viewport.documentToView(anchor),
                radius: anchorRadius
            ))
            let handle = handles[index]
            let hasOut = index < count - 1 || hypot(handle.outOffset.x, handle.outOffset.y) > CanvasOverlayGeometry.epsilon
            let hasIn = index > 0 || hypot(handle.inOffset.x, handle.inOffset.y) > CanvasOverlayGeometry.epsilon
            if hasOut {
                let out = CGPoint(x: anchor.x + handle.outOffset.x, y: anchor.y + handle.outOffset.y)
                circles.append(CurveGrabCircle(
                    kind: .tangent(index: index, isOut: true),
                    center: document.viewport.documentToView(out),
                    radius: tangentRadius
                ))
            }
            if hasIn {
                let incoming = CGPoint(x: anchor.x + handle.inOffset.x, y: anchor.y + handle.inOffset.y)
                circles.append(CurveGrabCircle(
                    kind: .tangent(index: index, isOut: false),
                    center: document.viewport.documentToView(incoming),
                    radius: tangentRadius
                ))
            }
        }
        return circles
    }

    private func curveGrabPath(_ circles: [CurveGrabCircle]) -> Path {
        var path = Path()
        for circle in circles {
            path.addEllipse(in: CGRect(
                x: circle.center.x - circle.radius,
                y: circle.center.y - circle.radius,
                width: circle.radius * 2,
                height: circle.radius * 2
            ))
        }
        return path
    }

    private func curveGrabGesture(
        strokeID: UUID,
        circles: [CurveGrabCircle],
        nodeEdit: Bool
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if curveGrab == nil {
                    let centers = circles.map(\.center)
                    let radii = circles.map(\.radius)
                    if let index = CanvasOverlayGeometry.nearestGrab(at: value.startLocation, centers: centers, radii: radii),
                       circles.indices.contains(index) {
                        curveGrab = circles[index].kind
                    }
                    curveGrabMoved = false
                }
                guard let grab = curveGrab else { return }
                let moved = hypot(value.translation.width, value.translation.height) >= anchorDragThreshold
                switch grab {
                case .anchor(let index):
                    if nodeEdit {
                        curveGrabMoved = true
                        performNodeAnchorDrag(strokeID: strokeID, index: index, location: value.location)
                    } else if moved {
                        curveGrabMoved = true
                        guard let stroke = document.stroke(with: strokeID) else { return }
                        handleMoveDragChanged(
                            strokeID: strokeID,
                            stroke: stroke,
                            value: OverlayPointerValue(
                                startLocation: value.startLocation,
                                location: value.location,
                                translation: value.translation
                            ),
                            anchorIndex: index
                        )
                    }
                case .tangent(let index, let isOut):
                    curveGrabMoved = true
                    performTangentDrag(strokeID: strokeID, index: index, isOut: isOut, location: value.location)
                }
            }
            .onEnded { _ in
                let grab = curveGrab
                let moved = curveGrabMoved
                curveGrab = nil
                curveGrabMoved = false
                switch grab {
                case .anchor(let index):
                    if nodeEdit {
                        finishNodeAnchorDrag(strokeID: strokeID)
                    } else if moved {
                        finishMoveDrag(strokeID: strokeID)
                    } else {
                        handleAnchorTap(at: index)
                    }
                case .tangent:
                    finishTangentDrag()
                case nil:
                    break
                }
            }
    }

    /// Direction used when a drag lands on the anchor and the proposed offset has no length.
    private func tangentFallbackDirection(
        anchors: [CGPoint],
        index: Int,
        isOut: Bool,
        stored: CGPoint
    ) -> CGPoint {
        if hypot(stored.x, stored.y) > CanvasOverlayGeometry.epsilon {
            return stored
        }
        guard anchors.indices.contains(index) else { return CGPoint(x: 1, y: 0) }
        let neighborIndex = isOut
            ? min(index + 1, anchors.count - 1)
            : max(index - 1, 0)
        let anchor = anchors[index]
        let neighbor = anchors[neighborIndex]
        return CGPoint(x: neighbor.x - anchor.x, y: neighbor.y - anchor.y)
    }

    /// Keeps one curve anchor from landing on another. Pairs that are already closer than
    /// the grab gap can move apart, but a drag cannot stack them further.
    private func separatedCurveAnchor(_ stroke: VectorStroke, index: Int, proposed: CGPoint) -> CGPoint {
        guard stroke.shapeType == .curve, stroke.points.indices.contains(index) else { return proposed }
        let others = stroke.points.enumerated().compactMap { offset, point in
            offset == index ? nil : point
        }
        return CanvasOverlayGeometry.separatedPoint(
            proposed: proposed,
            current: stroke.points[index],
            obstacles: others,
            minimumDistance: curveAnchorGrabGap
        )
    }

    private func strokeNodeDrag(strokeID: UUID, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                performNodeAnchorDrag(strokeID: strokeID, index: index, location: value.location)
            }
            .onEnded { _ in
                finishNodeAnchorDrag(strokeID: strokeID)
            }
    }

    private func performNodeAnchorDrag(strokeID: UUID, index: Int, location: CGPoint) {
        if nodeDragOriginPoints.isEmpty {
            document.beginInteractiveEdit()
            nodeDragOriginStroke = document.stroke(with: strokeID)
            nodeDragOriginPoints = nodeDragOriginStroke.map {
                ShapeGeometry.handlePoints(for: $0)
            } ?? []
        }
        // Edit the geometry captured at drag start. A parametric shape rewrites its
        // anchor set on every edit, so re-reading the live stroke would let `index`
        // land on a different anchor (or out of bounds) part-way through the drag.
        guard let stroke = nodeDragOriginStroke ?? document.stroke(with: strokeID),
              stroke.points.indices.contains(index) else { return }
        let rawPoint = document.viewport.viewToDocument(location)
        let snapped = resolveNodeSnap(
            rawPoint: rawPoint,
            strokeID: strokeID
        )
        let moved = ShapeGeometry.applyingMovedAnchor(
            stroke,
            at: index,
            to: separatedCurveAnchor(stroke, index: index, proposed: snapped)
        )
        document.updateStroke(moved, recordUndo: false)
        onChanged()
    }

    private func finishNodeAnchorDrag(strokeID: UUID) {
        let didEdit = !nodeDragOriginPoints.isEmpty
        nodeDragOriginPoints = []
        nodeDragOriginStroke = nil
        clearMoveSnap()
        guard didEdit else { return }
        document.reconcileIntersectionAnchors(around: [strokeID])
        onChanged()
    }

    /// Snaps a node-edit vertex to nearby object geometry (endpoints/center/on-rim/intersection).
    /// Returns the raw point when nothing snaps.
    private func resolveNodeSnap(rawPoint: CGPoint, strokeID: UUID) -> CGPoint {
        resolveMoveSnap(reference: rawPoint, excluding: strokeID)
    }

    // MARK: - Move tool routing

    @ViewBuilder
    private func moveToolOverlay(canvasSize: CGSize) -> some View {
        ZStack {
            if document.usesGroupTransform {
                multiSelectionMoveOverlay
            } else if document.selectedTextID != nil {
                textMoveOverlay
            } else if document.isReferenceImageSelected {
                imageMoveOverlay
            } else if document.selectedStrokeID != nil {
                strokeMoveOverlay
            } else {
                emptyMoveOverlay
            }

            if let rect = marqueeViewRect {
                marqueeBox(rect)
            }

            if document.moveAxisLockEnabled,
               moveTranslationAxis != .free,
               let center = moveAxisGuidelineCenter {
                moveAxisGuideline(
                    axis: moveTranslationAxis,
                    center: document.viewport.documentToView(center),
                    size: canvasSize
                )
            }
        }
    }

    /// Document-space center used for the dashed axis guideline during a locked move.
    private var moveAxisGuidelineCenter: CGPoint? {
        if let bbox = document.selectionBoundingBox(), !bbox.isNull, !bbox.isInfinite {
            return CGPoint(x: bbox.midX, y: bbox.midY)
        }
        if let frame = document.resolvedReferenceImageFrame {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        return nil
    }

    @ViewBuilder
    private func moveAxisGuideline(axis: MoveDragAxis, center: CGPoint, size: CGSize) -> some View {
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

    /// Constrains a whole-object Move delta to X or Y once the drag passes the threshold.
    /// Anchor reshape, scale, and rotate skip this path.
    private func axisLockedTranslationDelta(
        rawDelta: CGPoint,
        viewTranslation: CGSize
    ) -> CGPoint {
        moveTranslationAxis = MoveAxisLock.resolvedAxis(
            current: moveTranslationAxis,
            viewTranslation: viewTranslation,
            enabled: document.moveAxisLockEnabled
        )
        return MoveAxisLock.constrainedDelta(rawDelta, axis: moveTranslationAxis)
    }

    private func resetMoveAxisLock() {
        moveTranslationAxis = .free
    }

    /// Full-canvas catcher for tools whose handles live on this overlay. A tap
    /// on empty grid leaves the tool; a tap on another shape retargets it.
    @ViewBuilder
    private var emptyToolDismissOverlay: some View {
        SingleTouchCanvasCatcher(
            allowsDrag: false,
            onTap: { handleToolDismissTap(at: $0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleToolDismissTap(at viewPoint: CGPoint) {
        let documentPoint = document.viewport.viewToDocument(viewPoint)
        let threshold = document.viewport.viewToDocument(distance: 16)
        if document.isHitOnInactiveLayer(near: documentPoint, threshold: threshold) {
            return
        }
        if document.elementHit(near: documentPoint, threshold: threshold) == .none,
           document.group(at: documentPoint) == nil {
            onDismissTool()
            return
        }
        document.selectElement(near: documentPoint, threshold: threshold)
        onChanged()
    }

    /// Background layer shown when nothing is selected: a drag draws a marquee and
    /// a tap selects (or toggles) the element underneath.
    @ViewBuilder
    private var emptyMoveOverlay: some View {
        canvasCatcher(
            onTap: { handleMoveTap(at: $0) },
            canMove: { _ in false },
            onMoveBegan: {},
            onMoveChanged: { _ in },
            onMoveEnded: {}
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

            SingleTouchCanvasCatcher(
                onTap: { handleMoveTap(at: $0) },
                onDragChanged: { value in
                    handleBackgroundDragChanged(
                        value,
                        canMove: { point in
                            document.selectionContains(point: point, threshold: moveHitThreshold)
                                || (document.selectedGroup != nil
                                    && document.selectionBoundingBox()?.contains(point) == true)
                        },
                        onMoveBegan: { beginGroupMove() },
                        onMoveChanged: { value in
                            let raw = documentDelta(from: value.translation)
                            let locked = axisLockedTranslationDelta(
                                rawDelta: raw,
                                viewTranslation: value.translation
                            )
                            applyGroupMove(delta: locked)
                        }
                    )
                },
                onDragEnded: { value in
                    handleBackgroundDragEnded(value, onMoveEnded: { finishGroupMove() })
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            boxPath(viewCorners)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .allowsHitTesting(false)

            if document.isMoveRotateMode {
                pivotMarker(at: center)
                groupRotationHandle(pivot: center)
            }

            if let activeSnap {
                snapMarker(activeSnap)
            }
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
        document.beginInteractiveEdit()
        groupMoveStrokeOrigins = [:]
        groupMoveSnapOrigins = []
        groupMoveSnapCenters = []
        for id in document.selectedStrokeIDs {
            if let stroke = document.stroke(with: id) {
                groupMoveStrokeOrigins[id] = stroke
                groupMoveSnapOrigins.append(contentsOf: ShapeGeometry.handlePoints(for: stroke))
                if let center = ShapeGeometry.shapeCenter(for: stroke) {
                    groupMoveSnapOrigins.append(center)
                    groupMoveSnapCenters.append(center)
                }
            }
        }
        groupMoveTextOrigins = [:]
        for id in document.selectedTextIDs {
            if let position = document.textElement(with: id)?.position {
                groupMoveTextOrigins[id] = position
            }
        }
        snapHaptics.prepare()
    }

    private func applyGroupMove(delta rawDelta: CGPoint) {
        // Snap the whole group when any member's anchor/center lands on other geometry.
        var delta = translationSnappedDelta(
            origins: groupMoveSnapOrigins,
            centerOrigins: groupMoveSnapCenters,
            rawDelta: rawDelta,
            excluding: Set(groupMoveStrokeOrigins.keys)
        )
        // Object snap must not pull the group off the locked axis.
        delta = MoveAxisLock.constrainedDelta(delta, axis: moveTranslationAxis)
        // Translate each child independently from its captured origin. Overlapping
        // anchors may coincide visually but are never welded or merged.
        for (_, origin) in groupMoveStrokeOrigins {
            document.updateStroke(origin.offsettingGeometry(by: delta), recordUndo: false)
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
        groupMoveSnapOrigins = []
        groupMoveSnapCenters = []
        clearMoveSnap()
        resetMoveAxisLock()
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
                    // Capture before expand, which clears the readout when membership changes.
                    groupRotateReadoutBaseline = document.groupHandleRotationDegrees ?? 0
                    document.expandSelectionToGroupsIfNeeded()
                    if document.hasMultiSelection {
                        document.groupHandleRotationDegrees = groupRotateReadoutBaseline
                    }
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
                if document.hasMultiSelection {
                    document.groupHandleRotationDegrees = groupRotateReadoutBaseline
                        + Double(groupRotateAccumulated * 180 / .pi)
                }

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
        CanvasOverlayGeometry.marqueeRect(
            from: document.viewport.viewToDocument(start),
            to: document.viewport.viewToDocument(current)
        )
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

    /// Full-canvas 1-finger catcher used by the Move tool. A second finger fails
    /// this pan immediately so pinch-zoom on the parent can begin.
    @ViewBuilder
    private func canvasCatcher(
        onTap: @escaping (CGPoint) -> Void,
        canMove: @escaping (CGPoint) -> Bool,
        onMoveBegan: @escaping () -> Void,
        onMoveChanged: @escaping (OverlayPointerValue) -> Void,
        onMoveEnded: @escaping () -> Void
    ) -> some View {
        SingleTouchCanvasCatcher(
            onTap: onTap,
            onDragChanged: { value in
                handleBackgroundDragChanged(
                    value,
                    canMove: canMove,
                    onMoveBegan: onMoveBegan,
                    onMoveChanged: onMoveChanged
                )
            },
            onDragEnded: { value in
                handleBackgroundDragEnded(value, onMoveEnded: onMoveEnded)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shared background drag that either moves the current selection (when the
    /// drag starts over it) or draws a marquee (when it starts on empty canvas).
    private func handleBackgroundDragChanged(
        _ value: OverlayPointerValue,
        canMove: (CGPoint) -> Bool,
        onMoveBegan: () -> Void,
        onMoveChanged: (OverlayPointerValue) -> Void
    ) {
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

    private func handleBackgroundDragEnded(
        _ value: OverlayPointerValue,
        onMoveEnded: () -> Void
    ) {
        if dragIsMarquee {
            if let rect = marqueeDocRect(start: value.startLocation, current: value.location) {
                document.selectElements(in: rect)
                if document.hasCanvasSelection {
                    document.isMoveToolHighlighted = true
                }
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

    /// Move-tool tap: toggles the element under the tap in/out of the selection,
    /// or clears the selection when tapping empty canvas. A single already-selected
    /// element stays selected so a simple tap never deselects it.
    private func handleMoveTap(at viewPoint: CGPoint) {
        let documentPoint = document.viewport.viewToDocument(viewPoint)
        let threshold = document.viewport.viewToDocument(distance: 16)
        // Other layers stay visible but must not be selectable; a tap on one of
        // those shapes is ignored instead of selecting through to this layer.
        if document.isHitOnInactiveLayer(near: documentPoint, threshold: threshold) {
            return
        }
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
        case .referenceImage(let id):
            if document.selectedReferenceImageID == id {
                break
            }
            document.selectReferenceImage(id: id)
        case .none:
            if let group = document.group(at: documentPoint) {
                document.selectGroup(group)
            } else {
                document.clearElementSelection()
            }
        }
        document.isMoveToolHighlighted = document.hasCanvasSelection
        onChanged()
    }

    // MARK: - Handle tap selection

    /// One recorded tap on a handle, plus the selection state it replaced.
    private struct HandleTap {
        var index: Int
        var time: Date
        var priorSelection: Set<Int>
        var priorPivot: Int?
    }

    /// The recorded tap this one pairs with as a double-tap: same handle, close enough in time.
    private func pairedTap(_ previous: HandleTap?, index: Int, now: Date) -> HandleTap? {
        guard let previous,
              previous.index == index,
              now.timeIntervalSince(previous.time) <= handleDoubleTapWindow else { return nil }
        return previous
    }

    /// Anchor handle tap. A first tap selects just this anchor right away; a second tap
    /// inside the double-tap window undoes that and toggles the anchor into whatever was
    /// selected beforehand, which is the multi-select gesture.
    private func handleAnchorTap(at index: Int) {
        let now = Date()
        if let previous = pairedTap(lastAnchorTap, index: index, now: now) {
            lastAnchorTap = nil
            document.selectedAnchorIndices = previous.priorSelection
            document.moveRotationPivotAnchorIndex = previous.priorPivot
            document.toggleAnchorSelection(at: index)
        } else {
            lastAnchorTap = HandleTap(
                index: index,
                time: now,
                priorSelection: document.selectedAnchorIndices,
                priorPivot: document.moveRotationPivotAnchorIndex
            )
            document.selectSingleAnchor(at: index)
        }
        onChanged()
    }

    /// Fillet-corner handle tap. Same immediate-single / rewinding-double split as
    /// `handleAnchorTap`, minus the rotation pivot, which corners do not carry.
    private func handleFilletCornerTap(at index: Int) {
        let now = Date()
        if let previous = pairedTap(lastFilletCornerTap, index: index, now: now) {
            lastFilletCornerTap = nil
            document.selectedFilletCornerIndices = previous.priorSelection
            document.toggleFilletCornerSelection(at: index)
        } else {
            lastFilletCornerTap = HandleTap(
                index: index,
                time: now,
                priorSelection: document.selectedFilletCornerIndices,
                priorPivot: nil
            )
            document.selectSingleFilletCorner(at: index)
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

            canvasCatcher(
                onTap: { handleMoveTap(at: $0) },
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

            if let pivot, document.isMoveRotateMode {
                pivotMarker(at: pivot)
                rotationHandle(strokeID: strokeID, pivot: pivot)
            }

            if stroke.shapeType == .curve,
               let curveHandles = stroke.curveHandles,
               curveHandles.count == stroke.points.count {
                curveTangentConnectors(stroke: stroke, curveHandles: curveHandles)
            }

            ForEach(Array(handles.enumerated()), id: \.offset) { index, point in
                let selected = document.selectedAnchorIndices.contains(index)
                let isPivot = document.isMoveRotateMode
                    && document.moveRotationPivotAnchorIndex == index
                let ring = anchorScreenLength(base: anchorHandleSize + 6)
                ZStack {
                    handleView(style: selected ? .selectedAnchor : .move, strokeColor: stroke.strokeColor)
                    if isPivot {
                        Circle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: ring, height: ring)
                    }
                }
                .frame(width: anchorHitTarget(visible: ring), height: anchorHitTarget(visible: ring))
                .contentShape(Rectangle())
                .position(document.viewport.documentToView(point))
                .allowsHitTesting(stroke.shapeType != .curve)
                .highPriorityGesture(anchorMoveDrag(strokeID: strokeID, stroke: stroke, anchorIndex: index))
                .onTapGesture { handleAnchorTap(at: index) }
            }

            if stroke.shapeType == .curve,
               let curveHandles = stroke.curveHandles,
               curveHandles.count == stroke.points.count {
                curveTangentDots(curveHandles: curveHandles, anchors: stroke.points)
                curveGrabLayer(strokeID: strokeID, stroke: stroke, curveHandles: curveHandles, nodeEdit: false)
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

    private func applyMove(strokeID: UUID, stroke: VectorStroke, delta: CGPoint, anchorIndex: Int?) {
        guard !moveDragOriginPoints.isEmpty else { return }
        // Only a drag that began on an anchor handle edits nodes. Dragging the body
        // translates the whole object even while anchors are selected — otherwise a
        // leftover anchor selection turns a move into a reshape, which flattens the
        // curvature a Bézier keeps in `curveHandles`.
        let indices = anchorIndex == nil ? [] : document.selectedAnchorIndices

        if indices.isEmpty {
            let origin = moveDragOriginStroke ?? stroke
            document.updateStroke(origin.offsettingGeometry(by: delta), recordUndo: false)
            return
        }

        // Re-apply from the geometry captured at drag start, not from last frame's result:
        // parametric shapes re-derive their anchors on every edit (an arc re-emits a
        // different number of them as its sweep changes), so accumulating would let the
        // dragged index drift onto a different anchor part-way through the drag.
        let origin = moveDragOriginStroke ?? document.stroke(with: strokeID) ?? stroke
        var moves: [Int: CGPoint] = [:]
        for index in indices where moveDragOriginPoints.indices.contains(index) {
            let anchor = moveDragOriginPoints[index]
            moves[index] = CGPoint(x: anchor.x + delta.x, y: anchor.y + delta.y)
        }
        // One curve anchor cannot be dragged onto another. A group of anchors moving
        // together keeps its spacing, including a pair that was already close.
        if indices.count == 1,
           let index = indices.first,
           origin.shapeType == .curve,
           let proposed = moves[index],
           moveDragOriginPoints.indices.contains(index) {
            let others = moveDragOriginPoints.enumerated().compactMap { offset, point in
                offset == index ? nil : point
            }
            moves[index] = CanvasOverlayGeometry.separatedPoint(
                proposed: proposed,
                current: moveDragOriginPoints[index],
                obstacles: others,
                minimumDistance: curveAnchorGrabGap
            )
        }
        guard !moves.isEmpty else { return }
        document.updateStroke(
            ShapeGeometry.applyingMovedAnchors(origin, moves: moves),
            recordUndo: false
        )
    }

    private func anchorMoveDrag(strokeID: UUID, stroke: VectorStroke, anchorIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: anchorDragThreshold, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                handleMoveDragChanged(
                    strokeID: strokeID,
                    stroke: stroke,
                    value: OverlayPointerValue(
                        startLocation: value.startLocation,
                        location: value.location,
                        translation: value.translation
                    ),
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
        value: OverlayPointerValue,
        anchorIndex: Int?
    ) {
        if moveDragOriginPoints.isEmpty {
            document.beginInteractiveEdit()
            let current = document.stroke(with: strokeID) ?? stroke
            moveDragOriginStroke = current
            moveDragOriginPoints = ShapeGeometry.handlePoints(for: current)
            if let anchorIndex, document.selectedAnchorIndices.isEmpty {
                document.selectedAnchorIndices = [anchorIndex]
            }
            snapHaptics.prepare()
        }
        let rawDelta = documentDelta(from: value.translation)
        let baseDelta: CGPoint
        if anchorIndex == nil {
            // Whole-object body drag — axis lock applies. Anchor-handle reshape does not.
            baseDelta = axisLockedTranslationDelta(
                rawDelta: rawDelta,
                viewTranslation: value.translation
            )
        } else {
            baseDelta = rawDelta
        }
        var delta = snapAdjustedDelta(
            strokeID: strokeID,
            stroke: stroke,
            rawDelta: baseDelta,
            anchorIndex: anchorIndex,
            cursorViewPoint: value.location
        )
        if anchorIndex == nil {
            delta = MoveAxisLock.constrainedDelta(delta, axis: moveTranslationAxis)
        }
        applyMove(strokeID: strokeID, stroke: stroke, delta: delta, anchorIndex: anchorIndex)
        onChanged()
    }

    private func finishMoveDrag(strokeID: UUID) {
        let didEdit = !moveDragOriginPoints.isEmpty
        moveDragOriginPoints = []
        moveDragOriginStroke = nil
        clearMoveSnap()
        resetMoveAxisLock()
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
    /// - whole-object body drag → every anchor plus the shape center,
    /// - dragging a single anchor handle → that anchor,
    /// - anchor drag whose index is out of range → the first selected anchor.
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

        // Whole-object move: snap using every anchor (plus center) as a reference so the shape
        // locks on when any of its own points lands on other geometry.
        if anchorIndex == nil {
            let center = ShapeGeometry.shapeCenter(for: stroke)
            var origins = moveDragOriginPoints
            if let center { origins.append(center) }
            return translationSnappedDelta(
                origins: origins,
                centerOrigins: center.map { [$0] } ?? [],
                rawDelta: rawDelta,
                excluding: [strokeID]
            )
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
            excluding: strokeID
        )
        return CGPoint(x: rawDelta.x + (snapped.x - raw.x), y: rawDelta.y + (snapped.y - raw.y))
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
        excluding strokeID: UUID
    ) -> CGPoint {
        let scale = max(document.viewport.scale, 0.0001)
        let update = snapSession.update(
            rawPoint: raw,
            engine: snapEngine,
            strokes: document.interactiveStrokes(),
            enabledKinds: document.enabledSnapKinds,
            snapRadius: SnapTuning.snapRadiusPoints / scale,
            breakawayRadius: SnapTuning.breakawayRadiusPoints / scale,
            breakawayVelocity: SnapTuning.breakawayVelocityPoints / scale,
            excludedStrokeID: strokeID
        )
        if let candidate = update.candidate {
            activeSnap = candidate
            if update.didLock { snapHaptics.play() }
            return candidate.point
        }
        activeSnap = nil
        return raw
    }

    /// Corrects a raw translation delta so any anchor (or center) of the moving object(s)
    /// magnetically locks onto a nearby snap point of other geometry. Drives the indicator and
    /// haptics. Returns the delta unchanged when snapping is disabled or nothing is in range.
    private func translationSnappedDelta(
        origins: [CGPoint],
        centerOrigins: [CGPoint] = [],
        rawDelta: CGPoint,
        excluding excludedStrokeIDs: Set<UUID>
    ) -> CGPoint {
        guard !document.enabledSnapKinds.isEmpty, !(origins.isEmpty && centerOrigins.isEmpty) else {
            activeSnap = nil
            return rawDelta
        }
        let scale = max(document.viewport.scale, 0.0001)
        let update = snapSession.updateTranslation(
            origins: origins,
            centerOrigins: centerOrigins,
            rawDelta: rawDelta,
            engine: snapEngine,
            strokes: document.interactiveStrokes(),
            enabledKinds: document.enabledSnapKinds,
            snapRadius: SnapTuning.snapRadiusPoints / scale,
            breakawayRadius: SnapTuning.breakawayRadiusPoints / scale,
            excludedStrokeIDs: excludedStrokeIDs
        )
        activeSnap = update.candidate
        if update.didLock { snapHaptics.play() }
        return CGPoint(x: rawDelta.x + update.correction.x, y: rawDelta.y + update.correction.y)
    }

    private func clearMoveSnap() {
        snapSession.reset()
        activeSnap = nil
    }

    // MARK: - Copy selection

    @ViewBuilder
    private var copySelectionOverlay: some View {
        if let bbox = document.selectionBoundingBox() {
            let viewCorners = [
                CGPoint(x: bbox.minX, y: bbox.minY),
                CGPoint(x: bbox.maxX, y: bbox.minY),
                CGPoint(x: bbox.maxX, y: bbox.maxY),
                CGPoint(x: bbox.minX, y: bbox.maxY)
            ].map { document.viewport.documentToView($0) }

            boxPath(viewCorners)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Pattern preview

    @ViewBuilder
    private var patternPreviewOverlay: some View {
        ZStack {
            ForEach(patternPreviewStrokes) { stroke in
                patternPreviewPath(for: stroke)
                    .stroke(
                        Color.accentColor.opacity(0.65),
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
        if stroke.isClosed, stroke.shapeType != .arc {
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
                handleView(style: .addAnchor, strokeColor: stroke.strokeColor)
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
                handleView(style: selected ? .selectedAnchor : .fillet, strokeColor: stroke.strokeColor)
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
                    .onTapGesture { handleFilletCornerTap(at: index) }
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
                handleView(style: .edit, strokeColor: stroke.strokeColor)
                    .position(document.viewport.documentToView(corner))
                    .highPriorityGesture(scaleDrag(strokeID: strokeID, cornerIndex: index, bbox: bbox))
            }
        }
    }

    private func scaleDrag(strokeID: UUID, cornerIndex: Int, bbox: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if scaleDragOriginPoints.isEmpty {
                    document.beginInteractiveEdit()
                    scaleDragOriginPoints = document.stroke(with: strokeID)?.points ?? []
                    scaleDragOriginHandles = document.stroke(with: strokeID)?.curveHandles
                    scaleDragOriginCutouts = document.stroke(with: strokeID)?.cutoutPoints ?? []
                    scaleDragOriginCenter = CGPoint(x: bbox.midX, y: bbox.midY)
                    let corner = CanvasOverlayGeometry.cornerHandles(of: bbox)[cornerIndex]
                    scaleDragOriginCorner = corner
                    scaleDragOriginCornerDist = CanvasOverlayGeometry.cornerDistance(
                        from: scaleDragOriginCenter,
                        to: corner
                    )
                }
                guard !scaleDragOriginPoints.isEmpty else { return }
                let center = scaleDragOriginCenter
                let factors = CanvasOverlayGeometry.scaleFactors(
                    center: center,
                    corner: scaleDragOriginCorner,
                    dragPoint: document.viewport.viewToDocument(value.location),
                    uniform: document.scaleUniform,
                    originCornerDistance: scaleDragOriginCornerDist
                )
                let scaled = CanvasOverlayGeometry.scaled(
                    points: scaleDragOriginPoints,
                    about: center,
                    x: factors.x,
                    y: factors.y
                )
                if scaleDragOriginHandles != nil || !scaleDragOriginCutouts.isEmpty,
                   var stroke = document.stroke(with: strokeID) {
                    stroke.points = scaled
                    if let originHandles = scaleDragOriginHandles {
                        stroke.curveHandles = CanvasOverlayGeometry.scaled(
                            handles: originHandles,
                            x: factors.x,
                            y: factors.y
                        )
                    }
                    stroke.cutoutPoints = scaleDragOriginCutouts.map {
                        CanvasOverlayGeometry.scaled(points: $0, about: center, x: factors.x, y: factors.y)
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
                scaleDragOriginCutouts = []
                guard didEdit else { return }
                document.reconcileIntersectionAnchors(around: [strokeID])
                onChanged()
            }
    }

    // MARK: - Center anchor

    @ViewBuilder
    private func centerHandle(strokeID: UUID, stroke: VectorStroke, centerOverride: CGPoint? = nil) -> some View {
        if let center = centerOverride ?? ShapeGeometry.shapeCenter(for: stroke) {
            let side = anchorScreenLength(base: anchorHandleSize)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 0.22, green: 0.48, blue: 0.78))
                .frame(width: side, height: side)
                .shadow(color: .white.opacity(0.85), radius: 0.5)
                .frame(width: anchorHitTarget(visible: side), height: anchorHitTarget(visible: side))
                .contentShape(Rectangle())
                .position(document.viewport.documentToView(center))
                .highPriorityGesture(centerHandleDrag(strokeID: strokeID))
        }
    }

    private func centerHandleDrag(strokeID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if centerDragOriginPoints.isEmpty {
                    let stroke = document.stroke(with: strokeID)
                    centerDragOriginPoints = stroke?.points ?? []
                    if let stroke {
                        centerDragSnapCenter = ShapeGeometry.shapeCenter(for: stroke)
                        var origins = ShapeGeometry.handlePoints(for: stroke)
                        if let center = centerDragSnapCenter {
                            origins.append(center)
                        }
                        centerDragSnapOrigins = origins
                    }
                    snapHaptics.prepare()
                    document.beginInteractiveEdit()
                    centerDragOriginStroke = document.stroke(with: strokeID)
                }
                guard let origin = centerDragOriginStroke else { return }
                let rawDelta = documentDelta(from: value.translation)
                let locked = axisLockedTranslationDelta(
                    rawDelta: rawDelta,
                    viewTranslation: value.translation
                )
                var delta = translationSnappedDelta(
                    origins: centerDragSnapOrigins,
                    centerOrigins: centerDragSnapCenter.map { [$0] } ?? [],
                    rawDelta: locked,
                    excluding: [strokeID]
                )
                delta = MoveAxisLock.constrainedDelta(delta, axis: moveTranslationAxis)
                document.updateStroke(origin.offsettingGeometry(by: delta), recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                let didEdit = !centerDragOriginPoints.isEmpty
                centerDragOriginPoints = []
                centerDragOriginStroke = nil
                centerDragSnapOrigins = []
                centerDragSnapCenter = nil
                clearMoveSnap()
                resetMoveAxisLock()
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

            canvasCatcher(
                onTap: { handleMoveTap(at: $0) },
                canMove: { document.selectionContains(point: $0, threshold: moveHitThreshold) },
                onMoveBegan: {
                    textMoveOrigin = document.textElement(with: id)?.position
                    document.beginInteractiveEdit()
                },
                onMoveChanged: { value in
                    guard let origin = textMoveOrigin else { return }
                    let raw = documentDelta(from: value.translation)
                    let delta = axisLockedTranslationDelta(
                        rawDelta: raw,
                        viewTranslation: value.translation
                    )
                    document.setTextPosition(
                        id: id,
                        position: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
                        recordUndo: false
                    )
                    onChanged()
                },
                onMoveEnded: {
                    textMoveOrigin = nil
                    resetMoveAxisLock()
                    onChanged()
                }
            )

            boxPath(viewCorners)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .allowsHitTesting(false)

            if document.isMoveRotateMode {
                textRotationHandle(id: id, viewCorners: viewCorners, viewCenter: viewCenter)
            }
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

    // MARK: - Reference image (move / scale)

    @ViewBuilder
    private var imageMoveOverlay: some View {
        if document.isReferenceImageSelected,
           let corners = document.referenceImageCorners() {
            let viewCorners = corners.map { document.viewport.documentToView($0) }

            canvasCatcher(
                onTap: { handleMoveTap(at: $0) },
                canMove: { document.selectionContains(point: $0, threshold: moveHitThreshold) },
                onMoveBegan: {
                    imageMoveOrigin = document.resolvedReferenceImageFrame
                    document.beginInteractiveEdit()
                },
                onMoveChanged: { value in
                    guard let origin = imageMoveOrigin else { return }
                    let raw = documentDelta(from: value.translation)
                    let delta = axisLockedTranslationDelta(
                        rawDelta: raw,
                        viewTranslation: value.translation
                    )
                    document.setReferenceImageFrame(
                        origin.offsetBy(dx: delta.x, dy: delta.y),
                        recordUndo: false
                    )
                    onChanged()
                },
                onMoveEnded: {
                    imageMoveOrigin = nil
                    resetMoveAxisLock()
                    onChanged()
                }
            )

            boxPath(viewCorners)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .allowsHitTesting(false)

            ForEach(Array(viewCorners.enumerated()), id: \.offset) { index, corner in
                handleView(style: .edit)
                    .position(corner)
                    .highPriorityGesture(imageScaleDrag(cornerIndex: index))
            }

            if document.isMoveRotateMode, let image = document.selectedReferenceImage {
                imageRotationHandle(id: image.id, viewCorners: viewCorners, viewCenter: document.viewport.documentToView(image.center))
            }
        }
    }

    @ViewBuilder
    private var imageScaleOverlay: some View {
        if document.isReferenceImageSelected,
           let corners = document.referenceImageCorners() {
            let viewCorners = corners.map { document.viewport.documentToView($0) }

            boxPath(viewCorners)
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .allowsHitTesting(false)

            ForEach(Array(viewCorners.enumerated()), id: \.offset) { index, corner in
                handleView(style: .edit)
                    .position(corner)
                    .highPriorityGesture(imageScaleDrag(cornerIndex: index))
            }
        }
    }

    private func imageScaleDrag(cornerIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if imageScaleOrigin == nil {
                    guard let frame = document.resolvedReferenceImageFrame else { return }
                    imageScaleOrigin = frame
                    imageScaleOriginCenter = CGPoint(x: frame.midX, y: frame.midY)
                    imageScaleOriginRotation = document.selectedReferenceImage?.rotation ?? 0
                    let corner = CanvasOverlayGeometry.cornerHandles(of: frame)[cornerIndex]
                    imageScaleOriginCorner = corner
                    imageScaleOriginCornerDist = CanvasOverlayGeometry.cornerDistance(
                        from: imageScaleOriginCenter,
                        to: corner
                    )
                    document.beginInteractiveEdit()
                }
                guard let origin = imageScaleOrigin else { return }
                let center = imageScaleOriginCenter
                let worldDrag = document.viewport.viewToDocument(value.location)
                let dragPoint = ReferenceImage.rotate(worldDrag, around: center, by: -imageScaleOriginRotation)
                let factors = CanvasOverlayGeometry.scaleFactors(
                    center: center,
                    corner: imageScaleOriginCorner,
                    dragPoint: dragPoint,
                    uniform: document.scaleUniform,
                    originCornerDistance: imageScaleOriginCornerDist
                )
                document.setReferenceImageFrame(
                    CanvasOverlayGeometry.scaledFrame(
                        origin: origin,
                        center: center,
                        x: factors.x,
                        y: factors.y
                    ),
                    recordUndo: false
                )
                onChanged()
            }
            .onEnded { _ in
                imageScaleOrigin = nil
                imageScaleOriginRotation = 0
                onChanged()
            }
    }

    @ViewBuilder
    private func imageRotationHandle(id: UUID, viewCorners: [CGPoint], viewCenter: CGPoint) -> some View {
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
                .highPriorityGesture(imageRotateDrag(id: id))
        }
    }

    private func imageRotateDrag(id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let currentDoc = document.viewport.viewToDocument(value.location)
                if imageRotateOriginRadians == nil {
                    guard let image = document.referenceImage(with: id) else { return }
                    imageRotateOriginRadians = image.rotation
                    imageRotatePivot = image.center
                    imageRotatePreviousAngle = atan2(
                        currentDoc.y - image.center.y,
                        currentDoc.x - image.center.x
                    )
                    imageRotateAccumulated = 0
                    document.beginInteractiveEdit()
                }
                guard let origin = imageRotateOriginRadians else { return }
                let angle = atan2(currentDoc.y - imageRotatePivot.y, currentDoc.x - imageRotatePivot.x)
                let rawStep = angle - imageRotatePreviousAngle
                let step = atan2(sin(rawStep), cos(rawStep))
                imageRotateAccumulated += step
                imageRotatePreviousAngle = angle
                document.setReferenceImageRotation(radians: origin + imageRotateAccumulated, id: id, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                imageRotateOriginRadians = nil
                imageRotatePreviousAngle = 0
                imageRotateAccumulated = 0
                onChanged()
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
                    textScaleOriginDist = CanvasOverlayGeometry.cornerDistance(
                        from: element.center,
                        to: element.corners()[cornerIndex]
                    )
                    document.beginInteractiveEdit()
                }
                guard let origin = textScaleOrigin else { return }
                let newSize = CanvasOverlayGeometry.scaledFontSize(
                    origin: origin.fontSize,
                    center: textScaleOriginCenter,
                    dragPoint: document.viewport.viewToDocument(value.location),
                    originDistance: textScaleOriginDist
                )
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
        case edit, move, command, selectedAnchor, fillet, addAnchor
    }

    private func handleView(style: HandleStyle, strokeColor: CodableColor? = nil) -> some View {
        let fill: Color
        let halo: Color
        let outline: Color?
        if style == .selectedAnchor {
            fill = .blue
            halo = .white.opacity(0.85)
            outline = nil
        } else if let strokeColor {
            fill = Color(red: strokeColor.red, green: strokeColor.green, blue: strokeColor.blue)
            if Self.isLightAnchorColor(strokeColor) {
                halo = .black.opacity(0.45)
                outline = Color(white: 0.15)
            } else {
                halo = .white.opacity(0.85)
                outline = nil
            }
        } else {
            fill = Color(white: 0.28)
            halo = .white.opacity(0.85)
            outline = nil
        }
        let side = anchorScreenLength(base: anchorHandleSize)
        return Rectangle()
            .fill(fill)
            .overlay {
                if let outline {
                    Rectangle().strokeBorder(outline, lineWidth: 1)
                }
            }
            .frame(width: side, height: side)
            .shadow(color: halo, radius: 0.5)
            .frame(width: anchorHitTarget(visible: side), height: anchorHitTarget(visible: side))
            .contentShape(Rectangle())
    }

    /// On-screen side of an anchor whose 1× size is `base`. Grows with zoom above 1×.
    private func anchorScreenLength(base: CGFloat) -> CGFloat {
        CanvasOverlayGeometry.anchorScreenLength(base: base, scale: document.viewport.scale)
    }

    /// Hit target stays at least `anchorTouchTargetSize`, and widens if the visible mark would be clipped.
    private func anchorHitTarget(visible: CGFloat) -> CGFloat {
        max(anchorTouchTargetSize, visible)
    }

    /// On-screen diameter of a tangent handle. Grows with the dot once zoom exceeds the floor.
    private var curveTangentHitExtent: CGFloat {
        CanvasOverlayGeometry.screenGrabExtent(
            minimum: CanvasOverlayGeometry.curveTangentHitDiameter,
            mark: anchorHandleSize,
            scale: document.viewport.scale
        )
    }

    /// Document distance between curve anchors so their grab squares do not stack.
    private var curveAnchorGrabGap: CGFloat {
        let anchorHit = anchorHitTarget(visible: anchorScreenLength(base: anchorHandleSize))
        return document.viewport.viewToDocument(distance: anchorHit)
    }

    /// Light stroke colors need a dark edge so the anchor still reads on the line and the canvas.
    private static func isLightAnchorColor(_ color: CodableColor) -> Bool {
        let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
        return luminance > 0.72
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
