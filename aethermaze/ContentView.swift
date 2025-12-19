import ARKit
import Combine
import RealityKit
import SwiftUI

struct ContentView: View {
    @StateObject private var motionController = MotionController()
    @StateObject private var gameCoordinator = GameCoordinator()  // [NEW] Coordinator

    var body: some View {
        ZStack {
            // ARViewContainer hosts the 3D scene
            ARViewContainer(gameCoordinator: gameCoordinator, motionController: motionController)
                .edgesIgnoringSafeArea(.all)

            // UI Overlay
            VStack {
                // Retro Top HUD Bar
                HStack(spacing: 0) {
                    Group {
                        HUDItem(
                            label: "SCORE", value: String(format: "%05d", gameCoordinator.score))
                        HUDDivider()
                        HUDItem(
                            label: "TIME", value: timeString(from: gameCoordinator.timeRemaining)
                        )
                        .foregroundColor(gameCoordinator.timeRemaining < 10 ? .red : .green)
                        .shadow(
                            color: gameCoordinator.timeRemaining < 10 ? .red : .clear, radius: 2)
                        HUDDivider()
                        HUDItem(
                            label: "LVL",
                            value: String(format: "%02d", gameCoordinator.currentLevel))
                        HUDDivider()
                        HUDItem(
                            label: "MARBLES",
                            value: "\(gameCoordinator.marblesUsed)/\(gameCoordinator.maxMarbles)")
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
                .background(Color.black.opacity(0.9))
                .edgesIgnoringSafeArea(.top)

                // Add a divider line for that extra retro feel
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(.green.opacity(0.5))

                Spacer()

                if gameCoordinator.gameState == .gameOver {
                    VStack(spacing: 20) {
                        Text("GAME OVER")
                            .font(.system(size: 40, weight: .heavy, design: .monospaced))
                            .foregroundColor(.red)
                            .shadow(color: .red, radius: 2)

                        Text("SCORE: \(gameCoordinator.score)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)

                        Divider()
                            .overlay(.white)

                        Text("HIGH SCORES")
                            .font(.headline)
                            .foregroundColor(.green)
                            .padding(.top)

                        ForEach(Array(gameCoordinator.getHighScores().enumerated()), id: \.offset) {
                            index, score in
                            HStack {
                                Text("\(index + 1).")
                                    .fixedSize(horizontal: true, vertical: false)
                                Spacer()
                                Text("\(score)")
                            }
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal)
                        }

                        Button {
                            gameCoordinator.resetGame()
                        } label: {
                            Text("TRY AGAIN")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding()
                                .frame(width: 200)
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                        .padding(.top, 20)
                    }
                    .padding(30)
                    .background(Color.black.opacity(0.95))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.green, lineWidth: 2)
                    )
                    .transition(.scale)
                } else if gameCoordinator.gameState == .levelComplete {
                    Text("LEVEL COMPLETE!")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.green)
                        .padding()
                        .background(.black.opacity(0.7))
                        .cornerRadius(20)
                }
            }
            .padding()
        }
        // Capture keyboard events for the Simulator
        .focusable()
        .onKeyPress { press in
            switch press.key {
            case .upArrow:
                motionController.updateKeyboardTilt(pitchDelta: -1.0, rollDelta: 0)
                return .handled
            case .downArrow:
                motionController.updateKeyboardTilt(pitchDelta: 1.0, rollDelta: 0)
                return .handled
            case .leftArrow:
                motionController.updateKeyboardTilt(pitchDelta: 0, rollDelta: -1.0)
                return .handled
            case .rightArrow:
                motionController.updateKeyboardTilt(pitchDelta: 0, rollDelta: 1.0)
                return .handled
            case .escape:
                motionController.resetKeyboardTilt()
                return .handled
            default:
                return .ignored
            }
        }
    }
}

