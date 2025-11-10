//
//  Metal4Renderer+Compilation.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/7.
//

import Metal
import AVFoundation

extension Metal4Renderer {
    func compileRenderPipeline(for transferFunction: String) -> MTLRenderPipelineState? {
        let compiler = try! self.device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "Basic Metal 4 render pipeline"
        
        descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        descriptor.vertexFunctionDescriptor = self.makeVertexShaderDescriptor()
        descriptor.fragmentFunctionDescriptor = self.makeFragmentShaderDescriptor(for: transferFunction)
//        descriptor.maxVertexAmplificationCount = 2
        let compilerTasksOpt = self.configureCompilerTaskOptions()
        
        do {
            let compilerRenderState = try compiler.makeRenderPipelineState(descriptor: descriptor, compilerTaskOptions: compilerTasksOpt)
            return compilerRenderState
        } catch (let error) {
            print("Failed to create render pipeline state: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    func makeVertexShaderDescriptor() -> MTL4LibraryFunctionDescriptor {
        let descriptor = MTL4LibraryFunctionDescriptor()
        descriptor.library = self.library
        descriptor.name = "vertex_main"
        return descriptor
    }

    func makeFragmentShaderDescriptor(for transferFunction: String) -> MTL4LibraryFunctionDescriptor {
        let descriptor = MTL4LibraryFunctionDescriptor()
        descriptor.library = self.library
        let fragmentFunctionName = switch transferFunction {
//        case AVVideoTransferFunction_SMPTE_ST_2084_PQ:
//            "fragment_tonemap_pq"
//        case AVVideoTransferFunction_ITU_R_2100_HLG:
//            "fragment_tonemap_hlg"
        default:
            "fragment_linear"
        }
        print("Selected fargment func: \(fragmentFunctionName)")
        descriptor.name = fragmentFunctionName
        return descriptor
    }
    
    func configureCompilerTaskOptions() -> MTL4CompilerTaskOptions {
        guard let archiveURL = Bundle.main.url(forResource: "archive", withExtension: "metallib") else {
            print("Failed to get URL for Metal 4 compile archive")
            print("Continue without compile archive")
            return MTL4CompilerTaskOptions()
        }
        
        do {
            let archive = try self.device.makeArchive(url: archiveURL)
            let compilerTasksOpt = MTL4CompilerTaskOptions()
            compilerTasksOpt.lookupArchives = [archive]
            return compilerTasksOpt
        } catch (let error) {
            print("Failed to create compiler task option: \(error.localizedDescription)")
            print("Continue without compile archive")
        }
        return MTL4CompilerTaskOptions()
    }
}
