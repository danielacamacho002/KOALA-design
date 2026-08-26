//
//  TextElement.swift
//  vectr
//

import CoreGraphics
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Reference to a font used by a `TextElement`. Built-in fonts store their
/// display name; imported fonts store the PostScript name (for resolution once
/// registered) plus the on-disk file name (so they survive save/reload).
enum FontRef: Codable, Equatable {
    case builtin(String)
    case imported(postScriptName: String, fileName: String)

    var displayName: String {
        switch self {
        case .builtin(let name):
            return name
        case .imported(let postScriptName, _):
            return postScriptName
        }
    }

    static var `default`: FontRef {
        .builtin(FontCatalog.defaultFontName)
    }
}

/// An editable text object placed on the canvas. Stays editable (content, font,
/// size, color, rotation) and is converted to vector glyph outlines only at
/// export time.
struct TextElement: Identifiable, Codable, Equatable {
    /// Default stroke weight (document units) for a text element's outline.
    static let defaultStrokeWidth: CGFloat = 1.5

    var id: UUID = UUID()
    var layerID: UUID
    var text: String
    /// Top-left anchor of the (unrotated) text block, in document space.
    var position: CGPoint
    var fontRef: FontRef
    /// Font size in document units.
    var fontSize: CGFloat
    /// Fill color for the glyphs (used when `isOutline` is `false`).
    var color: CodableColor
    /// Stroke color for the glyph outlines (used when `isOutline` is `true`).
    var strokeColor: CodableColor = CodableColor(.primary)
    /// Stroke weight in document units, applied when rendering as an outline.
    var strokeWidth: CGFloat = TextElement.defaultStrokeWidth
    /// When `true`, glyphs render hollow (stroke only, no fill).
    var isOutline: Bool = false
    /// CCW rotation in radians around the block center.
    var rotation: CGFloat = 0

    init(
        id: UUID = UUID(),
        layerID: UUID,
        text: String = "",
        position: CGPoint = .zero,
        fontRef: FontRef = .default,
        fontSize: CGFloat = 24,
        color: CodableColor = CodableColor(.primary),
        strokeColor: CodableColor = CodableColor(.primary),
        strokeWidth: CGFloat = TextElement.defaultStrokeWidth,
        isOutline: Bool = false,
        rotation: CGFloat = 0
    ) {
        self.id = id
        self.layerID = layerID
        self.text = text
        self.position = position
        self.fontRef = fontRef
        self.fontSize = fontSize
        self.color = color
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.isOutline = isOutline
        self.rotation = rotation
    }

    private enum CodingKeys: String, CodingKey {
        case id, layerID, text, position, fontRef, fontSize, color
        case strokeColor, strokeWidth, isOutline, rotation
    }

    // Custom decoding so documents saved before stroke/outline support (which
    // lack these keys) still load, falling back to sensible defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layerID = try container.decode(UUID.self, forKey: .layerID)
        text = try container.decode(String.self, forKey: .text)
        position = try container.decode(CGPoint.self, forKey: .position)
        fontRef = try container.decode(FontRef.self, forKey: .fontRef)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        color = try container.decode(CodableColor.self, forKey: .color)
        strokeColor = try container.decodeIfPresent(CodableColor.self, forKey: .strokeColor) ?? CodableColor(.primary)
        strokeWidth = try container.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? TextElement.defaultStrokeWidth
        isOutline = try container.decodeIfPresent(Bool.self, forKey: .isOutline) ?? false
        rotation = try container.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }

    /// Fill color as a `CGColor` (used when `isOutline` is `false`).
    var cgColor: CGColor {
        color.platformCGColor
    }

    /// Stroke color as a `CGColor` (used when `isOutline` is `true`).
    var strokeCGColor: CGColor {
        strokeColor.platformCGColor
    }
}

#if canImport(UIKit)
extension FontRef {
    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .builtin(let name):
            if let builtIn = FontCatalog.builtIn(named: name) {
                return builtIn.uiFont(size: size)
            }
            return UIFont.systemFont(ofSize: size)
        case .imported(let postScriptName, _):
            return UIFont(name: postScriptName, size: size) ?? UIFont.systemFont(ofSize: size)
        }
    }
}

