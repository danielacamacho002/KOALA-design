//
//  SVGImporter.swift
//  Koala
//

import CoreGraphics
import Foundation
import UIKit

enum SVGImporter {
    struct ParsedSVG: Equatable {
        var strokes: [VectorStroke] = []
        var textElements: [TextElement] = []

        var hasVectorContent: Bool { !strokes.isEmpty || !textElements.isEmpty }
    }

    static func importStrokes(from url: URL, layerID: UUID) throws -> [VectorStroke] {
        try importDocument(from: url, layerID: layerID).strokes
    }

    static func importDocument(from url: URL, layerID: UUID) throws -> ParsedSVG {
        let data = try Data(contentsOf: url)
        guard let xml = decodeXML(from: data) else {
            throw ImportRouter.ImportError.unsupportedFormat
        }
        return parse(xml: xml, layerID: layerID)
    }

    static func parse(xml: String, layerID: UUID) -> ParsedSVG {
        let walker = TreeParser(layerID: layerID)
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = walker
        parser.shouldProcessNamespaces = true
        parser.parse()
        return ParsedSVG(strokes: walker.strokes, textElements: walker.textElements)
    }

    /// Shifts imported artwork so its bounds are centered on the document origin.
    static func centered(_ parsed: ParsedSVG) -> ParsedSVG {
        let points = parsed.strokes.flatMap { ShapeGeometry.renderPoints(for: $0) }
            + parsed.textElements.flatMap { $0.corners() }
        guard !points.isEmpty else { return parsed }
        let bounds = PrintLayoutCoordinateSpace.boundingRect(for: points)
        guard !bounds.isNull else { return parsed }
        let offset = CGPoint(x: -bounds.midX, y: -bounds.midY)
        guard offset != .zero else { return parsed }
        return ParsedSVG(
            strokes: parsed.strokes.map { $0.offsettingGeometry(by: offset) },
            textElements: parsed.textElements.map { text in
                var copy = text
                copy.position = CGPoint(x: text.position.x + offset.x, y: text.position.y + offset.y)
                return copy
            }
        )
    }

    /// Shifts imported artwork so its bounds are centered on the document origin.
    static func centeredStrokes(_ strokes: [VectorStroke]) -> [VectorStroke] {
        centered(ParsedSVG(strokes: strokes)).strokes
    }

    fileprivate static func pathStrokes(
        from pathData: String,
        layerID: UUID,
        transform: CGAffineTransform,
        paint: PaintAttributes
    ) -> [VectorStroke] {
        var strokes: [VectorStroke] = []
        let subpaths = SVGPathParser.parse(pathData)
        let closed = subpaths.filter { $0.isClosed && $0.points.count >= 3 }
        let open = subpaths.filter { !$0.isClosed && $0.points.count >= 2 }

        func makeStroke(from subpath: SVGPathParser.Subpath, cutouts: [[CGPoint]] = []) -> VectorStroke {
            if subpath.hasCurves {
                return VectorStroke(
                    layerID: layerID,
                    points: subpath.points,
                    strokeWidth: paint.strokeWidth,
                    strokeColor: paint.strokeColor,
                    isClosed: subpath.isClosed,
                    shapeType: .curve,
                    cutoutPoints: cutouts,
                    curveHandles: normalizedHandles(for: subpath),
                    fillOpacity: subpath.isClosed ? paint.fillOpacity : nil,
                    fillColor: subpath.isClosed ? paint.fillColor : nil,
                    fillRule: subpath.isClosed ? paint.fillRule : nil
                )
            }
            return VectorStroke(
                layerID: layerID,
                points: subpath.points,
                strokeWidth: paint.strokeWidth,
                strokeColor: paint.strokeColor,
                isClosed: subpath.isClosed,
                shapeType: .polyline,
                cutoutPoints: cutouts,
                fillOpacity: subpath.isClosed ? paint.fillOpacity : nil,
                fillColor: subpath.isClosed ? paint.fillColor : nil,
                fillRule: subpath.isClosed ? paint.fillRule : nil
            )
        }

        if let first = closed.first {
            let extra = closed.dropFirst().compactMap { subpath -> [CGPoint]? in
                let contour = sampledPoints(for: subpath)
                return polygonArea(contour) > 0.01 ? contour : nil
            }
            strokes.append(applying(transform, to: makeStroke(from: first, cutouts: extra)))
        }
        for subpath in open {
            strokes.append(applying(transform, to: makeStroke(from: subpath)))
        }
        return strokes
    }

