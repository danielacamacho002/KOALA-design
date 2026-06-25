//
//  CommandHistoryStore.swift
//  vectr
//

import Foundation
import Observation

struct CommandSequence: Codable, Identifiable, Equatable {
    var id: UUID
    var label: String
    var commands: [String]
    var createdAt: Date

    init(id: UUID = UUID(), label: String, commands: [String], createdAt: Date = Date()) {
        self.id = id
        self.label = label
        self.commands = commands
        self.createdAt = createdAt
    }
}

@Observable
final class CommandHistoryStore {
    static let shared = CommandHistoryStore()

    private let inputsKey = "vectr.commandHistory.inputs"
    private let sequencesKey = "vectr.commandHistory.sequences"
    private let maxInputs = 40
    private let maxSequences = 12

    var recentInputs: [String] = []
    var recentSequences: [CommandSequence] = []

    private init() {
        load()
    }

    func recordInput(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased()
        guard lower != "undo", lower != "close", lower != "c", lower != "cancel", lower != "esc" else { return }

        recentInputs.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentInputs.insert(trimmed, at: 0)
        if recentInputs.count > maxInputs {
            recentInputs = Array(recentInputs.prefix(maxInputs))
        }
        save()
    }

    func recordSequence(from commandLog: [String], pointCount: Int) {
        let commands = commandLog
            .filter { $0.hasPrefix("> ") }
            .map { String($0.dropFirst(2)) }
            .filter { command in
                let lower = command.lowercased()
                return lower != "undo" && lower != "close" && lower != "c"
            }
        guard commands.count >= 2 else { return }

        let label = "Polyline · \(pointCount) pts"
        let sequence = CommandSequence(label: label, commands: commands)

        recentSequences.removeAll { $0.commands == sequence.commands }
        recentSequences.insert(sequence, at: 0)
        if recentSequences.count > maxSequences {
            recentSequences = Array(recentSequences.prefix(maxSequences))
        }
        save()
    }

    func removeSequence(id: UUID) {
        recentSequences.removeAll { $0.id == id }
        save()
    }

    func clearInputs() {
        recentInputs = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        if let inputs = defaults.stringArray(forKey: inputsKey) {
            recentInputs = inputs
        }
        if let data = defaults.data(forKey: sequencesKey),
           let decoded = try? JSONDecoder().decode([CommandSequence].self, from: data) {
            recentSequences = decoded
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(recentInputs, forKey: inputsKey)
        if let data = try? JSONEncoder().encode(recentSequences) {
            defaults.set(data, forKey: sequencesKey)
        }
    }
}
