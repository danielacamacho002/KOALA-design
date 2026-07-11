//
//  EditorView.swift
//  vectr
//

import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    var projectURL: URL?
    var projectLibrary: ProjectLibrary?

    @Environment(\.dismiss) private var dismiss
    @State private var store = DocumentStore()
    @State private var commandSession = ShapeCommandSession()
    @State private var showExportSheet = false
    @State private var showFileExporter = false
    @State private var exportFormat: ExportFormat = .vectr
    @State private var exportDocument: EditorExportDocument?
    @State private var errorMessage: String?
    @State private var canvasSize: CGSize = .zero
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
    @State private var printExportDocument: EditorExportDocument?
    @State private var lastSavedSnapshot: DocumentSnapshot?
    @State private var patternSettings = PatternSettings()
    @State private var patternPreviewStrokes: [VectorStroke] = []
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
                    onUndo: {
                        store.document.undo()
                        refreshCanvas()
                    },
                    onRedo: {
                        store.document.redo()
                        refreshCanvas()
                    },
                    onSave: { saveDocument() },
                    onSwitchToDesign: { switchToDesignMode() },
                    onExport: preparePrintExport,
                    onChanged: { refreshCanvas() },
                    onLayoutReady: { size in centerPrintLayoutWithoutRescaling(in: size) },
                    onFitToGrid: { size in fitPrintLayoutToGrid(in: size) }
                )
            } else {
                designEditorBody
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                document: store.document,
                fileName: $store.fileName,
                onFileNameChanged: handleFileNameChanged
            )
        }
        .sheet(isPresented: $showExportSheet) {
            ExportFormatSheet { format in
                exportFormat = format
                prepareExport()
            }
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: exportDocument,
            contentType: exportFormat.contentType,
            defaultFilename: store.fileName
        ) { _ in
            exportDocument = nil
        }
        .fileExporter(
            isPresented: Binding(
                get: { printExportDocument != nil },
                set: { if !$0 { printExportDocument = nil } }
            ),
            document: printExportDocument,
            contentType: .pdf,
            defaultFilename: "\(store.fileName)-tiled"
        ) { _ in
            printExportDocument = nil
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Save") {
                pendingDismiss = true
                saveDocument()
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
                    isCommandMode: commandSession.isActive,
                    activeCategory: store.document.activeCategory,
                    commandPreviewPoints: commandSession.previewPoints,
                    commandControlPoints: commandSession.displayControlPoints,
                    commandCanFinish: commandSession.canFinish,
                    commandRevision: commandSession.revision,
                    strokeCount: store.document.strokes.count,
                    geometryRevision: store.document.geometryRevision,
                    contentRevision: store.contentRevision,
                    visualGridSpacing: UnitConversion.visualGridSpacing(
                        sliderValue: store.document.settings.defaultGridSpacingInUnits,
                        unit: store.document.settings.units
                    ),
                    measurementUnit: store.document.settings.units,
                    isConstructionPreview: store.document.activeCategory == .line
                        && store.document.lineVariant == .constructionLine,
                    commandPreviewClosed: commandSession.canFinish
                        && (store.document.activeCategory == .rectangle
                            || store.document.activeCategory == .circle),
                    allowsDragDraw: allowsDragDraw,
                    lineVariant: store.document.lineVariant,
                    circleVariant: store.document.circleVariant,
                    rectangleVariant: store.document.rectangleVariant,
                    canvasBackgroundColor: Color(hex: canvasColorHex),
                    onCanvasTap: handleCanvasTap,
                    onStrokeSelected: { stroke in
                        store.document.selectedStrokeID = stroke?.id
                        store.markDirty()
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
                    onCurveCommitted: commitCurve
                )
                .ignoresSafeArea()

                if isDragDrawing, let start = dragDrawStart, let end = dragDrawEnd {
                    LiveDimensionOverlay(
                        document: store.document,
                        start: start,
                        end: end,
                        category: store.document.activeCategory,
                        circleVariant: store.document.circleVariant,
                        rectangleVariant: store.document.rectangleVariant
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
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
                    onEditText: { beginTextEditing($0) }
                )
                .ignoresSafeArea()
                .allowsHitTesting(canvasOverlayAcceptsHits)

                DimensionOverlayView(document: store.document) {
                    refreshCanvas()
                }
                .ignoresSafeArea()
            }
            .overlay(alignment: .topLeading) {
                if store.document.activeCategory == .fillet {
                    FilletRadiusPanelView(
                        document: store.document,
                        units: store.document.settings.units,
                        onApply: {
                            store.document.clearToolSelections()
                            refreshCanvas()
                        },
                        onCancel: {
                            store.document.clearToolSelections()
                            refreshCanvas()
                        }
                    )
                    .padding(.leading, 10)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if store.document.activeCategory == .move,
                          store.document.selectedStrokeID != nil || store.document.selectedTextID != nil {
                    MoveRotatePanelView(document: store.document) {
                        refreshCanvas()
                    }
                    .padding(.leading, 10)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if store.document.activeCategory == .addAnchor {
                    AddAnchorPanelView(
                        document: store.document,
                        onApply: { refreshCanvas() },
                        onStatus: { statusMessage = $0 }
                    )
                    .padding(.leading, 10)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if store.document.activeCategory == .pattern {
                    PatternPanelView(
                        document: store.document,
                        units: store.document.settings.units,
                        settings: $patternSettings,
                        onPreviewChange: updatePatternPreview,
                        onApply: {
                            patternPreviewStrokes = []
                            refreshCanvas()
                        },
                        onStatus: { statusMessage = $0 }
                    )
                    .padding(.leading, 10)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .overlay(alignment: .topLeading) {
                if let editingTextID {
                    TextToolPanelView(
                        document: store.document,
                        elementID: editingTextID,
                        onChanged: { refreshCanvas() },
                        onDone: { endTextEditingIfNeeded() }
                    )
                    .padding(.leading, 10)
                    .padding(.top, 8)
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
                            refreshCanvas()
                        },
                        onVariantChanged: { startDrawingSessionIfNeeded() }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .overlay(alignment: .bottomLeading) {
                ConstraintSettingsView(document: store.document)
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .topTrailing) {
                LayersPanelView(document: store.document, isExpanded: $showLayersPanel) {
                    refreshCanvas()
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
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                self.statusMessage = nil
                            }
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
                canUndo: store.document.canUndo,
                canRedo: store.document.canRedo,
                onBack: handleBack,
                onUndo: {
                    store.document.undo()
                    refreshCanvas()
                },
                onRedo: {
                    store.document.redo()
                    refreshCanvas()
                },
                onSettings: { showSettings = true },
                onShare: { showExportSheet = true },
                onSave: { saveDocument() },
                onToolSelected: handleToolSelected,
                onVariantSelected: {
                    showCommandPanel = true
                    startDrawingSessionIfNeeded()
                },
                onSwitchToPrintLayout: { switchToPrintLayoutMode() }
            )
        }
    }

    private func switchToPrintLayoutMode() {
        savedDesignViewport = store.document.viewport
        editorMode = .printLayout
        store.document.printSelectedStrokeID = nil
        store.document.printSelectedTextID = nil
        store.document.autoPositionDesignOnPrintGrid()
        store.document.refreshRegistrationMarkSuggestions()
        centerPrintLayoutWithoutRescaling(in: canvasSize)
        refreshCanvas()
    }

    private func switchToDesignMode() {
        editorMode = .design
        if let savedDesignViewport {
            store.document.viewport = savedDesignViewport
        }
        refreshCanvas()
    }

    private func fitPrintLayoutToGrid(in size: CGSize? = nil) {
        let layoutSize = size ?? canvasSize
        guard layoutSize.width > 0, layoutSize.height > 0 else { return }
        canvasSize = layoutSize
        let points = store.document.allPrintLayoutPoints()
        store.document.viewport.fitToPoints(
            points,
            in: layoutSize,
            chrome: ViewportTransform.ChromeInsets(left: 40, right: 40, top: 60, bottom: 40)
        )
        refreshCanvas()
    }

    private func centerPrintLayoutWithoutRescaling(in size: CGSize? = nil) {
        let layoutSize = size ?? canvasSize
        guard layoutSize.width > 0, layoutSize.height > 0 else { return }
        canvasSize = layoutSize

        let points = store.document.allPrintLayoutPoints()
        guard let bounds = boundingRect(for: points) else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let currentScale = store.document.viewport.scale
        let viewCenter = CGPoint(x: layoutSize.width / 2, y: layoutSize.height / 2)
        store.document.viewport.translation = CGPoint(
            x: viewCenter.x - center.x * currentScale,
            y: viewCenter.y - center.y * currentScale
        )
        refreshCanvas()
    }

    private func boundingRect(for points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    private func preparePrintExport(_ kind: PrintLayoutExportKind) {
        do {
            let tempURL: URL
            switch kind {
            case .tiledPDF:
                tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(store.fileName)-tiled.pdf")
                try TiledPDFExporter.write(document: store.document, to: tempURL)
            case .singlePDF:
                tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(store.fileName).pdf")
                try PDFExporter.write(document: store.document, to: tempURL)
            }
            printExportDocument = EditorExportDocument(fileURL: tempURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var drawingSnapEnabled: Bool {
        store.document.snapEnabled && store.document.grid.snapEnabled
    }

    private func snapDrawingInput(_ point: CGPoint) -> CGPoint {
        snapDrawingPoint(
            point,
            grid: store.document.grid,
            settings: store.document.settings,
            enabled: drawingSnapEnabled
        )
    }

    private func snapDrawingControlInput(_ raw: CGPoint, projected: CGPoint) -> CGPoint {
        snapDrawingControlPoint(
            raw: raw,
            projected: projected,
            grid: store.document.grid,
            settings: store.document.settings,
            enabled: drawingSnapEnabled
        )
    }

    private var canvasOverlayAcceptsHits: Bool {
        if commandSession.isActive { return false }
        switch store.document.activeCategory {
        case .move, .scale, .trim, .fillet:
            return true
        case .type:
            // With a text selected, the overlay handles move/scale/tap-to-edit;
            // with nothing selected, taps pass through so a new text can be placed.
            return store.document.selectedTextID != nil
        case .delete, .addAnchor, .pattern:
            // Let canvas taps pass through so delete/add-anchor/pattern can target the shape directly.
            return false
        default:
            if store.document.dimensionsVisible { return false }
            return store.document.selectedStrokeID != nil
        }
    }

    private var allowsDragDraw: Bool {
        switch store.document.activeCategory {
        case .curve:
            return true
        case .line:
            switch store.document.lineVariant {
            case .line, .constructionLine:
                return true
            case .arc:
                return canBeginArcDrag
            }
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
        refreshCanvas()
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
        refreshCanvas()
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
        guard store.fileURL == nil else { return }
        if let projectURL {
            do {
                try store.load(from: projectURL)
                syncDisplayName(for: projectURL)
                lastSavedSnapshot = snapshotFromStore()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else if let library = projectLibrary {
            do {
                let record = try library.createProject(name: store.fileName)
                try store.load(from: record.fileURL)
                store.fileName = record.name
                store.needsInitialViewportLayout = true
                lastSavedSnapshot = snapshotFromStore()
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

    private func applyInitialViewportLayoutIfNeeded() {
        guard store.needsInitialViewportLayout, canvasSize.width > 0, canvasSize.height > 0 else { return }
        let contentPoints = store.document.visibleStrokes().flatMap { ShapeGeometry.renderPoints(for: $0) }
        if contentPoints.isEmpty {
            store.document.viewport.resetToDefaultView(in: canvasSize)
        } else {
            store.document.viewport.fitToPoints(contentPoints, in: canvasSize)
            store.document.viewport.clampToCanvasExtent(
                in: canvasSize,
                canvasExtent: store.document.settings.canvasExtent
            )
        }
        store.needsInitialViewportLayout = false
        refreshCanvas()
    }

    private func recenterAnimated() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let start = store.document.viewport.translation
        let end = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        guard hypot(end.x - start.x, end.y - start.y) > 0.5 else { return }

        Task { @MainActor in
            let steps = 24
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let eased = easeInOut(t)
                store.document.viewport.translation = CGPoint(
                    x: start.x + (end.x - start.x) * eased,
                    y: start.y + (end.y - start.y) * eased
                )
                refreshCanvas()
                try? await Task.sleep(nanoseconds: 12_000_000)
            }
            store.document.viewport.centerOnAxisOrigin(in: canvasSize)
            refreshCanvas()
        }
    }

    private func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private func handleBack() {
        if store.hasUnsavedChanges {
            showUnsavedAlert = true
        } else {
            dismiss()
        }
    }

    private func discardChangesAndDismiss() {
        pendingDismiss = false
        if let lastSavedSnapshot {
            store.document = VectrDocument(snapshot: lastSavedSnapshot)
            store.hasUnsavedChanges = false
            store.contentRevision += 1
            store.needsInitialViewportLayout = false
        } else if let url = store.fileURL {
            do {
                try store.load(from: url)
                syncDisplayName(for: url)
                lastSavedSnapshot = snapshotFromStore()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        dismiss()
    }

    private func updateChromeInsets() {
        let panelWidth: CGFloat
        switch store.document.activeCategory {
        case .fillet, .addAnchor, .pattern:
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

    private func handleToolSelected(_ category: ToolCategory) {
        showCommandPanel = category.isDrawingTool
        showLayersPanel = false
        if category != .type {
            endTextEditingIfNeeded()
        }
        if category != .pattern {
            patternPreviewStrokes = []
        }
        switch category {
        case .type:
            commandSession.cancel()
            store.document.selectedStrokeID = nil
            statusMessage = "Tap to place or edit text; drag to move, corners to scale"
        case .delete:
            if let id = store.document.selectedStrokeID {
                store.document.removeStroke(id: id)
                refreshCanvas()
            } else if let textID = store.document.selectedTextID {
                store.document.removeTextElement(id: textID)
                refreshCanvas()
            } else {
                statusMessage = "Select a shape or text to delete"
            }
            commandSession.cancel()
        case .trim:
            commandSession.cancel()
            store.document.clearToolSelections()
            if store.document.selectedStrokeID == nil {
                statusMessage = "Tap a shape to select it"
            } else {
                statusMessage = "Tap a red side marker to remove that edge, or a corner to delete the point"
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
                statusMessage = "Select a closed shape, then tap an edge or enter total anchor count"
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
        case .curve:
            commandSession.cancel()
            store.document.selectedStrokeID = nil
            statusMessage = "Draw lines with Apple Pencil; double-tap to finish the curve"
        case .move, .scale, .dimensions:
            commandSession.cancel()
            if category == .move {
                store.document.clearToolSelections()
                if store.document.selectedTextID != nil {
                    statusMessage = "Drag to move the text, or use the handle to rotate"
                } else if store.document.selectedStrokeID == nil {
                    statusMessage = "Select a shape or text to move or rotate"
                } else {
                    statusMessage = "Tap an anchor to select it; double-tap to multi-select; drag to move"
                }
            }
        default:
            startDrawingSessionIfNeeded()
        }
        updateChromeInsets()
    }

    private func startDrawingSessionIfNeeded(anchor: CGPoint? = nil) {
        guard store.document.activeCategory.isDrawingTool else {
            commandSession.cancel()
            resetArcDragState()
            updateChromeInsets()
            return
        }
        resetArcDragState()
        store.document.selectedStrokeID = nil
        commandSession.start(
            category: store.document.activeCategory,
            lineVariant: store.document.lineVariant,
            circleVariant: store.document.circleVariant,
            rectangleVariant: store.document.rectangleVariant
        )
        if let anchor {
            commandSession.addPoint(anchor)
        }
        updateChromeInsets()
        refreshCanvas()
    }

    private var lineConnectTolerance: CGFloat {
        store.document.grid.visualSpacing(for: store.document.settings) * 0.5
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
        refreshCanvas()
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
            refreshCanvas()
        }
    }

    private func handleCanvasTap(_ documentPoint: CGPoint) {
        showCommandPanel = false
        showLayersPanel = false
        switch store.document.activeCategory {
        case .type:
            endTextEditingIfNeeded()
            if let hit = store.document.selectTextElement(at: documentPoint) {
                beginTextEditing(hit.id)
            } else {
                let element = TextElement(
                    layerID: store.document.activeLayerID,
                    text: "",
                    position: documentPoint,
                    fontRef: store.document.activeFontRef,
                    fontSize: store.document.activeFontSize,
                    color: store.document.strokeColor
                )
                store.document.addTextElement(element)
                beginTextEditing(element.id)
                store.markDirty()
                refreshCanvas()
            }
        case .line, .circle, .rectangle:
            if commandSession.isRefiningAttachedStroke {
                startDrawingSessionIfNeeded()
            }
            guard commandSession.isActive else { return }
            let snapped = snapDrawingInput(documentPoint)
            let projected = ShapeGeometry.projectCommandPoint(
                snapped,
                controlPoints: commandSession.controlPoints,
                category: store.document.activeCategory,
                lineVariant: store.document.lineVariant,
                circleVariant: store.document.circleVariant,
                rectangleVariant: store.document.rectangleVariant
            )
            let final = snapDrawingControlInput(snapped, projected: projected)
            commandSession.addPoint(final)
            if commandSession.canFinish, shouldAutoCommitAfterPoint {
                commitCommandShape(restart: true)
            } else {
                refreshCanvas()
            }
        case .trim:
            let threshold = store.document.viewport.viewToDocument(distance: 16)
            if let stroke = store.document.selectedStrokeID.flatMap({ store.document.stroke(with: $0) }) {
                if let pointIndex = StrokeEditor.nearestHandleIndex(in: stroke, point: documentPoint, threshold: threshold) {
                    store.document.deleteStrokePoint(at: pointIndex)
                    refreshCanvas()
                } else if stroke.shapeType != .circle, stroke.shapeType != .ellipse,
                          let edgeIndex = StrokeEditor.nearestEdgeIndex(in: stroke, point: documentPoint, threshold: threshold) {
                    store.document.deleteStrokeEdge(at: edgeIndex)
                    refreshCanvas()
                }
            } else {
                _ = store.document.selectStroke(near: documentPoint, threshold: threshold)
                refreshCanvas()
            }
        case .addAnchor:
            let threshold = store.document.viewport.viewToDocument(distance: 28)
            if let stroke = store.document.selectedStrokeID.flatMap({ store.document.stroke(with: $0) }) {
                if AnchorPointEngine.canEditAnchors(on: stroke) {
                    let snapped = snapDrawingInput(documentPoint)
                    if store.document.insertAnchor(at: snapped, threshold: threshold) {
                        refreshCanvas()
                    } else {
                        statusMessage = "Tap closer to an edge between anchors"
                    }
                } else {
                    statusMessage = "Select a closed shape to add anchors"
                }
            } else {
                _ = store.document.selectStroke(near: documentPoint, threshold: threshold)
                refreshCanvas()
            }
        case .pattern:
            let threshold = store.document.viewport.viewToDocument(distance: 16)
            store.document.selectElement(near: documentPoint, threshold: threshold)
            if let id = store.document.selectedStrokeID,
               let stroke = store.document.stroke(with: id) {
                patternSettings = PatternSettings.defaults(for: stroke)
            } else {
                patternPreviewStrokes = []
            }
            updatePatternPreview()
            refreshCanvas()
        case .delete:
            if let text = store.document.textElement(at: documentPoint) {
                store.document.removeTextElement(id: text.id)
                refreshCanvas()
                return
            }
            let threshold = store.document.viewport.viewToDocument(distance: 24)
            if let stroke = store.document.selectStroke(near: documentPoint, threshold: threshold) {
                store.document.removeStroke(id: stroke.id)
                refreshCanvas()
            } else if let selected = store.document.selectedStrokeID {
                store.document.removeStroke(id: selected)
                refreshCanvas()
            } else if let selectedText = store.document.selectedTextID {
                store.document.removeTextElement(id: selectedText)
                refreshCanvas()
            }
        default:
            let threshold = store.document.viewport.viewToDocument(distance: 16)
            store.document.selectElement(near: documentPoint, threshold: threshold)
            refreshCanvas()
        }
    }

    private func commitDragDraw(start: CGPoint, end: CGPoint) {
        let snappedStart = snapDrawingInput(start)
        let snappedEnd = snapDrawingInput(end)
        guard hypot(snappedEnd.x - snappedStart.x, snappedEnd.y - snappedStart.y) > 0.001 else {
            startDrawingSessionIfNeeded()
            return
        }

        let controlPoints = dragControlPoints(start: snappedStart, end: snappedEnd)
        guard !controlPoints.isEmpty else {
            startDrawingSessionIfNeeded()
            return
        }

        commandSession.start(
            category: store.document.activeCategory,
            lineVariant: store.document.lineVariant,
            circleVariant: store.document.circleVariant,
            rectangleVariant: store.document.rectangleVariant
        )
        for point in controlPoints {
            commandSession.addPoint(point)
        }

        guard commandSession.canFinish else {
            startDrawingSessionIfNeeded()
            return
        }

        // Use the same commit pathway as point-by-point entry.
        commitCommandShape(restart: false)

        if store.document.activeCategory.isDrawingTool {
            startDrawingSessionIfNeeded()
        } else {
            commandSession.cancel()
        }
    }

    private func commitCurve(anchors: [CGPoint]) {
        guard anchors.count >= 2 else { return }
        let stroke = VectorStroke(
            layerID: store.document.activeLayerID,
            points: anchors,
            strokeWidth: store.document.strokeWidth,
            strokeColor: store.document.strokeColor,
            isClosed: false,
            shapeType: .curve,
            curveHandles: ShapeGeometry.defaultCurveHandles(anchors: anchors)
        )
        store.document.addStroke(stroke)
        // Select the new curve so its anchor + tangent handles are immediately editable.
        store.document.selectedStrokeID = stroke.id
        store.markDirty()
        refreshCanvas()
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
            if restart, store.document.activeCategory.isDrawingTool {
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
        refreshCanvas()

        if restart, store.document.activeCategory.isDrawingTool {
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

    private func refreshCanvas() {
        store.markDirty()
    }

    private func snapshotFromStore() -> DocumentSnapshot {
        DocumentSnapshot(
            layers: store.document.layers,
            strokes: store.document.strokes,
            activeLayerID: store.document.activeLayerID,
            viewport: store.document.viewport,
            grid: store.document.grid,
            settings: store.document.settings,
            strokeWidth: store.document.strokeWidth,
            strokeColor: store.document.strokeColor,
            selectedStrokeID: store.document.selectedStrokeID,
            referenceImageData: store.document.referenceImageData,
            referenceImageFrame: store.document.referenceImageFrame,
            printLayout: store.document.printLayout,
            printStrokeTransforms: store.document.printStrokeTransforms,
            registrationMarks: store.document.registrationMarks
        )
    }

    private func saveDocument() {
        do {
            if store.fileURL == nil, let library = projectLibrary {
                let record = try library.createProject(name: store.fileName)
                store.fileURL = record.fileURL
                store.fileName = record.name
            }
            if let url = store.fileURL, let library = projectLibrary {
                let renamedURL = try library.renameProject(fileURL: url, name: store.fileName)
                store.fileURL = renamedURL
                syncDisplayName(for: renamedURL)
            }
            try store.save()
            if let url = store.fileURL, let library = projectLibrary {
                try library.updateAfterSave(document: store.document, fileURL: url, name: store.fileName)
            }
            lastSavedSnapshot = snapshotFromStore()
            if pendingDismiss {
                pendingDismiss = false
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareExport() {
        do {
            let tempURL = try ExportRouter.temporaryExportURL(
                document: store.document,
                name: store.fileName,
                format: exportFormat
            )
            exportDocument = EditorExportDocument(fileURL: tempURL)
            showFileExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditorExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { ExportFormat.allCases.map(\.contentType) }

    var fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Data(contentsOf: fileURL))
    }
}

extension UTType {
    static var vectrDocument: UTType {
        UTType(exportedAs: "earthwrm.vectr.document", conformingTo: .json)
    }
}

#Preview {
    NavigationStack {
        EditorView()
    }
}
