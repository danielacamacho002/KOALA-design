//
//  ConstraintSettingsView.swift
//  vectr
//

import SwiftUI

struct ConstraintSettingsView: View {
    @Bindable var document: VectrDocument

    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            StudioIconButton(
                systemImage: "circle.circle",
                isActive: document.constraints.midpointEnabled,
                size: iconSize
            ) {
                document.constraints.midpointEnabled.toggle()
            }
            .accessibilityLabel("Midpoint snap")

            StudioIconButton(
                systemImage: "angle",
                isActive: document.constraints.perpendicularEnabled,
                size: iconSize
            ) {
                document.constraints.perpendicularEnabled.toggle()
            }
            .accessibilityLabel("Perpendicular snap")

            StudioIconButton(
                systemImage: "scope",
                isActive: document.constraints.coincidentEnabled,
                size: iconSize
            ) {
                document.constraints.coincidentEnabled.toggle()
            }
            .accessibilityLabel("Coincident snap")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }
}
