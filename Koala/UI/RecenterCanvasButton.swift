//
//  RecenterCanvasButton.swift
//  Koala
//

import SwiftUI

struct RecenterCanvasButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "scope")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(.primary.opacity(0.88))
                .background {
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter")
    }
}
