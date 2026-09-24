//
//  FilletRadiusPanelView.swift
//  vectr
//

import SwiftUI

struct FilletRadiusPanelView: View {
    @Bindable var document: VectrDocument
    var units: MeasurementUnit
    /// Marks the document dirty after a live radius change. Corner selection stays put so the
    /// stepper can keep adjusting the same corners.
    var onChanged: () -> Void = {}
    var onApply: () -> Void
    var onCancel: () -> Void

    /// Radius step in document points, matching the thickness stepper.
    private static let radiusStepPoints: CGFloat = 0.5

    @State private var radiusText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelHeader("Fillet")

            VStack(alignment: .leading, spacing: 4) {
                ToolPanelSectionLabel("Radius")

                ToolPanelNumericStepper(
                    text: $radiusText,
                    placeholder: "0",
                    unitLabel: units.shortLabel,
                    onMinus: { stepRadius(by: -Self.radiusStepPoints) },
                    onPlus: { stepRadius(by: Self.radiusStepPoints) },
                    onSubmit: { apply(finish: false) }
                )
            }

            Text("Selected corners: \(document.selectedFilletCornerIndices.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ToolPanelCancelButton { onCancel() }

                Spacer()

                ToolPanelApplyButton(
                    isDisabled: document.selectedFilletCornerIndices.isEmpty
                ) {
                    apply(finish: true)
                }
            }
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
        .onAppear {
            radiusText = displayString(units.fromDocumentUnits(document.settings.defaultCornerRadius))
            syncRadiusTextToSelection()
        }
        .onChange(of: document.selectedFilletCornerIndices) { _, _ in
            syncRadiusTextToSelection()
        }
        .onChange(of: units) { _, _ in
            syncRadiusTextToSelection()
        }
    }

    /// Pre-fills the stepper with the selected corners' shared radius.
    private func syncRadiusTextToSelection() {
        if case .uniform(let radius) = document.selectedFilletRadiusSummary() {
            radiusText = displayString(units.fromDocumentUnits(radius))
        }
    }

    private func stepRadius(by deltaDocPoints: CGFloat) {
        let base: CGFloat
        if case .uniform(let radius) = document.selectedFilletRadiusSummary() {
            base = radius
        } else {
            base = parsedDocumentRadius() ?? document.settings.defaultCornerRadius
        }
        let next = max(0, base + deltaDocPoints)
        radiusText = displayString(units.fromDocumentUnits(next))
        commitRadius(next, finish: false)
    }

    /// `finish` commits and clears the corner selection. Live stepper changes leave it selected.
    private func apply(finish: Bool) {
        guard let docRadius = parsedDocumentRadius() else {
            syncRadiusTextToSelection()
            return
        }
        let clamped = max(0, docRadius)
        radiusText = displayString(units.fromDocumentUnits(clamped))
        commitRadius(clamped, finish: finish)
    }

    private func commitRadius(_ docRadius: CGFloat, finish: Bool) {
        guard !document.selectedFilletCornerIndices.isEmpty else { return }
        document.applyFilletToSelected(
            radius: docRadius,
            cornerIndices: document.selectedFilletCornerIndices
        )
        if finish {
            onApply()
        } else {
            onChanged()
        }
    }

    private func parsedDocumentRadius() -> CGFloat? {
        let cleaned = radiusText
            .replacingOccurrences(of: units.shortLabel, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else { return nil }
        return units.toDocumentUnits(CGFloat(value))
    }

    private func displayString(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}
