//
//  CommandPointParser.swift
//  Koala
//

import CoreGraphics
import Foundation

enum CommandPointParseError: LocalizedError {
    case empty
    case unrecognized(String)
    case needsStartPoint

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a point or command."
        case .unrecognized(let input):
            return "Could not parse “\(input)”."
        case .needsStartPoint:
            return "Enter the first point before a relative offset."
        }
    }
}

enum CommandPointInput: Equatable {
    case absolute(CGPoint)
    case relativePolar(distance: CGFloat, degrees: CGFloat)
    case relativeCartesian(CGPoint)
    case close
    case undo
    case cancel
}

enum CommandPointParser {
    static func parseScalar(_ text: String) -> CGFloat? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0 else { return nil }
        return CGFloat(value)
    }

    static func parseDiameter(_ text: String) -> CGFloat? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("d") else { return nil }
        let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard let value = Double(body), value > 0 else { return nil }
        return CGFloat(value)
    }

    /// Parses coordinate input.
    /// - First point: `0`, `0,0`, `10 20`, or `10,20` (always absolute)
    /// - Next points: `@15,0` relative cartesian · `15 90` relative polar · `30,40` absolute
    static func parse(_ raw: String, hasStartPoint: Bool) -> Result<CommandPointInput, CommandPointParseError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let lower = trimmed.lowercased()
        switch lower {
        case "close", "c":
            return .success(.close)
        case "undo", "u":
            return .success(.undo)
        case "cancel", "esc":
            return .success(.cancel)
        default:
            break
        }

        if lower.hasPrefix("@") {
            guard hasStartPoint else { return .failure(.needsStartPoint) }
            let body = String(trimmed.dropFirst())
            guard let point = parseCartesian(body) else {
                return .failure(.unrecognized(trimmed))
            }
            return .success(.relativeCartesian(point))
        }

        // First point, or explicit x,y (comma) → always absolute cartesian.
        if !hasStartPoint || trimmed.contains(",") {
            if let point = parseCartesian(trimmed) {
                return .success(.absolute(point))
            }
            if !hasStartPoint, lower == "0" {
                return .success(.absolute(.zero))
            }
            if !hasStartPoint {
                return .failure(.unrecognized(trimmed))
            }
        }

        // With a start point, bare "distance angle" is relative polar.
        if hasStartPoint, let polar = parsePolar(trimmed) {
            return .success(.relativePolar(distance: polar.distance, degrees: polar.degrees))
        }

        if let point = parseCartesian(trimmed) {
            return .success(.absolute(point))
        }

        if !hasStartPoint, lower == "0" {
            return .success(.absolute(.zero))
        }

        return .failure(.unrecognized(trimmed))
    }

    static func resolve(_ input: CommandPointInput, from previous: CGPoint?) -> CGPoint? {
        switch input {
        case .absolute(let point):
            return point
        case .relativePolar(let distance, let degrees):
            guard let previous else { return nil }
            return polarOffset(from: previous, distance: distance, degrees: degrees)
        case .relativeCartesian(let offset):
            guard let previous else { return nil }
            return CGPoint(x: previous.x + offset.x, y: previous.y + offset.y)
        case .close, .undo, .cancel:
            return nil
        }
    }

    /// Counterclockwise degrees from +X; +Y is up on screen (technical drawing convention).
    static func polarOffset(from origin: CGPoint, distance: CGFloat, degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: origin.x + distance * cos(radians),
            y: origin.y - distance * sin(radians)
        )
    }

    // MARK: - Private parsing

    private static func parsePolar(_ text: String) -> (distance: CGFloat, degrees: CGFloat)? {
        // Polar uses spaces only — commas mean cartesian.
        guard !text.contains(",") else { return nil }

        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "degrees", with: "")
            .replacingOccurrences(of: "degree", with: "")
            .replacingOccurrences(of: "deg", with: "")
            .replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespaces)

        let parts = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2,
              let distance = Double(parts[0]),
              let degrees = Double(parts[1]) else { return nil }
        return (CGFloat(distance), CGFloat(degrees))
    }

    private static func parseCartesian(_ text: String) -> CGPoint? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        if cleaned.count >= 2,
           let x = Double(cleaned[0]),
           let y = Double(cleaned[1]) {
            return CGPoint(x: x, y: y)
        }
        if cleaned.count == 1, let value = Double(cleaned[0]) {
            return CGPoint(x: value, y: 0)
        }
        return nil
    }
}
