//
//  RecenterCanvasButton.swift
//  vectr
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
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter")
    }
}
