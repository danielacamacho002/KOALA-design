//
//  CommandPromptBarView.swift
//  vectr
//

import SwiftUI

struct CommandPromptBarView: View {
    var toolTitle: String
    var prompt: String
    var stepLabel: String
    var showDone: Bool
    var onDone: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(toolTitle)
                    .font(.caption.weight(.semibold))
                Text(prompt)
                    .font(.subheadline.weight(.medium))
            }

            Spacer()

            Text(stepLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Cancel", role: .cancel) { onCancel() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            if showDone {
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
