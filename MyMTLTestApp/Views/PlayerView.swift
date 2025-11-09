//
//  PlayerView.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/8.
//

import SwiftUI
import AVKit

struct PlayerView: View {
    let video: VideoModel
    
    var body: some View {
        ZStack {
            Color.black
            if video.player.currentItem != nil {
                VideoPlayer(player: video.player)
                    .aspectRatio(video.aspectRatio, contentMode: .fit)
                    .contentMargins(20, for: .automatic)
                    .onAppear() {
                        video.player.play()
                    }
            }
        }
        .ignoresSafeArea()
    }
}
