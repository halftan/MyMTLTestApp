//
//  ImmersiveVRView.swift
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/13.
//

import RealityKit
import SwiftUI
import UniformTypeIdentifiers

#if os(visionOS)
struct ImmersiveVRView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(Settings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    private var root = Entity()
    private var playerEntity = VRPlayerEntity()
    private var anchor = AnchorEntity(.head, trackingMode: .once)

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in

                // Use fileModel's URL instead of hardcoded file
                guard
                    let resourceFileURL = appModel.videoModel.url
                else {
                    Text("No file is selected!")
                    print("Failed to get texture file URL")
                    return
                }

                VRPlayerUpdaterSystem.registerSystem()

                // let myMesh = try! PlaneMesh(size: [1.0, 1.0], dimensions: [16, 16])
                // let myMesh = try! HemisphereMesh(radius: 100, segments: 128, rings: 128, maxVertexDepth: 100)
                // let mesh = try! await MeshResource(from: myMesh.mesh)
                // let mat = try! await UnlitMaterial(texture: TextureResource(contentsOf: textureFile))
                // let m = ModelEntity(mesh: mesh, materials: [mat])

                // root.components.set(InputTargetComponent())
                // var collision = CollisionComponent(shapes: [.generateSphere(radius: 100)])
                // collision.filter = CollisionFilter(group: [], mask: [])
                // root.components.set(collision)

                content.add(anchor)
                anchor.addChild(root)
                root.addChild(playerEntity)
                playerEntity.scale = .init(x: 1, y: 1, z: -1)
                await playerEntity.setup(
                    resourceFile: resourceFileURL,
                    videoModel: appModel.videoModel)
                // if let affineTransform = area.transform(in: .local) {
                //     affineTransform.matrix4x4
                //     playerEntity.setTransformMatrix(.init(affineTransform), relativeTo: nil)
                // } else {
                //     print("Failed to get local area transform")
                // }
                // playerEntity.setTransformMatrix(area.transform(in: .global)?.matrix4x4)
            }
            update: { content in
                // playerEntity.setFrameSize(size: .init(width: proxy.size.width, height: proxy.size.height))
                // playerEntity.setTransformMatrix(.init(proxy.transform(in: .global)!), relativeTo: root)
                // let newFrame = content.convert(proxy.frame(in: .global), from: .global, to: .scene)
                // playerEntity.setScale([newFrame.extents.x, newFrame.extents.y, newFrame.extents.z], relativeTo: root)
                let baseTranslation = anchor.transform.translation
                print("Anchor translation: \(baseTranslation)")
                root.transform.translation = .init(
                    x: baseTranslation.x + settings.translateX,
                    y: baseTranslation.y + settings.translateY,
                    z: baseTranslation.z + settings.translateZ
                )
            }
            .onChange(of: settings.stereoOn, initial: true) {
                playerEntity.setStereo(settings.stereoOn)
            }
            .onChange(of: settings.paused, initial: true) {
                playerEntity.paused = settings.paused
            }
            .onDisappear {
                print("Disappeared")
                print("Cleaning up resources")
                appModel.videoModel.cleanup()
            }
            .gesture(
                TapGesture()
                    .targetedToEntity(root)
                    .onEnded { event in
                        print("Tap gesture received: \(event.gestureValue)")
                        Task { @MainActor in
                            switch appModel.mainWindowState {
                            case .closed:
                                print("Main window is closed, bringing it up now.")
                                appModel.mainWindowState = .inTransition
                                openWindow(id: appModel.mainWindowID)
                            case .inTransition:
                                // do nothing
                                print("Main window in transition, do nothing")
                                break
                            case .open:
                                print("Main window is open, closing it now.")
                                dismissWindow(id: appModel.mainWindowID)
                            }
                        }
                    }
            )
        }
    }
}
#endif
