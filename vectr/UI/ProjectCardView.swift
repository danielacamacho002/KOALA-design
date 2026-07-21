//
//  ProjectCardView.swift
//  vectr
//

import SwiftUI

struct ProjectCardView: View {
    let record: ProjectRecord
    var isSelected: Bool = false
    var isSelectionMode: Bool = false
    var compact: Bool = false

    @AppStorage(AppearanceSettings.canvasColorKey) private var canvasColorHex = AppearanceSettings.defaultCanvasHex

    private var canvasColor: Color { Color(hex: canvasColorHex) }
    private var panelColor: Color { Color(hex: AppearanceSettings.panelHex) }
    private var cornerRadius: CGFloat { compact ? 6 : 10 }

    var body: some View {
        if compact {
            listRow
        } else {
            gridCard
        }
    }

    private var gridCard: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                if isSelectionMode {
                    selectionBadge
                        .padding(8)
                }
            }

            Text(record.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(record.dimensionsLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    private var listRow: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                selectionBadge
            }

            thumbnail
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(record.dimensionsLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
            }

            Spacer()

            Text(record.modifiedAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.white)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = record.thumbnailURL, let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .background(canvasColor)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(panelColor.opacity(0.35))
                .overlay {
                    Image(systemName: "scribble.variable")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
        }
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.white)
            .symbolRenderingMode(.hierarchical)
    }
}
