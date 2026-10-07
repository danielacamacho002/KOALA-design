import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct KoalaDocumentTests {

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

        document.setElementSelection(strokeIDs: [stroke.id], textIDs: [])
        document.duplicateSelectedElements(offset: CGPoint(x: 10, y: 0))

        let copyID = document.strokes[1].id
        #expect(document.printTransform(for: copyID) == transform)
        let copyKey = KoalaDocument.dimensionOffsetKey(strokeID: copyID, dimensionID: "top")
        #expect(document.dimensionOffsets[copyKey] == CGPoint(x: 3, y: 3))
        #expect(document.isDimensionLocked(key: copyKey))
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
}
