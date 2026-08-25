//
//  SVGExporter.swift
//  vectr
//

import CoreGraphics
import Foundation

enum SVGExporter {
    static func export(document: VectrDocument) -> String {
        let bounds = DocumentRenderer.boundingRect(for: document)
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(bounds.minX) \(bounds.minY) \(width) \(height)" width="\(width)" height="\(height)">

        """
        for stroke in document.visibleStrokes() {
            let points = ShapeGeometry.renderPoints(for: stroke)
            guard points.count >= 2 else { continue }
            let color = stroke.strokeColor
            let strokeHex = String(format: "#%02X%02X%02X", Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255))
            let isFilled = stroke.isClosed && !stroke.isConstruction
            let cutEdges = Set(stroke.openEdgeStarts ?? [])

            if isFilled, !cutEdges.isEmpty {
                // Fill the full contour, then stroke only the retained (non-cut) edges so
                // the carved notch has no outline.
                let fillData = pathData(from: points, closed: true)
                svg += "  <path d=\"\(fillData)\" fill=\"#CCCCCC\" fill-opacity=\"\(stroke.resolvedFillOpacity)\" stroke=\"none\"/>\n"
                let strokeData = strokePathData(from: points, cutEdges: cutEdges)
                if !strokeData.isEmpty {
                    svg += "  <path d=\"\(strokeData)\" fill=\"none\" stroke=\"\(strokeHex)\" stroke-width=\"\(stroke.strokeWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
                }
            } else {
                let pathData = pathData(from: points, closed: stroke.isClosed)
                let fill = isFilled ? " fill=\"#CCCCCC\" fill-opacity=\"\(stroke.resolvedFillOpacity)\"" : " fill=\"none\""
                svg += "  <path d=\"\(pathData)\" stroke=\"\(strokeHex)\" stroke-width=\"\(stroke.strokeWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(fill)/>\n"
            }
        }

        for element in document.visibleTextElements() {
            let outline = TextOutline.path(for: element)
            let data = pathData(from: outline)
            guard !data.isEmpty else { continue }
            if element.isOutline {
                let color = element.strokeColor
                let strokeHex = String(format: "#%02X%02X%02X", Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255))
                svg += "  <path d=\"\(data)\" fill=\"none\" stroke=\"\(strokeHex)\" stroke-opacity=\"\(color.alpha)\" stroke-width=\"\(element.strokeWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
            } else {
                let color = element.color
                let fillHex = String(format: "#%02X%02X%02X", Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255))
                svg += "  <path d=\"\(data)\" fill=\"\(fillHex)\" fill-opacity=\"\(color.alpha)\" fill-rule=\"nonzero\"/>\n"
            }
        }

        svg += "</svg>\n"
        return svg
    }

    /// Serializes an arbitrary CGPath (including glyph outlines with curves) to SVG path data.
    private static func pathData(from path: CGPath) -> String {
        var data = ""
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                data += "M \(points[0].x) \(points[0].y) "
            case .addLineToPoint:
                data += "L \(points[0].x) \(points[0].y) "
            case .addQuadCurveToPoint:
                data += "Q \(points[0].x) \(points[0].y) \(points[1].x) \(points[1].y) "
            case .addCurveToPoint:
                data += "C \(points[0].x) \(points[0].y) \(points[1].x) \(points[1].y) \(points[2].x) \(points[2].y) "
            case .closeSubpath:
                data += "Z "
            @unknown default:
                break
            }
        }
        return data.trimmingCharacters(in: .whitespaces)
    }

    static func write(document: VectrDocument, to url: URL) throws {
        let svg = export(document: document)
        try svg.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func pathData(from points: [CGPoint], closed: Bool) -> String {
        guard let first = points.first else { return "" }
        var data = "M \(first.x) \(first.y)"
        for point in points.dropFirst() {
            data += " L \(point.x) \(point.y)"
        }
        if closed, points.count > 2 { data += " Z" }
        return data
    }

    /// Open subpaths tracing only the non-cut edges of a closed contour, so cut edges
    /// (`cutEdges` = start indices of edge `points[i] → points[i+1]`) are not stroked.
    private static func strokePathData(from points: [CGPoint], cutEdges: Set<Int>) -> String {
        let count = points.count
        guard count >= 2, let firstCut = (0..<count).first(where: { cutEdges.contains($0) }) else {
            return pathData(from: points, closed: true)
        }
        var data = ""
        var subpathOpen = false
        for step in 1...count {
            let edge = (firstCut + step) % count
            if cutEdges.contains(edge) {
                subpathOpen = false
            } else {
                let start = points[edge]
                let end = points[(edge + 1) % count]
                if !subpathOpen {
                    data += "M \(start.x) \(start.y) "
                    subpathOpen = true
                }
                data += "L \(end.x) \(end.y) "
            }
        }
        return data.trimmingCharacters(in: .whitespaces)
    }
}
