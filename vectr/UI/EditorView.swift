//
//  EditorView.swift
//  vectr
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EditorView: View {
    var projectURL: URL?
    var projectLibrary: ProjectLibrary?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = DocumentStore()
    @State private var commandSession = ShapeCommandSession()
    @State private var curveDraft = CurveDraftSession()
    private let objectSnapEngine = PathSnapEngine.makeDefault()
    @State private var showExportSheet = false
    @State private var showImportPicker = false
    @State private var pendingShareAfterDismiss = false
    @State private var exportFormat: ExportFormat = .vectr
    @State private var exportQuality: ExportQuality = .medium
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var canvasSize: CGSize = .zero
    @State private var canvasViewSize: CGSize = .zero
    @State private var canvasSafeAreaInsets: UIEdgeInsets = .zero
    @State private var showSettings = false
    @State private var chromeInsets = ViewportTransform.ChromeInsets()
    @State private var statusMessage: String?
    @State private var showUnsavedAlert = false
    @State private var pendingDismiss = false
    @State private var dragDrawStart: CGPoint?
    @State private var dragDrawEnd: CGPoint?
    @State private var isDragDrawing = false
    @State private var isArcDragActive = false
    @State private var arcDragPreviousAngle: CGFloat?
    @State private var arcDragAccumulatedSweep: CGFloat = 0
    @State private var showCommandPanel = true
    @State private var showLayersPanel = false
    @State private var hasInitializedDrawingSession = false
    @State private var editingTextID: UUID?
    @State private var editorMode: EditorMode = .design
    @State private var savedDesignViewport: ViewportTransform?
    @State private var printLayoutNeedsInitialFit = false
    @State private var printCanvasRect: CGRect = .zero
    @State private var lastSavedSnapshot: DocumentSnapshot?
    @State private var patternSettings = PatternSettings()
    @State private var patternPreviewStrokes: [VectorStroke] = []
    @State private var trimPreviewPoints: [CGPoint] = []
    @State private var trimPreviewStrokeWidth: CGFloat = 1
    @State private var trimFlashTask: Task<Void, Never>?
    @State private var pendingTrim: PendingTrim?
    @State private var persistTask: Task<Void, Never>?
    @State private var isLoadingProject = false
    @State private var isExporting = false
    @State private var didStartLoad = false
    @State private var designCanvasHandle = CanvasViewportHandle()
    @State private var printCanvasHandle = CanvasViewportHandle()
    @State private var pendingThumbnailRefresh = false
    @AppStorage(AppearanceSettings.canvasColorKey) private var canvasColorHex = AppearanceSettings.defaultCanvasHex

    init(projectURL: URL? = nil, projectLibrary: ProjectLibrary? = nil) {
        self.projectURL = projectURL
        self.projectLibrary = projectLibrary
    }

    var body: some View {
        Group {
            if editorMode == .printLayout {
                PrintLayoutView(
                    document: store.document,
                    canUndo: store.document.canUndo,
                    canRedo: store.document.canRedo,
                    onBack: handleBack,
                    onUndo: performUndo,
                    onRedo: {
                        store.document.redo()
                        store.markDirty()
                    },
                    onSwitchToDesign: { switchToDesignMode() },
                    onExport: preparePrintExport,
                    onChanged: {
                        store.markDirty()
                    },
                    onLayoutReady: { rect in handlePrintLayoutReady(in: rect) },
                    onFitToGrid: { rect in fitPrintLayoutToGrid(in: rect) },
                    viewportHandle: printCanvasHandle
                )
            } else {
                designEditorBody
            }
        }
        .navigationBarBackButtonHidden(true)
        .overlay {
            if isLoadingProject || isExporting {
                ZStack {
                    Color.black.opacity(0.28)
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(isExporting ? "Exporting…" : "Loading…")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .ignoresSafeArea()
                .allowsHitTesting(true)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                document: store.document,
                fileName: $store.fileName,
                onFileNameChanged: handleFileNameChanged
            )
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: ImportRouter.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showExportSheet, onDismiss: {
            guard pendingShareAfterDismiss else { return }
            pendingShareAfterDismiss = false
            presentDesignShare()
        }) {
            ExportFormatSheet { format, quality in
                exportFormat = format
                exportQuality = quality
                pendingShareAfterDismiss = true
            }
        }
        .background {
            ShareSheetPresenter(isPresented: $showShareSheet, items: shareItems) {
                shareItems = []
            }
        }
        .onAppear {
            store.persistDocument = { Task { await persistDocument(refreshThumbnail: false) } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                flushAutoSaveInBackground()
            }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Save") {
                pendingDismiss = true
                saveDocumentNow()
            }
            Button("Discard", role: .destructive) {
                discardChangesAndDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save changes before leaving?")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var designEditorBody: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .coordinateSpace(name: "editor")

                DrawingCanvasView(
                    document: store.document,
                    activeCategory: store.document.activeCategory,
                    commandPreviewPoints: commandSession.previewPoints,
                    commandControlPoints: commandSession.displayControlPoints,
                    commandCanFinish: commandSession.canFinish,
                    commandRevision: commandSession.revision,
                    strokeCount: store.document.strokes.count,
                    geometryRevision: store.document.geometryRevision,
                    selectedStrokeID: store.document.selectedStrokeID,
                    selectedTextID: store.document.selectedTextID,
                    selectedStrokeIDs: store.document.selectedStrokeIDs,
                    referenceImageIDs: store.document.visibleReferenceImages().map(\.id),
                    referenceImageFrames: store.document.visibleReferenceImages().map(\.frame),
                    visualGridSpacing: UnitConversion.visualGridSpacing(
                        sliderValue: store.document.settings.defaultGridSpacingInUnits,
                        unit: store.document.settings.units
                    ),
                    measurementUnit: store.document.settings.units,
                    gridVisible: store.document.grid.isVisible,
                    isConstructionPreview: store.document.activeCategory == .line
                        && store.document.lineVariant == .constructionLine,
                    commandPreviewClosed: commandSession.canFinish
                        && (store.document.activeCategory == .rectangle
                            || store.document.activeCategory == .circle),
                    allowsDragDraw: allowsDragDraw,
                    trimPreviewPoints: trimPreviewPoints,
                    trimPreviewStrokeWidth: trimPreviewStrokeWidth,
                    lineVariant: store.document.lineVariant,
                    circleVariant: store.document.circleVariant,
                    rectangleVariant: store.document.rectangleVariant,
                    canvasBackgroundColor: Color(hex: canvasColorHex),
                    onCanvasTap: handleCanvasTap,
                    onStrokeSelected: { stroke in
                        if let stroke {
                            store.document.selectStrokeConsideringGroups(stroke.id)
                        } else {
                            store.document.clearElementSelection()
                        }
                    },
                    onDragDrawBegan: { start in
                        if beginArcDragIfNeeded(at: start) {
                            return
                        }
                        startDrawingSessionIfNeeded()
                        dragDrawStart = start
                        dragDrawEnd = start
                        isDragDrawing = true
                    },
                    onDragDrawChanged: { start, end in
                        if updateArcDragIfNeeded(to: end) {
                            return
                        }
                        if !isDragDrawing {
                            dragDrawStart = start
                            isDragDrawing = true
                        }
                        dragDrawEnd = end
                    },
                    onDragDrawEnded: { start, end in
                        if endArcDragIfNeeded(at: end) {
                            return
                        }
                        commitDragDraw(start: start, end: end)
                        isDragDrawing = false
                        dragDrawStart = nil
                        dragDrawEnd = nil
                    },
                    curveDraft: curveDraft,
                    onCurveCommitted: commitCurve,
                    onLayoutMetrics: updateCanvasLayoutMetrics,
                    viewportHandle: designCanvasHandle
                )
                .ignoresSafeArea()
                .transaction { $0.animation = nil }

                if isDragDrawing, let start = dragDrawStart, let end = dragDrawEnd,
                   let category = store.document.activeCategory {
                    LiveDimensionOverlay(
                        document: store.document,
                        start: start,
                        end: end,
                        category: category,
                        lineVariant: store.document.lineVariant,
                        circleVariant: store.document.circleVariant,
                        rectangleVariant: store.document.rectangleVariant
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
                }

                CanvasOverlayView(
                    document: store.document,
                    commandSession: commandSession,
                    patternPreviewStrokes: patternPreviewStrokes,
                    onChanged: {
                        if commandSession.isRefiningAttachedStroke {
                            _ = syncAttachedStrokeFromSession(recordUndo: false)
                        }
                        store.markDirty()
                    },
                    onEditText: { beginTextEditing($0) },
                    onDismissTool: { dismissActiveTool() }
                )
                .ignoresSafeArea()
                .allowsHitTesting(canvasOverlayAcceptsHits)
                .transaction { $0.animation = nil }

                DimensionOverlayView(document: store.document) {
                    store.markDirty()
                }
                .ignoresSafeArea()
                .transaction { $0.animation = nil }

                ViewportNavigationInstaller(
                    document: store.document,
                    viewportHandle: designCanvasHandle,
                    onTwoFingerTap: handleDesignUndo
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if store.document.activeCategory == .fillet {
                    FilletRadiusPanelView(
                        document: store.document,
                        units: store.document.settings.units,
                        onApply: {
                            store.document.clearToolSelections()
                            store.markDirty()
                        },
                        onCancel: {
                            store.document.clearToolSelections()
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if store.document.activeCategory == .move,
                          !store.document.selectionIsEmpty {
                    MoveRotatePanelView(
                        document: store.document,
                        units: store.document.settings.units
                    ) {
                        store.markDirty()
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if store.document.activeCategory == .addAnchor {
                    AddAnchorPanelView(
                        document: store.document,
                        onApply: { store.markDirty() },
                        onCancel: {
                            store.document.clearToolSelections()
                        },
                        onStatus: { statusMessage = $0 }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if store.document.activeCategory == .pattern {
                    PatternPanelView(
                        document: store.document,
                        units: store.document.settings.units,
                        settings: $patternSettings,
                        onPreviewChange: updatePatternPreview,
                        onApply: {
                            patternPreviewStrokes = []
                            store.markDirty()
                        },
                        onCancel: {
                            patternPreviewStrokes = []
                            store.document.clearToolSelections()
                        },
                        onStatus: { statusMessage = $0 }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if store.document.activeCategory == .copy {
                    CopyPastePanelView(
                        document: store.document,
                        onChanged: { store.markDirty() },
                        onStatus: { statusMessage = $0 }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .overlay(alignment: .topLeading) {
                if let editingTextID {
                    TextToolPanelView(
                        document: store.document,
                        elementID: editingTextID,
                        onChanged: { store.markDirty() },
                        onDone: { endTextEditingIfNeeded() }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .overlay(alignment: .topLeading) {
                if commandSession.isActive && showCommandPanel {
                    ToolCommandPanelView(
                        session: commandSession,
                        document: store.document,
                        units: store.document.settings.units,
                        grid: store.document.grid,
                        documentSettings: store.document.settings,
                        snapEnabled: drawingSnapEnabled,
                        onSubmitPoint: handleCommandPointSubmitted,
                        onDone: { commitCommandShape(restart: true) },
                        onCancel: {
                            updateChromeInsets()
                        },
                        onVariantChanged: { startDrawingSessionIfNeeded() }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .overlay(alignment: .topLeading) {
                if store.document.activeCategory == .type && editingTextID == nil {
                    FontPickerView(
                        document: store.document,
                        library: FontLibrary.shared,
                        onChanged: { store.markDirty() },
                        onCancel: {
                            store.document.clearActiveTool()
                            updateChromeInsets()
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .overlay(alignment: .topLeading) {
                if store.document.activeCategory == .scale {
                    ScaleToolPanelView(document: store.document) {
                        store.markDirty()
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .overlay(alignment: .bottomLeading) {
                SnapToggleBar(document: store.document)
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .topTrailing) {
                LayersPanelView(document: store.document, isExpanded: $showLayersPanel) {
                    store.markDirty()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                RecenterCanvasButton {
                    recenterAnimated()
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
            .overlay(alignment: .bottom) {
                if statusMessage != nil {
                    Text(statusMessage ?? "")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .task(id: statusMessage) {
                            try? await Task.sleep(for: .seconds(2))
                            statusMessage = nil
                        }
                }
            }
            .onAppear {
                canvasSize = geometry.size
                updateChromeInsets()
                loadProjectIfNeeded()
                applyInitialViewportLayoutIfNeeded()
                if !hasInitializedDrawingSession {
                    hasInitializedDrawingSession = true
                    startDrawingSessionIfNeeded()
                }
            }
            .onChange(of: geometry.size) { _, size in
                canvasSize = size
                updateChromeInsets()
                applyInitialViewportLayoutIfNeeded()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            EditorToolbarView(
                document: store.document,
                canUndo: store.document.canUndo || curveDraft.canUndo,
                canRedo: curveDraft.canRedo || store.document.canRedo,
                onBack: handleBack,
                onUndo: handleDesignUndo,
                onRedo: handleDesignRedo,
                onSettings: { showSettings = true },
                onShare: { showExportSheet = true },
                onImport: { showImportPicker = true },
                onSave: { saveDocumentNow() },
                onToolSelected: handleToolSelected,
                onSwitchToPrintLayout: { switchToPrintLayoutMode() },
                onVisibilityToggled: {
                    store.markDirty()
                }
            )
        }
    }

    private func switchToPrintLayoutMode() {
        savedDesignViewport = store.document.viewport
        editorMode = .printLayout
        store.document.clearPrintSelection()
        store.document.autoPositionDesignOnPrintGrid()
        printLayoutNeedsInitialFit = true
        fitPrintLayoutToGrid()
        store.markDirty()
    }

    /// Fits all sheets into view the first time the layout appears, then only
    /// re-centers (preserving the user's zoom) on later size changes / rotations.
    private func handlePrintLayoutReady(in rect: CGRect) {
        if printLayoutNeedsInitialFit {
            printLayoutNeedsInitialFit = false
            fitPrintLayoutToGrid(in: rect)
        } else {
            // Keep size tracking current; the print canvas recenters itself
            // during bounds changes so rotation does not wait on this callback.
            canvasSize = rect.size
            printCanvasRect = rect
        }
    }

    private func switchToDesignMode() {
        editorMode = .design
        if let savedDesignViewport {
            store.document.viewport = savedDesignViewport
        }
        designCanvasHandle.refreshViewport()
    }

    private func fitPrintLayoutToGrid(in rect: CGRect? = nil) {
        let layoutRect = rect ?? printCanvasRect
        let layoutSize = layoutRect.size
        guard layoutSize.width > 0, layoutSize.height > 0 else { return }
        canvasSize = layoutSize
        printCanvasRect = layoutRect
        let points = store.document.allPrintLayoutPoints()
        store.document.viewport.fitToPoints(
            points,
            in: layoutSize,
            margin: 16,
            chrome: ViewportTransform.ChromeInsets(left: 16, right: 16, top: 40, bottom: 16),
            minScale: ViewportTransform.minScale
        )

        // Zoom in a bit past a perfect fit so the sheets aren't so small, then
        // re-center on the grid. The outermost sheets may extend slightly past
        // the edges, which is fine.
        let zoomInFactor: CGFloat = 1.8
        store.document.viewport.scale = min(
            store.document.viewport.scale * zoomInFactor,
            ViewportTransform.maxScale
        )
        centerPrintLayoutWithoutRescaling(in: layoutRect)
    }

    private func centerPrintLayoutWithoutRescaling(in rect: CGRect? = nil) {
        let layoutRect = rect ?? printCanvasRect
        let layoutSize = layoutRect.size
        guard layoutSize.width > 0, layoutSize.height > 0 else { return }
        canvasSize = layoutSize
        printCanvasRect = layoutRect

        let points = store.document.allPrintLayoutPoints()
        guard let bounds = boundingRect(for: points) else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let currentScale = store.document.viewport.scale
        // The canvas is drawn full-screen (it ignores the safe area / toolbar),
        // so center on the midpoint of the visible layout region in canvas
        // coordinates rather than on size/2.
        let viewCenter = CGPoint(x: layoutRect.midX, y: layoutRect.midY)
        store.document.viewport.translation = CGPoint(
            x: viewCenter.x - center.x * currentScale,
            y: viewCenter.y - center.y * currentScale
        )
        printCanvasHandle.refreshViewport()
    }

    private func boundingRect(for points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    private func preparePrintExport() {
        Task { await exportPrintLayout() }
    }

    private func exportPrintLayout() async {
        isExporting = true
        defer { isExporting = false }
        let snapshot = store.document.makeSnapshot()
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(store.fileName)-tiled.pdf")
            try await PersistenceWorker.shared.writeTiledPDF(snapshot: snapshot, to: tempURL)
            await presentShare(url: tempURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var drawingSnapEnabled: Bool {
        store.document.snapEnabled && store.document.grid.snapEnabled
    }

    /// Object snap (endpoints/midpoints/on-rim) resolved from the committed point, so tap-to-place,
    /// drag-draw, and typed-coordinate commits land exactly on real geometry. Object snap takes priority over the grid.
    private func objectSnappedPoint(
        _ point: CGPoint,
        alignmentOrigin: CGPoint? = nil,
        alignmentThrough: CGPoint? = nil
    ) -> CGPoint? {
        let enabledKinds = store.document.enabledSnapKinds
        guard !enabledKinds.isEmpty else { return nil }
        let scale = max(store.document.viewport.scale, 0.0001)
        let alignmentTolerance = alignmentOrigin == nil ? 0 : 4 / scale
        let endpointRadius = shouldAngleSnapDrawnSegment
            ? SnapTuning.lineEndpointSnapRadiusPoints / scale
            : nil
        return objectSnapEngine.closestCandidate(
            to: point,
            within: SnapTuning.snapRadiusPoints / scale,
            strokes: store.document.interactiveStrokes(),
            excludedStrokeID: commandSession.attachedStrokeID,
            enabledKinds: enabledKinds,
            alignmentOrigin: alignmentOrigin,
            alignmentThrough: alignmentThrough,
            alignmentTolerance: alignmentTolerance,
            endpointRadius: endpointRadius
        )?.point
    }

    private func snapDrawingInput(_ point: CGPoint, referenceStart: CGPoint? = nil) -> CGPoint {
        snapDrawingEndpoint(
            point,
            origin: referenceStart,
            applyAngleSnap: shouldAngleSnapDrawnSegment && referenceStart != nil,
            grid: store.document.grid,
            settings: store.document.settings,
            gridSnapEnabled: drawingSnapEnabled,
            scale: store.document.viewport.scale,
            objectSnap: { query, alignmentOrigin, alignmentThrough in
                objectSnappedPoint(
                    query,
                    alignmentOrigin: alignmentOrigin,
                    alignmentThrough: alignmentThrough
                )
            }
        )
    }

    private var shouldAngleSnapDrawnSegment: Bool {
        store.document.activeCategory == .line && store.document.lineVariant != .arc
    }

    private var canvasOverlayAcceptsHits: Bool {
        if commandSession.isActive { return false }
        switch store.document.activeCategory {
        case .move, .scale, .fillet, nil:
            return true
        case .type:
            // With a text selected, the overlay handles move/scale/tap-to-edit;
            // with nothing selected, taps pass through so a new text can be placed.
            return store.document.selectedTextID != nil
        case .delete, .addAnchor, .pattern, .trim, .dimensions, .copy:
            // Let canvas taps pass through so delete/add-anchor/pattern/trim/dimensions/copy can
            // target the shape directly (trim has no overlay handles; dimensions shows labels only).
            return false
        default:
            return store.document.selectedStrokeID != nil
        }
    }

    private var allowsDragDraw: Bool {
        switch store.document.activeCategory {
        case .line, .curve:
            return true
        case .circle:
            return store.document.circleVariant == .center
                || store.document.circleVariant == .edge
                || store.document.circleVariant == .ellipse
        case .rectangle:
            return store.document.rectangleVariant == .center
                || store.document.rectangleVariant == .edge
        default:
            return false
        }
    }

    private var shouldAutoCommitAfterPoint: Bool {
        switch store.document.activeCategory {
        case .line where store.document.lineVariant == .arc:
            return false
        case .rectangle where store.document.rectangleVariant == .center:
            return false
        default:
            return true
        }
    }

    private var canBeginArcDrag: Bool {
        guard store.document.activeCategory == .line,
              store.document.lineVariant == .arc,
              commandSession.isActive else { return false }
        return commandSession.controlPoints.count >= 2
    }

    private func beginArcDragIfNeeded(at point: CGPoint) -> Bool {
        guard canBeginArcDrag,
              let center = commandSession.controlPoints.first,
              commandSession.controlPoints.count >= 2 else { return false }
        let start = commandSession.controlPoints[1]
        let end = ShapeGeometry.projectArcEndpoint(center: center, start: start, point: point)
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        let initialSweep = atan2(sin(endAngle - startAngle), cos(endAngle - startAngle))

        if commandSession.controlPoints.count == 2 {
            commandSession.addPoint(end)
        } else {
            commandSession.movePoint(at: 2, to: end)
        }
        commandSession.setArcSweep(initialSweep)

        isArcDragActive = true
        arcDragPreviousAngle = endAngle
        arcDragAccumulatedSweep = initialSweep
        dragDrawStart = nil
        dragDrawEnd = nil
        isDragDrawing = false
        return true
    }

    private func updateArcDragIfNeeded(to point: CGPoint) -> Bool {
        guard isArcDragActive,
              store.document.activeCategory == .line,
              store.document.lineVariant == .arc,
              let center = commandSession.controlPoints.first,
              commandSession.controlPoints.count >= 2 else { return false }
        let start = commandSession.controlPoints[1]
        let end = ShapeGeometry.projectArcEndpoint(center: center, start: start, point: point)
        let endAngle = atan2(end.y - center.y, end.x - center.x)

        if let previous = arcDragPreviousAngle {
            let rawStep = endAngle - previous
            let step = atan2(sin(rawStep), cos(rawStep))
            arcDragAccumulatedSweep += step
        } else {
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            arcDragAccumulatedSweep = atan2(sin(endAngle - startAngle), cos(endAngle - startAngle))
        }
        arcDragPreviousAngle = endAngle

        if commandSession.controlPoints.count == 2 {
            commandSession.addPoint(end)
        } else {
            commandSession.movePoint(at: 2, to: end)
        }
        commandSession.setArcSweep(arcDragAccumulatedSweep)
        return true
    }

    private func endArcDragIfNeeded(at point: CGPoint) -> Bool {
        guard isArcDragActive else { return false }
        _ = updateArcDragIfNeeded(to: point)
        let shouldCommit = commandSession.canFinish
        resetArcDragState()
        if shouldCommit {
            commitCommandShape(restart: true)
        } else {
            startDrawingSessionIfNeeded()
        }
        return true
    }

    private func resetArcDragState() {
        isArcDragActive = false
        arcDragPreviousAngle = nil
        arcDragAccumulatedSweep = 0
    }

    private func loadProjectIfNeeded() {
        guard store.fileURL == nil, !didStartLoad else { return }
        didStartLoad = true
        Task { await loadProject() }
    }

    private func loadProject() async {
        isLoadingProject = true
        defer { isLoadingProject = false }
        if let projectURL {
            do {
                let snapshot = try await PersistenceWorker.shared.readSnapshot(from: projectURL)
                store.applyLoadedSnapshot(snapshot, from: projectURL)
                syncDisplayName(for: projectURL)
                lastSavedSnapshot = snapshot
                applyInitialViewportLayoutIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else if let library = projectLibrary {
            do {
                let record = try await library.createProject(name: store.fileName)
                let snapshot = try await PersistenceWorker.shared.readSnapshot(from: record.fileURL)
                store.applyLoadedSnapshot(snapshot, from: record.fileURL)
                store.fileName = record.name
                store.needsInitialViewportLayout = true
                lastSavedSnapshot = snapshot
                applyInitialViewportLayoutIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func syncDisplayName(for fileURL: URL) {
        guard let library = projectLibrary,
              let record = library.projects.first(where: {
                  $0.fileURL.standardizedFileURL.path == fileURL.standardizedFileURL.path
              }) else { return }
        store.fileName = record.name
    }

    /// Visible drawing area in canvas UIView coordinates. The GeometryReader is already the
    /// region below the toolbar; if the UIView expands under that chrome via
    /// `ignoresSafeArea()`, the extra height sits above (and below) that region.
    private var visibleRectInCanvasSpace: CGRect {
        let geo = canvasSize
        guard geo.width > 0, geo.height > 0 else { return .zero }
        let viewSize = canvasViewSize
        guard viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(origin: .zero, size: geo)
        }
        let extraHeight = max(0, viewSize.height - geo.height)
        let extraWidth = max(0, viewSize.width - geo.width)
        let top = max(0, extraHeight - canvasSafeAreaInsets.bottom)
        let leading = max(0, extraWidth - canvasSafeAreaInsets.right)
        return CGRect(x: leading, y: top, width: geo.width, height: geo.height)
    }

    private func updateCanvasLayoutMetrics(size: CGSize, insets: UIEdgeInsets) {
        let sizeChanged = abs(size.width - canvasViewSize.width) > 0.5
            || abs(size.height - canvasViewSize.height) > 0.5
        let insetsChanged = abs(insets.top - canvasSafeAreaInsets.top) > 0.5
            || abs(insets.bottom - canvasSafeAreaInsets.bottom) > 0.5
            || abs(insets.left - canvasSafeAreaInsets.left) > 0.5
            || abs(insets.right - canvasSafeAreaInsets.right) > 0.5
        guard sizeChanged || insetsChanged else { return }
        canvasViewSize = size
        canvasSafeAreaInsets = insets
        applyInitialViewportLayoutIfNeeded()
    }

    private func applyInitialViewportLayoutIfNeeded() {
        let visibleRect = visibleRectInCanvasSpace
        guard store.needsInitialViewportLayout, visibleRect.width > 0, visibleRect.height > 0 else { return }
        guard canvasViewSize.width > 0 else { return }
        let contentPoints = store.document.visibleStrokes().flatMap { ShapeGeometry.renderPoints(for: $0) }
        if contentPoints.isEmpty {
            store.document.viewport.frameCanvasInDrawableArea(
                canvasSize: store.document.settings.canvasSize,
                visibleRect: visibleRect
            )
        } else {
            store.document.viewport.fitToPoints(contentPoints, in: visibleRect.size)
            store.document.viewport.clampToCanvasSize(
                in: visibleRect.size,
                canvasSize: store.document.settings.canvasSize
            )
        }
        store.needsInitialViewportLayout = false
        designCanvasHandle.refreshViewport()
    }

    private func recenterAnimated() {
        let visibleRect = visibleRectInCanvasSpace
        guard visibleRect.width > 0, visibleRect.height > 0 else { return }

        var target = store.document.viewport
        target.frameCanvasInDrawableArea(
            canvasSize: store.document.settings.canvasSize,
            visibleRect: visibleRect
        )
        designCanvasHandle.animateViewport(to: target)
    }

    private func handleBack() {
        Task { @MainActor in
            await flushAutoSave()
            if store.hasUnsavedChanges {
                showUnsavedAlert = true
            } else {
                dismiss()
            }
        }
    }

    private func flushAutoSave() async {
        store.cancelAutoSave()
        await persistDocument(refreshThumbnail: true)
    }

    private func flushAutoSaveInBackground() {
        Task { @MainActor in
            let taskID = UIApplication.shared.beginBackgroundTask(withName: "vectr.autosave") {}
            defer {
                if taskID != .invalid {
                    UIApplication.shared.endBackgroundTask(taskID)
                }
            }
            await flushAutoSave()
        }
    }

    private func saveDocumentNow() {
        store.cancelAutoSave()
        Task { await persistDocument(refreshThumbnail: true) }
    }

    private func presentShare(url: URL, image: UIImage? = nil) async {
        if let image {
            shareItems = [JPEGShareItem(image: image, fileURL: url)]
        } else {
            shareItems = [url]
        }
        // Reset first so a second export can present again. Delay past any
        // just-dismissed format sheet so UIActivityViewController can present.
        showShareSheet = false
        try? await Task.sleep(for: .milliseconds(200))
        showShareSheet = true
    }

    private func presentDesignShare() {
        Task { await exportDesignShare() }
    }

    private func exportDesignShare() async {
        isExporting = true
        defer { isExporting = false }
        let snapshot = store.document.makeSnapshot()
        do {
            if exportFormat == .jpeg {
                let prepared = try await PersistenceWorker.shared.prepareJPEGForSharing(
                    snapshot: snapshot,
                    named: store.fileName,
                    quality: exportQuality
                )
                await presentShare(url: prepared.fileURL, image: UIImage(data: prepared.jpegData))
            } else {
                let tempURL = try await PersistenceWorker.shared.temporaryExportURL(
                    snapshot: snapshot,
                    name: store.fileName,
                    format: exportFormat,
                    quality: exportQuality
                )
                await presentShare(url: tempURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardChangesAndDismiss() {
        pendingDismiss = false
        pendingThumbnailRefresh = false
        store.cancelAutoSave()
        persistTask?.cancel()
        persistTask = nil
        if let lastSavedSnapshot {
            store.document = VectrDocument(snapshot: lastSavedSnapshot)
            store.hasUnsavedChanges = false
            store.contentRevision += 1
            store.needsInitialViewportLayout = false
        } else if let url = store.fileURL {
            do {
                try store.load(from: url)
                syncDisplayName(for: url)
                lastSavedSnapshot = store.document.makeSnapshot()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        dismiss()
    }

    private func updateChromeInsets() {
        let panelWidth: CGFloat
        switch store.document.activeCategory {
        case .fillet, .addAnchor, .pattern, .copy:
            panelWidth = 188
        default:
            panelWidth = 0
        }
        chromeInsets = ViewportTransform.ChromeInsets(
            left: panelWidth + 16,
            right: 156,
            top: 56,
            bottom: 20
        )
    }

    private func handleToolSelected(_ category: ToolCategory?) {
        let category = category ?? .move
        showCommandPanel = category.isDrawingTool
        if category != .copy {
            showLayersPanel = false
        }
        if category != .type {
            endTextEditingIfNeeded()
        }
        if category != .pattern {
            patternPreviewStrokes = []
        }
        settlePendingTrim()
        switch category {
        case .type:
            commandSession.cancel()
            store.document.selectedStrokeID = nil
            statusMessage = "Tap to place or edit text; drag to move, corners to scale"
        case .delete:
            if store.document.hasCanvasSelection {
                store.document.deleteSelectedElements()
                store.markDirty()
            } else {
                statusMessage = "Select a shape or text to delete"
            }
            commandSession.cancel()
        case .trim:
            commandSession.cancel()
            store.document.clearToolSelections()
            if store.document.selectedStrokeID == nil {
                statusMessage = "Tap a shape to select it, then tap the line to trim away"
            } else {
                statusMessage = "Tap the line segment to trim away"
            }
        case .fillet:
            commandSession.cancel()
            store.document.clearToolSelections()
            if store.document.selectedStrokeID == nil {
                statusMessage = "Select a shape, then choose corners to fillet"
            } else {
                statusMessage = "Tap a corner to select it; double-tap to multi-select; drag to set radius"
            }
        case .addAnchor:
            commandSession.cancel()
            store.document.clearToolSelections()
            if store.document.selectedStrokeID == nil {
                statusMessage = "Select a shape or line, then tap an edge or enter total anchor count"
            } else {
                statusMessage = "Tap an edge to add an anchor, or enter total anchor count"
            }
        case .pattern:
            commandSession.cancel()
            store.document.clearToolSelections()
            patternPreviewStrokes = []
            if let id = store.document.selectedStrokeID,
               let stroke = store.document.stroke(with: id) {
                patternSettings = PatternSettings.defaults(for: stroke)
                updatePatternPreview()
                statusMessage = "Adjust pattern settings, then tap Apply"
            } else {
                statusMessage = "Select a shape, then choose grid, linear, radial, or spiral"
            }
        case .copy:
            commandSession.cancel()
            store.document.clearToolSelections()
            if store.document.selectionIsEmpty,
               let lastID = store.document.lastSelectedStrokeID,
               store.document.stroke(with: lastID)?.layerID == store.document.activeLayerID {
                store.document.selectStrokeConsideringGroups(lastID)
            } else {
                store.document.expandSelectionToGroupsIfNeeded()
            }
            if store.document.selectionIsEmpty {
                statusMessage = "Tap a shape to copy, then switch layers and Paste"
            } else {
                statusMessage = "Copy the selection, then switch layers and Paste"
            }
        case .curve:
            commandSession.cancel()
            store.document.selectedStrokeID = nil
            statusMessage = "Draw lines with Apple Pencil; double-tap to finish the curve"
        case .dimensions:
            commandSession.cancel()
            store.document.revealDimensionsForCurrentSelection()
            if let strokeID = store.document.selectedStrokeID,
               let stroke = store.document.stroke(with: strokeID),
               !ShapeGeometry.showsDimensionsAutomatically(stroke),
               !store.document.hasRevealedDimensions(for: strokeID) {
                statusMessage = "Tap an edge to show its dimension"
            } else if store.document.selectedStrokeID == nil, store.document.selectedTextID == nil {
                statusMessage = "Tap a shape or edge to show dimensions"
            }
        case .move, .scale:
            commandSession.cancel()
            if category == .move {
                store.document.clearToolSelections()
                // Restore the last stroke selection so its edit handles reappear
                // when returning to the move tool from another tool. Expand to
                // the parent group when that stroke is a group member.
                if store.document.selectionIsEmpty,
                   !store.document.isReferenceImageSelected,
                   let lastID = store.document.lastSelectedStrokeID,
                   store.document.stroke(with: lastID)?.layerID == store.document.activeLayerID {
                    store.document.selectStrokeConsideringGroups(lastID)
                } else {
                    store.document.expandSelectionToGroupsIfNeeded()
                }
                if store.document.usesGroupTransform {
                    statusMessage = "Drag to move the group; tap to add or remove"
                } else if store.document.selectedTextID != nil {
                    statusMessage = "Drag to move the text"
                } else if store.document.isReferenceImageSelected {
                    statusMessage = "Drag to move the image; corners to scale"
                } else if store.document.selectedStrokeID == nil {
                    statusMessage = "Tap a shape to select; drag empty space to marquee-select"
                } else {
                    statusMessage = "Drag anchors or curve handles to edit; drag empty space to marquee-select"
                }
            }
        default:
            startDrawingSessionIfNeeded()
        }
        updateChromeInsets()
    }

    private func startDrawingSessionIfNeeded(anchor: CGPoint? = nil) {
        guard let category = store.document.activeCategory, category.isDrawingTool else {
            commandSession.cancel()
            resetArcDragState()
            updateChromeInsets()
            return
        }
        resetArcDragState()
        store.document.selectedStrokeID = nil
        commandSession.start(
            category: category,
            lineVariant: store.document.lineVariant,
            circleVariant: store.document.circleVariant,
            rectangleVariant: store.document.rectangleVariant
        )
        if let anchor {
            commandSession.addPoint(anchor)
        }
        if category == .line, store.document.lineVariant == .arc, commandSession.controlPoints.count < 2 {
            statusMessage = "Drag from the center to the start, then drag to set the sweep"
        }
        updateChromeInsets()
    }

    private var lineConnectTolerance: CGFloat {
        // Only weld chained segments that actually share a point. Half a grid
        // cell was treating a nearby line as the same vertex and inserting a
        // diagonal connector.
        coincidentAnchorTolerance(viewport: store.document.viewport, grid: store.document.grid)
    }

    private func commitLineSegment(start: CGPoint, end: CGPoint) {
        store.document.commitLineSegment(
            start: start,
            end: end,
            layerID: store.document.activeLayerID,
            strokeWidth: store.document.strokeWidth,
            strokeColor: store.document.strokeColor,
            connectTolerance: lineConnectTolerance
        )
        store.markDirty()
    }

    private func handleCommandPointSubmitted() {
        if commandSession.isRefiningAttachedStroke {
            if syncAttachedStrokeFromSession(recordUndo: false) {
                store.markDirty()
            }
            return
        }
        if commandSession.canFinish, shouldAutoCommitAfterPoint {
            commitCommandShape(restart: true)
        }
    }

    private func beginTextEditing(_ id: UUID) {
        store.document.selectedTextID = id
        withAnimation(.easeOut(duration: 0.15)) {
            editingTextID = id
        }
    }

    private func endTextEditingIfNeeded() {
        guard let id = editingTextID else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            editingTextID = nil
        }
        if let element = store.document.textElement(with: id),
           element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.document.removeTextElement(id: id)
            store.markDirty()
        }
    }

    /// Closed-arc fallback may only drop the implied closing chord (last→first).
    /// Opening at start→mid or mid→end would reorder the three anchors and flip
    /// the arc to the other side of its chord.
    private func closingEdgeFallbackAllowed(_ stroke: VectorStroke, edgeIndex: Int) -> Bool {
        if stroke.shapeType == .arc {
            return stroke.isClosed && edgeIndex == max(stroke.points.count - 1, 0)
        }
        return true
    }

    /// A trim tap that has been previewed but not yet cut.
    private struct PendingTrim {
        var point: CGPoint
        var threshold: CGFloat
    }

    /// Flash the span in red, then cut. `removal` already told us the trim will land, so
    /// `trimAt` is re-run after the flash rather than being made asynchronous.
    private func flashTrimRemoval(
        _ removal: TrimEngine.RemovedSegmentGeometry,
        at documentPoint: CGPoint,
        threshold: CGFloat
    ) {
        trimPreviewStrokeWidth = removal.strokeWidth
        trimPreviewPoints = removal.points
        pendingTrim = PendingTrim(point: documentPoint, threshold: threshold)
        trimFlashTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            settlePendingTrim()
        }
    }

    /// Apply the cut the flash is previewing and take the highlight down. The flash is
    /// cosmetic, so anything that interrupts it — another trim tap, leaving the tool —
    /// still commits the tap the user already made.
    private func settlePendingTrim() {
        trimFlashTask?.cancel()
        trimFlashTask = nil
        trimPreviewPoints = []
        guard let pending = pendingTrim else { return }
        pendingTrim = nil
        store.document.trimAt(pending.point, threshold: pending.threshold)
        store.markDirty()
    }

    /// Tap on empty grid / outside every shape. Used to leave the current tool.
    private func isEmptyCanvasTap(at documentPoint: CGPoint, viewThreshold: CGFloat = 16) -> Bool {
        let threshold = store.document.viewport.viewToDocument(distance: viewThreshold)
        if store.document.isHitOnInactiveLayer(near: documentPoint, threshold: threshold) {
            return false
        }
        if store.document.elementHit(near: documentPoint, threshold: threshold) != .none {
            return false
        }
        return store.document.group(at: documentPoint) == nil
    }

    /// Leave the current tool, hide its panel/handles, and fall back to idle Move.
    private func handleDesignUndo() {
        if curveDraft.canUndo {
            curveDraft.performUndo()
            return
        }
        curveDraft.discardRedo()
        store.document.undo()
        store.markDirty()
    }

    private func handleDesignRedo() {
        if curveDraft.canRedo {
            curveDraft.performRedo()
            return
        }
        store.document.redo()
        store.markDirty()
    }

    private func dismissActiveTool() {
        endTextEditingIfNeeded()
        commandSession.cancel()
        resetArcDragState()
        patternPreviewStrokes = []
        settlePendingTrim()
        showCommandPanel = false
        store.document.clearToolSelections()
        store.document.clearElementSelection()
        store.document.clearActiveTool()
        updateChromeInsets()
    }

    private func handleCanvasTap(_ documentPoint: CGPoint) {
        showCommandPanel = false
        // Keep layers open for copy/paste so the destination layer can be chosen
        // without reopening the panel after tapping a shape.
        if store.document.activeCategory != .copy {
            showLayersPanel = false
        }
        switch store.document.activeCategory {
        case .move, nil:
            activateMoveIfHit(at: documentPoint)
        case .curve:
            dismissActiveTool()
        case .type:
            endTextEditingIfNeeded()
            if store.document.isHitOnInactiveLayer(near: documentPoint, threshold: 0) {
                return
            }
            // With a text already selected, tap-away leaves Type. With nothing
            // selected, an empty tap is how a new text is placed.
            if store.document.selectedTextID != nil, isEmptyCanvasTap(at: documentPoint) {
                dismissActiveTool()
                return
            }
            if let hit = store.document.selectTextElement(at: documentPoint) {
                beginTextEditing(hit.id)
            } else {
                let element = store.document.makeTextElement(at: documentPoint)
                store.document.addTextElement(element)
                beginTextEditing(element.id)
                store.markDirty()
            }
        case .line, .circle, .rectangle:
            if isEmptyCanvasTap(at: documentPoint) {
                dismissActiveTool()
                return
            }
            activateMoveIfHit(at: documentPoint)
        case .trim:
            // Commit any still-flashing cut first, so a fast second tap is measured
            // against the geometry it will actually act on.
            settlePendingTrim()
            if isEmptyCanvasTap(at: documentPoint) {
                dismissActiveTool()
                return
            }
            let threshold = store.document.viewport.viewToDocument(distance: 16)
            if store.document.isHitOnInactiveLayer(near: documentPoint, threshold: threshold) {
                return
            }
            // Anchor-first: tapping a vertex deletes it. A corner drops its two edges and
            // opens the shape; a collinear point is removed without changing the geometry.
            if store.document.deleteStrokeAnchor(near: documentPoint, threshold: threshold) {
                store.markDirty()
            } else if let removal = store.document.trimRemovalPreview(
                at: documentPoint,
                threshold: threshold
            ) {
                flashTrimRemoval(removal, at: documentPoint, threshold: threshold)
            } else if let stroke = store.document.selectedStrokeID.flatMap({ store.document.stroke(with: $0) }) {
                // Non-CAD shapes previously trimmed via edge/vertex handles. Keep that
                // behavior by tapping the geometry itself (no overlay handles).
                let usesCADTrim = stroke.shapeType == .circle
                    || stroke.shapeType == .ellipse
                    || (stroke.shapeType == .arc && !stroke.isClosed)
                if !usesCADTrim,
                   let edgeIndex = StrokeEditor.nearestEdgeIndex(
                       in: stroke,
                       point: documentPoint,
                       threshold: threshold
                   ),
                   closingEdgeFallbackAllowed(stroke, edgeIndex: edgeIndex) {
                    store.document.deleteStrokeEdge(at: edgeIndex)
                    store.markDirty()
                } else {
                    statusMessage = "Tap the line segment to trim away"
                }
            } else {
                _ = store.document.selectStroke(near: documentPoint, threshold: threshold)
            }
        case .addAnchor:
            if isEmptyCanvasTap(at: documentPoint, viewThreshold: 28) {
                dismissActiveTool()
                return
            }
            let threshold = store.document.viewport.viewToDocument(distance: 28)
            if store.document.isHitOnInactiveLayer(near: documentPoint, threshold: threshold) {
                return
            }
            if let stroke = store.document.selectedStrokeID.flatMap({ store.document.stroke(with: $0) }) {
                if AnchorPointEngine.canEditAnchors(on: stroke) {
                    let snapped = snapDrawingInput(documentPoint)
                    if store.document.insertAnchor(at: snapped, threshold: threshold) {
                        store.markDirty()
                    } else {
                        statusMessage = "Tap closer to an edge between anchors"
                    }
                } else {
                    statusMessage = "Selected shape cannot receive anchors"
                }
            } else {
                _ = store.document.selectStroke(near: documentPoint, threshold: threshold)
            }
        case .pattern:
            if isEmptyCanvasTap(at: documentPoint) {
                dismissActiveTool()
                return
            }
            let threshold = store.document.viewport.viewToDocument(distance: 16)
            store.document.selectElement(near: documentPoint, threshold: threshold)
            if let id = store.document.selectedStrokeID,
               let stroke = store.document.stroke(with: id) {
                patternSettings = PatternSettings.defaults(for: stroke)
            } else {
                patternPreviewStrokes = []
            }
            updatePatternPreview()
        case .dimensions:
            let threshold = store.document.viewport.viewToDocument(distance: 16)
            switch store.document.handleDimensionTap(at: documentPoint, threshold: threshold) {
            case .selectedComplex:
                statusMessage = "Tap an edge to show its dimension"
            case .revealedEdge, .hiddenEdge, .autoRevealed, .dismissed, .ignored:
                break
            }
        case .copy:
            if isEmptyCanvasTap(at: documentPoint) {
                dismissActiveTool()
                return
            }
            let threshold = store.document.viewport.viewToDocument(distance: 16)
            let hit = store.document.selectElement(near: documentPoint, threshold: threshold)
            if hit != .none {
                let count = store.document.copySelectedElementsToClipboard()
                if count > 0 {
                    let noun = count == 1 ? "item" : "items"
                    statusMessage = "Copied \(count) \(noun). Switch layers, then Paste"
                }
            }
        case .delete:
            if isEmptyCanvasTap(at: documentPoint, viewThreshold: 24) {
                dismissActiveTool()
                return
            }
            if store.document.isHitOnInactiveLayer(near: documentPoint, threshold: store.document.viewport.viewToDocument(distance: 24)) {
                return
            }
            if let text = store.document.textElement(at: documentPoint) {
                store.document.removeTextElement(id: text.id)
                store.markDirty()
                return
            }
            let threshold = store.document.viewport.viewToDocument(distance: 24)
            // 1. Arc-on-edge knife: tapping inside the piece an arc slices off removes
            //    that piece. Attempted before the outline delete because the region being
            //    removed is bounded by the arc, so the tap is inherently near the arc line
            //    (which would otherwise be deleted as a whole shape).
            if store.document.sliceArcCut(at: documentPoint) {
                store.markDirty()
                return
            }
            // 2. Interior fill tap over an overlap: punch a hole (base MINUS target).
            //    Attempted before the outline delete so a thin cutter still cuts:
            //    tapping inside a narrow shape lands within the outline threshold of
            //    its own edges, which would otherwise be misread as an edge tap and
            //    delete the whole cutter. `punchOverlapHole` only fires when the tap is
            //    inside a top shape that overlaps a shape beneath, so true edge taps on
            //    standalone shapes still fall through to the outline delete below.
            if store.document.punchOverlapHole(at: documentPoint) {
                store.markDirty()
                return
            }
            // 3. Edge/line tap: tapping on or near an outline deletes that shape entirely.
            //    If the tap is *inside* a different filled shape, that shape is what was
            //    targeted — typically a small cutter sitting on a larger outline, where
            //    the base edge is closer than the cutter's own outline. Deleting the
            //    underlying outline would swallow the large shape. Fall through so the
            //    fill-delete below removes the shape under the finger instead.
            if let outline = store.document.strokeOutlineHit(near: documentPoint, threshold: threshold) {
                let fillUnderTap = store.document.strokeFillHit(at: documentPoint)
                if fillUnderTap == nil || fillUnderTap?.id == outline.id {
                    store.document.removeStroke(id: outline.id)
                    store.markDirty()
                    return
                }
            }
            // 4. Interior fill tap with nothing beneath: delete the filled shape.
            if let fill = store.document.strokeFillHit(at: documentPoint) {
                store.document.removeStroke(id: fill.id)
                store.markDirty()
                return
            }
            // 5. Imported raster behind the vectors.
            if let image = store.document.referenceImageHit(at: documentPoint) {
                store.document.removeReferenceImage(id: image.id)
                store.markDirty()
                return
            }
            // 6. Fall back to the current selection.
            if store.document.hasCanvasSelection {
                store.document.deleteSelectedElements()
                store.markDirty()
            }
        default:
            if isEmptyCanvasTap(at: documentPoint) {
                dismissActiveTool()
                return
            }
            let threshold = store.document.viewport.viewToDocument(distance: 16)
            store.document.selectElement(near: documentPoint, threshold: threshold)
        }
    }

    /// Idle canvas tap: if the tap hits a shape, line, or text, switch to the
    /// move/select/edit tool and select that element.
    private func activateMoveIfHit(at documentPoint: CGPoint) {
        let threshold = store.document.viewport.viewToDocument(distance: 16)
        let hit = store.document.elementHit(near: documentPoint, threshold: threshold)
        let groupHit = hit == .none ? store.document.group(at: documentPoint) : nil
        guard hit != .none || groupHit != nil else { return }

        switch hit {
        case .stroke(let id):
            store.document.selectStrokeConsideringGroups(id)
        case .text(let id):
            store.document.selectTextConsideringGroups(id)
        case .referenceImage(let id):
            store.document.selectReferenceImage(id: id)
        case .none:
            if let groupHit {
                store.document.selectGroup(groupHit)
            }
        }

        store.document.engageMoveTool()
        handleToolSelected(.move)
    }

    private func commitDragDraw(start: CGPoint, end: CGPoint) {
        // The start was already resolved during the gesture. Re-running object snap
        // can pull it onto a nearby corner and turn a straight preview into a diagonal.
        let snappedStart = start
        // Re-snap the end with the start as the axis reference so a live lock
        // is preserved on release; without it the free end can be grid-snapped off-axis.
        let snappedEnd = snapDrawingInput(end, referenceStart: snappedStart)
        guard hypot(snappedEnd.x - snappedStart.x, snappedEnd.y - snappedStart.y) > 0.001 else {
            startDrawingSessionIfNeeded()
            return
        }

        let controlPoints = dragControlPoints(start: snappedStart, end: snappedEnd)
        guard !controlPoints.isEmpty else {
            startDrawingSessionIfNeeded()
            return
        }

        guard let category = store.document.activeCategory else {
            startDrawingSessionIfNeeded()
            return
        }

        commandSession.start(
            category: category,
            lineVariant: store.document.lineVariant,
            circleVariant: store.document.circleVariant,
            rectangleVariant: store.document.rectangleVariant
        )
        for point in controlPoints {
            commandSession.addPoint(point)
        }

        if category == .line, store.document.lineVariant == .arc, !commandSession.canFinish {
            statusMessage = "Drag to set the sweep"
            return
        }

        guard commandSession.canFinish else {
            startDrawingSessionIfNeeded()
            return
        }

        // Use the same commit pathway as typed point-by-point entry.
        commitCommandShape(restart: false)

        if store.document.isDrawingToolActive {
            startDrawingSessionIfNeeded()
        } else {
            commandSession.cancel()
        }
    }

    private func commitCurve(anchors rawAnchors: [CGPoint]) {
        guard rawAnchors.count >= 2 else { return }

        // Recognize a closed shape: if the curve loops back near its start, drop the
        // duplicate end anchor and mark it closed so it can be filled/treated as a region.
        var anchors = rawAnchors
        var isClosed = false
        let tolerance = store.document.grid.spacing * 0.5
        if anchors.count >= 3,
           let first = anchors.first,
           let last = anchors.last,
           hypot(first.x - last.x, first.y - last.y) <= tolerance {
            anchors.removeLast()
            isClosed = true
        }

        guard anchors.count >= (isClosed ? 3 : 2) else { return }

        let stroke = VectorStroke(
            layerID: store.document.activeLayerID,
            points: anchors,
            strokeWidth: store.document.strokeWidth,
            strokeColor: store.document.strokeColor,
            isClosed: isClosed,
            shapeType: .curve,
            curveHandles: ShapeGeometry.defaultCurveHandles(anchors: anchors, closed: isClosed)
        )
        store.document.addStroke(stroke)
        // Select the new curve so its anchor + tangent handles are immediately editable.
        store.document.selectedStrokeID = stroke.id
        store.markDirty()
    }

    private func dragControlPoints(start: CGPoint, end: CGPoint) -> [CGPoint] {
        switch store.document.activeCategory {
        case .line:
            return [start, end]
        case .circle:
            switch store.document.circleVariant {
            case .center:
                return [start, end]
            case .edge:
                return [start, end]
            case .ellipse:
                let rx = max(0.001, abs(end.x - start.x))
                let ry = max(0.001, abs(end.y - start.y))
                return [
                    start,
                    CGPoint(x: start.x + rx, y: start.y),
                    CGPoint(x: start.x, y: start.y + ry)
                ]
            }
        case .rectangle:
            switch store.document.rectangleVariant {
            case .center:
                let halfW = max(0.001, abs(end.x - start.x))
                let halfH = max(0.001, abs(end.y - start.y))
                return [
                    start,
                    CGPoint(x: start.x + halfW, y: start.y),
                    CGPoint(x: start.x, y: start.y + halfH)
                ]
            case .edge:
                return [start, end]
            }
        default:
            return []
        }
    }

    private func handleFileNameChanged() {
        store.markDirty()
        guard let library = projectLibrary else { return }
        do {
            if let url = store.fileURL {
                let renamedURL = try library.renameProject(fileURL: url, name: store.fileName)
                store.fileURL = renamedURL
                syncDisplayName(for: renamedURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitCommandShape(restart: Bool = false) {
        if commandSession.isRefiningAttachedStroke {
            if syncAttachedStrokeFromSession(recordUndo: false) {
                store.markDirty()
            }
            if restart, store.document.isDrawingToolActive {
                startDrawingSessionIfNeeded()
            } else {
                commandSession.finish()
                updateChromeInsets()
            }
            return
        }

        if store.document.activeCategory == .line,
           store.document.lineVariant == .line,
           commandSession.controlPoints.count >= 2 {
            let start = commandSession.controlPoints[commandSession.controlPoints.count - 2]
            let end = commandSession.controlPoints.last!
            commitLineSegment(start: start, end: end)
            if restart {
                commandSession.restartLineChain(anchor: end)
            } else {
                commandSession.finish()
            }
            store.markDirty()

            if !restart {
                updateChromeInsets()
            }
            return
        }

        guard let stroke = commandSession.buildStroke(
            layerID: store.document.activeLayerID,
            strokeWidth: store.document.strokeWidth,
            strokeColor: store.document.strokeColor,
            cornerRadius: store.document.settings.defaultCornerRadius
        ) else { return }

        store.document.addStroke(stroke)
        commandSession.finish()
        store.markDirty()

        if restart, store.document.isDrawingToolActive {
            startDrawingSessionIfNeeded()
        } else {
            store.document.selectedStrokeID = stroke.id
            updateChromeInsets()
        }
    }

    @discardableResult
    private func syncAttachedStrokeFromSession(recordUndo: Bool) -> Bool {
        guard let attachedID = commandSession.attachedStrokeID,
              let existing = store.document.stroke(with: attachedID),
              let rebuilt = commandSession.buildStroke(
                layerID: existing.layerID,
                strokeWidth: existing.strokeWidth,
                strokeColor: existing.strokeColor,
                cornerRadius: existing.cornerRadius
              ) else { return false }

        var updated = rebuilt
        updated.id = existing.id
        updated.layerID = existing.layerID
        updated.isConstruction = existing.isConstruction
        updated.cornerRadiiByIndex = existing.cornerRadiiByIndex
        updated.cutoutPoints = existing.cutoutPoints
        if existing.isConstruction {
            updated.shapeType = .construction
        }

        store.document.updateStroke(updated, recordUndo: recordUndo)
        store.document.selectedStrokeID = updated.id
        return true
    }

    private func updatePatternPreview() {
        guard store.document.activeCategory == .pattern,
              let strokeID = store.document.selectedStrokeID,
              let stroke = store.document.stroke(with: strokeID) else {
            patternPreviewStrokes = []
            return
        }
        patternPreviewStrokes = PatternEngine.generatedCopies(from: stroke, settings: patternSettings)
    }

    private func performUndo() {
        store.document.undo()
        store.markDirty()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let content = try ImportRouter.loadContent(
                    from: url,
                    layerID: store.document.activeLayerID
                )
                let count = try store.document.importContent(content, offset: importPlacementOffset)
                store.markDirty()
                if count > 0 {
                    let noun = count == 1 ? "item" : "items"
                    statusMessage = "Imported \(count) \(noun)"
                } else {
                    statusMessage = "Imported image — drag to move, corners to scale"
                    if store.document.isReferenceImageSelected {
                        store.document.engageMoveTool()
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Places imported artwork at the visible canvas center so it is on-screen.
    private var importPlacementOffset: CGPoint {
        let rect = visibleRectInCanvasSpace
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return store.document.viewport.viewToDocument(CGPoint(x: rect.midX, y: rect.midY))
    }

    private func snapshotFromStore() -> DocumentSnapshot {
        store.document.makeSnapshot()
    }

    private func persistDocument(refreshThumbnail: Bool) async {
        if let persistTask {
            await persistTask.value
        }
        if store.hasUnsavedChanges {
            let task = Task { await performPersist(refreshThumbnail: refreshThumbnail) }
            persistTask = task
            await task.value
            persistTask = nil
        } else if refreshThumbnail {
            await refreshGalleryThumbnailIfNeeded()
        }
    }

    private func performPersist(refreshThumbnail: Bool) async {
        guard store.hasUnsavedChanges else { return }
        do {
            if store.fileURL == nil, let library = projectLibrary {
                let record = try await library.createProject(name: store.fileName)
                store.fileURL = record.fileURL
                store.fileName = record.name
            }
            if let url = store.fileURL, let library = projectLibrary {
                let renamedURL = try library.renameProject(fileURL: url, name: store.fileName)
                store.fileURL = renamedURL
                syncDisplayName(for: renamedURL)
            }
            guard let url = store.fileURL else { return }
            let snapshot = store.document.makeSnapshot()
            let revision = store.contentRevision
            let name = store.fileName
            let thumbnailURL = projectLibrary?.projects.first(where: {
                $0.fileURL.standardizedFileURL.path == url.standardizedFileURL.path
            })?.thumbnailURL
            let thumbnailExists = thumbnailURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let shouldWriteThumbnail = GalleryThumbnailPolicy.shouldWriteThumbnail(
                refreshRequested: refreshThumbnail,
                thumbnailExists: thumbnailExists
            )

            try await PersistenceWorker.shared.write(snapshot: snapshot, to: url)
            if shouldWriteThumbnail, let thumbnailURL {
                try await PersistenceWorker.shared.writeThumbnail(snapshot: snapshot, to: thumbnailURL)
            }
            lastSavedSnapshot = snapshot
            store.markSaved(forRevision: revision)
            projectLibrary?.updateMetadataAfterSave(fileURL: url, name: name, snapshot: snapshot)
            pendingThumbnailRefresh = thumbnailURL != nil && !shouldWriteThumbnail
            if pendingDismiss, !store.hasUnsavedChanges {
                pendingDismiss = false
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshGalleryThumbnailIfNeeded() async {
        guard pendingThumbnailRefresh else { return }
        guard let url = store.fileURL, let library = projectLibrary else { return }
        do {
            try await library.refreshThumbnail(snapshot: store.document.makeSnapshot(), fileURL: url)
            pendingThumbnailRefresh = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

extension UTType {
    nonisolated static var vectrDocument: UTType {
        UTType(exportedAs: "earthwrm.vectr.document", conformingTo: .json)
    }
}

#Preview {
    NavigationStack {
        EditorView()
    }
}
