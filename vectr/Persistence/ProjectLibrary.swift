//
//  ProjectLibrary.swift
//  vectr
//

import Foundation
import Observation

@Observable
final class ProjectLibrary {
    private(set) var projects: [ProjectRecord] = []

    private let fileManager = FileManager.default
    private let indexFileName = "projects-index.json"

    var projectsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Projects", isDirectory: true)
    }

    var thumbnailsDirectory: URL {
        projectsDirectory.appendingPathComponent(".thumbnails", isDirectory: true)
    }

    private var indexURL: URL {
        projectsDirectory.appendingPathComponent(indexFileName)
    }

    init() {
        ensureDirectories()
        loadIndex()
        if projects.isEmpty {
            scanFilesystem()
        }
    }

    func refresh() {
        scanFilesystem()
    }

    @discardableResult
    func createProject(
        name: String = "Untitled Artwork",
        canvasSize: CGSize? = nil,
        units: MeasurementUnit = .inches
    ) throws -> ProjectRecord {
        ensureDirectories()
        let id = UUID()
        let sanitized = sanitizedName(name)
        let fileName = uniqueFileName(base: sanitized, extension: DocumentCodec.fileExtension)
        let fileURL = projectsDirectory.appendingPathComponent(fileName)
        let document = VectrDocument()
        document.applyNewProjectDefaults(canvasSize: canvasSize, units: units)
        try DocumentCodec.write(document, to: fileURL)
        let record = makeRecord(id: id, name: name, fileURL: fileURL, document: document)
        try writeThumbnail(for: record, document: document)
        projects.insert(record, at: 0)
        saveIndex()
        return record
    }

    func duplicateProject(id: UUID) throws -> ProjectRecord {
        guard let source = projects.first(where: { $0.id == id }) else {
            throw LibraryError.projectNotFound
        }
        let document = try DocumentCodec.read(from: source.fileURL)
        let copyName = uniqueCopyName(for: source.name)
        let fileName = uniqueFileName(base: sanitizedName(copyName), extension: DocumentCodec.fileExtension)
        let fileURL = projectsDirectory.appendingPathComponent(fileName)
        try DocumentCodec.write(document, to: fileURL)
        let record = makeRecord(id: UUID(), name: copyName, fileURL: fileURL, document: document)
        try writeThumbnail(for: record, document: document)
        projects.insert(record, at: 0)
        saveIndex()
        return record
    }

    func deleteProjects(ids: Set<UUID>) throws {
        for id in ids {
            guard let index = projects.firstIndex(where: { $0.id == id }) else { continue }
            let record = projects[index]
            try? fileManager.removeItem(at: record.fileURL)
            if let thumb = record.thumbnailURL {
                try? fileManager.removeItem(at: thumb)
            }
            projects.remove(at: index)
        }
        saveIndex()
    }

    func renameProject(id: UUID, name: String) throws {
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw LibraryError.projectNotFound
        }
        var record = projects[index]
        let newFileName = uniqueFileName(
            base: sanitizedName(name),
            extension: DocumentCodec.fileExtension,
            excluding: record.fileURL
        )
        let newURL = projectsDirectory.appendingPathComponent(newFileName)
        if newURL != record.fileURL {
            try fileManager.moveItem(at: record.fileURL, to: newURL)
            record.fileURL = newURL
        }
        record.name = name
        record.modifiedAt = Date()
        projects[index] = record
        saveIndex()
    }

    @discardableResult
    func renameProject(fileURL: URL, name: String) throws -> URL {
        guard let index = indexOfProject(at: fileURL) else {
            throw LibraryError.projectNotFound
        }
        let id = projects[index].id
        try renameProject(id: id, name: name)
        return projects.first(where: { $0.id == id })?.fileURL ?? fileURL
    }

    func updateAfterSave(
        document: VectrDocument,
        fileURL: URL,
        name: String,
        refreshThumbnail: Bool = true
    ) throws {
        let normalizedURL = fileURL.standardizedFileURL
        let modifiedAt = Date()
        if let index = indexOfProject(at: normalizedURL) {
            var record = projects[index]
            record.name = name
            record.modifiedAt = modifiedAt
            record.canvasWidth = document.settings.canvasWidth
            record.canvasHeight = document.settings.canvasHeight
            if refreshThumbnail || thumbnailFileMissing(for: record) {
                try writeThumbnail(for: record, document: document)
            }
            projects[index] = record
        } else {
            let record = makeRecord(id: UUID(), name: name, fileURL: fileURL, document: document, modifiedAt: modifiedAt)
            try writeThumbnail(for: record, document: document)
            projects.insert(record, at: 0)
        }
        saveIndex()
    }

    /// Rewrites the gallery PNG without persisting the `.vectr` file.
    func refreshThumbnail(document: VectrDocument, fileURL: URL) throws {
        let normalizedURL = fileURL.standardizedFileURL
        guard let index = indexOfProject(at: normalizedURL) else { return }
        var record = projects[index]
        try writeThumbnail(for: record, document: document)
        record.modifiedAt = Date()
        projects[index] = record
        saveIndex()
    }

    @discardableResult
    func importFile(from sourceURL: URL) throws -> ProjectRecord {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        return try ImportRouter.importIntoLibrary(sourceURL: sourceURL, library: self)
    }

    enum LibraryError: Error, LocalizedError {
        case projectNotFound

        var errorDescription: String? {
            switch self {
            case .projectNotFound: return "Project not found."
            }
        }
    }

    // MARK: - Internal helpers

    func registerImportedProject(name: String, fileURL: URL, document: VectrDocument) throws -> ProjectRecord {
        let record = makeRecord(id: UUID(), name: name, fileURL: fileURL, document: document)
        try writeThumbnail(for: record, document: document)
        projects.insert(record, at: 0)
        saveIndex()
        return record
    }

    func copyIntoLibrary(from sourceURL: URL, name: String) throws -> URL {
        ensureDirectories()
        let fileName = uniqueFileName(base: sanitizedName(name), extension: sourceURL.pathExtension)
        let dest = projectsDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: sourceURL, to: dest)
        return dest
    }

    // MARK: - Private

    private func indexOfProject(at fileURL: URL) -> Int? {
        let targetPath = fileURL.standardizedFileURL.path
        return projects.firstIndex { $0.fileURL.standardizedFileURL.path == targetPath }
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ProjectRecord].self, from: data) else { return }
        projects = decoded.filter { fileManager.fileExists(atPath: $0.fileURL.path) }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func scanFilesystem() {
        ensureDirectories()
        guard let files = try? fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var scanned: [ProjectRecord] = []
        for url in files where url.pathExtension == DocumentCodec.fileExtension {
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            if let existing = projects.first(where: { $0.fileURL == url }) {
                var record = existing
                record.modifiedAt = modDate
                scanned.append(record)
            } else if let document = try? DocumentCodec.read(from: url) {
                let record = makeRecord(
                    id: UUID(),
                    name: url.deletingPathExtension().lastPathComponent,
                    fileURL: url,
                    document: document,
                    modifiedAt: modDate
                )
                scanned.append(record)
            }
        }
        projects = scanned.sorted { $0.modifiedAt > $1.modifiedAt }
        saveIndex()
    }

    private func makeRecord(
        id: UUID,
        name: String,
        fileURL: URL,
        document: VectrDocument,
        modifiedAt: Date = Date()
    ) -> ProjectRecord {
        ProjectRecord(
            id: id,
            name: name,
            fileURL: fileURL,
            thumbnailURL: thumbnailURL(for: id),
            modifiedAt: modifiedAt,
            canvasWidth: document.settings.canvasWidth,
            canvasHeight: document.settings.canvasHeight
        )
    }

    private func thumbnailURL(for id: UUID) -> URL {
        thumbnailsDirectory.appendingPathComponent("\(id.uuidString).png")
    }

    private func writeThumbnail(for record: ProjectRecord, document: VectrDocument) throws {
        guard let url = record.thumbnailURL else { return }
        try ThumbnailRenderer.writeThumbnail(for: document, to: url)
    }

    private func thumbnailFileMissing(for record: ProjectRecord) -> Bool {
        guard let url = record.thumbnailURL else { return true }
        return !fileManager.fileExists(atPath: url.path)
    }

    private func sanitizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return trimmed.components(separatedBy: invalid).joined(separator: "-").isEmpty ? "Untitled" : trimmed
    }

    private func uniqueFileName(base: String, extension ext: String, excluding: URL? = nil) -> String {
        var candidate = "\(base).\(ext)"
        var counter = 1
        while fileManager.fileExists(atPath: projectsDirectory.appendingPathComponent(candidate).path),
              projectsDirectory.appendingPathComponent(candidate) != excluding {
            candidate = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    private func uniqueCopyName(for name: String) -> String {
        var candidate = "\(name) Copy"
        var counter = 2
        while projects.contains(where: { $0.name == candidate }) {
            candidate = "\(name) Copy \(counter)"
            counter += 1
        }
        return candidate
    }
}
