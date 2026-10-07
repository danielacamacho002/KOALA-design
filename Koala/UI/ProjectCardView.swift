//
//  ProjectCardView.swift
//  Koala
//

import SwiftUI

struct ProjectCardView: View {
    let record: ProjectRecord
    var isSelected: Bool = false
    var isSelectionMode: Bool = false
    var compact: Bool = false

    @AppStorage(AppearanceSettings.canvasColorKey) private var canvasColorHex = AppearanceSettings.defaultCanvasHex
    @State private var thumbnailImage: UIImage?

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
        Group {
            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
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
        .task(id: thumbnailTaskID) {
            await loadThumbnail()
        }
    }

    private var thumbnailTaskID: String {
        "\(record.thumbnailURL?.path ?? "")|\(record.modifiedAt.timeIntervalSince1970)"
    }

    private func loadThumbnail() async {
        guard let url = record.thumbnailURL else {
            thumbnailImage = nil
            return
        }
        if let cached = ProjectThumbnailCache.image(for: url, modifiedAt: record.modifiedAt) {
            thumbnailImage = cached
            return
        }
        let data = try? await PersistenceWorker.shared.readFileData(from: url)
        guard let data, let image = UIImage(data: data) else {
            thumbnailImage = nil
            return
        }
        ProjectThumbnailCache.store(image, for: url, modifiedAt: record.modifiedAt)
        thumbnailImage = image
    }

    private var selectionBadge: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.white)
            .symbolRenderingMode(.hierarchical)
    }
}
