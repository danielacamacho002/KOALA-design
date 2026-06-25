//
//  SVGImporter.swift
//  vectr
//

import CoreGraphics
import Foundation

enum SVGImporter {
    static func importStrokes(from url: URL, layerID: UUID) throws -> [VectorStroke] {
        let xml = try String(contentsOf: url, encoding: .utf8)
        return parse(xml: xml, layerID: layerID)
    }

    static func parse(xml: String, layerID: UUID) -> [VectorStroke] {
        var strokes: [VectorStroke] = []
        let pattern = #"<path[^>]*d="([^"]+)"[^>]*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        regex.enumerateMatches(in: xml, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let pathRange = Range(match.range(at: 1), in: xml) else { return }
            let pathData = String(xml[pathRange])
            let points = parsePathData(pathData)
            guard points.count >= 2 else { return }
            let closed = pathData.uppercased().contains("Z")
            strokes.append(VectorStroke(
                layerID: layerID,
                points: points,
                strokeWidth: 1.5,
                isClosed: closed,
                shapeType: .polyline
            ))
        }
        return strokes
    }

    private static func parsePathData(_ data: String) -> [CGPoint] {
        let tokens = data
            .replacingOccurrences(of: ",", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        var points: [CGPoint] = []
        var index = 0
        var command = "M"
        while index < tokens.count {
            let token = tokens[index]
            if token.count == 1, token.first!.isLetter {
                command = token.uppercased()
                index += 1
                continue
            }
            switch command {
            case "M", "L":
                guard index + 1 < tokens.count,
                      let x = Double(tokens[index]),
                      let y = Double(tokens[index + 1]) else { break }
                points.append(CGPoint(x: x, y: y))
                index += 2
                if command == "M" { command = "L" }
            default:
                index += 1
            }
        }
        return points
    }
}
