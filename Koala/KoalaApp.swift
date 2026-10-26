//
//  KoalaApp.swift
//  Koala
//
//  Created by mylo on 5/28/26.
//

import SwiftUI

@main
struct KoalaApp: App {
    init() {
        PencilTextEntry.install()
        FontLibrary.prepareAtLaunch()
        DisplayZoomCompensation.startIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background {
                    if DisplayZoomCompensation.liveFactor > 1.01 {
                        DisplayZoomInstaller()
                    }
                }
        }
    }
}
