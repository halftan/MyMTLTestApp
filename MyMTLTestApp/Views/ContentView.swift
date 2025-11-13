//
//  ContentView.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/8.
//

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isFileImporterPresent = false
    @State private var showPlayer = false
    // @State private var renderer: Metal4Renderer

    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    // init() {
    //     self.renderer = Metal4Renderer(video: videoModel)
    // }

    var body: some View {
        VStack {
            #if os(macOS)
            PlayPlainVideoButton()
            #endif

            #if os(visionOS)
//            Button("Open VR Player in RealityView") {
//                openWindow(id: appModel.realityWindowID)
//            }
//            .font(.body)
//            .padding(.horizontal)

            OpenVRImageButton()
                .padding(.horizontal)

            #endif
        }
        .onAppear {
            print("ContentView: appear")
            appModel.mainWindowState = .open
        }
        .onDisappear {
            print("ContentView: disappear")
            appModel.mainWindowState = .closed
        }
    }
}
