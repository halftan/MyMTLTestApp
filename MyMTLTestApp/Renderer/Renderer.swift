//
//  Renderer.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/10.
//

import Foundation
import MetalKit
import simd

let maxFramesInFlight = 3

#if os(visionOS)

class Renderer: NSObject {

    let device: MTLDevice

    let commandQueue: MTLCommandQueue!

    let endFrameEvent: MTLSharedEvent!

    // Called at the start of every frame.
    private let didBeginFrame: () -> Void

    var pipelineStates: PipelineStates
    var depthStencilStates: DepthStencilStates
    var committedFrameNumber: UInt64 = 0

    // If provided, this is called at the end of every frame, and should return a drawable that will be presented.
    var getCurrentDrawable: (() -> CAMetalDrawable?)?

    // If provided, this is called whenever the drawable size changes.
    var drawableSizeWillChange: ((MTLDevice, CGSize, MTLStorageMode) -> Void)?

    var size: CGSize = .init(width: 100, height: 100)

    var textureProvider: TextureProviding

    let defaultPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        return descriptor
    }()

    init(device: MTLDevice,
         renderDestination: RenderDestination,
         textureProvider: TextureProviding,
         didBeginFrame: @escaping () -> Void) {

        self.commandQueue = device.makeCommandQueue()!
        self.didBeginFrame = didBeginFrame
        self.pipelineStates = .init(device: device, renderDestination: renderDestination)
        self.depthStencilStates = .init(device: device)
        self.device = device
        self.textureProvider = textureProvider

        self.endFrameEvent = device.makeSharedEvent()
        // Start the signal value + committed frames index at
        // max buffers in flight to avoid negative values
        self.endFrameEvent.signaledValue = UInt64(maxFramesInFlight)
        committedFrameNumber = UInt64(maxFramesInFlight)

        print("Renderer using device: \(device.name)")
        super.init()
    }

    func beginFrame() -> MTLCommandBuffer {
        // TODO: is waiting for GPU event needed here?
//        commandQueue.waitForEvent(endFrameEvent, value: committedFrameNumber - UInt64(maxFramesInFlight))
//        guard endFrameEvent.wait(untilSignaledValue: committedFrameNumber - UInt64(maxFramesInFlight), timeoutMS: 20) else {
//            print("Timeout waiting for next frame signal!")
//            return nil
//        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to create a new command buffer")
        }

        didBeginFrame()

        return commandBuffer
    }

    func beginDrawableCommands() -> MTLCommandBuffer {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to make command buffer from command queue")
        }

        // Add a completion handler that signals `inFlightSemaphore`
        // when Metal and the GPU has fully finished processing the commands encoded for this frame.
        // This indicates when the dynamic buffers, written this frame, will no longer be needed by Metal and the GPU.
        //        commandBuffer.addCompletedHandler { [weak self] _ in
        //            self?.inFlightSemaphore.signal()
        //        }

        return commandBuffer
    }

    func endFrame(_ commandBuffer: MTLCommandBuffer) {
        if let drawable = getCurrentDrawable?() {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
        committedFrameNumber += 1
//        endFrameEvent.signaledValue = committedFrameNumber
    }

    func encodePass(into commandBuffer: MTLCommandBuffer,
                    using descriptor: MTLRenderPassDescriptor,
                    label: String,
                    _ encodingBlock: (MTLRenderCommandEncoder) -> Void) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            fatalError("Failed to make render command encoder with: \(descriptor.description)")
        }
        renderEncoder.label = label
        encodingBlock(renderEncoder)
        renderEncoder.endEncoding()
    }

    func encodeStage(using renderEncoder: MTLRenderCommandEncoder,
                     label: String,
                     _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }

    func encodeSampleStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Sample stage") {
            renderEncoder.setRenderPipelineState(pipelineStates.simpleTextureSampling)
            // Calculate new display Transform and set vertex buffer

            weak var texture = textureProvider.frameTexture()
            if texture == nil {
                fatalError("failed to fetch texture for next frame")
            }
            let desiredSize = CGSize(width: texture!.width, height: texture!.height)
            var modelProjectionMatrix = self.displayTransform(
                frameSize: desiredSize,
                contentTransform: .identity,
                displaySize: desiredSize
            )
            renderEncoder.setVertexBytes(&modelProjectionMatrix, length: MemoryLayout<float4x4>.stride, index: 0)
            renderEncoder.setFragmentTexture(texture, index: 0)

            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
}

