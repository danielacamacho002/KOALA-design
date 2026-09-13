//
//  FontLibrary.swift
//  vectr
//

import CoreText
import Foundation
import Observation

/// A user-imported font, stored on disk under Documents/Fonts.
struct ImportedFont: Identifiable, Equatable {
    var id: String { postScriptName }
    let displayName: String
    let postScriptName: String
    let fileName: String

    var fontRef: FontRef {
        .imported(postScriptName: postScriptName, fileName: fileName)
    }
}

/// Manages the built-in font catalog and user-imported fonts. Imported fonts
/// are copied into Documents/Fonts (Files-app visible) and registered with the
/// Core Text font manager so they resolve for the current process.
@Observable
final class FontLibrary {
    static let shared = FontLibrary()

    /// Vector outline font formats we accept ("fonts must be in vector formats").
    static let allowedExtensions: Set<String> = ["ttf", "otf", "ttc"]

    let builtInFonts: [BuiltInFont] = FontCatalog.builtIn
    private(set) var importedFonts: [ImportedFont] = []

    /// Scans Documents/Fonts and registers each file once for this process.
    /// Call from `vectrApp.init` so imported faces resolve before any document opens.
    static func prepareAtLaunch() {
        _ = shared
    }

    /// Font files in `directory` with an allowed vector-font extension.
    static func fontFiles(in directory: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return items.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
    }

    init() {
        loadImportedFonts()
    }

    /// Directory where imported fonts live. Created on first access.
    var fontsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Fonts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Imports a font file, copying it into the Fonts directory and registering it.
    @discardableResult
    func importFont(from sourceURL: URL) throws -> ImportedFont {
        let ext = sourceURL.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            throw FontImportError.unsupportedFormat
        }

        let needsScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let destinationURL = uniqueDestinationURL(for: sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        guard let names = fontNames(at: destinationURL) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw FontImportError.unreadableFont
        }

        guard register(url: destinationURL) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw FontImportError.registrationFailed
        }

        let imported = ImportedFont(
            displayName: names.display,
            postScriptName: names.postScript,
            fileName: destinationURL.lastPathComponent
        )
        if let existing = importedFonts.firstIndex(where: { $0.postScriptName == imported.postScriptName }) {
            importedFonts[existing] = imported
        } else {
            importedFonts.append(imported)
        }
        importedFonts.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return imported
    }

    // MARK: - Private

    private func loadImportedFonts() {
        var fonts: [ImportedFont] = []
        for url in Self.fontFiles(in: fontsDirectory) {
            register(url: url)
            if let names = fontNames(at: url) {
                fonts.append(
                    ImportedFont(
                        displayName: names.display,
                        postScriptName: names.postScript,
                        fileName: url.lastPathComponent
                    )
                )
            }
        }
        importedFonts = fonts.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func uniqueDestinationURL(for fileName: String) -> URL {
        let directory = fontsDirectory
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        var candidate = fileName
        var counter = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(counter).\(ext)"
            counter += 1
        }
        return directory.appendingPathComponent(candidate)
    }

    private func fontNames(at url: URL) -> (postScript: String, display: String)? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return nil
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
        let postScript = CTFontCopyPostScriptName(font) as String
        let display = (CTFontCopyName(font, kCTFontFullNameKey) as String?)
            ?? (CTFontCopyFamilyName(font) as String?)
            ?? postScript
        return (postScript, display)
    }

    @discardableResult
    private func register(url: URL) -> Bool {
        var cfError: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError)
        if success { return true }

        if let error = cfError?.takeRetainedValue() {
            // Treat an already-registered font as success.
            if CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue {
                return true
            }
        }
        return false
    }
}

enum FontImportError: LocalizedError, Equatable {
    case unsupportedFormat
    case unreadableFont
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Fonts must be in a vector format (.ttf, .otf, or .ttc)."
        case .unreadableFont:
            return "This font file could not be read."
        case .registrationFailed:
            return "This font could not be installed."
        }
    }
}
