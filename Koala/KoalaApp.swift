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
        FontLibrary.prepareAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
