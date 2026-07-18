//
//  PrintMarginPanelView.swift
//  vectr
//

import SwiftUI

/// Floating command panel (matching the design-mode tool panels) for the unified
/// margin / print-border control. Chooses whether the printable area is shown
/// only on screen (red dashed) or additionally drawn onto the printed pages.
struct PrintMarginPanelView: View {
    @Bindable var document: VectrDocument
    var units: MeasurementUnit
    var onChanged: () -> Void
    var onClose: () -> Void

    @State private var thicknessText = ""

    /// Standard printable margin for letter paper (0.25 in), in document points.
    private static let defaultMargin: CGFloat = 18

    private var current: PrintMarginMode {
        document.printLayout.marginMode
    }

    /// Per-tap step for the +/- buttons, in document points, chosen to be a tidy
    /// increment in the active measurement unit.
    private var stepInPoints: CGFloat {
        switch units {
        case .inches: return units.toDocumentUnits(0.05)
        case .centimeters: return units.toDocumentUnits(0.1)
        case .millimeters: return units.toDocumentUnits(1)
        case .points: return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Margins")
                Spacer()
                ToolPanelCancelButton { onClose() }
            }

            ToolPanelSectionLabel("Print margin")
            ForEach(PrintMarginMode.allCases) { mode in
                ToolPanelLabelButton(
                    title: mode.label,
                    prominent: current == mode,
                    fullWidth: true,
                    alignment: .leading
                ) {
                    select(mode)
                }
            }

            Text("Outline is drawn on screen and included in the printed / exported pages.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ToolPanelSectionLabel("Margin width (\(units.shortLabel))")
            HStack(spacing: 4) {
                ToolPanelIconButton(systemImage: "minus", isDisabled: document.printLayout.printableMargin <= 0) {
                    setThickness(document.printLayout.printableMargin - stepInPoints)
                }
                FingerOnlyTextField(
                    placeholder: "0.25",
                    text: $thicknessText,
                    keyboardType: .decimalPad,
                    fontSize: 13,
                    cornerRadius: 0,
                    onSubmit: applyThickness
                )
                .frame(height: 28)
                ToolPanelIconButton(systemImage: "plus") {
                    setThickness(document.printLayout.printableMargin + stepInPoints)
                }
            }
            ToolPanelLabelButton(title: "Reset to 0.25 in", fullWidth: true) {
                setThickness(Self.defaultMargin)
            }
        }
        .toolPanelChrome(width: 208)
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
        guard let value = Double(thicknessText.trimmingCharacters(in: .whitespaces)) else { return }
        let points = units.toDocumentUnits(CGFloat(value))
        guard points >= 0 else { return }
        setThickness(points)
    }

    private func setThickness(_ points: CGFloat) {
        var settings = document.printLayout
        settings.printableMargin = max(0, points)
        document.updatePrintLayout(settings, recordUndo: false)
        syncThickness()
        onChanged()
    }

    private func syncThickness() {
        thicknessText = String(format: "%.2f", units.fromDocumentUnits(document.printLayout.printableMargin))
    }

    /// Refreshes the field from the model, but never clobbers a value the user is
    /// actively typing.
    private func syncThicknessIfIdle() {
        guard thicknessText.isEmpty
            || Double(thicknessText.trimmingCharacters(in: .whitespaces)) == nil else { return }
        syncThickness()
    }
}
