//
//  MyMTLTestApp.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/7.
//

import SwiftUI

@main
struct MyMTLTestApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: appModel.mainWindowID) {
            ContentView()
                .environment(appModel)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        #endif
        .windowResizability(.contentSize)
        
        #if os(visionOS)
        WindowGroup(id: appModel.realityWindowID) {
            VRPlayerView()
        }
        .defaultSize(width: 0.8, height: 0.5, depth: 1.0, in: .meters)
        .windowStyle(.plain)
        #endif
    }
}
