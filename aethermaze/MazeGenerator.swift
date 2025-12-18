import Foundation
import RealityKit

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
    typealias UIColor = NSColor
#endif
// MARK: - 2D Logic Structs
enum Direction: CaseIterable {
    case north, south, east, west
}

struct MazeCell {
    var walls: [Direction: Bool] = [.north: true, .south: true, .east: true, .west: true]
    var hasHole: Bool = false
    var isVisited = false
}

// MARK: - RealityKit Entity Creation
final class MazeGenerator {

    let unitSize: Float = 1.0
    var mazeMap: [[MazeCell]] = []

    // CHANGE: We now pass a generic 'Entity' as the parent
    func buildLevel(level: Int, width: Int, height: Int, parent: Entity) {
        mazeMap = Array(repeating: Array(repeating: MazeCell(), count: width), count: height)

        generateRecursiveBacktracker(width: width, height: height)

        // [NEW] Complexity: Remove 10% of walls to create loops
        removeRandomWalls(width: width, height: height, percentage: 0.10)

        placeHoles(level: level, width: width, height: height)
        placeStartAndEnd(width: width, height: height)  // Ensure start/end are always clear

        // Pass the parent entity to these functions
        createMergedFloor(parent: parent)
        createMergedWalls(parent: parent)
        createStartZone(parent: parent)  // [NEW] Visual start
        createWinZone(width: width, height: height, parent: parent)
        create3DMarble(parent: parent)  // Create marble last
        createDeathPlane(parent: parent)
    }

    // ... (generateRecursiveBacktracker, placeStartAndEnd, placeHoles remain same) ...
    // MARK: - Procedural Maze Algorithm
    private func generateRecursiveBacktracker(width: Int, height: Int) {
        // 1. Reset Walls (All closed)
        // Already done in init of MazeCell

        // 2. Stack-based DFS
        var stack: [(Int, Int)] = []
        var visited = Set<String>()  // "x,y"

        // Start at 0,0
        let startX = 0
        let startY = 0
        stack.append((startX, startY))
        visited.insert("\(startX),\(startY)")
        mazeMap[startY][startX].isVisited = true

        while !stack.isEmpty {
            let current = stack.last!
            let (cx, cy) = current

            // Find unvisited neighbors
            var neighbors: [(Direction, (Int, Int))] = []

            // North
            if cy > 0 && !mazeMap[cy - 1][cx].isVisited {
                neighbors.append((.north, (cx, cy - 1)))
            }
            // South
            if cy < height - 1 && !mazeMap[cy + 1][cx].isVisited {
                neighbors.append((.south, (cx, cy + 1)))
            }
            // East
            if cx < width - 1 && !mazeMap[cy][cx + 1].isVisited {
                neighbors.append((.east, (cx + 1, cy)))
            }
            // West
            if cx > 0 && !mazeMap[cy][cx - 1].isVisited {
                neighbors.append((.west, (cx - 1, cy)))
            }

            if !neighbors.isEmpty {
                // Choose random neighbor
                let chosen = neighbors.randomElement()!
                let (dir, (nx, ny)) = chosen

                // Remove walls between current and next
                // Note: mazeMap walls are [Direction: Bool]. removing means = false.

                mazeMap[cy][cx].walls[dir] = false

                // Open opposite wall of neighbor
                switch dir {
                case .north: mazeMap[ny][nx].walls[.south] = false
                case .south: mazeMap[ny][nx].walls[.north] = false
                case .east: mazeMap[ny][nx].walls[.west] = false
                case .west: mazeMap[ny][nx].walls[.east] = false
                }

                // Mark visited and push to stack
                mazeMap[ny][nx].isVisited = true
                visited.insert("\(nx),\(ny)")
                stack.append((nx, ny))
            } else {
                // Backtrack
                stack.removeLast()
            }
        }

        // OPTIONAL: Randomly remove a few more walls to create loops (Braid) matches
        // Makes it less linear and frustrating if a hole blocked a non-critical path.
        // But our Hole Protection strategy is better.
    }

    private func placeStartAndEnd(width: Int, height: Int) {
        if width > 0 && height > 0 {
            mazeMap[0][0].hasHole = false
            mazeMap[height - 1][width - 1].hasHole = false
        }
    }

