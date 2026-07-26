//
//  FontPickerView.swift
//  vectr
//

import SwiftUI
import UniformTypeIdentifiers

struct FontPickerView: View {
    @Bindable var document: VectrDocument
    @Bindable var library: FontLibrary
    var onDismiss: () -> Void

    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolPanelHeader("Font")

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(library.builtInFonts) { font in
                        fontRow(
                            name: font.displayName,
                            ref: .builtin(font.displayName),
                            previewFont: Font(font.uiFont(size: 17))
                        )
                    }

                    if !library.importedFonts.isEmpty {
                        ToolPanelSectionLabel("Imported")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        ForEach(library.importedFonts) { font in
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

            ToolPanelLabelButton(title: "Import Font", fullWidth: true) {
                showImporter = true
            }
        }
        .toolPanelChrome(width: 200)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.fontContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    @ViewBuilder
    private func fontRow(name: String, ref: FontRef, previewFont: Font) -> some View {
        let selected = isSelected(ref)
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
            .background(selected ? Color.accentColor : Color.toolPanelButtonFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ ref: FontRef) -> Bool {
        document.activeFontRef == ref
    }

    private func previewFont(for font: ImportedFont) -> Font {
        if let uiFont = UIFont(name: font.postScriptName, size: 17) {
            return Font(uiFont)
        }
        return .system(size: 17)
    }

    private func select(_ ref: FontRef) {
        document.activeFontRef = ref
        if let id = document.selectedTextID, var element = document.textElement(with: id) {
            element.fontRef = ref
            document.updateTextElement(element)
        }
        onDismiss()
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
