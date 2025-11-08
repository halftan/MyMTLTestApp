//
//  VideoModel.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/7.
//

import SwiftUI
import AVKit

@Observable
class VideoModel {
    var url: URL? {
        return _url
    }
    
    // Private backing storage for the url property
    private var _url: URL?
    
    // Observable time properties
    private(set) var currentTime: TimeInterval = 0.0
    private(set) var duration: TimeInterval = 0.0
    
    // Video track properties
    private(set) var naturalSize: CGSize = .zero
    
    private var asset: AVAsset? {
        didSet {
            print("\(self.debugDescription): asset set to: \(asset)")
            // Cancel loading of old asset when replaced
            if let oldAsset = oldValue, oldAsset !== asset {
                cancelAssetLoading()
            }
        }
    }
    
    let player: AVPlayer = AVPlayer()
    
    private var timeObserver: Any?
    
    init() {
    }
    
    @MainActor
    deinit {
        // Stop accessing security scoped resource if it exists
        if let url = _url {
            url.stopAccessingSecurityScopedResource()
        }
        self.cancelAssetLoading()
        print("VideoModel deinit: \(self)")
    }
    
    func load(_ url: URL) async throws {
        // Cancel loading of current asset before loading new one
        cancelAssetLoading()
        
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
        asset = AVURLAsset(url: url)
        
        // Set up the player item and time observer when loading a new asset
        let playerItem = AVPlayerItem(asset: asset!)
        player.replaceCurrentItem(with: playerItem)
        addPeriodicTimeObserver()
        
        await loadNaturalSize()
    }
    
    private func loadNaturalSize() async {
        guard let asset = asset else { return }
        
        do {
            // Load the tracks to access video track properties
            let tracks = try await asset.loadTracks(withMediaType: .video)
            
            // Get the first video track and load its natural size
            guard let firstVideoTrack = tracks.first else {
                print("No video track found in asset")
                return
            }
            
            let size = try await firstVideoTrack.load(.naturalSize)
            self.naturalSize = size
            print("Loaded natural size: \(size)")
            
        } catch {
            print("Failed to load video track natural size: \(error)")
        }
    }
    
    private func addPeriodicTimeObserver() {
        let interval = CMTime(value: 1, timescale: 10)
        self.timeObserver = self.player.addPeriodicTimeObserver(forInterval: interval,
                                                                queue: .main) { [weak self] time in
            guard let self else { print("timeObserver invalidated, self is nil"); return }
            Task { @MainActor in
                // Update the observable properties on the main actor
                self.currentTime = time.seconds
                self.duration = duration
            }
        }
    }
    
    private func cancelAssetLoading() {
        guard let asset = asset else { return }
        
        // Cancel all loading requests
        asset.cancelLoading()
        
        player.replaceCurrentItem(with: nil)
        
        // Remove time observer
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Pause the player
        player.pause()
    }
    
    // Optional: Method to manually cleanup resources
    func cleanup() {
        print("\(self.debugDescription): Video cleanup called")
        // Stop accessing security scoped resource if it exists
        if let url = _url {
            url.stopAccessingSecurityScopedResource()
        }
        cancelAssetLoading()
        _url = nil
        asset = nil
        naturalSize = .zero
    }
    
    var debugDescription: String {
        return "VideoModel holding url: \(self.url?.absoluteString ?? "None")"
    }
}

enum VideoModelError: Error {
    case securityScopedResourceAccessFailed(URL)
    
    var localizedDescription: String {
        switch self {
        case .securityScopedResourceAccessFailed(let url):
            return "Failed to start accessing security scoped resource for: \(url)"
        }
    }
}
