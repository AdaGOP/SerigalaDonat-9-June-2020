//
//  GameViewController.swift
//  Serigaladonat
//
//  Created by David Gunawan on 09/06/20.
//  Copyright © 2020 David Gunawan. All rights reserved.
//

import UIKit
import QuartzCore
import SceneKit

struct GameBitMask{
    static let wolf = 1 << 1
    static let land = 1 << 2
    static let donut = 1 << 3
}


enum ParticleType: Int,CaseIterable{
    case collect = 0
    case walkDust
}

class GameViewController: UIViewController {
    
    private var scnView: SCNView!
    private var scene: SCNScene?
    private var player: Player?
    var hud: HUD?
    
    private let velocityMultiplier: CGFloat = 0.0016
    
    
    // Camera and targets
    private var cameraNode = SCNNode()
    private var lookAtTarget = SCNNode()
    private var activeCamera: SCNNode?
    static let CameraOrientationSensitivity: Float = 0.05
    
    //Particles
    private var particles = [SCNParticleSystem](repeating: SCNParticleSystem(), count: ParticleType.allCases.count)
    
    var cameraDirection = vector_float2.zero {
        didSet {
            let l = simd_length(cameraDirection)
            if l > 1.0 {
                cameraDirection *= 1 / 1
            }
            cameraDirection.y = 0
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    
        
        setupWorld()
        setupPlayer()
        setupDonut()
        loadCamera()
        setupParticle()
        
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        hud = HUD(size: view.bounds.size)
        hud?.joyStick.trackingHandler = updatePlayerPosition
        
        hud?.joyStick.stopHandler = { [weak self] in
            self?.updatePlayerState(.idle)
        }
        
        hud?.joyStick.beginHandler = { [weak self] in
            self?.updatePlayerState(.running)
        }
        
        scnView.overlaySKScene = hud?.scene
    }
    
    func setupWorld() {
        scnView = (self.view as! SCNView)
        scene = SCNScene(named: "art.scnassets/GameScene.scn")!
        scene!.background.contents = UIImage(named: "art.scnassets/textures/Background_sky")
        scene?.physicsWorld.contactDelegate = self
        
        scnView.scene = scene
        scnView.allowsCameraControl = false
        scnView.showsStatistics = true
        
        let floor = scene?.rootNode.childNode(withName: "Grass", recursively: true)
        floor?.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        floor?.physicsBody?.categoryBitMask = GameBitMask.land
        floor?.physicsBody?.collisionBitMask = GameBitMask.wolf
    }
    
    func setupPlayer() {
        player = Player()
        player?.physicsBody = SCNPhysicsBody(type: .dynamic, shape: nil)
        player?.physicsBody?.categoryBitMask = GameBitMask.wolf
        player?.physicsBody?.collisionBitMask = GameBitMask.land | GameBitMask.donut
        player?.physicsBody?.contactTestBitMask = GameBitMask.donut
        scene?.rootNode.addChildNode(player!)
    }
    
    func setupDonut(){
        for i in 1...20{
            let donut = Donut()
            let x = Int.random(in: -10...10)
            let z = Int.random(in: -10...10)
            donut.position = SCNVector3(x,0,z)
            self.scene?.rootNode.addChildNode(donut)
        }
    }
    
    func setupParticle(){
        particles[ParticleType.collect.rawValue] = SCNParticleSystem.loadParticleSystems(atPath: "art.scnassets/Particles/Collect/collect.scnp").first!
    }
    
    

    
    func updatePlayerPosition(_ josyStickData: AnalogJoystickData) {
        player?.updateWolfPosition(joyStickData: josyStickData, velocityMultiplier: velocityMultiplier)
    }
    
    func updatePlayerState(_ state: WolfState) {
        player?.changeWolf(state)
    }
    
    func collect(_ donut: Donut){
        donut.runAction(SCNAction.playAudio(SCNAudioSource(fileNamed: "collect.mp3")!, waitForCompletion: true))
        donut.particleEmitter.addParticleSystem(particles[ParticleType.collect.rawValue])
        donut.childNode(withName: "donut", recursively: true)?.isHidden = true
    }
    
    func loadCamera() {
        //The lookAtTarget node will be placed slighlty above the character using a constraint
        weak var weakSelf = self

        self.lookAtTarget.constraints = [SCNTransformConstraint.positionConstraint(
                                        inWorldSpace: true, with: { (_ node: SCNNode, _ position: SCNVector3) -> SCNVector3 in
            guard let strongSelf = weakSelf else { return position }

            var worldPosition = strongSelf.player!.simdWorldPosition
            worldPosition.y = strongSelf.player!.basetAltitude + 0.5
            return SCNVector3(worldPosition)
        })]

        scene?.rootNode.addChildNode(lookAtTarget)

        scene?.rootNode.enumerateHierarchy({(_ node: SCNNode, _ _: UnsafeMutablePointer<ObjCBool>) -> Void in
            if node.camera != nil {
                self.setupFollowCamera(node)
            }
        })

        self.cameraNode.camera = SCNCamera()
        self.cameraNode.name = "mainCamera"
        self.cameraNode.camera!.zNear = 0.1
        self.cameraNode.camera!.zFar = 200
        scene?.rootNode.addChildNode(cameraNode)
    }
    
    func setupFollowCamera(_ cameraNode: SCNNode) {
        // look at "lookAtTarget"
        let lookAtConstraint = SCNLookAtConstraint(target: self.lookAtTarget)
        lookAtConstraint.influenceFactor = 0.07
        lookAtConstraint.isGimbalLockEnabled = true

        // distance constraints
        let follow = SCNDistanceConstraint(target: self.lookAtTarget)
        let distance = CGFloat(simd_length(cameraNode.simdPosition))
        follow.minimumDistance = distance
        follow.maximumDistance = distance

        // configure a constraint to maintain a constant altitude relative to the character
        let desiredAltitude = abs(cameraNode.simdWorldPosition.y)
        weak var weakSelf = self

        let keepAltitude = SCNTransformConstraint.positionConstraint(inWorldSpace: true, with: {(_ node: SCNNode, _ position: SCNVector3) -> SCNVector3 in
                guard let strongSelf = weakSelf else { return position }
                var position = float3(position)
                position.y = strongSelf.player!.basetAltitude + desiredAltitude
                return SCNVector3( position )
            })

        let accelerationConstraint = SCNAccelerationConstraint()
        accelerationConstraint.maximumLinearVelocity = 1500.0
        accelerationConstraint.maximumLinearAcceleration = 50.0
        accelerationConstraint.damping = 0.05

        // use a custom constraint to let the user orbit the camera around the character
        let transformNode = SCNNode()
        let orientationUpdateConstraint = SCNTransformConstraint(inWorldSpace: true) { (_ node: SCNNode, _ transform: SCNMatrix4) -> SCNMatrix4 in
            guard let strongSelf = weakSelf else { return transform }
            if strongSelf.activeCamera != node {
                return transform
            }

            // Slowly update the acceleration constraint influence factor to smoothly reenable the acceleration.
            accelerationConstraint.influenceFactor = min(1, accelerationConstraint.influenceFactor + 0.01)

            let targetPosition = strongSelf.lookAtTarget.presentation.simdWorldPosition
            let cameraDirection = strongSelf.cameraDirection
            if cameraDirection.allZero() {
                return transform
            }

            // Disable the acceleration constraint.
            accelerationConstraint.influenceFactor = 0

            let characterWorldUp = strongSelf.player!.presentation.simdWorldUp

            transformNode.transform = transform

            let q = simd_mul(
                simd_quaternion(GameViewController.CameraOrientationSensitivity * cameraDirection.x, characterWorldUp),
                simd_quaternion(GameViewController.CameraOrientationSensitivity * cameraDirection.y, transformNode.simdWorldRight)
            )

            transformNode.simdRotate(by: q, aroundTarget: targetPosition)
            return transformNode.transform
        }
        cameraNode.constraints = [follow, keepAltitude, accelerationConstraint, orientationUpdateConstraint, lookAtConstraint]
    }
    
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

}

extension GameViewController: SCNPhysicsContactDelegate{
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        if let donut = contact.nodeB.parent as? Donut{
            collect(donut)
        }
    }
}

extension SCNParticleSystem{
    static func loadParticleSystems(atPath path: String) -> [SCNParticleSystem] {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()

        let fileName = url.lastPathComponent
        let ext: String = url.pathExtension

        if ext == "scnp" {
            return [SCNParticleSystem(named: fileName, inDirectory: directory.relativePath)!]
        } else {
            var particles = [SCNParticleSystem]()
            let scene = SCNScene(named: fileName, inDirectory: directory.relativePath, options: nil)
            scene!.rootNode.enumerateHierarchy({(_ node: SCNNode, _ _: UnsafeMutablePointer<ObjCBool>) -> Void in
                if node.particleSystems != nil {
                    particles += node.particleSystems!
                }
            })
            return particles
        }
    }
}
