import ARKit
import Combine
import RealityKit
import SwiftUI

struct ContentView: View {
    @StateObject private var motionController = MotionController()
    @StateObject private var gameCoordinator = GameCoordinator()  // [NEW] Coordinator

    @AppStorage("isSoundEnabled") private var isSoundEnabled = true
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true

    private let maxLevelCount = 10
    
    // State for urgency pulse animation
    @State private var urgencyPulse = false

    // State for shard collection point display
    @State private var showShardBonus = false
    @State private var shardBonusOffset: CGFloat = 0

    // Game-feel state
    @State private var shakeOffset: CGSize = .zero      // Screen shake on fall
    @State private var damageFlash: Double = 0          // Red flash on fall
    @State private var showLevelBanner = false          // "LEVEL N" intro banner
    @State private var bannerLevel = 1

    var body: some View {
        ZStack {
            // World layer — slightly over-scaled so screen-shake never reveals black edges.
            ARViewContainer(gameCoordinator: gameCoordinator, motionController: motionController)
                .ignoresSafeArea()
                .scaleEffect(1.05)
                .offset(shakeOffset)

            // Damage flash when the marble falls
            Rectangle()
                .fill(Color.red)
                .opacity(damageFlash)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Soft urgency vignette when time is critically low
            if gameCoordinator.timeRemaining <= 10 && gameCoordinator.gameState == .playing {
                RadialGradient(
                    colors: [.clear, .clear, Color.red.opacity(urgencyPulse ? 0.55 : 0.25)],
                    center: .center, startRadius: 120, endRadius: 520
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: urgencyPulse
                )
                .onAppear { urgencyPulse = true }
                .onDisappear { urgencyPulse = false }
            }

            // Floating "+score" shard pickup popup
            if showShardBonus && gameCoordinator.lastShardBonus > 0 {
                ShardBonusPopup(
                    bonus: gameCoordinator.lastShardBonus,
                    timeBonus: gameCoordinator.lastShardTimeBonus
                )
                .offset(y: shardBonusOffset)
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
            }

            // Top HUD + streak bar
            VStack(spacing: 10) {
                ModernHUD(game: gameCoordinator)

                if gameCoordinator.perfectStreak > 0 && gameCoordinator.gameState == .playing {
                    StreakBar(
                        streak: gameCoordinator.perfectStreak,
                        multiplier: gameCoordinator.currentMultiplier
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if gameCoordinator.currentLevel == maxLevelCount
                    && gameCoordinator.gameState == .playing
                {
                    FinalLevelBadge()
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            // Level intro banner
            if showLevelBanner {
                LevelBanner(level: bannerLevel)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            // Center overlays for level complete / game over / victory
            if gameCoordinator.gameState == .gameOver {
                GameOverCard(game: gameCoordinator)
                    .transition(.scale.combined(with: .opacity))
            } else if gameCoordinator.gameState == .levelComplete {
                LevelCompleteCard(game: gameCoordinator)
                    .transition(.scale.combined(with: .opacity))
            }

            // Bottom settings
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    ModernToggle(isOn: $isSoundEnabled, label: "SOUND", icon: "speaker.wave.2.fill")
                    ModernToggle(isOn: $isHapticsEnabled, label: "HAPTICS", icon: "hand.tap.fill")
                }
                .padding(.bottom, 8)
            }
            .allowsHitTesting(gameCoordinator.gameState != .gameOver)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: gameCoordinator.gameState)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: gameCoordinator.perfectStreak)
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
        .onChange(of: gameCoordinator.shardCollectionTrigger) { _, _ in
            // Animate shard bonus display
            shardBonusOffset = 0
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                showShardBonus = true
            }
            
            // Animate floating up
            withAnimation(.easeOut(duration: 1.2)) {
                shardBonusOffset = -50
            }
            
            // Hide after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showShardBonus = false
                }
            }
        }
        .onChange(of: isSoundEnabled) { _, newValue in
            SoundManager.shared.isSoundEnabled = newValue
        }
        .onChange(of: isHapticsEnabled) { _, newValue in
            HapticManager.shared.isHapticsEnabled = newValue
        }
        .onChange(of: gameCoordinator.fallTrigger) { _, _ in
            triggerFallFeedback()
        }
        .onChange(of: gameCoordinator.levelStartTrigger) { _, _ in
            announceLevel(gameCoordinator.currentLevel)
        }
        .onAppear {
            announceLevel(gameCoordinator.currentLevel)
        }
    }

    // MARK: - Game-feel helpers

    private func triggerFallFeedback() {
        // Quick red flash
        withAnimation(.easeOut(duration: 0.08)) { damageFlash = 0.45 }
        withAnimation(.easeOut(duration: 0.45).delay(0.08)) { damageFlash = 0 }

        // Decaying shake
        let kicks: [(CGSize, Double)] = [
            (CGSize(width: 10, height: -6), 0.0),
            (CGSize(width: -8, height: 5), 0.05),
            (CGSize(width: 5, height: -3), 0.10),
            (CGSize(width: -3, height: 2), 0.15),
            (CGSize(width: 0, height: 0), 0.20),
        ]
        for (offset, delay) in kicks {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.12, dampingFraction: 0.5)) {
                    shakeOffset = offset
                }
            }
        }
    }

    private func announceLevel(_ level: Int) {
        guard gameCoordinator.gameState == .playing else { return }
        bannerLevel = level
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            showLevelBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeOut(duration: 0.35)) {
                showLevelBanner = false
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

        // Check for level change. Only rebuild once we're actually playing again —
        // otherwise the next maze pops in behind the "Level Complete" card (currentLevel
        // is incremented before the celebration), killing the win animation.
        let currentBuiltLevel = gameAnchor.components[LevelComponent.self]?.level ?? -1
        if currentBuiltLevel != gameCoordinator.currentLevel
            && gameCoordinator.gameState == .playing
        {
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

            // [BOUNCE FIX] We physically tilt the floor by rotating the whole
            // anchor. The catch: the floor is a KINEMATIC body, so rotating the
            // anchor teleports it to its new pose each frame. A point at maze
            // distance r from the rotation axis heaves vertically by ~r·Δangle
            // per frame — and that vertical jolt kicks the DYNAMIC marble. The
            // farther the marble sits from the pivot, the harder the kick, which
            // is why the bouncing grew worse toward the far corner AND on higher
            // levels (bigger boards = bigger r).
            //
            // The robust fix: rotate about the MARBLE'S OWN position. Sitting on
            // the rotation axis, the floor directly beneath it never moves
            // vertically — zero heave at the marble, regardless of board size or
            // tilt angle. Because the camera/lights are rigid children of this
            // same anchor, only the *rotation* affects what's on screen (the
            // pivot translation shifts camera and maze together), so this stays
            // visually identical to before while removing the kick.
            var pivot: SIMD3<Float>
            if let marble = uiView.scene.findEntity(named: "Marble") {
                let p = marble.position(relativeTo: gameAnchor)
                pivot = SIMD3<Float>(p.x, 0, p.z)
            } else {
                // Fallback to maze center until the marble exists.
                let baseSize = 5 + gameCoordinator.currentLevel
                let cols = Float(baseSize)
                let rows = Float(Int(Double(baseSize) * 1.5))
                pivot = SIMD3<Float>((cols - 1.0) / 2.0, 0, (rows - 1.0) / 2.0)
            }

            var t = Transform()
            t.rotation = rotation
            t.translation = pivot - rotation.act(pivot)
            gameAnchor.transform = t
        }

        // Animation timing
        let time = Float(Date().timeIntervalSince1970)
        
        // Shard Animation logic (Rotation + Bobbing)
        gameAnchor.children.forEach { entity in
            if entity.name.hasPrefix("Shard_") {
                let currentRotation = entity.transform.rotation
                let rotationDelta = simd_quatf(angle: 0.06, axis: [0, 1, 0])  // Slightly faster spin
                entity.transform.rotation = currentRotation * rotationDelta

                // Enhanced bobbing with slight variation per shard
                let shardId = Float(entity.name.hashValue % 100) / 100.0
                let bobOffset = sin(time * 2.5 + shardId * 3.14) * 0.05
                entity.position.y = 0.32 + bobOffset
            }
        }
        
        // WinZone Beacon Animation (pulsing/bobbing)
        if let winZone = gameAnchor.findEntity(named: "WinZone") {
            if let beacon = winZone.findEntity(named: "WinBeacon") {
                // Pulse scale and bobbing for the beacon
                let pulseScale = 1.0 + sin(time * 3.0) * 0.15
                beacon.scale = SIMD3<Float>(repeating: Float(pulseScale))
                
                // Bobbing effect
                let bobOffset = sin(time * 2.0) * 0.08
                beacon.position.y = 0.45 + bobOffset
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

        // Velocity tracking for sound
        var lastMarblePosition: SIMD3<Float>?
        var lastUpdateTime: TimeInterval = 0
        private var updateSubscription: Cancellable?

        func subscribeToEvents(arView: ARView, gameCoordinator: GameCoordinator) {
            // 1. Collision Events
            subscription = arView.scene.subscribe(to: CollisionEvents.Began.self) { event in
                let entityA = event.entityA
                let entityB = event.entityB

                // DeathPlane / WinZone check
                if (entityA.name == "Marble" && entityB.name == "DeathPlane")
                    || (entityB.name == "Marble" && entityA.name == "DeathPlane")
                {
                    print("Marble fell! Restarting level...")
                    HapticManager.shared.playFailureHaptic()
                    SoundManager.shared.playFallSound()
                    DispatchQueue.main.async {
                        gameCoordinator.restartLevel()
                        if let marble = arView.scene.findEntity(named: "Marble") as? ModelEntity {
                            marble.physicsBody?.mode = .static
                            marble.position = [0, 0.2, 0]
                            // Clear any residual velocities to prevent unexpected bouncing
                            marble.components.set(PhysicsMotionComponent(linearVelocity: .zero, angularVelocity: .zero))
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
                    SoundManager.shared.playWallImpactSound()
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

            // 2. High-Frequency Update Loop (SceneEvents.Update)
            updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) {
                [weak self] _ in
                guard let self = self else { return }

                if let marble = arView.scene.findEntity(named: "Marble") as? ModelEntity,
                    gameCoordinator.gameState == .playing
                {

                    let currentTime = Date().timeIntervalSince1970
                    let currentPosition = marble.position(relativeTo: nil)

                    if let lastPos = self.lastMarblePosition {
                        let deltaTime = Float(currentTime - self.lastUpdateTime)
                        if deltaTime > 0 {
                            let deltaPosition = currentPosition - lastPos
                            let velocity = deltaPosition / deltaTime
                            let speed = length(velocity)

                            // 🔊 Update Rolling Sound (High Frequency)
                            SoundManager.shared.updateRollingSound(velocity: speed)

                            // 📳 Update Rolling Haptic
                            HapticManager.shared.playRollingHaptic(intensity: speed)
                        }
                    }

                    self.lastMarblePosition = currentPosition
                    self.lastUpdateTime = currentTime

                    // [FIX] Grounding force at 60Hz
                    // Increased from -8.0 to -15.0 for maximum stability
                    marble.addForce([0, -15.0, 0], relativeTo: nil)
                } else {
                    SoundManager.shared.checkRollingSoundTimeout()
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

// MARK: - Modern "Aether" Theme

enum Aether {
    static let cyan = Color(red: 0.22, green: 0.88, blue: 1.0)
    static let violet = Color(red: 0.66, green: 0.43, blue: 1.0)
    static let mint = Color(red: 0.30, green: 1.0, blue: 0.68)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.27)
    static let danger = Color(red: 1.0, green: 0.32, blue: 0.42)

    static let accent = LinearGradient(
        colors: [cyan, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let success = LinearGradient(
        colors: [mint, cyan], startPoint: .leading, endPoint: .trailing)
    static let heat = LinearGradient(
        colors: [amber, Color(red: 1.0, green: 0.45, blue: 0.3)],
        startPoint: .leading, endPoint: .trailing)
}

// Reusable frosted-glass surface
struct GlassBackground: View {
    var corner: CGFloat = 18
    var stroke: AnyShapeStyle = AnyShapeStyle(Color.white.opacity(0.12))

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

// MARK: - HUD

struct ModernHUD: View {
    @ObservedObject var game: GameCoordinator

    private var lowTime: Bool { game.timeRemaining <= 10 }
    private var marblesLeft: Int { max(0, game.maxMarbles - game.marblesUsed + 1) }

    var body: some View {
        HStack(spacing: 8) {
            StatPill(
                icon: "star.fill", label: "SCORE",
                value: "\(game.score)", tint: Aether.cyan)
            StatPill(
                icon: "crown.fill", label: "BEST",
                value: "\(game.bestScore)", tint: Aether.violet)
            StatPill(
                icon: "timer", label: "TIME",
                value: timeString(from: game.timeRemaining),
                tint: lowTime ? Aether.danger : Aether.mint,
                emphasized: lowTime)
            StatPill(
                icon: "flag.checkered", label: "LEVEL",
                value: "\(game.currentLevel)", tint: Aether.cyan)
            StatPill(
                icon: "circlebadge.2.fill", label: "LIVES",
                value: "\(marblesLeft)", tint: Aether.amber)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GlassBackground(corner: 22))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = Aether.cyan
    var emphasized: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.55))

            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .shadow(color: emphasized ? tint.opacity(0.9) : .clear, radius: 6)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(emphasized ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: emphasized)
    }
}

// MARK: - Streak Bar

struct StreakBar: View {
    let streak: Int
    let multiplier: Double
    @State private var glow = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Aether.heat)
                Text("STREAK \(streak)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text("\(String(format: "%.2g", multiplier))×")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Aether.heat))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.black.opacity(0.3)))
                .overlay(Capsule().strokeBorder(Aether.amber.opacity(0.6), lineWidth: 1))
        )
        .shadow(color: Aether.amber.opacity(glow ? 0.7 : 0.25), radius: glow ? 14 : 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

struct FinalLevelBadge: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("FINAL LEVEL")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Aether.danger.opacity(0.85))
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 1))
        )
        .shadow(color: Aether.danger.opacity(pulse ? 0.8 : 0.3), radius: pulse ? 16 : 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Floating popups & banners

struct ShardBonusPopup: View {
    let bonus: Int
    let timeBonus: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 20))
                .foregroundStyle(Aether.cyan)
            Text("+\(bonus)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("+\(timeBonus)s")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Aether.mint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.black.opacity(0.35)))
                .overlay(Capsule().strokeBorder(Aether.accent, lineWidth: 1.5))
        )
        .shadow(color: Aether.cyan.opacity(0.5), radius: 16)
    }
}

struct LevelBanner: View {
    let level: Int
    var body: some View {
        VStack(spacing: 4) {
            Text("LEVEL")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .tracking(8)
            Text("\(level)")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundStyle(Aether.accent)
                .shadow(color: Aether.cyan.opacity(0.6), radius: 20)
        }
    }
}

// MARK: - Modern Toggle

struct ModernToggle: View {
    @Binding var isOn: Bool
    let label: String
    let icon: String

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isOn.toggle() }
            HapticManager.shared.playSuccessHaptic()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .opacity(isOn ? 1 : 0.6)
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isOn ? AnyShapeStyle(Aether.accent) : AnyShapeStyle(Color.white.opacity(0.4)))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(0.3)))
                    .overlay(
                        Capsule().strokeBorder(
                            isOn ? Aether.cyan.opacity(0.6) : Color.white.opacity(0.12),
                            lineWidth: 1)
                    )
            )
            .shadow(color: isOn ? Aether.cyan.opacity(0.35) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Center Overlay Cards

struct LevelCompleteCard: View {
    @ObservedObject var game: GameCoordinator

    var body: some View {
        VStack(spacing: 16) {
            Text("LEVEL COMPLETE")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Aether.success)
                .shadow(color: Aether.mint.opacity(0.5), radius: 10)

            VStack(spacing: 10) {
                BreakdownRow(
                    icon: "star.fill", label: "Level Score",
                    value: "+\(game.lastLevelScore)", tint: .white)
                if game.speedBonusEarned > 0 {
                    BreakdownRow(
                        icon: "bolt.fill", label: "Speed Bonus",
                        value: "+\(game.speedBonusEarned)", tint: Aether.amber)
                }
                if !game.hasFallenThisLevel {
                    BreakdownRow(
                        icon: "target", label: "Perfect Level",
                        value: "BONUS", tint: Aether.cyan)
                }
                if game.currentMultiplier > 1.0 {
                    BreakdownRow(
                        icon: "flame.fill", label: "Multiplier",
                        value: "\(String(format: "%.2g", game.currentMultiplier))×",
                        tint: Color(red: 1.0, green: 0.55, blue: 0.3))
                }
            }

            Text("Get ready for Level \(game.currentLevel)…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(GlassBackground(corner: 26, stroke: AnyShapeStyle(Aether.mint.opacity(0.5))))
        .shadow(color: Aether.mint.opacity(0.25), radius: 20)
        .padding(24)
    }
}

struct BreakdownRow: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = .white

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .fontWeight(.heavy)
                .foregroundStyle(tint)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
    }
}

