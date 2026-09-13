//
//  DrawingCanvasUIView.swift
//  vectr
//

import SwiftUI
import UIKit

protocol DrawingCanvasDelegate: AnyObject {
    func canvasDidUpdate(document: VectrDocument)
    func canvasDidSelectStroke(_ stroke: VectorStroke?)
}

final class DrawingCanvasUIView: UIView {
    weak var delegate: DrawingCanvasDelegate?

    var document: VectrDocument {
        didSet {
            performWithoutLayerAnimation {
                reloadStrokes()
                reloadReferenceImage()
                updateGridPresentation(forcePathRebuild: true)
            }
        }
    }

    var isCommandMode = false
    var activeCategory: ToolCategory? {
        didSet {
            if oldValue == .curve, activeCategory != .curve {
                // Don't discard an in-progress curve when leaving the tool: commit it
                // so the drawn strokes persist. Deferred to avoid mutating document
                // state during a SwiftUI view update.
                let anchors = curveDraft?.anchors ?? []
                resetCurve()
                if anchors.count >= 2 {
                    DispatchQueue.main.async { [weak self] in
                        self?.onCurveCommitted?(anchors)
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
    var circleVariant: CircleVariant = .center
    var rectangleVariant: RectangleVariant = .center
    var onCanvasTap: ((CGPoint) -> Void)?
    /// Two-finger tap — same as the toolbar undo button (Procreate-style).
    var onTwoFingerTap: (() -> Void)?
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
    /// Emitted when a curve is finished (double-tap) with its drawn anchor points.
    var onCurveCommitted: (([CGPoint]) -> Void)?
    /// Bounds size and safe-area insets in this view's own coordinate space.
    var onLayoutMetrics: ((CGSize, UIEdgeInsets) -> Void)?

    private var strokeLayers: [UUID: CAShapeLayer] = [:]
    private var textLayers: [UUID: CAShapeLayer] = [:]
    private var commandPreviewLayer: CAShapeLayer?
    private var dragPreviewLayer: CAShapeLayer?
    private var commandPointLayers: [CAShapeLayer] = []
    private var isPanning = false
    private var lastPanLocation: CGPoint?
    private var pinchStartScale: CGFloat = 1
    private var pinchAnchor: CGPoint = .zero
    private var dragDrawStart: CGPoint?
    private var dragDrawCurrent: CGPoint?
    private var curveDragStart: CGPoint?
    private var curveDragCurrent: CGPoint?
    private var curvePreviewLayer: CAShapeLayer?
    private var curveAnchorLayers: [CAShapeLayer] = []
    private let gridLayer = CALayer()
    private let sheetLayer = CALayer()
    private let worldLayer = CALayer()
    private let clipLayer = CALayer()
    private var rankLayers: [CAShapeLayer] = []
    private let axisXLayer = CAShapeLayer()
    private let axisYLayer = CAShapeLayer()
    private let boundaryLayer = CAShapeLayer()
    private var cachedGridCoverage: CGRect = .null
    private var cachedGridSubdiv: Int = -1
    private var cachedGridMajor: CGFloat = -1
    private var cachedCanvasSize: CGSize = .zero
    private var referenceImageLayer: CALayer?
    private var cachedReferenceImageData: Data?
    private var cachedReferenceImage: UIImage?
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

    /// Color of the canvas sheet itself (the area within the canvas bounds). The view's
    /// `backgroundColor` is the surrounding dark pasteboard shown when zoomed out.
    var canvasFillColor: UIColor = UIColor(Color(hex: AppearanceSettings.defaultCanvasHex)) {
        didSet {
            guard canvasFillColor != oldValue else { return }
            sheetLayer.backgroundColor = canvasFillColor.resolvedColor(with: traitCollection).cgColor
        }
    }

    init(document: VectrDocument) {
        self.document = document
        super.init(frame: .zero)
        backgroundColor = UIColor(Color(hex: AppearanceSettings.pasteboardHex))
        isMultipleTouchEnabled = true
        layer.addSublayer(gridLayer)
        setupGridLayers()
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
                    reloadReferenceImage()
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

    // MARK: - Touch navigation

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleNavigationBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPanning {
            handleNavigationMoved(touches)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isPanning {
            handleNavigationEnded()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isPanning = false
        lastPanLocation = nil
    }

    func handleSelection(at viewPoint: CGPoint) {
        let documentPoint = document.viewport.viewToDocument(viewPoint)
        let threshold = document.viewport.viewToDocument(distance: 16)
        let selection = document.selectElement(near: documentPoint, threshold: threshold)
        switch selection {
        case .stroke(let id):
            delegate?.canvasDidSelectStroke(document.stroke(with: id))
        case .text, .none:
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
        }

        for stroke in visible {
            if let existing = strokeLayers[stroke.id] {
                StrokeRenderer.updateShapeLayer(
                    existing,
                    stroke: stroke,
                    viewport: document.viewport,
                    opacity: document.opacity(forLayerID: stroke.layerID)
                )
            } else {
                addStrokeLayer(stroke)
            }
            strokeLayers[stroke.id]?.zPosition = zPositions[stroke.layerID] ?? 1
        }
        reloadStrokesHighlight()
        reloadTextElements()
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
                TextRenderer.update(existing, for: element, viewport: document.viewport, opacity: opacity)
            } else {
                let created = TextRenderer.makeLayer(for: element, viewport: document.viewport, opacity: opacity)
                layer.addSublayer(created)
                textLayers[element.id] = created
            }
            textLayers[element.id]?.zPosition = zPositions[element.layerID] ?? 1
        }
    }

    private func reloadReferenceImage() {
        guard let data = document.referenceImageData else {
            referenceImageLayer?.removeFromSuperlayer()
            referenceImageLayer = nil
            cachedReferenceImageData = nil
            cachedReferenceImage = nil
            return
        }

        if cachedReferenceImageData != data {
            cachedReferenceImageData = data
            cachedReferenceImage = UIImage(data: data)
        }

        guard let image = cachedReferenceImage else {
            referenceImageLayer?.removeFromSuperlayer()
            referenceImageLayer = nil
            return
        }

        let frame = document.referenceImageFrame ?? CGRect(
            x: -image.size.width / 2,
            y: -image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        let viewOrigin = document.viewport.documentToView(frame.origin)
        let viewSize = CGSize(
            width: document.viewport.documentToView(distance: frame.width),
            height: document.viewport.documentToView(distance: frame.height)
        )

        let layer: CALayer
        if let existing = referenceImageLayer {
            layer = existing
        } else {
            let created = CALayer()
            self.layer.insertSublayer(created, above: gridLayer)
            referenceImageLayer = created
            layer = created
        }

        layer.contents = image.cgImage
        layer.frame = CGRect(origin: viewOrigin, size: viewSize)
        layer.opacity = 0.85
    }

    private func addStrokeLayer(_ stroke: VectorStroke) {
        let shapeLayer = StrokeRenderer.makeShapeLayer(
            for: stroke,
            viewport: document.viewport,
            opacity: document.opacity(forLayerID: stroke.layerID)
        )
        layer.addSublayer(shapeLayer)
        strokeLayers[stroke.id] = shapeLayer
    }

    private func reloadStrokesHighlight() {
        for (id, layer) in strokeLayers {
            guard let stroke = document.stroke(with: id) else { continue }
            let base = document.opacity(forLayerID: stroke.layerID)
            layer.opacity = Float(base * (id == document.selectedStrokeID ? 1 : 0.85))
        }
    }

    func refreshStrokeHighlight() {
        reloadStrokesHighlight()
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
        for (id, layer) in strokeLayers {
            if let stroke = document.stroke(with: id) {
                StrokeRenderer.updateShapeLayer(
                    layer,
                    stroke: stroke,
                    viewport: document.viewport,
                    opacity: document.opacity(forLayerID: stroke.layerID)
                )
            }
        }
        reloadStrokesHighlight()
        for (id, layer) in textLayers {
            if let element = document.textElement(with: id) {
                TextRenderer.update(
                    layer,
                    for: element,
                    viewport: document.viewport,
                    opacity: document.opacity(forLayerID: element.layerID)
                )
            }
        }
        reloadReferenceImage()
        updateCommandPreviewLayer()
        updateDragPreviewLayer()
        updateCurvePreview()
        updateGridPresentation()
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
        configureGridShapeLayer(boundaryLayer, color: GridRenderer.boundaryColor, width: GridRenderer.boundaryLineWidth)
        boundaryLayer.lineDashPattern = GridRenderer.boundaryDash as [NSNumber]

        clipLayer.addSublayer(axisXLayer)
        clipLayer.addSublayer(axisYLayer)
        worldLayer.addSublayer(boundaryLayer)
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
        layer.contentsScale = traitCollection.displayScale
    }

    /// Pans and zooms via a world transform. Paths rebuild only when LOD, settings,
    /// or the visible region walk off the cached padded coverage.
    private func updateGridPresentation(forcePathRebuild: Bool = false) {
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
        boundaryLayer.path = paths.boundary
        boundaryLayer.isHidden = paths.boundary == nil

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
        boundaryLayer.lineWidth = GridRenderer.boundaryLineWidth * inv
        boundaryLayer.lineDashPattern = GridRenderer.boundaryDash.map { $0 * inv as NSNumber }
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
        boundaryLayer.strokeColor = GridRenderer.boundaryColor.resolvedColor(with: traitCollection).cgColor
    }

    private func performWithoutLayerAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    /// Avoid writing `document.viewport` when nothing changed — VectrDocument is
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
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = self
        addGestureRecognizer(twoFingerPan)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.delegate = self
        twoFingerTap.require(toFail: pinch)
        twoFingerTap.require(toFail: twoFingerPan)
        addGestureRecognizer(twoFingerTap)

        let tap = PreciseTapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.require(toFail: twoFingerPan)
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

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            cancelViewportAnimation()
            pinchStartScale = document.viewport.scale
            pinchAnchor = gesture.location(in: self)
        case .changed:
            let newScale = pinchStartScale * gesture.scale
            document.viewport.zoom(to: newScale, anchorViewPoint: pinchAnchor)
            clampViewportToCanvasExtent()
            refreshViewport()
            delegate?.canvasDidUpdate(document: document)
        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .began:
            cancelViewportAnimation()
            lastPanLocation = translation
        case .changed:
            let delta = CGPoint(
                x: translation.x - (lastPanLocation?.x ?? 0),
                y: translation.y - (lastPanLocation?.y ?? 0)
            )
            document.viewport.translation.x += delta.x
            document.viewport.translation.y += delta.y
            clampViewportToCanvasExtent()
            lastPanLocation = translation
            refreshViewport()
            delegate?.canvasDidUpdate(document: document)
        case .ended, .cancelled:
            lastPanLocation = nil
        default:
            break
        }
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onTwoFingerTap?()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let viewPoint = drawingViewPoint(from: gesture)
        let documentPoint = document.viewport.viewToDocument(viewPoint)

        switch activeCategory {
        case .line, .circle, .rectangle:
            if isCommandMode {
                onCanvasTap?(documentPoint)
            }
        case .trim, .delete, .addAnchor, .type, .copy, .scale, .fillet, .pattern, .dimensions, .curve:
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
        // Tangent snapping needs the anchored end of the in-progress line, which is
        // `dragDrawStart` once the drag is underway (nil during `.began`).
        let documentPoint = snappedDragPoint(rawPoint, referenceStart: dragDrawStart)

        switch gesture.state {
        case .began:
            snapHaptics.prepare()
            let startPoint = dragStartPoint(for: documentPoint)
            dragDrawStart = startPoint
            dragDrawCurrent = startPoint
            updateDragPreviewLayer()
            onDragDrawBegan?(startPoint)
        case .changed:
            guard let start = dragDrawStart else { return }
            dragDrawCurrent = documentPoint
            updateDragPreviewLayer()
            onDragDrawChanged?(start, documentPoint)
        case .ended, .cancelled:
            finishSnapInteraction()
            guard let start = dragDrawStart else { return }
            let end = documentPoint
            if hypot(end.x - start.x, end.y - start.y) <= 0.001 {
                onDragDrawEnded?(start, end)
                dragDrawStart = nil
                dragDrawCurrent = nil
                dragPreviewLayer?.removeFromSuperlayer()
                dragPreviewLayer = nil
                return
            }
            dragDrawCurrent = end
            onDragDrawEnded?(start, end)
            dragDrawStart = nil
            dragDrawCurrent = nil
            dragPreviewLayer?.removeFromSuperlayer()
            dragPreviewLayer = nil
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
            gridSnapEnabled: document.snapEnabled && document.grid.snapEnabled,
            scale: document.viewport.scale,
            objectSnap: { query, alignmentOrigin, alignmentThrough in
                resolveObjectSnap(
                    rawPoint: query,
                    referenceStart: referenceStart,
                    alignmentOrigin: alignmentOrigin,
                    alignmentThrough: alignmentThrough
                )
            }
        )
    }

    /// Polar tracking applies to straight segments (line / construction / curve), not arcs
    /// or 2-axis shapes whose opposite corner should stay free.
    private var shouldAngleSnapDrawnSegment: Bool {
        activeCategory == .line && lineVariant != .arc
    }

    /// Runs the snapping engine for a live pencil position, updates the visual indicator and
    /// haptics, and returns the locked point (or `nil` when nothing is snapped).
    ///
    /// Thresholds are defined in view points and converted to document units here so the feel
    /// stays constant across zoom levels.
    private func resolveObjectSnap(
        rawPoint: CGPoint,
        referenceStart: CGPoint? = nil,
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
            referenceStarts: referenceStart.map { [$0] } ?? [],
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
        let anchors = curveDraft?.anchors ?? []
        resetCurve()
        guard anchors.count >= 2 else { return }
        onCurveCommitted?(anchors)
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

        let anchors = previewCurveAnchors()

        guard !anchors.isEmpty else {
            curvePreviewLayer?.removeFromSuperlayer()
            curvePreviewLayer = nil
            return
        }

        let pointRadius: CGFloat = 4
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
            dot.fillColor = UIColor.systemBlue.cgColor
            dot.strokeColor = UIColor.white.cgColor
            dot.lineWidth = 1.5
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
            self.layer.addSublayer(newLayer)
            curvePreviewLayer = newLayer
            pathLayer = newLayer
        }

        let smoothed = ShapeGeometry.smoothCurvePoints(anchors: anchors)
        pathLayer.path = StrokeRenderer.livePath(
            points: smoothed,
            viewport: document.viewport,
            closed: false
        ).cgPath
        pathLayer.strokeColor = document.strokeColor.platformCGColor
        pathLayer.lineWidth = max(2, document.viewport.documentToView(distance: document.strokeWidth))
        pathLayer.opacity = Float(document.opacity(forLayerID: document.activeLayerID))
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

        let pointRadius: CGFloat = 5
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
        pathLayer.lineWidth = max(2, document.viewport.documentToView(distance: document.strokeWidth))
        pathLayer.lineDashPattern = isConstructionPreview ? [10, 6] : nil
        pathLayer.opacity = Float(document.opacity(forLayerID: document.activeLayerID))
    }

    private func updateDragPreviewLayer() {
        guard let start = dragDrawStart, let end = dragDrawCurrent else {
            dragPreviewLayer?.removeFromSuperlayer()
            dragPreviewLayer = nil
            return
        }

        let previewPoints = dragPreviewPoints(start: start, end: end)
        guard previewPoints.count >= 2 else {
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
        pathLayer.lineWidth = max(2, document.viewport.documentToView(distance: document.strokeWidth))
        pathLayer.lineDashPattern = isConstruction ? [10, 6] : nil
        pathLayer.opacity = Float(document.opacity(forLayerID: document.activeLayerID))
    }

    private func dragPreviewPoints(start: CGPoint, end: CGPoint) -> [CGPoint] {
        switch activeCategory {
        case .line:
            if lineVariant == .arc {
                return []
            }
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

    private func handleNavigationBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let event, event.allTouches?.count ?? 0 >= 2 {
            isPanning = true
            cancelViewportAnimation()
            if let touch = touches.first {
                lastPanLocation = touch.location(in: self)
            }
        }
    }

    private func handleNavigationMoved(_ touches: Set<UITouch>) {
        guard let touch = touches.first, let last = lastPanLocation else { return }
        let current = touch.location(in: self)
        let delta = CGPoint(x: current.x - last.x, y: current.y - last.y)
        document.viewport.translation.x += delta.x
        document.viewport.translation.y += delta.y
        clampViewportToCanvasExtent()
        lastPanLocation = current
        refreshViewport()
        delegate?.canvasDidUpdate(document: document)
    }

    private func clampViewportToCanvasExtent() {
        applyViewportIfNeeded {
            $0.clampToCanvasSize(
                in: bounds.size,
                canvasSize: document.settings.canvasSize
            )
        }
    }

    private func handleNavigationEnded() {
        isPanning = false
        lastPanLocation = nil
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
            case .line, .circle, .rectangle:
                if isCommandMode {
                    return shouldAcceptDrawingTouch(touch)
                }
            case .trim, .delete, .addAnchor, .copy, .scale, .fillet, .pattern, .dimensions:
                // These tools used to hit-test via SwiftUI overlays (finger-friendly).
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
