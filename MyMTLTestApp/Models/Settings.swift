//
//  Settings.swift
//  MyMTLTestApp
//
//  Created by 张凤鸣 on 2025/11/13.
//

import Foundation

@Observable
class Settings {
    var translateX: Float = 0
    var translateY: Float = 0
    var translateZ: Float = 0

    func resetTranslations() {
        translateX = 0.0
        translateY = 0.0
        translateZ = 0.0
    }

    enum StereoType: String, CaseIterable, Identifiable {
        var id: Self { self }

        case mono
        case stereo

        static var defaultType: Self { .stereo }
    }

    var stereoType: StereoType = .defaultType

    var stereoOn: Bool = true
}