extension TextElement {
    func resolvedUIFont() -> UIFont {
        fontRef.uiFont(size: fontSize)
    }

    /// Unrotated size of the laid-out text block, in document units.
    func textSize() -> CGSize {
        let font = resolvedUIFont()
        let measured = text.isEmpty ? " " : text
        let attributed = NSAttributedString(string: measured, attributes: [.font: font])
        let bounds = attributed.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// Axis-aligned bounding rect ignoring rotation (top-left anchored at `position`).
    var frame: CGRect {
        CGRect(origin: position, size: textSize())
    }

    var center: CGPoint {
        let f = frame
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// The four corners of the (possibly rotated) text block, in document space.
    func corners() -> [CGPoint] {
        let f = frame
        let base = [
            CGPoint(x: f.minX, y: f.minY),
            CGPoint(x: f.maxX, y: f.minY),
            CGPoint(x: f.maxX, y: f.maxY),
            CGPoint(x: f.minX, y: f.maxY)
        ]
        guard rotation != 0 else { return base }
        let pivot = center
        return base.map { rotatePoint($0, around: pivot, by: rotation) }
    }

    func contains(_ point: CGPoint) -> Bool {
        let f = frame
        guard rotation != 0 else { return f.contains(point) }
        let local = rotatePoint(point, around: center, by: -rotation)
        return f.contains(local)
    }

    func boundingBox() -> CGRect {
        guard rotation != 0 else { return frame }
        let pts = corners()
        var rect = CGRect.null
        for point in pts { rect = rect.union(CGRect(origin: point, size: .zero)) }
        return rect
    }

    private func rotatePoint(_ point: CGPoint, around pivot: CGPoint, by radians: CGFloat) -> CGPoint {
        let cosA = cos(radians)
        let sinA = sin(radians)
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return CGPoint(
            x: pivot.x + dx * cosA - dy * sinA,
            y: pivot.y + dx * sinA + dy * cosA
        )
    }
}

extension VectrDocument {
    enum ElementHit: Equatable {
        case text(UUID)
        case stroke(UUID)
        case none
    }

    /// Selects the top-most selectable (visible, unlocked layer) text element hit by `documentPoint`.
    @discardableResult
    func selectTextElement(at documentPoint: CGPoint) -> TextElement? {
        if isHitOnInactiveLayer(near: documentPoint, threshold: 0) {
            return nil
        }
        let hit = textElement(at: documentPoint)
        if let hit {
            selectTextConsideringGroups(hit.id)
        } else {
            setElementSelection(strokeIDs: [], textIDs: [])
        }
        return hit
    }

    /// The top-most selectable text element hit by `documentPoint`, without changing selection.
    /// Returns nil when another layer's text is in front, so tools cannot punch through.
    func textElement(at documentPoint: CGPoint) -> TextElement? {
        guard let hit = occupyingTextElements().reversed().first(where: { $0.contains(documentPoint) }) else {
            return nil
        }
        return isSelectableText(hit) ? hit : nil
    }

    /// Unified selection: prefers a hit text element, otherwise falls back to
    /// stroke hit testing. Text and strokes share a single active selection so
    /// the standard manipulation tools (move/scale/delete) treat text like a shape.
    /// Selecting any member of a group expands to the whole group.
    /// A tap on another layer's item is ignored (does not select or clear).
    @discardableResult
    func selectElement(near documentPoint: CGPoint, threshold: CGFloat) -> ElementHit {
        if isHitOnInactiveLayer(near: documentPoint, threshold: threshold) {
            return .none
        }
        if let text = textElement(at: documentPoint) {
            selectTextConsideringGroups(text.id)
            return .text(text.id)
        }
        if let stroke = strokeHit(near: documentPoint, threshold: threshold) {
            selectStrokeConsideringGroups(stroke.id)
            return .stroke(stroke.id)
        }
        clearElementSelection()
        return .none
    }
}
#endif
