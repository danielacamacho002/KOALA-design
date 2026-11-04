//
//  FilletRadiusPanelView.swift
//  Koala
//

import SwiftUI

struct FilletRadiusPanelView: View {
    @Bindable var document: KoalaDocument
    var units: MeasurementUnit
    /// Marks the document dirty after a live radius change. Corner selection stays put so the
    /// stepper can keep adjusting the same corners.
    var onChanged: () -> Void = {}
    var onApply: () -> Void
    var onCancel: () -> Void

    /// Radius step in document points, matching the thickness stepper.
    private static let radiusStepPoints: CGFloat = 0.5

    @State private var radiusText = ""
    /// True while the radius field is focused, so a canvas drag does not overwrite a number being typed.
    @State private var isEditingRadius = false

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
                    onSubmit: { apply(finish: false) },
                    onEditingChanged: { isEditingRadius = $0 }
                )
            }

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
        .onChange(of: document.geometryRevision) { _, _ in
            syncRadiusTextToSelection()
        }
        .onChange(of: units) { _, _ in
            syncRadiusTextToSelection()
        }
    }

    /// Pre-fills the stepper with the selected corners' shared radius.
    /// Corner drags change the radius without changing the selection, so this also runs on
    /// every geometry update and the field shows the live measurement.
    private func syncRadiusTextToSelection() {
        guard !isEditingRadius else { return }
        if case .uniform(let radius) = document.selectedFilletRadiusSummary() {
            let next = displayString(units.fromDocumentUnits(radius))
            if radiusText != next {
                radiusText = next
            }
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
        units.formatted(value)
    }
}