    nonisolated private static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in 0..<points.count {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    nonisolated private static func sampledPoints(for subpath: SVGPathParser.Subpath) -> [CGPoint] {
        guard subpath.hasCurves else { return subpath.points }
        return ShapeGeometry.curvePoints(
            anchors: subpath.points,
            handles: normalizedHandles(for: subpath),
            closed: subpath.isClosed
        )
    }

    nonisolated private static func normalizedHandles(for subpath: SVGPathParser.Subpath) -> [CurveHandle] {
        var handles = subpath.handles
        if handles.count < subpath.points.count {
            handles.append(contentsOf: Array(
                repeating: CurveHandle(),
                count: subpath.points.count - handles.count
            ))
        } else if handles.count > subpath.points.count {
            handles = Array(handles.prefix(subpath.points.count))
        }
        return handles
    }

    fileprivate static func circleStroke(
        layerID: UUID,
        cx: CGFloat,
        cy: CGFloat,
        rx: CGFloat,
        ry: CGFloat,
        transform: CGAffineTransform,
        paint: PaintAttributes
    ) -> VectorStroke {
        let local = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: cx, y: cy - ry),
                CGPoint(x: cx + rx, y: cy),
                CGPoint(x: cx, y: cy + ry),
                CGPoint(x: cx - rx, y: cy)
            ],
            strokeWidth: paint.strokeWidth,
            strokeColor: paint.strokeColor,
            isClosed: true,
            shapeType: rx == ry ? .circle : .ellipse,
            fillOpacity: paint.fillOpacity,
            fillColor: paint.fillColor,
            fillRule: paint.fillRule
        )
        return applying(transform, to: local)
    }

    fileprivate struct PaintAttributes {
        var strokeWidth: CGFloat
        var strokeColor: CodableColor
        var fillOpacity: CGFloat?
        var fillColor: CodableColor?
        var fillRule: PathFillRule
    }

    fileprivate struct Presentation {
        var fill: CodableColor? = CodableColor(red: 0, green: 0, blue: 0)
        var fillIsNone = false
        var stroke: CodableColor? = nil
        var strokeIsNone = true
        var fillOpacity: CGFloat = 1
        var strokeOpacity: CGFloat = 1
        var strokeWidth: CGFloat? = nil
        var fontFamily = "sans-serif"
        var fontSize: CGFloat = 16
        var textAnchor = "start"
        var x: CGFloat? = nil
        var y: CGFloat? = nil
        var fillRule: PathFillRule = .nonzero
    }

    fileprivate static func paintAttributes(
        from presentation: Presentation,
        transform: CGAffineTransform
    ) -> PaintAttributes {
        let scale = strokeScale(of: transform)
        var strokeColor = presentation.stroke ?? CodableColor(red: 0, green: 0, blue: 0)
        strokeColor.alpha = min(1, max(0, presentation.strokeOpacity))
        let width: CGFloat
        if presentation.strokeIsNone {
            width = 0
        } else if let value = presentation.strokeWidth {
            width = max(value * scale, 0)
        } else {
            width = max(1 * scale, 0.5)
        }
        return PaintAttributes(
            strokeWidth: width,
            strokeColor: strokeColor,
            fillOpacity: presentation.fillIsNone ? 0 : presentation.fillOpacity,
            fillColor: presentation.fillIsNone ? nil : presentation.fill,
            fillRule: presentation.fillRule
        )
    }

    fileprivate static func merging(_ base: Presentation, with attrs: [String: String]) -> Presentation {
        var presentation = base
        let merged = mergedPresentation(attrs)
        if let fill = merged["fill"] {
            if isPaintNone(fill) {
                presentation.fillIsNone = true
            } else if let color = parseColor(fill) {
                presentation.fillIsNone = false
                presentation.fill = color
            }
        }
        if let stroke = merged["stroke"] {
            if isPaintNone(stroke) {
                presentation.strokeIsNone = true
            } else if let color = parseColor(stroke) {
                presentation.strokeIsNone = false
                presentation.stroke = color
            }
        }
        if let opacity = parseNumber(merged["fill-opacity"]) {
            presentation.fillOpacity = min(1, max(0, opacity))
        }
        if let opacity = parseNumber(merged["stroke-opacity"]) {
            presentation.strokeOpacity = min(1, max(0, opacity))
        }
        if let width = parseNumber(merged["stroke-width"]) {
            presentation.strokeWidth = width
        }
        if let family = merged["font-family"], !family.isEmpty {
            presentation.fontFamily = family
        }
        if let size = parseLengthInDocumentPoints(merged["font-size"]) {
            presentation.fontSize = size
        }
        if let anchor = merged["text-anchor"], !anchor.isEmpty {
            presentation.textAnchor = anchor.lowercased()
        }
        if let x = parseNumber(merged["x"]) {
            presentation.x = x
        }
        if let y = parseNumber(merged["y"]) {
            presentation.y = y
        }
        if let rule = merged["fill-rule"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if rule == "evenodd" { presentation.fillRule = .evenodd }
            if rule == "nonzero" { presentation.fillRule = .nonzero }
        }
        return presentation
    }

    fileprivate static func resolveFontRef(_ family: String) -> FontRef {
        let names = family.split(separator: ",").map { chunk in
            chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        for name in names where !name.isEmpty {
            let lowered = name.lowercased()
            if lowered == "sans-serif" || lowered == "system-ui" { return .builtin("SF Pro") }
            if lowered == "arial" { return .builtin("Helvetica Neue") }
            if lowered == "serif" || lowered.hasPrefix("times") { return .builtin("Georgia") }
            if lowered == "monospace" || lowered.hasPrefix("courier") { return .builtin("Courier New") }
            if lowered.hasPrefix("helvetica") { return .builtin("Helvetica Neue") }
            if let built = FontCatalog.builtIn.first(where: { matchesBuiltIn($0, name: name) }) {
                return .builtin(built.displayName)
            }
            if let imported = FontLibrary.shared.importedFonts.first(where: {
                $0.displayName.compare(name, options: .caseInsensitive) == .orderedSame
                    || $0.postScriptName.compare(name, options: .caseInsensitive) == .orderedSame
            }) {
                return imported.fontRef
            }
            if let font = UIFont(name: name, size: 12) {
                return .imported(postScriptName: font.fontName, fileName: "")
            }
        }
        return .default
    }

    private static func matchesBuiltIn(_ font: BuiltInFont, name: String) -> Bool {
        if font.displayName.compare(name, options: .caseInsensitive) == .orderedSame {
            return true
        }
        if case .named(let postScriptName) = font.design {
            return postScriptName.compare(name, options: .caseInsensitive) == .orderedSame
        }
        return false
    }

    fileprivate static func makeTextElement(
        text: String,
        layerID: UUID,
        presentation: Presentation,
        transform: CGAffineTransform
    ) -> TextElement? {
        let collapsed = collapseWhitespace(text)
        guard !collapsed.isEmpty else { return nil }
        let scale = strokeScale(of: transform)
        let fontSize = max(1, presentation.fontSize * scale)
        let fontRef = resolveFontRef(presentation.fontFamily)
        let font = fontRef.uiFont(size: fontSize)
        let origin = CGPoint(x: presentation.x ?? 0, y: presentation.y ?? 0).applying(transform)
        var position = CGPoint(x: origin.x, y: origin.y - font.ascender)
        let width = (collapsed as NSString).size(withAttributes: [.font: font]).width
        switch presentation.textAnchor {
        case "middle": position.x -= width / 2
        case "end": position.x -= width
        default: break
        }
        let fill = presentation.fill ?? CodableColor(red: 0, green: 0, blue: 0)
        let stroke = presentation.stroke ?? fill
        let isOutline = presentation.fillIsNone && !presentation.strokeIsNone
        return TextElement(
            layerID: layerID,
            text: collapsed,
            position: position,
            fontRef: fontRef,
            fontSize: fontSize,
            color: isOutline ? stroke : fill,
            strokeColor: stroke,
            strokeWidth: (presentation.strokeWidth ?? 1) * scale,
            isOutline: isOutline,
            rotation: atan2(transform.b, transform.a)
        )
    }

    private static func collapseWhitespace(_ raw: String) -> String {
        let squeezed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return squeezed
    }

    private static func isPaintNone(_ raw: String) -> Bool {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered == "none" || lowered == "transparent"
    }

    private static func mergedPresentation(_ attrs: [String: String]) -> [String: String] {
        var merged: [String: String] = [:]
        for (key, value) in attrs {
            merged[key.lowercased()] = value
        }
        if let style = merged["style"] {
            for declaration in style.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                merged[key] = value
            }
        }
        return merged
    }

    private static func parseColor(_ raw: String?) -> CodableColor? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered == "none" || lowered == "transparent" { return nil }
        if lowered.hasPrefix("#") {
            return parseHexColor(String(trimmed.dropFirst()))
        }
        if lowered.hasPrefix("rgb") {
            return parseRGBColor(trimmed)
        }
        if let named = cssColorNamed(lowered) {
            return named
        }
        return parseHexColor(trimmed)
    }

    private static func cssColorNamed(_ name: String) -> CodableColor? {
        let colors: [String: (CGFloat, CGFloat, CGFloat)] = [
            "black": (0, 0, 0),
            "white": (1, 1, 1),
            "red": (1, 0, 0),
            "green": (0, 128 / 255, 0),
            "blue": (0, 0, 1),
            "gray": (128 / 255, 128 / 255, 128 / 255),
            "grey": (128 / 255, 128 / 255, 128 / 255),
            "silver": (192 / 255, 192 / 255, 192 / 255),
            "maroon": (128 / 255, 0, 0),
            "purple": (128 / 255, 0, 128 / 255),
            "fuchsia": (1, 0, 1),
            "lime": (0, 1, 0),
            "olive": (128 / 255, 128 / 255, 0),
            "yellow": (1, 1, 0),
            "navy": (0, 0, 128 / 255),
            "teal": (0, 128 / 255, 128 / 255),
            "aqua": (0, 1, 1),
            "orange": (1, 165 / 255, 0)
        ]
        guard let rgb = colors[name] else { return nil }
        return CodableColor(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private static func parseHexColor(_ hex: String) -> CodableColor? {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&value) else { return nil }
        switch sanitized.count {
        case 3:
            let r = CGFloat((value >> 8) & 0xF) / 15
            let g = CGFloat((value >> 4) & 0xF) / 15
            let b = CGFloat(value & 0xF) / 15
            return CodableColor(red: r, green: g, blue: b)
        case 6:
            let r = CGFloat((value >> 16) & 0xFF) / 255
            let g = CGFloat((value >> 8) & 0xFF) / 255
            let b = CGFloat(value & 0xFF) / 255
            return CodableColor(red: r, green: g, blue: b)
        case 8:
            let r = CGFloat((value >> 24) & 0xFF) / 255
            let g = CGFloat((value >> 16) & 0xFF) / 255
            let b = CGFloat((value >> 8) & 0xFF) / 255
            let a = CGFloat(value & 0xFF) / 255
            return CodableColor(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }

    private static func parseRGBColor(_ raw: String) -> CodableColor? {
        let inner = raw
            .replacingOccurrences(of: "rgba(", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "rgb(", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ")", with: "")
        let parts = inner.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        guard parts.count >= 3,
              let r = parseColorChannel(parts[0]),
              let g = parseColorChannel(parts[1]),
              let b = parseColorChannel(parts[2]) else { return nil }
        let alpha = parts.count > 3 ? parseNumber(parts[3]) : 1
        return CodableColor(red: r, green: g, blue: b, alpha: alpha ?? 1)
    }

    private static func parseColorChannel(_ raw: String) -> CGFloat? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%"), let value = Double(trimmed.dropLast()) {
            return min(1, max(0, CGFloat(value) / 100))
        }
        guard let value = Double(trimmed) else { return nil }
        return min(1, max(0, CGFloat(value) / 255))
    }

    fileprivate static func parseNumber(_ raw: String?) -> CGFloat? {
        guard let raw else { return nil }
        return SVGNumberScanner.firstNumber(in: raw)
    }

    fileprivate static func parseLengthInDocumentPoints(_ raw: String?) -> CGFloat? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != "auto" else { return nil }
        if trimmed.hasSuffix("%") { return nil }

        let suffixes: [(String, MeasurementUnit)] = [
            ("in", .inches),
            ("mm", .millimeters),
            ("cm", .centimeters),
            ("pt", .points),
            ("px", .points)
        ]
        for (suffix, unit) in suffixes {
            if trimmed.hasSuffix(suffix) {
                let number = String(trimmed.dropLast(suffix.count))
                guard let value = SVGNumberScanner.firstNumber(in: number) else { return nil }
                return UnitConversion.documentPoints(from: value, unit: unit)
            }
        }
        return SVGNumberScanner.firstNumber(in: trimmed)
    }

    fileprivate static func parsePointPairs(_ raw: String) -> [CGPoint] {
        let values = SVGNumberScanner.numbers(in: raw)
        guard values.count >= 2 else { return [] }
        var points: [CGPoint] = []
        var index = 0
        while index + 1 < values.count {
            points.append(CGPoint(x: values[index], y: values[index + 1]))
            index += 2
        }
        return points
    }

    fileprivate static func applying(_ transform: CGAffineTransform, to stroke: VectorStroke) -> VectorStroke {
        if transform.isIdentity { return stroke }

        var local = stroke
        if (stroke.shapeType == .circle || stroke.shapeType == .ellipse),
           hasRotationOrSkew(transform) || !isUniformConformal(transform) {
            // 4-cardinal ellipse math is axis-aligned. Rotate/skew/non-uniform scale
            // must be baked into samples or render rebuilds a cropped oval.
            local.points = ShapeGeometry.renderPoints(for: stroke)
            local.shapeType = .polyline
            local.curveHandles = nil
            local.isClosed = true
            local.shapeRotation = nil
        }

        let origin = CGPoint.zero.applying(transform)
        func mapVector(_ vector: CGPoint) -> CGPoint {
            let mapped = vector.applying(transform)
            return CGPoint(x: mapped.x - origin.x, y: mapped.y - origin.y)
        }

        var copy = local
        copy.points = local.points.map { $0.applying(transform) }
        copy.cutoutPoints = local.cutoutPoints.map { contour in
            contour.map { $0.applying(transform) }
        }
        if let handles = local.curveHandles {
            copy.curveHandles = handles.map { handle in
                CurveHandle(
                    inOffset: mapVector(handle.inOffset),
                    outOffset: mapVector(handle.outOffset)
                )
            }
        }
        if let base = local.rotationBasePoints {
            copy.rotationBasePoints = base.map { $0.applying(transform) }
        }
        if let center = local.rotationBaseCenter {
            copy.rotationBaseCenter = center.applying(transform)
        }
        return copy
    }

    fileprivate static func hasRotationOrSkew(_ transform: CGAffineTransform) -> Bool {
        abs(transform.b) > 0.0001 || abs(transform.c) > 0.0001
    }

    fileprivate static func isUniformConformal(_ transform: CGAffineTransform) -> Bool {
        let lx = hypot(transform.a, transform.b)
        let ly = hypot(transform.c, transform.d)
        guard lx > 1e-9, ly > 1e-9 else { return false }
        let dot = transform.a * transform.c + transform.b * transform.d
        return abs(lx - ly) <= 0.001 * max(lx, ly) && abs(dot) <= 0.001 * lx * ly
    }

    fileprivate static func strokeScale(of transform: CGAffineTransform) -> CGFloat {
        max(hypot(transform.a, transform.b), 0.0001)
    }

    fileprivate static func viewBoxTransform(from attrs: [String: String]) -> CGAffineTransform {
        guard let viewBox = parseViewBox(attrs["viewbox"] ?? attrs["viewBox"]) else { return .identity }
        var transform = CGAffineTransform(translationX: -viewBox.minX, y: -viewBox.minY)
        let width = parseLengthInDocumentPoints(attrs["width"])
        let height = parseLengthInDocumentPoints(attrs["height"])
        let sx = (width.map { viewBox.width > 0 ? $0 / viewBox.width : 1 }) ?? 1
        let sy = (height.map { viewBox.height > 0 ? $0 / viewBox.height : 1 }) ?? sx
        let scale = (width != nil && height != nil) ? min(sx, sy) : (width != nil ? sx : sy)
        if abs(scale - 1) > 0.0000001 {
            transform = CGAffineTransform(scaleX: scale, y: scale).concatenating(transform)
        }
        return transform
    }

    private static func parseViewBox(_ raw: String?) -> CGRect? {
        guard let raw else { return nil }
        let values = SVGNumberScanner.numbers(in: raw)
        guard values.count == 4, values[2] > 0, values[3] > 0 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private static func decodeXML(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let bomStripped = String(data: data.dropFirst(3), encoding: .utf8) {
            return bomStripped
        }
        return String(data: data, encoding: .isoLatin1)
    }
}

