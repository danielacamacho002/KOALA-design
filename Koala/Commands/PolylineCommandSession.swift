//
//  PolylineCommandSession.swift
//  Koala
//

import CoreGraphics
import Foundation
import Observation

@Observable
final class PolylineCommandSession {
    var isActive = false
    var points: [CGPoint] = []
    var commandLog: [String] = []
    var statusMessage = ""
    var inputText = ""
    var lastError: String?
    /// Bumped when geometry changes so the canvas refreshes.
    var revision = 0

    var prompt: String {
        points.isEmpty ? "Start point:" : "Next point:"
    }

    var hint: String {
        if points.isEmpty {
            return "0 or x,y — e.g. 0 then 15 180"
        }
        return "distance angle — e.g. 15 90° · close · undo"
    }

    func start() {
        isActive = true
        points = []
        commandLog = []
        inputText = ""
        lastError = nil
        statusMessage = "Enter start point, then distance + angle for each side."
        commandLog.append("Command: Polyline")
        revision += 1
    }

    func cancel() {
        isActive = false
        points = []
        inputText = ""
        lastError = nil
        statusMessage = "Command cancelled."
    }

    @discardableResult
    func submit() -> Bool {
        let raw = inputText
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

        switch CommandPointParser.parse(raw, hasStartPoint: !points.isEmpty) {
        case .success(let input):
            return apply(input, raw: raw)
        case .failure(let error):
            lastError = error.localizedDescription
            return false
        }
    }

    func finishClosed() -> [CGPoint]? {
        guard points.count >= 2 else {
            lastError = "Need at least 2 points."
            return nil
        }
        var result = points
        if result.first != result.last {
            result.append(result[0])
        }
        let count = result.count
        CommandHistoryStore.shared.recordSequence(from: commandLog, pointCount: count)
        resetAfterFinish()
        return result
    }

    func finishOpen() -> [CGPoint]? {
        guard points.count >= 2 else {
            lastError = "Need at least 2 points."
            return nil
        }
        let result = points
        CommandHistoryStore.shared.recordSequence(from: commandLog, pointCount: result.count)
        resetAfterFinish()
        return result
    }

    func movePoint(at index: Int, to point: CGPoint) {
        guard points.indices.contains(index) else { return }
        points[index] = point
        revision += 1
    }

    func translateAllPoints(by delta: CGPoint) {
        guard !points.isEmpty else { return }
        points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        revision += 1
    }

    /// Replays a saved command sequence into the current session.
    func replay(sequence: CommandSequence) {
        points = []
        commandLog = ["Command: Polyline (replay)"]
        lastError = nil
        inputText = ""

        for command in sequence.commands {
            switch CommandPointParser.parse(command, hasStartPoint: !points.isEmpty) {
            case .success(let input):
                _ = apply(input, raw: command)
                CommandHistoryStore.shared.recordInput(command)
            case .failure(let error):
                lastError = error.localizedDescription
                break
            }
        }
        statusMessage = "Replayed \(sequence.commands.count) commands."
        revision += 1
    }

    // MARK: - Private

    private func apply(_ input: CommandPointInput, raw: String) -> Bool {
        lastError = nil

        switch input {
        case .close:
            guard points.count >= 2 else {
                lastError = "Need at least 2 points to close."
                return false
            }
            if points.first != points.last {
                points.append(points[0])
            }
            commandLog.append("> \(raw)")
            statusMessage = "Path closed — tap Close to finish."
            revision += 1
            return true

        case .undo:
            guard !points.isEmpty else {
                lastError = "Nothing to undo."
                return false
            }
            points.removeLast()
            commandLog.append("> undo")
            statusMessage = points.isEmpty ? "Start point:" : "Removed last point."
            inputText = ""
            revision += 1
            return true

        case .cancel:
            cancel()
            return true

        case .absolute, .relativePolar, .relativeCartesian:
            guard let point = CommandPointParser.resolve(input, from: points.last) else {
                lastError = CommandPointParseError.needsStartPoint.localizedDescription
                return false
            }
            points.append(point)
            commandLog.append("> \(raw)")
            statusMessage = formatted(point)
            inputText = ""
            CommandHistoryStore.shared.recordInput(raw)
            revision += 1
            return true
        }
    }

    private func resetAfterFinish() {
        isActive = false
        points = []
        inputText = ""
        lastError = nil
    }

    private func formatted(_ point: CGPoint) -> String {
        let x = point.x.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(point.x))" : String(format: "%.2f", point.x)
        let y = point.y.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(point.y))" : String(format: "%.2f", point.y)
        return "Point (\(x), \(y))"
    }
}
