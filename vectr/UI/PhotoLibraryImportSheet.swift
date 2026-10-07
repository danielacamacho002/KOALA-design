//
//  PhotoLibraryImportSheet.swift
//  vectr
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Presents the system photo picker and hands back a temporary copy of the
/// original image file. The photo library UI runs out of process, so this does
/// not need photo-library read permission.
struct PhotoLibraryImportSheet: View {
    @Binding var isPresented: Bool
    var onPick: (Result<URL, Error>) -> Void

    var body: some View {
        PhotoLibraryImportPresenter(isPresented: $isPresented, onPick: onPick)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
    }
}

private struct PhotoLibraryImportPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (Result<URL, Error>) -> Void

    func makeUIViewController(context: Context) -> PhotoImportPresenterController {
        PhotoImportPresenterController()
    }

    func updateUIViewController(_ controller: PhotoImportPresenterController, context: Context) {
        controller.onPick = onPick
        controller.onFinished = { isPresented = false }
        controller.isPresented = isPresented
        controller.syncPresentation()
    }
}

private final class PhotoImportPresenterController: UIViewController, PHPickerViewControllerDelegate {
    var isPresented = false
    var onPick: (Result<URL, Error>) -> Void = { _ in }
    var onFinished: () -> Void = {}
    private weak var picker: PHPickerViewController?
    /// Set while a pick is being copied so a SwiftUI update cannot reopen the picker.
    private var isImporting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        syncPresentation()
    }

    func syncPresentation() {
        if !isPresented {
            isImporting = false
            return
        }
        guard !isImporting else { return }
        presentPickerIfNeeded()
    }

    private func presentPickerIfNeeded() {
        guard picker == nil, let host = presentationHost() else { return }
        guard host.presentedViewController == nil else { return }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        picker.modalPresentationStyle = .pageSheet
        self.picker = picker
        host.present(picker, animated: true)
    }

    private func presentationHost() -> UIViewController? {
        guard let root = view.window?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        self.picker = nil
        isImporting = true
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            onFinished()
            return
        }
        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
            if let url, let copy = Self.temporaryCopy(of: url, typeIdentifier: typeIdentifier) {
                self?.finish(.success(copy), deleteAfterPick: copy)
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, dataError in
                if let data, let copy = Self.temporaryFile(containing: data, typeIdentifier: typeIdentifier) {
                    self?.finish(.success(copy), deleteAfterPick: copy)
                } else {
                    self?.finish(.failure(dataError ?? error ?? PhotoLibraryImportError.unreadable), deleteAfterPick: nil)
                }
            }
        }
    }

    private func finish(_ result: Result<URL, Error>, deleteAfterPick url: URL?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onPick(result)
            if let url {
                try? FileManager.default.removeItem(at: url)
            }
            self.onFinished()
        }
    }

    private static func temporaryCopy(of url: URL, typeIdentifier: String) -> URL? {
        let destination = temporaryDestination(typeIdentifier: typeIdentifier, pathExtension: url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func temporaryFile(containing data: Data, typeIdentifier: String) -> URL? {
        let destination = temporaryDestination(typeIdentifier: typeIdentifier, pathExtension: "")
        do {
            try data.write(to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func temporaryDestination(typeIdentifier: String, pathExtension: String) -> URL {
        let ext = pathExtension.isEmpty
            ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "jpg")
            : pathExtension
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-\(UUID().uuidString).\(ext)")
    }
}

enum PhotoLibraryImportError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable: return "This photo couldn't be imported."
        }
    }
}
