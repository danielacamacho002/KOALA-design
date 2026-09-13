//
//  VectorStroke.swift
//  vectr
//

import CoreGraphics
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated struct VectorStroke: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var layerID: UUID
    var points: [CGPoint]
    var strokeWidth: CGFloat
    var strokeColor: CodableColor
    var isClosed: Bool
    /// Corner fillet radius in document units (0 = sharp corners).
    var cornerRadius: CGFloat = 0
    /// Corner-specific fillet radius overrides keyed by vertex index.
    /// Missing indices fall back to `cornerRadius`.
    var cornerRadiiByIndex: [Int: CGFloat]? = nil
    /// Vertex indices that are the midpoint of a baked fillet arc. These points stay editable
    /// anchors, but rendering/export re-expands them into a smooth circular arc passing through
    /// (previous anchor, this midpoint, next anchor).
    var smoothCornerIndices: Set<Int>? = nil
    /// Dashed reference segment (not filled as a plane).
    var isConstruction: Bool = false
    var shapeType: StrokeShapeType = .polyline
    /// CCW rotation from +X for parametric circle/ellipse storage (nil treated as 0).
    var shapeRotation: CGFloat? = nil
    /// Original points at draw time; used to restore 0° orientation for point-based shapes.
    var rotationBasePoints: [CGPoint]? = nil
    /// Shape center when `rotationBasePoints` was captured.
    var rotationBaseCenter: CGPoint? = nil
    /// Nested closed contours subtracted from the fill (even-odd), e.g. inner circle holes.
    var cutoutPoints: [[CGPoint]] = []
    /// Indices `i` (into `points`) whose outgoing edge `points[i] → points[i+1]` is a
    /// Boolean *cut* edge: it bounds a notch carved out of an edge and must be filled
    /// through but NOT stroked, so a through-cut has no outline along the removed area.
    var openEdgeStarts: [Int]? = nil
    /// Indices into `cutoutPoints` for holes punched by a Boolean cut. They still carve
    /// the fill (even-odd) but are NOT stroked, so a punched hole has no outline —
    /// unlike donut rings, whose inner circle is a real, stroked edge.
    var openCutoutIndices: Set<Int>? = nil
    /// Editable Bezier tangent handles for `.curve` strokes, one entry per anchor in `points`.
    /// When nil, curves fall back to the auto-computed cardinal spline.
    var curveHandles: [CurveHandle]? = nil
    /// Fill opacity (0...1) for closed shapes. `nil` falls back to `defaultFillOpacity`.
    var fillOpacity: CGFloat? = nil
    /// When `true`, omitted from canvas, hit-testing, and export.
    /// Optional so older documents without this key still decode: synthesized
    /// Codable throws on a missing non-optional key even when a default exists.
    var isHidden: Bool? = nil

    /// Default plane fill opacity for closed shapes that have never been customized.
    static let defaultFillOpacity: CGFloat = 0.25

    init(
        id: UUID = UUID(),
        layerID: UUID,
        points: [CGPoint] = [],
        strokeWidth: CGFloat = 1.5,
        strokeColor: CodableColor = CodableColor(.primary),
        isClosed: Bool = false,
        cornerRadius: CGFloat = 0,
        cornerRadiiByIndex: [Int: CGFloat]? = nil,
        smoothCornerIndices: Set<Int>? = nil,
        isConstruction: Bool = false,
        shapeType: StrokeShapeType = .polyline,
        shapeRotation: CGFloat? = nil,
        rotationBasePoints: [CGPoint]? = nil,
        rotationBaseCenter: CGPoint? = nil,
        cutoutPoints: [[CGPoint]] = [],
        openEdgeStarts: [Int]? = nil,
        openCutoutIndices: Set<Int>? = nil,
        curveHandles: [CurveHandle]? = nil,
        fillOpacity: CGFloat? = nil,
        isHidden: Bool? = nil
    ) {
        self.id = id
        self.layerID = layerID
        self.points = points
        self.strokeWidth = strokeWidth
        self.strokeColor = strokeColor
        self.isClosed = isClosed
        self.cornerRadius = cornerRadius
        self.cornerRadiiByIndex = cornerRadiiByIndex
        self.smoothCornerIndices = smoothCornerIndices
        self.isConstruction = isConstruction
        self.shapeType = shapeType
        self.shapeRotation = shapeRotation
        self.rotationBasePoints = rotationBasePoints
        self.rotationBaseCenter = rotationBaseCenter
        self.cutoutPoints = cutoutPoints
        self.openEdgeStarts = openEdgeStarts
        self.openCutoutIndices = openCutoutIndices
        self.curveHandles = curveHandles
        self.fillOpacity = fillOpacity
        self.isHidden = isHidden
    }

    /// True when this stroke should be omitted from canvas, hit-testing, and export.
    var isHiddenFromCanvas: Bool { isHidden == true }

    var resolvedShapeRotation: CGFloat {
        shapeRotation ?? 0
    }

    /// Effective fill opacity for closed, non-construction shapes, clamped to 0...1.
    var resolvedFillOpacity: CGFloat {
        min(1, max(0, fillOpacity ?? VectorStroke.defaultFillOpacity))
    }

    var rotationDegrees: Double {
        ShapeGeometry.normalizedRotationDegrees(resolvedShapeRotation)
    }

    func displayPath() -> CGPath {
        if hasAnyCornerFillets {
            return FilletPathBuilder.path(for: self)
        }
        if hasBakedSmoothCorners {
            return smoothCGPath()
        }
        return cgPath()
    }

    var hasBakedSmoothCorners: Bool {
        guard let smoothCornerIndices else { return false }
        return !smoothCornerIndices.isEmpty
    }

    /// Path that renders baked fillet corners as smooth circular arcs while keeping the stored
    /// anchor set minimal (three anchors per corner).
    private func smoothCGPath() -> CGPath {
        let contour = ShapeGeometry.renderPoints(for: self)
        let path = CGMutablePath()
        guard let first = contour.first else { return path }
        path.move(to: first)
        for point in contour.dropFirst() {
            path.addLine(to: point)
        }
        if isClosed, shapeType != .arc, contour.count > 2 {
            path.closeSubpath()
        }
        return path
    }

    var hasAnyCornerFillets: Bool {
        if cornerRadius > 0 { return true }
        guard let cornerRadiiByIndex else { return false }
        return cornerRadiiByIndex.contains { $0.value > 0 }
    }

    func filletCornerIndices() -> [Int] {
        var count = points.count
        if isClosed,
           count > 1,
           hypot(points[0].x - points[count - 1].x, points[0].y - points[count - 1].y) <= 0.001 {
            count -= 1
        }
        guard count >= 3 else { return [] }
        if isClosed {
            return Array(0..<count)
        }
        return Array(1..<(count - 1))
    }

    /// Corner radii after applying global fallback + per-corner overrides.
    /// Returns only corners that have an effective radius > 0.
    func resolvedFilletCornerRadii() -> [Int: CGFloat] {
        let validIndices = Set(filletCornerIndices())
        guard !validIndices.isEmpty else { return [:] }

        var resolved: [Int: CGFloat] = [:]
        if cornerRadius > 0 {
            for index in validIndices {
                resolved[index] = cornerRadius
            }
        }
        if let cornerRadiiByIndex {
            for (index, radius) in cornerRadiiByIndex where validIndices.contains(index) {
                resolved[index] = max(0, radius)
            }
        }
        return resolved.filter { $0.value > 0 }
    }

    var cgColor: CGColor {
        strokeColor.platformCGColor
    }

    var swiftUIColor: Color {
        strokeColor.color
    }

    func cgPath() -> CGPath {
        let path = CGMutablePath()
        // Sparse parametric shapes expand through renderPoints so export/extrude
        // match on-canvas geometry (curves, circles, ellipses, and arcs).
        let pathPoints: [CGPoint]
        switch shapeType {
        case .curve, .circle, .ellipse, .arc:
            pathPoints = ShapeGeometry.renderPoints(for: self)
        default:
            pathPoints = points
        }
        guard let first = pathPoints.first else { return path }
        path.move(to: first)
        for point in pathPoints.dropFirst() {
            path.addLine(to: point)
        }
        if isClosed, shapeType != .arc, pathPoints.count > 2 {
            path.closeSubpath()
        }
        return path
    }

    func boundingBox(padding: CGFloat = 0) -> CGRect? {
        guard !points.isEmpty else { return nil }
        var minX = points[0].x
        var maxX = points[0].x
        var minY = points[0].y
        var maxY = points[0].y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
    }

    /// Independent copy translated by `offset`, keeping every modifier so Duplicate
    /// matches the original: fillets, baked smooth corners, holes, cut edges, curve
    /// handles, rotation baseline, and fill.
    func duplicated(offset: CGPoint) -> VectorStroke {
        var copy = self
        copy.id = UUID()
        return copy.offsettingGeometry(by: offset)
    }

    /// Shifts every stored point by `offset` without changing identity or modifiers.
    func offsettingGeometry(by offset: CGPoint) -> VectorStroke {
        guard offset != .zero else { return self }
        var copy = self
        copy.points = copy.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        copy.cutoutPoints = copy.cutoutPoints.map { contour in
            contour.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        }
        if let basePoints = copy.rotationBasePoints {
            copy.rotationBasePoints = basePoints.map {
                CGPoint(x: $0.x + offset.x, y: $0.y + offset.y)
            }
        }
        if let center = copy.rotationBaseCenter {
            copy.rotationBaseCenter = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
        }
        return copy
    }

    func distance(to point: CGPoint) -> CGFloat {
        let samplePoints = ShapeGeometry.renderPoints(for: self)
        guard samplePoints.count >= 2 else {
            guard let only = samplePoints.first ?? points.first else { return .greatestFiniteMagnitude }
            return hypot(point.x - only.x, point.y - only.y)
        }
        var best = CGFloat.greatestFiniteMagnitude
        let count = isClosed ? samplePoints.count : samplePoints.count - 1
        for index in 0..<count {
            let start = samplePoints[index]
            let end = samplePoints[(index + 1) % samplePoints.count]
            best = min(best, distance(from: point, toSegmentFrom: start, to: end))
        }
        return best
    }

    func contains(_ point: CGPoint) -> Bool {
        guard isClosed, !isConstruction else { return false }
        let contourPoints = ShapeGeometry.renderPoints(for: self)
        guard contourPoints.count >= 3 else { return false }

        let path = CGMutablePath()
        appendContour(contourPoints, to: path)

        for cutout in cutoutPoints {
            guard cutout.count >= 3 else { continue }
            let renderedCutout = ShapeGeometry.renderPoints(
                for: VectorStroke(
                    layerID: layerID,
                    points: cutout,
                    isClosed: true,
                    shapeType: .circle
                )
            )
            appendContour(renderedCutout, to: path)
        }

        let fillRule: CGPathFillRule = cutoutPoints.isEmpty ? .winding : .evenOdd
        return path.contains(point, using: fillRule, transform: .identity)
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projX = start.x + t * dx
        let projY = start.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }

    private func appendContour(_ points: [CGPoint], to path: CGMutablePath) {
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
    }
}

