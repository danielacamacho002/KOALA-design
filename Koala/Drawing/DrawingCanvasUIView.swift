//
//  DrawingCanvasUIView.swift
//  Koala
//

import SwiftUI
import UIKit

protocol DrawingCanvasDelegate: AnyObject {
    func canvasDidUpdate(document: KoalaDocument)
    func canvasDidSelectStroke(_ stroke: VectorStroke?)
}

final class DrawingCanvasUIView: UIView {
    weak var delegate: DrawingCanvasDelegate?

    var document: KoalaDocument {
        didSet {
            performWithoutLayerAnimation {
                reloadStrokes()
                reloadReferenceImages()
                updateGridPresentation(forcePathRebuild: true)
            }
        }
    }

    var activeCategory: ToolCategory? {
        didSet {
            if oldValue == .curve, activeCategory != .curve {
                // Don't discard an in-progress curve when leaving the tool: commit it
                // so the drawn strokes persist. Deferred to avoid mutating document
                // state during a SwiftUI view update. A resumed curve with no new
                // points finishes as nil and is left unchanged.
                let finish = curveDraft?.makeFinish()
                resetCurve()
                if let finish {
                    DispatchQueue.main.async { [weak self] in
                        self?.onCurveCommitted?(finish)
                    }
                }
            }
        }
    }
    var lineVariant: LineVariant = .line
    var commandPreviewPoints: [CGPoint] = [] {
        didSet { updateCommandPreviewLayer() }
    }
    var commandControlPoints: [CGPoint] = [] {
        didSet { updateCommandPreviewLayer() }
    }
    var commandCanFinish = false {
        didSet { updateCommandPreviewLayer() }
    }
    var isConstructionPreview = false
    var commandPreviewClosed = false
    var allowsDragDraw = false
    /// Span the trim tool is about to remove, flashed in red before the cut applies.
    var trimPreviewPoints: [CGPoint] = [] {
        didSet { updateTrimPreviewLayer() }
    }
    var trimPreviewStrokeWidth: CGFloat = 1 {
        didSet { updateTrimPreviewLayer() }
    }
    var circleVariant: CircleVariant = .center
    var rectangleVariant: RectangleVariant = .center
    var onCanvasTap: ((CGPoint) -> Void)?
    var onDragDrawBegan: ((CGPoint) -> Void)?
    var onDragDrawChanged: ((CGPoint, CGPoint) -> Void)?
    var onDragDrawEnded: ((CGPoint, CGPoint) -> Void)?
    /// In-progress curve anchors and per-segment undo, owned by the editor.
    var curveDraft: CurveDraftSession? {
        didSet {
            if oldValue !== curveDraft {
                oldValue?.detachCanvas(self)
                curveDraft?.attachCanvas(self)
            }
            updateCurvePreview()
        }
    }
    /// Emitted when a curve is finished (double-tap or leaving the tool).
    var onCurveCommitted: ((CurveDraftFinish) -> Void)?
    /// Bounds size and safe-area insets in this view's own coordinate space.
    var onLayoutMetrics: ((CGSize, UIEdgeInsets) -> Void)?

    private var strokeLayers: [UUID: CAShapeLayer] = [:]
    /// Width and dash inputs cached so a pinch does not scan the document per shape.
    private struct ArtworkStrokeMetrics {
        var strokeWidth: CGFloat
        var isConstruction: Bool
        var rendersSeparateOutline: Bool
    }
    private var artworkStrokeMetrics: [UUID: ArtworkStrokeMetrics] = [:]
    private var artworkMaxStrokeWidth: CGFloat = 0
    private var artworkHasConstruction = false
    /// True after line widths were written for a zoom range where they do not depend on scale.
    private var artworkAppliedUncappedMetrics = false
    /// Green rim drawn just behind each selected stroke.
    private var selectionHaloLayers: [UUID: CAShapeLayer] = [:]
    private var textLayers: [UUID: CAShapeLayer] = [:]
    /// Document-space shift of a group move. Member paths stay where they were
    /// drawn; only layer positions move until the drag commits.
    private var translationPreviewDelta: CGPoint = .zero
    private var translationPreviewStrokeIDs: Set<UUID> = []
    private var translationPreviewTextIDs: Set<UUID> = []
    /// Outline-text stroke widths. Filled text does not change with zoom.
    private var outlineTextWidths: [UUID: CGFloat] = [:]
    private var commandPreviewLayer: CAShapeLayer?
    private var dragPreviewLayer: CAShapeLayer?
    private var trimPreviewLayer: CAShapeLayer?
    private var commandPointLayers: [CAShapeLayer] = []
    private var dragDrawStart: CGPoint?
    private var dragDrawCurrent: CGPoint?
    /// True after a `.changed` sample, so a lift can be compared to the preview.
    /// A stroke that jumps from `.began` to `.ended` leaves this false.
    private var dragDrawHasMoved = false
    private var curveDragStart: CGPoint?
    private var curveDragCurrent: CGPoint?
    private var curvePreviewLayer: CAShapeLayer?
    private var curveAnchorLayers: [CAShapeLayer] = []
    private let gridLayer = CALayer()
    private let sheetLayer = CALayer()
    private let worldLayer = CALayer()
    /// Strokes, text, halos, and reference images in document space. Pinch and pan
    /// set this layer's transform instead of rebuilding every path.
    private let artworkLayer = CALayer()
    private let clipLayer = CALayer()
    private var rankLayers: [CAShapeLayer] = []
    private let axisXLayer = CAShapeLayer()
    private let axisYLayer = CAShapeLayer()
    private var cachedGridCoverage: CGRect = .null
    private var cachedGridSubdiv: Int = -1
    private var cachedGridMajor: CGFloat = -1
    private var cachedCanvasSize: CGSize = .zero
    private var referenceImageLayers: [UUID: CALayer] = [:]
    private var cachedReferenceImages: [UUID: (data: Data, contents: CGImage)] = [:]
    private var lastLaidOutSize: CGSize = .zero
    private var lastEmittedLayoutSize: CGSize = .zero
    private var lastEmittedSafeAreaInsets: UIEdgeInsets = .zero
    private var layoutMetricsWorkItem: DispatchWorkItem?
    private var viewportAnimationTask: Task<Void, Never>?

    // Object snapping (endpoints/midpoints). Decoupled engine + per-gesture lock session +
    // visual/haptic feedback. Toggle globally via `document.isSnappingEnabled`.
    private let snapEngine = PathSnapEngine.makeDefault()
    private let snapSession = SnapInteractionSession()
    private let snapHaptics = SnapHaptics()
    private let snapIndicator = SnapIndicatorRenderer()
    private let axisLockGlyph = AxisLockGlyphRenderer()

    /// Color of the canvas sheet itself (the area within the canvas bounds). The view's
    /// `backgroundColor` is the surrounding dark pasteboard shown when zoomed out.
    var canvasFillColor: UIColor = UIColor(Color(hex: AppearanceSettings.defaultCanvasHex)) {
        didSet {
            guard canvasFillColor != oldValue else { return }
            sheetLayer.backgroundColor = canvasFillColor.resolvedColor(with: traitCollection).cgColor
        }
    }

    init(document: KoalaDocument) {
        self.document = document
        super.init(frame: .zero)
        backgroundColor = UIColor(Color(hex: AppearanceSettings.pasteboardHex))
        isMultipleTouchEnabled = true
        layer.addSublayer(gridLayer)
        setupGridLayers()
        setupArtworkLayer()
        setupGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let newSize = bounds.size
        let sizeChanged = lastLaidOutSize.width == 0
            || abs(newSize.width - lastLaidOutSize.width) > 0.5
            || abs(newSize.height - lastLaidOutSize.height) > 0.5

        performWithoutLayerAnimation {
            if sizeChanged, lastLaidOutSize.width > 0, lastLaidOutSize.height > 0 {
                applyViewportIfNeeded {
                    $0.preserveCenter(from: lastLaidOutSize, to: newSize)
                }
            }
            gridLayer.frame = bounds
            clampViewportToCanvasExtent()
            if sizeChanged {
                if strokeLayers.isEmpty && textLayers.isEmpty {
                    reloadStrokes()
                    reloadReferenceImages()
                    refreshCommandPreview()
                    updateGridPresentation(forcePathRebuild: true)
                } else {
                    refreshViewportContents()
                }
            }
        }

        if sizeChanged {
            lastLaidOutSize = newSize
        }
        scheduleLayoutMetricsNotification(immediate: lastEmittedLayoutSize == .zero)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        performWithoutLayerAnimation {
            applyGridColors()
            sheetLayer.backgroundColor = canvasFillColor.resolvedColor(with: traitCollection).cgColor
        }
    }

