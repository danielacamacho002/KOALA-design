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
            let pathData = pathData(from: points, closed: stroke.isClosed)
            let color = stroke.strokeColor
            let strokeHex = String(format: "#%02X%02X%02X", Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255))
            let fill = stroke.isClosed && !stroke.isConstruction ? " fill=\"#CCCCCC\" fill-opacity=\"\(stroke.resolvedFillOpacity)\"" : " fill=\"none\""
            svg += "  <path d=\"\(pathData)\" stroke=\"\(strokeHex)\" stroke-width=\"\(stroke.strokeWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(fill)/>\n"
        }

        for element in document.visibleTextElements() {
            let outline = TextOutline.path(for: element)
            let data = pathData(from: outline)
            guard !data.isEmpty else { continue }
            let color = element.color
            let fillHex = String(format: "#%02X%02X%02X", Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255))
            svg += "  <path d=\"\(data)\" fill=\"\(fillHex)\" fill-opacity=\"\(color.alpha)\" fill-rule=\"nonzero\"/>\n"
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
}