@objc protocol DrawableProviding {
    var viewCount: Int { get }

    // TODO: omitted for now
//    func viewMatrix(viewIndex: Int) -> simd_float4x4
//    func projectionMatrix(viewIndex: Int) -> simd_float4x4

    func colorTexture(viewIndex: Int, for commandBuffer: MTLCommandBuffer) -> MTLTexture?
    func depthStencilTexture(viewIndex: Int, for commandBuffer: MTLCommandBuffer) -> MTLTexture?
}

protocol TextureProviding {
    func frameTexture() -> MTLTexture?
}

extension Renderer {
    func draw(provider: DrawableProviding) {
        var commandBuffer = beginFrame()
        commandBuffer.label = "Shadow commands"

        // TODO: draw shadows

        commandBuffer.commit()

        for viewIndex in 0..<provider.viewCount {
            // TODO: scene/texture update
            commandBuffer = beginDrawableCommands()
            commandBuffer.label = "GBuffer & Lighting Commands"

            if let color = provider.colorTexture(viewIndex: viewIndex, for: commandBuffer),
               let depthStencil = provider.depthStencilTexture(viewIndex: viewIndex, for: commandBuffer) {

                defaultPassDescriptor.colorAttachments[0].texture = color
                defaultPassDescriptor.colorAttachments[0].clearColor = .init(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
//                defaultPassDescriptor.depthAttachment.texture = depthStencil
//                defaultPassDescriptor.stencilAttachment.texture = depthStencil

                encodePass(into: commandBuffer, using: defaultPassDescriptor, label: "Default render pass") { renderEncoder in
                    var viewIndex = viewIndex
                    renderEncoder.setFragmentBytes(&viewIndex, length: MemoryLayout<Int>.size, index: 0)
                    encodeSampleStage(using: renderEncoder)
                }
            }

            endFrame(commandBuffer)
        }
    }

    func drawableSizeWillChange(size: CGSize) {
        let storageMode = MTLStorageMode.private

        self.size = size
        drawableSizeWillChange?(device, size, storageMode)
    }
}

extension Renderer {
    func displayTransform(frameSize: CGSize,
                                  contentTransform: CGAffineTransform,
                                  displaySize: CGSize) -> simd_float4x4
    {
        // The natural frame of a video track is the bounding rect of the image containing a frame's contents.
        let naturalFrame = CGRectMake(0, 0, frameSize.width, frameSize.height)
        // The video frame is the bounding rect of a frame after transformation by the track's preferred transform.
        let videoFrame = CGRectApplyAffineTransform(naturalFrame, contentTransform)
        // Vertices in the vertex shader are the corners of a canonical (unit) square; this transform reshapes
        // that square so its size matches the natural frame of the video.
        let naturalFromCanonicalTransform = CGAffineTransformMakeScale(frameSize.width, frameSize.height)
        // Concatenating the preferred transform of the video with the natural-from-canonical transform produces
        // a transform that scales, rotates, and translates the unit square into the final video frame size and orientation.
        let videoFromCanonicalTransform = CGAffineTransformConcat(naturalFromCanonicalTransform, contentTransform)
        let videoFrameMatrix = simd_float4x4(videoFromCanonicalTransform)
        // To display the video in an aspect-correct manner, we transform the bounds of the video frame
        // so that they fit tightly within the bounding rect of the surface to be presented.
        let displayBounds = CGRect(x: 0, y: 0, width: displaySize.width, height: displaySize.height)
        let modelMatrix = transformForAspectFitting(videoFrame, in: displayBounds)
        // The projection matrix takes us from coordinates expressed relative to the presentation surface's bounds
        // into clip space.
        let projectionMatrix = float4x4.orthographicProjection(left: 0,
                                                               top: 0,
                                                               right: Float(displayBounds.width),
                                                               bottom: Float(displayBounds.height),
                                                               near: -1,
                                                               far: 1)
        // The final model–projection matrix combines the effects of the above transforms.
        let videoTransform = projectionMatrix * modelMatrix * videoFrameMatrix
        return videoTransform
    }
}

extension Renderer {
    static func loadTexture(device: MTLDevice,
                            resourceFile: URL) async throws -> MTLTexture {
        /// Load texture data with optimal parameters for sampling

        let textureLoader = MTKTextureLoader(device: device)

        let textureLoaderOptions = [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
        ]

        return try await textureLoader.newTexture(URL: resourceFile, options: textureLoaderOptions)
    }
}

#endif