    func handleSelection(at viewPoint: CGPoint) {
        let documentPoint = document.viewport.viewToDocument(viewPoint)
        let threshold = document.viewport.viewToDocument(distance: 16)
        let selection = document.selectElement(near: documentPoint, threshold: threshold)
        switch selection {
        case .stroke(let id):
            delegate?.canvasDidSelectStroke(document.stroke(with: id))
        case .text, .referenceImage, .none:
            delegate?.canvasDidSelectStroke(nil)
        }
        reloadStrokesHighlight()
    }

    // MARK: - Stroke layers

    /// Content layers are banded by document-layer index (+1 keeps them above the
    /// grid/reference image at 0); previews use `Self.previewZPosition` to stay on top.
    private func layerZPositions() -> [UUID: CGFloat] {
        Dictionary(uniqueKeysWithValues: document.layers.enumerated().map { ($1.id, CGFloat($0 + 1)) })
    }

    static let previewZPosition: CGFloat = 10_000

    func reloadStrokes() {
        let visible = document.visibleStrokes()
        let visibleIDs = Set(visible.map(\.id))
        let zPositions = layerZPositions()

        let staleIDs = strokeLayers.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            strokeLayers[id]?.removeFromSuperlayer()
            strokeLayers.removeValue(forKey: id)
            selectionHaloLayers[id]?.removeFromSuperlayer()
            selectionHaloLayers.removeValue(forKey: id)
        }

