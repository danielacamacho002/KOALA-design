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
    var onChanged: () -> Void
    var onClose: () -> Void

    private var current: PrintMarginMode {
        document.printLayout.marginMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Margins")
                Spacer()
                ToolPanelCancelButton { onClose() }
            }

            ToolPanelSectionLabel("Display")
            ToolPanelLabelButton(
                title: PrintMarginMode.off.label,
                prominent: current == .off,
                fullWidth: true,
                alignment: .leading
            ) {
                select(.off)
            }
            ToolPanelLabelButton(
                title: PrintMarginMode.displayOnly.label,
                prominent: current == .displayOnly,
                fullWidth: true,
                alignment: .leading
            ) {
                select(.displayOnly)
            }

            Text("Red dashed guide on screen only — not printed.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ToolPanelSectionLabel("Print onto pages")
            ToolPanelLabelButton(
                title: PrintMarginMode.printDashed.label,
                prominent: current == .printDashed,
                fullWidth: true,
                alignment: .leading
            ) {
                select(.printDashed)
            }
            ToolPanelLabelButton(
                title: PrintMarginMode.printSolid.label,
                prominent: current == .printSolid,
                fullWidth: true,
                alignment: .leading
            ) {
                select(.printSolid)
            }

            Text("Outline is drawn on screen and included in the printed / exported pages.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toolPanelChrome(width: 208)
    }

    private func select(_ mode: PrintMarginMode) {
        var settings = document.printLayout
        settings.marginMode = mode
        document.updatePrintLayout(settings, recordUndo: false)
        onChanged()
    }
}
