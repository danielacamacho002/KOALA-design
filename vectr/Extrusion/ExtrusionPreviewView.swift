//
//  ExtrusionPreviewView.swift
//  vectr
//

import SceneKit
import SwiftUI

struct ExtrusionPreviewView: UIViewRepresentable {
    let stroke: VectorStroke
    @Binding var depth: CGFloat

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .systemGroupedBackground
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        context.coordinator.sceneView = view
        context.coordinator.rebuild(stroke: stroke, depth: depth)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.rebuild(stroke: stroke, depth: depth)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var sceneView: SCNView?
        private var contentNode: SCNNode?

        func rebuild(stroke: VectorStroke, depth: CGFloat) {
            guard let sceneView else { return }
            let scene = SCNScene()
            sceneView.scene = scene

            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 120, 200)
            cameraNode.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(cameraNode)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 400
            scene.rootNode.addChildNode(ambient)

            contentNode?.removeFromParentNode()
            if let node = PathExtruder.makeNode(from: stroke, depth: depth) {
                scene.rootNode.addChildNode(node)
                contentNode = node
            }
        }
    }
}
