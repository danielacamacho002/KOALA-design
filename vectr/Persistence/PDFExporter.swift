//
//  PDFExporter.swift
//  vectr
//

import UIKit

enum PDFExporter {
    static func write(document: VectrDocument, to url: URL) throws {
        try write(snapshot: document.makeSnapshot(), to: url)
    }

    nonisolated static func write(snapshot: DocumentSnapshot, to url: URL) throws {
        let bounds = DocumentRenderer.boundingRect(for: snapshot)
        let pageRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: max(bounds.width + 40, 612),
                height: max(bounds.height + 40, 792)
            )
        )

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            DocumentRenderer.draw(
                snapshot: snapshot,
                in: context.cgContext,
                bounds: pageRect,
                options: DocumentRenderer.Options(size: pageRect.size, drawGrid: false, padding: 20)
            )
        }
    }

    enum ExportError: Error {
        case writeFailed
    }
}
