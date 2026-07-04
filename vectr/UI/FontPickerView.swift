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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(library.builtInFonts) { font in
                        fontRow(
                            name: font.displayName,
                            ref: .builtin(font.displayName),
                            previewFont: Font(font.uiFont(size: 17))
                        )
                        Divider().padding(.leading, 14)
                    }

                    if !library.importedFonts.isEmpty {
                        sectionHeader("Imported")
                        ForEach(library.importedFonts) { font in
                            fontRow(
                                name: font.displayName,
                                ref: font.fontRef,
                                previewFont: previewFont(for: font)
                            )
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)

            Divider()

            Button {
                showImporter = true
            } label: {
                Label("Import Font", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 248)
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
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func fontRow(name: String, ref: FontRef, previewFont: Font) -> some View {
        Button {
            select(ref)
        } label: {
            HStack(spacing: 10) {
                Text(name)
                    .font(previewFont)
                    .lineLimit(1)
                    .foregroundStyle(isSelected(ref) ? Color.accentColor : Color.primary)
                Spacer(minLength: 12)
                if isSelected(ref) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
