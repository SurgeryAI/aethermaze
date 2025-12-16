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
    func buildLevel(level: Int, parent: Entity) {
        let size = 5 + level * 2
        mazeMap = Array(repeating: Array(repeating: MazeCell(), count: size), count: size)

        generateRecursiveBacktracker(width: size, height: size)

        generateRecursiveBacktracker(width: size, height: size)

        placeHoles(level: level)
        placeStartAndEnd(size: size)  // Ensure start/end are always clear

        // Pass the parent entity to these functions
        create3DFloor(parent: parent)
        create3DWalls(parent: parent)
        createStartZone(parent: parent)  // [NEW] Visual start
        createWinZone(size: size, parent: parent)
        create3DMarble(parent: parent)  // Create marble last
        createDeathPlane(parent: parent)
    }

    // ... (generateRecursiveBacktracker, placeStartAndEnd, placeHoles remain same) ...
    // MARK: - Procedural Maze Algorithm
    private func generateRecursiveBacktracker(width: Int, height: Int) {
        // Placeholder Logic - Just a simple open grid for now to test movement
        // In a real app we'd use a real stack-based generator
        for y in 0..<height {
            for x in 0..<width {
                // Open some random walls for testing
                if x < width - 1 && Bool.random() { mazeMap[y][x].walls[.east] = false }
                if y < height - 1 && Bool.random() { mazeMap[y][x].walls[.south] = false }
            }
        }
    }

    private func placeStartAndEnd(size: Int) {
        if size > 0 {
            mazeMap[0][0].hasHole = false
            mazeMap[size - 1][size - 1].hasHole = false
        }
    }

    private func placeHoles(level: Int) {
        let numHoles = 2 + level
        for _ in 0..<numHoles {
            let randomX = Int.random(in: 1..<mazeMap.count - 1)
            let randomY = Int.random(in: 1..<mazeMap.count - 1)
            mazeMap[randomY][randomX].hasHole = true
        }
    }

    // MARK: - 3D Entity Creation

    // REFACTORED: Create individual tiles instead of one big plane
    private func create3DFloor(parent: Entity) {
        // Standard floor tile
        let tileMesh = MeshResource.generateBox(width: unitSize, height: 0.1, depth: unitSize)

        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: .brown)
        floorMaterial.roughness = 0.8

        // Hole tile material (maybe darker?)
        var holeMaterial = PhysicallyBasedMaterial()
        holeMaterial.baseColor = .init(tint: .brown)
        holeMaterial.roughness = 0.8

        for (y, row) in mazeMap.enumerated() {
            for (x, cell) in row.enumerated() {
                // Explicit SIMD3<Float>
                let position: SIMD3<Float> = [Float(x) * unitSize, -0.05, Float(y) * unitSize]

                if !cell.hasHole {
                    let tile = ModelEntity(mesh: tileMesh, materials: [floorMaterial])
                    tile.position = position

                    // Zero restitution
                    let material = PhysicsMaterialResource.generate(
                        staticFriction: 0.1, dynamicFriction: 0.1, restitution: 0.0)

                    tile.components.set(
                        PhysicsBodyComponent(
                            shapes: [
                                ShapeResource.generateBox(
                                    width: unitSize, height: 0.1, depth: unitSize)
                            ],
                            massProperties: .default,
                            material: material,
                            mode: .kinematic))

                    tile.components.set(
                        CollisionComponent(shapes: [
                            ShapeResource.generateBox(width: unitSize, height: 0.1, depth: unitSize)
                        ]))

                    parent.addChild(tile)
                } else {
                    // [NEW] Hole Tile
                    if let holeMesh = generateHoleTileMesh() {
                        let tile = ModelEntity(mesh: holeMesh, materials: [holeMaterial])
                        tile.position = position

                        // Generate Static Mesh Shape for the hole (Concave)
                        let shape = ShapeResource.generateStaticMesh(from: holeMesh)

                        let material = PhysicsMaterialResource.generate(
                            staticFriction: 0.1, dynamicFriction: 0.1, restitution: 0.0)

                        tile.components.set(
                            PhysicsBodyComponent(
                                shapes: [shape],
                                massProperties: .default,
                                material: material,
                                mode: .kinematic))
                        tile.components.set(CollisionComponent(shapes: [shape]))

                        parent.addChild(tile)
                    }
                }
            }
        }
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

    private func createWinZone(size: Int, parent: Entity) {
        // Trigger at the end cell
        let endX = size - 1
        let endY = size - 1

        let winZone = Entity()
        winZone.name = "WinZone"
        winZone.position = [Float(endX) * unitSize, 0, Float(endY) * unitSize]

        // A box slightly larger than the marble
        let shape = ShapeResource.generateBox(
            width: unitSize * 0.8, height: unitSize, depth: unitSize * 0.8)

        // Make it a trigger (no physics response, just event)
        // RealityKit Triggers are often just kinematic or static bodies that we listen for events on.
        let collision = CollisionComponent(shapes: [shape])
        winZone.components.set(collision)

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

    private func create3DWalls(parent: Entity) {
        let wallMesh = MeshResource.generateBox(width: unitSize, height: 0.2, depth: 0.05)
        let wallMaterial = SimpleMaterial(color: .gray, isMetallic: false)

        for (y, row) in mazeMap.enumerated() {
            for (x, cell) in row.enumerated() {

                let basePosition = SIMD3<Float>(Float(x) * unitSize, 0, Float(y) * unitSize)

                // Existing Checks for East/South (Internal & Outer East/South)
                if cell.walls[.east] == true {
                    let wall = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
                    // East wall separates X and X+1. Needs to run along Z.
                    // Original mesh is X-long. So Rotate 90 Y.
                    wall.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    wall.position = basePosition + SIMD3<Float>(unitSize / 2, 0.1, 0)
                    wall.components.set(wallPhysicsComponent())
                    wall.components.set(
                        CollisionComponent(shapes: [
                            .generateBox(width: unitSize, height: 0.2, depth: 0.05)
                        ]))
                    wall.name = "Wall"
                    parent.addChild(wall)
                }

                if cell.walls[.south] == true {
                    let wall = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
                    // South wall separates Y and Y+1 (Z and Z+1). Needs to run along X.
                    // Original mesh is X-long. No Rotation.
                    // wall.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    wall.position = basePosition + SIMD3<Float>(0, 0.1, unitSize / 2)
                    wall.components.set(wallPhysicsComponent())
                    wall.components.set(
                        CollisionComponent(shapes: [
                            .generateBox(width: unitSize, height: 0.2, depth: 0.05)
                        ]))
                    wall.name = "Wall"
                    parent.addChild(wall)
                }

                // [NEW] Border Checks: North and West
                // Only needed for y==0 (North) and x==0 (West) because internal walls are covered by the neighbor's South/East

                if y == 0 && cell.walls[.north] == true {
                    let wall = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
                    // No Rotation
                    // wall.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    wall.position = basePosition + SIMD3<Float>(0, 0.1, -unitSize / 2)
                    wall.components.set(wallPhysicsComponent())
                    wall.components.set(
                        CollisionComponent(shapes: [
                            .generateBox(width: unitSize, height: 0.2, depth: 0.05)
                        ]))
                    wall.name = "Wall"
                    parent.addChild(wall)
                }

                if x == 0 && cell.walls[.west] == true {
                    let wall = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
                    wall.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    wall.position = basePosition + SIMD3<Float>(-unitSize / 2, 0.1, 0)
                    wall.components.set(wallPhysicsComponent())
                    wall.components.set(
                        CollisionComponent(shapes: [
                            .generateBox(width: unitSize, height: 0.2, depth: 0.05)
                        ]))
                    wall.name = "Wall"
                    parent.addChild(wall)
                }

                // Note: No longer need 'createHoleTrigger' because the hole is now a physical gap!
            }
        }
    }

    private func wallPhysicsComponent() -> PhysicsBodyComponent {
        var physics = PhysicsBodyComponent(massProperties: .default, mode: .kinematic)
        physics.material = .generate(staticFriction: 0.1, dynamicFriction: 0.1, restitution: 0.1)
        return physics
    }

    private func createStartZone(parent: Entity) {
        // Visual marker for the start (Blue Pad on Floor)
        // Cylinder height 0.01, radius 0.3
        let markerMesh = MeshResource.generateBox(width: 0.6, height: 0.01, depth: 0.6)
        var markerMat = SimpleMaterial(color: .blue, isMetallic: false)
        // Make it slightly transparent?
        // markerMat.baseColor = MaterialColorParameter.color(UIColor.blue.withAlphaComponent(0.5))
        // SimpleMaterial doesn't support alpha well in non-PBR. Use PBR if needed.
        // Just solid blue is fine.

        let marker = ModelEntity(mesh: markerMesh, materials: [markerMat])
        marker.position = [0, 0.01, 0]  // Just above floor limit (0 and -0.05)
        marker.name = "StartMarker"

        // No collision, just visual guide
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
        marble.components.set(physicsBody)
        marble.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.15)]))

        parent.addChild(marble)
    }
}
