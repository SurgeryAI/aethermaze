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

        placeStartAndEnd(size: size)
        placeHoles(level: level)

        // Pass the parent entity to these functions
        create3DFloor(parent: parent)
        create3DWalls(parent: parent)
        create3DMarble(parent: parent)
        createDeathPlane(parent: parent)
        createWinZone(size: size, parent: parent)
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
        let tileMesh = MeshResource.generateBox(width: unitSize, height: 0.1, depth: unitSize)

        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: .brown)
        floorMaterial.roughness = 0.8

        for (y, row) in mazeMap.enumerated() {
            for (x, cell) in row.enumerated() {
                if !cell.hasHole {
                    let tile = ModelEntity(mesh: tileMesh, materials: [floorMaterial])
                    // Position: Center of the cell
                    tile.position = [Float(x) * unitSize, -0.05, Float(y) * unitSize]

                    tile.components.set(
                        PhysicsBodyComponent(massProperties: .default, mode: .kinematic))
                    tile.components.set(
                        CollisionComponent(shapes: [
                            .generateBox(width: unitSize, height: 0.1, depth: unitSize)
                        ]))

                    parent.addChild(tile)
                }
            }
        }
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

        // Visual marker for the end (Green flag/light)
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

                if cell.walls[.east] == true {
                    let wall = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
                    wall.position = basePosition + SIMD3<Float>(unitSize / 2, 0.1, 0)
                    wall.components.set(wallPhysicsComponent())
                    wall.components.set(
                        CollisionComponent(shapes: [
                            .generateBox(width: unitSize, height: 0.2, depth: 0.05)
                        ]))
                    wall.name = "Wall"  // [NEW] Name for collision detection
                    parent.addChild(wall)
                }

                if cell.walls[.south] == true {
                    let wall = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
                    wall.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    wall.position = basePosition + SIMD3<Float>(0, 0.1, unitSize / 2)
                    wall.components.set(wallPhysicsComponent())
                    wall.components.set(
                        CollisionComponent(shapes: [
                            .generateBox(width: unitSize, height: 0.2, depth: 0.05)
                        ]))
                    wall.name = "Wall"  // [NEW] Name for collision detection
                    parent.addChild(wall)
                }

                // Note: No longer need 'createHoleTrigger' because the hole is now a physical gap!
            }
        }
    }

    private func wallPhysicsComponent() -> PhysicsBodyComponent {
        var physics = PhysicsBodyComponent(massProperties: .default, mode: .kinematic)
        physics.material = .generate(staticFriction: 0.1, dynamicFriction: 0.1, restitution: 0.5)
        return physics
    }

    private func create3DMarble(parent: Entity) {
        let marbleMesh = MeshResource.generateSphere(radius: 0.15)  // Slightly larger marble

        var marbleMaterial = PhysicallyBasedMaterial()
        marbleMaterial.baseColor = .init(tint: .white)
        marbleMaterial.metallic = 1.0
        marbleMaterial.roughness = 0.1

        let marble = ModelEntity(mesh: marbleMesh, materials: [marbleMaterial])
        marble.name = "Marble"
        marble.position = [0.0, 0.5, 0.0]

        let physicsBody = PhysicsBodyComponent(
            massProperties: .default, material: .generate(friction: 0.5, restitution: 0.5),
            mode: .dynamic)
        marble.components.set(physicsBody)
        marble.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.15)]))

        parent.addChild(marble)
    }
}
