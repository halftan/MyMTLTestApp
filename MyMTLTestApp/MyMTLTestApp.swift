//
//  MyMTLTestApp.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/7.
//

import SwiftUI

@main
struct MyMTLTestApp: App {
//    @State private var videoModel: VideoModel
//    @State private var renderer: Metal4Renderer
    
//    init() {
//        let videoModel = VideoModel()
//        self.videoModel = videoModel
//        self.renderer = Metal4Renderer(video: videoModel)
//    }
    
    @Environment(\.openWindow) private var openWindow
    @State private var video = VideoModel()
    
    var body: some Scene {
        WindowGroup("Main Window", id: "main") {
//            MetalView(delegate: self.renderer)
            OpenVideoView(video: video)
                .frame(width: 200, height: 100, alignment: .center)
                .padding()
                .onDisappear() {
                    print("Disappear")
                }
        }
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
#endif
        .defaultSize(width: 400, height: 200)
        .windowResizability(.contentSize)
        
        WindowGroup("Player", id: "player") {
            PlayerView(video: video)
                .onDisappear() {
                    video.cleanup()
                }
                .aspectRatio(video.naturalSize, contentMode: .fit)
        }
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
#endif
        .windowResizability(.contentSize)
    }
}
