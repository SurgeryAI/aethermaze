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
                // Retro Top HUD Bar
                HStack(spacing: 15) {
                    Spacer()
                    Group {
                        Text("SCORE: \(String(format: "%05d", gameCoordinator.score))")
                        Text("|")
                            .opacity(0.5)
                        Text("TIME: \(timeString(from: gameCoordinator.elapsedTime))")
                        Text("|")
                            .opacity(0.5)
                        Text("LVL: \(String(format: "%02d", gameCoordinator.currentLevel))")
                        Text("|")
                            .opacity(0.5)
                        Text("MARBLES: \(String(format: "%02d", gameCoordinator.marblesUsed))")
                    }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    Spacer()
                }
                .padding(.vertical, 16)
                .padding(.top, 20)  // Extra padding for notch/status bar
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
                                    .frame(width: 30, alignment: .leading)
                                Spacer()
                                Text("\(score)")
                            }
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.green)
                            .frame(width: 200)
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

                // Decrease divisor to INCREASE sensitivity (steeper angle for same tilt)
                let multiplier: Float = 25.0  // Reduced sensitivity (was 10.0)
                let pitch = Double(g.z / multiplier)  // Forward/Back
                let roll = Double(g.x / multiplier)  // Left/Right

                let rotation =
                    simd_quatf(angle: Float(pitch), axis: [1, 0, 0])
                    * simd_quatf(angle: Float(-roll), axis: [0, 0, 1])

                // Smoothly animate
                // Note: move(to: ...) is better for smoothing if avail, but setting property works for 60fps too
                gameAnchor.transform.rotation = rotation
                if let marble = uiView.scene.findEntity(named: "Marble") as? ModelEntity {

                    // [NEW] Audio Updates
                    // Ensure engine connects if needed (lazy start)
                    SoundManager.shared.startEngine()

                    if let velocity = marble.physicsMotion?.linearVelocity {
                        let speed = length(velocity)
                        SoundManager.shared.updateRollingSound(velocity: speed)
                    }

                    // Check if one is Marble and other is DeathPlane or WinZone
                    // ... (keep existing Logic if it was here, or we are adding this to the frame update)
                }
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

        // Calculate Rectangular Dimensions
        // Standard Portrait Ratio ~1.5 to 1.8
        let baseSize = 5 + gameCoordinator.currentLevel
        let cols = baseSize
        let rows = Int(Double(baseSize) * 1.5)  // 50% taller than wide

        let generator = MazeGenerator()
        generator.buildLevel(
            level: gameCoordinator.currentLevel, width: cols, height: rows, parent: gameAnchor)

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

        // Adjust camera based on larger dimension (Height)
        let levelWidth = Float(cols)
        let levelHeight = Float(rows)
        let maxDim = max(levelWidth, levelHeight)

        // Level size determines the base scale
        let camHeight = max(15.0, maxDim * 2.0)  // Higher up
        let camDist = max(5.0, maxDim * 0.8)  // Closer horizontally (steeper angle)

        // Attach Camera to GameAnchor so it moves WITH the board tilt.
        // This makes the board look stationary on screen, but Gravity (World) will change relative to it.
        gameAnchor.addChild(camera)

        camera.look(
            at: [Float(levelWidth) / 2.0, 0.0, Float(levelHeight) / 2.0],
            from: [Float(levelWidth) / 2.0, Float(camHeight), Float(camDist)],
            relativeTo: gameAnchor)

        // Remove separate cameraAnchor
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

// Helper formats time
func timeString(from timeInterval: TimeInterval) -> String {
    let minutes = Int(timeInterval) / 60
    let seconds = Int(timeInterval) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

// Helper Component to store level info on the Anchor
struct LevelComponent: Component {
    var level: Int
}
