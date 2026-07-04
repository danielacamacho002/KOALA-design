//
//  TextToolPanelView.swift
//  vectr
//

import SwiftUI

/// Floating panel for entering and editing a text element's content and size.
struct TextToolPanelView: View {
    @Bindable var document: VectrDocument
    let elementID: UUID
    var onChanged: () -> Void
    var onDone: () -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Text")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Done", action: onDone)
                    .font(.subheadline.weight(.semibold))
            }

            TextField("Type here", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .focused($focused)
                .onChange(of: text) { _, newValue in
                    applyText(newValue)
                }

            HStack(spacing: 10) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(.secondary)
                Slider(value: fontSizeBinding, in: 6...200, step: 1)
                Text("\(Int(currentFontSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(12)
        .frame(width: 264)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            text = document.textElement(with: elementID)?.text ?? ""
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: elementID) { _, _ in
            text = document.textElement(with: elementID)?.text ?? ""
        }
    }

    private var currentFontSize: CGFloat {
        document.textElement(with: elementID)?.fontSize ?? document.activeFontSize
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(currentFontSize) },
            set: { newValue in
                document.activeFontSize = CGFloat(newValue)
                document.setTextFontSize(id: elementID, size: CGFloat(newValue))
                onChanged()
            }
        )
    }

    private func applyText(_ newValue: String) {
        guard var element = document.textElement(with: elementID) else { return }
        element.text = newValue
        document.updateTextElement(element, recordUndo: false)
        onChanged()
    }
}