        var metrics: [UUID: ArtworkStrokeMetrics] = [:]
        metrics.reserveCapacity(visible.count)
        var maxStrokeWidth: CGFloat = 0
        var hasConstruction = false
        for stroke in visible {
            if let existing = strokeLayers[stroke.id] {
                StrokeRenderer.updateShapeLayer(
                    existing,
                    stroke: stroke,
                    viewport: StrokeRenderer.documentSpaceViewport,
                    opacity: document.opacity(forLayerID: stroke.layerID),
                    limitZoomedWidth: true
                )
            } else {
                addStrokeLayer(stroke)
            }
            strokeLayers[stroke.id]?.zPosition = zPositions[stroke.layerID] ?? 1
            let separateOutline = StrokeRenderer.rendersSeparateOutline(stroke)
            metrics[stroke.id] = ArtworkStrokeMetrics(
                strokeWidth: stroke.strokeWidth,
                isConstruction: stroke.isConstruction,
                rendersSeparateOutline: separateOutline
            )
            maxStrokeWidth = max(maxStrokeWidth, stroke.strokeWidth)
            if stroke.isConstruction {
                hasConstruction = true
            }
        }
        artworkStrokeMetrics = metrics
        artworkMaxStrokeWidth = maxStrokeWidth
        artworkHasConstruction = hasConstruction
        artworkAppliedUncappedMetrics = false
        reloadStrokesHighlight()
        reloadTextElements()
        reloadReferenceImages()
        applyContinuationVisibility()
        applyArtworkTransform()
        // A reload mid-drag rebuilds halos at position zero. Put the preview back.
        if !translationPreviewStrokeIDs.isEmpty || !translationPreviewTextIDs.isEmpty {
            setTranslationPreview(
                translationPreviewDelta,
                strokeIDs: translationPreviewStrokeIDs,
                textIDs: translationPreviewTextIDs
            )
        }
    }

    func reloadTextElements() {
        let visible = document.visibleTextElements()
        let visibleIDs = Set(visible.map(\.id))
        let zPositions = layerZPositions()

        let staleIDs = textLayers.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            textLayers[id]?.removeFromSuperlayer()
            textLayers.removeValue(forKey: id)
        }

        for element in visible {
            let opacity = document.opacity(forLayerID: element.layerID)
            if let existing = textLayers[element.id] {
                TextRenderer.updateDocumentSpace(
                    existing,
                    for: element,
                    scale: document.viewport.scale,
                    opacity: opacity
                )
            } else {
                let created = TextRenderer.makeDocumentSpaceLayer(
                    for: element,
                    scale: document.viewport.scale,
                    opacity: opacity
                )
                artworkLayer.addSublayer(created)
                textLayers[element.id] = created
            }
            textLayers[element.id]?.zPosition = zPositions[element.layerID] ?? 1
        }
        var outlines: [UUID: CGFloat] = [:]
        for element in visible where element.isOutline {
            outlines[element.id] = element.strokeWidth
        }
        outlineTextWidths = outlines
    }

    func reloadReferenceImages() {
        let images = document.visibleReferenceImages()
        let ids = Set(images.map(\.id))
        let zPositions = layerZPositions()

        for id in referenceImageLayers.keys where !ids.contains(id) {
            referenceImageLayers[id]?.removeFromSuperlayer()
            referenceImageLayers.removeValue(forKey: id)
            cachedReferenceImages.removeValue(forKey: id)
        }

        for (index, item) in images.enumerated() {
            if cachedReferenceImages[item.id]?.data != item.data {
                if let image = UIImage(data: item.data),
                   let contents = ReferenceImageDrawing.uprightCGImage(from: image) {
                    cachedReferenceImages[item.id] = (item.data, contents)
                } else {
                    cachedReferenceImages.removeValue(forKey: item.id)
                }
            }
            guard let contents = cachedReferenceImages[item.id]?.contents else {
                referenceImageLayers[item.id]?.removeFromSuperlayer()
                referenceImageLayers.removeValue(forKey: item.id)
                continue
            }

            let imageLayer: CALayer
            if let existing = referenceImageLayers[item.id] {
                imageLayer = existing
            } else {
                let created = CALayer()
                artworkLayer.addSublayer(created)
                referenceImageLayers[item.id] = created
                imageLayer = created
            }

            let frame = item.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.contents = contents
            imageLayer.contentsGravity = .resize
            imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            imageLayer.bounds = CGRect(origin: .zero, size: frame.size)
            imageLayer.position = center
            imageLayer.transform = item.rotation == 0
                ? CATransform3DIdentity
                : CATransform3DMakeRotation(item.rotation, 0, 0, 1)
            imageLayer.opacity = Float(document.opacity(forLayerID: item.layerID) * item.opacity)
            let layerZ = zPositions[item.layerID] ?? 1
            imageLayer.zPosition = layerZ - 0.5 + CGFloat(index) * 0.001
            CATransaction.commit()
        }
    }

    private func addStrokeLayer(_ stroke: VectorStroke) {
        let shapeLayer = StrokeRenderer.makeShapeLayer(
            for: stroke,
            viewport: StrokeRenderer.documentSpaceViewport,
            opacity: document.opacity(forLayerID: stroke.layerID),
            limitZoomedWidth: true
        )
        artworkLayer.addSublayer(shapeLayer)
        strokeLayers[stroke.id] = shapeLayer
    }

    private func reloadStrokesHighlight() {
        var selected = document.selectedStrokeIDs
        if let id = document.selectedStrokeID {
            selected.insert(id)
        }
        for (id, layer) in strokeLayers {
            guard let stroke = document.stroke(with: id) else { continue }
            let base = document.opacity(forLayerID: stroke.layerID)
            layer.opacity = Float(base * (selected.contains(id) ? 1 : 0.85))
        }
        updateSelectionHalos(selected: selected)
    }

    /// Strokes a wider copy of each selected path behind the artwork so a green
    /// rim shows around the shape, in the same green as an active toolbar icon.
    private func updateSelectionHalos(selected: Set<UUID>) {
        for id in selectionHaloLayers.keys where !selected.contains(id) {
            selectionHaloLayers[id]?.removeFromSuperlayer()
            selectionHaloLayers.removeValue(forKey: id)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in selected {
            guard let stroke = document.stroke(with: id),
                  let strokeLayer = strokeLayers[id] else {
                selectionHaloLayers[id]?.removeFromSuperlayer()
                selectionHaloLayers.removeValue(forKey: id)
                continue
            }
            let halo = selectionHaloLayer(for: id, below: strokeLayer)
            let scale = document.viewport.scale
            let screenWidth = CanvasOverlayGeometry.displayStrokeScreenWidth(
                strokeWidth: stroke.strokeWidth,
                scale: scale
            )
            let inv = 1 / max(scale, .leastNonzeroMagnitude)
            halo.path = StrokeRenderer.outlinePath(
                for: stroke,
                viewport: StrokeRenderer.documentSpaceViewport
            ).cgPath
            halo.lineWidth = (screenWidth + CanvasOverlayGeometry.selectionHaloOutset * 2) * inv
            halo.lineDashPattern = stroke.isConstruction
                ? StrokeRenderer.constructionDashPattern(scale: scale)
                : nil
            // Same depth as the stroke, sitting immediately under it, so the rim
            // shows around the shape and still paints over artwork behind it.
            halo.zPosition = strokeLayer.zPosition
            halo.opacity = Float(document.opacity(forLayerID: stroke.layerID))
            halo.contentsScale = DisplayZoomCompensation.layerContentsScale
        }
        CATransaction.commit()
    }

    private func selectionHaloLayer(for id: UUID, below strokeLayer: CAShapeLayer) -> CAShapeLayer {
        let halo: CAShapeLayer
        if let existing = selectionHaloLayers[id] {
            halo = existing
        } else {
            let created = CAShapeLayer()
            created.fillColor = nil
            created.lineCap = .round
            created.lineJoin = .round
            created.strokeColor = SelectionHighlight.iconUIColor.cgColor
            selectionHaloLayers[id] = created
            halo = created
        }
        let sublayers = artworkLayer.sublayers
        let haloIndex = sublayers?.firstIndex(of: halo)
        let strokeIndex = sublayers?.firstIndex(of: strokeLayer)
        if halo.superlayer !== artworkLayer || haloIndex != strokeIndex.map({ $0 - 1 }) {
            artworkLayer.insertSublayer(halo, below: strokeLayer)
        }
        return halo
    }

    func refreshStrokeHighlight() {
        reloadStrokesHighlight()
    }

    /// Shifts already-drawn stroke, halo, and text layers by a document-space delta.
    /// Paths are absolute in `artworkLayer`, so this is a position change, not a rebuild.
    func previewTranslation(delta: CGPoint, strokeIDs: Set<UUID>, textIDs: Set<UUID>) {
        let retiredStrokes = translationPreviewStrokeIDs.subtracting(strokeIDs)
        let retiredText = translationPreviewTextIDs.subtracting(textIDs)
        translationPreviewDelta = delta
        translationPreviewStrokeIDs = strokeIDs
        translationPreviewTextIDs = textIDs
        performWithoutLayerAnimation {
            setTranslationPreview(.zero, strokeIDs: retiredStrokes, textIDs: retiredText)
            setTranslationPreview(delta, strokeIDs: strokeIDs, textIDs: textIDs)
        }
    }

    /// Drops the preview shift. When `reloadGeometry` is set, rebuilds paths in the
    /// same transaction so the reset and the committed geometry appear together.
    func endTranslationPreview(reloadGeometry: Bool) {
        let strokes = translationPreviewStrokeIDs
        let texts = translationPreviewTextIDs
        guard !strokes.isEmpty || !texts.isEmpty else { return }
        translationPreviewDelta = .zero
        translationPreviewStrokeIDs = []
        translationPreviewTextIDs = []
        performWithoutLayerAnimation {
            setTranslationPreview(.zero, strokeIDs: strokes, textIDs: texts)
            if reloadGeometry {
                reloadStrokes()
            }
        }
    }

    private func setTranslationPreview(_ delta: CGPoint, strokeIDs: Set<UUID>, textIDs: Set<UUID>) {
        guard !strokeIDs.isEmpty || !textIDs.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in strokeIDs {
            strokeLayers[id]?.position = delta
            selectionHaloLayers[id]?.position = delta
        }
        for id in textIDs {
            textLayers[id]?.position = delta
        }
        CATransaction.commit()
    }

    func refreshViewport() {
        performWithoutLayerAnimation {
            refreshViewportContents()
        }
    }

    func cancelViewportAnimation() {
        viewportAnimationTask?.cancel()
        viewportAnimationTask = nil
    }

    func animateViewport(to target: ViewportTransform) {
        cancelViewportAnimation()
        let start = document.viewport
        let translationDelta = hypot(
            target.translation.x - start.translation.x,
            target.translation.y - start.translation.y
        )
        guard translationDelta > 0.5 || abs(target.scale - start.scale) > 0.0001 else { return }

        viewportAnimationTask = Task { @MainActor [weak self] in
            let steps = 24
            for step in 1...steps {
                if Task.isCancelled { return }
                guard let self else { return }
                let t = ViewportTransform.easeInOut(CGFloat(step) / CGFloat(steps))
                self.document.viewport = start.interpolated(toward: target, t: t)
                self.refreshViewport()
                try? await Task.sleep(nanoseconds: 12_000_000)
            }
            if Task.isCancelled { return }
            guard let self else { return }
            self.document.viewport = target
            self.refreshViewport()
        }
    }

    private func refreshViewportContents() {
        applyArtworkTransform()
        if !commandPreviewPoints.isEmpty || !commandControlPoints.isEmpty {
            updateCommandPreviewLayer()
        }
        if dragDrawStart != nil {
            updateDragPreviewLayer()
        }
        if trimPreviewPoints.count >= 2 {
            updateTrimPreviewLayer()
        }
        if !(curveDraft?.anchors.isEmpty ?? true) || curveDragCurrent != nil {
            updateCurvePreview()
        }
        updateGridPresentation()
    }

    private func setupArtworkLayer() {
        artworkLayer.anchorPoint = .zero
        artworkLayer.position = .zero
        artworkLayer.masksToBounds = false
        artworkLayer.zPosition = 1
        layer.addSublayer(artworkLayer)
    }

    /// Pan and zoom move `artworkLayer`. Stroke paths stay in document space.
    /// Line widths are rewritten only once a stroke is thick enough on screen that
    /// the cap (or a construction dash) actually depends on the zoom level.
    private func applyArtworkTransform() {
        let scale = document.viewport.scale
        artworkLayer.setAffineTransform(document.viewport.affineTransform)
        if artworkZoomNeedsMetricUpdate(scale: scale) {
            for (id, metrics) in artworkStrokeMetrics {
                guard let shape = strokeLayers[id] else { continue }
                let widthChanges = strokeWidthDependsOnScale(metrics.strokeWidth, scale: scale)
                if !metrics.isConstruction && !widthChanges && artworkAppliedUncappedMetrics {
                    continue
                }
                StrokeRenderer.applyDocumentSpaceZoom(
                    shape,
                    strokeWidth: metrics.strokeWidth,
                    isConstruction: metrics.isConstruction,
                    rendersSeparateOutline: metrics.rendersSeparateOutline,
                    scale: scale
                )
            }
            artworkAppliedUncappedMetrics = !artworkWidthsDependOnScale(scale)
        }
        if !selectionHaloLayers.isEmpty {
            updateHaloZoomMetrics(scale: scale)
        }
        if !outlineTextWidths.isEmpty {
            for (id, strokeWidth) in outlineTextWidths {
                guard let textLayer = textLayers[id] else { continue }
                let local = CanvasOverlayGeometry.displayStrokeDocumentWidth(
                    strokeWidth: strokeWidth,
                    scale: scale
                )
                if textLayer.lineWidth != local {
                    textLayer.lineWidth = local
                }
            }
        }
    }

    private func artworkZoomNeedsMetricUpdate(scale: CGFloat) -> Bool {
        if artworkHasConstruction || !artworkAppliedUncappedMetrics {
            return true
        }
        return artworkWidthsDependOnScale(scale)
    }

    /// True when at least one stroke's on-screen width is holding at the cap,
    /// so its document-space line width has to shrink as the zoom grows.
    private func artworkWidthsDependOnScale(_ scale: CGFloat) -> Bool {
        guard artworkMaxStrokeWidth > 0, scale > 0 else { return false }
        return strokeWidthDependsOnScale(artworkMaxStrokeWidth, scale: scale)
    }

    private func strokeWidthDependsOnScale(_ strokeWidth: CGFloat, scale: CGFloat) -> Bool {
        let cap = CanvasOverlayGeometry.displayStrokeScreenCap
        if strokeWidth > cap { return scale > 1 }
        if strokeWidth <= 0 { return false }
        return scale > cap / strokeWidth
    }

    private func updateHaloZoomMetrics(scale: CGFloat) {
        let inv = 1 / max(scale, .leastNonzeroMagnitude)
        let outset = CanvasOverlayGeometry.selectionHaloOutset * 2 * inv
        for (id, halo) in selectionHaloLayers {
            let metrics = artworkStrokeMetrics[id]
            let screen = CanvasOverlayGeometry.displayStrokeScreenWidth(
                strokeWidth: metrics?.strokeWidth ?? 0,
                scale: scale
            )
            let local = screen * inv + outset
            if halo.lineWidth != local {
                halo.lineWidth = local
            }
            if metrics?.isConstruction == true {
                let dash = StrokeRenderer.constructionDashPattern(scale: scale)
                if halo.lineDashPattern != dash {
                    halo.lineDashPattern = dash
                }
            }
        }
    }

    // MARK: - Layer-backed grid

    private func setupGridLayers() {
        gridLayer.masksToBounds = true
        gridLayer.addSublayer(sheetLayer)
        gridLayer.addSublayer(worldLayer)

        worldLayer.anchorPoint = .zero
        worldLayer.position = .zero
        worldLayer.masksToBounds = false

        clipLayer.anchorPoint = .zero
        clipLayer.masksToBounds = true
        worldLayer.addSublayer(clipLayer)

        configureGridShapeLayer(axisXLayer, color: GridRenderer.axisXColor, width: GridRenderer.axisLineWidth)
        configureGridShapeLayer(axisYLayer, color: GridRenderer.axisYColor, width: GridRenderer.axisLineWidth)

        clipLayer.addSublayer(axisXLayer)
        clipLayer.addSublayer(axisYLayer)
        sheetLayer.backgroundColor = canvasFillColor.resolvedColor(with: traitCollection).cgColor
    }

    private func configureGridShapeLayer(_ layer: CAShapeLayer, color: UIColor, width: CGFloat) {
        layer.fillColor = nil
        layer.strokeColor = color.resolvedColor(with: traitCollection).cgColor
        layer.lineWidth = width
        layer.lineCap = .butt
        layer.lineJoin = .miter
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.contentsScale = max(traitCollection.displayScale, DisplayZoomCompensation.layerContentsScale)
    }

    /// Pans and zooms via a world transform. Paths rebuild only when LOD, settings,
    /// or the visible region walk off the cached padded coverage.
    private func updateGridPresentation(forcePathRebuild: Bool = false) {
        // Grid lines and axes honor the document's visibility toggle so thin
        // strokes can be inspected on a clean sheet. The canvas sheet lives
        // outside `clipLayer`, so the sheet extent stays visible.
        let gridHidden = !document.grid.isVisible
        clipLayer.isHidden = gridHidden
        if gridHidden {
            applyWorldTransform()
            updateSheetFrame()
            return
        }
        if forcePathRebuild || gridNeedsPathRebuild() {
            rebuildGridPaths()
        } else {
            applyWorldTransform()
        }
        updateSheetFrame()
    }

    private func gridNeedsPathRebuild() -> Bool {
        let viewport = document.viewport
        let grid = document.grid
        let settings = document.settings
        let canvasSize = settings.canvasSize
        let subdiv = grid.visibleSubdivisions(for: settings, scale: viewport.scale)
        let major = grid.visualSpacing(for: settings)

        if cachedGridSubdiv != subdiv { return true }
        if cachedGridMajor != major { return true }
        if cachedCanvasSize != canvasSize { return true }
        if cachedGridSubdiv < 0 { return true }

        let visible = GridRenderer.documentRect(fromViewBounds: bounds, viewport: viewport)
        let clipped: CGRect
        if let canvas = GridRenderer.canvasRect(size: canvasSize) {
            clipped = visible.intersection(canvas)
        } else {
            clipped = visible
        }
        if clipped.isNull || clipped.isEmpty {
            return false
        }
        if cachedGridCoverage.isNull || cachedGridCoverage.isEmpty {
            return true
        }
        return !cachedGridCoverage.contains(clipped)
    }

    private func rebuildGridPaths() {
        let viewport = document.viewport
        let grid = document.grid
        let settings = document.settings
        let canvasSize = settings.canvasSize
        let paths = GridRenderer.makeLayerPaths(
            viewBounds: bounds,
            viewport: viewport,
            grid: grid,
            documentSettings: settings,
            canvasSize: canvasSize,
            padScreens: 1
        )

        cachedGridCoverage = paths.coverage
        cachedGridSubdiv = grid.visibleSubdivisions(for: settings, scale: viewport.scale)
        cachedGridMajor = grid.visualSpacing(for: settings)
        cachedCanvasSize = canvasSize

        updateClipLayer(canvasRect: paths.canvasRect)

        ensureRankLayerCount(paths.rankPaths.count)
        for (index, path) in paths.rankPaths.enumerated() {
            rankLayers[index].path = path
            rankLayers[index].isHidden = path.isEmpty
        }
        for index in paths.rankPaths.count..<rankLayers.count {
            rankLayers[index].isHidden = true
            rankLayers[index].path = nil
        }

        axisXLayer.path = paths.axisX
        axisYLayer.path = paths.axisY

        applyGridColors()
        applyWorldTransform()
    }

    private func ensureRankLayerCount(_ count: Int) {
        while rankLayers.count < count {
            let layer = CAShapeLayer()
            configureGridShapeLayer(layer, color: GridRenderer.lineColor(rank: rankLayers.count), width: GridRenderer.gridLineWidth)
            clipLayer.insertSublayer(layer, below: axisXLayer)
            rankLayers.append(layer)
        }
    }

    private func updateClipLayer(canvasRect: CGRect?) {
        if let canvasRect, !canvasRect.isNull, !canvasRect.isEmpty {
            clipLayer.masksToBounds = true
            clipLayer.anchorPoint = .zero
            clipLayer.bounds = canvasRect
            clipLayer.position = CGPoint(x: canvasRect.minX, y: canvasRect.minY)
        } else {
            clipLayer.masksToBounds = false
            clipLayer.anchorPoint = .zero
            clipLayer.position = .zero
            clipLayer.bounds = .zero
        }
    }

    private func applyWorldTransform() {
        let viewport = document.viewport
        worldLayer.setAffineTransform(viewport.affineTransform)
        let inv = 1 / max(viewport.scale, .leastNonzeroMagnitude)
        let gridWidth = GridRenderer.gridLineWidth * inv
        for layer in rankLayers {
            layer.lineWidth = gridWidth
        }
        axisXLayer.lineWidth = GridRenderer.axisLineWidth * inv
        axisYLayer.lineWidth = GridRenderer.axisLineWidth * inv
    }

    private func updateSheetFrame() {
        let canvasSize = document.settings.canvasSize
        guard canvasSize.width > 0, canvasSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            sheetLayer.isHidden = true
            return
        }
        let canvasView = GridRenderer.canvasRectInView(viewport: document.viewport, canvasSize: canvasSize)
        let visible = canvasView.intersection(bounds)
        guard !visible.isNull, !visible.isEmpty else {
            sheetLayer.isHidden = true
            return
        }
        sheetLayer.isHidden = false
        sheetLayer.frame = visible
        sheetLayer.backgroundColor = canvasFillColor.resolvedColor(with: traitCollection).cgColor
    }

    private func applyGridColors() {
        for (index, layer) in rankLayers.enumerated() {
            layer.strokeColor = GridRenderer.lineColor(rank: index).resolvedColor(with: traitCollection).cgColor
        }
        axisXLayer.strokeColor = GridRenderer.axisXColor.resolvedColor(with: traitCollection).cgColor
        axisYLayer.strokeColor = GridRenderer.axisYColor.resolvedColor(with: traitCollection).cgColor
    }

    private func performWithoutLayerAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    /// Avoid writing `document.viewport` when nothing changed — KoalaDocument is
    /// `@Observable`, so a no-op assign still rebuilds the SwiftUI editor mid-rotation.
    private func applyViewportIfNeeded(_ mutate: (inout ViewportTransform) -> Void) {
        var viewport = document.viewport
        mutate(&viewport)
        guard viewport != document.viewport else { return }
        document.viewport = viewport
        delegate?.canvasDidUpdate(document: document)
    }

    /// Trailing-debounce layout metrics so rotation does not poke SwiftUI every frame.
    /// The first layout is reported immediately so the initial viewport can be framed.
    private func scheduleLayoutMetricsNotification(immediate: Bool) {
        let emit = { [weak self] in
            guard let self else { return }
            let size = self.bounds.size
            let insets = self.safeAreaInsets
            let sizeChanged = abs(size.width - self.lastEmittedLayoutSize.width) > 0.5
                || abs(size.height - self.lastEmittedLayoutSize.height) > 0.5
            let insetsChanged = abs(insets.top - self.lastEmittedSafeAreaInsets.top) > 0.5
                || abs(insets.bottom - self.lastEmittedSafeAreaInsets.bottom) > 0.5
                || abs(insets.left - self.lastEmittedSafeAreaInsets.left) > 0.5
                || abs(insets.right - self.lastEmittedSafeAreaInsets.right) > 0.5
            guard sizeChanged || insetsChanged else { return }
            self.lastEmittedLayoutSize = size
            self.lastEmittedSafeAreaInsets = insets
            self.onLayoutMetrics?(size, insets)
        }

        if immediate {
            layoutMetricsWorkItem?.cancel()
            emit()
            return
        }

        layoutMetricsWorkItem?.cancel()
        let work = DispatchWorkItem(block: emit)
        layoutMetricsWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    // MARK: - Gestures

    private func setupGestures() {
        let tap = PreciseTapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)

        let dragDraw = PrecisePanGestureRecognizer(target: self, action: #selector(handleDragDraw(_:)))
        dragDraw.maximumNumberOfTouches = 1
        dragDraw.delegate = self
        addGestureRecognizer(dragDraw)
        tap.require(toFail: dragDraw)

        let curveFinish = PreciseTapGestureRecognizer(target: self, action: #selector(handleCurveFinish(_:)))
        curveFinish.numberOfTapsRequired = 2
        curveFinish.delegate = self
        addGestureRecognizer(curveFinish)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let viewPoint = drawingViewPoint(from: gesture)
        let documentPoint = document.viewport.viewToDocument(viewPoint)

        switch activeCategory {
        case .line, .circle, .rectangle, .trim, .delete, .addAnchor, .type, .copy, .scale, .fillet, .pattern, .dimensions, .curve:
            // Forward taps so empty-canvas / outside-shape hits can dismiss the tool.
            // Scale/fillet handles still win via the overlay's high-priority gestures.
            onCanvasTap?(documentPoint)
        case .move, nil:
            // Move (the idle default) is handled by the SwiftUI overlay.
            break
        }
    }

    @objc private func handleDragDraw(_ gesture: UIPanGestureRecognizer) {
        guard allowsDragDraw else { return }
        if activeCategory == .curve {
            handleCurveDrag(gesture)
            return
        }
        switch gesture.state {
        case .began, .changed:
            guard gesture.numberOfTouches == 1 else { return }
        default:
            break
        }

        let viewPoint = drawingViewPoint(from: gesture)
        let rawPoint = document.viewport.viewToDocument(viewPoint)
        // Do not pin the free end to the start's axis. A nearly vertical stroke
        // would lock upright and the pencil could not place it in the gap.
        let documentPoint = snappedDragPoint(rawPoint)

        switch gesture.state {
        case .began:
            snapHaptics.prepare()
            let startPoint = dragStartPoint(for: documentPoint)
            dragDrawStart = startPoint
            dragDrawCurrent = startPoint
            dragDrawHasMoved = false
            updateDragPreviewLayer()
            onDragDrawBegan?(startPoint)
        case .changed:
            guard let start = dragDrawStart else { return }
            dragDrawHasMoved = true
            dragDrawCurrent = documentPoint
            updateDragPreviewLayer()
            onDragDrawChanged?(start, documentPoint)
        case .ended, .cancelled:
            finishSnapInteraction()
            let lastPreview = dragDrawHasMoved ? dragDrawCurrent : nil
            dragDrawHasMoved = false
            guard let start = dragDrawStart else { return }
            let end = pencilLiftEndPoint(
                proposed: documentPoint,
                lastPreview: lastPreview,
                scale: document.viewport.scale
            )
            if hypot(end.x - start.x, end.y - start.y) <= 0.001 {
                onDragDrawEnded?(start, end)
                dragDrawStart = nil
                dragDrawCurrent = nil
                removeDragPreview()
                return
            }
            dragDrawCurrent = end
            onDragDrawEnded?(start, end)
            dragDrawStart = nil
            dragDrawCurrent = nil
            removeDragPreview()
            DispatchQueue.main.async { [weak self] in
                self?.reloadStrokes()
            }
        default:
            break
        }
    }

    private func snappedDragPoint(_ point: CGPoint, referenceStart: CGPoint? = nil) -> CGPoint {
        snapDrawingEndpoint(
            point,
            origin: referenceStart,
            applyAngleSnap: shouldAngleSnapDrawnSegment,
            grid: document.grid,
            settings: document.settings,
            gridSnapEnabled: shouldGridSnapDrawnPoint,
            scale: document.viewport.scale,
            allowedAxes: document.enabledDrawingAxes,
            objectSnap: { query, alignmentOrigin, alignmentThrough in
                resolveObjectSnap(
                    rawPoint: query,
                    alignmentOrigin: alignmentOrigin,
                    alignmentThrough: alignmentThrough
                )
            }
        )
    }

    /// Curve anchors follow the pencil. Object snap still applies. Lines, circles,
    /// and rectangles keep the grid lattice.
    private var shouldGridSnapDrawnPoint: Bool {
        guard activeCategory != .curve else { return false }
        return document.snapEnabled && document.grid.snapEnabled
    }

    /// Polar tracking applies to straight segments (line / construction / curve), not arcs
    /// or 2-axis shapes whose opposite corner should stay free.
    private var shouldAngleSnapDrawnSegment: Bool {
        !document.enabledDrawingAxes.isEmpty && activeCategory == .line && lineVariant != .arc
    }

    /// Runs the snapping engine for a live pencil position, updates the visual indicator and
    /// haptics, and returns the locked point (or `nil` when nothing is snapped).
    ///
    /// Thresholds are defined in view points and converted to document units here so the feel
    /// stays constant across zoom levels.
    private func resolveObjectSnap(
        rawPoint: CGPoint,
        alignmentOrigin: CGPoint? = nil,
        alignmentThrough: CGPoint? = nil
    ) -> CGPoint? {
        let enabledKinds = document.enabledSnapKinds
        guard !enabledKinds.isEmpty else {
            finishSnapInteraction()
            return nil
        }

        let scale = max(document.viewport.scale, 0.0001)
        let alignmentTolerance = alignmentOrigin == nil ? 0 : 4 / scale
        let endpointRadius = shouldAngleSnapDrawnSegment
            ? SnapTuning.lineEndpointSnapRadiusPoints / scale
            : nil
        let update = snapSession.update(
            rawPoint: rawPoint,
            engine: snapEngine,
            strokes: document.interactiveStrokes(),
            enabledKinds: enabledKinds,
            snapRadius: SnapTuning.snapRadiusPoints / scale,
            breakawayRadius: SnapTuning.breakawayRadiusPoints / scale,
            breakawayVelocity: SnapTuning.breakawayVelocityPoints / scale,
            alignmentOrigin: alignmentOrigin,
            alignmentThrough: alignmentThrough,
            alignmentTolerance: alignmentTolerance,
            endpointRadius: endpointRadius
        )

        if let candidate = update.candidate {
            snapIndicator.update(
                kind: candidate.kind,
                viewPoint: document.viewport.documentToView(candidate.point),
                in: layer
            )
            if update.didLock {
                snapHaptics.play()
            }
            return candidate.point
        }

        snapIndicator.update(kind: nil, viewPoint: nil, in: layer)
        return nil
    }

    /// Clears snap lock state and hides the indicator. Call when a snap-capable gesture ends.
    private func finishSnapInteraction() {
        snapSession.reset()
        snapIndicator.clear()
    }

    private func dragStartPoint(for point: CGPoint) -> CGPoint {
        if activeCategory == .circle, circleVariant == .center {
            return snappedCircleCenter(from: point)
        }
        return point
    }

    /// Snap a new circle's center to an existing circle center when starting a concentric ring.
    /// Only geometry on the active layer is considered so other layers stay independent.
    private func snappedCircleCenter(from point: CGPoint) -> CGPoint {
        let tolerance = document.grid.visualSpacing(for: document.settings) * 0.5
        for stroke in document.interactiveStrokes().reversed() {
            guard stroke.shapeType == .circle,
                  stroke.isClosed,
                  let circle = ShapeGeometry.circleFromCardinalPoints(stroke.points) else { continue }
            if hypot(point.x - circle.center.x, point.y - circle.center.y) <= tolerance {
                return circle.center
            }
        }
        return point
    }

    // MARK: - Curve building

    private func handleCurveDrag(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            guard gesture.numberOfTouches == 1 else { return }
        default:
            break
        }

        let rawPoint = document.viewport.viewToDocument(drawingViewPoint(from: gesture))
        let documentPoint = snappedDragPoint(rawPoint, referenceStart: curveDragStart)

        switch gesture.state {
        case .began:
            snapHaptics.prepare()
            curveDragStart = documentPoint
            curveDragCurrent = documentPoint
            curveDraft?.beginDrag()
            updateCurvePreview()
        case .changed:
            curveDragCurrent = documentPoint
            updateCurvePreview()
        case .ended:
            if let start = curveDragStart {
                appendCurveLine(start: start, end: documentPoint)
            }
            clearInProgressCurveDrag()
            updateCurvePreview()
        case .cancelled, .failed:
            curveDraft?.endDrag()
            clearInProgressCurveDrag()
            updateCurvePreview()
        default:
            break
        }
    }

    private func appendCurveLine(start: CGPoint, end: CGPoint) {
        curveDraft?.appendSegment(start: start, end: end, connectTolerance: curveConnectTolerance)
    }

    @discardableResult
    func undoLastCurveSegment() -> Bool {
        if curveDragStart != nil {
            curveDraft?.endDrag()
            clearInProgressCurveDrag()
            updateCurvePreview()
            return true
        }
        guard curveDraft?.undoCommittedSegment() == true else { return false }
        updateCurvePreview()
        return true
    }

    @discardableResult
    func redoLastCurveSegment() -> Bool {
        guard curveDragStart == nil else { return false }
        guard curveDraft?.redoCommittedSegment() == true else { return false }
        updateCurvePreview()
        return true
    }

    @objc private func handleCurveFinish(_ gesture: UITapGestureRecognizer) {
        guard activeCategory == .curve else { return }
        commitCurve()
    }

    private func commitCurve() {
        let finish = curveDraft?.makeFinish()
        resetCurve()
        guard let finish else { return }
        onCurveCommitted?(finish)
    }

    func refreshCurvePreview() {
        updateCurvePreview()
    }

    private func resetCurve() {
        curveDraft?.reset()
        clearInProgressCurveDrag()
        updateCurvePreview()
    }

    private func clearInProgressCurveDrag() {
        curveDragStart = nil
        curveDragCurrent = nil
        finishSnapInteraction()
    }

    private var curveAnchors: [CGPoint] {
        curveDraft?.anchors ?? []
    }

    private var curveConnectTolerance: CGFloat {
        document.grid.visualSpacing(for: document.settings) * 0.5
    }

    private func previewCurveAnchors() -> [CGPoint] {
        var anchors = curveAnchors
        guard let current = curveDragCurrent, let start = curveDragStart else { return anchors }
        if anchors.isEmpty {
            anchors.append(start)
        } else if let last = anchors.last,
                  hypot(start.x - last.x, start.y - last.y) > curveConnectTolerance {
            anchors.append(start)
        }
        anchors.append(current)
        return anchors
    }

    private func updateCurvePreview() {
        curveAnchorLayers.forEach { $0.removeFromSuperlayer() }
        curveAnchorLayers.removeAll()
        defer { applyContinuationVisibility() }

        let anchors = previewCurveAnchors()

        guard !anchors.isEmpty else {
            curvePreviewLayer?.removeFromSuperlayer()
            curvePreviewLayer = nil
            return
        }

        let previewStyle = continuationPreviewStyle()
        let pointRadius = CanvasOverlayGeometry.anchorScreenLength(
            base: 8,
            scale: document.viewport.scale,
            strokeWidth: previewStyle.width
        ) / 2
        for point in curveAnchors {
            let dot = CAShapeLayer()
            let viewPoint = document.viewport.documentToView(point)
            dot.path = UIBezierPath(
                ovalIn: CGRect(
                    x: viewPoint.x - pointRadius,
                    y: viewPoint.y - pointRadius,
                    width: pointRadius * 2,
                    height: pointRadius * 2
                )
            ).cgPath
            dot.fillColor = UIColor.systemTeal.cgColor
            dot.zPosition = Self.previewZPosition
            layer.addSublayer(dot)
            curveAnchorLayers.append(dot)
        }

        guard anchors.count >= 2 else {
            curvePreviewLayer?.removeFromSuperlayer()
            curvePreviewLayer = nil
            return
        }

        let pathLayer: CAShapeLayer
        if let existing = curvePreviewLayer {
            pathLayer = existing
        } else {
            let newLayer = CAShapeLayer()
            newLayer.fillColor = UIColor.clear.cgColor
            newLayer.lineCap = .round
            newLayer.lineJoin = .round
            newLayer.zPosition = Self.previewZPosition
            self.layer.addSublayer(newLayer)
            curvePreviewLayer = newLayer
            pathLayer = newLayer
        }
        pathLayer.zPosition = Self.previewZPosition

        let smoothed = previewCurvePoints(anchors)
        pathLayer.path = StrokeRenderer.livePath(
            points: smoothed,
            viewport: document.viewport,
            closed: false
        ).cgPath
        pathLayer.strokeColor = previewStyle.color
        pathLayer.lineWidth = previewLineWidth(previewStyle.width)
        pathLayer.opacity = previewStyle.opacity
    }

    /// Seeded curves keep their stored tangents. A new draft still uses the cardinal spline.
    private func previewCurvePoints(_ anchors: [CGPoint]) -> [CGPoint] {
        guard let handles = curveDraft?.continuation?.originalHandles, anchors.count >= 2 else {
            return ShapeGeometry.smoothCurvePoints(anchors: anchors)
        }
        let merged = ShapeGeometry.continuationHandles(
            originalHandles: handles,
            anchors: anchors,
            closed: false
        )
        return ShapeGeometry.curvePoints(anchors: anchors, handles: merged, closed: false)
    }

    private func continuationPreviewStyle() -> (color: CGColor, width: CGFloat, opacity: Float) {
        let fallbackWidth = document.strokeWidth
        let fallbackOpacity = Float(document.opacity(forLayerID: document.activeLayerID))
        guard let id = curveDraft?.continuationStrokeID,
              let stroke = document.stroke(with: id) else {
            return (document.strokeColor.platformCGColor, fallbackWidth, fallbackOpacity)
        }
        return (
            stroke.strokeColor.platformCGColor,
            stroke.strokeWidth,
            Float(document.opacity(forLayerID: stroke.layerID))
        )
    }

    /// Preview strokes stay at least `minimum` points, and stop thickening once zoom
    /// passes the same cap as the committed strokes.
    private func previewLineWidth(_ strokeWidth: CGFloat, minimum: CGFloat = 2) -> CGFloat {
        max(
            minimum,
            CanvasOverlayGeometry.displayStrokeScreenWidth(
                strokeWidth: strokeWidth,
                scale: document.viewport.scale
            )
        )
    }

    /// The source stroke is hidden while its anchors are in the draft, so it is not drawn twice.
    private func applyContinuationVisibility() {
        let hiddenID = curveDraft?.continuationStrokeID
        for (id, strokeLayer) in strokeLayers {
            let hidden = id == hiddenID
            if strokeLayer.isHidden != hidden {
                strokeLayer.isHidden = hidden
            }
        }
    }

    // MARK: - Command preview

    func refreshCommandPreview() {
        updateCommandPreviewLayer()
    }

    private func updateCommandPreviewLayer() {
        commandPointLayers.forEach { $0.removeFromSuperlayer() }
        commandPointLayers.removeAll()

        let dots = commandControlPoints.isEmpty ? commandPreviewPoints : commandControlPoints
        guard !dots.isEmpty else {
            commandPreviewLayer?.removeFromSuperlayer()
            commandPreviewLayer = nil
            return
        }

        let pointRadius = CanvasOverlayGeometry.anchorScreenLength(
            base: 10,
            scale: document.viewport.scale,
            strokeWidth: document.strokeWidth
        ) / 2
        for point in dots {
            let dot = CAShapeLayer()
            let viewPoint = document.viewport.documentToView(point)
            dot.path = UIBezierPath(
                ovalIn: CGRect(
                    x: viewPoint.x - pointRadius,
                    y: viewPoint.y - pointRadius,
                    width: pointRadius * 2,
                    height: pointRadius * 2
                )
            ).cgPath
            dot.fillColor = UIColor.systemBlue.cgColor
            dot.strokeColor = UIColor.white.cgColor
            dot.lineWidth = 1.5
            dot.zPosition = Self.previewZPosition
            layer.addSublayer(dot)
            commandPointLayers.append(dot)
        }

        guard commandCanFinish, commandPreviewPoints.count >= 2 else {
            commandPreviewLayer?.removeFromSuperlayer()
            commandPreviewLayer = nil
            return
        }

        let pathLayer: CAShapeLayer
        if let existing = commandPreviewLayer {
            pathLayer = existing
        } else {
            let newLayer = CAShapeLayer()
            newLayer.fillColor = UIColor.clear.cgColor
            newLayer.lineCap = .round
            newLayer.lineJoin = .round
            newLayer.zPosition = Self.previewZPosition
            self.layer.addSublayer(newLayer)
            commandPreviewLayer = newLayer
            pathLayer = newLayer
        }

        let strokeColor = document.strokeColor.platformCGColor
        let isClosed = commandPreviewClosed || (
            commandPreviewPoints.count > 2
            && hypot(
                commandPreviewPoints.first!.x - commandPreviewPoints.last!.x,
                commandPreviewPoints.first!.y - commandPreviewPoints.last!.y
            ) < 0.01
        )

        var cornerRadius: CGFloat = 0
        if isClosed,
           FilletPathBuilder.axisAlignedRectangle(from: commandPreviewPoints) != nil,
           document.settings.defaultCornerRadius > 0 {
            cornerRadius = document.settings.defaultCornerRadius
        }

        pathLayer.path = StrokeRenderer.livePath(
            points: commandPreviewPoints,
            viewport: document.viewport,
            closed: isClosed,
            cornerRadius: cornerRadius,
            isConstruction: isConstructionPreview,
            shapeType: previewShapeType
        ).cgPath
        pathLayer.strokeColor = isConstructionPreview
            ? UIColor.systemBlue.withAlphaComponent(0.6).cgColor
            : strokeColor
        pathLayer.fillColor = isClosed && !isConstructionPreview
            ? UIColor.systemGray.withAlphaComponent(0.2).cgColor
            : UIColor.clear.cgColor
        pathLayer.lineWidth = previewLineWidth(document.strokeWidth)
        pathLayer.lineDashPattern = isConstructionPreview ? [10, 6] : nil
        pathLayer.opacity = Float(document.opacity(forLayerID: document.activeLayerID))
    }

    private func updateDragPreviewLayer() {
        guard let start = dragDrawStart, let end = dragDrawCurrent else {
            removeDragPreview()
            return
        }

        if activeCategory == .line, lineVariant == .arc {
            // Sweep preview lives on the command session once center + start are parked.
            if commandControlPoints.count >= 2 {
                removeDragPreview()
                return
            }
            axisLockGlyph.clear()
            updateArcRadiusPreviewLayer(center: start, start: end)
            return
        }

        let previewPoints = dragPreviewPoints(start: start, end: end)
        guard previewPoints.count >= 2 else {
            removeDragPreview()
            return
        }

        let pathLayer: CAShapeLayer
        if let existing = dragPreviewLayer {
            pathLayer = existing
        } else {
            let newLayer = CAShapeLayer()
            newLayer.fillColor = UIColor.clear.cgColor
            newLayer.lineCap = .round
            newLayer.lineJoin = .round
            newLayer.zPosition = Self.previewZPosition
            self.layer.addSublayer(newLayer)
            dragPreviewLayer = newLayer
            pathLayer = newLayer
        }

        let isClosed = activeCategory == .circle || activeCategory == .rectangle
        let isConstruction = activeCategory == .line && isConstructionPreview
        pathLayer.path = StrokeRenderer.livePath(
            points: previewPoints,
            viewport: document.viewport,
            closed: isClosed,
            cornerRadius: 0,
            isConstruction: isConstruction,
            shapeType: dragPreviewShapeType
        ).cgPath
        pathLayer.strokeColor = isConstruction
            ? UIColor.systemBlue.withAlphaComponent(0.6).cgColor
            : document.strokeColor.platformCGColor
        pathLayer.fillColor = isClosed
            ? UIColor.systemGray.withAlphaComponent(0.15).cgColor
            : UIColor.clear.cgColor
        pathLayer.lineWidth = previewLineWidth(document.strokeWidth)
        pathLayer.lineDashPattern = isConstruction ? [10, 6] : nil
        pathLayer.opacity = Float(document.opacity(forLayerID: document.activeLayerID))
        updateAxisLockGlyph(start: start, end: end)
    }

    /// Pink bar beside the stationary end while a straight line is horizontal or vertical.
    /// It sits off the stroke, on the downward side, so the pencil and the line don't cover it.
    /// Cleared with the preview, so the committed stroke has no marker.
    private func updateAxisLockGlyph(start: CGPoint, end: CGPoint) {
        guard activeCategory == .line, lineVariant != .arc else {
            axisLockGlyph.clear()
            return
        }
        let minimum = document.viewport.viewToDocument(distance: 12)
        guard let axis = drawingAxis(from: start, to: end, minimumLength: minimum),
              document.enabledDrawingAxes.contains(axis) else {
            axisLockGlyph.clear()
            return
        }
        axisLockGlyph.update(
            axis: axis,
            viewPoint: axisLockGlyphPoint(start: start, end: end),
            in: layer
        )
    }

    /// View point just off the start, perpendicular to the segment and toward the bottom of the screen.
    private func axisLockGlyphPoint(start: CGPoint, end: CGPoint) -> CGPoint {
        let startView = document.viewport.documentToView(start)
        let endView = document.viewport.documentToView(end)
        let dx = endView.x - startView.x
        let dy = endView.y - startView.y
        let length = hypot(dx, dy)
        guard length > 1 else {
            return CGPoint(x: startView.x, y: startView.y + 16)
        }
        var nx = -dy / length
        var ny = dx / length
        if ny < 0 {
            nx = -nx
            ny = -ny
        }
        let gap: CGFloat = 16
        return CGPoint(x: startView.x + nx * gap, y: startView.y + ny * gap)
    }

    private func removeDragPreview() {
        dragPreviewLayer?.removeFromSuperlayer()
        dragPreviewLayer = nil
        axisLockGlyph.clear()
    }

    /// `trimPreviewPoints` arrive already flattened by `TrimEngine`, so a plain polyline
    /// traces the removed span without re-fitting it through `StrokeRenderer`.
    private func updateTrimPreviewLayer() {
        guard trimPreviewPoints.count >= 2 else {
            performWithoutLayerAnimation {
                trimPreviewLayer?.removeFromSuperlayer()
                trimPreviewLayer = nil
            }
            return
        }

        performWithoutLayerAnimation {
            let pathLayer: CAShapeLayer
            if let existing = trimPreviewLayer {
                pathLayer = existing
            } else {
                let newLayer = CAShapeLayer()
                newLayer.fillColor = UIColor.clear.cgColor
                newLayer.lineCap = .round
                newLayer.lineJoin = .round
                newLayer.zPosition = Self.previewZPosition
                self.layer.addSublayer(newLayer)
                trimPreviewLayer = newLayer
                pathLayer = newLayer
            }

            let viewPoints = trimPreviewPoints.map { document.viewport.documentToView($0) }
            let path = UIBezierPath()
            path.move(to: viewPoints[0])
            for point in viewPoints.dropFirst() {
                path.addLine(to: point)
            }
            pathLayer.path = path.cgPath
            pathLayer.strokeColor = UIColor.systemRed.cgColor
            pathLayer.lineWidth = max(
                3,
                previewLineWidth(trimPreviewStrokeWidth, minimum: 0) + 2
            )
        }
    }

    private func updateArcRadiusPreviewLayer(center: CGPoint, start: CGPoint) {
        let radius = hypot(start.x - center.x, start.y - center.y)
        guard radius > 0.001 else {
            dragPreviewLayer?.removeFromSuperlayer()
            dragPreviewLayer = nil
            return
        }

        let pathLayer: CAShapeLayer
        if let existing = dragPreviewLayer {
            pathLayer = existing
        } else {
            let newLayer = CAShapeLayer()
            newLayer.fillColor = UIColor.clear.cgColor
            newLayer.lineCap = .round
            newLayer.lineJoin = .round
            newLayer.zPosition = Self.previewZPosition
            self.layer.addSublayer(newLayer)
            dragPreviewLayer = newLayer
            pathLayer = newLayer
        }

        let path = UIBezierPath()
        path.append(
            StrokeRenderer.livePath(
                points: ShapeGeometry.circleCardinalPoints(center: center, radius: radius),
                viewport: document.viewport,
                closed: true,
                shapeType: .circle
            )
        )
        path.append(
            StrokeRenderer.livePath(
                points: [center, start],
                viewport: document.viewport,
                closed: false
            )
        )
        pathLayer.path = path.cgPath
        pathLayer.strokeColor = document.strokeColor.platformCGColor
        pathLayer.fillColor = UIColor.systemGray.withAlphaComponent(0.15).cgColor
        pathLayer.lineWidth = previewLineWidth(document.strokeWidth)
        pathLayer.lineDashPattern = nil
        pathLayer.opacity = Float(document.opacity(forLayerID: document.activeLayerID))
    }

    private func dragPreviewPoints(start: CGPoint, end: CGPoint) -> [CGPoint] {
        switch activeCategory {
        case .line:
            return [start, end]
        case .circle:
            switch circleVariant {
            case .center:
                let radius = hypot(end.x - start.x, end.y - start.y)
                return ShapeGeometry.circleCardinalPoints(center: start, radius: radius)
            case .edge:
                let center = CGPoint(
                    x: (start.x + end.x) / 2,
                    y: (start.y + end.y) / 2
                )
                let radius = hypot(end.x - start.x, end.y - start.y) / 2
                return ShapeGeometry.circleCardinalPoints(center: center, radius: radius)
            case .ellipse:
                let rx = max(0.001, abs(end.x - start.x))
                let ry = max(0.001, abs(end.y - start.y))
                return ShapeGeometry.ellipseCardinalPoints(center: start, rx: rx, ry: ry)
            }
        case .rectangle:
            switch rectangleVariant {
            case .center:
                let halfW = max(0.001, abs(end.x - start.x))
                let halfH = max(0.001, abs(end.y - start.y))
                return ShapeGeometry.rectangleFromCenterDistances(start, halfWidth: halfW, halfHeight: halfH)
            default:
                return ShapeGeometry.rectangleFromCorners(start, end)
            }
        default:
            return [start, end]
        }
    }

    private var dragPreviewShapeType: StrokeShapeType? {
        switch activeCategory {
        case .circle:
            switch circleVariant {
            case .ellipse: return .ellipse
            default: return .circle
            }
        case .rectangle:
            return .rectangle
        default:
            return nil
        }
    }

    private var previewShapeType: StrokeShapeType? {
        dragPreviewShapeType
    }

    private func clampViewportToCanvasExtent() {
        applyViewportIfNeeded {
            $0.clampToCanvasSize(
                in: bounds.size,
                canvasSize: document.settings.canvasSize
            )
        }
    }

    private func shouldAcceptDrawingTouch(_ touch: UITouch) -> Bool {
        if touch.type == .pencil || touch.type == .stylus { return true }
        guard !document.settings.allowsFingerDrawing else { return true }
        return false
    }

    /// Pencil tip in this view. Falls back to the recognizer centroid for finger input.
    private func drawingViewPoint(from gesture: UIGestureRecognizer) -> CGPoint {
        if let pan = gesture as? PrecisePanGestureRecognizer {
            return pan.drawingViewPoint(fallbackIn: self)
        }
        if let tap = gesture as? PreciseTapGestureRecognizer {
            return tap.drawingViewPoint(fallbackIn: self)
        }
        return gesture.location(in: self)
    }
}

