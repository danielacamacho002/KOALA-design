//
//  VectrDocument.swift
//  vectr
//

import CoreGraphics
import Foundation
import Observation
import SwiftUI

@Observable
final class VectrDocument {
    var layers: [Layer]
    var strokes: [VectorStroke]
    var textElements: [TextElement] = []
    var activeLayerID: UUID
    var viewport: ViewportTransform
    var grid: GridSettings
    var settings: DocumentSettings = DocumentSettings()

    var strokeWidth: CGFloat = 1.5
    var strokeColor: CodableColor = CodableColor(.primary)
    var selectedStrokeID: UUID?
    var snapEnabled: Bool = true
    var dimensionsVisible: Bool = false
    // Document-space offsets of dragged dimension labels, keyed by "<strokeID>:<dimensionID>".
    var dimensionOffsets: [String: CGPoint] = [:]
    var scaleUniform: Bool = true
    var selectedAnchorIndices: Set<Int> = []
    var selectedFilletCornerIndices: Set<Int> = []
    /// When set, move-tool rotation pivots around this anchor index; nil uses shape center.
    var moveRotationPivotAnchorIndex: Int?
    var constraints: ConstraintSettings = ConstraintSettings()
    var activeCategory: ToolCategory = .line
    var lineVariant: LineVariant = .line
    var circleVariant: CircleVariant = .center
    var rectangleVariant: RectangleVariant = .center
    var selectedTextID: UUID?
    var activeFontRef: FontRef = .default
    var activeFontSize: CGFloat = 24
    var referenceImageData: Data?
    var referenceImageFrame: CGRect?

    var printLayout: PrintLayoutSettings = PrintLayoutSettings()
    var printStrokeTransforms: [UUID: PrintStrokeTransform] = [:]
    var registrationMarks: [RegistrationMark] = []
    var printSelectedStrokeID: UUID?
    var printLayoutRevision = 0

    private var undoStack: [DocumentSnapshot] = []
    private var redoStack: [DocumentSnapshot] = []
    private let undoLimit = 50
    /// Bumped when undo/redo stacks change to keep toolbar state in sync.
    var undoRevision = 0

    /// Bumped whenever stroke geometry changes so the canvas can refresh.
    var geometryRevision = 0

    var canUndo: Bool {
        _ = undoRevision
        return !undoStack.isEmpty
    }
    var canRedo: Bool {
        _ = undoRevision
        return !redoStack.isEmpty
    }

    var activeLayer: Layer? {
        layers.first { $0.id == activeLayerID }
    }

    init() {
        let defaultLayer = Layer(name: "Layer 1")
        layers = [defaultLayer]
        strokes = []
        activeLayerID = defaultLayer.id
        viewport = ViewportTransform()
        grid = GridSettings()
        applyNewProjectDefaults()
    }

    init(snapshot: DocumentSnapshot) {
        layers = snapshot.layers
        strokes = snapshot.strokes
        textElements = snapshot.textElements
        activeLayerID = snapshot.activeLayerID
        viewport = snapshot.viewport
        grid = snapshot.grid
        settings = snapshot.settings
        strokeWidth = snapshot.strokeWidth
        strokeColor = snapshot.strokeColor
        selectedStrokeID = snapshot.selectedStrokeID
        referenceImageData = snapshot.referenceImageData
        referenceImageFrame = snapshot.referenceImageFrame
        printLayout = snapshot.printLayout
        printStrokeTransforms = snapshot.printStrokeTransforms
        registrationMarks = snapshot.registrationMarks
        dimensionOffsets = snapshot.dimensionOffsets
        settings.syncCanvasExtentToMaximum()
        syncGridFromSettings()
        refreshRegistrationMarkSuggestions()
    }

    func strokes(for layerID: UUID) -> [VectorStroke] {
        strokes.filter { $0.layerID == layerID }
    }

