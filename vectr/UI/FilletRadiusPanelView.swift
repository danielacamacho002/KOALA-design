//
//  FilletRadiusPanelView.swift
//  vectr
//

import SwiftUI

struct FilletRadiusPanelView: View {
    @Bindable var document: VectrDocument
    var units: MeasurementUnit
    var onApply: () -> Void
    var onCancel: () -> Void

    @State private var radiusText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fillet")
                .font(.caption.weight(.semibold))

            Text("Select corner anchors, enter radius, or drag a corner handle:")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                FingerOnlyTextField(
                    placeholder: "Radius",
                    text: $radiusText,
                    keyboardType: .decimalPad,
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
            }

            Text("Selected corners: \(document.selectedFilletCornerIndices.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Cancel", role: .cancel) { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(document.selectedFilletCornerIndices.isEmpty)
            }
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
        .onAppear {
            let display = units.fromDocumentUnits(document.settings.defaultCornerRadius)
            radiusText = String(format: "%.3f", display)
        }
    }

    private func apply() {
        guard let value = Double(radiusText.trimmingCharacters(in: .whitespaces)) else { return }
        let docRadius = units.toDocumentUnits(CGFloat(value))
        document.applyFilletToSelected(
            radius: docRadius,
            cornerIndices: document.selectedFilletCornerIndices
        )
        onApply()
    }
}
