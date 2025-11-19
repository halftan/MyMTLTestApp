// Renderer.swift
import MetalKit
import AVFoundation

nonisolated let alignedModelProjectionMatrixSize = (MemoryLayout<simd_float4x4>.size + 0xFF) & -0x100
nonisolated let edrHeadroomSize = (MemoryLayout<Float>.size)

enum Metal4RendererError: Error {
    case badVertexDescriptor
    case drawableNotAvailable
    case renderPassDescriptorNotAvailable
    case commandQueueCreationFailed
    case initializationFailed(String)

    var localizedDescription: String {
        switch self {
        case .initializationFailed(let desc):
            return "Failed to initialize VideoModel: \(desc)"
        case .badVertexDescriptor:
            return "Bad vertex descriptor"
        case .drawableNotAvailable:
            return "Drawable not available"
        case .renderPassDescriptorNotAvailable:
            return "Render pass descriptor not available"
        case .commandQueueCreationFailed:
            return "Command queue creation failed"
        }
    }
}

enum TonemappingMode {
    case edr
    case auto
}

class Metal4Renderer: NSObject, @MainActor RenderDelegate {
    let device: MTLDevice

    let commandQueue: MTL4CommandQueue

    let commandBuffer: MTL4CommandBuffer

    let endFrameEvent: MTLSharedEvent

    let vertexArgumentTable: MTL4ArgumentTable
    let fragmentArgumentTable: MTL4ArgumentTable

    let vertexBuffer: MTLBuffer
    let edrHeadroomBuffer: MTLBuffer

    private var renderPipelineState: MTLRenderPipelineState!
    private var commandAllocators: [MTL4CommandAllocator] = []
    private var view: MTKView?

    var library: MTLLibrary?
    var committedFrameNumber: UInt64 = 0
    var viewportSize: CGSize = .zero
    var colorPixelFormat: MTLPixelFormat = .invalid

    var videoModel: VideoModel?
    var mtlTextureCache: CVMetalTextureCache?

    var vertexBufferIndex = 0
    var vertexBufferOffset = 0
    var edrHeadroomBufferIndex = 0
    var edrHeadroomBufferOffset = 0

    let tonemappingMode: TonemappingMode = .auto
    private var currentEDRHeadroom: CGFloat = 1.1

    init(video: VideoModel) {
        self.colorPixelFormat = .rgba16Float

        self.device = MTLCreateSystemDefaultDevice()!
        print("Selected Metal device: \(device.name)")
        self.videoModel = video
        // The command queue is used to submit work to the GPU.
        self.commandQueue = device.makeMTL4CommandQueue()!
        self.commandBuffer = device.makeCommandBuffer()!
        self.library = device.makeDefaultLibrary()

        let vertexBufferSize = alignedModelProjectionMatrixSize * maxFramesInFlight
        self.vertexBuffer = device.makeBuffer(length: vertexBufferSize, options: [.storageModeShared])!
        self.vertexBuffer.label = "Main vertex buffer"

        let edrHeadroomBufferSize = edrHeadroomSize * maxFramesInFlight
        self.edrHeadroomBuffer = device.makeBuffer(length: edrHeadroomBufferSize, options: [.storageModeShared])!
        self.edrHeadroomBuffer.label = "EDR headroom buffer"

        self.endFrameEvent = device.makeSharedEvent()!
        // Start the signal value + committed frames index at
        // max buffers in flight to avoid negative values
        self.endFrameEvent.signaledValue = UInt64(maxFramesInFlight)
        committedFrameNumber = UInt64(maxFramesInFlight)

        let argTableDesc = MTL4ArgumentTableDescriptor()
        argTableDesc.maxBufferBindCount = 1
        self.vertexArgumentTable = try! device.makeArgumentTable(descriptor: argTableDesc)
        argTableDesc.maxBufferBindCount = 1
        argTableDesc.maxTextureBindCount = 1
        self.fragmentArgumentTable = try! device.makeArgumentTable(descriptor: argTableDesc)

        super.init()

        self.mtlTextureCache = try! makeMetalTextureCache()
        self.commandAllocators = (0...maxFramesInFlight).map({_ in self.device.makeCommandAllocator()!})
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
            throw Metal4RendererError.initializationFailed("Failed to create CVMetalTextureCache: invalid pixel format")
        default:
            throw Metal4RendererError.initializationFailed("Failed to create CVMetalTextureCache: CVReturn:\(result)")
        }

