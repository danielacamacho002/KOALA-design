import Foundation
import Testing
@testable import vectr

@MainActor
struct FontLibraryTests {
    @Test func fontFilesIncludesOnlyAllowedExtensions() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: directory.appendingPathComponent("A.ttf"))
        try Data().write(to: directory.appendingPathComponent("B.ttf"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))

        let names = Set(FontLibrary.fontFiles(in: directory).map(\.lastPathComponent))
        #expect(names == ["A.ttf", "B.ttf"])
    }

    @Test func fontFilesInEmptyDirectoryIsEmpty() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(FontLibrary.fontFiles(in: directory).isEmpty)
    }

    @Test func importFontRejectsUnsupportedFormat() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let txt = directory.appendingPathComponent("notes.txt")
        try Data().write(to: txt)

        #expect(throws: FontImportError.unsupportedFormat) {
            try FontLibrary().importFont(from: txt)
        }
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FontLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