// MARK: - XML tree

private final class TreeParser: NSObject, XMLParserDelegate {
    private struct Frame {
        var transform: CGAffineTransform
        var presentation: SVGImporter.Presentation
        var buffer = ""
        var collectsText = false
    }

    let layerID: UUID
    var strokes: [VectorStroke] = []
    var textElements: [TextElement] = []
    private var stack: [Frame] = [
        Frame(transform: .identity, presentation: SVGImporter.Presentation())
    ]
    private var skipDepth = 0
    private var svgDepth = 0

    private static let skipTags: Set<String> = [
        "defs", "clippath", "mask", "symbol", "pattern", "marker",
        "lineargradient", "radialgradient", "filter", "metadata",
        "style", "script", "title", "desc", "image"
    ]
    private static let groupTags: Set<String> = ["svg", "g", "a", "text", "tspan"]

    init(layerID: UUID) {
        self.layerID = layerID
    }

    private var current: Frame {
        stack.last ?? Frame(transform: .identity, presentation: SVGImporter.Presentation())
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        let attrs = Self.lowercased(attributeDict)
        if skipDepth > 0 {
            skipDepth += 1
            return
        }
        if Self.skipTags.contains(name) {
            skipDepth = 1
            return
        }

        if Self.groupTags.contains(name) {
            if name == "tspan" || name == "text" {
                emitTextIfNeeded()
            }
            var transform = current.transform
            if name == "svg" {
                svgDepth += 1
                if svgDepth == 1 {
                    transform = transform.concatenating(SVGImporter.viewBoxTransform(from: attrs))
                }
            }
            transform = transform.concatenating(SVGTransformParser.parse(attrs["transform"]))
            let presentation = SVGImporter.merging(current.presentation, with: attrs)
            stack.append(Frame(
                transform: transform,
                presentation: presentation,
                collectsText: name == "text" || name == "tspan"
            ))
            return
        }

        let transform = current.transform.concatenating(SVGTransformParser.parse(attrs["transform"]))
        let presentation = SVGImporter.merging(current.presentation, with: attrs)
        let paint = SVGImporter.paintAttributes(from: presentation, transform: transform)
        switch name {
        case "path":
            if let data = attrs["d"] {
                strokes.append(contentsOf: SVGImporter.pathStrokes(
                    from: data,
                    layerID: layerID,
                    transform: transform,
                    paint: paint
                ))
            }
        case "rect":
            appendRect(from: attrs, transform: transform, paint: paint)
        case "line":
            appendLine(from: attrs, transform: transform, paint: paint)
        case "polyline", "polygon":
            appendPoly(from: attrs, closed: name == "polygon", transform: transform, paint: paint)
        case "circle":
            appendCircle(from: attrs, transform: transform, paint: paint)
        case "ellipse":
            appendEllipse(from: attrs, transform: transform, paint: paint)
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if skipDepth > 0 {
            skipDepth -= 1
            return
        }
        let name = localName(elementName)
        if name == "text" || name == "tspan" {
            emitTextIfNeeded()
        }
        if name == "svg" {
            svgDepth = max(0, svgDepth - 1)
        }
        if Self.groupTags.contains(name), stack.count > 1 {
            stack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth == 0, stack.last?.collectsText == true else { return }
        stack[stack.count - 1].buffer += string
    }

    private func emitTextIfNeeded() {
        guard var frame = stack.last, frame.collectsText else { return }
        if let element = SVGImporter.makeTextElement(
            text: frame.buffer,
            layerID: layerID,
            presentation: frame.presentation,
            transform: frame.transform
        ) {
            textElements.append(element)
        }
        frame.buffer = ""
        stack[stack.count - 1] = frame
    }

    private func appendRect(
        from attrs: [String: String],
        transform: CGAffineTransform,
        paint: SVGImporter.PaintAttributes
    ) {
        let x = SVGImporter.parseNumber(attrs["x"]) ?? 0
        let y = SVGImporter.parseNumber(attrs["y"]) ?? 0
        guard let width = SVGImporter.parseNumber(attrs["width"]),
              let height = SVGImporter.parseNumber(attrs["height"]),
              width > 0, height > 0 else { return }
        let stroke = VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: x, y: y),
                CGPoint(x: x + width, y: y),
                CGPoint(x: x + width, y: y + height),
                CGPoint(x: x, y: y + height)
            ],
            strokeWidth: paint.strokeWidth,
            strokeColor: paint.strokeColor,
            isClosed: true,
            shapeType: .rectangle,
            fillOpacity: paint.fillOpacity,
            fillColor: paint.fillColor,
            fillRule: paint.fillRule
        )
        strokes.append(SVGImporter.applying(transform, to: stroke))
    }

    private func appendLine(
        from attrs: [String: String],
        transform: CGAffineTransform,
        paint: SVGImporter.PaintAttributes
    ) {
        guard let x1 = SVGImporter.parseNumber(attrs["x1"]),
              let y1 = SVGImporter.parseNumber(attrs["y1"]),
              let x2 = SVGImporter.parseNumber(attrs["x2"]),
              let y2 = SVGImporter.parseNumber(attrs["y2"]) else { return }
        let stroke = VectorStroke(
            layerID: layerID,
            points: [CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)],
            strokeWidth: paint.strokeWidth,
            strokeColor: paint.strokeColor,
            shapeType: .polyline
        )
        strokes.append(SVGImporter.applying(transform, to: stroke))
    }

    private func appendPoly(
        from attrs: [String: String],
        closed: Bool,
        transform: CGAffineTransform,
        paint: SVGImporter.PaintAttributes
    ) {
        guard let raw = attrs["points"] else { return }
        let points = SVGImporter.parsePointPairs(raw)
        guard points.count >= 2 else { return }
        let stroke = VectorStroke(
            layerID: layerID,
            points: points,
            strokeWidth: paint.strokeWidth,
            strokeColor: paint.strokeColor,
            isClosed: closed,
            shapeType: .polyline,
            fillOpacity: closed ? paint.fillOpacity : nil,
            fillColor: closed ? paint.fillColor : nil,
            fillRule: closed ? paint.fillRule : nil
        )
        strokes.append(SVGImporter.applying(transform, to: stroke))
    }

    private func appendCircle(
        from attrs: [String: String],
        transform: CGAffineTransform,
        paint: SVGImporter.PaintAttributes
    ) {
        let cx = SVGImporter.parseNumber(attrs["cx"]) ?? 0
        let cy = SVGImporter.parseNumber(attrs["cy"]) ?? 0
        guard let radius = SVGImporter.parseNumber(attrs["r"]), radius > 0 else { return }
        strokes.append(SVGImporter.circleStroke(
            layerID: layerID,
            cx: cx,
            cy: cy,
            rx: radius,
            ry: radius,
            transform: transform,
            paint: paint
        ))
    }

    private func appendEllipse(
        from attrs: [String: String],
        transform: CGAffineTransform,
        paint: SVGImporter.PaintAttributes
    ) {
        let cx = SVGImporter.parseNumber(attrs["cx"]) ?? 0
        let cy = SVGImporter.parseNumber(attrs["cy"]) ?? 0
        guard let rx = SVGImporter.parseNumber(attrs["rx"]),
              let ry = SVGImporter.parseNumber(attrs["ry"]),
              rx > 0, ry > 0 else { return }
        strokes.append(SVGImporter.circleStroke(
            layerID: layerID,
            cx: cx,
            cy: cy,
            rx: rx,
            ry: ry,
            transform: transform,
            paint: paint
        ))
    }

    private func localName(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map { String($0).lowercased() } ?? qualified.lowercased()
    }

    private static func lowercased(_ attrs: [String: String]) -> [String: String] {
        Dictionary(
            attrs.map { key, value in
                let local = key.split(separator: ":").last.map(String.init) ?? key
                return (local.lowercased(), value)
            },
            uniquingKeysWith: { _, last in last }
        )
    }
}