    /// Strokes on visible layers, ordered back-to-front by layer (index 0 = backmost layer),
    /// stable within a layer by insertion order.
    func visibleStrokes() -> [VectorStroke] {
        let order = layerIndexByID()
        let visibleLayerIDs = Set(layers.filter(\.isVisible).map(\.id))
        return strokes
            .enumerated()
            .filter { visibleLayerIDs.contains($0.element.layerID) }
            .sorted { lhs, rhs in
                let l = order[lhs.element.layerID] ?? 0
                let r = order[rhs.element.layerID] ?? 0
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    /// Visible strokes excluding those on locked layers, for hit-testing/selection.
    func selectableStrokes() -> [VectorStroke] {
        let lockedLayerIDs = Set(layers.filter(\.isLocked).map(\.id))
        guard !lockedLayerIDs.isEmpty else { return visibleStrokes() }
        return visibleStrokes().filter { !lockedLayerIDs.contains($0.layerID) }
    }

    func stroke(with id: UUID) -> VectorStroke? {
        strokes.first { $0.id == id }
    }

    // MARK: - Layers

    private func layerIndexByID() -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: layers.enumerated().map { ($1.id, $0) })
    }

    @discardableResult
    func addLayer() -> Layer {
        pushUndo()
        let layer = Layer(name: nextLayerName())
        layers.append(layer)
        activeLayerID = layer.id
        geometryRevision += 1
        return layer
    }

    private func nextLayerName() -> String {
        let existing = Set(layers.map(\.name))
        var n = layers.count + 1
        while existing.contains("Layer \(n)") { n += 1 }
        return "Layer \(n)"
    }

    /// Deletes a layer along with its strokes and text. The last remaining layer cannot be deleted.
    func deleteLayer(id: UUID) {
        guard layers.count > 1,
              let index = layers.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        layers.remove(at: index)
        strokes.removeAll { $0.layerID == id }
        textElements.removeAll { $0.layerID == id }
        if let selected = selectedStrokeID, stroke(with: selected) == nil {
            selectedStrokeID = nil
        }
        if let selectedText = selectedTextID, textElement(with: selectedText) == nil {
            selectedTextID = nil
        }
        if activeLayerID == id {
            activeLayerID = layers[min(index, layers.count - 1)].id
        }
        geometryRevision += 1
    }

    func renameLayer(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = layers.firstIndex(where: { $0.id == id }),
              layers[index].name != trimmed else { return }
        pushUndo()
        layers[index].name = trimmed
    }

    func toggleLayerVisibility(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        layers[index].isVisible.toggle()
        geometryRevision += 1
    }

    func toggleLayerLock(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        layers[index].isLocked.toggle()
        geometryRevision += 1
    }

    func setActiveLayer(id: UUID) {
        guard activeLayerID != id, layers.contains(where: { $0.id == id }) else { return }
        activeLayerID = id
    }

    /// Replaces the layer stack with a reordered copy of the same layers (index 0 = backmost).
    func reorderLayers(_ newOrder: [Layer]) {
        guard newOrder.map(\.id) != layers.map(\.id),
              Set(newOrder.map(\.id)) == Set(layers.map(\.id)),
              newOrder.count == layers.count else { return }
        pushUndo()
        layers = newOrder
        geometryRevision += 1
    }

    // MARK: - Text Elements

