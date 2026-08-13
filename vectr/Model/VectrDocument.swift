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
    /// Structural groups referencing strokes/text by ID. Purely organizational:
    /// members remain independent entities in `strokes`/`textElements`.
    var groups: [ObjectGroup] = []
    /// Layer folders. Membership is stored on each `Layer.groupID`; this list
    /// only holds the folder name and collapsed state.
    var layerGroups: [LayerGroup] = []
    var activeLayerID: UUID
    var viewport: ViewportTransform
    var grid: GridSettings
    var settings: DocumentSettings = DocumentSettings()

    var strokeWidth: CGFloat = 1.5
    var strokeColor: CodableColor = CodableColor(.primary)
    var selectedStrokeID: UUID? {
        didSet {
            guard !isSyncingSelection else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            if let id = selectedStrokeID {
                lastSelectedStrokeID = id
                selectedStrokeIDs = [id]
                selectedTextID = nil
                selectedTextIDs = []
            } else {
                selectedStrokeIDs = []
            }
        }
    }
    /// Full set of selected strokes for multi-object move/rotate. Always includes
    /// the primary `selectedStrokeID` when a stroke is selected.
    var selectedStrokeIDs: Set<UUID> = []
    /// Full set of selected text elements, kept in sync with `selectedTextID`.
    var selectedTextIDs: Set<UUID> = []
    /// Remembers the most recent stroke selection so the move tool can restore its
    /// edit handles after switching to another tool and back.
    var lastSelectedStrokeID: UUID?
    /// Guards the selection property observers against re-entrant updates.
    private var isSyncingSelection = false
    var snapEnabled: Bool = true
    /// Master switch for the object snapping engine (endpoint/midpoint magnetic snapping).
    /// Independent of grid snapping (`snapEnabled`); map this to a toolbar icon to toggle
    /// the whole engine on/off. Kept as a plain document property so it is globally reachable
    /// wherever the document is in scope.
    var isSnappingEnabled: Bool = true
    /// Per-type toggles for the object snapping engine, driven by the canvas snap bar.
    var endpointSnapEnabled: Bool = true
    var midpointSnapEnabled: Bool = true
    var intersectionSnapEnabled: Bool = true
    /// Curved-geometry snap toggles: circle/ellipse/arc center, quadrant apexes, and
    /// tangent contact for an in-progress line.
    var centerSnapEnabled: Bool = true
    var quadrantSnapEnabled: Bool = true
    var tangentSnapEnabled: Bool = true
    var dimensionsVisible: Bool = false
    // Document-space offsets of dragged dimension labels, keyed by "<strokeID>:<dimensionID>".
    var dimensionOffsets: [String: CGPoint] = [:]
    var scaleUniform: Bool = true
    var selectedAnchorIndices: Set<Int> = []
    var selectedFilletCornerIndices: Set<Int> = []
    /// When set, move-tool rotation pivots around this anchor index; nil uses shape center.
    var moveRotationPivotAnchorIndex: Int?
    var activeCategory: ToolCategory = .line
    var lineVariant: LineVariant = .line
    var circleVariant: CircleVariant = .center
    var rectangleVariant: RectangleVariant = .center
    var selectedTextID: UUID? {
        didSet {
            guard !isSyncingSelection else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            if let id = selectedTextID {
                selectedTextIDs = [id]
                selectedStrokeID = nil
                selectedStrokeIDs = []
            } else {
                selectedTextIDs = []
            }
        }
    }
    var activeFontRef: FontRef = .default
    var activeFontSize: CGFloat = 24
    var referenceImageData: Data?
    var referenceImageFrame: CGRect?

    var printLayout: PrintLayoutSettings = PrintLayoutSettings()
    var printStrokeTransforms: [UUID: PrintStrokeTransform] = [:]
    var printSelectedStrokeID: UUID?
    var printSelectedTextID: UUID?
    var printLayoutRevision = 0
    /// Print-layout-only sliced fragments produced by the Cut tool. Each is a fresh
    /// polyline in base (design) space; laid over the design strokes and never
    /// mutating them, so Design mode stays fully intact.
    var printPieces: [VectorStroke] = []
    /// Original design strokes that have been cut and are hidden in Print Layout
    /// (replaced by their `printPieces`). They remain fully intact in Design mode.
    var printHiddenStrokeIDs: Set<UUID> = []

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
        groups = snapshot.groups
        layerGroups = snapshot.layerGroups
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
        printPieces = snapshot.printPieces
        printHiddenStrokeIDs = snapshot.printHiddenStrokeIDs
        dimensionOffsets = snapshot.dimensionOffsets
        settings.syncCanvasExtentToMaximum()
        syncGridFromSettings()
        normalizeLayerGrouping()
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

    /// Visible strokes on the active layer that isn't locked, for hit-testing/selection.
    /// Shapes on other layers are visible but not editable until their layer is active.
    func selectableStrokes() -> [VectorStroke] {
        let lockedLayerIDs = Set(layers.filter(\.isLocked).map(\.id))
        return visibleStrokes().filter { $0.layerID == activeLayerID && !lockedLayerIDs.contains($0.layerID) }
    }

    func stroke(with id: UUID) -> VectorStroke? {
        strokes.first { $0.id == id }
    }

    /// Single source of truth for what Print Layout renders/selects/exports:
    /// visible design strokes that have not been cut, followed by print-layout pieces
    /// (filtered to visible layers). Design mode never uses this.
    func printLayoutStrokes() -> [VectorStroke] {
        let visibleLayerIDs = Set(layers.filter(\.isVisible).map(\.id))
        var result = visibleStrokes().filter { !printHiddenStrokeIDs.contains($0.id) }
        result.append(contentsOf: printPieces.filter { visibleLayerIDs.contains($0.layerID) })
        return result
    }

    /// Resolves a print-layout stroke id, preferring pieces over design strokes.
    func printLayoutStroke(with id: UUID) -> VectorStroke? {
        if let piece = printPieces.first(where: { $0.id == id }) { return piece }
        return strokes.first { $0.id == id }
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
        pruneGroups()
        if let selected = selectedStrokeID, stroke(with: selected) == nil {
            selectedStrokeID = nil
        }
        if let selectedText = selectedTextID, textElement(with: selectedText) == nil {
            selectedTextID = nil
        }
        if activeLayerID == id {
            activeLayerID = layers[min(index, layers.count - 1)].id
        }
        normalizeLayerGrouping()
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
        // Selection is confined to the active layer, so drop anything selected on the
        // previous layer to prevent stale edit handles/drags on non-active shapes.
        let selectedOnActive = selectedStrokeIDs.filter { stroke(with: $0)?.layerID == id }
        let selectedTextOnActive = selectedTextIDs.filter { textElement(with: $0)?.layerID == id }
        if selectedOnActive.count != selectedStrokeIDs.count || selectedTextOnActive.count != selectedTextIDs.count {
            setElementSelection(strokeIDs: selectedOnActive, textIDs: selectedTextOnActive)
        }
    }

    /// Replaces the layer stack with a reordered copy of the same layers (index 0 = backmost).
    func reorderLayers(_ newOrder: [Layer]) {
        guard newOrder.map(\.id) != layers.map(\.id),
              Set(newOrder.map(\.id)) == Set(layers.map(\.id)),
              newOrder.count == layers.count else { return }
        pushUndo()
        layers = newOrder
        normalizeLayerGrouping()
        geometryRevision += 1
    }

    // MARK: - Layer Folders

    func layerGroup(with id: UUID) -> LayerGroup? {
        layerGroups.first { $0.id == id }
    }

    /// Member layers of a folder, in back-to-front document order.
    func layers(inGroup groupID: UUID) -> [Layer] {
        layers.filter { $0.groupID == groupID }
    }

    /// Keeps folder invariants intact: drops dangling `groupID`s and empty
    /// folders, and re-gathers each folder's layers into a single contiguous run
    /// (anchored at the position of its first member) so a folder never appears
    /// split in the stacking order.
    func normalizeLayerGrouping() {
        let groupIDs = Set(layerGroups.map(\.id))
        for i in layers.indices where layers[i].groupID != nil && !groupIDs.contains(layers[i].groupID!) {
            layers[i].groupID = nil
        }
        var result: [Layer] = []
        var placed = Set<UUID>()
        for layer in layers {
            guard let gid = layer.groupID else {
                result.append(layer)
                continue
            }
            if placed.contains(gid) { continue }
            placed.insert(gid)
            result.append(contentsOf: layers.filter { $0.groupID == gid })
        }
        layers = result
        let used = Set(layers.compactMap(\.groupID))
        layerGroups.removeAll { !used.contains($0.id) }
    }

    private func nextLayerGroupName() -> String {
        let existing = Set(layerGroups.map(\.name))
        var n = layerGroups.count + 1
        while existing.contains("Folder \(n)") { n += 1 }
        return "Folder \(n)"
    }

    /// Puts the given layers into a new folder. Any prior folder membership of
    /// those layers is replaced; the members are gathered contiguously.
    @discardableResult
    func groupLayers(ids: Set<UUID>) -> LayerGroup? {
        let members = layers.filter { ids.contains($0.id) }
        guard !members.isEmpty else { return nil }
        pushUndo()
        let group = LayerGroup(name: nextLayerGroupName())
        layerGroups.append(group)
        for i in layers.indices where ids.contains(layers[i].id) {
            layers[i].groupID = group.id
        }
        normalizeLayerGrouping()
        geometryRevision += 1
        return group
    }

    /// Dissolves a folder, leaving its layers in place at the top level.
    func ungroupLayers(groupID: UUID) {
        guard layerGroups.contains(where: { $0.id == groupID }) else { return }
        pushUndo()
        for i in layers.indices where layers[i].groupID == groupID {
            layers[i].groupID = nil
        }
        layerGroups.removeAll { $0.id == groupID }
        geometryRevision += 1
    }

    /// Removes a single layer from its folder, leaving it at the top level.
    func removeLayerFromFolder(layerID: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }),
              layers[index].groupID != nil else { return }
        pushUndo()
        layers[index].groupID = nil
        normalizeLayerGrouping()
        geometryRevision += 1
    }

    func renameLayerGroup(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = layerGroups.firstIndex(where: { $0.id == id }),
              layerGroups[index].name != trimmed else { return }
        pushUndo()
        layerGroups[index].name = trimmed
    }

    /// Collapse state is presentation-only, so it isn't recorded on the undo stack.
    func toggleLayerGroupCollapsed(id: UUID) {
        guard let index = layerGroups.firstIndex(where: { $0.id == id }) else { return }
        layerGroups[index].isCollapsed.toggle()
    }

    /// Whether all member layers of a folder are currently visible.
    func layerGroupIsVisible(id: UUID) -> Bool {
        let members = layers(inGroup: id)
        return !members.isEmpty && members.allSatisfy(\.isVisible)
    }

    /// Whether all member layers of a folder are currently locked.
    func layerGroupIsLocked(id: UUID) -> Bool {
        let members = layers(inGroup: id)
        return !members.isEmpty && members.allSatisfy(\.isLocked)
    }

    /// Cascades a visibility change to every layer in the folder.
    func setLayerGroupVisibility(id: UUID, isVisible: Bool) {
        guard layers.contains(where: { $0.groupID == id }) else { return }
        pushUndo()
        for i in layers.indices where layers[i].groupID == id {
            layers[i].isVisible = isVisible
        }
        geometryRevision += 1
    }

    /// Cascades a lock change to every layer in the folder.
    func setLayerGroupLocked(id: UUID, isLocked: Bool) {
        guard layers.contains(where: { $0.groupID == id }) else { return }
        pushUndo()
        for i in layers.indices where layers[i].groupID == id {
            layers[i].isLocked = isLocked
        }
        geometryRevision += 1
    }

    /// Merges the given layers into a single layer, preserving the visual
    /// front/back stacking of their contents. The front-most selected layer is
    /// kept as the destination (its name, visibility, lock, and folder stay);
    /// the others are removed. Returns the surviving layer's id.
    @discardableResult
    func mergeLayers(ids: Set<UUID>) -> UUID? {
        let indexed = layers.enumerated().filter { ids.contains($0.element.id) }
        guard indexed.count >= 2 else { return nil }
        pushUndo()
        let order = layerIndexByID()
        // Destination = front-most (largest layer index) among the selection.
        let targetID = indexed.max(by: { order[$0.element.id] ?? 0 < order[$1.element.id] ?? 0 })!.element.id
        let mergedIDs = Set(indexed.map(\.element.id))

        strokes = mergedContentPreservingOrder(strokes, mergedIDs: mergedIDs, targetID: targetID, order: order,
                                               layerID: { $0.layerID }, setLayerID: { $0.layerID = $1 })
        textElements = mergedContentPreservingOrder(textElements, mergedIDs: mergedIDs, targetID: targetID, order: order,
                                                    layerID: { $0.layerID }, setLayerID: { $0.layerID = $1 })

        layers.removeAll { mergedIDs.contains($0.id) && $0.id != targetID }
        pruneGroups()
        if let selected = selectedStrokeID, stroke(with: selected) == nil { selectedStrokeID = nil }
        if let selectedText = selectedTextID, textElement(with: selectedText) == nil { selectedTextID = nil }
        if mergedIDs.contains(activeLayerID) { activeLayerID = targetID }
        normalizeLayerGrouping()
        geometryRevision += 1
        return targetID
    }

    /// Reassigns every element on a merged layer to `targetID`, ordering the
    /// merged block back-to-front by original layer index (then insertion order)
    /// and reinserting it where the first merged element used to sit.
    private func mergedContentPreservingOrder<T>(
        _ items: [T],
        mergedIDs: Set<UUID>,
        targetID: UUID,
        order: [UUID: Int],
        layerID: (T) -> UUID,
        setLayerID: (inout T, UUID) -> Void
    ) -> [T] {
        let sortedMerged = items.enumerated()
            .filter { mergedIDs.contains(layerID($0.element)) }
            .sorted { lhs, rhs in
                let l = order[layerID(lhs.element)] ?? 0
                let r = order[layerID(rhs.element)] ?? 0
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map { entry -> T in
                var copy = entry.element
                setLayerID(&copy, targetID)
                return copy
            }
        guard !sortedMerged.isEmpty else { return items }
        var result: [T] = []
        var insertedBlock = false
        for item in items {
            if mergedIDs.contains(layerID(item)) {
                if !insertedBlock {
                    insertedBlock = true
                    result.append(contentsOf: sortedMerged)
                }
            } else {
                result.append(item)
            }
        }
        return result
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

    /// Visible text elements on the active layer that isn't locked, for hit-testing/selection.
    /// Text on other layers is visible but not editable until its layer is active.
    func selectableTextElements() -> [TextElement] {
        let lockedLayerIDs = Set(layers.filter(\.isLocked).map(\.id))
        return visibleTextElements().filter { $0.layerID == activeLayerID && !lockedLayerIDs.contains($0.layerID) }
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
        pruneGroups()
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
            // The drawn segment starts at the polyline's first point, so its free
            // endpoint (`end`) becomes the new first vertex, extending outward.
            stroke.points.insert(end, at: 0)
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
            // The drawn segment ends at the polyline's last point, so its free
            // endpoint (`start`) becomes the new last vertex, extending outward.
            stroke.points.append(start)
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
        ClosedShapeDetector.reconcile(document: self)
    }

    func deleteStrokeEdge(at edgeIndex: Int) {
        guard let id = selectedStrokeID,
              let stroke = stroke(with: id),
              let updated = StrokeEditor.deleteEdge(stroke, edgeIndex: edgeIndex) else { return }
        pushUndo()
        updateStroke(updated, recordUndo: false)
        ClosedShapeDetector.reconcile(document: self)
    }

    /// CAD-style trim: remove the contour span between cut points that bounds `documentPoint`.
    @discardableResult
    func trimAt(_ documentPoint: CGPoint, threshold: CGFloat) -> Bool {
        guard let result = TrimEngine.trim(
            at: documentPoint,
            threshold: threshold,
            strokes: strokes,
            preferredStrokeID: selectedStrokeID
        ) else { return false }

        pushUndo()
        if let index = strokes.firstIndex(where: { $0.id == result.strokeID }) {
            strokes[index] = result.stroke
        }
        var affected: Set<UUID> = [result.stroke.id]
        if let additional = result.additionalStroke {
            strokes.append(additional)
            affected.insert(additional.id)
        }
        selectedStrokeID = result.stroke.id
        reconcileIntersectionAnchors(around: affected)
        ClosedShapeDetector.reconcile(document: self)
        DonutDetector.reconcile(document: self)
        geometryRevision += 1
        return true
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

    @discardableResult
    func applyPattern(to strokeID: UUID, settings: PatternSettings) -> PatternApplyResult {
        guard let source = stroke(with: strokeID) else {
            return .noSelection
        }
        if let layer = layers.first(where: { $0.id == source.layerID }), layer.isLocked {
            return .layerLocked
        }

        let application = PatternEngine.application(
            from: source,
            sourceID: strokeID,
            settings: settings
        )
        guard application.repositionedSource != nil || !application.newStrokes.isEmpty else {
            return .nothingToCreate
        }

        pushUndo()

        if let repositioned = application.repositionedSource,
           let index = strokes.firstIndex(where: { $0.id == strokeID }) {
            strokes[index] = repositioned
        }

        if application.removeSource {
            strokes.removeAll { $0.id == strokeID }
        }

        strokes.append(contentsOf: application.newStrokes)

        if application.removeSource {
            selectedStrokeID = application.newStrokes.last?.id
        } else {
            selectedStrokeID = strokeID
        }

        var affectedIDs = Set(application.newStrokes.map(\.id))
        if application.repositionedSource != nil || !application.removeSource {
            affectedIDs.insert(strokeID)
        }
        reconcileIntersectionAnchors(around: affectedIDs)
        ClosedShapeDetector.reconcile(document: self)
        DonutDetector.reconcile(document: self)
        geometryRevision += 1

        let createdCount: Int
        switch settings.mode {
        case .radial, .spiral where settings.keepOriginal:
            createdCount = application.newStrokes.count
        case .radial, .spiral:
            createdCount = application.newStrokes.count + (application.repositionedSource != nil ? 1 : 0)
        default:
            createdCount = application.newStrokes.count
        }
        return .success(created: createdCount)
    }

    /// Single tap: reset the selection to only this anchor and adopt it as the rotation pivot.
    func selectSingleAnchor(at index: Int) {
        selectedAnchorIndices = [index]
        moveRotationPivotAnchorIndex = index
    }

    /// Double-tap: multi-select toggle that leaves the other selected anchors untouched.
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

    // MARK: - Multi-element selection

    /// Number of selected elements across strokes and text.
    var selectionCount: Int {
        selectedStrokeIDs.count + selectedTextIDs.count
    }

    /// True when more than one element (stroke and/or text) is selected.
    var hasMultiSelection: Bool {
        selectionCount > 1
    }

    var selectionIsEmpty: Bool {
        selectedStrokeIDs.isEmpty && selectedTextIDs.isEmpty
    }

    /// Replaces the entire element selection, picking a stable primary so the
    /// single-object tools (fillet/trim/scale/rotate panel) keep working.
    func setElementSelection(strokeIDs: Set<UUID>, textIDs: Set<UUID>) {
        isSyncingSelection = true
        selectedStrokeIDs = strokeIDs
        selectedTextIDs = textIDs
        if let primary = strokeIDs.first {
            selectedStrokeID = primary
            selectedTextID = nil
            lastSelectedStrokeID = primary
        } else if let primaryText = textIDs.first {
            selectedTextID = primaryText
            selectedStrokeID = nil
        } else {
            selectedStrokeID = nil
            selectedTextID = nil
        }
        isSyncingSelection = false
        clearAnchorSelection()
    }

    func toggleStrokeSelection(_ id: UUID) {
        var next = selectedStrokeIDs
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        setElementSelection(strokeIDs: next, textIDs: selectedTextIDs)
    }

    func toggleTextSelection(_ id: UUID) {
        var next = selectedTextIDs
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        setElementSelection(strokeIDs: selectedStrokeIDs, textIDs: next)
    }

    func clearElementSelection() {
        setElementSelection(strokeIDs: [], textIDs: [])
    }

    /// Non-mutating topmost stroke hit, mirroring `selectStroke` without changing selection.
    func strokeHit(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        let candidates = selectableStrokes()
        if let fillHit = candidates.reversed().first(where: { $0.contains(documentPoint) }) {
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
        return best
    }

    /// Topmost stroke whose outline is within `threshold` of the point, ignoring fill.
    /// Used by the Delete tool to distinguish an edge/line tap from an interior fill tap.
    func strokeOutlineHit(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        var best: VectorStroke?
        var bestDistance = threshold
        for stroke in selectableStrokes().reversed() {
            let distance = stroke.distance(to: documentPoint)
            if distance < bestDistance {
                bestDistance = distance
                best = stroke
            }
        }
        return best
    }

    /// Topmost closed stroke whose filled interior contains the point, ignoring outline proximity.
    func strokeFillHit(at documentPoint: CGPoint) -> VectorStroke? {
        selectableStrokes().reversed().first { $0.contains(documentPoint) }
    }

    /// Non-mutating topmost element hit (text preferred over strokes).
    func elementHit(near documentPoint: CGPoint, threshold: CGFloat) -> ElementHit {
        if let text = textElement(at: documentPoint) { return .text(text.id) }
        if let stroke = strokeHit(near: documentPoint, threshold: threshold) { return .stroke(stroke.id) }
        return .none
    }

    /// True when `point` lies on/near any currently selected element.
    func selectionContains(point: CGPoint, threshold: CGFloat) -> Bool {
        for id in selectedStrokeIDs {
            guard let stroke = stroke(with: id) else { continue }
            if stroke.contains(point) || stroke.distance(to: point) <= threshold {
                return true
            }
        }
        for id in selectedTextIDs {
            if let text = textElement(with: id), text.contains(point) {
                return true
            }
        }
        return false
    }

    /// Marquee selection: selects every element whose bounds overlap `rect`.
    func selectElements(in rect: CGRect, additive: Bool = false) {
        var strokeIDs = additive ? selectedStrokeIDs : []
        var textIDs = additive ? selectedTextIDs : []
        for stroke in selectableStrokes() {
            if let bbox = stroke.boundingBox(), Self.rectsOverlap(bbox, rect) {
                strokeIDs.insert(stroke.id)
            }
        }
        for text in selectableTextElements() {
            if Self.rectsOverlap(text.boundingBox(), rect) {
                textIDs.insert(text.id)
            }
        }
        let expanded = expandedSelectionForGroups(strokeIDs: strokeIDs, textIDs: textIDs)
        setElementSelection(strokeIDs: expanded.strokeIDs, textIDs: expanded.textIDs)
    }

    /// Combined bounding box of the current selection, in document space.
    func selectionBoundingBox() -> CGRect? {
        var rect: CGRect?
        for id in selectedStrokeIDs {
            if let stroke = stroke(with: id), let bbox = stroke.boundingBox() {
                rect = rect.map { $0.union(bbox) } ?? bbox
            }
        }
        for id in selectedTextIDs {
            if let text = textElement(with: id) {
                let bbox = text.boundingBox()
                rect = rect.map { $0.union(bbox) } ?? bbox
            }
        }
        return rect
    }

    /// Rect overlap test that (unlike `CGRect.intersects`) treats degenerate
    /// zero-area rects (e.g. an axis-aligned line) as overlapping.
    private static func rectsOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX <= b.maxX && a.maxX >= b.minX && a.minY <= b.maxY && a.maxY >= b.minY
    }

    // MARK: - Multi-element operations

    /// Any non-construction stroke with editable anchors (open or closed,
    /// including rectangles / circles via their handle points).
    private func isJoinable(_ stroke: VectorStroke) -> Bool {
        !stroke.isConstruction && ShapeGeometry.handlePoints(for: stroke).count >= 2
    }

    private var joinableSelectedStrokes: [VectorStroke] {
        strokes.filter { selectedStrokeIDs.contains($0.id) && isJoinable($0) }
    }

    /// True when two selected shapes have anchors within snap tolerance of each
    /// other. Open vs closed does not matter — Join appears exactly when a weld
    /// is possible.
    var canJoinSelection: Bool {
        let selected = joinableSelectedStrokes
        guard selected.count >= 2 else { return false }
        return PathJoinEngine.hasTouchingAnchors(selected, tolerance: grid.spacing * 0.5)
    }

    /// Permanently welds selected shapes that share touching anchors into one
    /// (or fewer) paths. Distinct from grouping: geometry is fused, not just
    /// moved together. Undoable, but there is no dedicated "unjoin".
    @discardableResult
    func joinSelectedShapes() -> Bool {
        let selected = joinableSelectedStrokes
        guard selected.count >= 2 else { return false }
        let tolerance = grid.spacing * 0.5
        guard let joined = PathJoinEngine.join(selected, tolerance: tolerance), !joined.isEmpty else {
            return false
        }
        pushUndo()
        let removeIDs = Set(selected.map(\.id))
        strokes.removeAll { removeIDs.contains($0.id) }
        strokes.append(contentsOf: joined)
        pruneGroups()
        ClosedShapeDetector.reconcile(document: self)
        let joinedIDs = Set(joined.map(\.id))
        reconcileIntersectionAnchors(around: joinedIDs)
        geometryRevision += 1
        setElementSelection(strokeIDs: joinedIDs, textIDs: [])
        return true
    }

    /// Deletes every selected stroke and text element in one undoable step.
    func deleteSelectedElements() {
        guard !selectionIsEmpty else { return }
        pushUndo()
        let strokeIDs = selectedStrokeIDs
        let textIDs = selectedTextIDs
        strokes.removeAll { strokeIDs.contains($0.id) }
        textElements.removeAll { textIDs.contains($0.id) }
        pruneGroups()
        isSyncingSelection = true
        selectedStrokeIDs = []
        selectedTextIDs = []
        selectedStrokeID = nil
        selectedTextID = nil
        isSyncingSelection = false
        clearAnchorSelection()
        geometryRevision += 1
    }

    /// Duplicates the selection, offsetting the copies and selecting them.
    func duplicateSelectedElements(offset: CGPoint) {
        guard !selectionIsEmpty else { return }
        pushUndo()
        var newStrokeIDs: Set<UUID> = []
        var newTextIDs: Set<UUID> = []
        for id in selectedStrokeIDs {
            guard var copy = stroke(with: id) else { continue }
            copy.id = UUID()
            copy.points = copy.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
            copy.cutoutPoints = copy.cutoutPoints.map { contour in
                contour.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
            }
            copy.rotationBasePoints = nil
            copy.rotationBaseCenter = nil
            strokes.append(copy)
            newStrokeIDs.insert(copy.id)
        }
        for id in selectedTextIDs {
            guard var copy = textElement(with: id) else { continue }
            copy.id = UUID()
            copy.position = CGPoint(x: copy.position.x + offset.x, y: copy.position.y + offset.y)
            textElements.append(copy)
            newTextIDs.insert(copy.id)
        }
        geometryRevision += 1
        setElementSelection(strokeIDs: newStrokeIDs, textIDs: newTextIDs)
    }

    /// Rotates every selected element by `degrees` around the selection's combined
    /// bounding-box center. Used by the move panel when 2+ elements are selected.
    /// Expands to full groups first; does not weld overlapping anchors.
    func rotateSelectedElements(byDegrees degrees: Double, recordUndo: Bool = true) {
        expandSelectionToGroupsIfNeeded()
        guard let bbox = selectionBoundingBox() else { return }
        let radians = CGFloat(degrees * .pi / 180)
        guard abs(radians) > 1e-9 else { return }
        let pivot = CGPoint(x: bbox.midX, y: bbox.midY)
        if recordUndo { pushUndo() }
        for id in selectedStrokeIDs {
            guard let stroke = stroke(with: id) else { continue }
            let rotated = ShapeGeometry.rotatedStroke(stroke, around: pivot, by: radians)
            updateStroke(rotated, recordUndo: false)
        }
        for id in selectedTextIDs {
            guard var text = textElement(with: id) else { continue }
            let rotatedCenter = ShapeGeometry.rotatePoints(
                [text.center],
                around: pivot,
                by: radians
            ).first ?? text.center
            text.rotation += radians
            let size = text.textSize()
            text.position = CGPoint(
                x: rotatedCenter.x - size.width / 2,
                y: rotatedCenter.y - size.height / 2
            )
            updateTextElement(text, recordUndo: false)
        }
        // Intentionally skip intersection-anchor reconciliation so overlapping
        // vertices remain independent after a group transform.
        geometryRevision += 1
    }

    /// Mirrors the selection about its combined bounding-box center.
    func flipSelection(horizontal: Bool) {
        expandSelectionToGroupsIfNeeded()
        guard let bbox = selectionBoundingBox() else { return }
        pushUndo()
        let cx = bbox.midX
        let cy = bbox.midY
        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: horizontal ? 2 * cx - point.x : point.x,
                y: horizontal ? point.y : 2 * cy - point.y
            )
        }
        for id in selectedStrokeIDs {
            guard let index = strokes.firstIndex(where: { $0.id == id }) else { continue }
            strokes[index].points = strokes[index].points.map(flip)
            strokes[index].cutoutPoints = strokes[index].cutoutPoints.map { $0.map(flip) }
            if let handles = strokes[index].curveHandles {
                strokes[index].curveHandles = handles.map { handle in
                    CurveHandle(
                        inOffset: CGPoint(
                            x: horizontal ? -handle.inOffset.x : handle.inOffset.x,
                            y: horizontal ? handle.inOffset.y : -handle.inOffset.y
                        ),
                        outOffset: CGPoint(
                            x: horizontal ? -handle.outOffset.x : handle.outOffset.x,
                            y: horizontal ? handle.outOffset.y : -handle.outOffset.y
                        )
                    )
                }
            }
            strokes[index].rotationBasePoints = nil
            strokes[index].rotationBaseCenter = nil
        }
        for id in selectedTextIDs {
            guard let index = textElements.firstIndex(where: { $0.id == id }) else { continue }
            let newCenter = flip(textElements[index].center)
            let size = textElements[index].textSize()
            textElements[index].position = CGPoint(
                x: newCenter.x - size.width / 2,
                y: newCenter.y - size.height / 2
            )
        }
        reconcileIntersectionAnchors(around: selectedStrokeIDs)
        geometryRevision += 1
    }

    // MARK: - Groups

    /// The group containing the given stroke, if any.
    func group(containingStroke id: UUID) -> ObjectGroup? {
        groups.first { $0.containsStroke(id) }
    }

    /// The group containing the given text element, if any.
    func group(containingText id: UUID) -> ObjectGroup? {
        groups.first { $0.containsText(id) }
    }

    /// Group is available when at least two elements are selected.
    var canGroupSelection: Bool {
        selectionCount >= 2
    }

    /// Ungroup is available when any selected element belongs to a group.
    var canUngroupSelection: Bool {
        selectedStrokeIDs.contains { group(containingStroke: $0) != nil }
            || selectedTextIDs.contains { group(containingText: $0) != nil }
    }

    /// Expands a selection so that whenever a member of a group is included,
    /// all of that group's other members are included too. Keeps only members
    /// that still exist in the document.
    func expandedSelectionForGroups(
        strokeIDs: Set<UUID>,
        textIDs: Set<UUID>
    ) -> (strokeIDs: Set<UUID>, textIDs: Set<UUID>) {
        var resultStrokes = strokeIDs
        var resultTexts = textIDs
        for group in groups {
            let touchesGroup = group.strokeIDs.contains(where: strokeIDs.contains)
                || group.textIDs.contains(where: textIDs.contains)
            guard touchesGroup else { continue }
            for id in group.strokeIDs where stroke(with: id) != nil {
                resultStrokes.insert(id)
            }
            for id in group.textIDs where textElement(with: id) != nil {
                resultTexts.insert(id)
            }
        }
        return (resultStrokes, resultTexts)
    }

    /// Combined document-space bounds of a group's existing members.
    func groupBoundingBox(_ group: ObjectGroup) -> CGRect? {
        var rect: CGRect?
        for id in group.strokeIDs {
            if let s = stroke(with: id), let b = s.boundingBox() {
                rect = rect.map { $0.union(b) } ?? b
            }
        }
        for id in group.textIDs {
            if let t = textElement(with: id) {
                let b = t.boundingBox()
                rect = rect.map { $0.union(b) } ?? b
            }
        }
        return rect
    }

    /// Topmost group whose bounding box contains `documentPoint` (gives thin/open
    /// members a large, closed-shape-like hit area).
    func group(at documentPoint: CGPoint) -> ObjectGroup? {
        groups.reversed().first { groupBoundingBox($0)?.contains(documentPoint) == true }
    }

    /// The group whose membership exactly matches the current selection, if any.
    var selectedGroup: ObjectGroup? {
        groups.first { Set($0.strokeIDs) == selectedStrokeIDs && Set($0.textIDs) == selectedTextIDs }
    }

    /// True when any currently selected element belongs to a group.
    var selectionTouchesGroup: Bool {
        selectedStrokeIDs.contains { group(containingStroke: $0) != nil }
            || selectedTextIDs.contains { group(containingText: $0) != nil }
    }

    /// True when the move tool should transform the selection as a unit
    /// (multi-select or any selected member of a group).
    var usesGroupTransform: Bool {
        hasMultiSelection || selectionTouchesGroup
    }

    /// Replaces the selection with the full membership of a group.
    func selectGroup(_ group: ObjectGroup) {
        let strokeIDs = Set(group.strokeIDs.filter { stroke(with: $0) != nil })
        let textIDs = Set(group.textIDs.filter { textElement(with: $0) != nil })
        setElementSelection(strokeIDs: strokeIDs, textIDs: textIDs)
    }

    /// Selects a stroke, expanding to its parent group when it belongs to one.
    func selectStrokeConsideringGroups(_ id: UUID) {
        if let group = group(containingStroke: id) {
            selectGroup(group)
        } else {
            setElementSelection(strokeIDs: [id], textIDs: [])
        }
    }

    /// Selects a text element, expanding to its parent group when it belongs to one.
    func selectTextConsideringGroups(_ id: UUID) {
        if let group = group(containingText: id) {
            selectGroup(group)
        } else {
            setElementSelection(strokeIDs: [], textIDs: [id])
        }
    }

    /// Expands the current selection so every touched group is fully selected.
    /// Returns true when the selection changed.
    @discardableResult
    func expandSelectionToGroupsIfNeeded() -> Bool {
        let expanded = expandedSelectionForGroups(
            strokeIDs: selectedStrokeIDs,
            textIDs: selectedTextIDs
        )
        guard expanded.strokeIDs != selectedStrokeIDs
            || expanded.textIDs != selectedTextIDs else { return false }
        setElementSelection(strokeIDs: expanded.strokeIDs, textIDs: expanded.textIDs)
        return true
    }

    /// Bundles the current selection into a single new group. Any groups that
    /// overlap the selection are merged into the new one so re-grouping stays flat.
    /// Purely structural: no stroke/text geometry is modified.
    func groupSelectedElements() {
        guard canGroupSelection else { return }
        pushUndo()

        // Absorb members of any group that overlaps the current selection.
        var strokeIDs = selectedStrokeIDs
        var textIDs = selectedTextIDs
        let overlapping = groups.filter { group in
            group.strokeIDs.contains(where: selectedStrokeIDs.contains)
                || group.textIDs.contains(where: selectedTextIDs.contains)
        }
        for group in overlapping {
            strokeIDs.formUnion(group.strokeIDs)
            textIDs.formUnion(group.textIDs)
        }
        let overlappingIDs = Set(overlapping.map(\.id))
        groups.removeAll { overlappingIDs.contains($0.id) }

        // Keep only members that still exist, preserving document order.
        let orderedStrokeIDs = strokes.map(\.id).filter { strokeIDs.contains($0) }
        let orderedTextIDs = textElements.map(\.id).filter { textIDs.contains($0) }
        guard orderedStrokeIDs.count + orderedTextIDs.count >= 2 else { return }

        let newGroup = ObjectGroup(strokeIDs: orderedStrokeIDs, textIDs: orderedTextIDs)
        groups.append(newGroup)
        setElementSelection(
            strokeIDs: Set(orderedStrokeIDs),
            textIDs: Set(orderedTextIDs)
        )
    }

    /// Dissolves every group that intersects the current selection, leaving the
    /// members behind as independent entities. Selection is preserved so the
    /// user can continue editing, but each child is once again individually
    /// selectable (anchors/points are no longer locked to a parent group).
    func ungroupSelectedElements() {
        guard canUngroupSelection else { return }
        pushUndo()
        groups.removeAll { group in
            group.strokeIDs.contains(where: selectedStrokeIDs.contains)
                || group.textIDs.contains(where: selectedTextIDs.contains)
        }
        // Keep the former members selected as a loose multi-selection so
        // subsequent taps can target individual shapes again.
        clearToolSelections()
    }

    /// Removes stale member references and drops any group left with fewer than
    /// two members. Call after deleting or welding elements.
    func pruneGroups() {
        let strokeIDSet = Set(strokes.map(\.id))
        let textIDSet = Set(textElements.map(\.id))
        var changed = false
        var pruned: [ObjectGroup] = []
        for var group in groups {
            let strokeCount = group.strokeIDs.count
            let textCount = group.textIDs.count
            group.strokeIDs.removeAll { !strokeIDSet.contains($0) }
            group.textIDs.removeAll { !textIDSet.contains($0) }
            if group.strokeIDs.count != strokeCount || group.textIDs.count != textCount {
                changed = true
            }
            if group.memberCount >= 2 {
                pruned.append(group)
            } else {
                changed = true
            }
        }
        if changed {
            groups = pruned
        }
    }

    /// Single tap: reset the fillet selection to only this corner.
    func selectSingleFilletCorner(at index: Int) {
        selectedFilletCornerIndices = [index]
    }

    /// Double-tap: multi-select toggle that leaves the other selected corners untouched.
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
        pruneGroups()
        if selectedStrokeID == id {
            clearToolSelections()
            selectedStrokeID = nil
        }
    }

    /// Interior fill tap for the Delete tool: when the topmost filled shape under
    /// `documentPoint` overlaps a closed shape beneath it, subtracts the top shape
    /// (Boolean: base MINUS target) to punch a hole in the base and removes the top
    /// shape. Returns `true` when a subtraction was performed.
    @discardableResult
    func punchOverlapHole(at documentPoint: CGPoint) -> Bool {
        let candidates = selectableStrokes()
        guard let targetIndex = candidates.lastIndex(where: {
            $0.isClosed && !$0.isConstruction && $0.contains(documentPoint)
        }) else { return false }

        let target = candidates[targetIndex]
        let targetContour = ShapeGeometry.renderPoints(for: target)
        guard targetContour.count >= 3 else { return false }

        // Search shapes beneath the target (front-to-back below it) for an overlap.
        for index in stride(from: targetIndex - 1, through: 0, by: -1) {
            let base = candidates[index]
            guard base.id != target.id, base.isClosed, !base.isConstruction else { continue }
            let baseContour = ShapeGeometry.renderPoints(for: base)
            guard baseContour.count >= 3 else { continue }
            guard let cutouts = ShapeBooleanEngine.subtractionCutouts(
                baseContour: baseContour,
                targetContour: targetContour
            ) else { continue }
            guard let baseArrayIndex = strokes.firstIndex(where: { $0.id == base.id }) else { continue }

            pushUndo()
            var updatedBase = strokes[baseArrayIndex]
            updatedBase.cutoutPoints.append(contentsOf: cutouts)
            strokes[baseArrayIndex] = updatedBase
            strokes.removeAll { $0.id == target.id }
            pruneGroups()
            deselectStrokeAfterMutation(target.id)
            geometryRevision += 1
            return true
        }
        return false
    }

    /// Removes a stroke id from every selection set after it has been deleted/consumed.
    private func deselectStrokeAfterMutation(_ id: UUID) {
        if selectedStrokeIDs.contains(id) {
            var remaining = selectedStrokeIDs
            remaining.remove(id)
            setElementSelection(strokeIDs: remaining, textIDs: selectedTextIDs)
        }
        if selectedStrokeID == id {
            clearToolSelections()
            selectedStrokeID = nil
        }
    }

    func selectStroke(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        guard let hit = strokeHit(near: documentPoint, threshold: threshold) else {
            setElementSelection(strokeIDs: [], textIDs: [])
            return nil
        }
        selectStrokeConsideringGroups(hit.id)
        return hit
    }

    /// Updates `selectedStrokeID`, clearing anchor/fillet selections whenever the stroke changes.
    private func setSelectedStrokeID(_ id: UUID?) {
        if selectedStrokeID != id {
            clearToolSelections()
        }
        selectedStrokeID = id
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

    func clearPrintSelection() {
        printSelectedStrokeID = nil
        printSelectedTextID = nil
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

    #if canImport(UIKit)
    /// Unified print-layout selection: prefers a hit text element, otherwise
    /// falls back to stroke hit testing. Text and strokes each keep their own
    /// print selection slot; selecting one kind clears the other.
    @discardableResult
    func selectPrintElement(near documentPoint: CGPoint, threshold: CGFloat) -> ElementHit {
        for element in visibleTextElements().reversed() {
            let transform = effectivePrintTransform(for: element.id)
            let affine = PrintLayoutCoordinateSpace.textPrintTransform(for: element, transform: transform)
            let local = documentPoint.applying(affine.inverted())
            if element.contains(local) {
                printSelectedTextID = element.id
                printSelectedStrokeID = nil
                return .text(element.id)
            }
        }
        if let stroke = selectPrintStroke(near: documentPoint, threshold: threshold) {
            printSelectedTextID = nil
            return .stroke(stroke.id)
        }
        printSelectedTextID = nil
        return .none
    }
    #endif

    func selectPrintStroke(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        for stroke in printLayoutStrokes().reversed() {
            let transformed = transformedPrintStroke(stroke)
            if transformed.contains(documentPoint) {
                printSelectedStrokeID = stroke.id
                return stroke
            }
        }

        var best: VectorStroke?
        var bestDistance = threshold
        for stroke in printLayoutStrokes().reversed() {
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
        printLayoutRevision += 1
    }

    func allPrintLayoutPoints() -> [CGPoint] {
        var points: [CGPoint] = []
        for stroke in printLayoutStrokes() {
            points.append(contentsOf: ShapeGeometry.renderPoints(for: transformedPrintStroke(stroke)))
        }
        for element in visibleTextElements() {
            points.append(contentsOf: PrintLayoutCoordinateSpace.transformedTextCorners(
                element,
                transform: effectivePrintTransform(for: element.id)
            ))
        }
        let gridBounds = PrintPageGridEngine.gridBounds(for: printLayout)
        points.append(contentsOf: [
            gridBounds.origin,
            CGPoint(x: gridBounds.maxX, y: gridBounds.maxY)
        ])
        return points
    }

    /// Cut tool: slices every print-layout stroke that crosses the printable-margin
    /// line nearest `point` (in document/print-grid space) into independent pieces.
    /// Print-layout-only — the underlying design strokes are hidden, not mutated.
    @discardableResult
    func cutAlongNearestPrintBorder(near point: CGPoint, threshold: CGFloat) -> Bool {
        let rects = PrintPageGridEngine.printableRects(for: printLayout)
        guard !rects.isEmpty else { return false }

        let coordinateEpsilon: CGFloat = 0.5
        func dedupe(_ values: [CGFloat]) -> [CGFloat] {
            var result: [CGFloat] = []
            for value in values.sorted() {
                if let last = result.last, abs(last - value) <= coordinateEpsilon { continue }
                result.append(value)
            }
            return result
        }
        let verticals = dedupe(rects.flatMap { [$0.minX, $0.maxX] })
        let horizontals = dedupe(rects.flatMap { [$0.minY, $0.maxY] })

        var bestAxis: PrintSliceEngine.Axis?
        var bestCoordinate: CGFloat = 0
        var bestDistance = threshold
        for x in verticals where abs(x - point.x) < bestDistance {
            bestDistance = abs(x - point.x)
            bestAxis = .vertical
            bestCoordinate = x
        }
        for y in horizontals where abs(y - point.y) < bestDistance {
            bestDistance = abs(y - point.y)
            bestAxis = .horizontal
            bestCoordinate = y
        }
        guard let axis = bestAxis else { return false }
        let coordinate = bestCoordinate

        var newPieces: [VectorStroke] = []
        var hideIDs: [UUID] = []
        var removePieceIDs: [UUID] = []

        for stroke in printLayoutStrokes() {
            let strokeInP = transformedPrintStroke(stroke)
            guard let fragments = PrintSliceEngine.slice(strokeInP, axis: axis, coordinate: coordinate) else {
                continue
            }
            // Convert each fragment from print-grid space back to base space so that
            // `effectivePrintTransform` (identity per-piece + contentOffset) re-places it
            // exactly where the sliced portion was — no visual jump.
            let offset = printLayout.contentOffset
            let basePieces = fragments.map { piece -> VectorStroke in
                var copy = piece
                copy.points = piece.points.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
                if !copy.cutoutPoints.isEmpty {
                    copy.cutoutPoints = copy.cutoutPoints.map { contour in
                        contour.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
                    }
                }
                return copy
            }
            if strokes.contains(where: { $0.id == stroke.id }) {
                hideIDs.append(stroke.id)
            } else {
                removePieceIDs.append(stroke.id)
            }
            newPieces.append(contentsOf: basePieces)
        }

        guard !newPieces.isEmpty else { return false }

        pushUndo()

        for id in hideIDs {
            printHiddenStrokeIDs.insert(id)
        }
        if !removePieceIDs.isEmpty {
            let removeSet = Set(removePieceIDs)
            printPieces.removeAll { removeSet.contains($0.id) }
            for id in removePieceIDs {
                printStrokeTransforms.removeValue(forKey: id)
                if printSelectedStrokeID == id { printSelectedStrokeID = nil }
            }
        }
        printPieces.append(contentsOf: newPieces)

        var settings = printLayout
        settings.activeTool = .select
        printLayout = settings
        printSelectedStrokeID = nil
        printSelectedTextID = nil
        printLayoutRevision += 1
        geometryRevision += 1
        return true
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
            groups: groups,
            layerGroups: layerGroups,
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
            printPieces: printPieces,
            printHiddenStrokeIDs: printHiddenStrokeIDs,
            dimensionOffsets: dimensionOffsets
        )
    }

    private func apply(_ snapshot: DocumentSnapshot) {
        layers = snapshot.layers
        strokes = snapshot.strokes
        textElements = snapshot.textElements
        groups = snapshot.groups
        layerGroups = snapshot.layerGroups
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
        printPieces = snapshot.printPieces
        printHiddenStrokeIDs = snapshot.printHiddenStrokeIDs
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
    var groups: [ObjectGroup] = []
    var layerGroups: [LayerGroup] = []
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
    var printPieces: [VectorStroke] = []
    var printHiddenStrokeIDs: Set<UUID> = []
    var dimensionOffsets: [String: CGPoint] = [:]
}
