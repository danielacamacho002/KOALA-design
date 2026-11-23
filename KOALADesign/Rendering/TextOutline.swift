//
//  TextOutline.swift
//  Koala
//

import CoreGraphics
import CoreText
import UIKit

/// Converts a `TextElement` into vector glyph outlines (a `CGPath`) in document
/// space. This is the single source of truth for exporting text as true vectors
/// (SVG/PDF/image), so exports never depend on the viewer having the font.
nonisolated enum TextOutline: Sendable {
    static func path(for element: TextElement) -> CGPath {
        let result = CGMutablePath()
        guard !element.text.isEmpty else { return result }

        let font = element.fontRef.uiFont(size: element.fontSize)
        let lineHeight = font.lineHeight
        let ascent = font.ascender
        let lines = element.text.components(separatedBy: CharacterSet.newlines)

        for (lineIndex, lineText) in lines.enumerated() {
            guard !lineText.isEmpty else { continue }
            let baselineY = element.position.y + CGFloat(lineIndex) * lineHeight + ascent

            let attributed = NSAttributedString(string: lineText, attributes: [.font: font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else { continue }

            for run in runs {
                let glyphCount = CTRunGetGlyphCount(run)
                guard glyphCount > 0 else { continue }

                let runFont = resolveFont(for: run, fallback: font)
                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)

                for index in 0..<glyphCount {
                    // Flip Core Text's y-up glyph space into the document's y-down
                    // space and translate to the glyph's pen position.
                    var transform = CGAffineTransform(
                        a: 1, b: 0, c: 0, d: -1,
                        tx: element.position.x + positions[index].x,
                        ty: baselineY - positions[index].y
                    )
                    if let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[index], &transform) {
                        result.addPath(glyphPath)
                    }
                }
            }
        }

        guard element.rotation != 0 else { return result }
        let center = element.center
        var rotation = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: element.rotation)
            .translatedBy(x: -center.x, y: -center.y)
        return result.copy(using: &rotation) ?? result
    }

    private static func resolveFont(for run: CTRun, fallback: UIFont) -> CTFont {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        if let value = attributes[kCTFontAttributeName as String],
           CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() {
            return value as! CTFont
        }
        return fallback as CTFont
    }
}
