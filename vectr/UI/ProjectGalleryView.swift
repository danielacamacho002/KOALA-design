//
//  ProjectGalleryView.swift
//  vectr
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProjectGalleryView: View {
    @State private var library = ProjectLibrary()
    @AppStorage("galleryViewMode") private var viewModeRaw = GalleryViewMode.grid.rawValue
    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showImportPicker = false
    @State private var showPhotoPicker = false
    @State private var showImportSourceSheet = false
    @State private var pendingFileImport = false
    @State private var pendingPhotoImport = false
    @State private var showNewCanvasSheet = false
    @State private var showExportSheet = false
    @State private var pendingShareAfterDismiss = false
    @State private var exportFormat: ExportFormat = .vectr
    @State private var exportQuality: ExportQuality = .medium
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var isExporting = false

    private let gridColumns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    private var toolbarColor: Color { Color(hex: AppearanceSettings.toolbarHex) }

    private var viewMode: GalleryViewMode {
        get { GalleryViewMode(rawValue: viewModeRaw) ?? .grid }
        nonmutating set { viewModeRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                if !isSelectionMode {
                    galleryTitle
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

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
                            Divider()
                                .overlay(Color.white.opacity(0.12))
                                .padding(.leading, 88)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .scrollContentBackground(.hidden)
            .background(toolbarColor)
            .foregroundStyle(.white)
            .navigationTitle(isSelectionMode ? "\(selectedIDs.count) Selected" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { galleryToolbar }
            .toolbarBackground(toolbarColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(.white)
            .navigationDestination(for: UUID.self) { projectID in
                if let record = library.projects.first(where: { $0.id == projectID }) {
                    EditorView(projectURL: record.fileURL, projectLibrary: library)
                }
            }
        }
        .background(toolbarColor.ignoresSafeArea())
        .preferredColorScheme(navigationPath.isEmpty ? .dark : nil)
        .task { await library.refresh() }
        .background {
            DocumentImportSheet(
                isPresented: $showImportPicker,
                contentTypes: ImportRouter.supportedTypes
            ) { url in
                handleImport(.success([url]))
            }
            PhotoLibraryImportSheet(isPresented: $showPhotoPicker) { result in
                switch result {
                case .success(let url):
                    handleImport(.success([url]))
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showImportSourceSheet, onDismiss: {
            if pendingFileImport {
                pendingFileImport = false
                showImportPicker = true
            } else if pendingPhotoImport {
                pendingPhotoImport = false
                showPhotoPicker = true
            }
        }) {
            ImportSourceSheet { source in
                switch source {
                case .files:
                    pendingFileImport = true
                case .photoLibrary:
                    pendingPhotoImport = true
                }
            }
        }
        .sheet(isPresented: $showNewCanvasSheet) {
            CanvasSizeSheet { size, units in
                createProject(canvasSize: size, units: units)
            }
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
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.28)
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Exporting…")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .ignoresSafeArea()
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

    private var galleryTitle: some View {
        Text("KOALA")
            .font(.custom("HelveticaNeue-Medium", size: 34))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("KOALA")
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
                Button { showImportSourceSheet = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Import")
                Button {
                    isSelectionMode = true
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                Button { showNewCanvasSheet = true } label: {
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

    private func createProject(canvasSize: CGSize? = nil, units: MeasurementUnit = .inches) {
        Task {
            do {
                let record = try await library.createProject(canvasSize: canvasSize, units: units)
                navigationPath.append(record.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func duplicateSelected() {
        guard let id = selectedIDs.first else { return }
        Task {
            do {
                _ = try await library.duplicateProject(id: id)
                isSelectionMode = false
                selectedIDs.removeAll()
            } catch {
                errorMessage = error.localizedDescription
            }
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
        Task { await exportSelected(record: record) }
    }

    private func exportSelected(record: ProjectRecord) async {
        isExporting = true
        defer { isExporting = false }
        do {
            let snapshot = try await PersistenceWorker.shared.readSnapshot(from: record.fileURL)
            if exportFormat == .jpeg {
                let prepared = try await PersistenceWorker.shared.prepareJPEGForSharing(
                    snapshot: snapshot,
                    named: record.name,
                    quality: exportQuality
                )
                guard let image = UIImage(data: prepared.jpegData) else {
                    throw JPEGExporter.ExportError.renderFailed
                }
                shareItems = [JPEGShareItem(image: image, fileURL: prepared.fileURL)]
            } else {
                let tempURL = try await PersistenceWorker.shared.temporaryExportURL(
                    snapshot: snapshot,
                    name: record.name,
                    format: exportFormat,
                    quality: exportQuality
                )
                shareItems = [tempURL]
            }
            showShareSheet = false
            try? await Task.sleep(for: .milliseconds(200))
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum GalleryViewMode: String {
    case grid, list
}
