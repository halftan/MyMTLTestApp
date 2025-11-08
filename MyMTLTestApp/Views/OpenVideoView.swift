//
//  OpenVideoView.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/8.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct OpenVideoView: View {
    @State private var isFileImporterPresent = false
    @State private var selectedItem: PhotosPickerItem?
    @Environment(\.openWindow) private var openWindow
    
    let video: VideoModel

    var body: some View {
        HStack {
            Button("Open video") {
                isFileImporterPresent = true
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
                            try await video.load(url)
                            openWindow(id: "player")
                        } catch (let error) {
                            print(error)
                        }
                    }
                }
            }
            Button("Open from Photos") {
            }
            .overlay() {
                PhotosPicker(selection: $selectedItem) {
                    Text("Select video")
                }
            }
        }
    }
}