// Standard bridge between SwiftUI and RealityKit
struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var gameCoordinator: GameCoordinator
    @ObservedObject var motionController: MotionController

    // We use a static key to find the anchor later
    let anchorName = "GameAnchor"

    func makeUIView(context: Context) -> ARView {
        // 1. Create the ARView in Non-AR mode (Standard 3D game mode)
        let arView = ARView(frame: .zero)

        #if os(iOS)
            arView.cameraMode = .nonAR
            arView.automaticallyConfigureSession = true
        #endif

        // 2. Setup the Game Scene
        setupGame(arView: arView)

        // 3. Setup Physics subscription
        context.coordinator.subscribeToEvents(arView: arView, gameCoordinator: gameCoordinator)

        // 4. Start Audio Engine
        SoundManager.shared.startEngine()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Find or create GameAnchor
        guard let gameAnchor = uiView.scene.findEntity(named: anchorName) as? AnchorEntity else {
            setupGame(arView: uiView)
            return
        }

        // Check for level change
        let currentBuiltLevel = gameAnchor.components[LevelComponent.self]?.level ?? -1
        if currentBuiltLevel != gameCoordinator.currentLevel {
            uiView.scene.removeAnchor(gameAnchor)
            setupGame(arView: uiView)
            return
        }

        // Motion Handling (Tilt the Maze)
        if gameCoordinator.gameState == .playing {
            let g = motionController.currentGravity
            let multiplier: Float = 25.0

            let combinedPitch = Double(g.z / multiplier) + Double(motionController.keyboardPitch)
            let combinedRoll = Double(g.x / multiplier) + Double(motionController.keyboardRoll)

            let rotation =
                simd_quatf(angle: Float(combinedPitch), axis: [1, 0, 0])
                * simd_quatf(angle: Float(-combinedRoll), axis: [0, 0, 1])

            gameAnchor.transform.rotation = rotation

            // Optimized: Find marble once or track it
            if let marble = uiView.scene.findEntity(named: "Marble") as? ModelEntity {
                if let velocity = marble.physicsMotion?.linearVelocity {
                    let speed = length(velocity)
                    SoundManager.shared.updateRollingSound(velocity: speed)
                    HapticManager.shared.playRollingHaptic(intensity: speed)
                }
            }
            // Stop sound when not playing
            SoundManager.shared.updateRollingSound(velocity: 0)
        }

        // Shard Animation logic (Rotation)
        // Find all shards and rotate them
        gameAnchor.children.forEach { entity in
            if entity.name.hasPrefix("Shard_") {
                let currentRotation = entity.transform.rotation
                let rotationDelta = simd_quatf(angle: 0.05, axis: [0, 1, 0])
                entity.transform.rotation = currentRotation * rotationDelta

                // Bobbing effect
                let time = Float(Date().timeIntervalSince1970)
                let bobOffset = sin(time * 2.0) * 0.04
                entity.position.y = 0.3 + bobOffset
            }
        }
    }

    private func setupGame(arView: ARView) {
        // clear old
        arView.scene.anchors.removeAll()

        let gameAnchor = AnchorEntity(world: [0, 0, 0])
        gameAnchor.name = anchorName
        // Store current level in a component so we know when to rebuild
        gameAnchor.components.set(LevelComponent(level: gameCoordinator.currentLevel))

        arView.scene.addAnchor(gameAnchor)

        // Calculate Rectangular Dimensions
        // Standard Portrait Ratio ~1.5 to 1.8
        let baseSize = 5 + gameCoordinator.currentLevel
        let cols = baseSize
        let rows = Int(Double(baseSize) * 1.5)  // 50% taller than wide

        let generator = MazeGenerator()
        generator.buildLevel(
            level: gameCoordinator.currentLevel, width: cols, height: rows, parent: gameAnchor)
        // Calculate dimensions
        let levelWidth = Float(cols)
        let levelHeight = Float(rows)
        let maxDim = max(levelWidth, levelHeight)
        let centerX: Float = (levelWidth - 1.0) / 2.0
        let centerZ: Float = (levelHeight - 1.0) / 2.0

        // Lighting centered on the maze for optimal shadow distribution
        let mainLight = DirectionalLight()
        mainLight.look(
            at: [centerX, 0.0, centerZ], from: [centerX + 5.0, 15.0, centerZ + 8.0],
            relativeTo: gameAnchor)
        mainLight.light.intensity = 3500  // Reduced for less contrast
        mainLight.light.isRealWorldProxy = false
        mainLight.shadow?.shadowProjection = .automatic(maximumDistance: Float(maxDim) * 2.0)
        mainLight.shadow?.depthBias = 0.5  // Softer shadows
        gameAnchor.addChild(mainLight)

        // Fill Light from above-ish side for wall visibility
        let fillLight = DirectionalLight()
        fillLight.look(
            at: [centerX, 0.0, centerZ], from: [centerX, 8.0, centerZ - 8.0],
            relativeTo: gameAnchor)
        fillLight.light.intensity = 1800
        gameAnchor.addChild(fillLight)

        // Front Fill Light to soften shadows further (Replaces AmbientLight which is not in RealityKit)
        let frontFill = DirectionalLight()
        frontFill.look(
            at: [centerX, 0.0, centerZ], from: [centerX, 5.0, centerZ + 15.0],
            relativeTo: gameAnchor)
        frontFill.light.intensity = 1000
        gameAnchor.addChild(frontFill)

        // Camera framing to maximize screen real estate
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60  // Tighter FOV for more scale

        let camHeight = max(10.0, maxDim * 1.4)  // Moved closer to the maze
        let camDist = max(0.0, maxDim * 0.1)  // Maintain top-down angle

        gameAnchor.addChild(camera)
        camera.look(
            at: [centerX, -0.5, centerZ],
            from: [centerX, camHeight, centerZ + camDist],
            relativeTo: gameAnchor)

        // Branded Background Backdrop (App Icon Nebula)
        let backgroundRoot = Entity()
        backgroundRoot.name = "BackgroundSystem"

        let planeMesh = MeshResource.generatePlane(width: 100, depth: 100)
        var bgMat = UnlitMaterial()

        if let texture = try? TextureResource.load(named: "AppBackground") {
            // Use 0.95 alpha to keep it slightly recessed/dark
            bgMat.color = .init(tint: .white.withAlphaComponent(0.95), texture: .init(texture))
        } else {
            // Fallback to the deep nebula blue if texture fails
            bgMat.color = .init(tint: .init(red: 0.05, green: 0.1, blue: 0.3, alpha: 1.0))
        }

        let backgroundPlane = ModelEntity(mesh: planeMesh, materials: [bgMat])
        // Position it far below the maze to create scale and a sense of 'floating' in a larger world
        backgroundPlane.position = [0, -15.0, 0]
        // Match the isometric/tilted vibe of the icon art
        backgroundPlane.orientation = simd_quatf(angle: .pi / 16, axis: [1, 0, 0])

        backgroundRoot.addChild(backgroundPlane)
        backgroundRoot.position = [centerX, 0, centerZ]
        gameAnchor.addChild(backgroundRoot)
        // let cameraAnchor = AnchorEntity(world: [0, 0, 0])
        // cameraAnchor.addChild(camera)
    }

    // Custom Coordinator to handle Physics Events
    func makeCoordinator() -> ARCoordinator {
        return ARCoordinator()
    }

    class ARCoordinator {
        var subscription: Cancellable?

        func subscribeToEvents(arView: ARView, gameCoordinator: GameCoordinator) {
            subscription = arView.scene.subscribe(to: CollisionEvents.Began.self) { event in
                let entityA = event.entityA
                let entityB = event.entityB

                // Check if one is Marble and other is DeathPlane or WinZone
                if (entityA.name == "Marble" && entityB.name == "DeathPlane")
                    || (entityB.name == "Marble" && entityA.name == "DeathPlane")
                {
                    print("Marble fell! Restarting level...")
                    HapticManager.shared.playFailureHaptic()  // [NEW] Haptic
                    DispatchQueue.main.async {
                        gameCoordinator.restartLevel()
                        // Force reset of physics position?
                        // The UpdateUIView loop will catch the "restart" by rebuilding if we change IDs,
                        // OR we can manually reset position here.
                        // Simplest for prototype: GameCoordinator toggle triggers UI update,
                        // UpdateUIView sees state change.
                        // Actually, purely resetting position is better than full rebuild for same level.
                        if let marble = arView.scene.findEntity(named: "Marble") as? ModelEntity {
                            // Stop momentum
                            marble.physicsBody?.mode = .static  // Temporary freeze
                            marble.position = [0, 0.2, 0]
                            marble.physicsBody?.mode = .dynamic
                        }
                    }
                }

                if (entityA.name == "Marble" && entityB.name == "WinZone")
                    || (entityB.name == "Marble" && entityA.name == "WinZone")
                {
                    print("Level Complete!")
                    HapticManager.shared.playSuccessHaptic()

                    if let marble = (entityA.name == "Marble" ? entityA : entityB) as? ModelEntity {
                        // Playful Jump
                        marble.applyImpulse([0, 1.5, 0], at: [0, 0, 0], relativeTo: nil)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        gameCoordinator.nextLevel()
                    }
                }

                // Wall Collision
                if (entityA.name == "RefinedWalls" && entityB.name == "Marble")
                    || (entityB.name == "RefinedWalls" && entityA.name == "Marble")
                {
                    HapticManager.shared.playCollisionHaptic()
                }

                // Shard Collection
                if (entityA.name == "Marble" && entityB.name.hasPrefix("Shard_"))
                    || (entityB.name == "Marble" && entityA.name.hasPrefix("Shard_"))
                {
                    let shard = entityA.name.hasPrefix("Shard_") ? entityA : entityB
                    print("Shard collected: \(shard.name)")

                    DispatchQueue.main.async {
                        gameCoordinator.addTime(15)
                        HapticManager.shared.playSuccessHaptic()

                        // "Pop" animation before removal
                        shard.move(
                            to: Transform(
                                scale: [1.5, 1.5, 1.5], rotation: shard.transform.rotation,
                                translation: shard.transform.translation), relativeTo: shard.parent,
                            duration: 0.2)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            shard.removeFromParent()
                        }
                    }
                }
            }
        }
    }
}

// Helper formats time
func timeString(from timeInterval: TimeInterval) -> String {
    let minutes = Int(timeInterval) / 60
    let seconds = Int(timeInterval) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

// [NEW] HUD Subviews for better layout control
struct HUDItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .opacity(0.7)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
        }
        .foregroundColor(.green)
        .frame(maxWidth: .infinity)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
}

struct HUDDivider: View {
    var body: some View {
        Rectangle()
            .frame(width: 1, height: 25)
            .foregroundColor(.green.opacity(0.3))
            .padding(.horizontal, 4)
    }
}

// Helper Component to store level info on the Anchor
struct LevelComponent: Component {
    var level: Int
}
