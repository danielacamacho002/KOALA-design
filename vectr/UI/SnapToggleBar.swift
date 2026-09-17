//
//  SnapToggleBar.swift
//  vectr
//

import SwiftUI

/// Bottom-left canvas control for the object snapping engine. Starts as a single
/// button; tapping it reveals independent toggles for which snap types the engine
/// considers: Endpoints (square), Midpoints (triangle), Intersections (X), Center,
/// and on-rim / compass (diamond). These map directly to `PathSnapEngine`'s enabled
/// kinds via the document toggles.
struct SnapToggleBar: View {
    @Bindable var document: VectrDocument
    @State private var isExpanded = false

    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            StudioIconButton(
                systemImage: "circle.grid.cross",
                isActive: isExpanded,
                size: iconSize
            ) {
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .accessibilityLabel(isExpanded ? "Hide snaps" : "Show snaps")

            if isExpanded {
                snapToggles
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        // The bar sits on the cream canvas, so icons must stay dark even when
        // the rest of the app is in dark mode (Color.primary would otherwise
        // go white and vanish).
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var snapToggles: some View {
        StudioIconButton(
            isActive: document.endpointSnapEnabled,
            size: iconSize,
            action: { document.endpointSnapEnabled.toggle() }
        ) {
            EndpointSnapIcon()
                .frame(width: 17, height: 17)
        }
        .accessibilityLabel("Endpoint snap")

        StudioIconButton(
            isActive: document.midpointSnapEnabled,
            size: iconSize,
            action: { document.midpointSnapEnabled.toggle() }
        ) {
            MidpointSnapIcon()
                .frame(width: 17, height: 17)
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
            isActive: document.quadrantSnapEnabled,
            size: iconSize,
            action: { document.quadrantSnapEnabled.toggle() }
        ) {
            QuadrantSnapIcon()
                .frame(width: 21, height: 21)
        }
        .accessibilityLabel("Circle snap")
    }
}
