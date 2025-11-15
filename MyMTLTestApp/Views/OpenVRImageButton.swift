//
//  OpenVRImageButton.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/13.
//

import SwiftUI
import UniformTypeIdentifiers

struct OpenVRImageButton: View {

    @State private var showFileImporter = false

    @Environment(AppModel.self) private var appModel
    @Environment(Settings.self) private var settings
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    func doOpenImmersiveSpace() async {
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.immersiveViewID) {
        case .opened:
            settings.paused = false
            break

        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }

    var body: some View {
        VStack {
            Button("Select file") {
                showFileImporter = true
            }
            .glassBackgroundEffect()
            .padding()

            Button {
                Task { @MainActor in
                    switch appModel.immersiveSpaceState {
                    case .open:
                        settings.paused = true
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                    case .closed:
                        await doOpenImmersiveSpace()
                    case .inTransition:
                        // This case should not ever happen because button is disabled for this case.
                        break
                    }
                }
            } label: {
                Text(
                    appModel.immersiveSpaceState == .open
                        ? "Hide Immersive Space" : "Show Immersive Space"
                )
            }
            .disabled(appModel.immersiveSpaceState == .inTransition)
            .animation(.none, value: 0)
            .fontWeight(.semibold)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .video, .movie]
        ) { result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)
            case .success(let url):
                Task {
                    do {
                        try await appModel.videoModel.load(url)
                        await doOpenImmersiveSpace()
                    } catch (let error) {
                        fatalError(error.localizedDescription)
                    }
                }
            }
        }
    }
}
