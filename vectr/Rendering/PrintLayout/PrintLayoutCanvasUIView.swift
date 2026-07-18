//
//  PrintLayoutCanvasUIView.swift
//  vectr
//

import UIKit

final class PrintLayoutCanvasUIView: UIView {
    var document: VectrDocument {
        didSet { reloadAll() }
    }

    var onCanvasTap: ((CGPoint) -> Void)?

    private let sheetsLayer = CALayer()
    private let artworkLayer = CALayer()
    private let overlayLayer = CALayer()

    private var sheetLayers: [CALayer] = []
    private var borderLayer: CAShapeLayer?

    private var strokeLayers: [UUID: CAShapeLayer] = [:]
    private var textLayers: [UUID: CAShapeLayer] = [:]
    private var dimOverlayLayer: CAShapeLayer?

    private var pinchStartScale: CGFloat = 1
    private var pinchAnchor: CGPoint = .zero

    init(document: VectrDocument) {
        self.document = document
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.92, alpha: 1)
        isMultipleTouchEnabled = true

        layer.addSublayer(sheetsLayer)
        layer.addSublayer(artworkLayer)
        layer.addSublayer(overlayLayer)
        sheetsLayer.frame = bounds
        artworkLayer.frame = bounds
        overlayLayer.frame = bounds

        setupGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        sheetsLayer.frame = bounds
        artworkLayer.frame = bounds
        overlayLayer.frame = bounds
        reloadAll()
    }

    func reloadAll() {
        reloadSheets()
        reloadStrokes()
        reloadTextElements()
        reloadDimOverlay()
        reloadBorders()
    }

    func refreshViewport() {
        reloadSheets()
        reloadStrokes()
        reloadTextElements()
        reloadDimOverlay()
        reloadBorders()
    }

    // MARK: - Rendering

    private func reloadSheets() {
        sheetLayers.forEach { $0.removeFromSuperlayer() }
        sheetLayers.removeAll()

        for sheet in PrintPageGridEngine.sheets(for: document.printLayout) {
            let viewOrigin = document.viewport.documentToView(sheet.frame.origin)
            let viewSize = CGSize(
                width: document.viewport.documentToView(distance: sheet.frame.width),
                height: document.viewport.documentToView(distance: sheet.frame.height)
            )
            let sheetViewFrame = CGRect(origin: viewOrigin, size: viewSize)

            let layer = CALayer()
            layer.backgroundColor = UIColor.white.cgColor
            layer.frame = sheetViewFrame
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.12
            layer.shadowRadius = 4
            layer.shadowOffset = CGSize(width: 0, height: 2)
            // Distinct border so each page reads as an individual sheet of paper.
            layer.borderColor = UIColor.systemGray2.cgColor
            layer.borderWidth = 1
            sheetsLayer.addSublayer(layer)
            sheetLayers.append(layer)

            // Page number in the bottom-right corner of each sheet.
            let label = makePageNumberLayer(number: sheet.id + 1, sheetViewFrame: sheetViewFrame)
            sheetsLayer.addSublayer(label)
            sheetLayers.append(label)
        }
    }

    private func makePageNumberLayer(number: Int, sheetViewFrame: CGRect) -> CATextLayer {
        let width: CGFloat = 44
        let height: CGFloat = 16
        let inset: CGFloat = 8
        let label = CATextLayer()
        label.string = "\(number)"
        label.fontSize = 12
        label.foregroundColor = UIColor.secondaryLabel.cgColor
        label.alignmentMode = .right
        label.truncationMode = .none
        label.contentsScale = UIScreen.main.scale
        label.frame = CGRect(
            x: sheetViewFrame.maxX - width - inset,
            y: sheetViewFrame.maxY - height - inset,
            width: width,
            height: height
        )
        return label
    }

    private func reloadStrokes() {
        let printStrokes = document.printLayoutStrokes()
        let visibleIDs = Set(printStrokes.map(\.id))
        for (id, layer) in strokeLayers where !visibleIDs.contains(id) {
            layer.removeFromSuperlayer()
            strokeLayers.removeValue(forKey: id)
        }

        for stroke in printStrokes {
            let transform = document.effectivePrintTransform(for: stroke.id)
            let transformed = document.transformedPrintStroke(stroke)
            let opacity = PrintBorderRenderer.strokeOpacity(
                for: transformed,
                settings: document.printLayout
            )
            let isSelected = stroke.id == document.printSelectedStrokeID

            if let layer = strokeLayers[stroke.id] {
                StrokeRenderer.updateShapeLayer(
                    layer,
                    stroke: stroke,
                    viewport: document.viewport,
                    pointTransform: transform,
                    opacity: isSelected ? 1 : opacity
                )
            } else {
                let layer = StrokeRenderer.makeShapeLayer(
                    for: stroke,
                    viewport: document.viewport,
                    pointTransform: transform,
                    opacity: isSelected ? 1 : opacity
                )
                artworkLayer.addSublayer(layer)
                strokeLayers[stroke.id] = layer
            }
        }
    }

    /// Renders text elements as filled vector glyph outlines on the print grid,
    /// so text is treated as a shape like strokes. Each element applies its own
    /// print transform (which includes the global artwork `contentOffset`).
    private func reloadTextElements() {
        let visibleIDs = Set(document.visibleTextElements().map(\.id))
        for (id, layer) in textLayers where !visibleIDs.contains(id) {
            layer.removeFromSuperlayer()
            textLayers.removeValue(forKey: id)
        }

        let documentToView = CGAffineTransform(
            a: document.viewport.scale, b: 0, c: 0, d: document.viewport.scale,
            tx: document.viewport.translation.x, ty: document.viewport.translation.y
        )

        for element in document.visibleTextElements() {
            let printTransform = document.effectivePrintTransform(for: element.id)
            var transform = PrintLayoutCoordinateSpace
                .textPrintTransform(for: element, transform: printTransform)
                .concatenating(documentToView)
            let viewPath = TextOutline.path(for: element).copy(using: &transform)

            let isSelected = element.id == document.printSelectedTextID
            let opacity = isSelected ? 1 : textOpacity(for: element, transform: printTransform)

            if let layer = textLayers[element.id] {
                layer.path = viewPath
                layer.fillColor = element.cgColor
                layer.opacity = Float(opacity)
            } else {
                let layer = CAShapeLayer()
                layer.fillRule = .nonZero
                layer.strokeColor = nil
                layer.path = viewPath
                layer.fillColor = element.cgColor
                layer.opacity = Float(opacity)
                artworkLayer.addSublayer(layer)
                textLayers[element.id] = layer
            }
        }
    }

    /// Mirrors `PrintBorderRenderer.strokeOpacity`: dims text whose transformed
    /// corners fall outside every printable area.
    private func textOpacity(for element: TextElement, transform: PrintStrokeTransform) -> CGFloat {
        guard document.printLayout.isPrintBorderVisible else { return 1 }
        let corners = PrintLayoutCoordinateSpace.transformedTextCorners(element, transform: transform)
        let hasUnprintablePoint = corners.contains {
            !PrintBorderRenderer.isPointInsideAnyPrintableArea($0, settings: document.printLayout)
        }
        return hasUnprintablePoint ? 0.3 : 1
    }

    private func reloadBorders() {
        borderLayer?.removeFromSuperlayer()
        borderLayer = nil
        guard document.printLayout.isPrintBorderVisible else { return }

        let layer = PrintBorderRenderer.makeBorderLayer(
            settings: document.printLayout,
            viewport: document.viewport
        )
        overlayLayer.addSublayer(layer)
        borderLayer = layer
    }

    private func reloadDimOverlay() {
        dimOverlayLayer?.removeFromSuperlayer()
        dimOverlayLayer = nil
        guard document.printLayout.isPrintBorderVisible else { return }

        let layer = PrintBorderRenderer.makeDimOverlayLayer(
            settings: document.printLayout,
            viewport: document.viewport
        )
        overlayLayer.insertSublayer(layer, at: 0)
        dimOverlayLayer = layer
    }

    // MARK: - Gestures

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        addGestureRecognizer(twoFingerPan)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let viewPoint = gesture.location(in: self)
        onCanvasTap?(viewPoint)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartScale = document.viewport.scale
            pinchAnchor = gesture.location(in: self)
        case .changed:
            let newScale = pinchStartScale * gesture.scale
            document.viewport.zoom(to: newScale, anchorViewPoint: pinchAnchor)
            refreshViewport()
        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        if gesture.state == .changed {
            document.viewport.translation.x += translation.x
            document.viewport.translation.y += translation.y
            gesture.setTranslation(.zero, in: self)
            refreshViewport()
        }
    }
}
