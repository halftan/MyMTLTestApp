//
//  VRPlayerView.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/10.
//

import SwiftUI
import RealityKit
import RealityKit_assets

#if os(visionOS)
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

struct VRPlayerComponent: TransientComponent {}

class VRPlayerEntity: Entity, HasModel {
    
    var renderer: Renderer!
    
    var leftEyeTarget = RenderTarget()
    var rightEyeTarget = RenderTarget()
    var monoTarget: RenderTarget {
        leftEyeTarget
    }
    var monoMaterial: ShaderGraphMaterial!
    var stereoMaterial: ShaderGraphMaterial!

    let textureSize = MTLSizeMake(3840, 2160, 1)
    var aspectRatio: Double {
        Double(textureSize.width) / Double(textureSize.height)
    }
    
    var device: MTLDevice!
    
    var colorPixelFormat: MTLPixelFormat = .rgba16Float
    var depthStencilPixelFormat: MTLPixelFormat = .depth32Float_stencil8
    
    var texture: MTLTexture!

    func makeRenderTarget(size: MTLSize) -> RenderTarget {
        let colorTexture = try! LowLevelTexture(descriptor: .init(textureType: .type2D,
                                                                  pixelFormat: colorPixelFormat,
                                                                  width: textureSize.width,
                                                                  height: textureSize.height,
                                                                  depth: textureSize.depth,
                                                                  mipmapLevelCount: 1,
                                                                  textureUsage: [.shaderRead, .shaderWrite, .renderTarget]))

        let depthStencilDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthStencilPixelFormat,
                                                                              width: textureSize.width,
                                                                              height: textureSize.height,
                                                                              mipmapped: false)

        depthStencilDescriptor.storageMode = .memoryless
        depthStencilDescriptor.usage = [.renderTarget]

        let depthStencilTexture = device.makeTexture(descriptor: depthStencilDescriptor)

        return .init(colorTexture: colorTexture,
                     depthStencilTexture: depthStencilTexture)
    }

    @MainActor
    func setup(textureName: String, frameSize: CGSize) async {
        self.device = MTLCreateSystemDefaultDevice()
        
        self.texture = try! Renderer.loadTexture(device: device, textureName: textureName)

        self.leftEyeTarget = makeRenderTarget(
            size: .init(
                width: texture.width / 2,
                height: texture.height,
                depth: texture.depth
            )
        )
        self.rightEyeTarget = makeRenderTarget(
            size: .init(
                width: texture.width / 2,
                height: texture.height,
                depth: texture.depth
            )
        )

        self.monoMaterial = await createFramebufferMaterial(
            leftEyeTexture: leftEyeTarget.colorTexture,
            rightEyeTexture: leftEyeTarget.colorTexture
        )
        self.stereoMaterial = await createFramebufferMaterial(
            leftEyeTexture: leftEyeTarget.colorTexture,
            rightEyeTexture: rightEyeTarget.colorTexture
        )
        
        self.components.set(ModelComponent(mesh: MeshResource.generatePlane(width: 1, height: 1),
                                           materials: [stereoMaterial]))
        
        self.components.set(VRPlayerComponent())
        
        createScene(size: frameSize)
    }
    
    var size: CGSize = .init(width: 100, height: 100)
    
    func createScene(size: CGSize) {
        self.size = size
        renderer = Renderer(device: device, renderDestination: self, texture: texture) { [weak self] in
            guard let self else {
                return
            }
            
            // TODO: update scene
        }
        renderer.drawableSizeWillChange(size: size)
    }

    func update() {
        renderer.draw(provider: self)
    }
    
    func setFrameSize(size: CGSize) {
        self.size = size
        renderer.drawableSizeWillChange(size: size)
    }
}

extension VRPlayerEntity: DrawableProviding, RenderDestination {
    var viewCount: Int {
        return 2
    }
    
    func renderTarget(for viewIndex: Int) -> RenderTarget {
        switch viewIndex {
        case 0:
            return leftEyeTarget
        case 1:
            return rightEyeTarget
        default:
            return monoTarget
        }
    }

    func colorTexture(viewIndex: Int, for commandBuffer: any MTLCommandBuffer) -> (any MTLTexture)? {
        return renderTarget(for: viewIndex).colorTexture.replace(using: commandBuffer)
    }
    
    func depthStencilTexture(viewIndex: Int, for commandBuffer: any MTLCommandBuffer) -> (any MTLTexture)? {
        return renderTarget(for: viewIndex).depthStencilTexture
    }
    
    
}

class VRPlayerUpdaterSystem: System {
    required init(scene: RealityKit.Scene) {}
    
    static let vrplayer = EntityQuery(where: .has(VRPlayerComponent.self))
    
    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.vrplayer, updatingSystemWhen: .rendering) {
            (entity as? VRPlayerEntity)?.update()
        }
    }
}

struct VRPlayerView: View {
    @State var root = Entity()
    @State var playerEntity = VRPlayerEntity()

    var body: some View {
        GeometryReader { area in
            RealityView { content in
                VRPlayerUpdaterSystem.registerSystem()
                
                content.add(root)
                root.addChild(playerEntity)
                await playerEntity.setup(textureName: "SBS", frameSize: area.size)
//                if let affineTransform = area.transform(in: .local) {
////                    affineTransform.matrix4x4
//                    playerEntity.setTransformMatrix(.init(affineTransform), relativeTo: nil)
//                } else {
//                    print("Failed to get local area transform")
//                }
//                playerEntity.setTransformMatrix(area.transform(in: .global)?.matrix4x4)
            }
            .onChange(of: area.size) { oldVal, newVal in
                playerEntity.setFrameSize(size: newVal)
            }
        }
        .ignoresSafeArea()
    }
}

#endif
