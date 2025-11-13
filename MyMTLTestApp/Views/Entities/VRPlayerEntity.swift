//
//  VRPlayerEntity.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/13.
//
import SwiftUI
import AVFoundation
import CoreVideo
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

enum VRPlayerEntityError: Error {
    case initializationFailed(String)

    var localizedDescription: String {
        switch self {
        case .initializationFailed(let desc):
            return "Failed to initialize VRPlayerEntity: \(desc)"
        }
    }
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

class VRPlayerEntity: Entity, HasModel, TextureProviding {

    var renderer: Renderer!

    var leftEyeTarget = RenderTarget()
    var rightEyeTarget = RenderTarget()
    var monoTarget: RenderTarget {
        leftEyeTarget
    }
    var monoMaterial: ShaderGraphMaterial!
    var stereoMaterial: ShaderGraphMaterial!

    var stereoOn = true

    // let textureSize = MTLSizeMake(1024, 1024, 1)
    // var aspectRatio: Double {
    //     Double(textureSize.width) / Double(textureSize.height)
    // }

    var device: MTLDevice!

    var colorPixelFormat: MTLPixelFormat = .rgba16Float
    var depthStencilPixelFormat: MTLPixelFormat = .depth32Float_stencil8

    var texture: MTLTexture!

    var videoModel: VideoModel?
    var mtlTextureCache: CVMetalTextureCache?
    var cvMetalTexture: CVMetalTexture!

    func frameTexture() -> (any MTLTexture)? {
        return texture
    }

    func makeRenderTarget(size: MTLSize) -> RenderTarget {
        let colorTexture = try! LowLevelTexture(descriptor: .init(textureType: .type2D,
                                                                  pixelFormat: colorPixelFormat,
                                                                  width: size.width,
                                                                  height: size.height,
                                                                  depth: size.depth,
                                                                  mipmapLevelCount: 1,
                                                                  textureUsage: [.shaderRead, .shaderWrite, .renderTarget]))

        let depthStencilDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthStencilPixelFormat,
                                                                              width: size.width,
                                                                              height: size.height,
                                                                              mipmapped: false)

        depthStencilDescriptor.storageMode = .memoryless
        depthStencilDescriptor.usage = [.renderTarget]

        let depthStencilTexture = device.makeTexture(descriptor: depthStencilDescriptor)

        return .init(colorTexture: colorTexture,
                     depthStencilTexture: depthStencilTexture)
    }

    private func makeMetalTextureCache() throws -> CVMetalTextureCache? {
        var mtlTextureCache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                               nil,
                                               self.device,
                                               nil,
                                               &mtlTextureCache)
        switch result {
        case kCVReturnSuccess:
            print("Successfully created CVMetalTextureCache")
        case kCVReturnInvalidPixelFormat:
            throw VRPlayerEntityError.initializationFailed("Failed to create CVMetalTextureCache: invalid pixel format")
        default:
            throw VRPlayerEntityError.initializationFailed("Failed to create CVMetalTextureCache: CVReturn:\(result)")
        }

        return mtlTextureCache
    }

    @MainActor
    func setup(resourceFile: URL, videoModel: VideoModel) async {
        self.device = MTLCreateSystemDefaultDevice()

        var size: MTLSize
        self.videoModel = videoModel
        if videoModel.isVideo {
            print("Loading video resource")
            self.mtlTextureCache = try! makeMetalTextureCache()
            size = .init(
                width: Int(videoModel.naturalSize.width / 2), height: Int(videoModel.naturalSize.height), depth: 1
            )
            // make a default texture
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: colorPixelFormat,
                width: Int(videoModel.naturalSize.width / 2),
                height: Int(videoModel.naturalSize.height),
                mipmapped: false
            )
            self.texture = device.makeTexture(descriptor: descriptor)
        } else {
            print("Loading image resource")
            self.texture = try! await Renderer.loadTexture(device: device, resourceFile: resourceFile)
            size = .init(
                width: texture.width / 2,
                height: texture.height,
                depth: texture.depth
            )
        }

        self.leftEyeTarget = makeRenderTarget(size: size)
        self.rightEyeTarget = makeRenderTarget(size: size)

        self.monoMaterial = await createFramebufferMaterial(
            leftEyeTexture: leftEyeTarget.colorTexture,
            rightEyeTexture: leftEyeTarget.colorTexture
        )
        self.stereoMaterial = await createFramebufferMaterial(
            leftEyeTexture: leftEyeTarget.colorTexture,
            rightEyeTexture: rightEyeTarget.colorTexture
        )

