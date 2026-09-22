import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import vectr

@MainActor
struct ImportRouterTests {
    @Test func jpegImportAddsReferenceImageWithoutReplacingStrokes() throws {
        let url = try writeJPEG()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = VectrDocument()
        let existing = VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        )
        document.addStroke(existing)

        let content = try ImportRouter.loadContent(from: url, layerID: document.activeLayerID)
        #expect(content.hasReferenceImage)
        #expect(content.strokes.isEmpty)
        #expect(content.referenceImages[0].layerID == document.activeLayerID)

        let importedCount = try document.importContent(content)
        #expect(importedCount == 0)
        #expect(document.strokes.count == 1)
        #expect(document.strokes[0].id == existing.id)
        #expect(document.referenceImages.count == 1)
        #expect(document.referenceImages[0].data == content.referenceImages[0].data)
        #expect(document.referenceImages[0].frame == content.referenceImages[0].frame)
        #expect(document.referenceImages[0].layerID == document.activeLayerID)
        #expect(document.isReferenceImageSelected)
    }

    @Test func svgImportAppendsCenteredStrokesToActiveLayer() throws {
        let url = try writeSVG(body: #"<line x1="0" y1="0" x2="40" y2="0" stroke="black"/>"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = VectrDocument()
        let existing = VectorStroke(
            layerID: document.activeLayerID,
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 100)]
        )
        document.addStroke(existing)

        let content = try ImportRouter.loadContent(from: url, layerID: document.activeLayerID)
        #expect(content.strokes.count == 1)

        let importedCount = try document.importContent(content, offset: CGPoint(x: 5, y: -3))
        #expect(importedCount == 1)
        #expect(document.strokes.count == 2)
        #expect(document.strokes[0].id == existing.id)

        let imported = document.strokes[1]
        #expect(imported.id != content.strokes[0].id)
        #expect(imported.layerID == document.activeLayerID)
        #expect(imported.points == [
            CGPoint(x: content.strokes[0].points[0].x + 5, y: content.strokes[0].points[0].y - 3),
            CGPoint(x: content.strokes[0].points[1].x + 5, y: content.strokes[0].points[1].y - 3)
        ])
    }

    @Test func svgTextImportAddsEditableText() throws {
        let url = try writeSVG(body: #"<text x="0" y="20" font-family="Georgia" font-size="18" fill="black">Hello</text>"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = VectrDocument()
        let content = try ImportRouter.loadContent(from: url, layerID: document.activeLayerID)
        #expect(content.strokes.isEmpty)
        #expect(content.textElements.count == 1)
        #expect(content.textElements[0].text == "Hello")
        #expect(content.textElements[0].fontRef == .builtin("Georgia"))

        #expect(try document.importContent(content) == 1)
        #expect(document.textElements.count == 1)
        #expect(document.textElements[0].layerID == document.activeLayerID)
    }

    @Test func emptySVGThrowsNoVectorContent() throws {
        let url = try writeSVG(body: "")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ImportRouter.ImportError.noVectorContent) {
            try ImportRouter.loadContent(from: url, layerID: UUID())
        }
    }

    @Test func unsupportedFormatThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ImportRouter.ImportError.unsupportedFormat) {
            try ImportRouter.loadContent(from: url, layerID: UUID())
        }
    }

    @Test func vectorImportOntoLockedLayerThrows() throws {
        let url = try writeSVG(body: #"<line x1="0" y1="0" x2="10" y2="0" stroke="black"/>"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = VectrDocument()
        document.toggleLayerLock(id: document.activeLayerID)
        let content = try ImportRouter.loadContent(from: url, layerID: document.activeLayerID)

        #expect(throws: ImportRouter.ImportError.layerLocked) {
            try document.importContent(content)
        }
        #expect(document.strokes.isEmpty)
    }

    @Test func jpegImportOntoLockedLayerThrows() throws {
        let url = try writeJPEG()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = VectrDocument()
        document.toggleLayerLock(id: document.activeLayerID)
        let content = try ImportRouter.loadContent(from: url, layerID: document.activeLayerID)

        #expect(throws: ImportRouter.ImportError.layerLocked) {
            try document.importContent(content)
        }
        #expect(document.referenceImages.isEmpty)
        #expect(!document.isReferenceImageSelected)
    }

    @Test func pngImportAddsReferenceImage() throws {
        let url = try writePNG()
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try ImportRouter.loadContent(from: url, layerID: UUID())
        #expect(content.hasReferenceImage)
        #expect(content.referenceImages.first?.frame.width == 2)
        #expect(content.referenceImages.first?.frame.height == 2)
    }

    private func writeJPEG() throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: pointScaleFormat())
        let data = renderer.jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }

    private func writePNG() throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: pointScaleFormat())
        let data = renderer.pngData { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    /// Keep fixture pixels 1:1 with points so retina simulators don't 2× the imported frame.
    private func pointScaleFormat() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return format
    }

    private func writeSVG(body: String) throws -> URL {
        let xml = """
        <svg xmlns="http://www.w3.org/2000/svg" width="40" height="10">
        \(body)
        </svg>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).svg")
        try Data(xml.utf8).write(to: url)
        return url
    }
}
