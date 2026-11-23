import CoreGraphics
import Foundation
import Testing
@testable import KOALADesign

@MainActor
struct KoalaDocumentTests {

    /// Axis constraints stay off on a fresh document. They only engage after
    /// the user selects them in the constraints bar.
    @Test func axisConstraintsStartOff() {
        let document = KoalaDocument()
        #expect(document.horizontalAlignmentEnabled == false)
        #expect(document.verticalAlignmentEnabled == false)
        #expect(document.enabledDrawingAxes.isEmpty)
        #expect(document.enabledAlignmentAxes.isEmpty)
    }

    // MARK: - Layer lifecycle

    /// Deleting a layer has to take its contents with it. Anything left behind
    /// becomes unreachable geometry that still exports and still saves.
    @Test func deletingALayerRemovesEverythingOnIt() {
        let document = KoalaDocument()
        let keep = document.activeLayerID
        let doomed = document.addLayer()

        let keptStroke = line(on: keep)
        document.addStroke(keptStroke)
        document.addStroke(line(on: doomed.id, x: 50))
        document.addTextElement(document.makeTextElement(at: CGPoint(x: 5, y: 5), layerID: doomed.id))
        document.referenceImages = [
            ReferenceImage(layerID: doomed.id, data: Data([0x1]), frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        ]

        document.deleteLayer(id: doomed.id)

        #expect(document.layers.map(\.id) == [keep])
        #expect(document.strokes.map(\.id) == [keptStroke.id])
        #expect(document.textElements.isEmpty)
        #expect(document.referenceImages.isEmpty)
        #expect(document.activeLayerID == keep)
    }

    /// The canvas is never layer-less, so the last layer must refuse to go.
    @Test func theLastLayerCannotBeDeleted() {
        let document = KoalaDocument()
        let only = document.activeLayerID
        document.deleteLayer(id: only)
        #expect(document.layers.map(\.id) == [only])
    }

    @Test func deletingTheSelectedStrokesLayerClearsTheSelection() {
        let document = KoalaDocument()
        let doomed = document.addLayer()
        let stroke = line(on: doomed.id)
        document.addStroke(stroke)
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])
        #expect(document.selectedStrokeID == stroke.id)

        document.deleteLayer(id: doomed.id)

