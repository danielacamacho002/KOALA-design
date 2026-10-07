//
//  CommandBarView.swift
//  Koala
//

import SwiftUI

struct CommandBarView: View {
    @Bindable var session: PolylineCommandSession
    @Bindable var history = CommandHistoryStore.shared
    var onCommit: ([CGPoint], Bool) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(session.commandLog.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.hasPrefix(">") ? .primary : .secondary)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(maxHeight: 160)
                .background(Color(.secondarySystemBackground))
                .onChange(of: session.commandLog.count) { _, count in
                    if count > 0 {
                        withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }
            }

            if !history.recentSequences.isEmpty {
                recentSequencesSection
            }

            promptArea
        }
        .toolPanelChrome(width: 260)
    }

    private var header: some View {
        HStack {
            ToolPanelHeader("Command")
            Spacer()
            ToolPanelCancelButton {
                session.cancel()
                onCancel()
            }
        }
    }

    private var promptArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.prompt)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(session.hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if session.points.count >= 2 {
                Text("Drag blue points to adjust · drag canvas to move all · Close/Done to keep.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !session.points.isEmpty {
                Text("Drag the blue point to reposition the start.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = session.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if !session.statusMessage.isEmpty {
                Text(session.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                FingerOnlyTextField(
                    placeholder: "Type point…",
                    text: $session.inputText,
                    keyboardType: .numbersAndPunctuation,
                    fontSize: 12,
                    cornerRadius: 0,
                    onSubmit: submitInput
                )
                .frame(height: 26)

                ToolPanelIconButton(systemImage: "return", prominent: true, action: submitInput)
            }

            if !history.recentInputs.isEmpty {
                recentInputsRow
            }

            HStack(spacing: 4) {
                ToolPanelLabelButton(
                    title: "Close",
                    isDisabled: session.points.count < 2
                ) {
                    commit(closed: true)
                }
                ToolPanelLabelButton(
                    title: "Done",
                    prominent: true,
                    isDisabled: session.points.count < 2
                ) {
                    commit(closed: false)
                }
                Spacer()
                Text("\(session.points.count) pts")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func submitInput() {
        let closed = session.submit()
        if closed, session.points.count >= 3, session.points.first == session.points.last {
            commit(closed: true)
        }
    }

    private func commit(closed: Bool) {
        let points = closed ? session.finishClosed() : session.finishOpen()
        guard let points else { return }
        onCommit(points, closed)
    }

    private var recentInputsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Recent")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(history.recentInputs.prefix(12), id: \.self) { entry in
                        Button {
                            session.inputText = entry
                        } label: {
                            Text(entry)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(Color(.secondarySystemBackground))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recentSequencesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Recent shapes")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(history.recentSequences) { sequence in
                        Button {
                            session.replay(sequence: sequence)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sequence.label)
                                    .font(.caption.weight(.medium))
                                Text(sequence.commands.joined(separator: " → "))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 140, alignment: .leading)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                history.removeSequence(id: sequence.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
