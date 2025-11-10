//
//  PipelineStates.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/10.
//

import Metal

struct PipelineStates {

    lazy var simpleTextureSampling = makeRenderPipelineState(label: "Texture Sampling") { descriptor in
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_linear_sbs")
        
        // TODO: add depth stencil to the scene
        descriptor.depthAttachmentPixelFormat = .invalid
        descriptor.stencilAttachmentPixelFormat = .invalid
        descriptor.colorAttachments[0]?.pixelFormat = colorPixelFormat
    }

    let device: MTLDevice
    let library: MTLLibrary

    let colorPixelFormat: MTLPixelFormat
    let depthStencilPixelFormat: MTLPixelFormat

    init(device: MTLDevice, renderDestination: RenderDestination) {
        self.device = device
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create Metal default library with device: \(device.description)")
        }
        self.library = library
        self.colorPixelFormat = renderDestination.colorPixelFormat
        self.depthStencilPixelFormat = renderDestination.depthStencilPixelFormat
    }

    func makeRenderPipelineState(label: String,
                                 block: (MTLRenderPipelineDescriptor) -> Void) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        block(descriptor)
        descriptor.label = label
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
