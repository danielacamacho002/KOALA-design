//
//  ImportRouter.swift
//  Koala
//

import CoreGraphics
import Foundation
import UIKit
import UniformTypeIdentifiers

enum ImportRouter {
    struct ImportedContent: Equatable {
        var strokes: [VectorStroke] = []
        var textElements: [TextElement] = []
        var referenceImages: [ReferenceImage] = []
        /// Source layers (index 0 = backmost). Items whose `layerID` is not in
        /// this list land on the target document's active layer.
        var layers: [Layer] = []
        var layerGroups: [LayerGroup] = []

        var hasVectorContent: Bool { !strokes.isEmpty || !textElements.isEmpty }
        var hasReferenceImage: Bool { !referenceImages.isEmpty }
    }

    static var supportedTypes: [UTType] {
        [.vectrDocument, .jpeg, .png, .heic, .gif, .tiff, .pdf, .svg, UTType(filenameExtension: "ai") ?? .pdf]
    }

    static func importIntoLibrary(sourceURL: URL, library: ProjectLibrary) throws -> ProjectRecord {
        let ext = sourceURL.pathExtension.lowercased()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent

        if ext == DocumentCodec.fileExtension {
            let dest = try library.copyIntoLibrary(from: sourceURL, name: baseName)
            let document = try DocumentCodec.read(from: dest)
            return try library.registerImportedProject(name: baseName, fileURL: dest, document: document)
        }

        let document = KoalaDocument()
        let content = try loadContent(from: sourceURL, layerID: document.activeLayerID)
        apply(content, to: document)

        let dest = library.projectsDirectory.appendingPathComponent(
            libraryUniqueName(base: baseName, in: library.projectsDirectory, ext: DocumentCodec.fileExtension)
        )
        try DocumentCodec.write(document, to: dest)
        return try library.registerImportedProject(name: baseName, fileURL: dest, document: document)
    }

    static func loadContent(from sourceURL: URL, layerID: UUID) throws -> ImportedContent {
        let ext = sourceURL.pathExtension.lowercased()
        switch ext {
        case DocumentCodec.fileExtension:
            let imported = try DocumentCodec.read(from: sourceURL)
            guard imported.strokes.isEmpty == false
                    || imported.textElements.isEmpty == false
                    || imported.referenceImages.isEmpty == false else {
                throw ImportError.noVectorContent
            }
            return ImportedContent(
                strokes: imported.strokes,
                textElements: imported.textElements,
                referenceImages: imported.referenceImages,
                layers: imported.layers,
                layerGroups: imported.layerGroups
            )

        case "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp":
            return try loadRasterImage(from: sourceURL, layerID: layerID)

        case "svg":
            let parsed = try SVGImporter.importDocument(from: sourceURL, layerID: layerID)
            let centered = SVGImporter.centered(parsed)
            guard centered.hasVectorContent else { throw ImportError.noVectorContent }
            return ImportedContent(
                strokes: centered.strokes,
                textElements: centered.textElements,
                layers: centered.layers,
                layerGroups: centered.layerGroups
            )

        case "pdf", "ai":
            return try loadPDF(from: sourceURL, layerID: layerID)

        default:
            throw ImportError.unsupportedFormat
        }
    }

    private static func apply(_ content: ImportedContent, to document: KoalaDocument) {
        document.strokes = content.strokes
        document.textElements = content.textElements
        document.referenceImages = content.referenceImages.map { image in
            var copy = image
            copy.layerID = document.activeLayerID
            return copy
        }
        guard let topLayer = content.layers.last else { return }
        let importedIDs = Set(content.layers.map(\.id))
        let usesFallback = content.strokes.contains { !importedIDs.contains($0.layerID) }
            || content.textElements.contains { !importedIDs.contains($0.layerID) }
            || !document.referenceImages.isEmpty
        let fallback = usesFallback ? document.layers.filter { $0.id == document.activeLayerID } : []
        document.layers = fallback + content.layers
        document.layerGroups = content.layerGroups
        document.activeLayerID = usesFallback ? document.activeLayerID : topLayer.id
        document.normalizeLayerGrouping()
    }

    private static func loadRasterImage(from sourceURL: URL, layerID: UUID) throws -> ImportedContent {
        let data = try Data(contentsOf: sourceURL)
        guard let image = UIImage(data: data) else { throw ImportError.unsupportedFormat }
        return ImportedContent(
            referenceImages: [
                ReferenceImage(
                    layerID: layerID,
                    data: data,
                    frame: CGRect(
                        x: -image.size.width / 2,
                        y: -image.size.height / 2,
                        width: image.size.width,
                        height: image.size.height
                    )
                )
            ]
        )
    }

    private static func loadPDF(from sourceURL: URL, layerID: UUID) throws -> ImportedContent {
        guard let provider = CGDataProvider(url: sourceURL as CFURL),
              let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: 1) else {
            throw ImportError.unsupportedFormat
        }

        let pageRect = page.getBoxRect(.mediaBox)
        let strokes = extractLineStrokes(from: page, layerID: layerID, pageHeight: pageRect.height)
        if !strokes.isEmpty {
            return ImportedContent(strokes: strokes)
        }

        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let data = renderer.jpegData(withCompressionQuality: 0.9) { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(pageRect)
            ctx.cgContext.drawPDFPage(page)
        }
        return ImportedContent(
            referenceImages: [ReferenceImage(layerID: layerID, data: data, frame: pageRect)]
        )
    }

    private static func extractLineStrokes(from page: CGPDFPage, layerID: UUID, pageHeight: CGFloat) -> [VectorStroke] {
        // Basic PDF path extraction is limited; return empty to fall back to raster reference.
        []
    }

    private static func libraryUniqueName(base: String, in directory: URL, ext: String) -> String {
        let fm = FileManager.default
        var candidate = "\(base).\(ext)"
        var counter = 1
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    enum ImportError: Error, LocalizedError, Equatable {
        case unsupportedFormat
        case noVectorContent
        case layerLocked

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "This file format is not supported."
            case .noVectorContent: return "No vector content found in this file."
            case .layerLocked: return "Unlock the active layer to import artwork."
            }
        }
    }
}