    private func removeRandomWalls(width: Int, height: Int, percentage: Double) {
        // Iterate through all internal walls and remove a percentage of them
        // Internal Vertical Walls: (x from 0 to width-2)
        // Internal Horizontal Walls: (y from 0 to height-2)

        for y in 0..<height {
            for x in 0..<width {
                // Check East Wall (if not boundary)
                if x < width - 1 {
                    if mazeMap[y][x].walls[.east] == true {
                        if Double.random(in: 0...1) < percentage {
                            mazeMap[y][x].walls[.east] = false
                            mazeMap[y][x + 1].walls[.west] = false
                        }
                    }
                }

                // Check South Wall (if not boundary)
                if y < height - 1 {
                    if mazeMap[y][x].walls[.south] == true {
                        if Double.random(in: 0...1) < percentage {
                            mazeMap[y][x].walls[.south] = false
                            mazeMap[y + 1][x].walls[.north] = false
                        }
                    }
                }
            }
        }
    }

    private func placeHoles(level: Int, width: Int, height: Int) {
        // Algorithm:
        // 1. Solve the maze (BFS) to find the "Correct Path".
        // 2. Collect all cells in that path.
        // 3. Randomly select cells NOT in that set to be holes.

        guard let solutionPath = solveMazeBFS(width: width, height: height) else {
            print("Error: Maze not solvable even without holes?")
            return
        }

        let pathSet = Set(solutionPath.map { "\($0.x),\($0.y)" })
        let totalCells = Double(width * height)

        // [NEW] Complexity: More holes (5% of area) or at least 2+Level
        let pctHoles = Int(totalCells * 0.05)
        let levelHoles = 2 + level
        let numHoles = max(levelHoles, pctHoles)

        var holesPlaced = 0
        var attempts = 0

        while holesPlaced < numHoles && attempts < 100 {
            attempts += 1
            let randomX = Int.random(in: 0..<width)
            let randomY = Int.random(in: 0..<height)

            // Don't place on start or end
            if (randomX == 0 && randomY == 0)
                || (randomX == width - 1 && randomY == height - 1)
            {
                continue
            }

            // Don't place on solution path
            if pathSet.contains("\(randomX),\(randomY)") {
                continue
            }

            // Don't place if already hole
            if mazeMap[randomY][randomX].hasHole {
                continue
            }

            mazeMap[randomY][randomX].hasHole = true
            holesPlaced += 1
        }
    }

    // Helper BFS Solver
    struct Point: Hashable {
        let x: Int, y: Int
    }

    private func solveMazeBFS(width: Int, height: Int) -> [Point]? {
        let start = Point(x: 0, y: 0)
        let end = Point(x: width - 1, y: height - 1)

        var queue: [Point] = [start]
        var cameFrom: [Point: Point] = [:]
        var visited = Set<Point>()
        visited.insert(start)

        while !queue.isEmpty {
            let current = queue.removeFirst()

            if current == end {
                // Reconstruct path
                var path: [Point] = []
                var p = current
                while p != start {
                    path.append(p)
                    p = cameFrom[p]!
                }
                path.append(start)
                return path  // Reversed, but set membership doesn't care
            }

            let cx = current.x
            let cy = current.y
            let cell = mazeMap[cy][cx]

            // Check neighbors if no wall
            // North
            if !cell.walls[.north]! && cy > 0 {
                let next = Point(x: cx, y: cy - 1)
                if !visited.contains(next) {
                    visited.insert(next)
                    cameFrom[next] = current
                    queue.append(next)
                }
            }
            // South
            if !cell.walls[.south]! && cy < height - 1 {
                let next = Point(x: cx, y: cy + 1)
                if !visited.contains(next) {
                    visited.insert(next)
                    cameFrom[next] = current
                    queue.append(next)
                }
            }
            // East
            if !cell.walls[.east]! && cx < width - 1 {
                let next = Point(x: cx + 1, y: cy)
                if !visited.contains(next) {
                    visited.insert(next)
                    cameFrom[next] = current
                    queue.append(next)
                }
            }
            // West
            if !cell.walls[.west]! && cx > 0 {
                let next = Point(x: cx - 1, y: cy)
                if !visited.contains(next) {
                    visited.insert(next)
                    cameFrom[next] = current
                    queue.append(next)
                }
            }
        }
        return nil
    }

