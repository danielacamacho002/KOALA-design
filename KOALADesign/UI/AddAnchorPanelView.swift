//
//  AddAnchorPanelView.swift
//  Koala
//

import SwiftUI

struct AddAnchorPanelView: View {
    @Bindable var document: KoalaDocument
    var onApply: () -> Void
    var onCancel: () -> Void
    var onStatus: (String) -> Void

    @State private var totalText = "0"

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
            ToolPanelHeader("Add Anchor")

            FingerOnlyTextField(
                placeholder: "0",
                text: $totalText,
                keyboardType: .numberPad,
                fontSize: 12,
                cornerRadius: 0,
                backgroundColor: .clear,
                onSubmit: apply
            )
            .padding(.horizontal, 6)
            .frame(width: ToolPanelMetrics.pointFieldWidth, height: 28, alignment: .leading)
            .toolPanelControlFill()

            Text("Current anchors: \(currentCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.toolPanelSecondaryLabel)

            HStack(spacing: 4) {
                ToolPanelCancelButton { onCancel() }

                Spacer()

                ToolPanelApplyButton(isDisabled: !canApply) { apply() }
            }
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
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
            onStatus("Select a shape first")
        case .notEligible:
            onStatus("Selected shape cannot receive anchors")
        case .alreadyHasCount(let count):
            onStatus("Already has \(count) anchors")
        case .invalidTarget:
            onStatus("Enter at least 3 total anchors")
        }
    }
}
