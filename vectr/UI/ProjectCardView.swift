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
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if isSelectionMode {
                    selectionBadge
                        .padding(8)
                }
            }

            Text(record.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(record.dimensionsLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var listRow: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                selectionBadge
            }

            thumbnail
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(record.dimensionsLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.modifiedAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = record.thumbnailURL, let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .background(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: compact ? 6 : 10)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    Image(systemName: "scribble.variable")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            .symbolRenderingMode(.hierarchical)
    }
}
