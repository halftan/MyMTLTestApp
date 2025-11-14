//
//  VideoModel+Metal.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/8.
//

import Metal
import QuartzCore
import AVFoundation
import CoreImage
import SwiftUI

extension VideoModel {
    func makeVideoOutput() -> AVPlayerItemVideoOutput {
        let outputVideoSettings: [String : any Sendable] = [
            AVVideoAllowWideColorKey: true,
            AVVideoColorPropertiesKey: videoColorProperties,
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_64RGBAHalf)
        ]

        let videoPlayerItemOutput = AVPlayerItemVideoOutput(outputSettings: outputVideoSettings)
        return videoPlayerItemOutput
    }

    func prepareForRender() async throws {
        guard let playerItem = self.player?.currentItem else {
            throw VideoModelError.initializationFailed("trying to setup video output before playerItem is set")
        }
        self.videoOutput = makeVideoOutput()
        if self.videoOutput == nil{
            throw VideoModelError.initializationFailed("video output has not been initialized")
        }
        playerItem.add(self.videoOutput!)
//        #if os(visionOS)
//        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCopyPixelBuffers(link:)))
//        #elseif os(macOS)
//        displayLink = (NSApp.mainWindow?.displayLink(target: self, selector: #selector(displayLinkCopyPixelBuffers(link:))))!
//        #endif

//        self.statusObserver = playerItem.observe(\.status,
//                                                  options: [.new, .old, .initial],
//                                                  changeHandler: { [weak self] playerItem, change in
//            Task { @MainActor in
//                guard let self = self else { return }
////                guard let displayLink = self.displayLink else { return }
//                if playerItem.status == .readyToPlay {
//                    print("Set videoOutput: \(self.videoOutput?.debugDescription ?? "None")")
//                    playerItem.add(self.videoOutput!)
////                    displayLink.add(to: .main, forMode: .common)
//                }
//            }
//        })
    }

//    func extractFrame(with mtlTextureCache: CVMetalTextureCache) -> (any MTLTexture)? {
//        guard let videoOutput = videoOutput else {
//            print("video output not set!")
//            return nil
//        }
//        let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
//        if videoOutput.hasNewPixelBuffer(forItemTime: itemTime) {
//            if let buffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
//                let width = CVPixelBufferGetWidth(buffer)
//                let height = CVPixelBufferGetHeight(buffer)
//
//                var cvTexture: CVMetalTexture?
//                let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
//                                                          mtlTextureCache,
//                                                          buffer,
//                                                          nil,
//                                                          MTLPixelFormat.rgba16Float,
//                                                          width, height, 0,
//                                                          &cvTexture)
//                switch result {
//                case kCVReturnSuccess:
//                    break
//                default:
//                    print("Error when calling CVMetalTextureCacheCreateTextureFromImage: \(result)")
//                    return nil
//                }
//                return CVMetalTextureGetTexture(cvTexture!)
//            }
//        }
//        return nil
//    }

//    @objc
//    func displayLinkCopyPixelBuffers(link: CADisplayLink) {
//        guard let videoOutput = videoOutput else {
//            print("video output not set!")
//            return
//        }
//        let currentTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
//        if videoOutput.hasNewPixelBuffer(forItemTime: currentTime) {
//            if let buffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
//                let width = CVPixelBufferGetWidth(buffer)
//                let height = CVPixelBufferGetHeight(buffer)
//
//                var cvTexture: CVMetalTexture?
//                let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
//                                                          self.mtlTextureCache!,
//                                                          buffer,
//                                                          nil,
//                                                          MTLPixelFormat.rgba16Float,
//                                                          width, height, 0,
//                                                          &cvTexture)
//                var texture = CVMetalTextureGetTexture(cvTexture!)
//                let image = CIImage(cvPixelBuffer: buffer)
//            }
//        }
//    }
}

