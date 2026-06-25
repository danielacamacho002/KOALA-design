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

            paperSizeButton

            gridControls

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

    private var paperSizeButton: some View {
        Menu {
            ForEach(PaperSize.allCases) { size in
                Button(size.label) {
                    var settings = document.printLayout
                    settings.paperSize = size
                    document.updatePrintLayout(settings)
                    onSettingsChanged()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc")
                Text(document.printLayout.paperSize.label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var gridControls: some View {
        HStack(spacing: 8) {
            gridStepper(label: "Cols", value: document.printLayout.columns) { newValue in
                var settings = document.printLayout
                settings.columns = newValue
                document.updatePrintLayout(settings)
                onSettingsChanged()
            }
            gridStepper(label: "Rows", value: document.printLayout.rows) { newValue in
                var settings = document.printLayout
                settings.rows = newValue
                document.updatePrintLayout(settings)
                onSettingsChanged()
            }
        }
        .padding(.leading, 8)
    }

    private func gridStepper(label: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Stepper("\(value)", onIncrement: {
                onChange(min(value + 1, 10))
            }, onDecrement: {
                onChange(max(value - 1, 1))
            })
            .labelsHidden()
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .frame(width: 16)
        }
    }

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ForEach(PrintLayoutTool.allCases, id: \.self) { tool in
                StudioIconButton(
                    systemImage: tool.systemImage,
                    isActive: isToolActive(tool),
                    size: iconSize
                ) {
                    var settings = document.printLayout
                    if tool == .printBorder {
                        settings.isPrintBorderVisible.toggle()
                    } else {
                        settings.activeTool = tool
                        if tool == .registrationMark {
                            settings.showRegistrationSuggestions = true
                        }
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

    private func isToolActive(_ tool: PrintLayoutTool) -> Bool {
        switch tool {
        case .printBorder:
            return document.printLayout.isPrintBorderVisible
        default:
            return document.printLayout.activeTool == tool
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
