//
//  ShareSheet.swift
//  vectr
//

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
            guard uiViewController.presentedViewController == nil else { return }
            guard !items.isEmpty else { return }

            context.coordinator.isPresenting = true
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                context.coordinator.isPresenting = false
                isPresented = false
                onComplete?()
            }
            if let popover = activity.popoverPresentationController,
               let view = uiViewController.view {
                popover.sourceView = view
                popover.sourceRect = CGRect(
                    x: view.bounds.midX,
                    y: view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }

            DispatchQueue.main.async {
                let presenter = Self.presentationAnchor(from: uiViewController)
                guard presenter.presentedViewController == nil else {
                    context.coordinator.isPresenting = false
                    return
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
        } else {
            context.coordinator.isPresenting = false
            if let presented = uiViewController.presentedViewController {
                presented.dismiss(animated: true)
            }
        }
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

/// Shares a JPEG so the system offers image actions (Save Image) while still
/// providing a named `.jpg` file for AirDrop / Files.
final class JPEGShareItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let fileURL: URL

    init(image: UIImage, fileURL: URL) {
        self.image = image
        self.fileURL = fileURL
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        switch activityType {
        case .saveToCameraRoll, .message, .mail, .postToFacebook, .postToTwitter, .copyToPasteboard:
            return image
        default:
            return fileURL
        }
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
        fileURL.deletingPathExtension().lastPathComponent
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        thumbnailImageForActivityType activityType: UIActivity.ActivityType?,
        suggestedSize size: CGSize
    ) -> UIImage? {
        image
    }
}