struct GameOverCard: View {
    @ObservedObject var game: GameCoordinator

    private var isVictory: Bool { game.currentLevel > 10 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(isVictory ? "VICTORY" : "GAME OVER")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(isVictory ? AnyShapeStyle(Aether.heat) : AnyShapeStyle(Aether.danger))
                    .shadow(color: (isVictory ? Aether.amber : Aether.danger).opacity(0.6), radius: 12)

                VStack(spacing: 2) {
                    Text("FINAL SCORE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(3)
                    Text("\(game.score)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                VStack(spacing: 10) {
                    BreakdownRow(
                        icon: "flag.checkered", label: "Levels Cleared",
                        value: "\(max(0, game.currentLevel - 1))/10", tint: Aether.mint)
                    BreakdownRow(
                        icon: "diamond.fill", label: "Shards Collected",
                        value: "\(game.totalShardsCollected)", tint: Aether.cyan)
                    BreakdownRow(
                        icon: "flame.fill", label: "Best Streak",
                        value: "\(game.bestStreak)", tint: Aether.amber)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06)))

                if game.isNewHighScore {
                    Label("NEW HIGH SCORE!", systemImage: "trophy.fill")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Aether.heat)
                        .shadow(color: Aether.amber.opacity(0.6), radius: 8)
                } else if game.leaderboardPosition > 0 && game.leaderboardPosition <= 10 {
                    Label("#\(game.leaderboardPosition) on the leaderboard",
                        systemImage: "rosette")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Aether.cyan)
                }

                let scores = game.getHighScores()
                if !scores.isEmpty {
                    VStack(spacing: 8) {
                        Text("HIGH SCORES")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .tracking(3)
                        ForEach(Array(scores.prefix(5).enumerated()), id: \.offset) { i, s in
                            HStack {
                                Text("\(i + 1)")
                                    .foregroundStyle(.white.opacity(0.4))
                                    .frame(width: 22, alignment: .leading)
                                Spacer()
                                Text("\(s)")
                                    .foregroundStyle(s == game.score ? Aether.cyan : .white)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    HapticManager.shared.playSuccessHaptic()
                    game.resetGame()
                } label: {
                    Text("PLAY AGAIN")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(Aether.accent))
                        .shadow(color: Aether.cyan.opacity(0.5), radius: 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 380, maxHeight: 560)
        .background(GlassBackground(corner: 30, stroke: AnyShapeStyle(Aether.accent)))
        .shadow(color: .black.opacity(0.5), radius: 24)
        .padding(24)
    }
}

// Helper Component to store level info on the Anchor
struct LevelComponent: Component {
    var level: Int
}
