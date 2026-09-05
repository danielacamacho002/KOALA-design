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
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" viewBox="\(bounds.minX) \(bounds.minY) \(width) \(height)" width="\(width)" height="\(height)">

        """

        let strokesByLayer = Dictionary(grouping: document.visibleStrokes(), by: \.layerID)
        let textByLayer = Dictionary(grouping: document.visibleTextElements(), by: \.layerID)

        func hasContent(_ layerID: UUID) -> Bool {
            !(strokesByLayer[layerID] ?? []).isEmpty || !(textByLayer[layerID] ?? []).isEmpty
        }

        var index = 0
        let layers = document.layers
        while index < layers.count {
            let layer = layers[index]
            if let groupID = layer.groupID, let folder = document.layerGroup(with: groupID) {
                var members: [Layer] = []
                while index < layers.count, layers[index].groupID == groupID {
                    members.append(layers[index])
                    index += 1
                }
                let visibleMembers = members.filter { $0.isVisible && hasContent($0.id) }
                guard !visibleMembers.isEmpty else { continue }
                svg += groupOpen(id: folder.id, prefix: "folder", name: folder.name, indent: 1)
                for member in visibleMembers {
                    svg += layerMarkup(
                        member,
                        strokes: strokesByLayer[member.id] ?? [],
                        text: textByLayer[member.id] ?? [],
                        indent: 2
                    )
                }
                svg += groupClose(indent: 1)
            } else {
                if layer.isVisible, hasContent(layer.id) {
                    svg += layerMarkup(
                        layer,
                        strokes: strokesByLayer[layer.id] ?? [],
                        text: textByLayer[layer.id] ?? [],
                        indent: 1
                    )
                }
                index += 1
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

    // MARK: - Layer groups

    private static func layerMarkup(
        _ layer: Layer,
        strokes: [VectorStroke],
        text: [TextElement],
        indent: Int
    ) -> String {
        var markup = groupOpen(
            id: layer.id,
            prefix: "layer",
            name: layer.name,
            indent: indent,
            opacity: layer.resolvedOpacity
        )
        let pathIndent = indent + 1
        for stroke in strokes {
            markup += strokeMarkup(stroke, indent: pathIndent)
        }
        for element in text {
            markup += textMarkup(element, indent: pathIndent)
        }
        markup += groupClose(indent: indent)
        return markup
    }

    private static func groupOpen(
        id: UUID,
        prefix: String,
        name: String,
        indent: Int,
        opacity: CGFloat = 1
    ) -> String {
        let escaped = escapeXML(name)
        let opacityAttr = opacity < 0.999 ? " opacity=\"\(opacity)\"" : ""
        return "\(pad(indent))<g id=\"\(prefix)-\(id.uuidString)\" data-name=\"\(escaped)\" inkscape:groupmode=\"layer\" inkscape:label=\"\(escaped)\"\(opacityAttr)>\n"
    }

    private static func groupClose(indent: Int) -> String {
        "\(pad(indent))</g>\n"
    }

    private static func pad(_ indent: Int) -> String {
        String(repeating: "  ", count: indent)
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Geometry

    private static func strokeMarkup(_ stroke: VectorStroke, indent: Int) -> String {
        let color = stroke.strokeColor
        let paintHex = hexRGB(from: color)
        let strokeOpacity = formatSVG(clampedUnit(color.alpha))
        let lineWidth = formatSVG(max(0, stroke.strokeWidth))
        let isFilled = stroke.isClosed && !stroke.isConstruction
        let cutEdges = Set(stroke.openEdgeStarts ?? [])
        let prefix = pad(indent)
        let fillRule = stroke.cutoutPoints.isEmpty ? "" : " fill-rule=\"evenodd\""
        let dash = stroke.isConstruction ? " stroke-dasharray=\"10 6\"" : ""
        let strokePaint = "stroke=\"\(paintHex)\" stroke-opacity=\"\(strokeOpacity)\" stroke-width=\"\(lineWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(dash)"

        // Same path the canvas uses, so live fillets (`cornerRadius` /
        // `cornerRadiiByIndex`) and baked smooth corners export as real curves.
        // Cutouts stay in the fill path so holes survive export.
        let displayData = pathData(from: fillPath(for: stroke))
        guard !displayData.isEmpty else { return "" }

        if isFilled, !cutEdges.isEmpty {
            // Fill the filleted contour, then stroke only the retained (non-cut)
            // edges so the carved notch has no outline.
            let fillOpacity = formatSVG(stroke.resolvedFillOpacity)
            var markup = "\(prefix)<path d=\"\(displayData)\" fill=\"\(Self.planeFillHex)\" fill-opacity=\"\(fillOpacity)\" stroke=\"none\"\(fillRule)/>\n"
            let points = ShapeGeometry.renderPoints(for: stroke)
            let strokeData = strokePathData(from: points, cutEdges: cutEdges)
            if !strokeData.isEmpty {
                markup += "\(prefix)<path d=\"\(strokeData)\" fill=\"none\" \(strokePaint)/>\n"
            }
            return markup
        }

        if isFilled {
            let fillOpacity = formatSVG(stroke.resolvedFillOpacity)
            return "\(prefix)<path d=\"\(displayData)\" \(strokePaint) fill=\"\(Self.planeFillHex)\" fill-opacity=\"\(fillOpacity)\"\(fillRule)/>\n"
        }
        return "\(prefix)<path d=\"\(displayData)\" \(strokePaint) fill=\"none\"/>\n"
    }

    private static func textMarkup(_ element: TextElement, indent: Int) -> String {
        let outline = TextOutline.path(for: element)
        let data = pathData(from: outline)
        guard !data.isEmpty else { return "" }
        let prefix = pad(indent)
        if element.isOutline {
            let color = element.strokeColor
            return "\(prefix)<path d=\"\(data)\" fill=\"none\" stroke=\"\(hexRGB(from: color))\" stroke-opacity=\"\(formatSVG(clampedUnit(color.alpha)))\" stroke-width=\"\(formatSVG(max(0, element.strokeWidth)))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
        }
        let color = element.color
        return "\(prefix)<path d=\"\(data)\" fill=\"\(hexRGB(from: color))\" fill-opacity=\"\(formatSVG(clampedUnit(color.alpha)))\" fill-rule=\"nonzero\"/>\n"
    }

    /// Outer contour plus subtracted holes, matching on-canvas even-odd fills.
    private static func fillPath(for stroke: VectorStroke) -> CGPath {
        let path = CGMutablePath()
        path.addPath(stroke.displayPath())
        for cutout in stroke.cutoutPoints {
            let hole = VectorStroke(
                layerID: stroke.layerID,
                points: cutout,
                strokeWidth: stroke.strokeWidth,
                isClosed: true,
                shapeType: .circle
            )
            path.addPath(hole.displayPath())
        }
        return path
    }

    /// Closed-plane fill, matching the gray used on canvas / PDF / JPEG.
    private static let planeFillHex = "#CCCCCC"

    /// sRGB hex. Components are clamped so Display P3 values cannot emit
    /// invalid `#` paints that viewers drop (taking stroke width with them).
    private static func hexRGB(from color: CodableColor) -> String {
        let r = Int((clampedUnit(color.red) * 255).rounded())
        let g = Int((clampedUnit(color.green) * 255).rounded())
        let b = Int((clampedUnit(color.blue) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func clampedUnit(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value.isFinite ? value : 0))
    }

    /// Locale-invariant decimal so `stroke-width` / opacity stay valid SVG.
    private static func formatSVG(_ value: CGFloat) -> String {
        let number = value.isFinite ? Double(value) : 0
        var text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), number)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text.isEmpty ? "0" : text
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
