//
//  LayersPanelView.swift
//  Koala
//

import SwiftUI

/// Collapsible layers panel (Procreate-style toggle, Illustrator-style ordering).
/// Collapsed it is a single icon button; expanded it shows the layer stack with
/// the frontmost layer at the top of the list. Layers can be organized into
/// folders and multi-selected to group or merge them.
struct LayersPanelView: View {
    @Bindable var document: KoalaDocument
    /// Expansion is owned by the editor so taps outside the panel can collapse it.
    @Binding var isExpanded: Bool
    /// Called after any mutation so the owner can mark the document dirty.
    var onChanged: () -> Void
    /// Top-left of this chrome overlay, in canvas-view coordinates.
    var overlayOrigin: CGPoint
    var isTourHighlighted: Bool = false

    @State private var renamingLayerID: UUID?
    @State private var renamingGroupID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool
    /// Layers picked for a group/merge operation (independent of the active layer).
    @State private var selectedLayerIDs: Set<UUID> = []
    /// Local slider value so programmatic sync does not rewrite the document.
    @State private var opacitySlider: Double = 1
    /// Finger-drag of a row grip. Undo is recorded once for the whole drag.
    @State private var reorderDrag: LayerReorderDrag?
    @Environment(\.colorScheme) private var colorScheme

