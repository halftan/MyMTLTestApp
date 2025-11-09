//
//  VRPlayerView.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/10.
//

import SwiftUI
import RealityKit
import RealityKit_assets

struct RenderTarget {
    var colorTexture: LowLevelTexture!
    var depthStencilTexture: MTLTexture!
}

let frameBufferShader = LazyAsync {
    return try! await ShaderGraphMaterial(
        named: "/Root/Material",
        from: "FramebufferShader",
        in: realityKit_assetsBundle
    )
}

@MainActor
func createFramebufferMaterial(leftEyeTexture: LowLevelTexture, rightEyeTexture: LowLevelTexture) async -> ShaderGraphMaterial {
    var material = await frameBufferShader.get()

    await MainActor.run {
        try! material.setParameter(name: "Eye_L", value: .textureResource(.init(from: leftEyeTexture)))
        try! material.setParameter(name: "Eye_R", value: .textureResource(.init(from: rightEyeTexture)))
    }

    return material
}

class VRPlayerEntity: Entity, HasModel {
    var leftEyeTarget = RenderTarget()
    var rightEyeTarget = RenderTarget()
    var monoTarget: RenderTarget {
        leftEyeTarget
    }
    var monoMaterial: ShaderGraphMaterial!
    var stereoMaterial: ShaderGraphMaterial!
    
    var device: MTLDevice!
    var rateMap: MTLRasterizationRateMap!
    var colorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    var depthStencilPixelFormat: MTLPixelFormat = .depth32Float_stencil8
    
    func makeRenderTarget(size: CGSize) -> RenderTarget {
        let colorTexture = try! LowLevelTexture(descriptor: .init(textureType: .type2D,
                                                                  pixelFormat: colorPixelFormat,
                                                                  width: Int(size.width),
                                                                  height: Int(size.height),
                                                                  depth: 1,
                                                                  mipmapLevelCount: 1,
                                                                  textureUsage: [.shaderRead, .shaderWrite, .renderTarget]))
        
    }

    @MainActor
    func setup() async {
        self.device = MTLCreateSystemDefaultDevice()
        self.leftEyeTarget = makeRenderTarget()
        self.rightEyeTarget = makeRenderTarget()
    }
}

struct VRPlayerView: View {
    @State var root = Entity()
    @State var playerEntity = VRPlayerEntity()
    
    var body: some View {
        RealityView { content in
            content.add(root)
            
            root.addChild(playerEntity)
        }
    }
}
