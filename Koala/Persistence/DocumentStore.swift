//
//  DocumentStore.swift
//  Koala
//

import Foundation
import Observation

@Observable
final class DocumentStore {
    var document: KoalaDocument
    var fileURL: URL?
    var fileName: String = "Untitled Artwork"
    var hasUnsavedChanges = false
    var needsInitialViewportLayout = false
    /// Incremented when persisted content changes. Not a canvas refresh signal.
    var contentRevision = 0

    /// Writes the current document. The editor assigns this so auto-save can
    /// persist without observing `contentRevision` in a large SwiftUI body.
    @ObservationIgnored
    var persistDocument: (() -> Void)?

    @ObservationIgnored
    private var autoSaveTask: Task<Void, Never>?

    init(document: KoalaDocument = KoalaDocument()) {
        self.document = document
        self.needsInitialViewportLayout = true
    }

    /// Marks the project unsaved and debounces auto-save. Does not redraw the canvas.
    func markDirty() {
        hasUnsavedChanges = true
        contentRevision += 1
        scheduleAutoSave()
    }

    func cancelAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    /// Cancels the debounce timer and writes immediately if there are unsaved changes.
    func flushAutoSave() {
        cancelAutoSave()
        guard hasUnsavedChanges else { return }
        persistDocument?()
    }

    func newDocument() {
        cancelAutoSave()
        document = KoalaDocument()
        document.applyNewProjectDefaults()
        fileURL = nil
        fileName = "Untitled Artwork"
        hasUnsavedChanges = false
        needsInitialViewportLayout = true
    }

    func load(from url: URL) throws {
        cancelAutoSave()
        applyLoadedSnapshot(try DocumentCodec.readSnapshot(from: url), from: url)
    }

    func applyLoadedSnapshot(_ snapshot: DocumentSnapshot, from url: URL) {
        document = KoalaDocument(snapshot: snapshot)
        fileURL = url
        fileName = url.deletingPathExtension().lastPathComponent
        hasUnsavedChanges = false
        // Always re-center on the grid origin when opening, ignoring the viewport saved in the file.
        needsInitialViewportLayout = true
        if document.simplifyStoredDenseAnchors() {
            markDirty()
        }
    }

    func save(to url: URL? = nil) throws {
        cancelAutoSave()
        let destination = url ?? fileURL
        guard let destination else { return }
        try DocumentCodec.write(document.makeSnapshot(), to: destination)
        fileURL = destination
        hasUnsavedChanges = false
    }

    /// Clears dirty only when no edits landed after `revision` was snapshotted.
    func markSaved(forRevision revision: Int) {
        guard SaveRevisionPolicy.shouldClearDirty(
            savedRevision: revision,
            currentRevision: contentRevision
        ) else { return }
        hasUnsavedChanges = false
    }

    deinit {
        autoSaveTask?.cancel()
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard hasUnsavedChanges else { return }
            persistDocument?()
        }
    }
}

enum SaveRevisionPolicy {
    static func shouldClearDirty(savedRevision: Int, currentRevision: Int) -> Bool {
        savedRevision == currentRevision
    }
}

enum GalleryThumbnailPolicy {
    /// Quiet autosaves keep an existing gallery PNG. Rewrite it on explicit
    /// save / leave / background, or when the thumbnail file is missing.
    static func shouldWriteThumbnail(refreshRequested: Bool, thumbnailExists: Bool) -> Bool {
        refreshRequested || !thumbnailExists
    }
}