    private let panelWidth: CGFloat = 280
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
        .onboardingAnchor(.layers)
        .onboardingHighlight(isTourHighlighted, cornerRadius: isExpanded ? 0 : 8)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                commitRenameIfNeeded()
                selectedLayerIDs = []
                reorderDrag = nil
            }
        }
    }

    // MARK: - Collapsed toggle

    private var toggleButton: some View {
        let sheet = CanvasIconContrast.sheetRect(
            viewport: document.viewport,
            canvasSize: document.settings.canvasSize,
            overlayOrigin: overlayOrigin
        )
        return CanvasContrastTint(canvasRect: sheet) { overCanvas in
            StudioIconButton(
                systemImage: "square.3.layers.3d",
                isActive: isExpanded,
                size: 34,
                inactiveColor: CanvasIconContrast.iconColor(isOverCanvas: overCanvas)
            ) {
                isExpanded.toggle()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Rectangle().fill(CanvasIconContrast.washColor(isOverCanvas: overCanvas)))
            .accessibilityLabel(isExpanded ? "Hide layers" : "Show layers")
        }
    }

    // MARK: - Expanded card

    private var panelCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            panelHeader
            opacityControls
            if !selectedLayerIDs.isEmpty {
                selectionBar
            }
            layerList
        }
        .padding(10)
        .frame(width: panelWidth)
        .foregroundStyle(.white)
        .background(Rectangle().fill(Color(hex: AppearanceSettings.toolbarHex)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        // Scoped to the expanded card so the collapsed panel does not observe
        // `geometryRevision` and wake on every frame of a canvas drag.
        .onAppear { syncOpacitySlider() }
        .onChange(of: document.activeLayerID) { _, _ in syncOpacitySlider() }
        .onChange(of: selectedLayerIDs) { _, _ in syncOpacitySlider() }
        .onChange(of: document.geometryRevision) { _, _ in syncOpacitySlider() }
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
                    .foregroundStyle(Color.toolPanelSecondaryLabel)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse layers panel")
        }
    }

    private var opacityControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(opacityTargetIDs.count > 1 ? "Opacity (\(opacityTargetIDs.count))" : "Opacity")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.toolPanelSecondaryLabel)
                Spacer()
                Text(opacityLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.toolPanelSecondaryLabel)
            }
            LayerOpacityBar(value: opacityBinding) { editing in
                if editing {
                    document.beginInteractiveEdit()
                } else {
                    onChanged()
                }
            }
        }
        .padding(.horizontal, 2)
    }

    /// Contextual actions shown while one or more layers are selected.
    private var selectionBar: some View {
        HStack(spacing: 8) {
            Text("\(validSelection.count) selected")
                .font(.caption2.weight(.medium))
                .foregroundStyle(SelectionHighlight.font)

            Spacer()

            Button {
                groupSelected()
            } label: {
                Label {
                    Text("Group")
                        .foregroundStyle(SelectionHighlight.font)
                } icon: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(SelectionHighlight.icon)
                }
                .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(validSelection.isEmpty)
            .opacity(validSelection.isEmpty ? 0.4 : 1)

            Button {
                mergeSelected()
            } label: {
                Label {
                    Text("Merge")
                        .foregroundStyle(SelectionHighlight.font)
                } icon: {
                    Image(systemName: "arrow.triangle.merge")
                        .foregroundStyle(SelectionHighlight.icon)
                }
                .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(validSelection.count < 2)
            .opacity(validSelection.count < 2 ? 0.4 : 1)

            Button {
                selectedLayerIDs = []
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SelectionHighlight.icon)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selection")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Rectangle().fill(SelectionHighlight.background))
    }

    private var layerList: some View {
        List {
            ForEach(displayRows) { row in
                HStack(spacing: 2) {
                    rowView(row)
                    reorderGrip(for: row)
                }
                .frame(height: rowHeight - 12)
                .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(rowBackground(row))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, rowHeight)
        .frame(height: min(CGFloat(displayRows.count) * rowHeight, maxListHeight))
    }

    /// Same dark gray as the filled opacity line. Drawn here because the system
    /// list grip stays light gray and does not take a tint.
    private var reorderGripColor: Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return Color(uiColor: LayerOpacityBar.gripUIColor(
            compatibleWith: UITraitCollection(userInterfaceStyle: style)
        ))
    }

    private func reorderGrip(for row: PanelRow) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(reorderGripColor)
            .frame(width: 22, height: rowHeight - 12, alignment: .trailing)
            .contentShape(Rectangle())
            .highPriorityGesture(reorderGesture(for: row))
            .accessibilityLabel("Move layer")
    }

    private func reorderGesture(for row: PanelRow) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let rows = displayRows
                guard let current = rows.firstIndex(where: { $0.id == row.id }) else { return }
                if reorderDrag?.rowID != row.id {
                    reorderDrag = LayerReorderDrag(rowID: row.id, startIndex: current, didRecordUndo: false)
                }
                guard let drag = reorderDrag else { return }
                let delta = Int((value.translation.height / rowHeight).rounded())
                let target = min(max(drag.startIndex + delta, 0), rows.count - 1)
                guard target != current else { return }
                moveRows(
                    from: IndexSet(integer: current),
                    to: target > current ? target + 1 : target,
                    recordUndo: !drag.didRecordUndo
                )
                reorderDrag?.didRecordUndo = true
            }
            .onEnded { _ in
                reorderDrag = nil
            }
    }

    // MARK: - Display model

    /// A panel entry: either a folder header or a layer. Folders appear at the
    /// position of their front-most member; a collapsed folder hides its layers.
    private enum PanelRow: Identifiable, Equatable {
        case folder(LayerGroup)
        case layer(Layer, indented: Bool)

        var id: String {
            switch self {
            case .folder(let group): return "folder-\(group.id.uuidString)"
            case .layer(let layer, _): return "layer-\(layer.id.uuidString)"
            }
        }
    }

    /// Rows in display (front-to-back) order.
    private var displayRows: [PanelRow] {
        var rows: [PanelRow] = []
        var emittedGroups = Set<UUID>()
        for layer in document.layers.reversed() {
            if let gid = layer.groupID, let group = document.layerGroup(with: gid) {
                if !emittedGroups.contains(gid) {
                    emittedGroups.insert(gid)
                    rows.append(.folder(group))
                }
                if !group.isCollapsed {
                    rows.append(.layer(layer, indented: true))
                }
            } else {
                rows.append(.layer(layer, indented: false))
            }
        }
        return rows
    }

    @ViewBuilder
    private func rowBackground(_ row: PanelRow) -> some View {
        switch row {
        case .folder:
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .padding(.vertical, 2)
        case .layer:
            Rectangle()
                .fill(Color.clear)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func rowView(_ row: PanelRow) -> some View {
        switch row {
        case .folder(let group):
            folderRow(group)
        case .layer(let layer, let indented):
            layerRow(layer, indented: indented)
        }
    }

    // MARK: - Folder row

    @ViewBuilder
    private func folderRow(_ group: LayerGroup) -> some View {
        let members = document.layers(inGroup: group.id)
        HStack(spacing: 6) {
            selectionToggle(isOn: membersAllSelected(members), isMixed: membersSomeSelected(members)) {
                toggleFolderSelection(members)
            }

            Button {
                document.toggleLayerGroupCollapsed(id: group.id)
                onChanged()
            } label: {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.toolPanelSecondaryLabel)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            Image(systemName: group.isCollapsed ? "folder.fill" : "folder")
                .font(.caption)
                .foregroundStyle(Color.accentColor.opacity(0.85))

            if renamingGroupID == group.id {
                renameField
            } else {
                Text(group.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded { beginRenameGroup(group) }
                            .exclusively(
                                before: TapGesture().onEnded {
                                    document.toggleLayerGroupCollapsed(id: group.id)
                                    onChanged()
                                }
                            )
                    )
            }

            let memberOpacities = members.map(\.resolvedOpacity)
            if let first = memberOpacities.first,
               first < 0.999,
               memberOpacities.allSatisfy({ abs($0 - first) < 0.001 }) {
                Text("\(Int((first * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.toolPanelSecondaryLabel)
            }

            let allVisible = document.layerGroupIsVisible(id: group.id)
            Image(systemName: allVisible ? "eye" : "eye.slash")
                .font(.caption)
                .foregroundStyle(allVisible ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    document.setLayerGroupVisibility(id: group.id, isVisible: !allVisible)
                    onChanged()
                }
                .accessibilityLabel(allVisible ? "Hide folder" : "Show folder")

            let allLocked = document.layerGroupIsLocked(id: group.id)
            Image(systemName: allLocked ? "lock.fill" : "lock.open")
                .font(.caption)
                .foregroundStyle(allLocked ? Color.accentColor : Color.white.opacity(0.35))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    document.setLayerGroupLocked(id: group.id, isLocked: !allLocked)
                    onChanged()
                }
                .accessibilityLabel(allLocked ? "Unlock folder" : "Lock folder")

            Menu {
                Button {
                    beginRenameGroup(group)
                } label: {
                    Label("Rename Folder", systemImage: "pencil")
                }

                if members.contains(where: { $0.resolvedOpacity < 0.999 }) {
                    Button {
                        document.setLayerGroupOpacity(id: group.id, opacity: 1)
                        onChanged()
                    } label: {
                        Label("Reset Opacity", systemImage: "circle.lefthalf.filled")
                    }
                }

                Button {
                    document.ungroupLayers(groupID: group.id)
                    onChanged()
                } label: {
                    Label("Ungroup", systemImage: "folder.badge.minus")
                }

                Button {
                    mergeFolder(group)
                } label: {
                    Label("Merge Folder", systemImage: "arrow.triangle.merge")
                }
                .disabled(members.count < 2)

                Divider()

                Button(role: .destructive) {
                    deleteFolder(group)
                } label: {
                    Label("Delete Folder & Layers", systemImage: "trash")
                }
                .disabled(members.count >= document.layers.count)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Folder options")
        }
    }

    // MARK: - Layer row

    @ViewBuilder
    private func layerRow(_ layer: Layer, indented: Bool) -> some View {
        HStack(spacing: 6) {
            selectionToggle(isOn: layerDotIsOn(layer), isMixed: false) {
                toggleSelection(layer.id)
            }

            if indented {
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1)
                    .padding(.leading, 4)
            }

            LayerThumbnailView(document: document, layerID: layer.id)
                .opacity(layer.resolvedOpacity)
                .onTapGesture { activate(layer) }

            if renamingLayerID == layer.id {
                renameField
            } else {
                Text(layer.name)
                    .font(.caption.weight(layer.id == document.activeLayerID ? .semibold : .regular))
                    .foregroundStyle(Color.white)
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

            if layer.resolvedOpacity < 0.999 {
                Text("\(Int((layer.resolvedOpacity * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.toolPanelSecondaryLabel)
            }

            Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                .font(.caption)
                .foregroundStyle(layer.isVisible ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    document.toggleLayerVisibility(id: layer.id)
                    onChanged()
                }
                .accessibilityLabel(layer.isVisible ? "Hide layer" : "Show layer")

            Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                .font(.caption)
                .foregroundStyle(layer.isLocked ? Color.accentColor : Color.white.opacity(0.35))
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

                if layer.resolvedOpacity < 0.999 {
                    Button {
                        document.setLayerOpacity(id: layer.id, opacity: 1)
                        onChanged()
                    } label: {
                        Label("Reset Opacity", systemImage: "circle.lefthalf.filled")
                    }
                }

                if layer.groupID != nil {
                    Button {
                        removeFromFolder(layer)
                    } label: {
                        Label("Remove from Folder", systemImage: "folder.badge.minus")
                    }
                }

                Button(role: .destructive) {
                    document.deleteLayer(id: layer.id)
                    selectedLayerIDs.remove(layer.id)
                    onChanged()
                } label: {
                    Label("Delete Layer", systemImage: "trash")
                }
                .disabled(document.layers.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Layer options")
        }
    }

    // MARK: - Shared subviews

    private var renameField: some View {
        TextField(
            "",
            text: $renameText,
            prompt: Text("Name").foregroundStyle(Color.white.opacity(0.45))
        )
            .font(.caption)
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Rectangle().fill(Color(hex: AppearanceSettings.toolbarHex)))
            .overlay(Rectangle().stroke(Color.white.opacity(0.28), lineWidth: 1))
            .focused($renameFieldFocused)
            .onSubmit { commitRenameIfNeeded() }
    }

    private func selectionToggle(isOn: Bool, isMixed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? "circle.fill" : (isMixed ? "circle.lefthalf.filled" : "circle"))
                .font(.caption)
                .foregroundStyle(isOn || isMixed ? SelectionHighlight.icon : Color.white.opacity(0.35))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Deselect" : "Select")
    }

    // MARK: - Selection helpers

    /// The left dot is the only selected state: the active layer, or any layer picked for group/merge.
    private func layerDotIsOn(_ layer: Layer) -> Bool {
        layer.id == document.activeLayerID || selectedLayerIDs.contains(layer.id)
    }

    private var validSelection: Set<UUID> {
        selectedLayerIDs.intersection(Set(document.layers.map(\.id)))
    }

    /// Selected layers when a multi-select is active; otherwise the active layer.
    private var opacityTargetIDs: Set<UUID> {
        let selected = validSelection
        if !selected.isEmpty { return selected }
        return [document.activeLayerID]
    }

    private var opacityLabel: String {
        let values = document.layers.filter { opacityTargetIDs.contains($0.id) }.map(\.resolvedOpacity)
        guard let first = values.first else { return "100%" }
        if values.contains(where: { abs($0 - first) > 0.001 }) {
            return "Mixed"
        }
        return "\(Int((first * 100).rounded()))%"
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { opacitySlider },
            set: { newValue in
                opacitySlider = newValue
                document.setLayersOpacity(ids: opacityTargetIDs, opacity: CGFloat(newValue), recordUndo: false)
                onChanged()
            }
        )
    }

    private func syncOpacitySlider() {
        let values = document.layers.filter { opacityTargetIDs.contains($0.id) }.map(\.resolvedOpacity)
        if let first = values.first {
            opacitySlider = Double(first)
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedLayerIDs.contains(id) {
            selectedLayerIDs.remove(id)
        } else {
            selectedLayerIDs.insert(id)
        }
    }

    private func membersAllSelected(_ members: [Layer]) -> Bool {
        !members.isEmpty && members.allSatisfy { layerDotIsOn($0) }
    }

    private func membersSomeSelected(_ members: [Layer]) -> Bool {
        members.contains { layerDotIsOn($0) } && !membersAllSelected(members)
    }

    private func toggleFolderSelection(_ members: [Layer]) {
        if membersAllSelected(members) {
            for m in members { selectedLayerIDs.remove(m.id) }
        } else {
            for m in members { selectedLayerIDs.insert(m.id) }
        }
    }

    // MARK: - Actions

    private func groupSelected() {
        commitRenameIfNeeded()
        let ids = validSelection
        guard !ids.isEmpty else { return }
        document.groupLayers(ids: ids)
        selectedLayerIDs = []
        onChanged()
    }

    private func mergeSelected() {
        commitRenameIfNeeded()
        let ids = validSelection
        guard ids.count >= 2 else { return }
        if let target = document.mergeLayers(ids: ids) {
            document.setActiveLayer(id: target)
        }
        selectedLayerIDs = []
        onChanged()
    }

    private func mergeFolder(_ group: LayerGroup) {
        commitRenameIfNeeded()
        let ids = Set(document.layers(inGroup: group.id).map(\.id))
        guard ids.count >= 2 else { return }
        if let target = document.mergeLayers(ids: ids) {
            document.setActiveLayer(id: target)
        }
        selectedLayerIDs.subtract(ids)
        onChanged()
    }

    private func deleteFolder(_ group: LayerGroup) {
        commitRenameIfNeeded()
        let ids = document.layers(inGroup: group.id).map(\.id)
        for id in ids {
            document.deleteLayer(id: id)
            selectedLayerIDs.remove(id)
        }
        onChanged()
    }

    private func removeFromFolder(_ layer: Layer) {
        commitRenameIfNeeded()
        document.removeLayerFromFolder(layerID: layer.id)
        onChanged()
    }

    private func activate(_ layer: Layer) {
        commitRenameIfNeeded()
        document.setActiveLayer(id: layer.id)
        onChanged()
    }

    private func beginRename(_ layer: Layer) {
        commitRenameIfNeeded()
        renameText = layer.name
        renamingLayerID = layer.id
        renamingGroupID = nil
        renameFieldFocused = true
    }

    private func beginRenameGroup(_ group: LayerGroup) {
        commitRenameIfNeeded()
        renameText = group.name
        renamingGroupID = group.id
        renamingLayerID = nil
        renameFieldFocused = true
    }

    private func commitRenameIfNeeded() {
        guard renamingLayerID != nil || renamingGroupID != nil else { return }
        if let id = renamingLayerID {
            document.renameLayer(id: id, to: renameText)
        }
        if let id = renamingGroupID {
            document.renameLayerGroup(id: id, to: renameText)
        }
        renamingLayerID = nil
        renamingGroupID = nil
        renameFieldFocused = false
        onChanged()
    }

    /// `List.onMove` indices are in display (front-to-back) order. Rebuild the
    /// document's back-to-front `layers` array from the reordered rows; folder
    /// membership is preserved (only explicit actions change it) and normalized
    /// back to contiguous runs by the document.
    private func moveRows(from source: IndexSet, to destination: Int, recordUndo: Bool = true) {
        var rows = displayRows
        rows.move(fromOffsets: source, toOffset: destination)
        var frontToBack: [Layer] = []
        for row in rows {
            switch row {
            case .folder(let group):
                if group.isCollapsed {
                    frontToBack.append(contentsOf: document.layers(inGroup: group.id).reversed())
                }
            case .layer(let layer, _):
                if let current = document.layers.first(where: { $0.id == layer.id }) {
                    frontToBack.append(current)
                }
            }
        }
        document.reorderLayers(Array(frontToBack.reversed()), recordUndo: recordUndo)
        onChanged()
    }
}

/// In-progress grip drag. `startIndex` stays put so later movement is measured
/// from where the row began, not from where it has already jumped.
private struct LayerReorderDrag {
    var rowID: String
    var startIndex: Int
    var didRecordUndo: Bool
}

/// Sharp opacity slider. The track and handle reuse the layer thumbnail boxes:
/// white rectangle, hairline stroke, with ink filling in from the left.
private struct LayerOpacityBar: View {
    /// Ink painted over the track. At 100% this is the dark gray line in the panel.
    static let inkOpacity: CGFloat = 0.78
    static let lineColor = Color.primary.opacity(inkOpacity)

    /// Opaque color of that line, so a grip on the dark panel matches it instead of
    /// blending a translucent black into the panel and staying light.
    static func gripUIColor(compatibleWith traits: UITraitCollection) -> UIColor {
        let track = UIColor.systemBackground.resolvedColor(with: traits)
        let ink = UIColor.label.resolvedColor(with: traits).withAlphaComponent(inkOpacity)
        var trackRed: CGFloat = 0, trackGreen: CGFloat = 0, trackBlue: CGFloat = 0, trackAlpha: CGFloat = 0
        var inkRed: CGFloat = 0, inkGreen: CGFloat = 0, inkBlue: CGFloat = 0, inkAlpha: CGFloat = 0
        track.getRed(&trackRed, green: &trackGreen, blue: &trackBlue, alpha: &trackAlpha)
        ink.getRed(&inkRed, green: &inkGreen, blue: &inkBlue, alpha: &inkAlpha)
        let alpha = inkAlpha
        return UIColor(
            red: inkRed * alpha + trackRed * (1 - alpha),
            green: inkGreen * alpha + trackGreen * (1 - alpha),
            blue: inkBlue * alpha + trackBlue * (1 - alpha),
            alpha: 1
        )
    }

    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void

    private let slotHeight: CGFloat = 2
    private let thumbWidth: CGFloat = 8
    private let thumbHeight: CGFloat = 14
    private let controlHeight: CGFloat = 22

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, thumbWidth)
            let travel = max(1, width - thumbWidth)
            let origin = CGFloat(value) * travel
            let midY = geometry.size.height / 2

            ZStack {
                Rectangle()
                    .fill(Color(.systemBackground))
                    .frame(width: width, height: slotHeight)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Self.lineColor)
                            .frame(width: max(0, origin), height: slotHeight)
                    }
                    .clipped()
                    .overlay {
                        Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    }
                    .position(x: width / 2, y: midY)

                Rectangle()
                    .fill(Color(.systemBackground))
                    .overlay {
                        Rectangle().stroke(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                    .frame(width: thumbWidth, height: thumbHeight)
                    .position(x: origin + thumbWidth / 2, y: midY)
            }
            .contentShape(Rectangle())
            .gesture(drag(travel: travel))
        }
        .frame(height: controlHeight)
        .transaction { $0.animation = nil }
        .accessibilityElement()
        .accessibilityLabel("Layer opacity")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: 0.05)
            case .decrement: step(by: -0.05)
            @unknown default: break
            }
        }
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
                    isDragging = true
                    onEditingChanged(true)
                }
                let next = fraction(at: gesture.location.x, travel: travel)
                if abs(next - value) > 0.001 {
                    value = next
                }
            }
            .onEnded { _ in
                guard isDragging else { return }
                isDragging = false
                onEditingChanged(false)
            }
    }

    private func step(by delta: Double) {
        let next = min(1, max(0, ((value + delta) * 100).rounded() / 100))
        guard abs(next - value) > 0.001 else { return }
        onEditingChanged(true)
        value = next
        onEditingChanged(false)
    }

    private func fraction(at x: CGFloat, travel: CGFloat) -> Double {
        let raw = Double((x - thumbWidth / 2) / travel)
        let clamped = min(1, max(0, raw))
        return (clamped * 100).rounded() / 100
    }
}

