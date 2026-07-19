//
//  ProjectGalleryView.swift
//  vectr
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectGalleryView: View {
    @State private var library = ProjectLibrary()
    @AppStorage("galleryViewMode") private var viewModeRaw = GalleryViewMode.grid.rawValue
    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showImportPicker = false
    @State private var showExportSheet = false
    @State private var pendingShareAfterDismiss = false
    @State private var exportFormat: ExportFormat = .vectr
    @State private var exportQuality: ExportQuality = .medium
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()

    private let gridColumns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    private var viewMode: GalleryViewMode {
        get { GalleryViewMode(rawValue: viewModeRaw) ?? .grid }
        nonmutating set { viewModeRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                if viewMode == .grid {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(library.projects) { project in
                            projectButton(project)
                        }
                    }
                    .padding(20)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(library.projects) { project in
                            projectButton(project)
                                .padding(.horizontal, 20)
                            Divider().padding(.leading, 88)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .background(Color(white: 0.16))
            .navigationTitle(isSelectionMode ? "\(selectedIDs.count) Selected" : "vectr")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { galleryToolbar }
            .navigationDestination(for: UUID.self) { projectID in
                if let record = library.projects.first(where: { $0.id == projectID }) {
                    EditorView(projectURL: record.fileURL, projectLibrary: library)
                }
            }
        }
        .onAppear { library.refresh() }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: ImportRouter.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showExportSheet, onDismiss: {
            guard pendingShareAfterDismiss else { return }
            pendingShareAfterDismiss = false
            presentShareExport()
        }) {
            ExportFormatSheet { format, quality in
                exportFormat = format
                exportQuality = quality
                pendingShareAfterDismiss = true
            }
        }
        .background {
            ShareSheetPresenter(isPresented: $showShareSheet, items: shareItems) {
                shareItems = []
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var galleryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelectionMode {
                Button("Cancel") {
                    isSelectionMode = false
                    selectedIDs.removeAll()
                }
            } else {
                Button {
                    viewMode = viewMode == .grid ? .list : .grid
                } label: {
                    Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSelectionMode {
                Button("Share") { showExportSheet = true }
                    .disabled(selectedIDs.isEmpty)
                Button("Duplicate") { duplicateSelected() }
                    .disabled(selectedIDs.count != 1)
                Button("Delete", role: .destructive) { deleteSelected() }
                    .disabled(selectedIDs.isEmpty)
            } else {
                Button { showImportPicker = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                Button {
                    isSelectionMode = true
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                Button { createProject() } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func projectButton(_ project: ProjectRecord) -> some View {
        Button {
            if isSelectionMode {
                toggleSelection(project.id)
            } else {
                navigationPath.append(project.id)
            }
        } label: {
            ProjectCardView(
                record: project,
                isSelected: selectedIDs.contains(project.id),
                isSelectionMode: isSelectionMode,
                compact: viewMode == .list
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func createProject() {
        do {
            let record = try library.createProject()
            navigationPath.append(record.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicateSelected() {
        guard let id = selectedIDs.first else { return }
        do {
            _ = try library.duplicateProject(id: id)
            isSelectionMode = false
            selectedIDs.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelected() {
        do {
            try library.deleteProjects(ids: selectedIDs)
            isSelectionMode = false
            selectedIDs.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let record = try library.importFile(from: url)
                navigationPath.append(record.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func presentShareExport() {
        guard let id = selectedIDs.first,
              let record = library.projects.first(where: { $0.id == id }) else { return }
        do {
            let document = try DocumentCodec.read(from: record.fileURL)
            let tempURL = try ExportRouter.temporaryExportURL(
                document: document,
                name: record.name,
                format: exportFormat,
                quality: exportQuality
            )
            shareItems = [tempURL]
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum GalleryViewMode: String {
    case grid, list
}

extension ImportRouter {
    static var supportedTypes: [UTType] {
        [.vectrDocument, .jpeg, .pdf, .svg, UTType(filenameExtension: "ai") ?? .pdf]
    }
}
