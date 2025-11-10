//
//  ContentView.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/8.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    @State private var isFileImporterPresent = false
    @State private var showPlayer = false
    @State private var videoModel: VideoModel
    @State private var renderer: Metal4Renderer
    
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    
    init() {
        let videoModel = VideoModel()
        self.videoModel = videoModel
        self.renderer = Metal4Renderer(video: videoModel)
    }

    var body: some View {
        ZStack {
            if showPlayer && videoModel.url != nil {
//                PlayerView(video: videoModel)
//                    .ignoresSafeArea()
//                    .frame(minWidth: 200)
//                    .toolbar {
//                        ToolbarItem(placement: .primaryAction) {
//                            Button("Close") {
//                                showPlayer = false
//                                videoModel.cleanup()
//                            }
//                        }
//                    }
                MetalView(delegate: renderer)
                    .ignoresSafeArea()
                    .frame(minWidth: 400, minHeight: 400 / videoModel.aspectRatio)
                    .aspectRatio(videoModel.aspectRatio, contentMode: .fit)
                VStack {
                    Spacer()
                    HStack {
                        Button("", systemImage: "stop") {
                            showPlayer = false
                            videoModel.cleanup()
                        }
                        Button("", systemImage: "play") {
                            videoModel.player.play()
                        }
                        Button("", systemImage: "pause") {
                            videoModel.player.pause()
                        }
                    }
                    .backgroundStyle(.thinMaterial)
                    .padding(.bottom, 5)
                }
            } else {
                VStack(spacing: 20) {
                    Text("MyMTLTestApp")
                        .font(.title)
                        .padding(.bottom, 20)
                    
                    Button("Select a video file to play") {
                        isFileImporterPresent = true
                    }
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    #if os(macOS)
                        .glassEffect()
                    #elseif os(visionOS)
                        .glassBackgroundEffect()
                    #endif
                    
                    #if os(visionOS)
                    Button("Open VR Player in RealityView") {
                        openWindow(id: appModel.realityWindowID)
                    }
                    .font(.body)
                    #endif
                }
                .padding(.all, 20)
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresent,
            allowedContentTypes: [.movie, .video]
        ) { result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)
            case .success(let url):
                Task {
                    do {
                        try await videoModel.load(url)
                        let transferFunction = videoModel.transferFunction
                        if transferFunction == "" {
                            print("Video transfer function not set!")
                            return
                        }
                        await renderer.prepareRender(for: transferFunction)
                        withAnimation(.easeInOut(duration: 1)) {
                            
                            showPlayer = true
                        }
                    } catch (let error) {
                        print(error)
                    }
                }
            }
        }
        .onChange(of: videoModel.url) { oldUrl, newUrl in
            if newUrl != nil {
                showPlayer = true
            }
        }
    }
}