    // MARK: - 3D Entity Creation

    // REFACTORED: Create individual tiles instead of one big plane
    private func createMergedFloor(parent: Entity) {
        var standardPositions: [SIMD3<Float>] = []
        var holePositions: [SIMD3<Float>] = []

        for (y, row) in mazeMap.enumerated() {
            for (x, cell) in row.enumerated() {
                let position: SIMD3<Float> = [Float(x) * unitSize, -0.05, Float(y) * unitSize]
                if cell.hasHole {
                    holePositions.append(position)
                } else {
                    standardPositions.append(position)
                }
            }
        }

        // 1. Create Standard Floor Entity
        if !standardPositions.isEmpty {
            let floorEntity = Entity()
            floorEntity.name = "MergedFloor"

            // Generate combined mesh
            if let combinedMesh = generateMergedBoxMesh(
                positions: standardPositions, boxSize: [unitSize, 0.1, unitSize])
            {
                var floorMaterial = PhysicallyBasedMaterial()
                floorMaterial.baseColor = .init(tint: .brown)
                floorMaterial.roughness = 0.8

                let model = ModelEntity(mesh: combinedMesh, materials: [floorMaterial])
                floorEntity.addChild(model)
            }

            // Generate combined collisions
            let material = PhysicsMaterialResource.generate(
                staticFriction: 0.1, dynamicFriction: 0.1, restitution: 0.0)
            var shapes: [ShapeResource] = []
            let thickHeight: Float = 1.0

            for pos in standardPositions {
                // Adjust position to be centered for the thick floor
                let collisionPos = pos + SIMD3<Float>(0, -0.4, 0)  // Center of 1.0 height floor
                shapes.append(
                    ShapeResource.generateBox(
                        width: unitSize * 1.02, height: thickHeight, depth: unitSize * 1.02
                    ).offsetBy(translation: collisionPos))
            }

            floorEntity.components.set(CollisionComponent(shapes: shapes))
            floorEntity.components.set(
                PhysicsBodyComponent(massProperties: .default, material: material, mode: .kinematic)
            )
            parent.addChild(floorEntity)
        }

        // 2. Create Hole Tiles (Batch them as one entity if possible, or keep separate if complex)
        // For simplicity and to reuse the existing hole mesh logic, we'll create one entity per hole but share the mesh.
        if !holePositions.isEmpty, let holeMesh = generateHoleTileMesh() {
            var holeMaterial = PhysicallyBasedMaterial()
            holeMaterial.baseColor = .init(tint: .brown)
            holeMaterial.roughness = 0.8

            let pMat = PhysicsMaterialResource.generate(
                staticFriction: 0.1, dynamicFriction: 0.1, restitution: 0.0)
            let sideWidth: Float = (unitSize - 0.8) / 2.0
            let fullLength: Float = unitSize
            let innerLength: Float = unitSize - (sideWidth * 2)
            let height: Float = 0.1

            for pos in holePositions {
                let holeTile = ModelEntity(mesh: holeMesh, materials: [holeMaterial])
                holeTile.position = pos
                holeTile.name = "HoleTile"

                // Add 4 collision boxes for the hole frame
                let leftPos = SIMD3<Float>(-(unitSize / 2) + (sideWidth / 2), 0, 0)
                let rightPos = SIMD3<Float>((unitSize / 2) - (sideWidth / 2), 0, 0)
                let topPos = SIMD3<Float>(0, 0, -(unitSize / 2) + (sideWidth / 2))
                let botPos = SIMD3<Float>(0, 0, (unitSize / 2) - (sideWidth / 2))

                let shapes = [
                    ShapeResource.generateBox(size: [sideWidth, height, fullLength]).offsetBy(
                        translation: leftPos),
                    ShapeResource.generateBox(size: [sideWidth, height, fullLength]).offsetBy(
                        translation: rightPos),
                    ShapeResource.generateBox(size: [innerLength, height, sideWidth]).offsetBy(
                        translation: topPos),
                    ShapeResource.generateBox(size: [innerLength, height, sideWidth]).offsetBy(
                        translation: botPos),
                ]

                holeTile.components.set(CollisionComponent(shapes: shapes))
                holeTile.components.set(
                    PhysicsBodyComponent(massProperties: .default, material: pMat, mode: .kinematic)
                )
                parent.addChild(holeTile)
            }
        }
    }

