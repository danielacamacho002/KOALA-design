//
//  PrintLayoutCanvasView.swift
//  vectr
//

import SwiftUI

struct PrintLayoutCanvasView: UIViewRepresentable {
    @Bindable var document: VectrDocument
    var printLayoutRevision: Int
    var geometryRevision: Int
    var printSelectedStrokeID: UUID?
    var printSelectedTextID: UUID?
    var viewportHandle: CanvasViewportHandle?
    var onCanvasTap: (CGPoint) -> Void
    var onTwoFingerTap: (() -> Void)?

    func makeUIView(context: Context) -> PrintLayoutCanvasUIView {
        let view = PrintLayoutCanvasUIView(document: document)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.delegate = context.coordinator
        view.onCanvasTap = { viewPoint in
            let docPoint = document.viewport.viewToDocument(viewPoint)
            onCanvasTap(docPoint)
        }
        view.onTwoFingerTap = onTwoFingerTap
        viewportHandle?.attach(view)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PrintLayoutCanvasUIView, context: Context) -> CGSize {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }

    func updateUIView(_ uiView: PrintLayoutCanvasUIView, context: Context) {
        context.coordinator.document = document
        uiView.delegate = context.coordinator
        uiView.onCanvasTap = { viewPoint in
            let docPoint = document.viewport.viewToDocument(viewPoint)
            onCanvasTap(docPoint)
        }
        uiView.onTwoFingerTap = onTwoFingerTap
        viewportHandle?.attach(uiView)

        let didSwapDocument = uiView.document !== document
        if didSwapDocument {
            uiView.document = document
        }

        let change = context.coordinator.invalidation.consume(
            geometryRevision: geometryRevision,
            printLayoutRevision: printLayoutRevision,
            printLayout: document.printLayout,
            selectedStrokeID: printSelectedStrokeID,
            selectedTextID: printSelectedTextID,
            viewport: document.viewport,
            didSwapDocument: didSwapDocument
        )

        if didSwapDocument { return }

        if change.geometryChanged {
            uiView.reloadStrokes()
            uiView.reloadTextElements()
        }

        if change.sheetGridChanged {
            uiView.reloadSheets()
        }

        var didRefreshViewport = false
        var needsViewportRefresh = change.viewportChanged
        if change.viewportChanged && change.viewportAlreadyHandled {
            needsViewportRefresh = false
        }
        if needsViewportRefresh {
            uiView.refreshViewport()
            didRefreshViewport = true
        }

        if change.artworkLayoutChanged && !change.geometryChanged && !didRefreshViewport {
            if change.selectedArtworkOnly {
                uiView.reloadSelectedPrintElement()
            } else {
                uiView.reloadStrokes()
                uiView.reloadTextElements()
            }
        }

        if (change.overlaySettingsChanged || change.sheetGridChanged) && !didRefreshViewport {
            uiView.updateOverlays()
        }

        let needsHighlight = change.selectionChanged
            || change.overlaySettingsChanged
            || change.sheetGridChanged
        if needsHighlight && !didRefreshViewport && !change.geometryChanged && !change.artworkLayoutChanged {
            uiView.refreshHighlight()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    final class Coordinator: NSObject, PrintLayoutCanvasDelegate {
        var document: VectrDocument
        var invalidation = PrintLayoutCanvasInvalidation()

        init(document: VectrDocument) {
            self.document = document
        }

        func canvasDidUpdate(document: VectrDocument) {
            self.document = document
            invalidation.markViewportHandledByCanvas()
        }
    }
}
