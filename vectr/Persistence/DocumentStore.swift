//
//  DocumentStore.swift
//  vectr
//

import Foundation
import Observation

@Observable
final class DocumentStore {
    var document: VectrDocument
    var fileURL: URL?
    var fileName: String = "Untitled Artwork"
    var hasUnsavedChanges = false
    var needsInitialViewportLayout = false
    /// Incremented when document content changes so views observing the store refresh reliably.
    var contentRevision = 0

    init(document: VectrDocument = VectrDocument()) {
        self.document = document
        self.needsInitialViewportLayout = true
    }

    func markDirty() {
        hasUnsavedChanges = true
        contentRevision += 1
    }

    func newDocument() {
        document = VectrDocument()
        document.applyNewProjectDefaults()
        fileURL = nil
        fileName = "Untitled Artwork"
        hasUnsavedChanges = false
        needsInitialViewportLayout = true
    }

    func load(from url: URL) throws {
        applyLoadedSnapshot(try DocumentCodec.readSnapshot(from: url), from: url)
    }

    func applyLoadedSnapshot(_ snapshot: DocumentSnapshot, from url: URL) {
        document = VectrDocument(snapshot: snapshot)
        fileURL = url
        fileName = url.deletingPathExtension().lastPathComponent
        hasUnsavedChanges = false
        // Always re-center on the grid origin when opening, ignoring the viewport saved in the file.
        needsInitialViewportLayout = true
    }

    func save(to url: URL? = nil) throws {
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
}

enum SaveRevisionPolicy {
    static func shouldClearDirty(savedRevision: Int, currentRevision: Int) -> Bool {
        savedRevision == currentRevision
    }
}
