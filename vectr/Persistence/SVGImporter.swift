//
//  SVGImporter.swift
//  vectr
//

import CoreGraphics
import Foundation

enum SVGImporter {
    static func importStrokes(from url: URL, layerID: UUID) throws -> [VectorStroke] {
        let data = try Data(contentsOf: url)
        guard let xml = decodeXML(from: data) else {
            throw ImportRouter.ImportError.unsupportedFormat
        }
        return parse(xml: xml, layerID: layerID)
    }

    static func parse(xml: String, layerID: UUID) -> [VectorStroke] {
        let scale = svgCoordinateScale(from: xml)
        var strokes: [VectorStroke] = []
        for element in extractElements(named: "path", from: xml) {
            guard let pathData = stringAttribute("d", in: element) else { continue }
            let strokeWidth = strokeWidth(from: element, scale: scale)
            strokes.append(contentsOf: pathStrokes(
                from: pathData,
                layerID: layerID,
                scale: scale,
                strokeWidth: strokeWidth
            ))
        }
        strokes.append(contentsOf: strokesFromBasicShapes(in: xml, layerID: layerID, scale: scale))
        return strokes
    }

    private static func pathStrokes(
        from pathData: String,
        layerID: UUID,
        scale: CGFloat,
        strokeWidth: CGFloat
    ) -> [VectorStroke] {
        var strokes: [VectorStroke] = []
        let subpaths = SVGPathParser.parse(pathData)
        for subpath in subpaths where subpath.points.count >= 2 {
            let points = subpath.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            let handles = subpath.handles.map { handle in
                CurveHandle(
                    inOffset: CGPoint(x: handle.inOffset.x * scale, y: handle.inOffset.y * scale),
                    outOffset: CGPoint(x: handle.outOffset.x * scale, y: handle.outOffset.y * scale)
                )
            }
            strokes.append(VectorStroke(
                layerID: layerID,
                points: points,
                strokeWidth: strokeWidth,
                isClosed: subpath.isClosed,
                shapeType: subpath.hasCurves ? .curve : .polyline,
                curveHandles: subpath.hasCurves ? handles : nil
            ))
        }
        return strokes
    }

    private static func strokesFromBasicShapes(in xml: String, layerID: UUID, scale: CGFloat) -> [VectorStroke] {
        var strokes: [VectorStroke] = []
        for element in extractElements(named: "rect", from: xml) {
            let strokeWidth = strokeWidth(from: element, scale: scale)
            guard let x = attribute("x", in: element, defaultValue: 0),
                  let y = attribute("y", in: element, defaultValue: 0),
                  let width = attribute("width", in: element),
                  let height = attribute("height", in: element),
                  width > 0, height > 0 else { continue }
            let points = [
                CGPoint(x: x * scale, y: y * scale),
                CGPoint(x: (x + width) * scale, y: y * scale),
                CGPoint(x: (x + width) * scale, y: (y + height) * scale),
                CGPoint(x: x * scale, y: (y + height) * scale)
            ]
            strokes.append(VectorStroke(layerID: layerID, points: points, strokeWidth: strokeWidth, isClosed: true, shapeType: .rectangle))
        }

        for element in extractElements(named: "line", from: xml) {
            let strokeWidth = strokeWidth(from: element, scale: scale)
            guard let x1 = attribute("x1", in: element),
                  let y1 = attribute("y1", in: element),
                  let x2 = attribute("x2", in: element),
                  let y2 = attribute("y2", in: element) else { continue }
            strokes.append(VectorStroke(
                layerID: layerID,
                points: [
                    CGPoint(x: x1 * scale, y: y1 * scale),
                    CGPoint(x: x2 * scale, y: y2 * scale)
                ],
                strokeWidth: strokeWidth,
                shapeType: .polyline
            ))
        }

        for tag in ["polyline", "polygon"] {
            for element in extractElements(named: tag, from: xml) {
                let strokeWidth = strokeWidth(from: element, scale: scale)
                guard let rawPoints = stringAttribute("points", in: element) else { continue }
                let points = parsePointPairs(rawPoints).map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
                guard points.count >= 2 else { continue }
                strokes.append(VectorStroke(
                    layerID: layerID,
                    points: points,
                    strokeWidth: strokeWidth,
                    isClosed: tag == "polygon",
                    shapeType: .polyline
                ))
            }
        }

        for element in extractElements(named: "circle", from: xml) {
            let strokeWidth = strokeWidth(from: element, scale: scale)
            guard let cx = attribute("cx", in: element),
                  let cy = attribute("cy", in: element),
                  let radius = attribute("r", in: element), radius > 0 else { continue }
            strokes.append(circleStroke(layerID: layerID, cx: cx * scale, cy: cy * scale, rx: radius * scale, ry: radius * scale, strokeWidth: strokeWidth))
        }

        for element in extractElements(named: "ellipse", from: xml) {
            let strokeWidth = strokeWidth(from: element, scale: scale)
            guard let cx = attribute("cx", in: element),
                  let cy = attribute("cy", in: element),
                  let rx = attribute("rx", in: element),
                  let ry = attribute("ry", in: element),
                  rx > 0, ry > 0 else { continue }
            strokes.append(circleStroke(layerID: layerID, cx: cx * scale, cy: cy * scale, rx: rx * scale, ry: ry * scale, strokeWidth: strokeWidth))
        }

        return strokes
    }

