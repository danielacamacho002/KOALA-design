//
//  PrintLayoutCanvasInvalidation.swift
//  vectr
//

import CoreGraphics
import Foundation

/// Diffs print-canvas inputs so `updateUIView` can refresh only what changed.
struct PrintLayoutCanvasInvalidation {
    struct Change: Equatable {
        var geometryChanged = false
        var selectionChanged = false
        var viewportChanged = false
        var viewportAlreadyHandled = false
        var printLayoutChanged = false
        var sheetGridChanged = false
        var overlaySettingsChanged = false
        var artworkLayoutChanged = false
        /// True when only the selected element's print transform moved.
        var selectedArtworkOnly = false
    }

    struct ViewportSnapshot: Equatable {
        var scale: CGFloat
        var translationX: CGFloat
        var translationY: CGFloat

        init(_ viewport: ViewportTransform) {
            scale = viewport.scale
            translationX = viewport.translation.x
            translationY = viewport.translation.y
        }
    }

    private var lastGeometryRevision: Int?
    private var lastPrintLayoutRevision: Int?
    private var lastSelectedStrokeID: UUID?
    private var lastSelectedTextID: UUID?
    private var lastViewport: ViewportSnapshot?
    private var lastPrintLayout: PrintLayoutSettings?
    private var viewportHandledByCanvas = false

    mutating func markViewportHandledByCanvas() {
        viewportHandledByCanvas = true
    }

    mutating func consume(
        geometryRevision: Int,
        printLayoutRevision: Int,
        printLayout: PrintLayoutSettings,
        selectedStrokeID: UUID?,
        selectedTextID: UUID?,
        viewport: ViewportTransform,
        didSwapDocument: Bool
    ) -> Change {
        var change = Change()

        if didSwapDocument || lastGeometryRevision == nil {
            change.geometryChanged = true
        } else {
            change.geometryChanged = lastGeometryRevision != geometryRevision
        }

        change.selectionChanged = didSwapDocument
            || lastSelectedStrokeID != selectedStrokeID
            || lastSelectedTextID != selectedTextID

        let viewportSnapshot = ViewportSnapshot(viewport)
        if didSwapDocument || lastViewport == nil {
            change.viewportChanged = true
        } else {
            change.viewportChanged = lastViewport != viewportSnapshot
        }
        if change.viewportChanged {
            change.viewportAlreadyHandled = viewportHandledByCanvas
            viewportHandledByCanvas = false
        }

        if didSwapDocument || lastPrintLayoutRevision == nil {
            change.printLayoutChanged = true
            change.sheetGridChanged = true
            change.overlaySettingsChanged = true
            change.artworkLayoutChanged = true
        } else if lastPrintLayoutRevision != printLayoutRevision {
            change.printLayoutChanged = true
            let previous = lastPrintLayout ?? printLayout
            change.sheetGridChanged = !Self.sheetGridMatches(previous, printLayout)
            change.overlaySettingsChanged = !Self.overlaySettingsMatch(previous, printLayout)
            let contentOffsetChanged = previous.contentOffset != printLayout.contentOffset
            let settingsUnchanged = previous == printLayout
            change.artworkLayoutChanged = contentOffsetChanged || settingsUnchanged
            change.selectedArtworkOnly = settingsUnchanged
                && (selectedStrokeID != nil || selectedTextID != nil)
        }

        lastGeometryRevision = geometryRevision
        lastPrintLayoutRevision = printLayoutRevision
        lastSelectedStrokeID = selectedStrokeID
        lastSelectedTextID = selectedTextID
        lastViewport = viewportSnapshot
        lastPrintLayout = printLayout

        return change
    }

    private static func sheetGridMatches(_ lhs: PrintLayoutSettings, _ rhs: PrintLayoutSettings) -> Bool {
        lhs.paperSize == rhs.paperSize
            && lhs.customPaperSize == rhs.customPaperSize
            && lhs.columns == rhs.columns
            && lhs.rows == rhs.rows
            && lhs.overlap == rhs.overlap
    }

    private static func overlaySettingsMatch(_ lhs: PrintLayoutSettings, _ rhs: PrintLayoutSettings) -> Bool {
        lhs.printableMargin == rhs.printableMargin
            && lhs.marginMode == rhs.marginMode
            && lhs.activeTool == rhs.activeTool
    }
}
