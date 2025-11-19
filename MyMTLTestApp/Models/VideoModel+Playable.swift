//
//  VideoModel+MediaProvider.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/17.
//

import AVFoundation

extension VideoModel: Playable {
    var videoOutput: AVPlayerItemVideoOutput? {
        get {
            let output = self.player?.currentItem?.outputs.first as? AVPlayerItemVideoOutput
            return output
        }
    }

    var aspectRatio: CGFloat {
        get {
            if naturalSize != .zero {
                return naturalSize.width / naturalSize.height
            }
            return .defaultAspectRatio
        }
    }

    nonisolated func seek(to: CMTime) async -> Bool {
        guard let player = await player else {
            print("Failed to obtain current player")
            return false
        }
        return await player.seek(to: to)
    }

    nonisolated func stop() async {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            pause()
            cleanup()
        }
    }

    func play() {
        guard let player = player else {
            print("Failed to obtain current player")
            return
        }
        player.play()
    }

    func pause() {
        guard let player = player else {
            print("Failed to obtain current player")
            return
        }
        player.pause()
    }
}
