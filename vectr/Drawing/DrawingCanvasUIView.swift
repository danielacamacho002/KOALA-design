//
//  DrawingCanvasUIView.swift
//  vectr
//

import UIKit

protocol DrawingCanvasDelegate: AnyObject {
    func canvasDidUpdate(document: VectrDocument)
    func canvasDidSelectStroke(_ stroke: VectorStroke?)
}

final class DrawingCanvasUIView: UIView {
    weak var delegate: DrawingCanvasDelegate?

    var document: VectrDocument {
        didSet { reloadStrokes(); reloadReferenceImage(); setNeedsDisplay() }
    }

    var isCommandMode = false
    var activeCategory: ToolCategory = .line
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
    var onDragDrawBegan: ((CGPoint) -> Void)?
    var onDragDrawChanged: ((CGPoint, CGPoint) -> Void)?
    var onDragDrawEnded: ((CGPoint, CGPoint) -> Void)?

    private var strokeLayers: [UUID: CAShapeLayer] = [:]
    private var commandPreviewLayer: CAShapeLayer?
    private var dragPreviewLayer: CAShapeLayer?
    private var commandPointLayers: [CAShapeLayer] = []
    private var isPanning = false
    private var lastPanLocation: CGPoint?
    private var pinchStartScale: CGFloat = 1
    private var pinchAnchor: CGPoint = .zero
    private var dragDrawStart: CGPoint?
    private var dragDrawCurrent: CGPoint?
    private let gridLayer = CALayer()
    private var referenceImageLayer: CALayer?
    private var cachedReferenceImageData: Data?
    private var cachedReferenceImage: UIImage?

    init(document: VectrDocument) {
        self.document = document
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        isMultipleTouchEnabled = true
        layer.addSublayer(gridLayer)
        setupGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gridLayer.frame = bounds
        clampViewportToCanvasExtent()
        reloadStrokes()
        reloadReferenceImage()
        refreshCommandPreview()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        GridRenderer.drawGrid(
            in: context,
            bounds: bounds,
            viewport: document.viewport,
            grid: document.grid,
            documentSettings: document.settings,
            canvasExtent: document.settings.canvasExtent
        )
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
        let stroke = document.selectStroke(near: documentPoint, threshold: threshold)
        delegate?.canvasDidSelectStroke(stroke)
        reloadStrokesHighlight()
    }

    // MARK: - Stroke layers

    func reloadStrokes() {
        let visible = document.visibleStrokes()
        let visibleIDs = Set(visible.map(\.id))

        let staleIDs = strokeLayers.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            strokeLayers[id]?.removeFromSuperlayer()
            strokeLayers.removeValue(forKey: id)
        }

        for stroke in visible {
            if let existing = strokeLayers[stroke.id] {
                StrokeRenderer.updateShapeLayer(existing, stroke: stroke, viewport: document.viewport)
            } else {
                addStrokeLayer(stroke)
            }
        }
        reloadStrokesHighlight()
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
        let shapeLayer = StrokeRenderer.makeShapeLayer(for: stroke, viewport: document.viewport)
        layer.addSublayer(shapeLayer)
        strokeLayers[stroke.id] = shapeLayer
    }

    private func reloadStrokesHighlight() {
        for (id, layer) in strokeLayers {
            layer.opacity = id == document.selectedStrokeID ? 1 : 0.85
        }
    }

    func refreshStrokeHighlight() {
        reloadStrokesHighlight()
    }

    func refreshViewport() {
        for (id, layer) in strokeLayers {
            if let stroke = document.stroke(with: id) {
                StrokeRenderer.updateShapeLayer(layer, stroke: stroke, viewport: document.viewport)
            }
        }
        reloadReferenceImage()
        updateCommandPreviewLayer()
        updateDragPreviewLayer()
        setNeedsDisplay()
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.require(toFail: twoFingerPan)
        addGestureRecognizer(tap)

        let dragDraw = UIPanGestureRecognizer(target: self, action: #selector(handleDragDraw(_:)))
        dragDraw.maximumNumberOfTouches = 1
        dragDraw.delegate = self
        addGestureRecognizer(dragDraw)
        tap.require(toFail: dragDraw)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
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

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let viewPoint = gesture.location(in: self)
        let documentPoint = document.viewport.viewToDocument(viewPoint)

        switch activeCategory {
        case .line, .circle, .rectangle:
            if isCommandMode {
                onCanvasTap?(documentPoint)
            }
        case .trim, .delete:
            onCanvasTap?(documentPoint)
        default:
            handleSelection(at: viewPoint)
        }
    }

    @objc private func handleDragDraw(_ gesture: UIPanGestureRecognizer) {
        guard allowsDragDraw else { return }
        switch gesture.state {
        case .began, .changed:
            guard gesture.numberOfTouches == 1 else { return }
        default:
            break
        }

        let viewPoint = gesture.location(in: self)
        let rawPoint = document.viewport.viewToDocument(viewPoint)
        let documentPoint = snappedDragPoint(rawPoint)

        switch gesture.state {
        case .began:
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

    private func snappedDragPoint(_ point: CGPoint) -> CGPoint {
        let enabled = document.snapEnabled && document.grid.snapEnabled
        return snapDrawingPoint(
            point,
            grid: document.grid,
            settings: document.settings,
            enabled: enabled
        )
    }

    private func dragStartPoint(for point: CGPoint) -> CGPoint {
        if activeCategory == .circle, circleVariant == .center {
            return snappedCircleCenter(from: point)
        }
        return point
    }

    /// Snap a new circle's center to an existing circle center when starting a concentric ring.
    private func snappedCircleCenter(from point: CGPoint) -> CGPoint {
        let tolerance = document.grid.visualSpacing(for: document.settings) * 0.5
        for stroke in document.strokes.reversed() {
            guard stroke.shapeType == .circle,
                  stroke.isClosed,
                  let circle = ShapeGeometry.circleFromCardinalPoints(stroke.points) else { continue }
            if hypot(point.x - circle.center.x, point.y - circle.center.y) <= tolerance {
                return circle.center
            }
        }
        return point
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
            case .ellipse:
                let rx = max(0.001, abs(end.x - start.x))
                let ry = max(0.001, abs(end.y - start.y))
                return ShapeGeometry.ellipseCardinalPoints(center: start, rx: rx, ry: ry)
            default:
                return [start, end]
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
        document.viewport.clampToCanvasExtent(
            in: bounds.size,
            canvasExtent: document.settings.canvasExtent
        )
    }

    private func handleNavigationEnded() {
        isPanning = false
        lastPanLocation = nil
    }

    private func shouldAcceptDrawingTouch(_ touch: UITouch) -> Bool {
        if touch.type == .pencil { return true }
        guard !document.settings.allowsFingerDrawing else { return true }
        return false
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

        if gestureRecognizer is UITapGestureRecognizer,
           activeCategory.isDrawingTool,
           isCommandMode {
            // Tap-to-place drawing points: respect finger drawing toggle, always allow pencil.
            return shouldAcceptDrawingTouch(touch)
        }

        return true
    }
}
