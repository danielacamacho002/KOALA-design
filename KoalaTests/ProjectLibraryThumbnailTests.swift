import Foundation
import Testing
@testable import Koala

@MainActor
struct ProjectLibraryThumbnailTests {
    @Test func movedContainerKeepsProjectIDsAndThumbnails() async throws {
        let oldRoot = try makeRoot()
        let newRoot = try makeRoot()
        defer {
            try? FileManager.default.removeItem(at: oldRoot)
            try? FileManager.default.removeItem(at: newRoot)
        }

        let original = try await ProjectLibrary(rootDirectory: oldRoot).createProject(name: "Drawing")
        try FileManager.default.moveItem(
            at: oldRoot.appendingPathComponent("Projects"),
            to: newRoot.appendingPathComponent("Projects")
        )

        let library = ProjectLibrary(rootDirectory: newRoot)
        await library.refresh()

        let record = try #require(library.projects.first)
        #expect(library.projects.count == 1)
        #expect(record.id == original.id)
        #expect(record.fileURL.path.hasPrefix(newRoot.path))
        let thumbnail = try #require(record.thumbnailURL)
        #expect(thumbnail.path.hasPrefix(newRoot.path))
        #expect(FileManager.default.fileExists(atPath: thumbnail.path))
    }

    @Test func refreshRewritesMissingThumbnail() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let library = ProjectLibrary(rootDirectory: root)
        let record = try await library.createProject(name: "Drawing")
        let thumbnail = try #require(record.thumbnailURL)
        try FileManager.default.removeItem(at: thumbnail)
        let revision = library.thumbnailRevision

        await library.refresh()

        #expect(FileManager.default.fileExists(atPath: thumbnail.path))
        #expect(library.thumbnailRevision > revision)
    }

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectLibraryThumbnailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
