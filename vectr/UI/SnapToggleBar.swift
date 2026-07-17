//
//  SnapToggleBar.swift
//  vectr
//

import SwiftUI

/// Bottom-left canvas control for the object snapping engine. Independent toggles drive
/// which snap types the engine considers: Endpoints (square), Midpoints (triangle) and
/// Intersections (X). These map directly to `PathSnapEngine`'s enabled kinds via the
/// document toggles.
struct SnapToggleBar: View {
    @Bindable var document: VectrDocument

    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            StudioIconButton(
                systemImage: "square",
                isActive: document.endpointSnapEnabled,
                size: iconSize
            ) {
                document.endpointSnapEnabled.toggle()
            }
            .accessibilityLabel("Endpoint snap")

            StudioIconButton(
                systemImage: "triangle",
                isActive: document.midpointSnapEnabled,
                size: iconSize
            ) {
                document.midpointSnapEnabled.toggle()
            }
            .accessibilityLabel("Midpoint snap")

            StudioIconButton(
                systemImage: "xmark",
                isActive: document.intersectionSnapEnabled,
                size: iconSize
            ) {
                document.intersectionSnapEnabled.toggle()
            }
            .accessibilityLabel("Intersection snap")

            StudioIconButton(
                systemImage: "smallcircle.circle",
                isActive: document.centerSnapEnabled,
                size: iconSize
            ) {
                document.centerSnapEnabled.toggle()
            }
            .accessibilityLabel("Center point snap")

            StudioIconButton(
                systemImage: "diamond",
                isActive: document.quadrantSnapEnabled,
                size: iconSize
            ) {
                document.quadrantSnapEnabled.toggle()
            }
            .accessibilityLabel("Quadrant snap")

            StudioIconButton(
                systemImage: "circle.and.line.horizontal",
                isActive: document.tangentSnapEnabled,
                size: iconSize
            ) {
                document.tangentSnapEnabled.toggle()
            }
            .accessibilityLabel("Tangential snap")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }
}