    private static func circleStroke(
        layerID: UUID,
        cx: CGFloat,
        cy: CGFloat,
        rx: CGFloat,
        ry: CGFloat,
        strokeWidth: CGFloat
    ) -> VectorStroke {
        VectorStroke(
            layerID: layerID,
            points: [
                CGPoint(x: cx, y: cy - ry),
                CGPoint(x: cx + rx, y: cy),
                CGPoint(x: cx, y: cy + ry),
                CGPoint(x: cx - rx, y: cy)
            ],
            strokeWidth: strokeWidth,
            isClosed: true,
            shapeType: rx == ry ? .circle : .ellipse
        )
    }

    private static func strokeWidth(from element: String, scale: CGFloat) -> CGFloat {
        guard let raw = firstAttribute(named: "stroke-width", in: element),
              let value = parseNumber(raw) else {
            return max(1.5 * scale, 1)
        }
        return max(value * scale, 0.5)
    }

    private static func extractElements(named tag: String, from xml: String) -> [String] {
        let pattern = #"<\#(tag)\b[^>]*(?:/>|>[^<]*</\#(tag)>)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        var results: [String] = []
        let range = NSRange(xml.startIndex..., in: xml)
        regex.enumerateMatches(in: xml, range: range) { match, _, _ in
            guard let match, let elementRange = Range(match.range, in: xml) else { return }
            results.append(String(xml[elementRange]))
        }
        return results
    }

    private static func attribute(_ name: String, in element: String, defaultValue: CGFloat? = nil) -> CGFloat? {
        if let raw = firstAttribute(named: name, in: element) {
            return parseNumber(raw) ?? defaultValue
        }
        return defaultValue
    }

    private static func stringAttribute(_ name: String, in element: String) -> String? {
        firstAttribute(named: name, in: element)
    }

    private static func parseNumber(_ raw: String) -> CGFloat? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed) else { return nil }
        return CGFloat(value)
    }

    private static func parsePointPairs(_ raw: String) -> [CGPoint] {
        let values = raw
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Double($0) }
        guard values.count >= 2 else { return [] }
        var points: [CGPoint] = []
        var index = 0
        while index + 1 < values.count {
            points.append(CGPoint(x: CGFloat(values[index]), y: CGFloat(values[index + 1])))
            index += 2
        }
        return points
    }

    /// Shifts imported artwork so its bounds are centered on the document origin.
    static func centeredStrokes(_ strokes: [VectorStroke]) -> [VectorStroke] {
        let points = strokes.flatMap { ShapeGeometry.renderPoints(for: $0) }
        guard !points.isEmpty else { return strokes }
        let bounds = PrintLayoutCoordinateSpace.boundingRect(for: points)
        guard !bounds.isNull else { return strokes }
        let offset = CGPoint(x: -bounds.midX, y: -bounds.midY)
        guard offset != .zero else { return strokes }
        return strokes.map { stroke in
            var copy = stroke
            copy.points = stroke.points.map {
                CGPoint(x: $0.x + offset.x, y: $0.y + offset.y)
            }
            return copy
        }
    }

    // MARK: - SVG metadata

    private static func decodeXML(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let bomStripped = String(data: data.dropFirst(3), encoding: .utf8) {
            return bomStripped
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Maps SVG user units to document points using width/height and viewBox when present.
    private static func svgCoordinateScale(from xml: String) -> CGFloat {
        guard let viewBoxWidth = parseViewBoxWidth(from: xml), viewBoxWidth > 0 else { return 1 }
        let widthInPoints = parseRootLengthInDocumentPoints(from: xml, attribute: "width")
            ?? viewBoxWidth
        return widthInPoints / viewBoxWidth
    }

    private static func parseViewBoxWidth(from xml: String) -> CGFloat? {
        guard let viewBox = firstAttribute(named: "viewBox", in: xml) else { return nil }
        let values = viewBox
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .compactMap { Double($0) }
        guard values.count == 4, values[2] > 0 else { return nil }
        return CGFloat(values[2])
    }

    private static func parseRootLengthInDocumentPoints(from xml: String, attribute: String) -> CGFloat? {
        guard let raw = firstAttribute(named: attribute, in: xml) else { return nil }
        return parseLengthInDocumentPoints(raw)
    }

    private static func firstAttribute(named name: String, in xml: String) -> String? {
        let pattern = #"\#(name)\s*=\s*(['"])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              match.numberOfRanges > 2,
              let valueRange = Range(match.range(at: 2), in: xml) else { return nil }
        return String(xml[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseLengthInDocumentPoints(_ raw: String) -> CGFloat? {
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
                guard let value = Double(number) else { return nil }
                return UnitConversion.documentPoints(from: CGFloat(value), unit: unit)
            }
        }

        guard let value = Double(trimmed) else { return nil }
        return CGFloat(value)
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
        let tokens = tokenize(data)
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
                      let largeArc = readDouble(at: &index),
                      let sweep = readDouble(at: &index),
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
                if !current.points.isEmpty {
                    current.isClosed = true
                    currentPoint = subpathStart
                }
                finishSubpath()
                lastControl = nil
                command = ""

            default:
                skipToken(at: &index)
                command = ""
            }

            if index == startIndex {
                skipToken(at: &index)
            }
        }

        if current.isValid { finishSubpath() }
        return subpaths
    }

    private static func tokenize(_ data: String) -> [String] {
        var normalized = ""
        for character in data {
            if character.isLetter {
                normalized.append(" ")
                normalized.append(character)
                normalized.append(" ")
            } else if character == "," {
                normalized.append(" ")
            } else if character == "-" {
                if let last = normalized.last, last == "e" || last == "E" {
                    normalized.append(character)
                } else {
                    normalized.append(" ")
                    normalized.append(character)
                }
            } else {
                normalized.append(character)
            }
        }

        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
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
