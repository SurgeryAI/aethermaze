import SwiftUI
import RealityKit
import ARKit // ✅ FIXED: Added ARKit import

struct ContentView: View {
    @StateObject private var motionController = MotionController()
    @State private var currentLevel = 1

    var body: some View {
        ZStack {
            // ARViewContainer hosts the 3D scene
            ARViewContainer(currentLevel: $currentLevel, motionController: motionController)
                .edgesIgnoringSafeArea(.all)
            
            // UI Overlay
            VStack {
                Text("Level \(currentLevel)")
                    .font(.largeTitle)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                Spacer()
            }
            .padding()
        }
    }
}

// Standard bridge between SwiftUI and RealityKit
struct ARViewContainer: UIViewRepresentable {
    @Binding var currentLevel: Int
    @ObservedObject var motionController: MotionController
    
    // We use a static key to find the anchor later
    let anchorName = "GameAnchor"

    func makeUIView(context: Context) -> ARView {
        // 1. Create the ARView in Non-AR mode (Standard 3D game mode)
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: true)
        
        // 2. Create a Root Anchor for the game
        let gameAnchor = AnchorEntity(world: [0, 0, 0])
        gameAnchor.name = anchorName
        arView.scene.addAnchor(gameAnchor)
        
        // 3. Generate the Maze
        let generator = MazeGenerator()
        generator.buildLevel(level: currentLevel, parent: gameAnchor)
        
        // 4. Add Lighting
        // Add a strong top-down light to create shadows inside the maze walls
        let mainLight = DirectionalLight()
        mainLight.light.intensity = 2000
        mainLight.light.isRealWorldProxy = true
        mainLight.shadow?.maximumDistance = 10
        mainLight.shadow?.depthBias = 1
        // Look down from above
        mainLight.look(at: [0,0,0], from: [0, 5, 2], relativeTo: gameAnchor)
        gameAnchor.addChild(mainLight)
        
        // Add a camera so we can see the board clearly
        let camera = PerspectiveCamera()
        // Position camera above the maze looking down
        camera.look(at: [2.5, 0, 2.5], from: [2.5, 8, 8], relativeTo: gameAnchor)
        let cameraAnchor = AnchorEntity(world: [0,0,0])
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // This runs whenever the MotionController updates
        
        // ✅ FIXED: Instead of changing global gravity, we TILT THE MAZE.
        // This is much smoother and more reliable in RealityKit.
        
        if let gameAnchor = uiView.scene.findEntity(named: anchorName) {
            let g = motionController.currentGravity
            
            // Convert the gravity values back into tilt angles
            // (We divide by the multiplier we set in MotionController to get radians back)
            let multiplier: Float = 25.0
            let pitch = Double(g.z / multiplier) // Forward/Back tilt
            let roll = Double(g.x / multiplier)  // Left/Right tilt
            
            // Apply rotation to the maze anchor
            // Note: We invert the angles to make the movement feel natural (tilting phone left drops left side)
            let rotation = simd_quatf(angle: Float(pitch), axis: [1, 0, 0]) * // Rotate around X (Pitch)
                           simd_quatf(angle: Float(-roll), axis: [0, 0, 1])   // Rotate around Z (Roll)
            
            // Smoothly animate to the new rotation
            gameAnchor.transform.rotation = rotation
        }
    }
}
