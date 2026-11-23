//
//  StrokeShapeType.swift
//  Koala
//

import Foundation

nonisolated enum StrokeShapeType: String, Codable, Equatable, Sendable {
    case polyline
    case circle
    case rectangle
    case arc
    case construction
    case ellipse
    /// Smooth spline whose `points` store the drawn anchors; expanded to a curve at render time.
    case curve
}

/// SVG / Core Graphics fill rule for compound paths (letters, overlapping ovals).
nonisolated enum PathFillRule: String, Codable, Equatable, Sendable {
    case nonzero
    case evenodd
}
