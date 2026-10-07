//
//  DrawingTool.swift
//  Koala
//

import Foundation

nonisolated enum ToolCategory: String, CaseIterable, Codable, Sendable {
    case line
    case circle
    case rectangle
    case curve
    case type
    case move
    case scale
    case dimensions
    case trim
    case fillet
    case addAnchor
    case pattern
    case copy
    case delete

    var isDrawingTool: Bool {
        switch self {
        case .line, .circle, .rectangle: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .line: return "Line"
        case .circle: return "Circle"
        case .rectangle: return "Rectangle"
        case .curve: return "Curve"
        case .type: return "Type"
        case .move: return "Move"
        case .scale: return "Scale"
        case .dimensions: return "Dimensions"
        case .trim: return "Trim"
        case .fillet: return "Fillet"
        case .addAnchor: return "Add Anchor"
        case .pattern: return "Pattern"
        case .copy: return "Copy"
        case .delete: return "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .line: return "line.diagonal"
        case .circle: return "circle"
        case .rectangle: return "rectangle"
        case .curve: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .type: return "textformat"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        case .dimensions: return "ruler"
        case .trim: return "scissors"
        case .fillet: return "point.topleft.down.to.point.bottomright.curvepath"
        case .addAnchor: return "plus.circle"
        case .pattern: return "square.grid.3x3"
        case .copy: return "doc.on.doc"
        case .delete: return "trash"
        }
    }

    static var shapeCategories: [ToolCategory] {
        [.line, .circle, .rectangle, .curve, .type]
    }

    static var actionCategories: [ToolCategory] {
        [.move, .scale, .dimensions, .trim, .fillet, .addAnchor, .pattern, .copy, .delete]
    }
}

nonisolated enum LineVariant: String, CaseIterable, Codable, Sendable {
    case line
    case arc
    case constructionLine

    var label: String {
        switch self {
        case .line: return "Line"
        case .arc: return "Arc"
        case .constructionLine: return "Const."
        }
    }
}

nonisolated enum CircleVariant: String, CaseIterable, Codable, Sendable {
    case center
    case edge
    case ellipse

    var label: String {
        switch self {
        case .center: return "Center"
        case .edge: return "Edge"
        case .ellipse: return "Ellipse"
        }
    }
}

nonisolated enum RectangleVariant: String, CaseIterable, Codable, Sendable {
    case center
    case edge

    var label: String {
        switch self {
        case .center: return "Center"
        case .edge: return "Corner"
        }
    }
}
