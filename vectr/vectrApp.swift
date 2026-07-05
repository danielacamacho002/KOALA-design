//
//  vectrApp.swift
//  vectr
//
//  Created by mylo on 5/28/26.
//

import SwiftUI

@main
struct vectrApp: App {
    init() {
        FontLibrary.shared.registerAllImportedFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
