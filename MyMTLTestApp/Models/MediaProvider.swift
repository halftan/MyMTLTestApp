//
//  MediaProvider.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/17.
//

import AVFoundation

enum ContentType: String, Identifiable, CaseIterable {
    var id: Self { self }
    
    case video_yuv420_sbs
    case video_srgb_sbs
    case image_sbs
    
    // not implemented yet
//    case video_yuv422_sbs
//    case video_yuv444_sbs
//    
//    case image_ou
//    case video_yuv420_ou
//    case video_srgb_ou
//    case video_yuv422_ou
//    case video_yuv444_ou

    static var defaultType: Self { .image_sbs }
}

protocol MediaProvider {
    var isVideo: Bool { get }
    var contentType: ContentType { get }
    var naturalSize: CGSize { get }
    var aspectRatio: CGFloat { get }
    var videoOutput: AVPlayerItemVideoOutput? { get }
    
    func cleanup()
}

protocol MediaPlaybackProvider: Observable {
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isEditingCurrentTime: Bool { get set }
    var isPlaying: Bool { get }
    
    nonisolated func seek(to: CMTime) async -> Bool
    func pause()
    func play()
    
    nonisolated func stop() async
}
