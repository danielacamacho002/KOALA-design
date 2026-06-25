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

struct VectorStroke: Identifiable, Codable, Equatable {
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
    /// Infinite dashed reference line (not filled as a plane).
    var isConstruction: Bool = false
    var shapeType: StrokeShapeType = .polyline
    /// Nested closed contours subtracted from the fill (even-odd), e.g. inner circle holes.
    var cutoutPoints: [[CGPoint]] = []

    init(
        id: UUID = UUID(),
        layerID: UUID,
        points: [CGPoint] = [],
        strokeWidth: CGFloat = 1.5,
        strokeColor: CodableColor = CodableColor(.primary),
        isClosed: Bool = false,
        cornerRadius: CGFloat = 0,
        cornerRadiiByIndex: [Int: CGFloat]? = nil,
        isConstruction: Bool = false,
        shapeType: StrokeShapeType = .polyline,
        cutoutPoints: [[CGPoint]] = []
    ) {
        self.id = id
        self.layerID = layerID
        self.points = points
        self.strokeWidth = strokeWidth
        self.strokeColor = strokeColor
        self.isClosed = isClosed
        self.cornerRadius = cornerRadius
        self.cornerRadiiByIndex = cornerRadiiByIndex
        self.isConstruction = isConstruction
        self.shapeType = shapeType
        self.cutoutPoints = cutoutPoints
    }

    func displayPath() -> CGPath {
        if hasAnyCornerFillets {
            return FilletPathBuilder.path(for: self)
        }
        return cgPath()
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
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        if isClosed, points.count > 2 {
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

/// Codable wrapper for SwiftUI/UIColor colors in documents.
struct CodableColor: Codable, Equatable {
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
        platform.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let platform = NSColor(color)
        platform.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        red = r
        green = g
        blue = b
        alpha = a
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

extension CGPoint: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(CGFloat.self)
        let y = try container.decode(CGFloat.self)
        self.init(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}
