//
//  FontPickerView.swift
//  vectr
//

import SwiftUI
import UniformTypeIdentifiers

/// Type-tool command panel: font, outline, stroke weight, and color, matching
/// the line / circle / rectangle panel. The font list opens as a side menu.
struct FontPickerView: View {
    @Bindable var document: VectrDocument
    @Bindable var library: FontLibrary
    var onChanged: () -> Void
    var onCancel: () -> Void = {}

    @State private var showFontMenu = false
    @State private var showImporter = false
    @State private var importError: String?
    @State private var strokeText = ""
    @State private var showColorPicker = false

    private let panelWidth: CGFloat = 150
    private static let strokeStepPoints: CGFloat = 0.5
    private static let strokeRange: ClosedRange<CGFloat> = 0.5...48

    private var units: MeasurementUnit { document.settings.units }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            commandPanel

            if showFontMenu {
                fontMenu
            }
        }
        .background {
            DocumentImportSheet(
                isPresented: $showImporter,
                contentTypes: Self.fontContentTypes
            ) { url in
                handleImport(.success([url]))
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onAppear { syncStrokeText() }
        .onChange(of: document.activeTextStrokeWidth) { _, _ in syncStrokeText() }
        .onChange(of: units) { _, _ in syncStrokeText() }
    }

    // MARK: - Command panel

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 14) {
                ToolPanelHeader("Type")

                VStack(alignment: .leading, spacing: 4) {
                    ToolPanelSectionLabel("Font")
                    ToolPanelMenuButton(
                        title: document.activeFontRef.displayName,
                        isExpanded: showFontMenu
                    ) {
                        showFontMenu.toggle()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ToolPanelSectionLabel("Style")
                    ToolPanelSegmentBar(
                        options: ["Fill", "Outline"],
                        selectedIndex: document.activeTextIsOutline ? 1 : 0
                    ) { index in
                        applyOutline(index == 1)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ToolPanelSectionLabel("Stroke")
                    ToolPanelNumericStepper(
                        text: $strokeText,
                        placeholder: "0",
                        unitLabel: units.shortLabel,
                        onMinus: { stepStroke(by: -Self.strokeStepPoints) },
                        onPlus: { stepStroke(by: Self.strokeStepPoints) },
                        onSubmit: applyStroke
                    )
                }

                colorRow
            }

            HStack {
                Spacer()
                ToolPanelCancelButton(action: onCancel)
            }
        }
        .toolPanelChrome(width: panelWidth)
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Color")

            HStack(spacing: 2) {
                Rectangle()
                    .fill(document.strokeColor.color)
                    .frame(width: 26, height: 26)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))

                Button {
                    showColorPicker = true
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Text color")
                .sheet(isPresented: $showColorPicker) {
                    SystemColorPickerSheet(
                        color: Binding(
                            get: { document.strokeColor.color },
                            set: { applyColor(CodableColor($0)) }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Side font menu

    private var fontMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(library.builtInFonts.enumerated()), id: \.element.id) { index, font in
                        if index > 0 {
                            fontMenuDivider
                        }
                        fontRow(
                            name: font.displayName,
                            ref: .builtin(font.displayName),
                            previewFont: Font(font.uiFont(size: 17))
                        )
                    }

                    if !library.importedFonts.isEmpty {
                        fontMenuDivider
                        ForEach(Array(library.importedFonts.enumerated()), id: \.element.id) { index, font in
                            if index > 0 {
                                fontMenuDivider
                            }
                            fontRow(
                                name: font.displayName,
                                ref: font.fontRef,
                                previewFont: previewFont(for: font)
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            fontMenuDivider

            Button {
                showImporter = true
            } label: {
                Text("Import Font")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.toolPanelButtonForeground)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 200)
        .background(Color.toolPanelButtonFill)
    }

    private var fontMenuDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }

    @ViewBuilder
    private func fontRow(name: String, ref: FontRef, previewFont: Font) -> some View {
        let selected = document.activeFontRef == ref
        Button {
            select(ref)
        } label: {
            HStack(spacing: 8) {
                Text(name)
                    .font(previewFont)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.black : Color.toolPanelButtonForeground)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.black)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func previewFont(for font: ImportedFont) -> Font {
        if let uiFont = UIFont(name: font.postScriptName, size: 17) {
            return Font(uiFont)
        }
        return .system(size: 17)
    }

    // MARK: - Actions

    private func select(_ ref: FontRef) {
        document.activeFontRef = ref
        if let id = document.selectedTextID, var element = document.textElement(with: id) {
            element.fontRef = ref
            document.updateTextElement(element)
        }
        showFontMenu = false
        onChanged()
    }

    private func applyOutline(_ isOutline: Bool) {
        document.activeTextIsOutline = isOutline
        if let id = document.selectedTextID {
            document.setTextOutline(id: id, isOutline: isOutline, recordUndo: true)
        }
        onChanged()
    }

    private func applyColor(_ color: CodableColor) {
        document.strokeColor = color
        if let id = document.selectedTextID {
            if document.activeTextIsOutline {
                document.setTextStrokeColor(id: id, color: color)
            } else {
                document.setTextFillColor(id: id, color: color)
            }
        }
        onChanged()
    }

    private func displayString(_ value: CGFloat) -> String {
        var text = String(format: "%.4f", value)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text.isEmpty ? "0" : text
    }

    private func syncStrokeText() {
        strokeText = displayString(units.fromDocumentUnits(document.activeTextStrokeWidth))
    }

    private func applyStroke() {
        let cleaned = strokeText
            .replacingOccurrences(of: units.shortLabel, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else {
            syncStrokeText()
            return
        }
        setStrokeWidth(units.toDocumentUnits(CGFloat(value)))
    }

    private func stepStroke(by deltaDocPoints: CGFloat) {
        setStrokeWidth(document.activeTextStrokeWidth + deltaDocPoints)
    }

    private func setStrokeWidth(_ proposed: CGFloat) {
        let clamped = min(Self.strokeRange.upperBound, max(Self.strokeRange.lowerBound, proposed))
        document.activeTextStrokeWidth = clamped
        if let id = document.selectedTextID {
            document.setTextStrokeWidth(id: id, width: clamped, recordUndo: true)
        }
        syncStrokeText()
        onChanged()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let imported = try library.importFont(from: url)
                select(imported.fontRef)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private static var fontContentTypes: [UTType] {
        let types = ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.font] : types
    }
}
