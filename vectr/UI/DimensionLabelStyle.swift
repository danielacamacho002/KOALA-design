//
//  DimensionLabelStyle.swift
//  vectr
//

import SwiftUI

enum DimensionLabelStyle {
    static let font: Font = .caption.weight(.semibold).monospacedDigit()

    static func foregroundColor(locked: Bool) -> Color {
        locked ? Color.secondary : Color.accentColor
    }
}

extension View {
    /// Plain floating dimension text, similar to Shapr3D — no pill chrome.
    func dimensionLabelAppearance(locked: Bool = false) -> some View {
        font(DimensionLabelStyle.font)
            .foregroundStyle(DimensionLabelStyle.foregroundColor(locked: locked))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }
}