    private func generateMergedBoxMesh(positions: [SIMD3<Float>], boxSize: SIMD3<Float>)
        -> MeshResource?
    {
        var combinedDesc = MeshDescriptor()
        var allPositions: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []
        var allIndices: [UInt32] = []
        var allUVs: [SIMD2<Float>] = []

        let halfSize = boxSize / 2.0

        for (i, pos) in positions.enumerated() {
            let offset = UInt32(i * 24)  // 24 vertices per box (4 per face * 6 faces)

            // Vertices and Normals for a box
            // This is a bit verbose, but necessary for a manual MeshDescriptor
            // 6 faces * 4 vertices = 24

            // Top face (+Y)
            allPositions.append(contentsOf: [
                pos + SIMD3(-halfSize.x, halfSize.y, -halfSize.z),
                pos + SIMD3(halfSize.x, halfSize.y, -halfSize.z),
                pos + SIMD3(halfSize.x, halfSize.y, halfSize.z),
                pos + SIMD3(-halfSize.x, halfSize.y, halfSize.z),
            ])
            allNormals.append(contentsOf: Array(repeating: [0, 1, 0], count: 4))

            // Bottom face (-Y)
            allPositions.append(contentsOf: [
                pos + SIMD3(-halfSize.x, -halfSize.y, halfSize.z),
                pos + SIMD3(halfSize.x, -halfSize.y, halfSize.z),
                pos + SIMD3(halfSize.x, -halfSize.y, -halfSize.z),
                pos + SIMD3(-halfSize.x, -halfSize.y, -halfSize.z),
            ])
            allNormals.append(contentsOf: Array(repeating: [0, -1, 0], count: 4))

            // Front face (+Z)
            allPositions.append(contentsOf: [
                pos + SIMD3(-halfSize.x, -halfSize.y, halfSize.z),
                pos + SIMD3(-halfSize.x, halfSize.y, halfSize.z),
                pos + SIMD3(halfSize.x, halfSize.y, halfSize.z),
                pos + SIMD3(halfSize.x, -halfSize.y, halfSize.z),
            ])
            allNormals.append(contentsOf: Array(repeating: [0, 0, 1], count: 4))

            // Back face (-Z)
            allPositions.append(contentsOf: [
                pos + SIMD3(halfSize.x, -halfSize.y, -halfSize.z),
                pos + SIMD3(halfSize.x, halfSize.y, -halfSize.z),
                pos + SIMD3(-halfSize.x, halfSize.y, -halfSize.z),
                pos + SIMD3(-halfSize.x, -halfSize.y, -halfSize.z),
            ])
            allNormals.append(contentsOf: Array(repeating: [0, 0, -1], count: 4))

            // Left face (-X)
            allPositions.append(contentsOf: [
                pos + SIMD3(-halfSize.x, -halfSize.y, -halfSize.z),
                pos + SIMD3(-halfSize.x, halfSize.y, -halfSize.z),
                pos + SIMD3(-halfSize.x, halfSize.y, halfSize.z),
                pos + SIMD3(-halfSize.x, -halfSize.y, halfSize.z),
            ])
            allNormals.append(contentsOf: Array(repeating: [-1, 0, 0], count: 4))

            // Right face (+X)
            allPositions.append(contentsOf: [
                pos + SIMD3(halfSize.x, -halfSize.y, halfSize.z),
                pos + SIMD3(halfSize.x, halfSize.y, halfSize.z),
                pos + SIMD3(halfSize.x, halfSize.y, -halfSize.z),
                pos + SIMD3(halfSize.x, -halfSize.y, -halfSize.z),
            ])
            allNormals.append(contentsOf: Array(repeating: [1, 0, 0], count: 4))

            // Indices for 6 faces
            for f in 0..<6 {
                let faceOffset = offset + UInt32(f * 4)
                allIndices.append(contentsOf: [
                    faceOffset, faceOffset + 1, faceOffset + 2, faceOffset, faceOffset + 2,
                    faceOffset + 3,
                ])
            }

            // UVs (simple projection)
            for _ in 0..<6 {
                allUVs.append(contentsOf: [[0, 0], [1, 0], [1, 1], [0, 1]])
            }
        }

        combinedDesc.positions = MeshBuffers.Positions(allPositions)
        combinedDesc.normals = MeshBuffers.Normals(allNormals)
        combinedDesc.textureCoordinates = MeshBuffers.TextureCoordinates(allUVs)
        combinedDesc.primitives = .triangles(allIndices)

        return try? MeshResource.generate(from: [combinedDesc])
    }

