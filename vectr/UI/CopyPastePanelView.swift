//
//  CopyPastePanelView.swift
//  vectr
//

import SwiftUI

struct CopyPastePanelView: View {
    @Bindable var document: VectrDocument
    var onChanged: () -> Void
    var onStatus: (String) -> Void

    private var canCopy: Bool { !document.selectionIsEmpty }
    private var canPaste: Bool { document.canPasteClipboard }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelHeader("Copy")

            Text("Duplicate stacks a copy on the original. Paste drops the clipboard one grid step down and to the right.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                ToolPanelLabelButton(
                    title: "Copy",
                    prominent: canCopy,
                    isDisabled: !canCopy,
                    fullWidth: true
                ) {
                    copySelection()
                }

                ToolPanelLabelButton(
                    title: "Paste",
                    prominent: canPaste,
                    isDisabled: !canPaste,
                    fullWidth: true
                ) {
                    pasteClipboard()
                }
            }

            ToolPanelLabelButton(
                title: "Duplicate",
                prominent: canCopy,
                isDisabled: !canCopy,
                fullWidth: true
            ) {
                duplicateSelection()
            }

            Text(document.clipboard.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let layer = document.activeLayer {
                Text("Paste onto: \(layer.name)")
                    .font(.caption2)
                    .foregroundStyle(layer.isLocked ? .red : .secondary)
            }
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
    }

    private func copySelection() {
        let count = document.copySelectedElementsToClipboard()
        guard count > 0 else {
            onStatus("Select a shape or text to copy")
            return
        }
        let noun = count == 1 ? "item" : "items"
        onStatus("Copied \(count) \(noun). Switch layers, then Paste")
    }

    private func pasteClipboard() {
        if document.clipboard.isEmpty {
            onStatus("Copy a shape first")
            return
        }
        if document.activeLayer?.isLocked == true {
            onStatus("Unlock the layer to paste")
            return
        }
        let count = document.pasteClipboardToActiveLayer()
        guard count > 0 else {
            onStatus("Nothing to paste")
            return
        }
        let layerName = document.activeLayer?.name ?? "layer"
        onStatus("Pasted onto \(layerName)")
        onChanged()
    }

    private func duplicateSelection() {
        guard canCopy else {
            onStatus("Select a shape or text to duplicate")
            return
        }
        document.duplicateSelectedElements(offset: .zero)
        onStatus("Duplicated")
        onChanged()
    }
}