    /// Text elements on visible layers, ordered back-to-front by layer like `visibleStrokes()`.
    func visibleTextElements() -> [TextElement] {
        let order = layerIndexByID()
        let visibleLayerIDs = Set(layers.filter(\.isVisible).map(\.id))
        return textElements
            .enumerated()
            .filter { visibleLayerIDs.contains($0.element.layerID) }
            .sorted { lhs, rhs in
                let l = order[lhs.element.layerID] ?? 0
                let r = order[rhs.element.layerID] ?? 0
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    /// Visible text elements excluding those on locked layers, for hit-testing/selection.
    func selectableTextElements() -> [TextElement] {
        let lockedLayerIDs = Set(layers.filter(\.isLocked).map(\.id))
        guard !lockedLayerIDs.isEmpty else { return visibleTextElements() }
        return visibleTextElements().filter { !lockedLayerIDs.contains($0.layerID) }
    }

    func textElement(with id: UUID) -> TextElement? {
        textElements.first { $0.id == id }
    }

    func addTextElement(_ element: TextElement) {
        pushUndo()
        textElements.append(element)
        geometryRevision += 1
    }

    func updateTextElement(_ element: TextElement, recordUndo: Bool = true) {
        guard let index = textElements.firstIndex(where: { $0.id == element.id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index] = element
        geometryRevision += 1
    }

    func removeTextElement(id: UUID) {
        guard textElements.contains(where: { $0.id == id }) else { return }
        pushUndo()
        textElements.removeAll { $0.id == id }
        if selectedTextID == id {
            selectedTextID = nil
        }
        geometryRevision += 1
    }

    func translateText(id: UUID, delta: CGPoint, recordUndo: Bool = false) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index].position.x += delta.x
        textElements[index].position.y += delta.y
        geometryRevision += 1
    }

    func setTextPosition(id: UUID, position: CGPoint, recordUndo: Bool = false) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index].position = position
        geometryRevision += 1
    }

    func setTextRotation(id: UUID, radians: CGFloat, recordUndo: Bool = false) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index].rotation = radians
        geometryRevision += 1
    }

    func setTextFontSize(id: UUID, size: CGFloat, recordUndo: Bool = false) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index].fontSize = max(1, size)
        geometryRevision += 1
    }

    /// End point of the most recent open line on the given layer, if any.
    func lastOpenLineEndpoint(on layerID: UUID) -> CGPoint? {
        guard let stroke = strokes.last(where: { stroke in
            stroke.layerID == layerID
                && stroke.shapeType == .polyline
                && !stroke.isClosed
                && !stroke.isConstruction
                && stroke.points.count >= 2
        }) else { return nil }
        return stroke.points.last
    }

    func addStroke(_ stroke: VectorStroke) {
        pushUndo()
        strokes.append(ShapeGeometry.captureRotationBaseIfNeeded(stroke))
        reconcileIntersectionAnchors(around: [stroke.id])
        ClosedShapeDetector.reconcile(document: self)
        DonutDetector.reconcile(document: self)
        geometryRevision += 1
    }

    /// Adds a line segment, extending an open polyline when an endpoint connects.
    @discardableResult
    func commitLineSegment(
        start: CGPoint,
        end: CGPoint,
        layerID: UUID,
        strokeWidth: CGFloat,
        strokeColor: CodableColor,
        connectTolerance: CGFloat
    ) -> UUID? {
        guard hypot(end.x - start.x, end.y - start.y) > 0.001 else { return nil }

        func pointsConnect(_ a: CGPoint, _ b: CGPoint) -> Bool {
            hypot(a.x - b.x, a.y - b.y) <= connectTolerance
        }

        func isOpenPolyline(_ stroke: VectorStroke) -> Bool {
            stroke.layerID == layerID
                && stroke.shapeType == .polyline
                && !stroke.isClosed
                && !stroke.isConstruction
                && stroke.points.count >= 2
        }

        func finalizeOpenPolyline(_ stroke: inout VectorStroke) {
            if stroke.points.count >= 3,
               pointsConnect(stroke.points.first!, stroke.points.last!) {
                stroke.isClosed = true
                // Normalize closure to avoid duplicate first/last corner vertices.
                stroke.points.removeLast()
            }
        }

        if let index = strokes.lastIndex(where: { stroke in
            isOpenPolyline(stroke) && pointsConnect(stroke.points.last!, start)
        }) {
            pushUndo()
            var stroke = strokes[index]
            stroke.points.append(end)
            finalizeOpenPolyline(&stroke)
            strokes[index] = stroke
            reconcileIntersectionAnchors(around: [stroke.id])
            geometryRevision += 1
            ClosedShapeDetector.reconcile(document: self)
            return stroke.id
        }

        if let index = strokes.lastIndex(where: { stroke in
            isOpenPolyline(stroke) && pointsConnect(stroke.points.first!, end)
        }) {
            pushUndo()
            var stroke = strokes[index]
            stroke.points.insert(start, at: 0)
            finalizeOpenPolyline(&stroke)
            strokes[index] = stroke
            reconcileIntersectionAnchors(around: [stroke.id])
            geometryRevision += 1
            ClosedShapeDetector.reconcile(document: self)
            return stroke.id
        }

        if let index = strokes.lastIndex(where: { stroke in
            isOpenPolyline(stroke) && pointsConnect(stroke.points.first!, start)
        }) {
            pushUndo()
            var stroke = strokes[index]
            stroke.points.insert(end, at: 1)
            finalizeOpenPolyline(&stroke)
            strokes[index] = stroke
            reconcileIntersectionAnchors(around: [stroke.id])
            geometryRevision += 1
            ClosedShapeDetector.reconcile(document: self)
            return stroke.id
        }

        if let index = strokes.lastIndex(where: { stroke in
            isOpenPolyline(stroke) && pointsConnect(stroke.points.last!, end)
        }) {
            pushUndo()
            var stroke = strokes[index]
            stroke.points.insert(start, at: stroke.points.count - 1)
            finalizeOpenPolyline(&stroke)
            strokes[index] = stroke
            reconcileIntersectionAnchors(around: [stroke.id])
            geometryRevision += 1
            ClosedShapeDetector.reconcile(document: self)
            return stroke.id
        }

        let stroke = VectorStroke(
            layerID: layerID,
            points: [start, end],
            strokeWidth: strokeWidth,
            strokeColor: strokeColor,
            shapeType: .polyline
        )
        addStroke(stroke)
        return stroke.id
    }

    func reconcileClosedShapes() {
        pushUndo()
        ClosedShapeDetector.reconcile(document: self)
    }

    func updateStroke(_ stroke: VectorStroke, recordUndo: Bool = true) {
        guard let index = strokes.firstIndex(where: { $0.id == stroke.id }) else { return }
        if recordUndo { pushUndo() }
        strokes[index] = stroke
        if recordUndo {
            reconcileIntersectionAnchors(around: [stroke.id])
        }
        geometryRevision += 1
    }

    func beginInteractiveEdit() {
        pushUndo()
    }

    static func dimensionOffsetKey(strokeID: UUID, dimensionID: String) -> String {
        "\(strokeID.uuidString):\(dimensionID)"
    }

    func setDimensionOffset(key: String, offset: CGPoint?, recordUndo: Bool = true) {
        if recordUndo { pushUndo() }
        if let offset {
            dimensionOffsets[key] = offset
        } else {
            dimensionOffsets.removeValue(forKey: key)
        }
        geometryRevision += 1
    }

    func translateStroke(id: UUID, delta: CGPoint, recordUndo: Bool = false) {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        strokes[index].points = strokes[index].points.map {
            CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
        }
        if recordUndo {
            reconcileIntersectionAnchors(around: [id])
        }
        geometryRevision += 1
    }

    func setStrokePoints(id: UUID, points: [CGPoint], recordUndo: Bool = false) {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        strokes[index].points = points
        if recordUndo {
            reconcileIntersectionAnchors(around: [id])
        }
        geometryRevision += 1
    }

    func rotateStroke(id: UUID, around pivot: CGPoint, byRadians angle: CGFloat, recordUndo: Bool = false) {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        strokes[index] = ShapeGeometry.rotatedStroke(strokes[index], around: pivot, by: angle)
        if recordUndo {
            reconcileIntersectionAnchors(around: [id])
        }
        geometryRevision += 1
    }

    func setStrokeRotation(
        id: UUID,
        toDegrees degrees: Double,
        pivotAnchorIndex: Int?,
        recordUndo: Bool = false
    ) {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        let stroke = strokes[index]
        guard let pivot = ShapeGeometry.rotationPivot(for: stroke, anchorIndex: pivotAnchorIndex) else { return }
        let target = CGFloat(degrees * .pi / 180)
        if recordUndo { pushUndo() }
        strokes[index] = ShapeGeometry.strokeWithAbsoluteRotation(stroke, radians: target, around: pivot)
        if recordUndo {
            reconcileIntersectionAnchors(around: [id])
        }
        geometryRevision += 1
    }

    func applyFilletToSelected(
        radius: CGFloat? = nil,
        cornerIndices: Set<Int>? = nil,
        recordUndo: Bool = true
    ) {
        guard let id = selectedStrokeID,
              let index = strokes.firstIndex(where: { $0.id == id }) else { return }

        let validCornerIndices = Set(ShapeGeometry.filletCornerIndices(for: strokes[index]))
        guard !validCornerIndices.isEmpty else { return }

        let requestedCorners = cornerIndices?.intersection(validCornerIndices) ?? validCornerIndices
        guard !requestedCorners.isEmpty else { return }

        if recordUndo { pushUndo() }

        let r = max(0, radius ?? settings.defaultCornerRadius)
        var updated = strokes[index]
        var overrides = updated.cornerRadiiByIndex ?? [:]
        for cornerIndex in requestedCorners {
            overrides[cornerIndex] = r
        }
        overrides = overrides.filter { validCornerIndices.contains($0.key) }

        // If every valid corner receives the same value, store it as the global base radius.
        if requestedCorners == validCornerIndices {
            updated.cornerRadius = r
        }

        // Keep only overrides that differ from the global radius. Zero is kept only when needed
        // to override a positive global radius on an individual corner.
        let epsilon: CGFloat = 0.0001
        let pruned = overrides.filter { _, value in
            let clamped = max(0, value)
            if clamped <= epsilon {
                return updated.cornerRadius > epsilon
            }
            return abs(clamped - updated.cornerRadius) > epsilon
        }
        updated.cornerRadiiByIndex = pruned.isEmpty ? nil : pruned

        // If no corner retains any radius, clear the global radius too.
        if updated.resolvedFilletCornerRadii().isEmpty {
            updated.cornerRadius = 0
            updated.cornerRadiiByIndex = nil
        }

        strokes[index] = updated
        geometryRevision += 1
    }

    func deleteStrokePoint(at pointIndex: Int) {
        guard let id = selectedStrokeID,
              let stroke = stroke(with: id),
              let updated = StrokeEditor.deletePoint(stroke, at: pointIndex) else { return }
        pushUndo()
        updateStroke(updated, recordUndo: false)
    }

    func deleteStrokeEdge(at edgeIndex: Int) {
        guard let id = selectedStrokeID,
              let stroke = stroke(with: id),
              let updated = StrokeEditor.deleteEdge(stroke, edgeIndex: edgeIndex) else { return }
        pushUndo()
        updateStroke(updated, recordUndo: false)
    }

    func currentAnchorCount(for stroke: VectorStroke) -> Int {
        AnchorPointEngine.anchorCount(for: stroke)
    }

    @discardableResult
    func insertAnchor(at documentPoint: CGPoint, threshold: CGFloat) -> Bool {
        guard let id = selectedStrokeID,
              let stroke = stroke(with: id),
              AnchorPointEngine.canEditAnchors(on: stroke),
              let updated = AnchorPointEngine.insertAtTap(
                  stroke: stroke,
                  point: documentPoint,
                  threshold: threshold
              ) else { return false }
        pushUndo()
        updateStroke(updated, recordUndo: false)
        return true
    }

    enum AnchorDistributionResult {
        case success
        case noSelection
        case notEligible
        case alreadyHasCount(Int)
        case invalidTarget
    }

    @discardableResult
    func distributeAnchors(toTotal targetCount: Int) -> AnchorDistributionResult {
        guard let stroke = selectedStrokeID.flatMap({ stroke(with: $0) }) else {
            return .noSelection
        }
        guard AnchorPointEngine.canEditAnchors(on: stroke) else {
            return .notEligible
        }
        guard targetCount >= 3 else {
            return .invalidTarget
        }
        // Baking fillets adds permanent anchors, so compare against the post-bake count.
        let bakedStroke = AnchorPointEngine.bakedFilletStroke(for: stroke) ?? stroke
        let current = currentAnchorCount(for: bakedStroke)
        if targetCount <= current {
            return .alreadyHasCount(current)
        }
        guard let updated = AnchorPointEngine.distributeToTotal(stroke: stroke, targetCount: targetCount) else {
            return .invalidTarget
        }
        pushUndo()
        updateStroke(updated, recordUndo: false)
        return .success
    }

    /// Single tap: reset the selection to only this anchor and adopt it as the rotation pivot.
    func selectSingleAnchor(at index: Int) {
        selectedAnchorIndices = [index]
        moveRotationPivotAnchorIndex = index
    }

    /// Long press: multi-select toggle that leaves the other selected anchors untouched.
    func toggleAnchorSelection(at index: Int) {
        if selectedAnchorIndices.contains(index) {
            selectedAnchorIndices.remove(index)
            if moveRotationPivotAnchorIndex == index {
                moveRotationPivotAnchorIndex = nil
            }
        } else {
            selectedAnchorIndices.insert(index)
        }
    }

    /// Tap on empty canvas: drop every anchor selection and reset the pivot to shape center.
    func clearAnchorSelection() {
        selectedAnchorIndices.removeAll()
        moveRotationPivotAnchorIndex = nil
    }

    func toggleFilletCornerSelection(at index: Int) {
        if selectedFilletCornerIndices.contains(index) {
            selectedFilletCornerIndices.remove(index)
        } else {
            selectedFilletCornerIndices.insert(index)
        }
    }

    /// Shared fillet radius of the currently selected corners, for display in the fillet panel.
    enum FilletRadiusSelection: Equatable {
        case none
        case uniform(CGFloat)
        case mixed
    }

    func selectedFilletRadiusSummary() -> FilletRadiusSelection {
        guard let id = selectedStrokeID,
              let stroke = stroke(with: id),
              !selectedFilletCornerIndices.isEmpty else { return .none }

        let resolved = stroke.resolvedFilletCornerRadii()
        var value: CGFloat?
        for index in selectedFilletCornerIndices {
            let radius = max(0, resolved[index] ?? 0)
            if let existing = value {
                if abs(existing - radius) > 0.0001 { return .mixed }
            } else {
                value = radius
            }
        }
        guard let value else { return .none }
        return .uniform(value)
    }

    func clearToolSelections() {
        selectedAnchorIndices.removeAll()
        selectedFilletCornerIndices.removeAll()
        moveRotationPivotAnchorIndex = nil
    }

    func selectTool(
        _ category: ToolCategory,
        lineVariant: LineVariant? = nil,
        circleVariant: CircleVariant? = nil,
        rectangleVariant: RectangleVariant? = nil
    ) {
        activeCategory = category
        if let lineVariant { self.lineVariant = lineVariant }
        if let circleVariant { self.circleVariant = circleVariant }
        if let rectangleVariant { self.rectangleVariant = rectangleVariant }
        if category == .dimensions {
            dimensionsVisible.toggle()
        }
    }

    var isDrawingToolActive: Bool {
        activeCategory.isDrawingTool
    }

    func syncGridFromSettings() {
        grid.spacing = UnitConversion.visualGridSpacing(
            sliderValue: settings.defaultGridSpacingInUnits,
            unit: settings.units
        )
    }

    /// Applies defaults intended for newly created projects.
    func applyNewProjectDefaults() {
        settings.units = .inches
        settings.defaultGridSpacing = UnitConversion.pointsPerInch
        settings.allowsFingerDrawing = false
        settings.syncCanvasExtentToMaximum()
        syncGridFromSettings()
    }

    func removeStroke(id: UUID) {
        guard strokes.contains(where: { $0.id == id }) else { return }
        pushUndo()
        strokes.removeAll { $0.id == id }
        if selectedStrokeID == id {
            selectedStrokeID = nil
        }
    }

    func selectStroke(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        let candidates = selectableStrokes()
        if let fillHit = candidates.reversed().first(where: { $0.contains(documentPoint) }) {
            selectedStrokeID = fillHit.id
            return fillHit
        }

        var best: VectorStroke?
        var bestDistance = threshold
        for stroke in candidates.reversed() {
            let distance = stroke.distance(to: documentPoint)
            if distance < bestDistance {
                bestDistance = distance
                best = stroke
            }
        }
        selectedStrokeID = best?.id
        return best
    }

    // MARK: - Print Layout

    func printTransform(for strokeID: UUID) -> PrintStrokeTransform {
        printStrokeTransforms[strokeID] ?? .identity
    }

    func setPrintTransform(_ transform: PrintStrokeTransform, for strokeID: UUID, recordUndo: Bool = true) {
        if recordUndo { pushUndo() }
        if transform == .identity {
            printStrokeTransforms.removeValue(forKey: strokeID)
        } else {
            printStrokeTransforms[strokeID] = transform
        }
        printLayoutRevision += 1
    }

    func effectivePrintTransform(for strokeID: UUID) -> PrintStrokeTransform {
        var transform = printTransform(for: strokeID)
        transform.translation = CGPoint(
            x: transform.translation.x + printLayout.contentOffset.x,
            y: transform.translation.y + printLayout.contentOffset.y
        )
        return transform
    }

    func transformedPrintStroke(_ stroke: VectorStroke) -> VectorStroke {
        PrintLayoutCoordinateSpace.transformedStroke(
            stroke,
            transform: effectivePrintTransform(for: stroke.id)
        )
    }

    /// Centers visible artwork on the paper grid the first time print layout is opened.
    func autoPositionDesignOnPrintGrid() {
        guard printLayout.contentOffset == .zero, printStrokeTransforms.isEmpty else { return }

        var points: [CGPoint] = []
        for stroke in visibleStrokes() {
            points.append(contentsOf: ShapeGeometry.renderPoints(for: stroke))
        }
        for element in visibleTextElements() {
            points.append(contentsOf: element.corners())
        }
        guard !points.isEmpty else { return }

        let designBounds = PrintLayoutCoordinateSpace.boundingRect(for: points)
        let gridBounds = PrintPageGridEngine.gridBounds(for: printLayout)
        guard !designBounds.isNull, !gridBounds.isNull else { return }

        var settings = printLayout
        settings.contentOffset = CGPoint(
            x: gridBounds.midX - designBounds.midX,
            y: gridBounds.midY - designBounds.midY
        )
        printLayout = settings
        printLayoutRevision += 1
    }

    func selectPrintStroke(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        for stroke in visibleStrokes().reversed() {
            let transformed = transformedPrintStroke(stroke)
            if transformed.contains(documentPoint) {
                printSelectedStrokeID = stroke.id
                return stroke
            }
        }

        var best: VectorStroke?
        var bestDistance = threshold
        for stroke in visibleStrokes().reversed() {
            let transformed = transformedPrintStroke(stroke)
            let distance = transformed.distance(to: documentPoint)
            if distance < bestDistance {
                bestDistance = distance
                best = stroke
            }
        }
        printSelectedStrokeID = best?.id
        return best
    }

    func updatePrintLayout(_ settings: PrintLayoutSettings, recordUndo: Bool = true) {
        if recordUndo { pushUndo() }
        printLayout = settings
        refreshRegistrationMarkSuggestions()
        printLayoutRevision += 1
    }

    func refreshRegistrationMarkSuggestions() {
        let locked = registrationMarks.filter(\.isLocked)
        registrationMarks = PrintPageGridEngine.refreshRegistrationMarks(
            locked: locked,
            settings: printLayout
        )
    }

    func lockRegistrationMark(_ mark: RegistrationMark) {
        pushUndo()
        if let index = registrationMarks.firstIndex(where: { $0.id == mark.id }) {
            registrationMarks[index].isLocked = true
        } else {
            var locked = mark
            locked.isLocked = true
            registrationMarks.append(locked)
        }
        printLayoutRevision += 1
    }

    func removeRegistrationMark(id: UUID) {
        guard registrationMarks.contains(where: { $0.id == id }) else { return }
        pushUndo()
        registrationMarks.removeAll { $0.id == id }
        refreshRegistrationMarkSuggestions()
        printLayoutRevision += 1
    }

    func allPrintLayoutPoints() -> [CGPoint] {
        var points: [CGPoint] = []
        for stroke in visibleStrokes() {
            points.append(contentsOf: ShapeGeometry.renderPoints(for: transformedPrintStroke(stroke)))
        }
        let offset = printLayout.contentOffset
        for element in visibleTextElements() {
            points.append(contentsOf: element.corners().map {
                CGPoint(x: $0.x + offset.x, y: $0.y + offset.y)
            })
        }
        let gridBounds = PrintPageGridEngine.gridBounds(for: printLayout)
        points.append(contentsOf: [
            gridBounds.origin,
            CGPoint(x: gridBounds.maxX, y: gridBounds.maxY)
        ])
        return points
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        let preservedViewport = viewport
        redoStack.append(currentSnapshot())
        apply(snapshot)
        viewport = preservedViewport
        undoRevision += 1
        geometryRevision += 1
        printLayoutRevision += 1
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        let preservedViewport = viewport
        undoStack.append(currentSnapshot())
        apply(snapshot)
        viewport = preservedViewport
        undoRevision += 1
        geometryRevision += 1
        printLayoutRevision += 1
    }

    private func pushUndo() {
        undoStack.append(currentSnapshot())
        if undoStack.count > undoLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        undoRevision += 1
    }

    func reconcileIntersectionAnchors(around strokeIDs: Set<UUID>) {
        guard !strokeIDs.isEmpty else { return }
        let updated = IntersectionAnchorEngine.reconcile(strokes: strokes, candidateIDs: strokeIDs)
        if updated != strokes {
            strokes = updated
        }
    }

    private func currentSnapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            layers: layers,
            strokes: strokes,
            textElements: textElements,
            activeLayerID: activeLayerID,
            viewport: viewport,
            grid: grid,
            settings: settings,
            strokeWidth: strokeWidth,
            strokeColor: strokeColor,
            selectedStrokeID: selectedStrokeID,
            referenceImageData: referenceImageData,
            referenceImageFrame: referenceImageFrame,
            printLayout: printLayout,
            printStrokeTransforms: printStrokeTransforms,
            registrationMarks: registrationMarks,
            dimensionOffsets: dimensionOffsets
        )
    }

    private func apply(_ snapshot: DocumentSnapshot) {
        layers = snapshot.layers
        strokes = snapshot.strokes
        textElements = snapshot.textElements
        activeLayerID = snapshot.activeLayerID
        grid = snapshot.grid
        settings = snapshot.settings
        strokeWidth = snapshot.strokeWidth
        strokeColor = snapshot.strokeColor
        selectedStrokeID = snapshot.selectedStrokeID
        referenceImageData = snapshot.referenceImageData
        referenceImageFrame = snapshot.referenceImageFrame
        printLayout = snapshot.printLayout
        printStrokeTransforms = snapshot.printStrokeTransforms
        registrationMarks = snapshot.registrationMarks
        dimensionOffsets = snapshot.dimensionOffsets
        settings.syncCanvasExtentToMaximum()
        syncGridFromSettings()
        printLayoutRevision += 1
    }
}

struct DocumentSnapshot: Codable {
    var layers: [Layer]
    var strokes: [VectorStroke]
    var textElements: [TextElement] = []
    var activeLayerID: UUID
    var viewport: ViewportTransform
    var grid: GridSettings
    var settings: DocumentSettings = DocumentSettings()
    var strokeWidth: CGFloat
    var strokeColor: CodableColor
    var selectedStrokeID: UUID?
    var referenceImageData: Data?
    var referenceImageFrame: CGRect?
    var printLayout: PrintLayoutSettings = PrintLayoutSettings()
    var printStrokeTransforms: [UUID: PrintStrokeTransform] = [:]
    var registrationMarks: [RegistrationMark] = []
    var dimensionOffsets: [String: CGPoint] = [:]
}
