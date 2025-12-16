import ARKit  // ✅ FIXED: Added ARKit import
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
                HStack {
                    Text("Level \(gameCoordinator.currentLevel)")
                        .font(.largeTitle)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                    Spacer()
                }

                Spacer()

                if gameCoordinator.gameState == .gameOver {
                    Text("GAME OVER")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.red)
                        .padding()
                        .background(.black.opacity(0.7))
                        .cornerRadius(20)
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

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // This runs whenever the MotionController updates or GameCoordinator updates

        // Check if level changed or restart requested
        if gameCoordinator.gameState == .levelComplete {
            // Wait a bit handled in coordinator, but we might want to prevent movement?
        }

        // If the coordinate signals a "reset" (we track level changes via a local var in coordinator if needed,
        // but RealityKit views are tricky to "rebuild".
        // For this prototype, if the level in coordinator != the level we built, we rebuild.
        // However, updateUIView is called frequently. We need a way to detect "New Level" trigger.
        // A simple way is to check the anchor name or a tag, OR just rebuild if the scene is empty.

        // Simple Reset Logic:
        // If the gameCoordinator.gameState just switched to .playing (after a win/loss), we might need to reset.
        // But for "Next Level", we genuinely need to rebuild.

        if let gameAnchor = uiView.scene.findEntity(named: anchorName) as? AnchorEntity {

            // Helper to check if we need to rebuild the level (e.g. level index mismatch)
            let currentBuiltLevel = gameAnchor.components[LevelComponent.self]?.level ?? -1
            if currentBuiltLevel != gameCoordinator.currentLevel {
                uiView.scene.removeAnchor(gameAnchor)
                setupGame(arView: uiView)
                return
            }

            // Motion Handling (Tilt the Maze)
            // Only tilt if playing
            if gameCoordinator.gameState == .playing {
                let g = motionController.currentGravity

                let multiplier: Float = 25.0
                let pitch = Double(g.z / multiplier)  // Forward/Back
                let roll = Double(g.x / multiplier)  // Left/Right

                let rotation =
                    simd_quatf(angle: Float(pitch), axis: [1, 0, 0])
                    * simd_quatf(angle: Float(-roll), axis: [0, 0, 1])

                // Smoothly animate
                // Note: move(to: ...) is better for smoothing if avail, but setting property works for 60fps too
                gameAnchor.transform.rotation = rotation
            }

            // Death/Win Logic Handling is done via Event Subscription in makeCoordinator
        } else {
            // If anchor missing, build it
            setupGame(arView: uiView)
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

        let generator = MazeGenerator()
        generator.buildLevel(level: gameCoordinator.currentLevel, parent: gameAnchor)

        // Lighting
        let mainLight = DirectionalLight()
        mainLight.light.intensity = 2000
        mainLight.light.isRealWorldProxy = true
        mainLight.shadow?.shadowProjection = .automatic(maximumDistance: 10)
        mainLight.shadow?.depthBias = 1
        mainLight.look(at: [0, 0, 0], from: [0, 5, 2], relativeTo: gameAnchor)
        gameAnchor.addChild(mainLight)

        // Camera
        let camera = PerspectiveCamera()
        let levelSize = Float(5 + gameCoordinator.currentLevel * 2)
        // Adjust camera based on level size
        let camHeight = max(8.0, levelSize * 1.2)
        let camDist = max(8.0, levelSize * 1.2)

        // Attach Camera to GameAnchor so it moves WITH the board tilt.
        // This makes the board look stationary on screen, but Gravity (World) will change relative to it.
        gameAnchor.addChild(camera)

        camera.look(
            at: [levelSize / 2.0, 0.0, levelSize / 2.0],
            from: [levelSize / 2.0, camHeight, camDist],
            relativeTo: gameAnchor)

        // Remove separate cameraAnchor
        // let cameraAnchor = AnchorEntity(world: [0, 0, 0])
        // cameraAnchor.addChild(camera)
        // arView.scene.addAnchor(cameraAnchor)
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
                    HapticManager.shared.playSuccessHaptic()  // [NEW] Haptic
                    DispatchQueue.main.async {
                        gameCoordinator.nextLevel()
                    }
                }

                // Wall Collision
                if (entityA.name == "Marble" && entityB.name == "Wall")
                    || (entityB.name == "Marble" && entityA.name == "Wall")
                {
                    HapticManager.shared.playCollisionHaptic()
                }
            }
        }
    }
}

// Helper Component to store level info on the Anchor
struct LevelComponent: Component {
    var level: Int
}