/// Bezier tangent handles for a single curve anchor, stored as offsets from the anchor.
/// Absolute control point = anchor + offset.
nonisolated struct CurveHandle: Codable, Equatable, Sendable {
    /// Control point leading into the anchor (from the previous segment).
    var inOffset: CGPoint
    /// Control point leading out of the anchor (toward the next segment).
    var outOffset: CGPoint

    init(inOffset: CGPoint = .zero, outOffset: CGPoint = .zero) {
        self.inOffset = inOffset
        self.outOffset = outOffset
    }
}

/// Codable wrapper for SwiftUI/UIColor colors in documents.
nonisolated struct CodableColor: Codable, Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(_ color: Color) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        #if canImport(UIKit)
        let platform = UIColor(color)
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let srgb = platform.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
           let comps = srgb.components, comps.count >= 3 {
            r = comps[0]
            g = comps[1]
            b = comps[2]
            if comps.count > 3 { a = comps[3] }
        } else {
            platform.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        #elseif canImport(AppKit)
        let platform = NSColor(color)
        platform.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        red = min(1, max(0, r))
        green = min(1, max(0, g))
        blue = min(1, max(0, b))
        alpha = min(1, max(0, a))
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var platformCGColor: CGColor {
        #if canImport(UIKit)
        UIColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
        #elseif canImport(AppKit)
        NSColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
        #else
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }
}
