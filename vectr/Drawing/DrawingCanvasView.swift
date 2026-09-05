//
//  DrawingCanvasView.swift
//  vectr
//

import SwiftUI

struct DrawingCanvasView: UIViewRepresentable {
    @Bindable var document: VectrDocument
    var isCommandMode: Bool = false
    var activeCategory: ToolCategory?
    var commandPreviewPoints: [CGPoint] = []
    var commandControlPoints: [CGPoint] = []
    var commandCanFinish: Bool = false
    var commandRevision: Int = 0
    var strokeCount: Int = 0
    var geometryRevision: Int = 0
    var contentRevision: Int = 0
    var visualGridSpacing: CGFloat = 20
    var measurementUnit: MeasurementUnit = .points
    var isConstructionPreview: Bool = false
    var commandPreviewClosed: Bool = false
    var allowsDragDraw: Bool = false
    var lineVariant: LineVariant = .line
    var circleVariant: CircleVariant = .center
    var rectangleVariant: RectangleVariant = .center
    var canvasBackgroundColor: Color = Color(hex: AppearanceSettings.defaultCanvasHex)
    var onCanvasTap: ((CGPoint) -> Void)?
    var onTwoFingerTap: (() -> Void)?
    var onStrokeSelected: ((VectorStroke?) -> Void)?
    var onDragDrawBegan: ((CGPoint) -> Void)?
    var onDragDrawChanged: ((CGPoint, CGPoint) -> Void)?
    var onDragDrawEnded: ((CGPoint, CGPoint) -> Void)?
    var curveDraft: CurveDraftSession?
    var onCurveCommitted: (([CGPoint]) -> Void)?
    var onLayoutMetrics: ((CGSize, UIEdgeInsets) -> Void)?
    var onCanvasReady: ((DrawingCanvasUIView) -> Void)?

    func makeUIView(context: Context) -> DrawingCanvasUIView {
        let view = DrawingCanvasUIView(document: document)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.delegate = context.coordinator
        configure(view)
        context.coordinator.canvasView = view
        onCanvasReady?(view)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DrawingCanvasUIView, context: Context) -> CGSize {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }

    func updateUIView(_ uiView: DrawingCanvasUIView, context: Context) {
        context.coordinator.document = document
        context.coordinator.onStrokeSelected = onStrokeSelected

        let didSwapDocument = uiView.document !== document
        if didSwapDocument {
            uiView.document = document
        }

        configure(uiView)

        let geometryChanged = context.coordinator.consumeGeometryChange(
            strokeCount: strokeCount,
            geometryRevision: geometryRevision,
            didSwapDocument: didSwapDocument
        )
        let commandChanged = context.coordinator.consumeCommandChange(
            commandRevision: commandRevision,
            didSwapDocument: didSwapDocument
        )
        let selectionChanged = context.coordinator.consumeSelectionChange(
            selectedStrokeID: document.selectedStrokeID,
            didSwapDocument: didSwapDocument
        )
        let viewportChanged = context.coordinator.consumeViewportChange(
            viewport: document.viewport,
            didSwapDocument: didSwapDocument
        )
        let gridDisplayChanged = context.coordinator.consumeGridDisplayChange(
            visualGridSpacing: visualGridSpacing,
            measurementUnit: measurementUnit,
            didSwapDocument: didSwapDocument
        )
        let referenceImageChanged = context.coordinator.consumeReferenceImageChange(
            data: document.referenceImageData,
            frame: document.referenceImageFrame,
            didSwapDocument: didSwapDocument
        )

        if geometryChanged {
            uiView.reloadStrokes()
        }

        var didRefreshViewport = false
        var needsViewportRefresh = didSwapDocument || viewportChanged || gridDisplayChanged || referenceImageChanged
        if viewportChanged && context.coordinator.consumeCanvasHandledViewportUpdate() {
            needsViewportRefresh = didSwapDocument || gridDisplayChanged || referenceImageChanged
        }

        if needsViewportRefresh {
            uiView.refreshViewport()
            didRefreshViewport = true
        }

        if commandChanged && !didRefreshViewport {
            uiView.refreshCommandPreview()
        }

        if selectionChanged && !didRefreshViewport && !geometryChanged {
            uiView.refreshStrokeHighlight()
        }

        _ = contentRevision
    }

