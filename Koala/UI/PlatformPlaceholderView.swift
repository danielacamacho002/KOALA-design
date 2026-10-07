//
//  PlatformPlaceholderView.swift
//  Koala
//

import SwiftUI

struct PlatformPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "KOALA for iPad",
            systemImage: "ipad.and.apple.pencil",
            description: Text("Open on iPad for the full drawing experience. Mac and visionOS support is coming soon.")
        )
    }
}
