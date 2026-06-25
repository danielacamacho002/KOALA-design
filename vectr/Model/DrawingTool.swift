//
//  DrawingTool.swift
//  vectr
//

import Foundation

enum ToolCategory: String, CaseIterable, Codable {
    case line
    case circle
    case rectangle
    case move
    case scale
    case dimensions
    case trim
    case fillet
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
        case .move: return "Move"
        case .scale: return "Scale"
        case .dimensions: return "Dimensions"
        case .trim: return "Trim"
        case .fillet: return "Fillet"
        case .delete: return "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .line: return "line.diagonal"
        case .circle: return "circle"
        case .rectangle: return "rectangle"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        case .dimensions: return "ruler"
        case .trim: return "scissors"
        case .fillet: return "point.topleft.down.to.point.bottomright.curvepath"
        case .delete: return "trash"
        }
    }

    static var shapeCategories: [ToolCategory] {
        [.line, .circle, .rectangle]
    }

    static var actionCategories: [ToolCategory] {
        [.move, .scale, .dimensions, .trim, .fillet, .delete]
    }
}

enum LineVariant: String, CaseIterable, Codable {
    case line
    case arc
    case constructionLine

    var label: String {
        switch self {
        case .line: return "Line"
        case .arc: return "Arc"
        case .constructionLine: return "Construction"
        }
    }
}

enum CircleVariant: String, CaseIterable, Codable {
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

enum RectangleVariant: String, CaseIterable, Codable {
    case center
    case edge

    var label: String {
        switch self {
        case .center: return "Center"
        case .edge: return "Corner"
        }
    }
}
