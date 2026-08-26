//
//  ElementClipboard.swift
//  vectr
//

import Foundation

/// In-memory copy buffer so items can move between layers after selection is cleared.
struct ElementClipboard: Equatable {
    var strokes: [VectorStroke] = []
    var textElements: [TextElement] = []
    var groups: [ObjectGroup] = []

    var isEmpty: Bool { strokes.isEmpty && textElements.isEmpty }

    var itemCount: Int { strokes.count + textElements.count }

    var summary: String {
        guard !isEmpty else { return "Clipboard empty" }
        let shapePart: String?
        switch strokes.count {
        case 0: shapePart = nil
        case 1: shapePart = "1 shape"
        default: shapePart = "\(strokes.count) shapes"
        }
        let textPart: String?
        switch textElements.count {
        case 0: textPart = nil
        case 1: textPart = "1 text"
        default: textPart = "\(textElements.count) texts"
        }
        return [shapePart, textPart].compactMap { $0 }.joined(separator: ", ") + " copied"
    }
}