// MARK: - Transforms

private enum SVGTransformParser {
    static func parse(_ raw: String?) -> CGAffineTransform {
        guard let raw, !raw.isEmpty else { return .identity }
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z]+)\s*\(([^)]*)\)"#) else {
            return .identity
        }
        var transform = CGAffineTransform.identity
        let range = NSRange(raw.startIndex..., in: raw)
        regex.enumerateMatches(in: raw, range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 3,
                  let nameRange = Range(match.range(at: 1), in: raw),
                  let argsRange = Range(match.range(at: 2), in: raw) else { return }
            let name = raw[nameRange].lowercased()
            let values = SVGNumberScanner.numbers(in: String(raw[argsRange]))
            let next = makeTransform(name: name, values: values)
            transform = next.concatenating(transform)
        }
        return transform
    }

    private static func makeTransform(name: String, values: [CGFloat]) -> CGAffineTransform {
        switch name {
        case "matrix":
            guard values.count >= 6 else { return .identity }
            return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
        case "translate":
            guard let tx = values.first else { return .identity }
            let ty = values.count > 1 ? values[1] : 0
            return CGAffineTransform(translationX: tx, y: ty)
        case "scale":
            guard let sx = values.first else { return .identity }
            let sy = values.count > 1 ? values[1] : sx
            return CGAffineTransform(scaleX: sx, y: sy)
        case "rotate":
            guard let angle = values.first else { return .identity }
            let radians = angle * .pi / 180
            let rotation = CGAffineTransform(rotationAngle: radians)
            guard values.count >= 3 else { return rotation }
            let cx = values[1]
            let cy = values[2]
            var transform = CGAffineTransform(translationX: -cx, y: -cy)
            transform = rotation.concatenating(transform)
            return CGAffineTransform(translationX: cx, y: cy).concatenating(transform)
        case "skewx":
            guard let angle = values.first else { return .identity }
            return CGAffineTransform(a: 1, b: 0, c: tan(angle * .pi / 180), d: 1, tx: 0, ty: 0)
        case "skewy":
            guard let angle = values.first else { return .identity }
            return CGAffineTransform(a: 1, b: tan(angle * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
        default:
            return .identity
        }
    }
}

// MARK: - Number scanning

private enum SVGNumberScanner {
    static func firstNumber(in raw: String) -> CGFloat? {
        numbers(in: raw).first
    }

    static func numbers(in raw: String) -> [CGFloat] {
        SVGPathParser.tokenize(raw).compactMap { token in
            Double(token).map { CGFloat($0) }
        }
    }
}

// MARK: - Path parser

private enum SVGPathParser {
    struct Subpath {
        var points: [CGPoint] = []
        var handles: [CurveHandle] = []
        var isClosed = false
        var hasCurves = false

        var isValid: Bool { points.count >= 2 }
    }

    static func parse(_ data: String) -> [Subpath] {
        var tokens = tokenize(data)
        guard !tokens.isEmpty else { return [] }

        var subpaths: [Subpath] = []
        var current = Subpath()
        var index = 0
        var command = ""
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?

        func ensureHandleCount() {
            while current.handles.count < current.points.count {
                current.handles.append(CurveHandle())
            }
        }

        func appendPoint(_ point: CGPoint, inOffset: CGPoint = .zero, outOffset: CGPoint = .zero) {
            current.points.append(point)
            current.handles.append(CurveHandle(inOffset: inOffset, outOffset: outOffset))
            currentPoint = point
        }

        func setOutOffset(at anchorIndex: Int, to offset: CGPoint) {
            ensureHandleCount()
            guard current.handles.indices.contains(anchorIndex) else { return }
            current.handles[anchorIndex].outOffset = offset
            if offset != .zero { current.hasCurves = true }
        }

        func setInOffset(at anchorIndex: Int, to offset: CGPoint) {
            ensureHandleCount()
            guard current.handles.indices.contains(anchorIndex) else { return }
            current.handles[anchorIndex].inOffset = offset
            if offset != .zero { current.hasCurves = true }
        }

        func finishSubpath() {
            guard current.isValid else {
                current = Subpath()
                return
            }
            ensureHandleCount()
            subpaths.append(current)
            current = Subpath()
        }

        func reflectiveControl(for command: Character) -> CGPoint {
            guard let lastControl else { return currentPoint }
            if command == "S" || command == "s" || command == "T" || command == "t" {
                return CGPoint(
                    x: 2 * currentPoint.x - lastControl.x,
                    y: 2 * currentPoint.y - lastControl.y
                )
            }
            return currentPoint
        }

        func readDouble(at i: inout Int) -> CGFloat? {
            guard i < tokens.count, let value = Double(tokens[i]) else { return nil }
            i += 1
            return CGFloat(value)
        }

        func readFlag(at i: inout Int) -> CGFloat? {
            guard i < tokens.count else { return nil }
            let token = tokens[i]
            if let first = token.first, first == "0" || first == "1",
               token.allSatisfy({ $0 == "0" || $0 == "1" }) {
                let rest = String(token.dropFirst())
                if rest.isEmpty {
                    i += 1
                } else {
                    tokens[i] = rest
                }
                return first == "1" ? 1 : 0
            }
            return readDouble(at: &i).map { $0 == 0 ? 0 : 1 }
        }

        func skipToken(at i: inout Int) {
            guard i < tokens.count else { return }
            i += 1
        }

        while index < tokens.count {
            let token = tokens[index]
            if token.count == 1, let letter = token.first, letter.isLetter {
                command = String(letter)
                index += 1
            } else if command.isEmpty {
                skipToken(at: &index)
                continue
            }

            let startIndex = index
            var finishedCommand = false

            let absolute = command.uppercased() == command
            let cmd = Character(command.uppercased())

            switch cmd {
            case "M":
                if current.isValid { finishSubpath() }
                guard let x = readDouble(at: &index), let y = readDouble(at: &index) else { break }
                let point = absolute
                    ? CGPoint(x: x, y: y)
                    : CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
                appendPoint(point)
                subpathStart = point
                lastControl = nil
                command = absolute ? "L" : "l"

            case "L":
                guard let x = readDouble(at: &index), let y = readDouble(at: &index) else { break }
                let point = absolute
                    ? CGPoint(x: x, y: y)
                    : CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
                appendPoint(point)
                lastControl = nil

            case "H":
                guard let x = readDouble(at: &index) else { break }
                let point = CGPoint(x: absolute ? x : currentPoint.x + x, y: currentPoint.y)
                appendPoint(point)
                lastControl = nil

            case "V":
                guard let y = readDouble(at: &index) else { break }
                let point = CGPoint(x: currentPoint.x, y: absolute ? y : currentPoint.y + y)
                appendPoint(point)
                lastControl = nil

            case "C":
                guard let x1 = readDouble(at: &index),
                      let y1 = readDouble(at: &index),
                      let x2 = readDouble(at: &index),
                      let y2 = readDouble(at: &index),
                      let x = readDouble(at: &index),
                      let y = readDouble(at: &index) else { break }
                let c1 = absolute
                    ? CGPoint(x: x1, y: y1)
                    : CGPoint(x: currentPoint.x + x1, y: currentPoint.y + y1)
                let c2 = absolute
                    ? CGPoint(x: x2, y: y2)
                    : CGPoint(x: currentPoint.x + x2, y: currentPoint.y + y2)
                let end = absolute
                    ? CGPoint(x: x, y: y)
                    : CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
                if current.points.isEmpty { appendPoint(currentPoint) }
                let anchorIndex = current.points.count - 1
                setOutOffset(at: anchorIndex, to: CGPoint(x: c1.x - currentPoint.x, y: c1.y - currentPoint.y))
                appendPoint(end, inOffset: CGPoint(x: c2.x - end.x, y: c2.y - end.y))
                lastControl = c2

            case "S":
                guard let x2 = readDouble(at: &index),
                      let y2 = readDouble(at: &index),
                      let x = readDouble(at: &index),
                      let y = readDouble(at: &index) else { break }
                let c1 = reflectiveControl(for: cmd)
                let c2 = absolute
                    ? CGPoint(x: x2, y: y2)
                    : CGPoint(x: currentPoint.x + x2, y: currentPoint.y + y2)
                let end = absolute
                    ? CGPoint(x: x, y: y)
                    : CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
                if current.points.isEmpty { appendPoint(currentPoint) }
                let anchorIndex = current.points.count - 1
                setOutOffset(at: anchorIndex, to: CGPoint(x: c1.x - currentPoint.x, y: c1.y - currentPoint.y))
                appendPoint(end, inOffset: CGPoint(x: c2.x - end.x, y: c2.y - end.y))
                lastControl = c2

            case "Q":
                guard let x1 = readDouble(at: &index),
                      let y1 = readDouble(at: &index),
                      let x = readDouble(at: &index),
                      let y = readDouble(at: &index) else { break }
                let q1 = absolute
                    ? CGPoint(x: x1, y: y1)
                    : CGPoint(x: currentPoint.x + x1, y: currentPoint.y + y1)
                let end = absolute
                    ? CGPoint(x: x, y: y)
                    : CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
                let c1 = CGPoint(
                    x: currentPoint.x + 2.0 / 3.0 * (q1.x - currentPoint.x),
                    y: currentPoint.y + 2.0 / 3.0 * (q1.y - currentPoint.y)
                )
                let c2 = CGPoint(
                    x: end.x + 2.0 / 3.0 * (q1.x - end.x),
                    y: end.y + 2.0 / 3.0 * (q1.y - end.y)
                )
                if current.points.isEmpty { appendPoint(currentPoint) }
                let anchorIndex = current.points.count - 1
                setOutOffset(at: anchorIndex, to: CGPoint(x: c1.x - currentPoint.x, y: c1.y - currentPoint.y))
                appendPoint(end, inOffset: CGPoint(x: c2.x - end.x, y: c2.y - end.y))
                lastControl = q1

            case "T":
                guard let x = readDouble(at: &index), let y = readDouble(at: &index) else { break }
                let q1 = reflectiveControl(for: cmd)
                let end = absolute
                    ? CGPoint(x: x, y: y)
                    : CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
                let c1 = CGPoint(
                    x: currentPoint.x + 2.0 / 3.0 * (q1.x - currentPoint.x),
                    y: currentPoint.y + 2.0 / 3.0 * (q1.y - currentPoint.y)
                )
                let c2 = CGPoint(
                    x: end.x + 2.0 / 3.0 * (q1.x - end.x),
                    y: end.y + 2.0 / 3.0 * (q1.y - end.y)
                )
                if current.points.isEmpty { appendPoint(currentPoint) }
                let anchorIndex = current.points.count - 1
                setOutOffset(at: anchorIndex, to: CGPoint(x: c1.x - currentPoint.x, y: c1.y - currentPoint.y))
                appendPoint(end, inOffset: CGPoint(x: c2.x - end.x, y: c2.y - end.y))
                lastControl = q1

            case "A":
                guard let rx = readDouble(at: &index),
                      let ry = readDouble(at: &index),
                      let angle = readDouble(at: &index),
                      let largeArc = readFlag(at: &index),
                      let sweep = readFlag(at: &index),
                      let x = readDouble(at: &index),
                      let y = readDouble(at: &index) else { break }
                let end = absolute
                    ? CGPoint(x: x, y: y)
                    : CGPoint(x: currentPoint.x + x, y: currentPoint.y + y)
                let arcPoints = arcSamplePoints(
                    from: currentPoint,
                    to: end,
                    rx: abs(rx),
                    ry: abs(ry),
                    xAxisRotation: angle,
                    largeArc: largeArc != 0,
                    sweep: sweep != 0
                )
                for point in arcPoints.dropFirst() {
                    appendPoint(point)
                }
                lastControl = nil

            case "Z":
                if current.points.count >= 2 {
                    current.isClosed = true
                    if let last = current.points.last,
                       hypot(last.x - subpathStart.x, last.y - subpathStart.y) < 0.001 {
                        current.points.removeLast()
                        if current.handles.count > current.points.count {
                            let incoming = current.handles.removeLast()
                            if current.handles.isEmpty == false {
                                current.handles[0].inOffset = incoming.inOffset
                                if incoming.inOffset != .zero { current.hasCurves = true }
                            }
                        }
                    }
                    currentPoint = subpathStart
                }
                finishSubpath()
                lastControl = nil
                command = ""
                finishedCommand = true

            default:
                skipToken(at: &index)
                command = ""
                finishedCommand = true
            }

            if !finishedCommand, index == startIndex {
                skipToken(at: &index)
            }
        }

        if current.isValid { finishSubpath() }
        return subpaths
    }

    static func tokenize(_ data: String) -> [String] {
        let chars = Array(data)
        var tokens: [String] = []
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character.isWhitespace || character == "," {
                index += 1
                continue
            }
            if let (number, next) = scanNumber(chars, start: index) {
                tokens.append(number)
                index = next
                continue
            }
            if character.isLetter {
                tokens.append(String(character))
                index += 1
                continue
            }
            index += 1
        }
        return tokens
    }

    private static func scanNumber(_ chars: [Character], start: Int) -> (String, Int)? {
        var index = start
        if index < chars.count, chars[index] == "+" || chars[index] == "-" {
            index += 1
        }

        var sawDigit = false
        var sawDot = false

        while index < chars.count, chars[index].isNumber {
            sawDigit = true
            index += 1
        }

        if index < chars.count, chars[index] == "." {
            let nextIsDigit = index + 1 < chars.count && chars[index + 1].isNumber
            if !sawDot && (nextIsDigit || !sawDigit) {
                sawDot = true
                index += 1
                while index < chars.count, chars[index].isNumber {
                    sawDigit = true
                    index += 1
                }
            }
        }

        if sawDigit, index < chars.count, chars[index] == "e" || chars[index] == "E" {
            let exponentIndex = index
            index += 1
            if index < chars.count, chars[index] == "+" || chars[index] == "-" {
                index += 1
            }
            let digitsStart = index
            while index < chars.count, chars[index].isNumber {
                index += 1
            }
            if index == digitsStart {
                index = exponentIndex
            }
        }

        guard sawDigit, index > start else { return nil }
        return (String(chars[start..<index]), index)
    }

    private static func arcSamplePoints(
        from start: CGPoint,
        to end: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        xAxisRotation: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) -> [CGPoint] {
        guard start != end else { return [start] }
        var radiiX = abs(rx)
        var radiiY = abs(ry)
        if radiiX == 0 || radiiY == 0 {
            return [start, end]
        }

        let angle = xAxisRotation * .pi / 180
        let cosA = cos(angle)
        let sinA = sin(angle)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1 = cosA * dx + sinA * dy
        let y1 = -sinA * dx + cosA * dy

        let radiiCheck = (x1 * x1) / (radiiX * radiiX) + (y1 * y1) / (radiiY * radiiY)
        if radiiCheck > 1 {
            let scale = sqrt(radiiCheck)
            radiiX *= scale
            radiiY *= scale
        }

        let rx2 = radiiX * radiiX
        let ry2 = radiiY * radiiY
        let x1sq = x1 * x1
        let y1sq = y1 * y1
        var factor = max(0, (rx2 * ry2 - rx2 * y1sq - ry2 * x1sq) / (rx2 * y1sq + ry2 * x1sq))
        factor = sqrt(factor)
        if largeArc == sweep { factor = -factor }
        let cx1 = factor * radiiX * y1 / radiiY
        let cy1 = factor * -radiiY * x1 / radiiX
        let centerX = cosA * cx1 - sinA * cy1 + (start.x + end.x) / 2
        let centerY = sinA * cx1 + cosA * cy1 + (start.y + end.y) / 2

        func angleBetween(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let det = ux * vy - uy * vx
            return atan2(det, dot)
        }

        let ux = (x1 - cx1) / radiiX
        let uy = (y1 - cy1) / radiiY
        let vx = (-x1 - cx1) / radiiX
        let vy = (-y1 - cy1) / radiiY
        var sweepAngle = angleBetween(ux, uy, vx, vy)
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        let startAngle = atan2((y1 - cy1) / radiiY, (x1 - cx1) / radiiX)
        let segments = max(4, Int(ceil(abs(sweepAngle) / (.pi / 12))))
        var points: [CGPoint] = [start]
        for step in 1...segments {
            let t = CGFloat(step) / CGFloat(segments)
            let theta = startAngle + sweepAngle * t
            let localX = radiiX * cos(theta)
            let localY = radiiY * sin(theta)
            let x = cosA * localX - sinA * localY + centerX
            let y = sinA * localX + cosA * localY + centerY
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }
}
