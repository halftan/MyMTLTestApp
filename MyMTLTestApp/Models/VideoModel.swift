//
//  VideoModel.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/7.
//

import AVKit
import Metal
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

extension CGFloat {
    static var defaultAspectRatio: Self {
        return 16.0 / 9.0
    }
}

@Observable
class VideoModel {
    var url: URL? {
        return _url
    }

    // Private backing storage for the url property
    private var _url: URL?

    private(set) var utType: UTType!
    private(set) var isVideo = true
    private(set) var contentType: ContentType = .defaultType
    private(set) var isPlaying: Bool = false

    // Observable time properties
    private(set) var currentTime: TimeInterval = 0.0
    private(set) var duration: TimeInterval = 0.0
    var isEditingCurrentTime: Bool = false

    // Video track properties
    @ObservationIgnored
    private(set) var naturalSize: CGSize = .zero

    private var asset: AVAsset?
    var assetIsHDR = false
    var assetPreferredTransform: CGAffineTransform = .identity
    var videoColorProperties: [String: any Sendable] = [:]
    var videoOutputSettings: AVQueuePlayerWithOutput.VideoOutputSettings = [:]

    var transferFunction: String {
        return videoColorProperties[AVVideoTransferFunctionKey] as? String ?? ""
    }

    var player: AVQueuePlayer?
    var playerItem: AVPlayerItem?
    var looper: AVPlayerLooper?

    private var timeObserver: Any?
    private var subscriptions: Set<AnyCancellable> = []
    var statusObserver: NSKeyValueObservation?
//    var videoOutput: AVPlayerItemVideoOutput?
    //    var displayLink: CADisplayLink?

    init() {
        print("Initializing video model")
    }

    @MainActor
    deinit {
        self.cleanup()
        print("VideoModel deinit: \(self)")
    }

    func load(_ url: URL) async throws {
        // Stop accessing the old URL's security scoped resource if it exists
        if let oldURL = _url {
            oldURL.stopAccessingSecurityScopedResource()
        }

        // Start accessing the new URL's security scoped resource
        let success = url.startAccessingSecurityScopedResource()
        guard success else {
            // Handle failure to access security scoped resource
            throw VideoModelError.securityScopedResourceAccessFailed(url)
        }

        _url = url

        let resourceValue = try url.resourceValues(forKeys: [.contentTypeKey])
        utType = resourceValue.contentType

        if utType.conforms(to: .movie) || utType.conforms(to: .video) {
            // video resource
            print("Resource is video")
            isVideo = true
            asset = AVURLAsset(url: url)

            try await parseVideoMetadata(asset: asset!)
            // Recreate asset to avoid side-affects caused by parsing metadata
            asset = AVURLAsset(url: url)

            // Set up the player item and time observer when loading a new asset
            playerItem = AVPlayerItem(asset: asset!)
            player = AVQueuePlayerWithOutput(videoOutputSettings: videoOutputSettings)
            player!.actionAtItemEnd = .advance
            looper = AVPlayerLooper(player: player!, templateItem: playerItem!)
            addObservers()
//            try await prepareForRender()
            player!.play()
            player!.replaceCurrentItem(with: playerItem)
        } else {
            isVideo = false
        }
        setContentType()
    }
    
    private func setContentType() {
        // TODO: actually load the media format
        if isVideo {
            contentType = .video_yuv420_sbs
        } else {
            contentType = .image_sbs
        }
    }

