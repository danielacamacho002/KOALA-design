//
//  PrintLayoutCanvasView.swift
//  vectr
//

import SwiftUI

struct PrintLayoutCanvasView: UIViewRepresentable {
    @Bindable var document: VectrDocument
    var printLayoutRevision: Int
    var geometryRevision: Int
    var onCanvasTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PrintLayoutCanvasUIView {
        let view = PrintLayoutCanvasUIView(document: document)
        view.onCanvasTap = { viewPoint in
            let docPoint = document.viewport.viewToDocument(viewPoint)
            onCanvasTap(docPoint)
        }
        return view
    }

    func updateUIView(_ uiView: PrintLayoutCanvasUIView, context: Context) {
        uiView.document = document
        uiView.onCanvasTap = { viewPoint in
            let docPoint = document.viewport.viewToDocument(viewPoint)
            onCanvasTap(docPoint)
        }
        uiView.reloadAll()
        _ = printLayoutRevision
        _ = geometryRevision
    }
}
