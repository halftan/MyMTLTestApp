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

