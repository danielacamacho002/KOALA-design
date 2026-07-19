//
//  ShareSheet.swift
//  vectr
//

import SwiftUI
import UIKit

/// Presents a system share sheet from a hosting view controller.
/// Prefer this over embedding `UIActivityViewController` in a SwiftUI `.sheet`,
/// which often appears blank on iPad.
struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented {
            guard uiViewController.presentedViewController == nil else { return }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
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
                uiViewController.present(activity, animated: true)
            }
        } else if let presented = uiViewController.presentedViewController {
            presented.dismiss(animated: true)
        }
    }
}
