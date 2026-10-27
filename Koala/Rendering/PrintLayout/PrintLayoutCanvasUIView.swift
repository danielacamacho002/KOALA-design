//
//  PrintLayoutCanvasUIView.swift
//  Koala
//

import SwiftUI
import UIKit

final class PrintLayoutCanvasUIView: UIView {
    var document: KoalaDocument {
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
    private var marginGuideLayer: CAShapeLayer?

    private var lastLaidOutSize: CGSize = .zero

    init(document: KoalaDocument) {
        self.document = document
        super.init(frame: .zero)
        backgroundColor = UIColor(Color(hex: AppearanceSettings.pasteboardHex))
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
        let newSize = bounds.size
        let sizeChanged = lastLaidOutSize.width == 0
            || abs(newSize.width - lastLaidOutSize.width) > 0.5
            || abs(newSize.height - lastLaidOutSize.height) > 0.5

        performWithoutLayerAnimation {
            if sizeChanged, lastLaidOutSize.width > 0, lastLaidOutSize.height > 0 {
                var viewport = document.viewport
                viewport.preserveCenter(from: lastLaidOutSize, to: newSize)
                if viewport != document.viewport {
                    document.viewport = viewport
                }
            }
            sheetsLayer.frame = bounds
            artworkLayer.frame = bounds
            overlayLayer.frame = bounds
            if sizeChanged {
                reloadAllContents()
            }
        }

        if sizeChanged {
            lastLaidOutSize = newSize
        }
    }

    func reloadAll() {
        performWithoutLayerAnimation {
            reloadAllContents()
        }
    }

    func refreshViewport() {
        performWithoutLayerAnimation {
            reloadAllContents()
        }
    }

    private func reloadAllContents() {
        reloadSheets()
        reloadStrokes()
        reloadTextElements()
        reloadDimOverlay()
        reloadMarginGuide()
        reloadBorders()
    }

    private func performWithoutLayerAnimation(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    // MARK: - Rendering

    private func reloadSheets() {
        let sheets = PrintPageGridEngine.sheets(for: document.printLayout)
        let needed = sheets.count * 2
        while sheetLayers.count > needed {
            sheetLayers.removeLast().removeFromSuperlayer()
        }

        for (index, sheet) in sheets.enumerated() {
            let viewOrigin = document.viewport.documentToView(sheet.frame.origin)
            let viewSize = CGSize(
                width: document.viewport.documentToView(distance: sheet.frame.width),
                height: document.viewport.documentToView(distance: sheet.frame.height)
            )
            let sheetViewFrame = CGRect(origin: viewOrigin, size: viewSize)
            let paperIndex = index * 2
            let labelIndex = paperIndex + 1

            let paper: CALayer
            if paperIndex < sheetLayers.count {
                paper = sheetLayers[paperIndex]
            } else {
                paper = makePaperLayer()
                sheetsLayer.addSublayer(paper)
                sheetLayers.append(paper)
            }
            paper.frame = sheetViewFrame

            let label: CATextLayer
            if labelIndex < sheetLayers.count, let existing = sheetLayers[labelIndex] as? CATextLayer {
                label = existing
            } else {
                label = makePageNumberLayer(number: sheet.id + 1, sheetViewFrame: sheetViewFrame)
                sheetsLayer.addSublayer(label)
                sheetLayers.append(label)
            }
            label.string = "\(sheet.id + 1)"
            label.frame = pageNumberFrame(in: sheetViewFrame)
        }
    }

    private func makePaperLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.borderColor = UIColor.systemGray2.cgColor
        layer.borderWidth = 1
        return layer
    }

    private func pageNumberFrame(in sheetViewFrame: CGRect) -> CGRect {
        let width: CGFloat = 44
        let height: CGFloat = 16
        let inset: CGFloat = 8
        return CGRect(
            x: sheetViewFrame.maxX - width - inset,
            y: sheetViewFrame.maxY - height - inset,
            width: width,
            height: height
        )
    }

    private func makePageNumberLayer(number: Int, sheetViewFrame: CGRect) -> CATextLayer {
        let label = CATextLayer()
        label.string = "\(number)"
        label.fontSize = 12
        label.foregroundColor = UIColor.secondaryLabel.cgColor
        label.alignmentMode = .right
        label.truncationMode = .none
        label.contentsScale = DisplayZoomCompensation.layerContentsScale
        label.frame = pageNumberFrame(in: sheetViewFrame)
        return label
    }

    /// Content stacks by document-layer index so a front layer stays in front of
    /// strokes and text on layers behind it.
    private func layerZPositions() -> [UUID: CGFloat] {
        Dictionary(uniqueKeysWithValues: document.layers.enumerated().map { ($1.id, CGFloat($0 + 1)) })
    }

    private func reloadStrokes() {
        let printStrokes = document.printLayoutStrokes()
        let visibleIDs = Set(printStrokes.map(\.id))
        let zPositions = layerZPositions()
        for (id, layer) in strokeLayers where !visibleIDs.contains(id) {
            layer.removeFromSuperlayer()
            strokeLayers.removeValue(forKey: id)
        }

        for stroke in printStrokes {
            let transform = document.effectivePrintTransform(for: stroke.id)
            let transformed = document.transformedPrintStroke(stroke)
            let cutOpacity = PrintBorderRenderer.strokeOpacity(
                for: transformed,
                settings: document.printLayout
            )
            let isSelected = document.printSelectedStrokeIDs.contains(stroke.id)
            let opacity = document.opacity(forLayerID: stroke.layerID) * (isSelected ? 1 : cutOpacity)

            if let layer = strokeLayers[stroke.id] {
                StrokeRenderer.updateShapeLayer(
                    layer,
                    stroke: stroke,
                    viewport: document.viewport,
                    pointTransform: transform,
                    opacity: opacity
                )
            } else {
                let layer = StrokeRenderer.makeShapeLayer(
                    for: stroke,
                    viewport: document.viewport,
                    pointTransform: transform,
                    opacity: opacity
                )
                artworkLayer.addSublayer(layer)
                strokeLayers[stroke.id] = layer
            }
            strokeLayers[stroke.id]?.zPosition = zPositions[stroke.layerID] ?? 1
        }
    }

    /// Renders text elements as filled vector glyph outlines on the print grid,
    /// so text is treated as a shape like strokes. Each element applies its own
    /// print transform (which includes the global artwork `contentOffset`).
    private func reloadTextElements() {
        let visibleIDs = Set(document.visibleTextElements().map(\.id))
        let zPositions = layerZPositions()
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

            let isSelected = document.printSelectedTextIDs.contains(element.id)
            let cutOpacity = isSelected ? 1 : textOpacity(for: element, transform: printTransform)
            let opacity = document.opacity(forLayerID: element.layerID) * cutOpacity
            let lineWidth = document.viewport.documentToView(distance: element.strokeWidth)

            if let layer = textLayers[element.id] {
                layer.path = viewPath
                applyTextStyle(to: layer, element: element, lineWidth: lineWidth)
                layer.opacity = Float(opacity)
            } else {
                let layer = CAShapeLayer()
                layer.fillRule = .nonZero
                layer.lineJoin = .round
                layer.lineCap = .round
                layer.path = viewPath
                applyTextStyle(to: layer, element: element, lineWidth: lineWidth)
                layer.opacity = Float(opacity)
                artworkLayer.addSublayer(layer)
                textLayers[element.id] = layer
            }
            textLayers[element.id]?.zPosition = zPositions[element.layerID] ?? 1
        }
    }

