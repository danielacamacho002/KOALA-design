//
//  PrintMarginPanelView.swift
//  Koala
//

import SwiftUI

/// Floating command panel (matching the design-mode tool panels) for the unified
/// margin / print-border control. Chooses whether the printable area is shown
/// only on screen (red dashed) or additionally drawn onto the printed pages.
struct PrintMarginPanelView: View {
    @Bindable var document: KoalaDocument
    var units: MeasurementUnit
    var onChanged: () -> Void
    var onClose: () -> Void

    @State private var thicknessText = ""

    private var current: PrintMarginMode {
        document.printLayout.marginMode
    }

    /// Per-tap step for the +/- buttons, in document points, chosen to be a tidy
    /// increment in the active measurement unit.
    private var stepInPoints: CGFloat {
        switch units {
        case .inches: return units.toDocumentUnits(0.05)
        case .feet: return units.toDocumentUnits(0.01)
        case .millimeters: return units.toDocumentUnits(1)
        case .meters: return units.toDocumentUnits(0.001)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Margins")
                Spacer()
                ToolPanelCancelButton { onClose() }
            }

            ToolPanelSegmentBar(
                options: PrintMarginMode.allCases.map(\.label),
                selectedIndex: PrintMarginMode.allCases.firstIndex(of: current) ?? 0
            ) { index in
                select(PrintMarginMode.allCases[index])
            }

            ToolPanelDivider()

            VStack(alignment: .leading, spacing: 4) {
                ToolPanelSectionLabel("Margin width")
                ToolPanelNumericStepper(
                    text: $thicknessText,
                    placeholder: "0.25",
                    unitLabel: units.shortLabel,
                    onMinus: { setThickness(document.printLayout.printableMargin - stepInPoints) },
                    onPlus: { setThickness(document.printLayout.printableMargin + stepInPoints) },
                    onSubmit: applyThickness
                )
            }
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
        .onAppear { syncThickness() }
        .onChange(of: document.printLayoutRevision) { _, _ in syncThicknessIfIdle() }
    }

    private func select(_ mode: PrintMarginMode) {
        var settings = document.printLayout
        settings.marginMode = mode
        document.updatePrintLayout(settings, recordUndo: false)
        onChanged()
    }

    private func applyThickness() {
        let cleaned = thicknessText
            .replacingOccurrences(of: units.shortLabel, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value >= 0 else {
            syncThickness()
            return
        }
        setThickness(units.toDocumentUnits(CGFloat(value)))
    }

    private func setThickness(_ points: CGFloat) {
        var settings = document.printLayout
        settings.printableMargin = max(0, points)
        document.updatePrintLayout(settings, recordUndo: false)
        syncThickness()
        onChanged()
    }

    private func syncThickness() {
        thicknessText = units.formatted(units.fromDocumentUnits(document.printLayout.printableMargin))
    }

    /// Refreshes the field from the model, but never clobbers a value the user is
    /// actively typing.
    private func syncThicknessIfIdle() {
        guard thicknessText.isEmpty
            || Double(thicknessText.trimmingCharacters(in: .whitespaces)) == nil else { return }
        syncThickness()
    }
}