    private func configure(_ uiView: DrawingCanvasUIView) {
        let resolvedCanvasFill = UIColor(canvasBackgroundColor)
        if uiView.canvasFillColor != resolvedCanvasFill {
            uiView.canvasFillColor = resolvedCanvasFill
        }
        if uiView.isCommandMode != isCommandMode {
            uiView.isCommandMode = isCommandMode
        }
        if uiView.activeCategory != activeCategory {
            uiView.activeCategory = activeCategory
        }
        if uiView.commandPreviewPoints != commandPreviewPoints {
            uiView.commandPreviewPoints = commandPreviewPoints
        }
        if uiView.commandControlPoints != commandControlPoints {
            uiView.commandControlPoints = commandControlPoints
        }
        if uiView.commandCanFinish != commandCanFinish {
            uiView.commandCanFinish = commandCanFinish
        }
        if uiView.isConstructionPreview != isConstructionPreview {
            uiView.isConstructionPreview = isConstructionPreview
        }
        if uiView.commandPreviewClosed != commandPreviewClosed {
            uiView.commandPreviewClosed = commandPreviewClosed
        }
        if uiView.allowsDragDraw != allowsDragDraw {
            uiView.allowsDragDraw = allowsDragDraw
        }
        if uiView.lineVariant != lineVariant {
            uiView.lineVariant = lineVariant
        }
        if uiView.circleVariant != circleVariant {
            uiView.circleVariant = circleVariant
        }
        if uiView.rectangleVariant != rectangleVariant {
            uiView.rectangleVariant = rectangleVariant
        }
        uiView.onCanvasTap = onCanvasTap
        uiView.onTwoFingerTap = onTwoFingerTap
        uiView.onDragDrawBegan = onDragDrawBegan
        uiView.onDragDrawChanged = onDragDrawChanged
        uiView.onDragDrawEnded = onDragDrawEnded
        if uiView.curveDraft !== curveDraft {
            uiView.curveDraft = curveDraft
        }
        uiView.onCurveCommitted = onCurveCommitted
        uiView.onLayoutMetrics = onLayoutMetrics
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, onStrokeSelected: onStrokeSelected)
    }

    final class Coordinator: NSObject, DrawingCanvasDelegate {
        struct ViewportSnapshot: Equatable {
            var scale: CGFloat
            var translationX: CGFloat
            var translationY: CGFloat
        }

        var document: VectrDocument
        var onStrokeSelected: ((VectorStroke?) -> Void)?
        weak var canvasView: DrawingCanvasUIView?
        private var lastStrokeCount: Int?
        private var lastGeometryRevision: Int?
        private var lastCommandRevision: Int?
        private var lastSelectedStrokeID: UUID?
        private var lastViewportSnapshot: ViewportSnapshot?
        private var lastVisualGridSpacing: CGFloat?
        private var lastMeasurementUnit: MeasurementUnit?
        private var lastReferenceImageData: Data?
        private var lastReferenceImageFrame: CGRect?
        private var viewportHandledByCanvas = false

        init(document: VectrDocument, onStrokeSelected: ((VectorStroke?) -> Void)?) {
            self.document = document
            self.onStrokeSelected = onStrokeSelected
        }

        func consumeGeometryChange(strokeCount: Int, geometryRevision: Int, didSwapDocument: Bool) -> Bool {
            defer {
                lastStrokeCount = strokeCount
                lastGeometryRevision = geometryRevision
            }
            if didSwapDocument { return true }
            guard let lastStrokeCount, let lastGeometryRevision else { return true }
            return lastStrokeCount != strokeCount || lastGeometryRevision != geometryRevision
        }

        func consumeCommandChange(commandRevision: Int, didSwapDocument: Bool) -> Bool {
            defer { lastCommandRevision = commandRevision }
            if didSwapDocument { return true }
            guard let lastCommandRevision else { return true }
            return lastCommandRevision != commandRevision
        }

        func consumeSelectionChange(selectedStrokeID: UUID?, didSwapDocument: Bool) -> Bool {
            defer { lastSelectedStrokeID = selectedStrokeID }
            if didSwapDocument { return true }
            return lastSelectedStrokeID != selectedStrokeID
        }

        func consumeViewportChange(viewport: ViewportTransform, didSwapDocument: Bool) -> Bool {
            let snapshot = ViewportSnapshot(
                scale: viewport.scale,
                translationX: viewport.translation.x,
                translationY: viewport.translation.y
            )
            defer { lastViewportSnapshot = snapshot }
            if didSwapDocument { return true }
            guard let lastViewportSnapshot else { return true }
            return lastViewportSnapshot != snapshot
        }

        func consumeGridDisplayChange(
            visualGridSpacing: CGFloat,
            measurementUnit: MeasurementUnit,
            didSwapDocument: Bool
        ) -> Bool {
            defer {
                lastVisualGridSpacing = visualGridSpacing
                lastMeasurementUnit = measurementUnit
            }
            if didSwapDocument { return true }
            guard let lastVisualGridSpacing, let lastMeasurementUnit else { return true }
            return abs(lastVisualGridSpacing - visualGridSpacing) > 0.0001 || lastMeasurementUnit != measurementUnit
        }

        func consumeReferenceImageChange(data: Data?, frame: CGRect?, didSwapDocument: Bool) -> Bool {
            defer {
                lastReferenceImageData = data
                lastReferenceImageFrame = frame
            }
            if didSwapDocument { return true }
            if lastReferenceImageData != data { return true }
            if lastReferenceImageFrame != frame { return true }
            return false
        }

        func consumeCanvasHandledViewportUpdate() -> Bool {
            let handled = viewportHandledByCanvas
            viewportHandledByCanvas = false
            return handled
        }

        func canvasDidUpdate(document: VectrDocument) {
            self.document = document
            viewportHandledByCanvas = true
        }

        func canvasDidSelectStroke(_ stroke: VectorStroke?) {
            onStrokeSelected?(stroke)
        }
    }
}
