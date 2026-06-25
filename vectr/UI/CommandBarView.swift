//
//  CommandBarView.swift
//  vectr
//

import SwiftUI

struct CommandBarView: View {
    @Bindable var session: PolylineCommandSession
    @Bindable var history = CommandHistoryStore.shared
    var onCommit: ([CGPoint], Bool) -> Void
    var onCancel: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .padding(10)
                }
                .onChange(of: session.commandLog.count) { _, count in
                    if count > 0 {
                        withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }
            }

            if !history.recentSequences.isEmpty {
                recentSequencesSection
                Divider()
            }

            promptArea
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .onAppear { fieldFocused = true }
    }

    private var header: some View {
        HStack {
            Text("Command")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Cancel", role: .cancel) {
                session.cancel()
                onCancel()
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
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

            HStack(spacing: 8) {
                TextField("Type point…", text: $session.inputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($fieldFocused)
                    .submitLabel(.next)
                    .onSubmit { submitInput() }

                Button(action: submitInput) {
                    Image(systemName: "return")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if !history.recentInputs.isEmpty {
                recentInputsRow
            }

            HStack(spacing: 8) {
                Button("Close") { commit(closed: true) }
                    .disabled(session.points.count < 2)
                Button("Done") { commit(closed: false) }
                    .disabled(session.points.count < 2)
                Spacer()
                Text("\(session.points.count) pts")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .padding(12)
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
            Text("Recent")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(history.recentInputs.prefix(12), id: \.self) { entry in
                        Button(entry) {
                            session.inputText = entry
                            fieldFocused = true
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
    }

    private var recentSequencesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent shapes")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                history.removeSequence(id: sequence.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}
