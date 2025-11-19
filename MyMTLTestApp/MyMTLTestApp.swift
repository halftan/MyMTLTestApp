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
    @State private var settings = Settings()

    var body: some Scene {
        WindowGroup(id: appModel.mainWindowID) {
            ContentView()
                .environment(appModel)
                .environment(settings)
            
            #if os(visionOS)
            SettingsView()
                .environment(appModel)
                .environment(settings)
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        #endif
        .windowResizability(.contentSize)

        #if os(visionOS)
        WindowGroup(id: appModel.realityWindowID) {
            VRPlayerView()
                .ignoresSafeArea()
        }
        .defaultSize(width: 1.0, height: 1.0, depth: 1.0, in: .meters)
        .windowStyle(.plain)

        ImmersiveSpace(id: appModel.immersiveViewID) {
            ImmersiveVRView()
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
                .environment(appModel)
                .environment(settings)
        }
        .immersionStyle(selection: .constant(.full), in: .mixed, .full)
        .upperLimbVisibility(settings.showHandsInImmersiveView)
        #endif
    }
}
