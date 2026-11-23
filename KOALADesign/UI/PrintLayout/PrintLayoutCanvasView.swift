//
//  PrintLayoutCanvasView.swift
//  Koala
//

import SwiftUI

struct PrintLayoutCanvasView: UIViewRepresentable {
    @Bindable var document: KoalaDocument
    var printLayoutRevision: Int
    var geometryRevision: Int
    var viewportHandle: CanvasViewportHandle?
    var onCanvasTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PrintLayoutCanvasUIView {
        let view = PrintLayoutCanvasUIView(document: document)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.onCanvasTap = { viewPoint in
            let docPoint = document.viewport.viewToDocument(viewPoint)
            onCanvasTap(docPoint)
        }
        viewportHandle?.attach(view)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PrintLayoutCanvasUIView, context: Context) -> CGSize {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }

    func updateUIView(_ uiView: PrintLayoutCanvasUIView, context: Context) {
        let didSwapDocument = uiView.document !== document
        if didSwapDocument {
            uiView.document = document
        }
        uiView.onCanvasTap = { viewPoint in
            let docPoint = document.viewport.viewToDocument(viewPoint)
            onCanvasTap(docPoint)
        }
        viewportHandle?.attach(uiView)
        if !didSwapDocument {
            uiView.reloadAll()
        }
        _ = printLayoutRevision
        _ = geometryRevision
    }
}
