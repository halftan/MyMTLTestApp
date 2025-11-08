// Renderer.swift
import MetalKit

enum Metal4RendererError: Error {
    case badVertexDescriptor
    case drawableNotAvailable
    case renderPassDescriptorNotAvailable
    case commandQueueCreationFailed
}

class Metal4Renderer: NSObject, @MainActor RenderDelegate {
    let kMaxFramesInFlight: UInt64 = 3
    
    let device: MTLDevice
    
    let commandQueue: MTL4CommandQueue
    
    let commandBuffer: MTL4CommandBuffer
    
    let sharedEvent: MTLSharedEvent
    
    private var renderPipelineState: MTLRenderPipelineState!
    private var commandAllocators: [MTL4CommandAllocator] = []
    private var view: MTKView?
    
    var library: MTLLibrary?
    var frameNumber: UInt64 = 0
    var viewportSize: CGRect = .zero
    var colorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    
    var videoModel: VideoModel?

    init(video: VideoModel) {
        self.device = MTLCreateSystemDefaultDevice()!
        self.videoModel = video
        // The command queue is used to submit work to the GPU.
        self.commandQueue = device.makeMTL4CommandQueue()!
        self.commandBuffer = device.makeCommandBuffer()!
        self.sharedEvent = device.makeSharedEvent()!
        super.init()
        self.commandAllocators = (0...kMaxFramesInFlight).map({_ in self.device.makeCommandAllocator()!})
    }
    
    func startRendering() {
        self.sharedEvent.signaledValue = frameNumber
    }
    
    func configure(view: MTKView) {
        self.view = view
        self.colorPixelFormat = view.colorPixelFormat
        view.device = self.device
        view.delegate = self
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        self.library = device.makeDefaultLibrary()
        self.renderPipelineState = self.compilerRenderPipeline(view.colorPixelFormat)
    }
    
    /// This method is called whenever the view's size changes.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // You can use this to respond to window resizes, for example,
        // by recreating size-dependent resources.
        print("View changed to: \(view.frame)")
        self.viewportSize = view.frame
    }
    
    /// This method is called for every frame that needs to be rendered.
    func draw(in view: MTKView) {
        frameNumber += 1
        let frameIndex = Int(frameNumber % kMaxFramesInFlight)
        let frameLabel = "Frame: \(frameNumber)"
        
        // The renderer skips waiting for the first `kMaxFramesInFlight` frames.
        // There aren't any earlier frames to wait for because they're the first.
        if (frameNumber > kMaxFramesInFlight) {
            // Wait for the oldest frame in flight to finish rendering before reusing its resources.
            self.waitOnSharedEvent(for: frameNumber - kMaxFramesInFlight)
        }

        // Validate required resources individually for better error reporting
        guard let drawable = view.currentDrawable else {
            print("⚠️ [Frame \(frameNumber)] No drawable available - view may not be ready or in background")
            return
        }
        
        guard let renderPassDescriptor = view.currentMTL4RenderPassDescriptor else {
            print("⚠️ [Frame \(frameNumber)] Render pass descriptor not available - MTKView configuration may be incomplete")
            return
        }
        
        guard let commandQueue = device.makeMTL4CommandQueue() else {
            print("❌ [Frame \(frameNumber)] Failed to create MTL4CommandQueue - device may be unavailable")
            return
        }
        
        let frameAllocator = self.commandAllocators[frameIndex]
        frameAllocator.reset()
        self.commandBuffer.beginCommandBuffer(allocator: frameAllocator)
        commandBuffer.label = frameLabel
        
        let renderEncoder = self.commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.label = frameLabel
        renderEncoder.setRenderPipelineState(self.renderPipelineState)
        
        // Update vertex and texture
        // TODO
        
        // Draw
        renderEncoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 4)
        
        // Finalize the render pass.
        renderEncoder.endEncoding()
        commandBuffer.endCommandBuffer()
        
        commandQueue.waitForDrawable(drawable)
        commandQueue.commit([commandBuffer])
        commandQueue.signalDrawable(drawable)
        drawable.present()
        
        commandQueue.signalEvent(self.sharedEvent, value: frameNumber)
    }

    func waitOnSharedEvent(for frame: UInt64) {
        let maxFrameTime: UInt64 = 10
        let beforeTimeout = self.sharedEvent.wait(untilSignaledValue: frame, timeoutMS: maxFrameTime)
        if !beforeTimeout {
            print("No signal from frame \(frame) after timeout(ms) \(maxFrameTime)")
        }
    }
}
