//
//  ColorPaletteView.swift
//  Koala
//

import SwiftUI

struct ColorPaletteView: View {
    @Binding var selectedColor: CodableColor

    private let palette: [CodableColor] = [
        CodableColor(red: 0, green: 0, blue: 0),
        CodableColor(red: 1, green: 1, blue: 1),
        CodableColor(red: 0.9, green: 0.2, blue: 0.2),
        CodableColor(red: 0.2, green: 0.5, blue: 0.95),
        CodableColor(red: 0.2, green: 0.75, blue: 0.35),
        CodableColor(red: 0.95, green: 0.75, blue: 0.1),
        CodableColor(red: 0.55, green: 0.35, blue: 0.85),
        CodableColor(red: 0.5, green: 0.5, blue: 0.55)
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(palette.indices, id: \.self) { index in
                let color = palette[index]
                Button {
                    selectedColor = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selectedColor == color ? Color.accentColor : Color.clear,
                                    lineWidth: 3
                                )
                        }
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
                .buttonStyle(.plain)
            }

            ColorPicker("", selection: Binding(
                get: { selectedColor.color },
                set: { selectedColor = CodableColor($0) }
            ))
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
