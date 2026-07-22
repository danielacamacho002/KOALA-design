//
//  ShareSheet.swift
//  vectr
//

import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Presents a system share sheet from a hosting view controller.
/// Prefer this over embedding `UIActivityViewController` in a SwiftUI `.sheet`,
/// which often appears blank on iPad.
struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var items: [Any]
    var onComplete: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented {
            guard !context.coordinator.isPresenting else { return }
            guard !items.isEmpty else { return }

            context.coordinator.isPresenting = true
            let items = self.items
            let onComplete = self.onComplete

            DispatchQueue.main.async {
                let presenter = Self.presentationAnchor(from: uiViewController)
                // Wait out any just-dismissed sheet before presenting.
                if presenter.presentedViewController != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.presentActivity(
                            from: Self.presentationAnchor(from: uiViewController),
                            items: items,
                            context: context,
                            onComplete: onComplete
                        )
                    }
                    return
                }
                self.presentActivity(
                    from: presenter,
                    items: items,
                    context: context,
                    onComplete: onComplete
                )
            }
        } else {
            context.coordinator.isPresenting = false
        }
    }

    private func presentActivity(
        from presenter: UIViewController,
        items: [Any],
        context: Context,
        onComplete: (() -> Void)?
    ) {
        guard presenter.presentedViewController == nil else {
            context.coordinator.isPresenting = false
            isPresented = false
            return
        }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.isPresenting = false
            isPresented = false
            onComplete?()
        }
        if let popover = activity.popoverPresentationController,
           let view = presenter.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    private static func presentationAnchor(from controller: UIViewController) -> UIViewController {
        if controller.viewIfLoaded?.window != nil {
            return topMost(from: controller)
        }
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        if let root = window?.rootViewController {
            return topMost(from: root)
        }
        return controller
    }

    private static func topMost(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = controller as? UINavigationController, let visible = nav.visibleViewController {
            return topMost(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return topMost(from: selected)
        }
        return controller
    }

    final class Coordinator {
        var isPresenting = false
    }
}

/// Shares a JPEG as a real image so the sheet offers Save Image / Photos,
/// while still handing a named `.jpg` file to AirDrop and Save to Files.
final class JPEGShareItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let fileURL: URL
    let title: String

    init(image: UIImage, fileURL: URL) {
        self.image = image
        self.fileURL = fileURL
        self.title = fileURL.deletingPathExtension().lastPathComponent
        super.init()
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        // Must be UIImage so the sheet classifies this as an image activity.
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        // Critical: when activityType is nil the system is probing available
        // activities. Returning a file URL here hides Save Image.
        guard let activityType else { return image }

        if activityType == .airDrop || Self.isSaveToFiles(activityType) {
            return fileURL
        }
        return image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.jpeg.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        thumbnailImageForActivityType activityType: UIActivity.ActivityType?,
        suggestedSize size: CGSize
    ) -> UIImage? {
        image
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = fileURL
        metadata.url = fileURL
        metadata.imageProvider = NSItemProvider(object: image)
        metadata.iconProvider = NSItemProvider(object: image)
        return metadata
    }

    private static func isSaveToFiles(_ activityType: UIActivity.ActivityType) -> Bool {
        activityType.rawValue == "com.apple.DocumentManagerUICore.SaveToFiles"
    }
}
