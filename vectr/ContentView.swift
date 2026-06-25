//
//  ContentView.swift
//  vectr
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            ProjectGalleryView()
        } else {
            PlatformPlaceholderView()
        }
        #else
        PlatformPlaceholderView()
        #endif
    }
}

#Preview {
    ContentView()
}