extension DrawingCanvasUIView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer,
           (gestureRecognizer as? UIPanGestureRecognizer)?.maximumNumberOfTouches == 1 {
            return allowsDragDraw
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer,
           pan.maximumNumberOfTouches == 1 {
            // Drag-draw recognizer: respect finger drawing toggle, always allow pencil.
            return shouldAcceptDrawingTouch(touch)
        }

        if let tap = gestureRecognizer as? UITapGestureRecognizer {
            if tap.numberOfTouchesRequired == 2 {
                // Finger undo stays available even when finger drawing is off.
                return true
            }
            if tap.numberOfTapsRequired == 2 {
                // Double-tap recognizer only finishes curves; inert elsewhere.
                // Accept a finger double-tap too so the curve can always be finished,
                // even when finger drawing is off and the curve was drawn with a Pencil.
                return activeCategory == .curve
            }
            if activeCategory == .curve {
                // Curve points come from Pencil drags; a single tap still needs to
                // reach the editor so tapping empty canvas can dismiss the tool.
                return true
            }
            switch activeCategory {
            case .line, .circle, .rectangle, .trim, .delete, .addAnchor, .copy, .scale, .fillet, .pattern, .dimensions:
                // Always accept finger taps so they keep working when "finger drawing"
                // is off, including tap-empty-to-dismiss.
                return true
            default:
                break
            }
        }

        return true
    }
}