/// Small preview of a single layer's content, zoomed to fit that layer's
/// drawing. This is a passive preview of what was drawn: it deliberately does
/// not track in-progress canvas work. Regeneration waits for edits to settle,
/// so a drag that bumps `geometryRevision` every frame does no work at all.
private struct LayerThumbnailView: View {
    let document: KoalaDocument
    let layerID: UUID

    @Environment(\.colorScheme) private var colorScheme

    @State private var image: UIImage?

    private let thumbnailSize = CGSize(width: 38, height: 30)
    /// Matches the trailing-debounce interval used for canvas layout metrics.
    private let settleDelay = Duration.milliseconds(80)

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
        .task(id: RenderKey(revision: document.geometryRevision, isDark: colorScheme == .dark)) {
            // Continuous edits restart this task before the delay elapses, so a
            // drag renders nothing until it settles. The first paint skips the
            // delay so opening the panel stays snappy on a cold cache.
            if image != nil {
                try? await Task.sleep(for: settleDelay)
                guard !Task.isCancelled else { return }
            }
            image = LayerThumbnailCache.shared.image(
                document: document,
                layerID: layerID,
                size: thumbnailSize,
                isDark: colorScheme == .dark
            )
        }
    }

    /// Both inputs the cached image depends on. Appearance is included because
    /// the renderer bakes dynamic colors against the trait collection.
    private struct RenderKey: Equatable {
        var revision: Int
        var isDark: Bool
    }
}
