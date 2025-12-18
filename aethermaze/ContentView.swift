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
                HStack(spacing: 0) {
                    Group {
                        HUDItem(
                            label: "SCORE", value: String(format: "%05d", gameCoordinator.score))
                        HUDDivider()
                        HUDItem(label: "TIME", value: timeString(from: gameCoordinator.elapsedTime))
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
        } else {
            // Stop sound when not playing
            SoundManager.shared.updateRollingSound(velocity: 0)
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
        mainLight.light.intensity = 3000  // Increased intensity
        mainLight.light.isRealWorldProxy = true
        mainLight.shadow?.shadowProjection = .automatic(maximumDistance: 10)
        mainLight.shadow?.depthBias = 1
        mainLight.look(at: [0, 0, 0], from: [0, 5, 2], relativeTo: gameAnchor)
        gameAnchor.addChild(mainLight)

        // [NEW] Fill Light to reduce harsh shadows
        let fillLight = DirectionalLight()
        fillLight.light.intensity = 800
        // Point from the opposite-ish side
        fillLight.look(at: [0, 0, 0], from: [0, -5, 2], relativeTo: gameAnchor)
        gameAnchor.addChild(fillLight)

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
                if (entityA.name == "RefinedWalls" && entityB.name == "Marble")
                    || (entityB.name == "RefinedWalls" && entityA.name == "Marble")
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