    // Procedural Mesh for Square with Round Hole
    private func generateHoleTileMesh() -> MeshResource? {
        var desc = MeshDescriptor()
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var textureCoordinates: [SIMD2<Float>] = []

        let radius: Float = unitSize * 0.4
        let yTop: Float = 0.05
        let halfSize = unitSize / 2
        let segments = 32  // Must be divisible by 4

        // We generate the top surface by connecting the inner circle loop to the outer square loop.
        // Outer loop points need to match the density of inner loop to make decent triangles?
        // Or we can just use the 4 corners and project.

        // Strategy: 4 Quadrants.
        // TR Quadrant (Corner 1). Angles 0 to 90.
        // Normalized t from 0 to 1 along the arc.
        // Corresponding point on square edge goes from (R, 0) -> (R, R) -> (0, R).
        // Actually, just interpolating between square boundary and circle boundary works.

        // Let's generate 'segments' number of points on both Inner Circle and Outer Square boundaries
        // and connect them with quads (2 triangles).

        for i in 0...segments {
            // Angle from 0 to 2pi
            let angle = (Float(i) / Float(segments)) * .pi * 2

            // Inner Point
            let ix = cos(angle) * radius
            let iz = sin(angle) * radius

            // Outer Point logic: Project ray to square boundary
            // abs(x) vs abs(z)
            var ox: Float = 0
            var oz: Float = 0

            // Simple logic to find point on square ring
            if abs(ix) >= abs(iz) {
                // Hitting Left or Right wall
                ox = (ix > 0 ? halfSize : -halfSize)
                oz = iz * (ox / ix)
            } else {
                // Hitting Top or Bottom wall
                oz = (iz > 0 ? halfSize : -halfSize)
                ox = ix * (oz / iz)
            }

            // Add Vertices
            // We duplicate vertices for flat shading normals if needed, but smooth circle is nice.
            // Let's reuse vertices for connected mesh.

            let innerPos = SIMD3<Float>(ix, yTop, iz)
            let outerPos = SIMD3<Float>(ox, yTop, oz)

            positions.append(innerPos)
            positions.append(outerPos)

            normals.append([0, 1, 0])
            normals.append([0, 1, 0])

            // Approx UVs
            textureCoordinates.append([(ix / unitSize) + 0.5, (iz / unitSize) + 0.5])
            textureCoordinates.append([(ox / unitSize) + 0.5, (oz / unitSize) + 0.5])

            // Add Indices (Quad between i and i-1)
            if i > 0 {
                let p1 = UInt32((i - 1) * 2)  // Prev Inner
                let p2 = UInt32((i - 1) * 2 + 1)  // Prev Outer
                let p3 = UInt32(i * 2)  // Curr Inner
                let p4 = UInt32(i * 2 + 1)  // Curr Outer

                // Tri 1: P1-P4-P2 (Order matters for culling)
                // Counter Clockwise?
                indices.append(contentsOf: [p1, p4, p2])
                indices.append(contentsOf: [p1, p3, p4])
            }
        }

        // Also Generate Inner Walls (Cylinder downwards)
        let wallStartIdx = UInt32(positions.count)
        let depth = 0.1  // 0.05 to -0.05

        for i in 0...segments {
            let angle = (Float(i) / Float(segments)) * .pi * 2
            let ix = cos(angle) * radius
            let iz = sin(angle) * radius

            let topPos = SIMD3<Float>(ix, yTop, iz)
            let botPos = SIMD3<Float>(ix, yTop - Float(depth), iz)

            positions.append(topPos)
            positions.append(botPos)

            // Normals point INWARDS (towards center). (-x, 0, -z)
            let n = SIMD3<Float>(-ix, 0, -iz)  // normalized later?
            normals.append(n)
            normals.append(n)

            textureCoordinates.append([0, 0])  // Dummy UVs
            textureCoordinates.append([0, 1])

            if i > 0 {
                let currTop = wallStartIdx + UInt32(i * 2)
                let currBot = wallStartIdx + UInt32(i * 2 + 1)
                let prevTop = wallStartIdx + UInt32((i - 1) * 2)
                let prevBot = wallStartIdx + UInt32((i - 1) * 2 + 1)

                // Triangles
                indices.append(contentsOf: [prevTop, currTop, prevBot])
                indices.append(contentsOf: [currTop, currBot, prevBot])
            }
        }

        desc.positions = MeshBuffers.Positions(positions)
        desc.normals = MeshBuffers.Normals(normals)
        desc.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        desc.primitives = .triangles(indices)

        return try? MeshResource.generate(from: [desc])
    }