        #expect(document.selectedStrokeID == nil)
        #expect(document.selectedStrokeIDs.isEmpty)
    }

    /// Merge keeps the front-most layer and restacks contents back-to-front, so a
    /// shape drawn on a back layer must end up behind one drawn on a front layer
    /// even when it was appended later.
    @Test func mergeKeepsTheFrontLayerAndRestacksBackToFront() {
        let document = KoalaDocument()
        let back = document.activeLayerID
        let front = document.addLayer()

        let frontStroke = line(on: front.id, x: 30)
        let backStroke = line(on: back, x: 0)
        document.addStroke(frontStroke)
        document.addStroke(backStroke)
        #expect(document.strokes.map(\.id) == [frontStroke.id, backStroke.id])

        let survivor = document.mergeLayers(ids: [back, front.id])

        #expect(survivor == front.id)
        #expect(document.layers.map(\.id) == [front.id])
        #expect(document.strokes.map(\.id) == [backStroke.id, frontStroke.id])
        #expect(document.strokes.allSatisfy { $0.layerID == front.id })
        #expect(document.activeLayerID == front.id)
    }

    @Test func mergingFewerThanTwoLayersIsANoOp() {
        let document = KoalaDocument()
        let only = document.activeLayerID
        #expect(document.mergeLayers(ids: [only]) == nil)
        #expect(document.mergeLayers(ids: []) == nil)
        #expect(document.layers.count == 1)
    }

    // MARK: - Layer-scoped selection

    /// Selection is confined to the active layer, so IDs from elsewhere must be
    /// dropped rather than quietly letting Move edit another layer.
    @Test func selectionDropsStrokesFromOtherLayers() {
        let document = KoalaDocument()
        let back = document.activeLayerID
        let front = document.addLayer()

        let backStroke = line(on: back)
        let frontStroke = line(on: front.id, x: 40)
        document.addStroke(backStroke)
        document.addStroke(frontStroke)
        document.setActiveLayer(id: front.id)

        document.setElementSelection(strokeIDs: [backStroke.id, frontStroke.id], textIDs: [])

        #expect(document.selectedStrokeIDs == [frontStroke.id])
        #expect(document.selectedStrokeID == frontStroke.id)
    }

    /// A layer folder moves as one: its layers share a selection scope, so a drag
    /// carries every member layer's shapes, including ones behind the active layer.
    @Test func layersInAFolderShareTheSelection() {
        let document = KoalaDocument()
        let back = document.activeLayerID
        let front = document.addLayer()
        let outside = document.addLayer()
        let backStroke = line(on: back)
        let frontStroke = line(on: front.id, x: 40)
        let outsideStroke = line(on: outside.id, x: 80)
        document.addStroke(backStroke)
        document.addStroke(frontStroke)
        document.addStroke(outsideStroke)
        document.groupLayers(ids: [back, front.id])
        document.setActiveLayer(id: front.id)

        document.setElementSelection(
            strokeIDs: [backStroke.id, frontStroke.id, outsideStroke.id],
            textIDs: []
        )
        #expect(document.selectedStrokeIDs == [backStroke.id, frontStroke.id])

        document.setElementSelection(strokeIDs: [], textIDs: [])
        document.selectElement(near: CGPoint(x: 10, y: 10), threshold: 2)
        #expect(document.selectedStrokeIDs == [backStroke.id])

        document.setActiveLayer(id: outside.id)
        #expect(document.selectionIsEmpty)
    }

    @Test func lockedLayerInAFolderStaysUnselectable() {
        let document = KoalaDocument()
        let back = document.activeLayerID
        let front = document.addLayer()
        let backStroke = line(on: back)
        document.addStroke(backStroke)
        document.groupLayers(ids: [back, front.id])
        document.toggleLayerLock(id: back)
        document.setActiveLayer(id: front.id)

        document.setElementSelection(strokeIDs: [backStroke.id], textIDs: [])
        #expect(document.selectionIsEmpty)
    }

    @Test func lockedAndHiddenLayersAreNotSelectable() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let stroke = line(on: layerID)
        document.addStroke(stroke)
        #expect(document.isSelectableStroke(stroke))

        document.toggleLayerLock(id: layerID)
        #expect(!document.isSelectableStroke(stroke))
        document.toggleLayerLock(id: layerID)

        document.toggleLayerVisibility(id: layerID)
        #expect(!document.isSelectableStroke(stroke))
    }

    @Test func marqueeSelectsOverlappingStrokesOnly() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let inside = line(on: layerID, x: 0)
        let outside = line(on: layerID, x: 500)
        document.addStroke(inside)
        document.addStroke(outside)

        document.selectElements(in: CGRect(x: -5, y: -5, width: 30, height: 30))

        #expect(document.selectedStrokeIDs == [inside.id])
    }

    // MARK: - Object groups

    /// Acting on one member has to act on the whole group, or a group move leaves
    /// part of the artwork behind.
    @Test func deletingOneGroupMemberDeletesTheWholeGroup() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let a = line(on: layerID, x: 0)
        let b = line(on: layerID, x: 30)
        document.addStroke(a)
        document.addStroke(b)
        document.groups = [ObjectGroup(strokeIDs: [a.id, b.id])]

        document.setElementSelection(strokeIDs: [a.id], textIDs: [])
        document.deleteSelectedElements()

        #expect(document.strokes.isEmpty)
        #expect(document.groups.isEmpty)
    }

    @Test func selectingOneMemberExpandsToTheGroup() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let a = line(on: layerID, x: 0)
        let b = line(on: layerID, x: 30)
        document.addStroke(a)
        document.addStroke(b)
        document.groups = [ObjectGroup(strokeIDs: [a.id, b.id])]

        document.setElementSelection(strokeIDs: [a.id], textIDs: [])
        #expect(document.expandSelectionToGroupsIfNeeded())
        #expect(document.selectedStrokeIDs == [a.id, b.id])
        #expect(!document.expandSelectionToGroupsIfNeeded())
    }

    /// A group of one is not a group; leaving it behind makes a lone shape
    /// un-selectable on its own.
    @Test func pruningDropsGroupsLeftWithFewerThanTwoMembers() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let a = line(on: layerID, x: 0)
        let b = line(on: layerID, x: 30)
        let c = line(on: layerID, x: 60)
        document.addStroke(a)
        document.addStroke(b)
        document.addStroke(c)
        document.groups = [
            ObjectGroup(strokeIDs: [a.id, b.id, UUID()]),
            ObjectGroup(strokeIDs: [c.id, UUID()])
        ]

        document.pruneGroups()

        #expect(document.groups.count == 1)
        #expect(document.groups[0].strokeIDs == [a.id, b.id])
    }

    // MARK: - Clipboard and duplication

    /// Paste must produce independent copies on the active layer; reusing IDs would
    /// make the original and the copy the same object.
    @Test func pasteCreatesNewIDsOnTheActiveLayer() {
        let document = KoalaDocument()
        let source = document.activeLayerID
        let stroke = line(on: source)
        document.addStroke(stroke)
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])
        #expect(document.copySelectedElementsToClipboard() == 1)

        let destination = document.addLayer()
        #expect(document.pasteClipboardToActiveLayer() == 1)

        #expect(document.strokes.count == 2)
        let pasted = document.strokes.filter { $0.layerID == destination.id }
        #expect(pasted.count == 1)
        #expect(pasted[0].id != stroke.id)
        let step = document.grid.spacing
        #expect(pasted[0].points == stroke.points.map {
            CGPoint(x: $0.x + step, y: $0.y + step)
        })
        #expect(document.selectedStrokeIDs == [pasted[0].id])
    }

    @Test func pasteIsBlockedOnALockedLayer() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let stroke = line(on: layerID)
        document.addStroke(stroke)
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])
        document.copySelectedElementsToClipboard()

        document.toggleLayerLock(id: layerID)

        #expect(!document.canPasteClipboard)
        #expect(document.pasteClipboardToActiveLayer() == 0)
        #expect(document.strokes.count == 1)
    }

    /// Group membership is remapped, not shared: the pasted copies form their own
    /// group instead of joining the original's.
    @Test func pasteRebuildsGroupsFromTheCopiedMembers() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let a = line(on: layerID, x: 0)
        let b = line(on: layerID, x: 30)
        document.addStroke(a)
        document.addStroke(b)
        document.groups = [ObjectGroup(strokeIDs: [a.id, b.id])]

        document.setElementSelection(strokeIDs: [a.id], textIDs: [])
        document.copySelectedElementsToClipboard()
        document.pasteClipboardToActiveLayer()

        #expect(document.groups.count == 2)
        let pastedGroup = document.groups[1]
        #expect(pastedGroup.strokeIDs.count == 2)
        #expect(!pastedGroup.strokeIDs.contains(a.id))
        #expect(!pastedGroup.strokeIDs.contains(b.id))
    }

    @Test func duplicateOffsetsTheCopyAndSelectsIt() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let stroke = line(on: layerID)
        document.addStroke(stroke)
        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])

        document.duplicateSelectedElements(offset: CGPoint(x: 10, y: 5))

        #expect(document.strokes.count == 2)
        let copy = document.strokes[1]
        #expect(copy.id != stroke.id)
        #expect(copy.points == stroke.points.map { CGPoint(x: $0.x + 10, y: $0.y + 5) })
        #expect(document.selectedStrokeIDs == [copy.id])
    }

    /// Print placement and pinned dimensions live outside the stroke, so a duplicate
    /// that skips them lands in the wrong spot in Print Layout.
    @Test func duplicateCarriesPrintTransformAndDimensionMetadata() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let stroke = line(on: layerID)
        document.addStroke(stroke)

        let transform = PrintStrokeTransform(translation: CGPoint(x: 12, y: -4))
        document.setPrintTransform(transform, for: stroke.id)
        let lockKey = KoalaDocument.dimensionOffsetKey(strokeID: stroke.id, dimensionID: "top")
        document.dimensionOffsets[lockKey] = CGPoint(x: 3, y: 3)
        document.dimensionLocks.insert(lockKey)
        document.pinnedVisibleDimensionKeys.insert(lockKey)

        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])
        document.duplicateSelectedElements(offset: CGPoint(x: 10, y: 0))

        let copyID = document.strokes[1].id
        #expect(document.printTransform(for: copyID) == transform)
        let copyKey = KoalaDocument.dimensionOffsetKey(strokeID: copyID, dimensionID: "top")
        #expect(document.dimensionOffsets[copyKey] == CGPoint(x: 3, y: 3))
        #expect(document.isDimensionLocked(key: copyKey))
        #expect(document.isDimensionPinnedVisible(key: copyKey))
    }

    /// An eye-pinned measurement stays up after leaving Dimensions. An ordinary
    /// revealed label does not, and hiding the edge drops the pin.
    @Test func pinnedDimensionStaysShownAfterLeavingTheTool() {
        let document = KoalaDocument()
        let stroke = line(on: document.activeLayerID)
        document.addStroke(stroke)
        let pinned = KoalaDocument.dimensionOffsetKey(strokeID: stroke.id, dimensionID: "length")
        let fleeting = KoalaDocument.dimensionOffsetKey(strokeID: stroke.id, dimensionID: "angle")
        document.revealDimension(key: pinned)
        document.revealDimension(key: fleeting)
        document.toggleDimensionPinnedVisible(key: pinned, recordUndo: false)

        document.selectTool(.line)

        #expect(document.isDimensionShown(key: pinned))
        #expect(!document.isDimensionShown(key: fleeting))
        #expect(!document.dimensionsVisible)

        document.hideDimension(key: pinned)

        #expect(!document.isDimensionPinnedVisible(key: pinned))
        #expect(!document.isDimensionShown(key: pinned))
    }

    /// Files saved before the eye pin omit the key. Opening one must not fail,
    /// and a file that does pin a label shows it before Dimensions is selected.
    @Test func visibilityPinIsOptionalOnOlderFilesAndShowsOnOpen() throws {
        let document = KoalaDocument()
        let stroke = line(on: document.activeLayerID)
        document.addStroke(stroke)
        let key = KoalaDocument.dimensionOffsetKey(strokeID: stroke.id, dimensionID: "length")
        document.toggleDimensionPinnedVisible(key: key, recordUndo: false)

        let opened = KoalaDocument(snapshot: document.makeSnapshot())
        #expect(opened.isDimensionShown(key: key))
        #expect(!opened.dimensionsVisible)

        let encoded = try JSONEncoder().encode(document.makeSnapshot())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "pinnedVisibleDimensionKeys")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let legacy = try JSONDecoder().decode(DocumentSnapshot.self, from: stripped)
        #expect(legacy.pinnedVisibleDimensionKeys == nil)
        #expect(KoalaDocument(snapshot: legacy).pinnedVisibleDimensionKeys.isEmpty)
    }

    /// A sleeve traced as cubics plus lines used to collapse the moment it was
    /// multi-selected. Selection compacts circular leftovers, and any three
    /// anchors define a circle, so the cubics were rewritten as arcs before Join.
    @Test func selectingBezierCurvesAndLinesKeepsTheBulge() {
        let document = KoalaDocument()
        let layerID = document.activeLayerID
        let curve = bulgingCurve(on: layerID)
        let tail = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 100, y: 0), CGPoint(x: 140, y: 0)],
            isClosed: false,
            shapeType: .polyline
        )
        document.addStroke(curve)
        document.addStroke(tail)

        document.setElementSelection(strokeIDs: [curve.id, tail.id], textIDs: [])

        let selected = document.stroke(with: curve.id)
        #expect(selected?.shapeType == .curve)
        #expect(selected?.curveHandles == curve.curveHandles)
        let rendered = ShapeGeometry.renderPoints(for: selected ?? curve)
        #expect((rendered.map(\.y).max() ?? 0) > 40)
        #expect(document.stroke(with: tail.id)?.points == tail.points)
    }

    /// Move compacts again at drag start. A quarter-circle cubic hugs a real
    /// circle, and that used to demote it to a smooth polyline before the delta.
    @Test func movingANearCircularCubicKeepsItsHandles() {
        let document = KoalaDocument()
        let curve = quarterCircleCubic(on: document.activeLayerID)
        document.addStroke(curve)
        document.setElementSelection(strokeIDs: [curve.id], textIDs: [], compactAnchors: false)

        document.beginInteractiveEdit()

        let edited = document.stroke(with: curve.id)
        #expect(edited?.shapeType == .curve)
        #expect(edited?.curveHandles == curve.curveHandles)
        let rendered = ShapeGeometry.renderPoints(for: edited ?? curve)
        #expect(rendered.contains { hypot($0.x - 70.7, $0.y - 70.7) < 3 })
    }

    /// Tessellated arcs with no cubic handles should still collapse to the compact
    /// anchor set when selected, so circle editing does not keep every sample.
    @Test func selectingATessellatedArcStillCompactsIt() {
        let document = KoalaDocument()
        let samples = (0...16).map { index -> CGPoint in
            let angle = CGFloat(index) * .pi / 32
            return CGPoint(x: cos(angle) * 100, y: sin(angle) * 100)
        }
        let arc = VectorStroke(
            layerID: document.activeLayerID,
            points: samples,
            isClosed: false,
            shapeType: .polyline
        )
        document.addStroke(arc)

        document.setElementSelection(strokeIDs: [arc.id], textIDs: [])

        let selected = document.stroke(with: arc.id)
        #expect(selected?.shapeType == .arc)
        #expect((selected?.points.count ?? 0) < samples.count)
    }

    /// The pencil can keep moving after the arc has used as much of the adjacent edges as it
    /// is allowed to. The stored radius has to stop at that same limit, or the readout keeps
    /// climbing after the corner has stopped changing.
    @Test func filletRadiusClampsToTheLargestArcTheCornerCanDraw() {
        let document = KoalaDocument()
        let square = VectorStroke(
            layerID: document.activeLayerID,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 100),
                CGPoint(x: 0, y: 100)
            ],
            isClosed: true,
            shapeType: .rectangle
        )
        document.addStroke(square)
        document.selectedStrokeID = square.id
        document.selectSingleFilletCorner(at: 0)

        let cap = FilletPathBuilder.maximumFilletRadius(for: square, cornerIndex: 0)
        #expect(abs((cap ?? 0) - 45) < 0.01)

        document.applyFilletToSelected(radius: 1000, cornerIndices: [0], recordUndo: false)
        let stored = document.stroke(with: square.id)?.resolvedFilletCornerRadii()[0]
        #expect(abs((stored ?? -1) - (cap ?? -2)) < 0.001)
        if case .uniform(let shown) = document.selectedFilletRadiusSummary() {
            #expect(abs(shown - (cap ?? -1)) < 0.001)
        } else {
            Issue.record("Expected a uniform fillet radius at the corner maximum")
        }

        document.applyFilletToSelected(radius: 10, cornerIndices: [0], recordUndo: false)
        let smaller = document.stroke(with: square.id)?.resolvedFilletCornerRadii()[0]
        #expect(abs((smaller ?? -1) - 10) < 0.001)
    }

    @Test func copyingAnEmptySelectionLeavesTheClipboardAlone() {
        let document = KoalaDocument()
        #expect(document.copySelectedElementsToClipboard() == 0)
        #expect(!document.canPasteClipboard)
        #expect(document.pasteClipboardToActiveLayer() == 0)
    }

    // MARK: - Helpers

    private func line(on layerID: UUID, x: CGFloat = 0) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: x, y: 0), CGPoint(x: x + 20, y: 20)]
        )
    }

    /// Three anchors always define a circle. The handles pull the cubics far off
    /// that circumcircle, which is the collapse selection used to apply.
    private func bulgingCurve(on layerID: UUID) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 10), CGPoint(x: 100, y: 0)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: 80)),
                CurveHandle(inOffset: CGPoint(x: 0, y: 40), outOffset: CGPoint(x: 0, y: 40)),
                CurveHandle(inOffset: CGPoint(x: 0, y: 80), outOffset: .zero)
            ]
        )
    }

    private func quarterCircleCubic(on layerID: UUID) -> VectorStroke {
        let radius: CGFloat = 100
        let kappa = radius * 4 / 3 * tan(.pi / 8)
        return VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: radius, y: 0), CGPoint(x: 0, y: radius)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(inOffset: .zero, outOffset: CGPoint(x: 0, y: kappa)),
                CurveHandle(inOffset: CGPoint(x: kappa, y: 0), outOffset: .zero)
            ]
        )
    }
}
