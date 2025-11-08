//
//  Metal4Renderer+Compilation.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/7.
//

import Metal

extension Metal4Renderer {
    func compilerRenderPipeline(_ format: MTLPixelFormat) -> MTLRenderPipelineState? {
        let compiler = try! self.device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        let descriptor = self.configureRenderPipeline(format)
        let compilerTasksOpt = self.configureCompilerTaskOptions()
        
        do {
            let compilerRenderState = try compiler.makeRenderPipelineState(descriptor: descriptor, compilerTaskOptions: compilerTasksOpt)
            return compilerRenderState
        } catch (let error) {
            print("Failed to create render pipeline state: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    func configureRenderPipeline(_ format: MTLPixelFormat) -> MTL4RenderPipelineDescriptor {
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "Basic Metal 4 render pipeline"
        
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.vertexFunctionDescriptor = self.makeVertexShaderDescriptor()
        descriptor.fragmentFunctionDescriptor = self.makeFragmentShaderDescriptor()
        
        return descriptor
    }
    
    func makeVertexShaderDescriptor() -> MTL4LibraryFunctionDescriptor {
        let descriptor = MTL4LibraryFunctionDescriptor()
        descriptor.library = self.library
        descriptor.name = "vertexShader"
        return descriptor
    }

    func makeFragmentShaderDescriptor() -> MTL4LibraryFunctionDescriptor {
        let descriptor = MTL4LibraryFunctionDescriptor()
        descriptor.library = self.library
        descriptor.name = "fragmentShader"
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