    private func createDeathPlane(parent: Entity) {
        // A large invisible collider below the maze to catch falling marbles
        let planeSize: Float = 100.0
        let deathPlane = Entity()
        deathPlane.name = "DeathPlane"
        deathPlane.position = [0, -3.0, 0]  // 3 units below

        let shape = ShapeResource.generateBox(width: planeSize, height: 0.1, depth: planeSize)
        let collision = CollisionComponent(shapes: [shape])
        deathPlane.components.set(collision)
        // Static body so it doesn't fall, but triggers collision
        deathPlane.components.set(PhysicsBodyComponent(massProperties: .default, mode: .kinematic))

        parent.addChild(deathPlane)
    }

    private func createWinZone(width: Int, height: Int, parent: Entity) {
        // Trigger at the end cell
        let endX = width - 1
        let endY = height - 1

        let winZone = Entity()
        winZone.name = "WinZone"
        winZone.position = [Float(endX) * unitSize, 0, Float(endY) * unitSize]

        // A box slightly larger than the marble
        let shape = ShapeResource.generateBox(
            width: unitSize * 0.8, height: unitSize, depth: unitSize * 0.8)

        // Make it a trigger (no physics response, just event)
        let collision = CollisionComponent(shapes: [shape])
        winZone.components.set(collision)

        // [FIX] WinZone Trigger needs to track inputs? No, default is fine.
        // But let's ensure it has a body mode that supports collisions.
        // Triggers often need to be .kinematic/static with isTrigger...
        // RealityKit doesn't have explicit "isTrigger" property on CollisionComponent in standard API,
        // it relies on Subscribe to CollisionEvents. And it needs a PhysicsBodyMode.
        // Default static often works.
        // If it was missing PhysicsBody, it might not register.
        // Adding kinematic body just in case (though Collision-only entities can trigger events if one other body is dynamic).
        // winZone.components.set(PhysicsBodyComponent(massProperties: .default, mode: .kinematic)) // Optional safety

        // Visual marker for the end (Green Pad)
        let padMesh = MeshResource.generateBox(width: 0.6, height: 0.01, depth: 0.6)
        let padMat = SimpleMaterial(color: .green, isMetallic: false)
        let pad = ModelEntity(mesh: padMesh, materials: [padMat])
        pad.position = [0, 0.01, 0]
        winZone.addChild(pad)

        // Keep floating marker but maybe higher?
        let markerMesh = MeshResource.generateSphere(radius: 0.2)
        let markerMat = SimpleMaterial(color: .green, isMetallic: false)
        let marker = ModelEntity(mesh: markerMesh, materials: [markerMat])
        marker.position = [0, 0.5, 0]
        winZone.addChild(marker)

        parent.addChild(winZone)
    }

