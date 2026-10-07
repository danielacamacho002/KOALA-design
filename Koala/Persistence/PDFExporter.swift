//
//  PDFExporter.swift
//  Koala
//

import UIKit

enum PDFExporter {
    static func write(document: KoalaDocument, to url: URL, opaqueFills: Bool = false) throws {
        try write(snapshot: document.makeSnapshot(), to: url, opaqueFills: opaqueFills)
    }

    nonisolated static func write(snapshot: DocumentSnapshot, to url: URL, opaqueFills: Bool = false) throws {
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
                options: DocumentRenderer.Options(
                    size: pageRect.size,
                    drawGrid: false,
                    padding: 20,
                    opaqueFills: opaqueFills
                )
            )
        }
    }

    enum ExportError: Error {
        case writeFailed
    }
}
