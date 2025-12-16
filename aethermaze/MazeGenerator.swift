import RealityKit
import UIKit
import Foundation

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
    }

    // MARK: - Procedural Maze Algorithm
    private func generateRecursiveBacktracker(width: Int, height: Int) {
        // Placeholder Logic
        for y in 0..<height {
            for x in 0..<width {
                if x < width - 1 { mazeMap[y][x].walls[.east] = false }
                if y < height - 1 { mazeMap[y][x].walls[.south] = false }
            }
        }
    }
    
    private func placeStartAndEnd(size: Int) {
        if size > 0 {
            mazeMap[0][0].hasHole = false
            mazeMap[size-1][size-1].hasHole = false
        }
    }
    
    private func placeHoles(level: Int) {
        let numHoles = 1 + level
        for _ in 0..<numHoles {
            let randomX = Int.random(in: 1..<mazeMap.count - 1)
            let randomY = Int.random(in: 1..<mazeMap.count - 1)
            mazeMap[randomY][randomX].hasHole = true
        }
    }

    // MARK: - 3D Entity Creation
    
    // CHANGE: 'content.add(x)' becomes 'parent.addChild(x)'
    private func create3DFloor(parent: Entity) {
        let floorSize = Float(mazeMap.count) * unitSize
        let floorMesh = MeshResource.generatePlane(width: floorSize, depth: floorSize)
        
        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: .brown)
        floorMaterial.roughness = 0.8
        
        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floor.position = [floorSize / 2 - unitSize / 2, -0.05, floorSize / 2 - unitSize / 2]
        
        floor.components.set(PhysicsBodyComponent(massProperties: .default, mode: .static))
        parent.addChild(floor)
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
                    parent.addChild(wall)
                }
                
                if cell.walls[.south] == true {
                    let wall = ModelEntity(mesh: wallMesh, materials: [wallMaterial])
                    wall.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
                    wall.position = basePosition + SIMD3<Float>(0, 0.1, unitSize / 2)
                    wall.components.set(wallPhysicsComponent())
                    parent.addChild(wall)
                }
                
                if cell.hasHole {
                    createHoleTrigger(x: x, y: y, parent: parent)
                }
            }
        }
    }
    
    private func wallPhysicsComponent() -> PhysicsBodyComponent {
        var physics = PhysicsBodyComponent(massProperties: .default, mode: .static)
        physics.material = .generate(staticFriction: 1.0, dynamicFriction: 1.0, restitution: 0.0)
        return physics
    }
    
    private func createHoleTrigger(x: Int, y: Int, parent: Entity) {
        let triggerBox = MeshResource.generateBox(width: unitSize, height: 0.1, depth: unitSize)
        let clearMaterial = SimpleMaterial(color: .clear, isMetallic: false)
        let trigger = ModelEntity(mesh: triggerBox, materials: [clearMaterial])
        
        trigger.position = [Float(x) * unitSize, -0.2, Float(y) * unitSize]
        trigger.name = "HoleTrigger_\(x)x\(y)"

        var collision = CollisionComponent(shapes: [.generateBox(width: unitSize, height: 0.1, depth: unitSize)])
        collision.filter = CollisionFilter(group: .default, mask: .default)
        trigger.components.set(collision)
        trigger.components.set(PhysicsBodyComponent(massProperties: .default, mode: .static))
        
        parent.addChild(trigger)
    }

    private func create3DMarble(parent: Entity) {
        let marbleMesh = MeshResource.generateSphere(radius: 0.05)
        
        var marbleMaterial = PhysicallyBasedMaterial()
        marbleMaterial.baseColor = .init(tint: .white)
        marbleMaterial.metallic = 1.0
        marbleMaterial.roughness = 0.1
        
        let marble = ModelEntity(mesh: marbleMesh, materials: [marbleMaterial])
        marble.name = "Marble"
        marble.position = [0.0, 0.5, 0.0]

        let physicsBody = PhysicsBodyComponent(massProperties: .default, material: .generate(friction: 0.3, restitution: 0.7), mode: .dynamic)
        marble.components.set(physicsBody)
        marble.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.05)]))
        
        parent.addChild(marble)
    }
}