    private func createMergedWalls(parent: Entity) {
        let wallHeight: Float = 0.8
        var wallData: [(transform: Transform, size: SIMD3<Float>)] = []

        for (y, row) in mazeMap.enumerated() {
            for (x, cell) in row.enumerated() {
                let basePosition = SIMD3<Float>(Float(x) * unitSize, 0, Float(y) * unitSize)
                let wallY: Float = wallHeight / 2

                if cell.walls[.east] == true {
                    var t = Transform()
                    t.rotation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    t.translation = basePosition + SIMD3<Float>(unitSize / 2, wallY, 0)
                    wallData.append((t, [unitSize, wallHeight, 0.05]))
                }

                if cell.walls[.south] == true {
                    var t = Transform()
                    t.translation = basePosition + SIMD3<Float>(0, wallY, unitSize / 2)
                    wallData.append((t, [unitSize, wallHeight, 0.05]))
                }

                if y == 0 && cell.walls[.north] == true {
                    var t = Transform()
                    t.translation = basePosition + SIMD3<Float>(0, wallY, -unitSize / 2)
                    wallData.append((t, [unitSize, wallHeight, 0.05]))
                }

                if x == 0 && cell.walls[.west] == true {
                    var t = Transform()
                    t.rotation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    t.translation = basePosition + SIMD3<Float>(-unitSize / 2, wallY, 0)
                    wallData.append((t, [unitSize, wallHeight, 0.05]))
                }
            }
        }

        if wallData.isEmpty { return }

        let wallsEntity = Entity()
        wallsEntity.name = "MergedWalls"

        // Generate combined mesh
        if let combinedMesh = generateMergedBoxMeshWithTransforms(wallData: wallData) {
            var wallMaterial = SimpleMaterial()
            if let texture = try? TextureResource.load(named: "wood_texture") {
                wallMaterial.color = .init(tint: .white, texture: .init(texture))
                wallMaterial.metallic = .float(0.0)
                wallMaterial.roughness = .float(0.8)
            } else {
                wallMaterial = SimpleMaterial(color: .brown, isMetallic: false)
            }

            let model = ModelEntity(mesh: combinedMesh, materials: [wallMaterial])
            wallsEntity.addChild(model)
        }

        // Generate combined collisions
        var shapes: [ShapeResource] = []
        for data in wallData {
            shapes.append(
                ShapeResource.generateBox(size: data.size).offsetBy(
                    rotation: data.transform.rotation, translation: data.transform.translation))
        }

        wallsEntity.components.set(CollisionComponent(shapes: shapes))
        wallsEntity.components.set(
            PhysicsBodyComponent(
                massProperties: .default,
                material: .generate(staticFriction: 0.1, dynamicFriction: 0.1, restitution: 0.0),
                mode: .kinematic))

        parent.addChild(wallsEntity)
    }

    private func generateMergedBoxMeshWithTransforms(
        wallData: [(transform: Transform, size: SIMD3<Float>)]
    ) -> MeshResource? {
        var combinedDesc = MeshDescriptor()
        var allPositions: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []
        var allIndices: [UInt32] = []
        var allUVs: [SIMD2<Float>] = []

        for (i, data) in wallData.enumerated() {
            let offset = UInt32(i * 24)
            let halfSize = data.size / 2.0
            let matrix = data.transform.matrix

            func addFace(
                p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>, p4: SIMD3<Float>,
                normal: SIMD3<Float>
            ) {
                let transformedNormal = normalize(
                    simd_make_float3(matrix * simd_make_float4(normal, 0)))
                allPositions.append(contentsOf: [
                    simd_make_float3(matrix * simd_make_float4(p1, 1)),
                    simd_make_float3(matrix * simd_make_float4(p2, 1)),
                    simd_make_float3(matrix * simd_make_float4(p3, 1)),
                    simd_make_float3(matrix * simd_make_float4(p4, 1)),
                ])
                allNormals.append(contentsOf: Array(repeating: transformedNormal, count: 4))
                allUVs.append(contentsOf: [[0, 0], [1, 0], [1, 1], [0, 1]])
            }

            // Top (+Y)
            addFace(
                p1: [-halfSize.x, halfSize.y, -halfSize.z],
                p2: [halfSize.x, halfSize.y, -halfSize.z],
                p3: [halfSize.x, halfSize.y, halfSize.z],
                p4: [-halfSize.x, halfSize.y, halfSize.z], normal: [0, 1, 0])
            // Bottom (-Y)
            addFace(
                p1: [-halfSize.x, -halfSize.y, halfSize.z],
                p2: [halfSize.x, -halfSize.y, halfSize.z],
                p3: [halfSize.x, -halfSize.y, -halfSize.z],
                p4: [-halfSize.x, -halfSize.y, -halfSize.z], normal: [0, -1, 0])
            // Front (+Z)
            addFace(
                p1: [-halfSize.x, -halfSize.y, halfSize.z],
                p2: [-halfSize.x, halfSize.y, halfSize.z],
                p3: [halfSize.x, halfSize.y, halfSize.z],
                p4: [halfSize.x, -halfSize.y, halfSize.z], normal: [0, 0, 1])
            // Back (-Z)
            addFace(
                p1: [halfSize.x, -halfSize.y, -halfSize.z],
                p2: [halfSize.x, halfSize.y, -halfSize.z],
                p3: [-halfSize.x, halfSize.y, -halfSize.z],
                p4: [-halfSize.x, -halfSize.y, -halfSize.z], normal: [0, 0, -1])
            // Left (-X)
            addFace(
                p1: [-halfSize.x, -halfSize.y, -halfSize.z],
                p2: [-halfSize.x, halfSize.y, -halfSize.z],
                p3: [-halfSize.x, halfSize.y, halfSize.z],
                p4: [-halfSize.x, -halfSize.y, halfSize.z], normal: [-1, 0, 0])
            // Right (+X)
            addFace(
                p1: [halfSize.x, -halfSize.y, halfSize.z],
                p2: [halfSize.x, halfSize.y, halfSize.z],
                p3: [halfSize.x, halfSize.y, -halfSize.z],
                p4: [halfSize.x, -halfSize.y, -halfSize.z], normal: [1, 0, 0])

            for f in 0..<6 {
                let faceOffset = offset + UInt32(f * 4)
                allIndices.append(contentsOf: [
                    faceOffset, faceOffset + 1, faceOffset + 2, faceOffset, faceOffset + 2,
                    faceOffset + 3,
                ])
            }
        }

        combinedDesc.positions = MeshBuffers.Positions(allPositions)
        combinedDesc.normals = MeshBuffers.Normals(allNormals)
        combinedDesc.textureCoordinates = MeshBuffers.TextureCoordinates(allUVs)
        combinedDesc.primitives = .triangles(allIndices)

        return try? MeshResource.generate(from: [combinedDesc])
    }

