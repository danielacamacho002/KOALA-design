//
//  AddAnchorPanelView.swift
//  vectr
//

import SwiftUI

struct AddAnchorPanelView: View {
    @Bindable var document: VectrDocument
    var onApply: () -> Void
    var onStatus: (String) -> Void

    @State private var totalText = ""

    private var currentCount: Int {
        guard let stroke = document.selectedStrokeID.flatMap({ document.stroke(with: $0) }) else { return 0 }
        return document.currentAnchorCount(for: stroke)
    }

    private var parsedTarget: Int? {
        Int(totalText.trimmingCharacters(in: .whitespaces))
    }

    private var canApply: Bool {
        guard document.selectedStrokeID != nil,
              let target = parsedTarget,
              target >= 3,
              target > currentCount else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Anchor")
                .font(.caption.weight(.semibold))

            Text("Tap an edge to add one anchor, or enter total anchor count.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                FingerOnlyTextField(
                    placeholder: "Total anchors",
                    text: $totalText,
                    keyboardType: .numberPad,
                    onSubmit: apply
                )
                .frame(height: 36)
                .padding(.horizontal, 10)

                Button(action: apply) {
                    Image(systemName: "return")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canApply)
            }

            Text("Current anchors: \(currentCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Apply") { apply() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canApply)
        }
        .padding(10)
        .frame(width: 172)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func apply() {
        guard let target = parsedTarget else {
            onStatus("Enter a valid anchor count")
            return
        }
        switch document.distributeAnchors(toTotal: target) {
        case .success:
            onApply()
        case .noSelection:
            onStatus("Select a closed shape first")
        case .notEligible:
            onStatus("Selected shape cannot receive anchors")
        case .alreadyHasCount(let count):
            onStatus("Already has \(count) anchors")
        case .invalidTarget:
            onStatus("Enter at least 3 total anchors")
        }
    }
}