        return mtlTextureCache
    }

    func configure(view: MTKView) {
        print("Configure called")
        self.view = view
        view.device = self.device
        view.delegate = self
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        view.framebufferOnly = false
    }

    func prepareRender(for transferFunction: String) async {
        guard let view = view else { return }
        guard let metalLayer = view.layer as? CAMetalLayer else { return }

        /// not needed as we've set these properties on metalLayer
//        view.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_HLG)
//        view.colorPixelFormat = self.colorPixelFormat

        reportMaxEDRHeadroom()
        setInitialEDRMetadata()

        metalLayer.wantsExtendedDynamicRangeContent = true
        switch transferFunction {
        case AVVideoTransferFunction_ITU_R_2100_HLG:
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_HLG)
        case AVVideoTransferFunction_SMPTE_ST_2084_PQ:
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
        case AVVideoTransferFunction_ITU_R_709_2:
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.itur_709_HLG)
        case AVVideoTransferFunction_IEC_sRGB:
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedSRGB)
        default:
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedDisplayP3)
        }
        metalLayer.pixelFormat = self.colorPixelFormat

        self.renderPipelineState = self.compileRenderPipeline(for: transferFunction)
    }

    /// This method is called whenever the view's size changes.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // You can use this to respond to window resizes, for example,
        // by recreating size-dependent resources.
        self.viewportSize = view.drawableSize
    }

    private func updateDynamicBufferState(frameIndex: UInt64) {

        self.vertexBufferIndex = (vertexBufferIndex + 1) % maxFramesInFlight
        self.vertexBufferOffset = alignedModelProjectionMatrixSize * vertexBufferIndex

        self.edrHeadroomBufferIndex = (edrHeadroomBufferIndex + 1) % maxFramesInFlight
        self.vertexBufferOffset = edrHeadroomSize * edrHeadroomBufferIndex
    }

    /// This method is called for every frame that needs to be rendered.
    func draw(in view: MTKView) {
        autoreleasepool {
            render(in: view)
        }
    }

    func render(in view: MTKView) {
        let frameIndex = Int(committedFrameNumber % UInt64(maxFramesInFlight))
        let frameLabel = "Frame: \(committedFrameNumber)"

        guard self.endFrameEvent.wait(untilSignaledValue: committedFrameNumber - UInt64(maxFramesInFlight), timeoutMS: 100) else {
            print("Timeout waiting for buffered frame to draw!")
            return
        }
        CVMetalTextureCacheFlush(self.mtlTextureCache!, 0)

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
        let frameTexture: MTLTexture! = CVMetalTextureGetTexture(cvTexture!)

        // Validate required resources individually for better error reporting
        guard let drawable = view.currentDrawable else {
            print("⚠️ [Frame \(committedFrameNumber)] No drawable available - view may not be ready or in background")
            return
        }

        guard let renderPassDescriptor = view.currentMTL4RenderPassDescriptor else {
            print("⚠️ [Frame \(committedFrameNumber)] Render pass descriptor not available - MTKView configuration may be incomplete")
            return
        }

        guard let commandQueue = device.makeMTL4CommandQueue() else {
            print("❌ [Frame \(committedFrameNumber)] Failed to create MTL4CommandQueue - device may be unavailable")
            return
        }
        let time = drawable.presentedTime

        let frameAllocator = self.commandAllocators[frameIndex]
        frameAllocator.reset()
        self.commandBuffer.beginCommandBuffer(allocator: frameAllocator)
        commandBuffer.label = "Main command buffer"

        let renderEncoder = self.commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.label = "Main render encoder"

        renderEncoder.pushDebugGroup("Draw video")

        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)

        renderEncoder.setRenderPipelineState(self.renderPipelineState)

        renderEncoder.setArgumentTable(self.vertexArgumentTable, stages: .vertex)
        renderEncoder.setArgumentTable(self.fragmentArgumentTable, stages: .fragment)

        // Update vertex and texture

        let matrix = UnsafeMutableRawPointer(vertexBuffer.contents() + vertexBufferOffset).bindMemory(to: simd_float4x4.self, capacity: 1)
        matrix[0] = displayTransform(frameSize: CGSize(width: pixelBufferWidth, height: pixelBufferHeight),
                                     contentTransform: videoModel?.assetPreferredTransform ?? .identity,
                                     displaySize: view.drawableSize)

        self.vertexArgumentTable.setAddress(vertexBuffer.gpuAddress + UInt64(vertexBufferOffset), index: 0)

        if tonemappingMode == .auto {
            pollCurrentEDRHeadroom()
            let edrHeadroomPointer = UnsafeMutableRawPointer(edrHeadroomBuffer.contents() + edrHeadroomBufferOffset).bindMemory(to: Float.self, capacity: 1)
            edrHeadroomPointer[0] = Float(currentEDRHeadroom)
            self.fragmentArgumentTable.setAddress(edrHeadroomBuffer.gpuAddress + UInt64(edrHeadroomBufferOffset), index: 0)
        }
        self.fragmentArgumentTable.setTexture(frameTexture.gpuResourceID, index: 0)

        // Draw
        renderEncoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // Finalize the render pass.
        renderEncoder.endEncoding()

        renderEncoder.popDebugGroup()

        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        commandQueue.commit([commandBuffer])
        commandQueue.signalDrawable(drawable)
        drawable.present()

        committedFrameNumber += 1
        commandQueue.signalEvent(self.endFrameEvent, value: committedFrameNumber)
    }

    private func displayTransform(frameSize: CGSize,
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

    private func reportMaxEDRHeadroom() {
        var maxHeadroom: CGFloat = 1.0
#if os(macOS)
        maxHeadroom = NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
#elseif os(iOS)
        maxHeadroom = UIScreen.main.potentialEDRHeadroom
#endif
        if maxHeadroom > 1.0 {
            print("The main display supports EDR with a maximum headroom of \(maxHeadroom).")
        } else {
            print("The main display does NOT support EDR.")
        }
    }

    private func pollCurrentEDRHeadroom() {
#if os (macOS)
        let screen = self.view?.window?.screen ?? NSScreen.main
        let headroom = screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0
#elseif os(iOS)
        let screen = self.view?.window?.screen ?? UIScreen.main
        let headroom = screen.currentEDRHeadroom
#else
        let headroom: CGFloat = 1.0
#endif
        if headroom != currentEDRHeadroom {
            print("EDR headrooom changed to \(headroom)")
            currentEDRHeadroom = headroom
        }
    }

    private func setInitialEDRMetadata() {
        guard let metalLayer = view?.layer as? CAMetalLayer else {
            print("Tried to set initial EDR metadata before view was configured")
            return
        }

        let videoIsHDR = videoModel?.isHDR ?? false
        if (tonemappingMode == .edr) && videoIsHDR && metalLayer.edrMetadata == nil {
            if CAEDRMetadata.isAvailable {
                metalLayer.edrMetadata = CAEDRMetadata.hdr10(minLuminance: 0.005,
                                                             maxLuminance: 1000.0,
                                                             opticalOutputScale: 100.0)
                print("Set default EDR metadata for HDR asset")
            } else {
                print("EDR tonemapping is not available; HDR content will likely clip")
            }
        }
    }
}
