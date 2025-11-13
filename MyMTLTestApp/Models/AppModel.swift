//
//  AppModel.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/8.
//

import SwiftUI
import UniformTypeIdentifiers

@Observable
class AppModel {
    let mainWindowID = "main"
    let realityWindowID = "RealityWindow"
    let immersiveViewID = "ImmersiveVRPlayerView"
    let contentWindowID = "ContentWindow"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    enum MainWindowState {
        case closed
        case inTransition
        case open
    }
    var mainWindowState = MainWindowState.open

    var videoModel = VideoModel()

    func cleanupVideoModel() {
        videoModel.cleanup()
    }
}
