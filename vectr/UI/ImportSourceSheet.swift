//
//  ImportSourceSheet.swift
//  vectr
//

import SwiftUI

enum ImportSource: Equatable {
    case files
    case photoLibrary

    var label: String {
        switch self {
        case .files: return "Files"
        case .photoLibrary: return "Photo Library"
        }
    }
}

/// Same chrome as the export sheet: dark page, square corners, one row per source.
struct ImportSourceSheet: View {
    var onSelect: (ImportSource) -> Void
    @Environment(\.dismiss) private var dismiss

    private var pageColor: Color { Color(hex: AppearanceSettings.pasteboardHex) }
    private var cardColor: Color { Color(hex: AppearanceSettings.toolbarHex) }

    private let sources: [ImportSource] = [.files, .photoLibrary]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(Array(sources.enumerated()), id: \.element.label) { index, source in
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 1)
                                }
                                sourceRow(source)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardColor)
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(pageColor)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                }
            }
        }
        .presentationBackground(pageColor)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func sourceRow(_ source: ImportSource) -> some View {
        Button {
            onSelect(source)
            dismiss()
        } label: {
            Text(source.label)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