    private func createStartZone(parent: Entity) {
        // Visual marker for the start (Blue Pad on Floor)
        // Cylinder height 0.01, radius 0.3
        let markerMesh = MeshResource.generateBox(width: 0.6, height: 0.01, depth: 0.6)
        let markerMat = SimpleMaterial(color: .blue, isMetallic: false)
        // Make it slightly transparent?
        // markerMat.baseColor = MaterialColorParameter.color(UIColor.blue.withAlphaComponent(0.5))
        // SimpleMaterial doesn't support alpha well in non-PBR. Use PBR if needed.
        // Just solid blue is fine.

        let marker = ModelEntity(mesh: markerMesh, materials: [markerMat])
        marker.position = [0, 0.01, 0]  // Just above floor limit (0 and -0.05)
        marker.name = "StartMarker"

        // No collision on the marker itself, but we need floor underneath it?
        // Actually, StartZone is usually at 0,0 which IS a floor tile (unless hole logic removed it).
        // MazeGenerator places Start/End at 0,0 / max,max and guarantees "No Hole".
        // So there IS a floor tile there created by create3DFloor.
        // We just add the visual marker on top.
        parent.addChild(marker)
    }

    private func create3DMarble(parent: Entity) {
        let marbleMesh = MeshResource.generateSphere(radius: 0.15)  // Slightly larger marble

        var marbleMaterial = PhysicallyBasedMaterial()
        marbleMaterial.baseColor = .init(tint: .white)
        marbleMaterial.metallic = 1.0
        marbleMaterial.roughness = 0.1

        let marble = ModelEntity(mesh: marbleMesh, materials: [marbleMaterial])
        marble.name = "Marble"
        // Lower spawn height to reduce impact/clipping risk
        // Floor is at 0.0 surface. Radius is 0.15. Center at 0.15 means touching.
        // 0.2 gives a tiny drop.
        marble.position = [0.0, 0.2, 0.0]

        let physicsBody = PhysicsBodyComponent(
            massProperties: .default, material: .generate(friction: 0.5, restitution: 0.0),
            mode: .dynamic)
        var dampedBody = physicsBody
        dampedBody.linearDamping = 0.5
        dampedBody.angularDamping = 0.5
        dampedBody.isContinuousCollisionDetectionEnabled = true
        marble.components.set(dampedBody)
        marble.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.15)]))

        parent.addChild(marble)
    }
}