//        let planeMesh = try! PlaneMesh(size: [0.1, 0.1], dimensions: [2, 2])
//        let mesh = try! await MeshResource(from: planeMesh.mesh)
//        let simpleMaterial = SimpleMaterial(color: .magenta, isMetallic: true)
//        let unlitMaterial = try! await UnlitMaterial(texture: TextureResource(contentsOf: Bundle.main.url(forResource: "uv1", withExtension: "png")!))
//        self.components.set(ModelComponent(mesh: mesh, materials: [simpleMaterial]))
//        self.components.set(ModelComponent(mesh: .generatePlane(width: 1.0, height: 1.0, cornerRadius: 0.1), materials: [unlitMaterial]))

        let hemisphereMesh = try! HemisphereMesh(radius: 10, segments: 128, rings: 256, maxVertexDepth: 1000)
        let hemisphereMeshResource = try! await MeshResource(from: hemisphereMesh.mesh)
        self.components.set(ModelComponent(mesh: hemisphereMeshResource, materials: [stereoMaterial]))

        self.components.set(VRPlayerComponent())

        createScene()
    }

    // var size: CGSize = .init(width: 100, height: 100)

    func createScene() {
        renderer = Renderer(device: device, renderDestination: self, textureProvider: self) { [weak self] in
            guard let self else {
                return
            }

            // TODO: update scene

            if videoModel == nil || !videoModel!.isVideo {
                return
            }

            // Extract next frame if item is video
            // maybe useful?
            // CVMetalTextureCacheFlush(self.mtlTextureCache!, 0)

            guard let videoOutput = videoModel?.videoOutput else {
                print("video output not set!")
                return
            }
            let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
            if !videoOutput.hasNewPixelBuffer(forItemTime: itemTime) {
                return
            }
            guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
                print("Failed to copy pixel buffer from video output")
                return
            }
            let pixelBufferWidth = CVPixelBufferGetWidth(pixelBuffer)
            let pixelBufferHeight = CVPixelBufferGetHeight(pixelBuffer)

            var cvTexture: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                self.mtlTextureCache!,
                pixelBuffer,
                nil,
                self.colorPixelFormat,
                pixelBufferWidth,
                pixelBufferHeight,
                0,
                &cvTexture)
            switch result {
            case kCVReturnSuccess:
                break
            default:
                print("Error when calling CVMetalTextureCacheCreateTextureFromImage: \(result)")
                return
            }
            cvMetalTexture = nil
            texture = nil

            cvMetalTexture = cvTexture
            texture = CVMetalTextureGetTexture(cvMetalTexture)
        }
    }

    var paused = false

    @MainActor
    func update() {
        if paused {
            texture = nil
            cvMetalTexture = nil
            return
        }
        autoreleasepool {
            renderer.draw(provider: self)
        }
        guard let isVideo = videoModel?.isVideo else {
            // videoModel is nil, could be something wrong. Pause rendering
            paused = true
            return
        }
        if !isVideo {
            // image needs only 1 render pass
            paused = true
        }
    }

    // func setFrameSize(size: CGSize) {
    //     self.size = size
    //     renderer.drawableSizeWillChange(size: size)
    // }

    func setStereo(_ state: Bool) {
        if state == stereoOn {
            // same state, do nothing
            return
        }
        stereoOn = state
        if stereoOn {
            self.components[ModelComponent.self]?.materials = [stereoMaterial]
        } else {
            self.components[ModelComponent.self]?.materials = [monoMaterial]
        }
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
    var updateOnce = true

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.vrplayer, updatingSystemWhen: .rendering) {
//            if updateOnce {
            (entity as? VRPlayerEntity)?.update()
//                updateOnce = false
//            }
        }
    }
}

#endif