    /// Applies fill vs. outline (stroke-only) styling to a text layer.
    private func applyTextStyle(to layer: CAShapeLayer, element: TextElement, lineWidth: CGFloat) {
        if element.isOutline {
            layer.fillColor = nil
            layer.strokeColor = element.strokeCGColor
            layer.lineWidth = lineWidth
        } else {
            layer.fillColor = element.cgColor
            layer.strokeColor = nil
        }
    }

    /// Mirrors `PrintBorderRenderer.strokeOpacity`: dims text whose transformed
    /// corners fall outside every printable area.
    private func textOpacity(for element: TextElement, transform: PrintStrokeTransform) -> CGFloat {
        guard document.printLayout.activeTool == .cut else { return 1 }
        let corners = PrintLayoutCoordinateSpace.transformedTextCorners(element, transform: transform)
        let hasUnprintablePoint = corners.contains {
            !PrintBorderRenderer.isPointInsideAnyPrintableArea($0, settings: document.printLayout)
        }
        return hasUnprintablePoint ? 0.3 : 1
    }

    private func reloadBorders() {
        borderLayer?.removeFromSuperlayer()
        borderLayer = nil
        // The red dashed border is a temporary trim guide shown while cutting.
        guard document.printLayout.activeTool == .cut else { return }

        let layer = PrintBorderRenderer.makeBorderLayer(
            settings: document.printLayout,
            viewport: document.viewport
        )
        overlayLayer.addSublayer(layer)
        borderLayer = layer
    }

    private func reloadMarginGuide() {
        marginGuideLayer?.removeFromSuperlayer()
        marginGuideLayer = nil
        guard let layer = PrintBorderRenderer.makeMarginGuideLayer(
            style: document.printLayout.marginMode.printedStyle,
            settings: document.printLayout,
            viewport: document.viewport
        ) else { return }
        overlayLayer.addSublayer(layer)
        marginGuideLayer = layer
    }

    private func reloadDimOverlay() {
        dimOverlayLayer?.removeFromSuperlayer()
        dimOverlayLayer = nil
        // Red margin shading is only a cutting aid, not shown for display/print modes.
        guard document.printLayout.activeTool == .cut else { return }

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
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let viewPoint = gesture.location(in: self)
        onCanvasTap?(viewPoint)
    }
}
