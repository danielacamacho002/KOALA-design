//
//  StrokeShapeType.swift
//  vectr
//

import Foundation

enum StrokeShapeType: String, Codable, Equatable {
    case polyline
    case circle
    case rectangle
    case arc
    case construction
    case ellipse
    /// Smooth spline whose `points` store the drawn anchors; expanded to a curve at render time.
    case curve
}
