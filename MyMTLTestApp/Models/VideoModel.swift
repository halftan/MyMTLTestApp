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

    private(set) var contentType: UTType!
    private(set) var isVideo = true

    // Observable time properties
    private(set) var currentTime: TimeInterval = 0.0
    private(set) var duration: TimeInterval = 0.0

    // Video track properties
    private(set) var naturalSize: CGSize = .zero
    var aspectRatio: CGFloat {
        if naturalSize != .zero {
            return naturalSize.width / naturalSize.height
        }
        return .defaultAspectRatio
    }

    private var asset: AVAsset?
    var assetIsHDR = false
    var assetPreferredTransform: CGAffineTransform = .identity
    var videoColorProperties: [String: any Sendable] = [:]

    var transferFunction: String {
        return videoColorProperties[AVVideoTransferFunctionKey] as? String ?? ""
    }

    let player: AVPlayer = AVPlayer()

    private var timeObserver: Any?
    var statusObserver: NSKeyValueObservation?
    var videoOutput: AVPlayerItemVideoOutput?
    //    var displayLink: CADisplayLink?

    init() {
        print("Initializing video model")
    }

    @MainActor
    deinit {
        // Stop accessing security scoped resource if it exists
        if let url = _url {
            url.stopAccessingSecurityScopedResource()
        }
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
        contentType = resourceValue.contentType

        if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
            // video resource
            print("Resource is video")
            isVideo = true
            asset = AVURLAsset(url: url)

            // Set up the player item and time observer when loading a new asset
            let playerItem = AVPlayerItem(asset: asset!)
            player.replaceCurrentItem(with: playerItem)
            addPeriodicTimeObserver()

            try await parseVideoMetadata()
            try await prepareForRender()
        } else {
            isVideo = false
        }
    }

    func parseVideoMetadata() async throws {
        guard let asset = self.asset else {
            print("Asset not ready yet for metadata parsing")
            return
        }
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

        self.assetPreferredTransform = try await firstTrack.load(.preferredTransform)

        videoColorProperties = [:]
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
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(value: 1, timescale: 10)
        self.timeObserver = self.player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else {
                print("timeObserver invalidated, self is nil")
                return
            }
            Task { @MainActor in
                // Update the observable properties on the main actor
                self.currentTime = time.seconds
                self.duration = self.duration
            }
        }
    }

    // Optional: Method to manually cleanup resources
    func cleanup() {
        print("\(self.debugDescription): Video cleanup called")

        // Pause the player
        player.pause()

        // Clean up player item and its associated resources
        if let playerItem = player.currentItem {
            // Remove video output from player item before niling it
            if let videoOutput = videoOutput {
                playerItem.remove(videoOutput)
            }
        }

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

        contentType = nil

        // Remove time observer
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        // Invalidate status observer
        if let statusObserver = statusObserver {
            statusObserver.invalidate()
            self.statusObserver = nil
        }

        // Clear player item
        player.replaceCurrentItem(with: nil)

        // Clear video output
        videoOutput = nil

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
