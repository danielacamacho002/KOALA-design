//
//  KoalaDocument.swift
//  Koala
//

import CoreGraphics
import Foundation
import Observation
import SwiftUI

@Observable
final class KoalaDocument {
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

    var strokeWidth: CGFloat = VectorStroke.defaultStrokeWidth
    var strokeColor: CodableColor = CodableColor(.primary)
    /// Session-only. While Move is dragging a selection, motion locks to the
    /// nearer of the X or Y axis after a short threshold. Not persisted.
    var moveAxisLockEnabled = false
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
                selectedReferenceImageID = nil
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
    var endpointSnapEnabled: Bool = false
    var midpointSnapEnabled: Bool = false
    var intersectionSnapEnabled: Bool = false
    /// Curved-geometry snap toggles: circle/ellipse/arc center, and on-rim / compass snap.
    var centerSnapEnabled: Bool = false
    var quadrantSnapEnabled: Bool = false
    var dimensionsVisible: Bool = false
    // Document-space offsets of dragged dimension labels, keyed by "<strokeID>:<dimensionID>".
    var dimensionOffsets: [String: CGPoint] = [:]
    // Dimensions whose edge is pinned, keyed the same way. A pinned edge stays put when
    // the perpendicular dimension is edited.
    var dimensionLocks: Set<String> = []
    /// Labels that stay on screen after leaving the Dimensions tool, keyed the same way
    /// as `dimensionLocks`. Persisted and undone.
    var pinnedVisibleDimensionKeys: Set<String> = []
    /// Session-only: which dimension labels are on screen. Not persisted or undone.
    var revealedDimensionKeys: Set<String> = []
    var scaleUniform: Bool = true
    var selectedAnchorIndices: Set<Int> = []
    var selectedFilletCornerIndices: Set<Int> = []
    /// When set, move-tool rotation pivots around this anchor index; nil uses shape center.
    var moveRotationPivotAnchorIndex: Int?
    /// Degrees the current multi-selection has been rotated since it was selected.
    /// Session-only; the rotate stepper shows this while the group handle is used.
    var groupHandleRotationDegrees: Double?
    /// Session clipboard for copying items from one layer and pasting onto another.
    /// Not persisted; switching layers clears selection, so copies live here until paste.
    var clipboard: ElementClipboard = ElementClipboard()
    /// Currently selected drawing or edit tool. Defaults to Move (select/edit).
    /// Clearing a tool always falls back here so the canvas is never tool-less.
    var activeCategory: ToolCategory? = .move
    /// Move is the idle default, so its toolbar icon stays off until the user
    /// taps it or starts using it. Launch and "exit tool → Move" leave this false.
    var isMoveToolHighlighted = false
    /// When true, the Move tool shows the rotation handle. Off by default so
    /// the handle is not in the way during ordinary move/edit.
    var isMoveRotateMode = false
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
                selectedReferenceImageID = nil
            } else {
                selectedTextIDs = []
            }
        }
    }
    var activeFontRef: FontRef = .default
    var activeFontSize: CGFloat = 24
    /// Defaults applied to the next text placed with the Type tool.
    var activeTextIsOutline = false
    var activeTextStrokeWidth: CGFloat = TextElement.defaultStrokeWidth
    var referenceImages: [ReferenceImage] = []
    var selectedReferenceImageID: UUID?

    var printLayout: PrintLayoutSettings = PrintLayoutSettings()
    var printStrokeTransforms: [UUID: PrintStrokeTransform] = [:]
    var printSelectedStrokeID: UUID?
    var printSelectedTextID: UUID?
    /// Full print-layout stroke selection. Always includes `printSelectedStrokeID`
    /// when a print stroke is selected.
    var printSelectedStrokeIDs: Set<UUID> = []
    /// Full print-layout text selection, kept in sync with `printSelectedTextID`.
    var printSelectedTextIDs: Set<UUID> = []
    var printLayoutRevision = 0
    /// Print-layout-only sliced fragments produced by the Cut tool. Each is a fresh
    /// polyline in base (design) space; laid over the design strokes and never
    /// mutating them, so Design mode stays fully intact.
    var printPieces: [VectorStroke] = []
    /// Original design strokes that have been cut and are hidden in Print Layout
    /// (replaced by their `printPieces`). They remain fully intact in Design mode.
    var printHiddenStrokeIDs: Set<UUID> = []
    /// Piece ID → original design stroke ID, so join/delete can prune cut fragments.
    var printPieceSourceIDs: [UUID: UUID] = [:]

    private var undoStack: [DocumentSnapshot] = []
    private var redoStack: [DocumentSnapshot] = []
    private let undoLimit = 50
    /// Live raster bytes by image id. Undo snapshots omit payloads; this map
    /// reattaches them so add/remove/move stay undoable without 50× copies.
    private var referenceImagePayloads: [UUID: Data] = [:]
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
        referenceImages = snapshot.resolvedReferenceImages()
        rememberReferenceImagePayloads(referenceImages)
        printLayout = snapshot.printLayout
        printStrokeTransforms = snapshot.printStrokeTransforms
        printPieces = snapshot.printPieces
        printHiddenStrokeIDs = snapshot.printHiddenStrokeIDs
        printPieceSourceIDs = snapshot.printPieceSourceIDs ?? [:]
        dimensionOffsets = snapshot.dimensionOffsets
        dimensionLocks = snapshot.dimensionLocks ?? []
        pinnedVisibleDimensionKeys = snapshot.pinnedVisibleDimensionKeys ?? []
        syncGridFromSettings()
        normalizeLayerGrouping()
    }

    /// Rewrites sampled curves already stored in the file. Opening a project is
    /// enough; the piece does not have to be drawn again.
    func simplifyStoredDenseAnchors() -> Bool {
        var changed = false
        for index in strokes.indices {
            let simplified = ShapeGeometry.withSimplifiedDenseAnchors(strokes[index])
            if simplified != strokes[index] {
                strokes[index] = simplified
                changed = true
            }
        }
        if changed {
            geometryRevision += 1
        }
        return changed
    }

    func strokes(for layerID: UUID) -> [VectorStroke] {
        strokes.filter { $0.layerID == layerID }
    }

    /// Strokes on visible layers, ordered back-to-front by layer (index 0 = backmost layer),
    /// stable within a layer by insertion order.
    func visibleStrokes() -> [VectorStroke] {
        DocumentQueries.visibleStrokes(layers: layers, strokes: strokes)
    }

    /// Visible strokes on the active layer that isn't locked, for hit-testing/selection.
    /// Shapes on other layers are visible but not editable until their layer is active.
    func selectableStrokes() -> [VectorStroke] {
        visibleStrokes().filter(isSelectableStroke)
    }

    /// True when a stroke can be selected or edited on the current layer.
    func isSelectableStroke(_ stroke: VectorStroke) -> Bool {
        isSelectableLayer(stroke.layerID)
    }

    /// True when a text element can be selected or edited on the current layer.
    func isSelectableText(_ text: TextElement) -> Bool {
        isSelectableLayer(text.layerID)
    }

    func isSelectableReferenceImage(_ image: ReferenceImage) -> Bool {
        isSelectableLayer(image.layerID)
    }

    /// Active layer that is visible and unlocked.
    func isSelectableLayer(_ layerID: UUID) -> Bool {
        guard layerID == activeLayerID,
              let layer = layers.first(where: { $0.id == layerID }) else { return false }
        return layer.isVisible && !layer.isLocked
    }

    /// Visible strokes on the active layer and any layers stacked in front of it.
    /// Back-layer geometry stays drawn but does not steal taps or block empty canvas.
    func occupyingStrokes() -> [VectorStroke] {
        let order = layerIndexByID()
        let activeIndex = order[activeLayerID] ?? 0
        return visibleStrokes().filter { (order[$0.layerID] ?? 0) >= activeIndex }
    }

    /// Visible text on the active layer and any layers stacked in front of it.
    func occupyingTextElements() -> [TextElement] {
        let order = layerIndexByID()
        let activeIndex = order[activeLayerID] ?? 0
        return visibleTextElements().filter { (order[$0.layerID] ?? 0) >= activeIndex }
    }

    /// Rasters rebound onto a known layer so hide/opacity/hit-testing match strokes.
    func resolvedReferenceImages() -> [ReferenceImage] {
        DocumentQueries.bindReferenceImages(referenceImages, layers: layers, fallback: activeLayerID)
    }

    func visibleReferenceImages() -> [ReferenceImage] {
        DocumentQueries.visibleReferenceImages(layers: layers, images: resolvedReferenceImages())
    }

    func referenceImages(for layerID: UUID) -> [ReferenceImage] {
        resolvedReferenceImages().filter { $0.layerID == layerID }
    }

    /// Visible images on the active layer and any layers stacked in front of it.
    func occupyingReferenceImages() -> [ReferenceImage] {
        let order = layerIndexByID()
        let activeIndex = order[activeLayerID] ?? 0
        return visibleReferenceImages().filter { (order[$0.layerID] ?? 0) >= activeIndex }
    }

    /// Geometry that editing tools, snaps, and constraints may interact with.
    /// Restricted to the active, visible, unlocked layer so other layers stay fully
    /// independent until they are grouped and merged into this one.
    func interactiveStrokes() -> [VectorStroke] {
        selectableStrokes()
    }

    func stroke(with id: UUID) -> VectorStroke? {
        strokes.first { $0.id == id }
    }

    /// Single source of truth for what Print Layout renders/selects/exports:
    /// visible design strokes that have not been cut, followed by print-layout pieces
    /// (filtered to visible layers). Design mode never uses this.
    func printLayoutStrokes() -> [VectorStroke] {
        DocumentQueries.printLayoutStrokes(
            layers: layers,
            strokes: strokes,
            printPieces: printPieces,
            printHiddenStrokeIDs: printHiddenStrokeIDs
        )
    }

    /// Resolves a print-layout stroke id, preferring pieces over design strokes.
    func printLayoutStroke(with id: UUID) -> VectorStroke? {
        if let piece = printPieces.first(where: { $0.id == id }) { return piece }
        return strokes.first { $0.id == id }
    }

    // MARK: - Layers

    private func layerIndexByID() -> [UUID: Int] {
        DocumentQueries.layerIndexByID(layers)
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
        let removedStrokeIDs = Set(strokes.filter { $0.layerID == id }.map(\.id))
        let removedTextIDs = Set(textElements.filter { $0.layerID == id }.map(\.id))
        layers.remove(at: index)
        strokes.removeAll { $0.layerID == id }
        textElements.removeAll { $0.layerID == id }
        referenceImages.removeAll { $0.layerID == id }
        pruneGroups()
        retireDesignStrokeIDs(removedStrokeIDs, textIDs: removedTextIDs, droppedLayerID: id)
        if let selected = selectedStrokeID, stroke(with: selected) == nil {
            selectedStrokeID = nil
        }
        if let selectedText = selectedTextID, textElement(with: selectedText) == nil {
            selectedTextID = nil
        }
        if let selectedImage = selectedReferenceImageID, referenceImage(with: selectedImage) == nil {
            selectedReferenceImageID = nil
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
        if !layers[index].isVisible,
           let selected = selectedReferenceImage,
           selected.layerID == id {
            selectedReferenceImageID = nil
        }
        geometryRevision += 1
    }

    func toggleLayerLock(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        layers[index].isLocked.toggle()
        geometryRevision += 1
    }

    /// Resolved 0...1 opacity for a layer; missing layers are treated as fully opaque.
    func opacity(forLayerID id: UUID) -> CGFloat {
        DocumentQueries.opacity(layers: layers, forLayerID: id)
    }

    func setLayerOpacity(id: UUID, opacity: CGFloat, recordUndo: Bool = true) {
        setLayersOpacity(ids: [id], opacity: opacity, recordUndo: recordUndo)
    }

    func setLayersOpacity(ids: Set<UUID>, opacity: CGFloat, recordUndo: Bool = true) {
        let clamped = min(1, max(0, opacity))
        let targets = layers.indices.filter { ids.contains(layers[$0].id) && layers[$0].opacity != clamped }
        guard !targets.isEmpty else { return }
        if recordUndo { pushUndo() }
        for i in targets {
            layers[i].opacity = clamped
        }
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
        } else if let imageID = selectedReferenceImageID,
                  referenceImage(with: imageID)?.layerID != id {
            selectedReferenceImageID = nil
        }
    }

    /// Replaces the layer stack with a reordered copy of the same layers (index 0 = backmost).
    /// A drag records undo on the first step only, so the whole reorder is one undo.
    func reorderLayers(_ newOrder: [Layer], recordUndo: Bool = true) {
        guard newOrder.map(\.id) != layers.map(\.id),
              Set(newOrder.map(\.id)) == Set(layers.map(\.id)),
              newOrder.count == layers.count else { return }
        if recordUndo { pushUndo() }
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

    /// Cascades an opacity change to every layer in the folder.
    func setLayerGroupOpacity(id: UUID, opacity: CGFloat, recordUndo: Bool = true) {
        setLayersOpacity(ids: Set(layers(inGroup: id).map(\.id)), opacity: opacity, recordUndo: recordUndo)
    }

    /// Merges the given layers into a single layer, preserving the visual
    /// front/back stacking of their contents. The front-most selected layer is
    /// kept as the destination (its name, visibility, lock, opacity, and folder
    /// stay); the others are removed. Returns the surviving layer's id.
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
        referenceImages = mergedContentPreservingOrder(referenceImages, mergedIDs: mergedIDs, targetID: targetID, order: order,
                                                       layerID: { $0.layerID }, setLayerID: { $0.layerID = $1 })

        layers.removeAll { mergedIDs.contains($0.id) && $0.id != targetID }
        pruneGroups()
        if let selected = selectedStrokeID, stroke(with: selected) == nil { selectedStrokeID = nil }
        if let selectedText = selectedTextID, textElement(with: selectedText) == nil { selectedTextID = nil }
        if let selectedImage = selectedReferenceImageID, referenceImage(with: selectedImage) == nil {
            selectedReferenceImageID = nil
        }
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
        DocumentQueries.visibleTextElements(layers: layers, textElements: textElements)
    }

    /// Visible text elements on the active layer that isn't locked, for hit-testing/selection.
    /// Text on other layers is visible but not editable until its layer is active.
    func selectableTextElements() -> [TextElement] {
        visibleTextElements().filter(isSelectableText)
    }

    func textElement(with id: UUID) -> TextElement? {
        textElements.first { $0.id == id }
    }

    func addTextElement(_ element: TextElement) {
        pushUndo()
        textElements.append(element)
        geometryRevision += 1
    }

    /// Builds a text element using the Type tool's current font, color, outline, and stroke defaults.
    func makeTextElement(at position: CGPoint, layerID: UUID? = nil) -> TextElement {
        TextElement(
            layerID: layerID ?? activeLayerID,
            text: "",
            position: position,
            fontRef: activeFontRef,
            fontSize: activeFontSize,
            color: strokeColor,
            strokeColor: strokeColor,
            strokeWidth: activeTextStrokeWidth,
            isOutline: activeTextIsOutline
        )
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
        pruneRevealedDimensions(forElementID: id)
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

    // MARK: - Reference image

    private static let minReferenceImageDimension: CGFloat = 8
    private static let additionalImageStagger: CGFloat = 36

    var hasReferenceImage: Bool { !referenceImages.isEmpty }

    var isReferenceImageSelected: Bool { selectedReferenceImageID != nil }

    /// Combined stroke/text selection plus the imported image, used by move/scale chrome.
    var hasCanvasSelection: Bool {
        !selectionIsEmpty || isReferenceImageSelected
    }

    var selectedReferenceImage: ReferenceImage? {
        guard let id = selectedReferenceImageID else { return nil }
        return referenceImage(with: id)
    }

    var resolvedReferenceImageFrame: CGRect? {
        guard let frame = selectedReferenceImage?.frame ?? referenceImages.last?.frame,
              frame.width > 0, frame.height > 0 else {
            return nil
        }
        return frame
    }

    func referenceImage(with id: UUID) -> ReferenceImage? {
        referenceImages.first { $0.id == id }
    }

    /// Front-most occupying imported image under `point` (last in the array is on top).
    func referenceImageHit(at point: CGPoint) -> ReferenceImage? {
        occupyingReferenceImages().reversed().first { $0.contains(point) }
    }

    func referenceImageContains(_ point: CGPoint) -> Bool {
        referenceImageHit(at: point) != nil
    }

    func referenceImageCorners() -> [CGPoint]? {
        guard let image = selectedReferenceImage,
              image.frame.width > 0, image.frame.height > 0 else { return nil }
        return image.corners()
    }

    func selectReferenceImage() {
        guard let id = selectedReferenceImageID ?? referenceImages.last?.id,
              referenceImage(with: id) != nil else {
            selectedReferenceImageID = nil
            return
        }
        selectReferenceImage(id: id)
    }

    func selectReferenceImage(id: UUID) {
        guard referenceImage(with: id) != nil else {
            selectedReferenceImageID = nil
            return
        }
        setElementSelection(strokeIDs: [], textIDs: [])
        selectedReferenceImageID = id
    }

    func setReferenceImageFrame(_ frame: CGRect, id: UUID? = nil, recordUndo: Bool = false) {
        guard let index = targetReferenceImageIndex(id: id) else { return }
        if recordUndo { pushUndo() }
        let width = max(abs(frame.width), Self.minReferenceImageDimension)
        let height = max(abs(frame.height), Self.minReferenceImageDimension)
        referenceImages[index].frame = CGRect(x: frame.minX, y: frame.minY, width: width, height: height)
    }

    func setReferenceImageRotation(radians: CGFloat, id: UUID? = nil, recordUndo: Bool = false) {
        guard let index = targetReferenceImageIndex(id: id) else { return }
        if recordUndo { pushUndo() }
        referenceImages[index].rotation = radians
        geometryRevision += 1
    }

    func setReferenceImageOpacity(_ opacity: CGFloat, id: UUID? = nil, recordUndo: Bool = false) {
        guard let index = targetReferenceImageIndex(id: id) else { return }
        if recordUndo { pushUndo() }
        referenceImages[index].opacity = min(1, max(0, opacity))
        geometryRevision += 1
    }

    func scaleReferenceImage(factorX: CGFloat, factorY: CGFloat, about center: CGPoint, id: UUID? = nil) {
        guard let index = targetReferenceImageIndex(id: id) else { return }
        let frame = referenceImages[index].frame
        let width = max(abs(frame.width * factorX), Self.minReferenceImageDimension)
        let height = max(abs(frame.height * factorY), Self.minReferenceImageDimension)
        setReferenceImageFrame(
            CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            ),
            id: referenceImages[index].id,
            recordUndo: false
        )
    }

    func removeReferenceImage(id: UUID? = nil, recordUndo: Bool = true) {
        let targetID = id ?? selectedReferenceImageID ?? referenceImages.last?.id
        guard let targetID, referenceImages.contains(where: { $0.id == targetID }) else { return }
        if recordUndo { pushUndo() }
        referenceImages.removeAll { $0.id == targetID }
        if selectedReferenceImageID == targetID {
            selectedReferenceImageID = nil
        }
        geometryRevision += 1
    }

    private func targetReferenceImageIndex(id: UUID?) -> Int? {
        if let id {
            return referenceImages.firstIndex { $0.id == id }
        }
        if let selected = selectedReferenceImageID {
            return referenceImages.firstIndex { $0.id == selected }
        }
        return referenceImages.indices.last
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

    func setTextFillColor(id: UUID, color: CodableColor, recordUndo: Bool = false) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index].color = color
        geometryRevision += 1
    }

    func setTextStrokeColor(id: UUID, color: CodableColor, recordUndo: Bool = false) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index].strokeColor = color
        geometryRevision += 1
    }

    func setTextStrokeWidth(id: UUID, width: CGFloat, recordUndo: Bool = false) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index].strokeWidth = max(0, width)
        geometryRevision += 1
    }

    func setTextOutline(id: UUID, isOutline: Bool, recordUndo: Bool = false) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        textElements[index].isOutline = isOutline
        geometryRevision += 1
    }

    // MARK: - Selected text styling (Move tool)

    /// Indices of the text elements in the current selection, in document order.
    private var selectedTextIndices: [Int] {
        textElements.indices.filter { selectedTextIDs.contains(textElements[$0].id) }
    }

    /// First selected text element in document order; the Move panel uses it as
    /// the representative whose values populate the style controls.
    var representativeSelectedText: TextElement? {
        textElements.first { selectedTextIDs.contains($0.id) }
    }

    /// Applies a font size to every selected text element as one undo step.
    func setSelectedTextsFontSize(_ size: CGFloat, recordUndo: Bool = false) {
        let indices = selectedTextIndices
        guard !indices.isEmpty else { return }
        if recordUndo { pushUndo() }
        for index in indices { textElements[index].fontSize = max(1, size) }
        geometryRevision += 1
    }

    /// Applies a fill color to every selected text element as one undo step.
    func setSelectedTextsFillColor(_ color: CodableColor, recordUndo: Bool = false) {
        let indices = selectedTextIndices
        guard !indices.isEmpty else { return }
        if recordUndo { pushUndo() }
        for index in indices { textElements[index].color = color }
        geometryRevision += 1
    }

    /// Applies a stroke color to every selected text element as one undo step.
    func setSelectedTextsStrokeColor(_ color: CodableColor, recordUndo: Bool = false) {
        let indices = selectedTextIndices
        guard !indices.isEmpty else { return }
        if recordUndo { pushUndo() }
        for index in indices { textElements[index].strokeColor = color }
        geometryRevision += 1
    }

    /// Applies a stroke weight to every selected text element as one undo step.
    func setSelectedTextsStrokeWidth(_ width: CGFloat, recordUndo: Bool = false) {
        let indices = selectedTextIndices
        guard !indices.isEmpty else { return }
        if recordUndo { pushUndo() }
        for index in indices { textElements[index].strokeWidth = max(0, width) }
        geometryRevision += 1
    }

    /// Applies outline (hollow) mode to every selected text element as one undo step.
    func setSelectedTextsOutline(_ isOutline: Bool, recordUndo: Bool = false) {
        let indices = selectedTextIndices
        guard !indices.isEmpty else { return }
        if recordUndo { pushUndo() }
        for index in indices { textElements[index].isOutline = isOutline }
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

    /// Merges imported artwork into the active layer. Vector items get new IDs;
    /// rasters are appended on the active layer. `offset` is added in document space.
    @discardableResult
    func importContent(_ content: ImportRouter.ImportedContent, offset: CGPoint = .zero) throws -> Int {
        let hasVectors = content.hasVectorContent
        if (hasVectors || content.hasReferenceImage) && activeLayer?.isLocked == true {
            throw ImportRouter.ImportError.layerLocked
        }
        guard hasVectors || content.hasReferenceImage else {
            throw ImportRouter.ImportError.noVectorContent
        }

        pushUndo()

        var newStrokeIDs: Set<UUID> = []
        var newTextIDs: Set<UUID> = []

        for stroke in content.strokes {
            var copy = stroke.duplicated(offset: offset)
            copy.layerID = activeLayerID
            strokes.append(ShapeGeometry.captureRotationBaseIfNeeded(copy))
            newStrokeIDs.insert(copy.id)
        }
        for text in content.textElements {
            var copy = text
            copy.id = UUID()
            copy.layerID = activeLayerID
            copy.position = CGPoint(x: copy.position.x + offset.x, y: copy.position.y + offset.y)
            textElements.append(copy)
            newTextIDs.insert(copy.id)
        }
        for image in content.referenceImages {
            let stagger = CGFloat(referenceImages.count) * Self.additionalImageStagger
            var copy = image
            copy.id = UUID()
            copy.layerID = activeLayerID
            copy.frame = copy.frame.offsetBy(dx: offset.x + stagger, dy: offset.y + stagger)
            referenceImages.append(copy)
        }

        geometryRevision += 1
        if !newStrokeIDs.isEmpty || !newTextIDs.isEmpty {
            setElementSelection(strokeIDs: newStrokeIDs, textIDs: newTextIDs, compactAnchors: false)
        } else if let lastImage = referenceImages.last, content.hasReferenceImage {
            selectReferenceImage(id: lastImage.id)
        }
        return newStrokeIDs.count + newTextIDs.count
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
            let points = stroke.points
            guard points.count >= 3, let first = points.first, let last = points.last else { return }
            let gap = hypot(first.x - last.x, first.y - last.y)
            guard gap <= connectTolerance else { return }
            var length: CGFloat = 0
            for index in 0..<(points.count - 1) {
                length += hypot(points[index + 1].x - points[index].x, points[index + 1].y - points[index].y)
            }
            // A V / star point whose feet sit in the same grid cell is not a loop.
            guard gap <= max(1, min(connectTolerance, length * 0.05)) else { return }
            stroke.isClosed = true
            stroke.points.removeLast()
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
        compactCircularAnchors(for: selectedStrokeIDs)
    }

    /// Rewrites tessellated circular runs back to the default 4 / 2–4 anchors so
    /// move and node-edit operate on the same compact set the overlay shows.
    ///
    /// User cubics are left alone. A garment curve's anchors often sit near some
    /// circle, and rewriting that cubic as an arc on select or drag-start collapses
    /// the bulge before Join or Move ever runs.
    func compactCircularAnchors(for ids: Set<UUID>) {
        var changed = false
        for id in ids {
            guard let index = strokes.firstIndex(where: { $0.id == id }) else { continue }
            let stroke = strokes[index]
            let compacted = ShapeGeometry.withCompactedCircularAnchors(
                stroke,
                rewritingPartialRuns: false,
                preservingBezierHandles: true
            )
            if compacted != stroke {
                strokes[index] = compacted
                changed = true
            }
        }
        if changed {
            geometryRevision += 1
        }
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

    func isDimensionLocked(key: String) -> Bool {
        dimensionLocks.contains(key)
    }

    func isDimensionRevealed(key: String) -> Bool {
        revealedDimensionKeys.contains(key)
    }

    func isDimensionPinnedVisible(key: String) -> Bool {
        pinnedVisibleDimensionKeys.contains(key)
    }

    /// True when the Dimensions tool is showing this label, or the eye is holding it on screen.
    func isDimensionShown(key: String) -> Bool {
        revealedDimensionKeys.contains(key) || pinnedVisibleDimensionKeys.contains(key)
    }

    func hasRevealedDimensions(for elementID: UUID) -> Bool {
        let prefix = elementID.uuidString + ":"
        return revealedDimensionKeys.contains { $0.hasPrefix(prefix) }
    }

    func revealDimension(key: String) {
        revealedDimensionKeys.insert(key)
    }

    func hideDimension(key: String) {
        revealedDimensionKeys.remove(key)
        guard pinnedVisibleDimensionKeys.contains(key) else { return }
        pushUndo()
        pinnedVisibleDimensionKeys.remove(key)
    }

    func clearRevealedDimensions() {
        revealedDimensionKeys.removeAll()
    }

    func revealAllDimensions(for stroke: VectorStroke) {
        for dimension in ShapeGeometry.semanticDimensions(for: stroke) {
            revealedDimensionKeys.insert(
                Self.dimensionOffsetKey(strokeID: stroke.id, dimensionID: dimension.id)
            )
        }
    }

    func revealAllTextDimensions(for textID: UUID) {
        for dimensionID in ["text-width", "text-height"] {
            revealedDimensionKeys.insert(
                Self.dimensionOffsetKey(strokeID: textID, dimensionID: dimensionID)
            )
        }
    }

    /// Auto-shows dimensions for any currently selected simple shape or text box.
    func revealDimensionsForCurrentSelection() {
        for id in selectedStrokeIDs {
            if let stroke = stroke(with: id), ShapeGeometry.showsDimensionsAutomatically(stroke) {
                revealAllDimensions(for: stroke)
            }
        }
        for id in selectedTextIDs {
            revealAllTextDimensions(for: id)
        }
    }

    func pruneRevealedDimensions(forElementID id: UUID) {
        let prefix = id.uuidString + ":"
        revealedDimensionKeys = revealedDimensionKeys.filter { !$0.hasPrefix(prefix) }
        pinnedVisibleDimensionKeys = pinnedVisibleDimensionKeys.filter { !$0.hasPrefix(prefix) }
    }

    enum DimensionTapResult {
        case revealedEdge
        case hiddenEdge
        case autoRevealed
        case selectedComplex
        case dismissed
        case ignored
    }

    /// Dimensions-mode tap: reveal or hide a specific edge, auto-show simple shapes,
    /// accumulate across shapes, and clear unpinned labels on an empty-canvas tap.
    @discardableResult
    func handleDimensionTap(at documentPoint: CGPoint, threshold: CGFloat) -> DimensionTapResult {
        if isHitOnInactiveLayer(near: documentPoint, threshold: threshold) {
            return .ignored
        }

        if let hit = nearestDimensionOutlineHit(at: documentPoint, threshold: threshold) {
            setElementSelection(strokeIDs: [hit.stroke.id], textIDs: [])
            if ShapeGeometry.showsDimensionsAutomatically(hit.stroke) {
                revealAllDimensions(for: hit.stroke)
                return .autoRevealed
            }
            let key = Self.dimensionOffsetKey(strokeID: hit.stroke.id, dimensionID: hit.dimensionID)
            if revealedDimensionKeys.contains(key) {
                hideDimension(key: key)
                return .hiddenEdge
            }
            revealDimension(key: key)
            return .revealedEdge
        }

        if let text = textElement(at: documentPoint) {
            setElementSelection(strokeIDs: [], textIDs: [text.id])
            revealAllTextDimensions(for: text.id)
            return .autoRevealed
        }

        if let fill = strokeFillHit(at: documentPoint) {
            setElementSelection(strokeIDs: [fill.id], textIDs: [])
            if ShapeGeometry.showsDimensionsAutomatically(fill) {
                revealAllDimensions(for: fill)
                return .autoRevealed
            }
            return .selectedComplex
        }

        clearRevealedDimensions()
        clearElementSelection()
        return .dismissed
    }

    /// Closest outline/edge among selectable strokes. Simple shapes report a dummy
    /// dimension id because any outline tap reveals every measurement.
    private func nearestDimensionOutlineHit(
        at documentPoint: CGPoint,
        threshold: CGFloat
    ) -> (stroke: VectorStroke, dimensionID: String)? {
        var best: (stroke: VectorStroke, dimensionID: String)?
        var bestDistance = threshold
        for stroke in occupyingStrokes().reversed() {
            guard isSelectableStroke(stroke) else { continue }
            if ShapeGeometry.showsDimensionsAutomatically(stroke) {
                let distance = stroke.distance(to: documentPoint)
                if distance < bestDistance {
                    bestDistance = distance
                    best = (stroke, "")
                }
            } else if let hit = ShapeGeometry.nearestSegmentDimension(
                on: stroke,
                to: documentPoint,
                threshold: bestDistance
            ) {
                bestDistance = hit.distance
                best = (stroke, hit.dimension.id)
            }
        }
        return best
    }

    /// Toggles a pin. `unlocking` names the opposite edge, released in the same undo
    /// step so both edges of an axis can never be pinned at once.
    func toggleDimensionLock(key: String, unlocking: String? = nil, recordUndo: Bool = true) {
        if recordUndo { pushUndo() }
        if dimensionLocks.contains(key) {
            dimensionLocks.remove(key)
        } else {
            dimensionLocks.insert(key)
            if let unlocking {
                dimensionLocks.remove(unlocking)
            }
        }
        geometryRevision += 1
    }

    /// Toggles whether this label stays visible after leaving the Dimensions tool.
    func toggleDimensionPinnedVisible(key: String, recordUndo: Bool = true) {
        if recordUndo { pushUndo() }
        if pinnedVisibleDimensionKeys.contains(key) {
            pinnedVisibleDimensionKeys.remove(key)
        } else {
            pinnedVisibleDimensionKeys.insert(key)
        }
    }

    func translateStroke(id: UUID, delta: CGPoint, recordUndo: Bool = false) {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        if recordUndo { pushUndo() }
        strokes[index] = strokes[index].offsettingGeometry(by: delta)
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
        var appliedByCorner: [Int: CGFloat] = [:]
        for cornerIndex in requestedCorners {
            let applied = FilletPathBuilder.clampedFilletRadius(
                for: updated,
                cornerIndex: cornerIndex,
                requested: r
            )
            overrides[cornerIndex] = applied
            appliedByCorner[cornerIndex] = applied
        }
        overrides = overrides.filter { validCornerIndices.contains($0.key) }

        // If every valid corner receives the same value, store it as the global base radius.
        // The value is the drawn radius, not the raw request, so a drag past the corner's
        // maximum does not leave a larger number than the arc on screen.
        let epsilon: CGFloat = 0.0001
        if requestedCorners == validCornerIndices {
            let appliedValues = requestedCorners.compactMap { appliedByCorner[$0] }
            if let first = appliedValues.first,
               appliedValues.count == requestedCorners.count,
               appliedValues.allSatisfy({ abs($0 - first) <= epsilon }) {
                updated.cornerRadius = first
            } else {
                updated.cornerRadius = 0
            }
        }

        // Keep only overrides that differ from the global radius. Zero is kept only when needed
        // to override a positive global radius on an individual corner.
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
        guard let id = selectedStrokeID else { return }
        compactCircularAnchors(for: [id])
        guard let stroke = stroke(with: id),
              let updated = StrokeEditor.deletePoint(stroke, at: pointIndex) else { return }
        pushUndo()
        updateStroke(updated, recordUndo: false)
        ClosedShapeDetector.reconcile(document: self)
    }

    func deleteStrokeEdge(at edgeIndex: Int) {
        guard let id = selectedStrokeID else { return }
        compactCircularAnchors(for: [id])
        guard let stroke = stroke(with: id),
              let updated = StrokeEditor.deleteEdge(stroke, edgeIndex: edgeIndex) else { return }
        pushUndo()
        updateStroke(updated, recordUndo: false)
        ClosedShapeDetector.reconcile(document: self)
    }

    /// Trim-tool tap that lands on an anchor: deletes the vertex. A corner removes the two
    /// edges that form it (reopening/splitting the path); a collinear point is removed without
    /// changing the shape. Returns `true` when the tap was on a vertex and handled.
    @discardableResult
    func deleteStrokeAnchor(near documentPoint: CGPoint, threshold: CGFloat) -> Bool {
        guard let id = selectedStrokeID else { return false }
        compactCircularAnchors(for: [id])
        guard let stroke = stroke(with: id) else { return false }
        // Circles / ellipses / arcs are trimmed parametrically, not by anchor deletion.
        guard stroke.shapeType != .circle,
              stroke.shapeType != .ellipse,
              stroke.shapeType != .arc else { return false }

        guard let index = StrokeEditor.nearestTrimAnchorIndex(
            in: stroke,
            point: documentPoint,
            threshold: threshold
        ) else { return false }

        let handles = StrokeEditor.handlePointsForEditing(stroke)
        guard handles.indices.contains(index) else { return false }
        let handle = handles[index]
        let handleDistance = hypot(handle.x - documentPoint.x, handle.y - documentPoint.y)
        // A filleted corner's anchor sits outside the outline — the arc cut that corner off —
        // so a tap out there never landed on the shape. Deleting it would drop both edges the
        // corner joins, which is how a single trim tap used to flatten a rounded rectangle.
        guard AnchorPointEngine.roundedOutlineDistance(from: stroke, to: handle) <= 0.01 else {
            return false
        }
        let droppingRedundant = PolygonBoolean.isRedundantContourVertex(
            handles,
            index: index,
            closed: stroke.isClosed
        )
        // Redundant leftovers on short tooth edges should still drop even if the tap
        // also projects onto the edge interior. Structural-corner taps keep the
        // mid-edge reject so an edge trim is not stolen by a nearby vertex.
        if !droppingRedundant,
           let edge = StrokeEditor.projectPointOnNearestEdge(
            in: stroke,
            point: documentPoint,
            threshold: threshold
        ), edge.t > 0.2, edge.t < 0.8 {
            let edgeDistance = hypot(edge.projected.x - documentPoint.x, edge.projected.y - documentPoint.y)
            if edgeDistance < handleDistance - 0.0001 { return false }
        }

        guard let result = StrokeEditor.deleteAnchor(stroke, at: index) else { return false }
        pushUndo()
        updateStroke(result.stroke, recordUndo: false)
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

    /// CAD-style trim: remove the contour span between cut points that bounds `documentPoint`.
    @discardableResult
    func trimAt(_ documentPoint: CGPoint, threshold: CGFloat) -> Bool {
        if isHitOnInactiveLayer(near: documentPoint, threshold: threshold) { return false }
        guard let result = TrimEngine.trim(
            at: documentPoint,
            threshold: threshold,
            strokes: interactiveStrokes(),
            preferredStrokeID: selectedStrokeID
        ) else { return false }

        pushUndo()
        if let index = strokes.firstIndex(where: { $0.id == result.strokeID }) {
            strokes[index] = compactedTrimLeftover(result.stroke)
        }
        var affected: Set<UUID> = [result.stroke.id]
        if let additional = result.additionalStroke {
            strokes.append(compactedTrimLeftover(additional))
            affected.insert(additional.id)
        }
        selectedStrokeID = result.stroke.id
        reconcileIntersectionAnchors(around: affected)
        ClosedShapeDetector.reconcile(document: self)
        DonutDetector.reconcile(document: self)
        geometryRevision += 1
        return true
    }

    /// A leftover whose fillet arcs are already stored as anchors is finished geometry:
    /// re-running circular run detection over it fits one wide arc across the straight
    /// edges between two fillets.
    private func compactedTrimLeftover(_ stroke: VectorStroke) -> VectorStroke {
        stroke.hasBakedSmoothCorners ? stroke : ShapeGeometry.withCompactedCircularAnchors(stroke)
    }

    /// Geometry of the span `trimAt` would remove at the same point. Read-only: no undo,
    /// no revision bump. Non-`nil` exactly when `trimAt` would accept the tap, so callers
    /// can use it to decide between trimming and the edge-delete fallback; a degenerate
    /// span comes back with no points rather than `nil`.
    func trimRemovalPreview(at documentPoint: CGPoint, threshold: CGFloat) -> TrimEngine.RemovedSegmentGeometry? {
        if isHitOnInactiveLayer(near: documentPoint, threshold: threshold) { return nil }
        guard let result = TrimEngine.trim(
            at: documentPoint,
            threshold: threshold,
            strokes: interactiveStrokes(),
            preferredStrokeID: selectedStrokeID
        ) else { return nil }
        return result.removedSegment
            ?? TrimEngine.RemovedSegmentGeometry(points: [], strokeWidth: result.stroke.strokeWidth)
    }

    func currentAnchorCount(for stroke: VectorStroke) -> Int {
        AnchorPointEngine.anchorCount(for: stroke)
    }

    @discardableResult
    func insertAnchor(
        at documentPoint: CGPoint,
        threshold: CGFloat,
        minimumSeparation: CGFloat = 0
    ) -> Bool {
        guard let id = selectedStrokeID else { return false }
        compactCircularAnchors(for: [id])
        guard let stroke = stroke(with: id),
              AnchorPointEngine.canEditAnchors(on: stroke),
              let updated = AnchorPointEngine.insertAtTap(
                  stroke: stroke,
                  point: documentPoint,
                  threshold: threshold,
                  minimumSeparation: minimumSeparation
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
    /// Off-layer items are dropped so Move/Edit cannot target another layer.
    func setElementSelection(strokeIDs: Set<UUID>, textIDs: Set<UUID>, compactAnchors: Bool = true) {
        let strokeIDs = strokeIDs.filter { stroke(with: $0).map(isSelectableStroke) ?? false }
        let textIDs = textIDs.filter { textElement(with: $0).map(isSelectableText) ?? false }
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
        selectedReferenceImageID = nil
        groupHandleRotationDegrees = nil
        clearAnchorSelection()
        if compactAnchors {
            compactCircularAnchors(for: strokeIDs)
        }
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
    /// Hits the front-most occupying shape first (active layer or anything stacked
    /// in front of it). A hit on a front layer is ignored instead of punching
    /// through to the active layer underneath.
    func strokeHit(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        guard let hit = topmostOccupyingStroke(near: documentPoint, threshold: threshold) else { return nil }
        return isSelectableStroke(hit) ? hit : nil
    }

    /// Stroke a tap should grab. Layers are walked front-to-back so a shape on a
    /// layer in front still blocks the active layer. Within one layer, an outline
    /// within `threshold` beats a containing fill, and otherwise the smallest
    /// containing shape wins so a line or shape inside a larger one can be selected.
    func topmostOccupyingStroke(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        preferredStrokeHit(in: occupyingStrokes(), near: documentPoint, threshold: threshold)
    }

    /// `strokes` are back-to-front. The first layer (front-most) with any hit wins.
    private func preferredStrokeHit(
        in strokes: [VectorStroke],
        near point: CGPoint,
        threshold: CGFloat
    ) -> VectorStroke? {
        let order = layerIndexByID()
        var byLayer: [UUID: [VectorStroke]] = [:]
        var layerIDs: [UUID] = []
        for stroke in strokes {
            if byLayer[stroke.layerID] == nil {
                layerIDs.append(stroke.layerID)
            }
            byLayer[stroke.layerID, default: []].append(stroke)
        }
        let frontToBack = layerIDs.sorted { (order[$0] ?? 0) > (order[$1] ?? 0) }
        for layerID in frontToBack {
            if let hit = Self.preferredStrokeHit(
                inLayer: byLayer[layerID] ?? [],
                near: point,
                threshold: threshold
            ) {
                return hit
            }
        }
        return nil
    }

    /// `strokes` are back-to-front within a single layer. Closest outline within
    /// `threshold` wins; exact distance ties stay front-most. Otherwise the
    /// smallest containing fill wins, and equal areas stay front-most.
    private static func preferredStrokeHit(
        inLayer strokes: [VectorStroke],
        near point: CGPoint,
        threshold: CGFloat
    ) -> VectorStroke? {
        var bestOutline: VectorStroke?
        var bestDistance = threshold
        for stroke in strokes.reversed() {
            let distance = stroke.distance(to: point)
            if distance < bestDistance {
                bestDistance = distance
                bestOutline = stroke
            }
        }
        if let bestOutline {
            return bestOutline
        }

        var bestFill: VectorStroke?
        var bestArea = CGFloat.greatestFiniteMagnitude
        for stroke in strokes.reversed() {
            guard stroke.contains(point) else { continue }
            let area = visibleHitArea(of: stroke)
            if bestFill == nil || area < bestArea {
                bestArea = area
                bestFill = stroke
            }
        }
        return bestFill
    }

    /// Bounding area of the drawn outline. Circles and curves store a few anchors
    /// whose box is smaller than the shape you see.
    private static func visibleHitArea(of stroke: VectorStroke) -> CGFloat {
        let points = ShapeGeometry.renderPoints(for: stroke)
        guard let first = points.first else { return .greatestFiniteMagnitude }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else { return .greatestFiniteMagnitude }
        return width * height
    }

    /// Topmost stroke whose outline is within `threshold` of the point, ignoring fill.
    /// Used by the Delete tool to distinguish an edge/line tap from an interior fill tap.
    func strokeOutlineHit(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        var best: VectorStroke?
        var bestDistance = threshold
        for stroke in occupyingStrokes().reversed() {
            let distance = stroke.distance(to: documentPoint)
            if distance < bestDistance {
                bestDistance = distance
                best = stroke
            }
        }
        guard let best, isSelectableStroke(best) else { return nil }
        return best
    }

    /// Topmost closed stroke whose filled interior contains the point, ignoring outline proximity.
    func strokeFillHit(at documentPoint: CGPoint) -> VectorStroke? {
        guard let hit = occupyingStrokes().reversed().first(where: { $0.contains(documentPoint) }) else { return nil }
        return isSelectableStroke(hit) ? hit : nil
    }

    /// Non-mutating topmost element hit (text preferred over strokes, image behind both).
    func elementHit(near documentPoint: CGPoint, threshold: CGFloat) -> ElementHit {
        switch occupyingElementHit(near: documentPoint, threshold: threshold) {
        case .text(let id):
            guard let text = textElement(with: id), isSelectableText(text) else { return .none }
            return .text(id)
        case .stroke(let id):
            guard let stroke = stroke(with: id), isSelectableStroke(stroke) else { return .none }
            return .stroke(id)
        case .referenceImage(let id):
            guard let image = referenceImage(with: id), isSelectableReferenceImage(image) else { return .none }
            return .referenceImage(id)
        case .none:
            return .none
        }
    }

    /// Front-most text or stroke on the active layer or stacked in front of it;
    /// imported images are hit only when nothing vector is on top of the point.
    func occupyingElementHit(near documentPoint: CGPoint, threshold: CGFloat) -> ElementHit {
        if let text = occupyingTextElements().reversed().first(where: { $0.contains(documentPoint) }) {
            return .text(text.id)
        }
        if let stroke = topmostOccupyingStroke(near: documentPoint, threshold: threshold) {
            return .stroke(stroke.id)
        }
        if let image = occupyingReferenceImages().reversed().first(where: { $0.contains(documentPoint) }) {
            return .referenceImage(image.id)
        }
        return .none
    }

    /// True when the front-most item under the point belongs to a layer in front of
    /// the active one (or the active layer is locked). Taps like this must not
    /// select, delete, or punch through.
    func isHitOnInactiveLayer(near documentPoint: CGPoint, threshold: CGFloat) -> Bool {
        switch occupyingElementHit(near: documentPoint, threshold: threshold) {
        case .none:
            return false
        case .stroke(let id):
            return stroke(with: id).map { !isSelectableStroke($0) } ?? false
        case .text(let id):
            return textElement(with: id).map { !isSelectableText($0) } ?? false
        case .referenceImage(let id):
            return referenceImage(with: id).map { !isSelectableReferenceImage($0) } ?? false
        }
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
        if let selected = selectedReferenceImage, selected.contains(point) {
            return true
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
        if strokeIDs.isEmpty, textIDs.isEmpty,
           let image = occupyingReferenceImages().reversed().first(where: {
               isSelectableReferenceImage($0) && Self.rectsOverlap($0.boundingBox(), rect)
           }) {
            selectReferenceImage(id: image.id)
            return
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
        let selected = strokes.filter { selectedStrokeIDs.contains($0.id) && isJoinable($0) }
        // Join welds geometry; only fuse shapes that already share a layer.
        guard let layerID = selected.first?.layerID else { return [] }
        return selected.filter { $0.layerID == layerID }
    }

    /// True when selected shapes can be fused: either two have anchors within
    /// snap tolerance, or two closed shapes overlap. Open vs closed does not
    /// matter for the anchor case — Join appears exactly when a fuse is possible.
    var canJoinSelection: Bool {
        let selected = joinableSelectedStrokes
        guard selected.count >= 2 else { return false }
        return PathJoinEngine.canJoin(selected, tolerance: grid.spacing * 0.5)
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
        let sharedTransform = sharedPrintTransform(for: removeIDs)
        strokes.removeAll { removeIDs.contains($0.id) }
        strokes.append(contentsOf: joined)
        pruneGroups()
        let joinedIDs = Set(joined.map(\.id))
        retireDesignStrokeIDs(removeIDs.subtracting(joinedIDs))
        if let sharedTransform, sharedTransform != .identity {
            for stroke in joined where !removeIDs.contains(stroke.id) {
                printStrokeTransforms[stroke.id] = sharedTransform
            }
            printLayoutRevision += 1
        }
        reconcileIntersectionAnchors(around: joinedIDs)
        geometryRevision += 1
        setElementSelection(strokeIDs: joinedIDs, textIDs: [])
        return true
    }

    /// True when any stroke, text element, or reference image is hidden from the canvas.
    var hasHiddenElements: Bool {
        strokes.contains { $0.isHiddenFromCanvas }
            || textElements.contains { $0.isHidden }
            || referenceImages.contains { $0.isHiddenFromCanvas }
    }

    /// True when every currently selected element is hidden.
    var selectedElementsAreHidden: Bool {
        if selectionIsEmpty {
            return selectedReferenceImage?.isHiddenFromCanvas == true
        }
        for id in selectedStrokeIDs {
            guard let stroke = stroke(with: id), stroke.isHiddenFromCanvas else { return false }
        }
        for id in selectedTextIDs {
            guard let text = textElement(with: id), text.isHidden else { return false }
        }
        return true
    }

    var canToggleElementVisibility: Bool {
        !selectionIsEmpty || isReferenceImageSelected || hasHiddenElements
    }

    /// Eye when the selection is visible; crossed-out eye when it is hidden
    /// (or when nothing is selected but hidden objects remain).
    var visibilityToolbarImage: String {
        let revealHidden = selectionIsEmpty && !isReferenceImageSelected && hasHiddenElements
        if selectedElementsAreHidden || revealHidden {
            return "eye.slash"
        }
        return "eye"
    }

    var visibilityToolbarAccessibilityLabel: String {
        if selectedElementsAreHidden {
            return "Show selection"
        }
        if selectionIsEmpty && !isReferenceImageSelected && hasHiddenElements {
            return "Show hidden objects"
        }
        return "Hide selection"
    }

    /// Hides or shows the current selection. With nothing selected, reveals every hidden object.
    func toggleSelectedElementsHidden() {
        if selectionIsEmpty && !isReferenceImageSelected {
            unhideAllElements()
            return
        }
        if selectedElementsAreHidden {
            unhideSelectedElements()
        } else {
            hideSelectedElements()
        }
    }

    /// Hides the current selection so it is omitted from canvas, hit-testing, and export.
    /// Selection is kept so the toolbar eye can toggle the same objects back on.
    func hideSelectedElements() {
        expandSelectionToGroupsIfNeeded()
        let imageID = selectionIsEmpty ? selectedReferenceImageID : nil
        guard !selectionIsEmpty || imageID != nil else { return }
        pushUndo()
        let strokeIDs = selectedStrokeIDs
        let textIDs = selectedTextIDs
        for index in strokes.indices where strokeIDs.contains(strokes[index].id) {
            strokes[index].isHidden = true
        }
        for index in textElements.indices where textIDs.contains(textElements[index].id) {
            textElements[index].isHidden = true
        }
        if let imageID, let index = referenceImages.firstIndex(where: { $0.id == imageID }) {
            referenceImages[index].isHidden = true
        }
        geometryRevision += 1
    }

    /// Reveals the currently selected hidden strokes, text, and reference image.
    func unhideSelectedElements() {
        expandSelectionToGroupsIfNeeded()
        let imageID = selectionIsEmpty ? selectedReferenceImageID : nil
        guard !selectionIsEmpty || imageID != nil else { return }
        pushUndo()
        let strokeIDs = selectedStrokeIDs
        let textIDs = selectedTextIDs
        for index in strokes.indices where strokeIDs.contains(strokes[index].id) {
            strokes[index].isHidden = false
        }
        for index in textElements.indices where textIDs.contains(textElements[index].id) {
            textElements[index].isHidden = false
        }
        if let imageID, let index = referenceImages.firstIndex(where: { $0.id == imageID }) {
            referenceImages[index].isHidden = false
        }
        geometryRevision += 1
    }

    /// Reveals every hidden stroke, text element, and reference image in one undoable step.
    func unhideAllElements() {
        guard hasHiddenElements else { return }
        pushUndo()
        for index in strokes.indices where strokes[index].isHiddenFromCanvas {
            strokes[index].isHidden = false
        }
        for index in textElements.indices where textElements[index].isHidden {
            textElements[index].isHidden = false
        }
        for index in referenceImages.indices where referenceImages[index].isHiddenFromCanvas {
            referenceImages[index].isHidden = false
        }
        geometryRevision += 1
    }

    /// Deletes every selected stroke and text element in one undoable step.
    func deleteSelectedElements() {
        if isReferenceImageSelected && selectionIsEmpty {
            removeReferenceImage()
            return
        }
        expandSelectionToGroupsIfNeeded()
        guard !selectionIsEmpty else { return }
        pushUndo()
        let strokeIDs = selectedStrokeIDs
        let textIDs = selectedTextIDs
        strokes.removeAll { strokeIDs.contains($0.id) }
        textElements.removeAll { textIDs.contains($0.id) }
        pruneGroups()
        retireDesignStrokeIDs(strokeIDs, textIDs: textIDs)
        isSyncingSelection = true
        selectedStrokeIDs = []
        selectedTextIDs = []
        selectedStrokeID = nil
        selectedTextID = nil
        isSyncingSelection = false
        selectedReferenceImageID = nil
        clearAnchorSelection()
        geometryRevision += 1
    }

    /// Copies the current selection (including any parent groups) into the session clipboard.
    /// Geometry stays in place; paste assigns new IDs on the active layer.
    @discardableResult
    func copySelectedElementsToClipboard() -> Int {
        expandSelectionToGroupsIfNeeded()
        guard !selectionIsEmpty else { return 0 }
        let copiedStrokes = strokes.filter { selectedStrokeIDs.contains($0.id) }
        let copiedText = textElements.filter { selectedTextIDs.contains($0.id) }
        let copiedGroups = groups.filter { group in
            group.strokeIDs.contains(where: selectedStrokeIDs.contains)
                || group.textIDs.contains(where: selectedTextIDs.contains)
        }
        clipboard = ElementClipboard(
            strokes: copiedStrokes,
            textElements: copiedText,
            groups: copiedGroups
        )
        return clipboard.itemCount
    }

    /// True when the clipboard has content and the active layer can receive it.
    var canPasteClipboard: Bool {
        !clipboard.isEmpty && activeLayer?.isLocked != true
    }

    /// Pastes clipboard contents onto the active layer, one grid step down and to
    /// the right of the copied position. Returns the number of items created, or 0
    /// when paste is not possible.
    @discardableResult
    func pasteClipboardToActiveLayer() -> Int {
        guard canPasteClipboard else { return 0 }
        pushUndo()

        let step = max(grid.spacing, 1)
        let offset = CGPoint(x: step, y: step)
        var strokeIDMap: [UUID: UUID] = [:]
        var textIDMap: [UUID: UUID] = [:]
        var newStrokeIDs: Set<UUID> = []
        var newTextIDs: Set<UUID> = []

        for stroke in clipboard.strokes {
            var copy = stroke.duplicated(offset: offset)
            strokeIDMap[stroke.id] = copy.id
            copy.layerID = activeLayerID
            strokes.append(ShapeGeometry.captureRotationBaseIfNeeded(copy))
            newStrokeIDs.insert(copy.id)
        }
        for text in clipboard.textElements {
            var copy = text
            let newID = UUID()
            textIDMap[text.id] = newID
            copy.id = newID
            copy.layerID = activeLayerID
            copy.position = CGPoint(x: copy.position.x + offset.x, y: copy.position.y + offset.y)
            textElements.append(copy)
            newTextIDs.insert(newID)
        }
        for group in clipboard.groups {
            let mappedStrokes = group.strokeIDs.compactMap { strokeIDMap[$0] }
            let mappedTexts = group.textIDs.compactMap { textIDMap[$0] }
            guard mappedStrokes.count + mappedTexts.count >= 2 else { continue }
            groups.append(ObjectGroup(strokeIDs: mappedStrokes, textIDs: mappedTexts))
        }

        geometryRevision += 1
        setElementSelection(strokeIDs: newStrokeIDs, textIDs: newTextIDs)
        return clipboard.itemCount
    }

    /// Duplicates the selection and selects the copies.
    /// `offset` is `.zero` for an in-place duplicate; Mirror passes the reflection shift.
    /// Copies geometry and modifiers as-is (fillets, holes, curve handles, rotation).
    func duplicateSelectedElements(offset: CGPoint) {
        expandSelectionToGroupsIfNeeded()
        guard !selectionIsEmpty else { return }
        pushUndo()

        let sourceStrokeIDs = selectedStrokeIDs
        let sourceTextIDs = selectedTextIDs
        let groupsToClone = groups.filter { group in
            group.strokeIDs.contains(where: sourceStrokeIDs.contains)
                || group.textIDs.contains(where: sourceTextIDs.contains)
        }

        var newStrokeIDs: Set<UUID> = []
        var newTextIDs: Set<UUID> = []
        var strokeIDMap: [UUID: UUID] = [:]
        var textIDMap: [UUID: UUID] = [:]

        for id in sourceStrokeIDs {
            guard let original = stroke(with: id) else { continue }
            let copy = original.duplicated(offset: offset)
            strokes.append(copy)
            strokeIDMap[id] = copy.id
            newStrokeIDs.insert(copy.id)
            copyStrokeMetadata(from: id, to: copy.id)
        }
        for id in sourceTextIDs {
            guard var copy = textElement(with: id) else { continue }
            copy.id = UUID()
            copy.position = CGPoint(x: copy.position.x + offset.x, y: copy.position.y + offset.y)
            textElements.append(copy)
            textIDMap[id] = copy.id
            newTextIDs.insert(copy.id)
        }

        for group in groupsToClone {
            let clonedStrokes = group.strokeIDs.compactMap { strokeIDMap[$0] }
            let clonedTexts = group.textIDs.compactMap { textIDMap[$0] }
            guard !clonedStrokes.isEmpty || !clonedTexts.isEmpty else { continue }
            groups.append(ObjectGroup(strokeIDs: clonedStrokes, textIDs: clonedTexts))
        }

        geometryRevision += 1
        setElementSelection(strokeIDs: newStrokeIDs, textIDs: newTextIDs)
    }

    /// Reflects a copy of the selection across one edge of its bounding box and
    /// selects the copy. Horizontal mirrors across the right edge; vertical across
    /// the bottom. The original stays put. One undo step covers the whole copy.
    func mirrorSelectedElements(horizontal: Bool = true) {
        expandSelectionToGroupsIfNeeded()
        guard let bbox = selectionBoundingBox() else { return }
        let span = horizontal ? bbox.width : bbox.height
        guard span > 1e-4 else { return }
        let offset = horizontal
            ? CGPoint(x: span, y: 0)
            : CGPoint(x: 0, y: span)
        duplicateSelectedElements(offset: offset)
        flipSelection(horizontal: horizontal, recordUndo: false)
    }

    /// Copies document-level per-stroke data (print placement, dimension pins) onto a clone.
    private func copyStrokeMetadata(from oldID: UUID, to newID: UUID) {
        if let transform = printStrokeTransforms[oldID] {
            printStrokeTransforms[newID] = transform
        }
        let oldPrefix = oldID.uuidString + ":"
        let newPrefix = newID.uuidString + ":"
        for (key, value) in dimensionOffsets where key.hasPrefix(oldPrefix) {
            let suffix = String(key.dropFirst(oldPrefix.count))
            dimensionOffsets[newPrefix + suffix] = value
        }
        for key in dimensionLocks where key.hasPrefix(oldPrefix) {
            let suffix = String(key.dropFirst(oldPrefix.count))
            dimensionLocks.insert(newPrefix + suffix)
        }
        for key in pinnedVisibleDimensionKeys where key.hasPrefix(oldPrefix) {
            let suffix = String(key.dropFirst(oldPrefix.count))
            pinnedVisibleDimensionKeys.insert(newPrefix + suffix)
        }
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
    func flipSelection(horizontal: Bool, recordUndo: Bool = true) {
        expandSelectionToGroupsIfNeeded()
        guard let bbox = selectionBoundingBox() else { return }
        if recordUndo { pushUndo() }
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

    /// Multiplies the current selection about its bounding-box center.
    /// Factors are relative to the geometry as it is now (`1` leaves an axis unchanged).
    /// A selected reference image scales about its own center. Text moves on both axes;
    /// its font size follows the vertical factor, or either factor when they match.
    /// One undo step covers the whole change. Returns false when nothing was scaled.
    @discardableResult
    func scaleSelectedElements(factorX: CGFloat, factorY: CGFloat, recordUndo: Bool = true) -> Bool {
        guard factorX.isFinite, factorY.isFinite, factorX > 0, factorY > 0 else { return false }
        guard abs(factorX - 1) > 1e-9 || abs(factorY - 1) > 1e-9 else { return false }

        if isReferenceImageSelected && selectionIsEmpty {
            guard let frame = resolvedReferenceImageFrame else { return false }
            if recordUndo { pushUndo() }
            scaleReferenceImage(
                factorX: factorX,
                factorY: factorY,
                about: CGPoint(x: frame.midX, y: frame.midY)
            )
            geometryRevision += 1
            return true
        }

        expandSelectionToGroupsIfNeeded()
        guard let bbox = selectionBoundingBox() else { return false }
        if recordUndo { pushUndo() }
        let center = CGPoint(x: bbox.midX, y: bbox.midY)
        let radiusScale = sqrt(factorX * factorY)

        func scaled(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: center.x + (point.x - center.x) * factorX,
                y: center.y + (point.y - center.y) * factorY
            )
        }

        for id in selectedStrokeIDs {
            guard let index = strokes.firstIndex(where: { $0.id == id }) else { continue }
            strokes[index].points = strokes[index].points.map(scaled)
            strokes[index].cutoutPoints = strokes[index].cutoutPoints.map { $0.map(scaled) }
            if let handles = strokes[index].curveHandles {
                strokes[index].curveHandles = handles.map { handle in
                    CurveHandle(
                        inOffset: CGPoint(x: handle.inOffset.x * factorX, y: handle.inOffset.y * factorY),
                        outOffset: CGPoint(x: handle.outOffset.x * factorX, y: handle.outOffset.y * factorY)
                    )
                }
            }
            strokes[index].cornerRadius *= radiusScale
            if let overrides = strokes[index].cornerRadiiByIndex {
                var scaledOverrides: [Int: CGFloat] = [:]
                for (corner, radius) in overrides {
                    scaledOverrides[corner] = radius * radiusScale
                }
                strokes[index].cornerRadiiByIndex = scaledOverrides
            }
        }

        let fontFactor = abs(factorX - factorY) <= 1e-6 ? abs(factorX) : abs(factorY)
        for id in selectedTextIDs {
            guard let index = textElements.firstIndex(where: { $0.id == id }) else { continue }
            let newCenter = scaled(textElements[index].center)
            textElements[index].fontSize = max(4, textElements[index].fontSize * fontFactor)
            let size = textElements[index].textSize()
            textElements[index].position = CGPoint(
                x: newCenter.x - size.width / 2,
                y: newCenter.y - size.height / 2
            )
        }
        if selectedTextIDs.count == 1,
           let id = selectedTextIDs.first,
           let text = textElement(with: id) {
            activeFontSize = text.fontSize
        }

        if selectedStrokeIDs.count == 1 && selectedTextIDs.isEmpty {
            reconcileIntersectionAnchors(around: selectedStrokeIDs)
        }
        geometryRevision += 1
        return true
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
            for id in group.strokeIDs {
                if let stroke = stroke(with: id), isSelectableStroke(stroke) {
                    resultStrokes.insert(id)
                }
            }
            for id in group.textIDs {
                if let text = textElement(with: id), isSelectableText(text) {
                    resultTexts.insert(id)
                }
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
    /// members a large, closed-shape-like hit area). Only members on the active
    /// layer count, so a group sitting entirely on another layer is not selectable.
    func group(at documentPoint: CGPoint) -> ObjectGroup? {
        groups.reversed().first { group in
            selectableGroupBoundingBox(group)?.contains(documentPoint) == true
        }
    }

    /// Bounds of a group's members that are currently selectable (active layer).
    private func selectableGroupBoundingBox(_ group: ObjectGroup) -> CGRect? {
        var rect: CGRect?
        for id in group.strokeIDs {
            guard let stroke = stroke(with: id), isSelectableStroke(stroke),
                  let bounds = stroke.boundingBox() else { continue }
            rect = rect.map { $0.union(bounds) } ?? bounds
        }
        for id in group.textIDs {
            guard let text = textElement(with: id), isSelectableText(text) else { continue }
            let bounds = text.boundingBox()
            rect = rect.map { $0.union(bounds) } ?? bounds
        }
        return rect
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
        guard let stroke = stroke(with: id), isSelectableStroke(stroke) else { return }
        if let group = group(containingStroke: id) {
            selectGroup(group)
        } else {
            setElementSelection(strokeIDs: [id], textIDs: [])
        }
    }

    /// Selects a text element, expanding to its parent group when it belongs to one.
    func selectTextConsideringGroups(_ id: UUID) {
        guard let text = textElement(with: id), isSelectableText(text) else { return }
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

    // MARK: - Stroke thickness editing

    /// Shared stroke width of the currently selected strokes, for display in the move panel.
    enum StrokeWidthSelection: Equatable {
        case none
        case uniform(CGFloat)
        case mixed
    }

    func selectedStrokeWidthSummary() -> StrokeWidthSelection {
        let ids = selectedStrokeIDs
        guard !ids.isEmpty else { return .none }
        var value: CGFloat?
        for id in ids {
            guard let stroke = stroke(with: id) else { continue }
            let width = stroke.strokeWidth
            if let existing = value {
                if abs(existing - width) > 0.0001 { return .mixed }
            } else {
                value = width
            }
        }
        guard let value else { return .none }
        return .uniform(value)
    }

    /// Representative width used to seed stepping/editing when the selection is mixed.
    func representativeSelectedStrokeWidth() -> CGFloat? {
        for id in selectedStrokeIDs {
            if let stroke = stroke(with: id) { return stroke.strokeWidth }
        }
        return nil
    }

    /// Sets the line thickness (document points) on every selected stroke.
    @discardableResult
    func setSelectedStrokesWidth(_ width: CGFloat, recordUndo: Bool = true) -> Bool {
        let ids = selectedStrokeIDs
        guard !ids.isEmpty else { return false }
        let clamped = max(0.1, width)
        let willChange = ids.contains { id in
            guard let stroke = stroke(with: id) else { return false }
            return abs(stroke.strokeWidth - clamped) > 0.0001
        }
        guard willChange else { return false }
        if recordUndo { pushUndo() }
        for id in ids {
            guard let index = strokes.firstIndex(where: { $0.id == id }) else { continue }
            strokes[index].strokeWidth = clamped
        }
        geometryRevision += 1
        return true
    }

    // MARK: - Stroke color editing

    /// Shared line/border color of the currently selected strokes, for display in the move panel.
    enum StrokeColorSelection: Equatable {
        case none
        case uniform(CodableColor)
        case mixed
    }

    func selectedStrokeColorSummary() -> StrokeColorSelection {
        let ids = selectedStrokeIDs
        guard !ids.isEmpty else { return .none }
        var value: CodableColor?
        for id in ids {
            guard let stroke = stroke(with: id) else { continue }
            if let existing = value {
                if existing != stroke.strokeColor { return .mixed }
            } else {
                value = stroke.strokeColor
            }
        }
        guard let value else { return .none }
        return .uniform(value)
    }

    /// Representative color used to seed the picker when the selection is mixed.
    func representativeSelectedStrokeColor() -> CodableColor? {
        for id in selectedStrokeIDs {
            if let stroke = stroke(with: id) { return stroke.strokeColor }
        }
        return nil
    }

    /// Sets the line/border color on every selected stroke.
    @discardableResult
    func setSelectedStrokesColor(_ color: CodableColor, recordUndo: Bool = true) -> Bool {
        let ids = selectedStrokeIDs
        guard !ids.isEmpty else { return false }
        let willChange = ids.contains { id in
            guard let stroke = stroke(with: id) else { return false }
            return stroke.strokeColor != color
        }
        guard willChange else { return false }
        if recordUndo { pushUndo() }
        for id in ids {
            guard let index = strokes.firstIndex(where: { $0.id == id }) else { continue }
            strokes[index].strokeColor = color
        }
        geometryRevision += 1
        return true
    }

    // MARK: - Fill opacity editing

    /// Selected strokes that are closed planes (and therefore have an editable fill).
    func closedFillableSelectedStrokeIDs() -> [UUID] {
        selectedStrokeIDs.compactMap { id in
            guard let stroke = stroke(with: id), stroke.isClosed, !stroke.isConstruction else { return nil }
            return id
        }
    }

    var hasClosedFillableSelection: Bool {
        !closedFillableSelectedStrokeIDs().isEmpty
    }

    /// Shared fill opacity of the selected closed shapes, for display in the move panel.
    func selectedFillOpacitySummary() -> StrokeWidthSelection {
        let ids = closedFillableSelectedStrokeIDs()
        guard !ids.isEmpty else { return .none }
        var value: CGFloat?
        for id in ids {
            guard let stroke = stroke(with: id) else { continue }
            let opacity = stroke.resolvedFillOpacity
            if let existing = value {
                if abs(existing - opacity) > 0.001 { return .mixed }
            } else {
                value = opacity
            }
        }
        guard let value else { return .none }
        return .uniform(value)
    }

    func representativeSelectedFillOpacity() -> CGFloat? {
        for id in closedFillableSelectedStrokeIDs() {
            if let stroke = stroke(with: id) { return stroke.resolvedFillOpacity }
        }
        return nil
    }

    // MARK: - Fill color editing

    /// Shared fill color of the selected closed shapes. `uniform(nil)` is the default gray plane.
    enum FillColorSelection: Equatable {
        case none
        case uniform(CodableColor?)
        case mixed
    }

    func selectedFillColorSummary() -> FillColorSelection {
        let ids = closedFillableSelectedStrokeIDs()
        guard !ids.isEmpty else { return .none }
        var seen: CodableColor??
        for id in ids {
            guard let stroke = stroke(with: id) else { continue }
            if let existing = seen {
                if existing != stroke.fillColor { return .mixed }
            } else {
                seen = .some(stroke.fillColor)
            }
        }
        guard let seen else { return .none }
        return .uniform(seen)
    }

    /// Stored fill of the first selected closed shape. `nil` means the default gray plane.
    func representativeSelectedFillColor() -> CodableColor? {
        for id in closedFillableSelectedStrokeIDs() {
            if let stroke = stroke(with: id) { return stroke.fillColor }
        }
        return nil
    }

    /// Sets the fill color on every selected closed shape. Opacity stays on `fillOpacity`.
    @discardableResult
    func setSelectedStrokesFillColor(_ color: CodableColor, recordUndo: Bool = true) -> Bool {
        let ids = closedFillableSelectedStrokeIDs()
        guard !ids.isEmpty else { return false }
        let willChange = ids.contains { id in
            guard let stroke = stroke(with: id) else { return false }
            return stroke.fillColor != color
        }
        guard willChange else { return false }
        if recordUndo { pushUndo() }
        for id in ids {
            guard let index = strokes.firstIndex(where: { $0.id == id }) else { continue }
            strokes[index].fillColor = color
        }
        geometryRevision += 1
        return true
    }

    /// Sets the fill opacity (0...1) on every selected closed shape.
    @discardableResult
    func setSelectedStrokesFillOpacity(_ opacity: CGFloat, recordUndo: Bool = true) -> Bool {
        let ids = closedFillableSelectedStrokeIDs()
        guard !ids.isEmpty else { return false }
        let clamped = min(1, max(0, opacity))
        let willChange = ids.contains { id in
            guard let stroke = stroke(with: id) else { return false }
            return abs(stroke.resolvedFillOpacity - clamped) > 0.0001
        }
        guard willChange else { return false }
        if recordUndo { pushUndo() }
        for id in ids {
            guard let index = strokes.firstIndex(where: { $0.id == id }) else { continue }
            strokes[index].fillOpacity = clamped
        }
        geometryRevision += 1
        return true
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
        if category != .move {
            isMoveToolHighlighted = false
            isMoveRotateMode = false
        }
        if let lineVariant { self.lineVariant = lineVariant }
        if let circleVariant { self.circleVariant = circleVariant }
        if let rectangleVariant { self.rectangleVariant = rectangleVariant }
        // Unpinned labels hide when you leave Dimensions. Eye-pinned labels stay up
        // so a measurement can stay on screen while drawing.
        let showingDimensions = (category == .dimensions)
        dimensionsVisible = showingDimensions
        if !showingDimensions {
            revealedDimensionKeys = revealedDimensionKeys.intersection(pinnedVisibleDimensionKeys)
        }
    }

    func clearActiveTool() {
        isMoveToolHighlighted = false
        selectTool(.move)
    }

    func engageMoveTool() {
        selectTool(.move)
        isMoveToolHighlighted = true
    }

    var isDrawingToolActive: Bool {
        activeCategory?.isDrawingTool ?? false
    }

    func syncGridFromSettings() {
        grid.spacing = UnitConversion.visualGridSpacing(
            sliderValue: settings.defaultGridSpacingInUnits,
            unit: settings.units
        )
    }

    /// Applies defaults intended for newly created projects.
    /// - Parameters:
    ///   - canvasSize: Optional canvas dimensions in document points. Defaults to 24" × 18" when nil.
    ///   - units: Working measurement unit for the new project.
    func applyNewProjectDefaults(canvasSize: CGSize? = nil, units: MeasurementUnit = .inches) {
        settings.units = units
        settings.defaultGridSpacing = UnitConversion.pointsPerInch
        settings.allowsFingerDrawing = false
        if let canvasSize {
            settings.canvasWidth = canvasSize.width
            settings.canvasHeight = canvasSize.height
        }
        syncGridFromSettings()
    }

    func removeStroke(id: UUID) {
        guard strokes.contains(where: { $0.id == id }) else { return }
        pushUndo()
        strokes.removeAll { $0.id == id }
        pruneGroups()
        retireDesignStrokeIDs([id])
        if selectedStrokeID == id {
            clearToolSelections()
            selectedStrokeID = nil
        }
        pruneRevealedDimensions(forElementID: id)
        geometryRevision += 1
    }

    /// The two shapes an overlap tap would cut, before the user confirms.
    /// `baseID` stays and receives the hole or notch. `cutterID` is deleted.
    struct OverlapCutProposal: Equatable {
        var baseID: UUID
        var cutterID: UUID
    }

    /// Geometry for the overlap-cut preview. `keptContours` is the base after
    /// subtraction. When `punchesHole` is true the first contour is the outer
    /// outline and the rest are holes; otherwise each contour is a remaining piece.
    struct OverlapCutPreview: Equatable {
        var keptContours: [[CGPoint]]
        var punchesHole: Bool
        var cutterContour: [CGPoint]
    }

    /// Chip centers in document space. `kept` is the plus, `cut` is the minus,
    /// and `confirm` is the check.
    struct OverlapCutChipPoints: Equatable {
        var kept: CGPoint
        var cut: CGPoint
        var confirm: CGPoint
    }

    /// Which pair an overlap tap would cut, without changing the document.
    /// A clearly smaller shape inside a larger one is the cutter. Otherwise the
    /// front shape is the cutter and the shape under the tap is the base.
    func proposedOverlapCut(at documentPoint: CGPoint) -> OverlapCutProposal? {
        guard let pair = overlapCutPair(at: documentPoint) else { return nil }
        return OverlapCutProposal(baseID: pair.base.id, cutterID: pair.cutter.id)
    }

    /// Subtracts `cutterID` from `baseID` and deletes the cutter. Swapping the
    /// ids cuts the other way. Returns `true` when a subtraction was performed.
    @discardableResult
    func applyOverlapCut(baseID: UUID, cutterID: UUID) -> Bool {
        guard baseID != cutterID,
              let base = stroke(with: baseID),
              let cutter = stroke(with: cutterID),
              base.isClosed, cutter.isClosed,
              !base.isConstruction, !cutter.isConstruction else { return false }
        let baseContour = ShapeGeometry.renderPoints(for: base)
        let cutterContour = ShapeGeometry.renderPoints(for: cutter)
        guard baseContour.count >= 3, cutterContour.count >= 3 else { return false }
        guard let outcome = ShapeBooleanEngine.subtract(
            baseContour: baseContour,
            targetContour: cutterContour
        ) else { return false }
        guard let baseArrayIndex = strokes.firstIndex(where: { $0.id == base.id }) else { return false }

        pushUndo()
        applySubtraction(
            outcome,
            toBaseAt: baseArrayIndex,
            curvedAlong: cutterUsesCurve(cutter) ? cutterContour : nil
        )
        strokes.removeAll { $0.id == cutter.id }
        pruneGroups()
        retireDesignStrokeIDs([cutter.id])
        deselectStrokeAfterMutation(cutter.id)
        geometryRevision += 1
        return true
    }

    /// Interior fill tap for the Delete tool. Subtracts the proposed cutter from
    /// the base and removes the cutter. When the cutter sits fully inside the
    /// base a hole is punched; when it crosses the base's edge the outline is
    /// reshaped into the notch. Returns `true` when a subtraction was performed.
    @discardableResult
    func punchOverlapHole(at documentPoint: CGPoint) -> Bool {
        guard let proposal = proposedOverlapCut(at: documentPoint) else { return false }
        return applyOverlapCut(baseID: proposal.baseID, cutterID: proposal.cutterID)
    }

    /// Read-only result of subtracting `cutterID` from `baseID`, for the chooser preview.
    func overlapCutPreview(baseID: UUID, cutterID: UUID) -> OverlapCutPreview? {
        guard baseID != cutterID,
              let base = stroke(with: baseID),
              let cutter = stroke(with: cutterID) else { return nil }
        let baseContour = ShapeGeometry.renderPoints(for: base)
        let cutterContour = ShapeGeometry.renderPoints(for: cutter)
        guard baseContour.count >= 3, cutterContour.count >= 3 else { return nil }
        guard let outcome = ShapeBooleanEngine.subtract(
            baseContour: baseContour,
            targetContour: cutterContour
        ) else { return nil }

        switch outcome {
        case let .interiorHole(cutouts):
            var holes: [[CGPoint]] = []
            for cutout in base.cutoutPoints {
                let rendered = ShapeGeometry.renderPoints(
                    for: VectorStroke(
                        layerID: base.layerID,
                        points: cutout,
                        isClosed: true,
                        shapeType: .polyline
                    )
                )
                if rendered.count >= 3 { holes.append(rendered) }
            }
            holes.append(contentsOf: cutouts.filter { $0.count >= 3 })
            return OverlapCutPreview(
                keptContours: [baseContour] + holes,
                punchesHole: true,
                cutterContour: cutterContour
            )
        case let .boundaryCut(contours):
            let pieces = contours.map(\.points).filter { $0.count >= 3 }
            guard !pieces.isEmpty else { return nil }
            return OverlapCutPreview(
                keptContours: pieces,
                punchesHole: false,
                cutterContour: cutterContour
            )
        case .baseRemoved:
            return OverlapCutPreview(
                keptContours: [],
                punchesHole: false,
                cutterContour: cutterContour
            )
        }
    }

    /// Plus, minus, and check centers. The signs sit on each shape's own body,
    /// outside the overlap, unless that shape is fully inside the other — then
    /// its sign stays at the center. `minimumGap` keeps the chips from covering
    /// the check; pass a distance converted from view points.
    func overlapCutChipPoints(
        baseID: UUID,
        cutterID: UUID,
        tapPoint: CGPoint,
        minimumGap: CGFloat
    ) -> OverlapCutChipPoints? {
        guard let base = stroke(with: baseID), let cutter = stroke(with: cutterID) else { return nil }
        let separatedChips = separatedChipPair(
            exclusiveChipPoint(for: base, other: cutter),
            exclusiveChipPoint(for: cutter, other: base),
            minimumGap: minimumGap
        )
        var confirm = tapPoint
        confirm = separated(from: separatedChips.0, point: confirm, minimumGap: minimumGap)
        confirm = separated(from: separatedChips.1, point: confirm, minimumGap: minimumGap)
        return OverlapCutChipPoints(kept: separatedChips.0, cut: separatedChips.1, confirm: confirm)
    }

    /// The first base/cutter pair under `documentPoint` whose subtraction succeeds.
    private func overlapCutPair(
        at documentPoint: CGPoint
    ) -> (base: VectorStroke, cutter: VectorStroke)? {
        if isHitOnInactiveLayer(near: documentPoint, threshold: 0) { return nil }
        let candidates = selectableStrokes()
        let containing = candidates.enumerated().compactMap { index, stroke -> (index: Int, area: CGFloat)? in
            guard stroke.isClosed, !stroke.isConstruction, stroke.contains(documentPoint) else { return nil }
            return (index, Self.visibleHitArea(of: stroke))
        }
        guard containing.count >= 2 else { return nil }

        // A shape sitting inside a larger one is the cutter, even when the larger
        // shape was drawn later and its fill is in front. Otherwise the front-most
        // shape is the cutter and shapes beneath it are the bases, so a grid of
        // similar cells still cuts the one on top.
        let smallest = containing.min { $0.area < $1.area }!
        let largestArea = containing.map(\.area).max() ?? 0
        let targetIndex: Int
        let orderedBeneath: [Int]
        if smallest.area < largestArea * 0.98 {
            targetIndex = smallest.index
            let hosts = containing.filter { $0.index != smallest.index && $0.area > smallest.area }
            guard let host = hosts.min(by: { $0.area < $1.area }) else { return nil }
            orderedBeneath = [host.index]
        } else {
            guard let front = containing.max(by: { $0.index < $1.index }) else { return nil }
            targetIndex = front.index
            let beneath = Array(stride(from: targetIndex - 1, through: 0, by: -1))
            orderedBeneath = beneath.filter { candidates[$0].contains(documentPoint) }
                + beneath.filter { !candidates[$0].contains(documentPoint) }
        }

        let cutter = candidates[targetIndex]
        let cutterContour = ShapeGeometry.renderPoints(for: cutter)
        guard cutterContour.count >= 3 else { return nil }

        for index in orderedBeneath {
            let base = candidates[index]
            guard base.id != cutter.id, base.isClosed, !base.isConstruction else { continue }
            let baseContour = ShapeGeometry.renderPoints(for: base)
            guard baseContour.count >= 3 else { continue }
            guard ShapeBooleanEngine.subtract(
                baseContour: baseContour,
                targetContour: cutterContour
            ) != nil else { continue }
            return (base, cutter)
        }
        return nil
    }

    private func cutterUsesCurve(_ cutter: VectorStroke) -> Bool {
        switch cutter.shapeType {
        case .circle, .ellipse, .arc, .curve: return true
        default: return false
        }
    }

    /// A point on `shape` that is not inside `other`. A shape fully contained by
    /// `other` keeps its center.
    private func exclusiveChipPoint(for shape: VectorStroke, other: VectorStroke) -> CGPoint {
        let contour = ShapeGeometry.renderPoints(for: shape)
        let center = centroid(contour)
        guard contour.count >= 3 else { return center }
        // `contains` counts the boundary as inside, so a center sitting on the
        // other shape's edge still walks out into this shape's exclusive body.
        if !other.contains(center) { return center }

        var anchor: CGPoint?
        var bestDistance = -CGFloat.greatestFiniteMagnitude
        for point in contour where !other.contains(point) {
            let distance = hypot(point.x - center.x, point.y - center.y)
            if distance > bestDistance {
                bestDistance = distance
                anchor = point
            }
        }
        guard let anchor else { return center }

        var placed: CGPoint?
        for t in [CGFloat(0.08), 0.16, 0.28, 0.42] {
            let candidate = CGPoint(
                x: anchor.x + (center.x - anchor.x) * t,
                y: anchor.y + (center.y - anchor.y) * t
            )
            if other.contains(candidate) { break }
            if shape.contains(candidate) {
                placed = candidate
            }
        }
        return placed ?? center
    }

    private func separatedChipPair(
        _ kept: CGPoint,
        _ cut: CGPoint,
        minimumGap: CGFloat
    ) -> (CGPoint, CGPoint) {
        let dx = cut.x - kept.x
        let dy = cut.y - kept.y
        let distance = hypot(dx, dy)
        guard distance < minimumGap else { return (kept, cut) }
        if distance <= 0.001 {
            return (
                CGPoint(x: kept.x - minimumGap / 2, y: kept.y),
                CGPoint(x: cut.x + minimumGap / 2, y: cut.y)
            )
        }
        let push = (minimumGap - distance) / 2
        let ux = dx / distance
        let uy = dy / distance
        return (
            CGPoint(x: kept.x - ux * push, y: kept.y - uy * push),
            CGPoint(x: cut.x + ux * push, y: cut.y + uy * push)
        )
    }

    /// Moves `point` out to `minimumGap` from `origin` when it sits closer than that.
    private func separated(from origin: CGPoint, point: CGPoint, minimumGap: CGFloat) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let distance = hypot(dx, dy)
        guard distance < minimumGap else { return point }
        if distance <= 0.001 {
            return CGPoint(x: origin.x + minimumGap, y: origin.y)
        }
        let scale = minimumGap / distance
        return CGPoint(x: origin.x + dx * scale, y: origin.y + dy * scale)
    }

    /// Uses an open arc as a knife to slice the base into two pieces and remove the piece
    /// the user tapped. The arc cuts when it is "on the edge" — either it pokes through the
    /// boundary, or it lies inside with its endpoints on/near an edge (within `attachTol`).
    /// A fully-interior arc floating away from every edge leaves the shape untouched.
    /// Returns `true` when a slice occurred.
    @discardableResult
    func sliceArcCut(at documentPoint: CGPoint) -> Bool {
        if isHitOnInactiveLayer(near: documentPoint, threshold: 0) { return false }
        let candidates = selectableStrokes()
        let arcs = candidates.filter { $0.shapeType == .arc && !$0.isConstruction }
        guard !arcs.isEmpty else { return false }

        // Endpoints must sit within ~24pt (in document space) of the edge to count as
        // "on the edge" when the arc doesn't poke through the boundary.
        let attachTol = viewport.viewToDocument(distance: 24)

        for arc in arcs {
            let arcPoints = ShapeGeometry.renderPoints(for: arc)
            guard arcPoints.count >= 2 else { continue }

            for base in candidates where base.id != arc.id && base.isClosed && !base.isConstruction {
                guard base.contains(documentPoint) else { continue }
                let baseContour = ShapeGeometry.renderPoints(for: base)
                guard baseContour.count >= 3 else { continue }
                guard let pieces = PolygonBoolean.split(
                    polygon: baseContour,
                    byOpenPath: arcPoints,
                    maxEndpointAttach: attachTol
                ), pieces.count == 2 else { continue }
                guard let removeIndex = pieces.firstIndex(where: {
                    PolygonBoolean.pointInPolygon(documentPoint, $0)
                }) else { continue }
                guard let baseArrayIndex = strokes.firstIndex(where: { $0.id == base.id }) else { continue }

                let keepIndex = removeIndex == 0 ? 1 : 0
                let keptPiece = pieces[keepIndex]

                pushUndo()
                var updated = reshaped(
                    strokes[baseArrayIndex],
                    toPoints: keptPiece,
                    curvedAlong: arcPoints
                )
                // Keep holes only where they still fall inside the retained piece.
                updated.cutoutPoints = strokes[baseArrayIndex].cutoutPoints.filter { hole in
                    PolygonBoolean.pointInPolygon(centroid(hole), keptPiece)
                }
                strokes[baseArrayIndex] = updated
                strokes.removeAll { $0.id == arc.id }
                pruneGroups()
                deselectStrokeAfterMutation(arc.id)
                geometryRevision += 1
                return true
            }
        }
        return false
    }

    /// Mutates the base stroke at `baseArrayIndex` according to a Boolean subtraction
    /// outcome, spawning additional strokes when a cut splits the base into pieces.
    private func applySubtraction(
        _ outcome: ShapeBooleanEngine.Subtraction,
        toBaseAt baseArrayIndex: Int,
        curvedAlong cutter: [CGPoint]?
    ) {
        switch outcome {
        case let .interiorHole(cutouts):
            var updatedBase = strokes[baseArrayIndex]
            updatedBase.cutoutPoints.append(contentsOf: cutouts)
            strokes[baseArrayIndex] = updatedBase

        case let .boundaryCut(contours):
            guard let primary = contours.first else { return }
            let baseID = strokes[baseArrayIndex].id
            var updatedBase = reshaped(
                strokes[baseArrayIndex],
                toPoints: primary.points,
                curvedAlong: cutter,
                cutEdgeStarts: primary.cutEdgeStarts
            )
            // Keep existing holes only where they still fall inside the reshaped outline.
            updatedBase.cutoutPoints = updatedBase.cutoutPoints.filter { hole in
                let holeCenter = centroid(hole)
                return PolygonBoolean.pointInPolygon(holeCenter, primary.points)
            }
            strokes[baseArrayIndex] = updatedBase

            // Remaining contours are disjoint pieces carved off the original shape.
            let extraContours = contours.dropFirst()
            guard !extraContours.isEmpty else { return }
            var newPieces: [VectorStroke] = []
            for contour in extraContours {
                var piece = reshaped(
                    updatedBase,
                    toPoints: contour.points,
                    curvedAlong: cutter,
                    cutEdgeStarts: contour.cutEdgeStarts
                )
                piece.id = UUID()
                piece.cutoutPoints = []
                newPieces.append(piece)
            }
            let insertionIndex = min(baseArrayIndex + 1, strokes.count)
            strokes.insert(contentsOf: newPieces, at: insertionIndex)
            // New fragments join whatever group the base belonged to.
            for i in groups.indices where groups[i].strokeIDs.contains(baseID) {
                groups[i].strokeIDs.append(contentsOf: newPieces.map(\.id))
            }

        case .baseRemoved:
            let baseID = strokes[baseArrayIndex].id
            strokes.remove(at: baseArrayIndex)
            deselectStrokeAfterMutation(baseID)
        }
    }

    /// Returns a copy of `stroke` reshaped into an arbitrary closed contour, clearing
    /// parametric/shape-specific state so the Boolean-cut result renders as new geometry.
    ///
    /// When the Boolean tags which edges came from the cutter, a circular bite is stored
    /// as an arc whose endpoints stay corners. Straight corners of the base stay corners.
    /// Other curved cutters still get Bézier handles, and the simplifier refuses to
    /// round a sharp corner into that curve.
    private func reshaped(
        _ stroke: VectorStroke,
        toPoints points: [CGPoint],
        curvedAlong cutter: [CGPoint]? = nil,
        cutEdgeStarts: [Int] = []
    ) -> VectorStroke {
        var copy = stroke
        copy.points = points
        copy.isClosed = true
        copy.shapeRotation = nil
        copy.rotationBasePoints = nil
        copy.rotationBaseCenter = nil
        copy.cornerRadius = 0
        copy.cornerRadiiByIndex = nil
        copy.smoothCornerIndices = nil
        copy.openEdgeStarts = nil
        copy.openCutoutIndices = nil

        if let kept = ShapeBooleanEngine.cornerPreservingContour(
            points: points,
            cutEdgeStarts: cutEdgeStarts
        ) {
            copy.points = kept.points
            copy.shapeType = .polyline
            copy.curveHandles = nil
            copy.smoothCornerIndices = kept.smoothCornerIndices.isEmpty ? nil : kept.smoothCornerIndices
            return copy
        }

        if let cutter,
           let handles = curveHandlesAlongCutter(points: points, cutter: cutter) {
            copy.shapeType = .curve
            copy.curveHandles = handles
        } else {
            copy.shapeType = .polyline
            copy.curveHandles = nil
        }
        return ShapeGeometry.withCompactedCircularAnchors(copy)
    }

    /// Builds per-anchor Bézier handles that reproduce the curved cutter edge as a true
    /// curve while keeping straight base edges straight. An edge is "curved" when both its
    /// endpoints lie on the cutter outline; those runs get Catmull-Rom-style tangents,
    /// everything else stays a straight segment. Returns `nil` when nothing is curved so
    /// the caller keeps a plain polyline.
    private func curveHandlesAlongCutter(points: [CGPoint], cutter: [CGPoint]) -> [CurveHandle]? {
        let n = points.count
        guard n >= 3, cutter.count >= 2 else { return nil }
        let eps = max(0.05, boundingDiagonalOf(cutter) * 1e-3)
        let onCutter = points.map { distanceToPolyline($0, cutter) <= eps }

        // edgeCurved[i] describes the edge points[i] → points[(i + 1) % n].
        var edgeCurved = [Bool](repeating: false, count: n)
        var anyCurved = false
        for i in 0..<n where onCutter[i] && onCutter[(i + 1) % n] {
            edgeCurved[i] = true
            anyCurved = true
        }
        guard anyCurved else { return nil }

        var handles = [CurveHandle](repeating: CurveHandle(), count: n)
        for i in 0..<n {
            let prev = points[(i + n - 1) % n]
            let cur = points[i]
            let next = points[(i + 1) % n]
            let inCurved = edgeCurved[(i + n - 1) % n]   // edge prev → cur
            let outCurved = edgeCurved[i]                // edge cur → next
            if inCurved, outCurved {
                let tangent = CGPoint(x: (next.x - prev.x) / 6, y: (next.y - prev.y) / 6)
                handles[i] = CurveHandle(
                    inOffset: CGPoint(x: -tangent.x, y: -tangent.y),
                    outOffset: tangent
                )
            } else if outCurved {
                handles[i].outOffset = CGPoint(x: (next.x - cur.x) / 3, y: (next.y - cur.y) / 3)
            } else if inCurved {
                handles[i].inOffset = CGPoint(x: (prev.x - cur.x) / 3, y: (prev.y - cur.y) / 3)
            }
        }
        return handles
    }

    private func boundingDiagonalOf(_ points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return 0 }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return hypot(maxX - minX, maxY - minY)
    }

    private func distanceToPolyline(_ point: CGPoint, _ polyline: [CGPoint]) -> CGFloat {
        guard polyline.count >= 2 else {
            if let only = polyline.first { return hypot(point.x - only.x, point.y - only.y) }
            return .greatestFiniteMagnitude
        }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<(polyline.count - 1) {
            best = min(best, distanceFromPoint(point, toSegment: polyline[i], polyline[i + 1]))
        }
        return best
    }

    private func distanceFromPoint(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq <= .ulpOfOne { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var sum = CGPoint.zero
        for point in points {
            sum.x += point.x
            sum.y += point.y
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
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
        pruneRevealedDimensions(forElementID: id)
    }

    func selectStroke(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        if isHitOnInactiveLayer(near: documentPoint, threshold: threshold) {
            return nil
        }
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

    var printSelectionCount: Int {
        printSelectedStrokeIDs.count + printSelectedTextIDs.count
    }

    var printSelectionIsEmpty: Bool {
        printSelectedStrokeIDs.isEmpty && printSelectedTextIDs.isEmpty
    }

    var printSelectedIDs: Set<UUID> {
        printSelectedStrokeIDs.union(printSelectedTextIDs)
    }

    func printTransform(for strokeID: UUID) -> PrintStrokeTransform {
        printStrokeTransforms[strokeID] ?? .identity
    }

    func setPrintTransform(_ transform: PrintStrokeTransform, for strokeID: UUID, recordUndo: Bool = true) {
        setPrintTransforms([strokeID: transform], recordUndo: recordUndo)
    }

    func setPrintTransforms(_ transforms: [UUID: PrintStrokeTransform], recordUndo: Bool = true) {
        guard !transforms.isEmpty else { return }
        if recordUndo { pushUndo() }
        for (id, transform) in transforms {
            if transform == .identity {
                printStrokeTransforms.removeValue(forKey: id)
            } else {
                printStrokeTransforms[id] = transform
            }
        }
        printLayoutRevision += 1
    }

    func setPrintSelection(strokeIDs: Set<UUID>, textIDs: Set<UUID>) {
        let validStrokeIDs = Set(strokeIDs.filter { printLayoutStroke(with: $0) != nil })
        let validTextIDs = Set(textIDs.filter { textElement(with: $0) != nil })
        printSelectedStrokeIDs = validStrokeIDs
        printSelectedTextIDs = validTextIDs
        if let current = printSelectedStrokeID, validStrokeIDs.contains(current) {
            printSelectedStrokeID = current
        } else {
            printSelectedStrokeID = validStrokeIDs.first
        }
        if let current = printSelectedTextID, validTextIDs.contains(current) {
            printSelectedTextID = current
        } else {
            printSelectedTextID = validTextIDs.first
        }
        printLayoutRevision += 1
    }

    func togglePrintStrokeSelection(_ id: UUID) {
        var next = printSelectedStrokeIDs
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        setPrintSelection(strokeIDs: next, textIDs: printSelectedTextIDs)
    }

    func togglePrintTextSelection(_ id: UUID) {
        var next = printSelectedTextIDs
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        setPrintSelection(strokeIDs: printSelectedStrokeIDs, textIDs: next)
    }

    func clearPrintSelection() {
        setPrintSelection(strokeIDs: [], textIDs: [])
    }

    func rotatePrintSelection(
        by radians: CGFloat,
        around pivot: CGPoint,
        originTransforms: [UUID: PrintStrokeTransform],
        originCenters: [UUID: CGPoint],
        recordUndo: Bool = false
    ) {
        guard abs(radians) > 1e-12 else { return }
        let cosR = cos(radians)
        let sinR = sin(radians)
        var updates: [UUID: PrintStrokeTransform] = [:]
        for id in printSelectedIDs {
            guard var transform = originTransforms[id], let center = originCenters[id] else { continue }
            let dx = center.x - pivot.x
            let dy = center.y - pivot.y
            let newCenter = CGPoint(
                x: pivot.x + dx * cosR - dy * sinR,
                y: pivot.y + dx * sinR + dy * cosR
            )
            transform.rotation += radians
            transform.translation.x += newCenter.x - center.x
            transform.translation.y += newCenter.y - center.y
            updates[id] = transform
        }
        setPrintTransforms(updates, recordUndo: recordUndo)
    }

    /// Mirrors the print selection. A lone element flips in place; a multi-selection
    /// mirrors about its group bounding box so the arrangement mirrors too, matching
    /// how `rotatePrintSelection` pivots.
    func flipPrintSelection(horizontal: Bool) {
        let ids = printSelectedIDs
        guard !ids.isEmpty else { return }
        let pivot: CGPoint? = ids.count > 1
            ? printSelectionBoundingBox().map { CGPoint(x: $0.midX, y: $0.midY) }
            : nil

        var updates: [UUID: PrintStrokeTransform] = [:]
        for id in ids {
            var transform = printTransform(for: id)
            let before = printBounds(for: id)
            if horizontal {
                transform.flipHorizontal.toggle()
            } else {
                transform.flipVertical.toggle()
            }
            if let pivot, !before.isNull {
                let after = printBounds(for: id, storedTransform: transform)
                if !after.isNull {
                    let target = CGPoint(
                        x: horizontal ? 2 * pivot.x - before.midX : before.midX,
                        y: horizontal ? before.midY : 2 * pivot.y - before.midY
                    )
                    transform.translation.x += target.x - after.midX
                    transform.translation.y += target.y - after.midY
                }
            }
            updates[id] = transform
        }
        setPrintTransforms(updates, recordUndo: false)
    }

    func effectivePrintTransform(for strokeID: UUID) -> PrintStrokeTransform {
        DocumentQueries.effectivePrintTransform(
            printStrokeTransforms: printStrokeTransforms,
            contentOffset: printLayout.contentOffset,
            for: strokeID
        )
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
    /// Topmost print-layout hit without changing selection. Text is preferred over strokes.
    func hitPrintElement(near documentPoint: CGPoint, threshold: CGFloat) -> ElementHit {
        for element in visibleTextElements().reversed() {
            let transform = effectivePrintTransform(for: element.id)
            let affine = PrintLayoutCoordinateSpace.textPrintTransform(for: element, transform: transform)
            let local = documentPoint.applying(affine.inverted())
            if element.contains(local) {
                return .text(element.id)
            }
        }
        if let stroke = printStrokeHit(near: documentPoint, threshold: threshold) {
            return .stroke(stroke.id)
        }
        return .none
    }

    /// Tap-to-toggle print selection, matching design-canvas Move: add on a new
    /// hit, toggle off a member of a multi-selection, keep a lone selection, clear
    /// on empty canvas.
    func handlePrintSelectTap(near documentPoint: CGPoint, threshold: CGFloat) {
        switch hitPrintElement(near: documentPoint, threshold: threshold) {
        case .stroke(let id):
            if printSelectedStrokeIDs.contains(id) {
                if printSelectionCount > 1 { togglePrintStrokeSelection(id) }
            } else {
                togglePrintStrokeSelection(id)
            }
        case .text(let id):
            if printSelectedTextIDs.contains(id) {
                if printSelectionCount > 1 { togglePrintTextSelection(id) }
            } else {
                togglePrintTextSelection(id)
            }
        case .referenceImage, .none:
            // Print layout never hit-tests reference images, so this is a miss.
            clearPrintSelection()
        }
    }

    #endif

    func printStrokeHit(near documentPoint: CGPoint, threshold: CGFloat) -> VectorStroke? {
        let strokes = printLayoutStrokes()
        let placed = strokes.map { transformedPrintStroke($0) }
        guard let hit = preferredStrokeHit(in: placed, near: documentPoint, threshold: threshold) else {
            return nil
        }
        return strokes.first { $0.id == hit.id }
    }

    func selectPrintElements(in rect: CGRect) {
        var strokeIDs: Set<UUID> = []
        var textIDs: Set<UUID> = []
        for stroke in printLayoutStrokes() {
            let points = ShapeGeometry.renderPoints(for: transformedPrintStroke(stroke))
            let bbox = PrintLayoutCoordinateSpace.boundingRect(for: points)
            if !bbox.isNull, Self.rectsOverlap(bbox, rect) {
                strokeIDs.insert(stroke.id)
            }
        }
        for element in visibleTextElements() {
            let corners = PrintLayoutCoordinateSpace.transformedTextCorners(
                element,
                transform: effectivePrintTransform(for: element.id)
            )
            let bbox = PrintLayoutCoordinateSpace.boundingRect(for: corners)
            if !bbox.isNull, Self.rectsOverlap(bbox, rect) {
                textIDs.insert(element.id)
            }
        }
        setPrintSelection(strokeIDs: strokeIDs, textIDs: textIDs)
    }

    func printBounds(for id: UUID) -> CGRect {
        printBounds(for: id, storedTransform: printTransform(for: id))
    }

    /// Bounds under an arbitrary stored transform, so a candidate placement can be
    /// measured before it is committed.
    func printBounds(for id: UUID, storedTransform: PrintStrokeTransform) -> CGRect {
        var effective = storedTransform
        effective.translation = CGPoint(
            x: effective.translation.x + printLayout.contentOffset.x,
            y: effective.translation.y + printLayout.contentOffset.y
        )
        if let stroke = printLayoutStroke(with: id) {
            let transformed = PrintLayoutCoordinateSpace.transformedStroke(stroke, transform: effective)
            let points = ShapeGeometry.renderPoints(for: transformed)
            return PrintLayoutCoordinateSpace.boundingRect(for: points)
        }
        if let element = textElement(with: id) {
            let corners = PrintLayoutCoordinateSpace.transformedTextCorners(element, transform: effective)
            return PrintLayoutCoordinateSpace.boundingRect(for: corners)
        }
        return .null
    }

    func printSelectionBoundingBox() -> CGRect? {
        var rect: CGRect?
        for id in printSelectedIDs {
            let bbox = printBounds(for: id)
            guard !bbox.isNull else { continue }
            rect = rect.map { $0.union(bbox) } ?? bbox
        }
        return rect
    }

    /// True when `point` lands on the print selection, so a drag there moves it
    /// instead of starting a marquee. Tested per element: the union bounding box of
    /// a multi-selection would swallow the empty gaps between the shapes.
    func printSelectionContains(point: CGPoint, threshold: CGFloat) -> Bool {
        for id in printSelectedStrokeIDs {
            guard let stroke = printLayoutStroke(with: id) else { continue }
            let transformed = transformedPrintStroke(stroke)
            if transformed.contains(point) || transformed.distance(to: point) <= threshold {
                return true
            }
        }
        for id in printSelectedTextIDs {
            guard let element = textElement(with: id) else { continue }
            let affine = PrintLayoutCoordinateSpace.textPrintTransform(
                for: element,
                transform: effectivePrintTransform(for: id)
            )
            if element.contains(point.applying(affine.inverted())) {
                return true
            }
        }
        // A lone selection keeps its whole bounding box draggable, so hollow and
        // thin shapes stay easy to grab.
        if printSelectionCount == 1, let bbox = printSelectionBoundingBox() {
            return bbox.insetBy(dx: -threshold, dy: -threshold).contains(point)
        }
        return false
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

    /// Drops print-layout copies and transforms for design strokes that no longer exist.
    func retireDesignStrokeIDs(
        _ strokeIDs: Set<UUID>,
        textIDs: Set<UUID> = [],
        droppedLayerID: UUID? = nil
    ) {
        guard !strokeIDs.isEmpty || !textIDs.isEmpty || droppedLayerID != nil else { return }

        printHiddenStrokeIDs.subtract(strokeIDs)
        for id in strokeIDs { printStrokeTransforms.removeValue(forKey: id) }
        for id in textIDs { printStrokeTransforms.removeValue(forKey: id) }

        let pieceIDsToRemove = Set(printPieces.compactMap { piece -> UUID? in
            if let layerID = droppedLayerID, piece.layerID == layerID { return piece.id }
            if strokeIDs.contains(piece.id) { return piece.id }
            if let source = printPieceSourceIDs[piece.id], strokeIDs.contains(source) { return piece.id }
            return nil
        })
        if !pieceIDsToRemove.isEmpty {
            printPieces.removeAll { pieceIDsToRemove.contains($0.id) }
            for id in pieceIDsToRemove {
                printStrokeTransforms.removeValue(forKey: id)
                printPieceSourceIDs.removeValue(forKey: id)
            }
        }
        printPieceSourceIDs = printPieceSourceIDs.filter { !strokeIDs.contains($0.value) }

        // Selection settles last, and its own revision bump covers the pruning above.
        let retired = strokeIDs.union(textIDs).union(pieceIDsToRemove)
        setPrintSelection(
            strokeIDs: printSelectedStrokeIDs.subtracting(retired),
            textIDs: printSelectedTextIDs.subtracting(retired)
        )
    }

    private func sharedPrintTransform(for ids: Set<UUID>) -> PrintStrokeTransform? {
        guard let firstID = ids.first else { return nil }
        let first = printTransform(for: firstID)
        for id in ids where printTransform(for: id) != first {
            return nil
        }
        return first
    }

    /// Cut tool: slices the print-layout stroke nearest `point` that crosses the
    /// printable-margin line nearest the tap. Print-layout-only — design strokes
    /// are hidden, not mutated.
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

        var bestStroke: VectorStroke?
        var bestStrokeDistance = threshold
        for stroke in printLayoutStrokes() {
            let strokeInP = transformedPrintStroke(stroke)
            guard PrintSliceEngine.crosses(strokeInP, axis: axis, coordinate: coordinate) else {
                continue
            }
            let distance = strokeInP.contains(point) ? 0 : strokeInP.distance(to: point)
            if distance < bestStrokeDistance {
                bestStrokeDistance = distance
                bestStroke = stroke
            }
        }
        guard let stroke = bestStroke else { return false }

        let strokeInP = transformedPrintStroke(stroke)
        guard let fragments = PrintSliceEngine.slice(
            strokeInP,
            axis: axis,
            coordinate: coordinate,
            nearestCrossingTo: point
        ) else { return false }

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

        let sourceID: UUID
        var hideIDs: [UUID] = []
        var removePieceIDs: [UUID] = []
        if strokes.contains(where: { $0.id == stroke.id }) {
            sourceID = stroke.id
            hideIDs.append(stroke.id)
        } else {
            sourceID = printPieceSourceIDs[stroke.id] ?? stroke.id
            removePieceIDs.append(stroke.id)
        }

        pushUndo()

        for id in hideIDs {
            printHiddenStrokeIDs.insert(id)
        }
        if !removePieceIDs.isEmpty {
            let removeSet = Set(removePieceIDs)
            printPieces.removeAll { removeSet.contains($0.id) }
            for id in removePieceIDs {
                printStrokeTransforms.removeValue(forKey: id)
                printPieceSourceIDs.removeValue(forKey: id)
            }
        }
        printPieces.append(contentsOf: basePieces)
        for piece in basePieces {
            printPieceSourceIDs[piece.id] = sourceID
        }

        setPrintSelection(strokeIDs: Set(basePieces.map(\.id)), textIDs: [])
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
        groupHandleRotationDegrees = nil
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
        groupHandleRotationDegrees = nil
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

    /// Full snapshot including raster bytes; used by the codec, exporters, and last-saved tracking.
    func makeSnapshot() -> DocumentSnapshot {
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
            referenceImages: {
                let images = resolvedReferenceImages()
                return images.isEmpty ? nil : images
            }(),
            referenceImageData: nil,
            referenceImageFrame: nil,
            printLayout: printLayout,
            printStrokeTransforms: printStrokeTransforms,
            printPieces: printPieces,
            printHiddenStrokeIDs: printHiddenStrokeIDs,
            printPieceSourceIDs: printPieceSourceIDs,
            dimensionOffsets: dimensionOffsets,
            dimensionLocks: dimensionLocks,
            pinnedVisibleDimensionKeys: pinnedVisibleDimensionKeys
        )
    }

    /// Undo/redo snapshot. Omits raster bytes; codec and last-saved still include them.
    private func currentSnapshot() -> DocumentSnapshot {
        rememberReferenceImagePayloads(referenceImages)
        var snapshot = makeSnapshot()
        snapshot.referenceImages = snapshot.referenceImages?.map { $0.omittingPayload() }
        snapshot.referenceImageData = nil
        snapshot.referenceImageFrame = nil
        return snapshot
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
        applyReferenceImages(from: snapshot)
        printLayout = snapshot.printLayout
        printStrokeTransforms = snapshot.printStrokeTransforms
        printPieces = snapshot.printPieces
        printHiddenStrokeIDs = snapshot.printHiddenStrokeIDs
        printPieceSourceIDs = snapshot.printPieceSourceIDs ?? [:]
        dimensionOffsets = snapshot.dimensionOffsets
        dimensionLocks = snapshot.dimensionLocks ?? []
        pinnedVisibleDimensionKeys = snapshot.pinnedVisibleDimensionKeys ?? []
        syncGridFromSettings()
        printLayoutRevision += 1
    }

    private func rememberReferenceImagePayloads(_ images: [ReferenceImage]) {
        for image in images where !image.data.isEmpty {
            referenceImagePayloads[image.id] = image.data
        }
    }

    /// Restore image ids/frames/layers from the snapshot; reattach live bytes by id.
    private func applyReferenceImages(from snapshot: DocumentSnapshot) {
        rememberReferenceImagePayloads(referenceImages)
        let restored = snapshot.resolvedReferenceImages()
        rememberReferenceImagePayloads(restored)
        referenceImages = restored.map { image in
            guard image.data.isEmpty, let cached = referenceImagePayloads[image.id] else {
                return image
            }
            var copy = image
            copy.data = cached
            return copy
        }
        if let selected = selectedReferenceImageID,
           !referenceImages.contains(where: { $0.id == selected }) {
            selectedReferenceImageID = nil
        }
    }

    /// Bytes of raster payloads held by undo/redo snapshots. Always 0.
    var undoRetainedReferenceImageBytes: Int {
        func retainedBytes(_ snapshot: DocumentSnapshot) -> Int {
            let imageBytes = (snapshot.referenceImages ?? []).reduce(0) { $0 + $1.data.count }
            return imageBytes + (snapshot.referenceImageData?.count ?? 0)
        }
        return undoStack.reduce(0) { $0 + retainedBytes($1) }
            + redoStack.reduce(0) { $0 + retainedBytes($1) }
    }
}

nonisolated struct DocumentSnapshot: Codable, Sendable {
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
    /// Current persisted rasters. Optional so documents saved before multiple-image
    /// support still decode; missing key becomes nil rather than a throw.
    var referenceImages: [ReferenceImage]?
    /// Legacy single-image payload. Used only when `referenceImages` is empty.
    var referenceImageData: Data?
    var referenceImageFrame: CGRect?
    var printLayout: PrintLayoutSettings = PrintLayoutSettings()
    var printStrokeTransforms: [UUID: PrintStrokeTransform] = [:]
    var printPieces: [VectorStroke] = []
    var printHiddenStrokeIDs: Set<UUID> = []
    /// Optional so projects saved before piece lineage shipped still open.
    var printPieceSourceIDs: [UUID: UUID]?
    var dimensionOffsets: [String: CGPoint] = [:]
    /// Optional rather than defaulted: synthesized Codable throws on a missing key even
    /// when a default exists, so projects saved before locks shipped would fail to open.
    var dimensionLocks: Set<String>?
    /// Same optional decoding as `dimensionLocks`: files saved before the eye pin omit it.
    var pinnedVisibleDimensionKeys: Set<String>?
}
