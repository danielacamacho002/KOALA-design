//
//  LayersPanelView.swift
//  vectr
//

import SwiftUI

/// Collapsible layers panel (Procreate-style toggle, Illustrator-style ordering).
/// Collapsed it is a single icon button; expanded it shows the layer stack with
/// the frontmost layer at the top of the list.
struct LayersPanelView: View {
    @Bindable var document: VectrDocument
    /// Expansion is owned by the editor so taps outside the panel can collapse it.
    @Binding var isExpanded: Bool
    /// Called after any mutation so the owner can mark the document dirty.
    var onChanged: () -> Void

    @State private var renamingLayerID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private let panelWidth: CGFloat = 248
    private let rowHeight: CGFloat = 44
    private let maxListHeight: CGFloat = 308

    var body: some View {
        Group {
            if isExpanded {
                panelCard
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                toggleButton
                    .padding(.trailing, 16)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { commitRenameIfNeeded() }
        }
    }

    // MARK: - Collapsed toggle

    private var toggleButton: some View {
        StudioIconButton(
            systemImage: "square.3.layers.3d",
            isActive: isExpanded,
            size: 34
        ) {
            isExpanded.toggle()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Rectangle().fill(Color.primary.opacity(0.05)))
        .accessibilityLabel(isExpanded ? "Hide layers" : "Show layers")
    }

    // MARK: - Expanded card

    private var panelCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            panelHeader
            layerList
        }
        .padding(10)
        .frame(width: panelWidth)
        .background(Rectangle().fill(Color(hex: AppearanceSettings.panelHex)))
        .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Text("Layers")
                .font(.caption.weight(.semibold))

            Spacer()

            Button {
                commitRenameIfNeeded()
                document.addLayer()
                onChanged()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add layer")

            Button {
                commitRenameIfNeeded()
                isExpanded = false
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse layers panel")
        }
    }

    /// Top row = frontmost layer (last in the document's back-to-front array).
    private var displayedLayers: [Layer] {
        document.layers.reversed()
    }

    private var layerList: some View {
        List {
            ForEach(displayedLayers) { layer in
                layerRow(layer)
                    .frame(height: rowHeight - 12)
                    .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 2))
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        Rectangle()
                            .fill(layer.id == document.activeLayerID
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear)
                            .padding(.vertical, 2)
                    )
            }
            .onMove(perform: moveRows)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .environment(\.defaultMinListRowHeight, rowHeight)
        .frame(height: min(CGFloat(document.layers.count) * rowHeight, maxListHeight))
    }

    // MARK: - Row

    @ViewBuilder
    private func layerRow(_ layer: Layer) -> some View {
        HStack(spacing: 6) {
            LayerThumbnailView(document: document, layerID: layer.id)
                .onTapGesture { activate(layer) }

            if renamingLayerID == layer.id {
                TextField("Layer name", text: $renameText)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Rectangle().fill(Color(.systemBackground)))
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    .focused($renameFieldFocused)
                    .onSubmit { commitRenameIfNeeded() }
            } else {
                Text(layer.name)
                    .font(.caption.weight(layer.id == document.activeLayerID ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded { beginRename(layer) }
                            .exclusively(
                                before: TapGesture().onEnded { activate(layer) }
                            )
                    )
            }

            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                .font(.caption)
                .foregroundStyle(layer.isVisible ? Color.primary.opacity(0.72) : Color.primary.opacity(0.28))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    document.toggleLayerVisibility(id: layer.id)
                    onChanged()
                }
                .accessibilityLabel(layer.isVisible ? "Hide layer" : "Show layer")

            Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                .font(.caption)
                .foregroundStyle(layer.isLocked ? Color.accentColor : Color.primary.opacity(0.28))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    document.toggleLayerLock(id: layer.id)
                    onChanged()
                }
                .accessibilityLabel(layer.isLocked ? "Unlock layer" : "Lock layer")

            Menu {
                Button {
                    beginRename(layer)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    document.deleteLayer(id: layer.id)
                    onChanged()
                } label: {
                    Label("Delete Layer", systemImage: "trash")
                }
                .disabled(document.layers.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Layer options")
        }
    }

    // MARK: - Actions

    private func activate(_ layer: Layer) {
        commitRenameIfNeeded()
        document.setActiveLayer(id: layer.id)
        onChanged()
    }

    private func beginRename(_ layer: Layer) {
        commitRenameIfNeeded()
        renameText = layer.name
        renamingLayerID = layer.id
        renameFieldFocused = true
    }

    private func commitRenameIfNeeded() {
        guard let id = renamingLayerID else { return }
        document.renameLayer(id: id, to: renameText)
        renamingLayerID = nil
        renameFieldFocused = false
        onChanged()
    }

    /// `List.onMove` indices are in display (front-to-back) order; the document
    /// stores layers back-to-front, so reorder a reversed copy and flip it back.
    private func moveRows(from source: IndexSet, to destination: Int) {
        var displayed = displayedLayers
        displayed.move(fromOffsets: source, toOffset: destination)
        document.reorderLayers(displayed.reversed())
        onChanged()
    }
}

/// Small preview of a single layer's content, zoomed to fit that layer's
/// drawing. Re-renders whenever document geometry changes.
private struct LayerThumbnailView: View {
    let document: VectrDocument
    let layerID: UUID

    @State private var image: UIImage?

    private let thumbnailSize = CGSize(width: 38, height: 30)

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(.systemBackground))

            if let image {
                Image(uiImage: image)
            } else {
                Image(systemName: "scribble")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.primary.opacity(0.2))
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .onAppear { regenerate() }
        .onChange(of: document.geometryRevision) { _, _ in regenerate() }
    }

    private func regenerate() {
        image = LayerThumbnailRenderer.render(
            document: document,
            layerID: layerID,
            size: thumbnailSize
        )
    }
}
