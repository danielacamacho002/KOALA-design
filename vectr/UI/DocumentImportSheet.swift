//
//  DocumentImportSheet.swift
//  vectr
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Presents the system file browser directly, so it keeps that browser's width,
/// with the same dark menu colors as Settings and Export.
struct DocumentImportSheet: View {
    @Binding var isPresented: Bool
    var contentTypes: [UTType]
    var onPick: (URL) -> Void

    var body: some View {
        DocumentImportPresenter(isPresented: $isPresented, contentTypes: contentTypes, onPick: onPick)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
    }
}

private struct DocumentImportPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var contentTypes: [UTType]
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> ImportPresenterController {
        ImportPresenterController()
    }

    func updateUIViewController(_ controller: ImportPresenterController, context: Context) {
        controller.contentTypes = contentTypes
        controller.onPick = onPick
        controller.onFinished = {
            isPresented = false
        }
        controller.isPresented = isPresented
        controller.syncPresentation()
    }
}

private final class ImportPresenterController: UIViewController, UIDocumentPickerDelegate {
    var isPresented = false
    var contentTypes: [UTType] = []
    var onPick: (URL) -> Void = { _ in }
    var onFinished: () -> Void = {}
    private weak var picker: StyledDocumentPicker?

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
        if isPresented {
            presentPickerIfNeeded()
        }
    }

    private func presentPickerIfNeeded() {
        guard picker == nil, let host = presentationHost() else { return }
        guard host.presentedViewController == nil else { return }
        let picker = StyledDocumentPicker(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        picker.modalPresentationStyle = .pageSheet
        self.picker = picker
        host.present(picker, animated: true)
    }

    /// Present from the full-screen controller. Presenting from this tiny anchor
    /// drops the canvas and leaves the window's black background behind the sheet.
    private func presentationHost() -> UIViewController? {
        guard let root = view.window?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        picker = nil
        if let url = urls.first {
            onPick(url)
        }
        onFinished()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        picker = nil
        onFinished()
    }
}

private final class StyledDocumentPicker: UIDocumentPickerViewController {
    private var pageColor: UIColor { UIColor(Color(hex: AppearanceSettings.pasteboardHex)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.tintColor = .secondaryLabel
        applyChrome()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyChrome()
    }

    private func applyChrome() {
        let page = pageColor
        view.backgroundColor = page
        if let sheet = sheetPresentationController {
            sheet.prefersPageSizing = true
            sheet.preferredCornerRadius = 0
        }
        presentationController?.containerView?.layer.cornerRadius = 0

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = page
        bar.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = bar
        navigationItem.scrollEdgeAppearance = bar
        navigationItem.compactAppearance = bar

        styleChrome(in: view, page: page)
    }

    private func styleChrome(in view: UIView, page: UIColor) {
        if let bar = view as? UINavigationBar {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = page
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.compactAppearance = appearance
            bar.tintColor = .secondaryLabel
        } else if view is UITableView || view is UICollectionView {
            view.backgroundColor = page
        }

        for subview in view.subviews {
            styleChrome(in: subview, page: page)
        }
    }
}