    func parseVideoMetadata(asset: AVAsset) async throws {
        let videoTracks = try await asset.loadTracks(withMediaCharacteristic: .visual)
        if videoTracks.isEmpty {
            print("No video track found in asset")
            return
        }

        let hdrTracks = try await asset.loadTracks(withMediaCharacteristic: .containsHDRVideo)
        self.assetIsHDR = !hdrTracks.isEmpty

        let firstTrack = videoTracks.first!
        let size = try await firstTrack.load(.naturalSize)
        self.naturalSize = size
        print("Loaded natural size: \(size)")
        self.duration = try await asset.load(.duration).seconds
        print("Loaded duration: \(self.duration)")

        self.assetPreferredTransform = try await firstTrack.load(.preferredTransform)

        videoColorProperties = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_Linear,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        videoColorProperties[AVVideoTransferFunctionKey] = AVVideoTransferFunction_Linear
        let formatDescriptions = try await firstTrack.load(.formatDescriptions)
        if let primaryFormatDescription = formatDescriptions.first {
            if let transferFunctionValue = primaryFormatDescription.extensions[.transferFunction] {
                print(
                    "Transfer function: \(transferFunctionValue) : plist: \(transferFunctionValue.propertyListRepresentation)"
                )
                let transferFunction = transferFunctionValue.propertyListRepresentation as! CFString
                if transferFunction
                    == CMFormatDescription.Extensions.Value.TransferFunction.itu_R_2020.rawValue
                {
                    // ITU_R_2020 requires special handling because there is no matching AVFoundation value for it.
                    // All of the other relevant transfer functions are spelled identically between CM and AV.
                    videoColorProperties[AVVideoTransferFunctionKey] =
                        AVVideoTransferFunction_ITU_R_709_2
                } else {
                    videoColorProperties[AVVideoTransferFunctionKey] = transferFunction as String
                }
                print(
                    "Selected output transfer function: \(String(describing: videoColorProperties[AVVideoTransferFunctionKey]))"
                )
            }
            if let videoColorPrimaries = primaryFormatDescription.extensions[.colorPrimaries] {
                print("Color primaries: \(videoColorPrimaries.propertyListRepresentation)")
                videoColorProperties[AVVideoColorPrimariesKey] =
                    videoColorPrimaries.propertyListRepresentation as! String

            }
            if let videoYCbCrMatrix = primaryFormatDescription.extensions[.yCbCrMatrix] {
                print("YCbCrMatrix: \(videoYCbCrMatrix.propertyListRepresentation)")
                videoColorProperties[AVVideoYCbCrMatrixKey] =
                    videoYCbCrMatrix.propertyListRepresentation as! String
            }
        }
        if formatDescriptions.count > 1 {
            print("Not handling multiple video format descriptions")
        }
        
        videoOutputSettings = [
            // disable wide color support for vision os
//            AVVideoAllowWideColorKey: true,
            AVVideoColorPropertiesKey: videoColorProperties,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
            //            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_64RGBAHalf),
            //            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8PlanarFullRange,
        ]
    }

    private func addObservers() {
        player!.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                switch status {
                case .playing:
                    self?.isPlaying = true
                case .paused:
                    self?.isPlaying = false
                case .waitingToPlayAtSpecifiedRate:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &subscriptions)
        
        let interval = CMTime(value: 1, timescale: 10)
        self.timeObserver = self.player!.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else {
                print("timeObserver invalidated, self is nil")
                return
            }
            Task { @MainActor in
                // Update the observable properties on the main actor
                if !self.isEditingCurrentTime {
                    self.currentTime = time.seconds
                }
            }
        }
    }
    
//    func prepareForRender() async throws {
//        guard let playerItem = self.playerItem else {
//            throw VideoModelError.initializationFailed("trying to setup video output before playerItem is set")
//        }
//        self.videoOutput = makeVideoOutput()
//        if self.videoOutput == nil{
//            throw VideoModelError.initializationFailed("video output has not been initialized")
//        }
//        playerItem.add(self.videoOutput!)
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
//    }

    // Optional: Method to manually cleanup resources
    func cleanup() {
        print("\(self.debugDescription): Video cleanup called")

        // Pause the player
        player?.pause()

        // Clean up player item and its associated resources
        if let playerItem = player?.currentItem {
            // Remove video output from player item before niling it
            if let videoOutput = videoOutput {
                playerItem.remove(videoOutput)
            }
        }
            // Remove time observer
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

            // Invalidate status observer
        if let statusObserver = statusObserver {
            statusObserver.invalidate()
            self.statusObserver = nil
        }
        looper = nil
        playerItem = nil
        player = nil

        // Stop accessing security scoped resource if it exists
        if let url = _url {
            url.stopAccessingSecurityScopedResource()
            self._url = nil
        }

        // Cancel asset loading
        if let asset = asset {
            asset.cancelLoading()
            self.asset = nil
        }

        utType = nil

        // Reset properties
        naturalSize = .zero
        currentTime = 0.0
        duration = 0.0
        assetIsHDR = false
        assetPreferredTransform = .identity
        videoColorProperties = [:]

        print("\(self.debugDescription): Video cleanup completed")
    }

    var debugDescription: String {
        return "VideoModel holding url: \(self.url?.absoluteString ?? "None")"
    }
}

enum VideoModelError: Error {
    case securityScopedResourceAccessFailed(URL)
    case initializationFailed(String)

    var localizedDescription: String {
        switch self {
        case .securityScopedResourceAccessFailed(let url):
            return "Failed to start accessing security scoped resource for: \(url)"
        case .initializationFailed(let desc):
            return "Failed to initialize VideoModel: \(desc)"
        }
    }
}
