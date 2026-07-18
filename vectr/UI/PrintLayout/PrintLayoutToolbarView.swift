//
//  PrintLayoutToolbarView.swift
//  vectr
//

import SwiftUI

enum PrintLayoutExportKind {
    case tiledPDF
    case singlePDF
}

struct PrintLayoutToolbarView: View {
    @Bindable var document: VectrDocument
    @Binding var isPaperPanelOpen: Bool
    @Binding var isMarginPanelOpen: Bool
    var canUndo: Bool
    var canRedo: Bool
    var onBack: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onSave: () -> Void
    var onSwitchToDesign: () -> Void
    var onExport: (PrintLayoutExportKind) -> Void
    var onSettingsChanged: () -> Void

    private let toolbarHeight: CGFloat = 48
    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: toolbarHeight)
            }
            .buttonStyle(.plain)

            ToolPaletteSeparator()
                .padding(.horizontal, 8)

            modeSegment

            ToolPaletteSeparator()
                .padding(.horizontal, 8)

            paperButton

            marginsButton

            ToolPaletteSeparator()
                .padding(.horizontal, 8)

            toolButtons

            Spacer(minLength: 8)

            exportMenu

            ToolPaletteSeparator()
                .padding(.horizontal, 8)

            HStack(spacing: 4) {
                toolbarIconButton("arrow.uturn.backward", disabled: !canUndo, action: onUndo)
                toolbarIconButton("arrow.uturn.forward", disabled: !canRedo, action: onRedo)
                toolbarIconButton("square.and.arrow.down", action: onSave)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: toolbarHeight)
        .background(.bar)
    }

    private var modeSegment: some View {
        HStack(spacing: 0) {
            modeChip("Design", active: false, action: onSwitchToDesign)
            modeChip("Print Layout", active: true, action: {})
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func modeChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var paperButton: some View {
        StudioIconButton(
            systemImage: "doc",
            isActive: isPaperPanelOpen,
            size: iconSize
        ) {
            isPaperPanelOpen.toggle()
            if isPaperPanelOpen { isMarginPanelOpen = false }
        }
        .accessibilityLabel("Paper & Grid")
    }

    private var marginsButton: some View {
        StudioIconButton(
            systemImage: "rectangle.dashed",
            isActive: isMarginPanelOpen || document.printLayout.marginMode.showsOverlay,
            size: iconSize
        ) {
            isMarginPanelOpen.toggle()
            if isMarginPanelOpen { isPaperPanelOpen = false }
        }
        .accessibilityLabel("Margins & Print Border")
    }

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ForEach(PrintLayoutTool.allCases, id: \.self) { tool in
                StudioIconButton(
                    systemImage: tool.systemImage,
                    isActive: document.printLayout.activeTool == tool,
                    size: iconSize
                ) {
                    var settings = document.printLayout
                    settings.activeTool = tool
                    // Cutting works against the dashed print-margin guides, so
                    // make sure they are visible when the tool is selected.
                    if tool == .cut, settings.marginMode == .off {
                        settings.marginMode = .displayOnly
                    }
                    document.updatePrintLayout(settings, recordUndo: false)
                    onSettingsChanged()
                }
                .accessibilityLabel(tool.label)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private var exportMenu: some View {
        Menu {
            Button("Export Tiled PDF") {
                onExport(.tiledPDF)
            }
            Button("Export Single PDF") {
                onExport(.singlePDF)
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func toolbarIconButton(_ systemImage: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 32, height: toolbarHeight)
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
