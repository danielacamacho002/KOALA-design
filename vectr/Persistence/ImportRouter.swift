//
//  ImportRouter.swift
//  vectr
//

import CoreGraphics
import Foundation
import UIKit
import UniformTypeIdentifiers

enum ImportRouter {
    static func importIntoLibrary(sourceURL: URL, library: ProjectLibrary) throws -> ProjectRecord {
        let ext = sourceURL.pathExtension.lowercased()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent

        switch ext {
        case DocumentCodec.fileExtension:
            let dest = try library.copyIntoLibrary(from: sourceURL, name: baseName)
            let document = try DocumentCodec.read(from: dest)
            return try library.registerImportedProject(name: baseName, fileURL: dest, document: document)

        case "jpg", "jpeg":
            let data = try Data(contentsOf: sourceURL)
            guard let image = UIImage(data: data) else { throw ImportError.unsupportedFormat }
            var document = VectrDocument()
            document.referenceImageData = data
            document.referenceImageFrame = CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            )
            let dest = library.projectsDirectory.appendingPathComponent(
                libraryUniqueName(base: baseName, in: library.projectsDirectory, ext: DocumentCodec.fileExtension)
            )
            try DocumentCodec.write(document, to: dest)
            return try library.registerImportedProject(name: baseName, fileURL: dest, document: document)

        case "svg":
            var document = VectrDocument()
            let strokes = try SVGImporter.importStrokes(from: sourceURL, layerID: document.activeLayerID)
            guard !strokes.isEmpty else { throw ImportError.noVectorContent }
            document.strokes = SVGImporter.centeredStrokes(strokes)
            let dest = library.projectsDirectory.appendingPathComponent(
                libraryUniqueName(base: baseName, in: library.projectsDirectory, ext: DocumentCodec.fileExtension)
            )
            try DocumentCodec.write(document, to: dest)
            return try library.registerImportedProject(name: baseName, fileURL: dest, document: document)

        case "pdf", "ai":
            return try importPDF(from: sourceURL, name: baseName, library: library)

        default:
            throw ImportError.unsupportedFormat
        }
    }

    private static func importPDF(from sourceURL: URL, name: String, library: ProjectLibrary) throws -> ProjectRecord {
        guard let provider = CGDataProvider(url: sourceURL as CFURL),
              let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: 1) else {
            throw ImportError.unsupportedFormat
        }

        var document = VectrDocument()
        let pageRect = page.getBoxRect(.mediaBox)
        let strokes = extractLineStrokes(from: page, layerID: document.activeLayerID, pageHeight: pageRect.height)

        if strokes.isEmpty {
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let data = renderer.jpegData(withCompressionQuality: 0.9) { ctx in
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fill(pageRect)
                ctx.cgContext.drawPDFPage(page)
            }
            document.referenceImageData = data
            document.referenceImageFrame = pageRect
        } else {
            document.strokes = strokes
        }

        let dest = library.projectsDirectory.appendingPathComponent(
            libraryUniqueName(base: name, in: library.projectsDirectory, ext: DocumentCodec.fileExtension)
        )
        try DocumentCodec.write(document, to: dest)
        return try library.registerImportedProject(name: name, fileURL: dest, document: document)
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

    enum ImportError: Error, LocalizedError {
        case unsupportedFormat
        case noVectorContent

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "This file format is not supported."
            case .noVectorContent: return "No vector content found in this file."
            }
        }
    }
}
