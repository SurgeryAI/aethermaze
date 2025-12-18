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

    func buildLevel(level: Int, width: Int, height: Int, parent: Entity) {
        mazeMap = Array(repeating: Array(repeating: MazeCell(), count: width), count: height)

        generateRecursiveBacktracker(width: width, height: height)
        removeRandomWalls(width: width, height: height, percentage: 0.10)
        placeHoles(level: level, width: width, height: height)
        placeStartAndEnd(width: width, height: height)

        createRefinedFloor(width: width, height: height, parent: parent)
        createRefinedWalls(parent: parent)
        createStartZone(parent: parent)
        createWinZone(width: width, height: height, parent: parent)
        create3DMarble(parent: parent)
        createDeathPlane(parent: parent)
    }

    // MARK: - Procedural Maze Algorithm
    private func generateRecursiveBacktracker(width: Int, height: Int) {
        var stack: [(Int, Int)] = []
        let startX = 0
        let startY = 0
        stack.append((startX, startY))
        mazeMap[startY][startX].isVisited = true

        while !stack.isEmpty {
            let current = stack.last!
            let (cx, cy) = current
            var neighbors: [(Direction, (Int, Int))] = []

            if cy > 0 && !mazeMap[cy - 1][cx].isVisited { neighbors.append((.north, (cx, cy - 1))) }
            if cy < height - 1 && !mazeMap[cy + 1][cx].isVisited {
                neighbors.append((.south, (cx, cy + 1)))
            }
            if cx < width - 1 && !mazeMap[cy][cx + 1].isVisited {
                neighbors.append((.east, (cx + 1, cy)))
            }
            if cx > 0 && !mazeMap[cy][cx - 1].isVisited { neighbors.append((.west, (cx - 1, cy))) }

            if !neighbors.isEmpty {
                let chosen = neighbors.randomElement()!
                let (dir, (nx, ny)) = chosen
                mazeMap[cy][cx].walls[dir] = false
                switch dir {
                case .north: mazeMap[ny][nx].walls[.south] = false
                case .south: mazeMap[ny][nx].walls[.north] = false
                case .east: mazeMap[ny][nx].walls[.west] = false
                case .west: mazeMap[ny][nx].walls[.east] = false
                }
                mazeMap[ny][nx].isVisited = true
                stack.append((nx, ny))
            } else {
                stack.removeLast()
            }
        }
    }

    private func placeStartAndEnd(width: Int, height: Int) {
        if width > 0 && height > 0 {
            mazeMap[0][0].hasHole = false
            mazeMap[height - 1][width - 1].hasHole = false
        }
    }

    private func removeRandomWalls(width: Int, height: Int, percentage: Double) {
        for y in 0..<height {
            for x in 0..<width {
                if x < width - 1 && mazeMap[y][x].walls[.east] == true {
                    if Double.random(in: 0...1) < percentage {
                        mazeMap[y][x].walls[.east] = false
                        mazeMap[y][x + 1].walls[.west] = false
                    }
                }
                if y < height - 1 && mazeMap[y][x].walls[.south] == true {
                    if Double.random(in: 0...1) < percentage {
                        mazeMap[y][x].walls[.south] = false
                        mazeMap[y + 1][x].walls[.north] = false
                    }
                }
            }
        }
    }

    private func placeHoles(level: Int, width: Int, height: Int) {
        guard let solutionPath = solveMazeBFS(width: width, height: height) else { return }
        let pathSet = Set(solutionPath.map { "\($0.x),\($0.y)" })
        let totalCells = Double(width * height)
        let numHoles = max(2 + level, Int(totalCells * 0.05))

        var holesPlaced = 0
        var attempts = 0
        while holesPlaced < numHoles && attempts < 200 {
            attempts += 1
            let rx = Int.random(in: 0..<width)
            let ry = Int.random(in: 0..<height)
            if (rx == 0 && ry == 0) || (rx == width - 1 && ry == height - 1) { continue }
            if pathSet.contains("\(rx),\(ry)") { continue }
            if mazeMap[ry][rx].hasHole { continue }
            mazeMap[ry][rx].hasHole = true
            holesPlaced += 1
        }
    }

    struct Point: Hashable { let x: Int, y: Int }
    private func solveMazeBFS(width: Int, height: Int) -> [Point]? {
        let start = Point(x: 0, y: 0)
        let end = Point(x: width - 1, y: height - 1)
        var queue: [Point] = [start]
        var cameFrom: [Point: Point] = [:]
        var visited = Set<Point>([start])
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current == end {
                var path: [Point] = []
                var p: Point? = current
                while let point = p {
                    path.append(point)
                    p = cameFrom[point]
                }
                return path
            }
            let cell = mazeMap[current.y][current.x]
            let neighbors: [(Direction, Point)] = [
                (.north, Point(x: current.x, y: current.y - 1)),
                (.south, Point(x: current.x, y: current.y + 1)),
                (.east, Point(x: current.x + 1, y: current.y)),
                (.west, Point(x: current.x - 1, y: current.y)),
            ]
            for (dir, next) in neighbors {
                if next.x >= 0 && next.x < width && next.y >= 0 && next.y < height
                    && !cell.walls[dir]! && !visited.contains(next)
                {
                    visited.insert(next)
                    cameFrom[next] = current
                    queue.append(next)
                }
            }
        }
        return nil
    }

    // MARK: - 3D Generation
    private func createRefinedFloor(width: Int, height: Int, parent: Entity) {
        let floorEntity = Entity()
        floorEntity.name = "RefinedFloor"
        if let combinedMesh = generateContiguousFloorMesh(width: width, height: height) {
            var floorMaterial = PhysicallyBasedMaterial()
            // Lighter, polished wood for the floor
            floorMaterial.baseColor = .init(
                tint: .init(red: 0.55, green: 0.38, blue: 0.22, alpha: 1.0))
            floorMaterial.roughness = 0.4
            floorMaterial.metallic = 0.1
            let model = ModelEntity(mesh: combinedMesh, materials: [floorMaterial])
            floorEntity.addChild(model)
        }
        var shapes: [ShapeResource] = []
        for y in 0..<height {
            var x = 0
            while x < width {
                if !mazeMap[y][x].hasHole {
                    let startX = x
                    while x < width && !mazeMap[y][x].hasHole {
                        x += 1
                    }
                    let count = Float(x - startX)
                    // Center point of the merged span
                    let centerX = (Float(startX) + (count - 1) / 2.0) * unitSize
                    let pos: SIMD3<Float> = [centerX, -0.05, Float(y) * unitSize]
                    shapes.append(
                        ShapeResource.generateBox(
                            width: count * unitSize, height: 1.0, depth: unitSize
                        ).offsetBy(translation: pos + [0, -0.45, 0]))
                } else {
                    x += 1
                }
            }
        }
        let solidGroup = CollisionGroup(rawValue: 1 << 0)
        floorEntity.components.set(
            CollisionComponent(
                shapes: shapes,
                filter: CollisionFilter(group: solidGroup, mask: solidGroup)
            ))
        floorEntity.components.set(
            PhysicsBodyComponent(
                massProperties: .default,
                material: .generate(staticFriction: 0.2, dynamicFriction: 0.2, restitution: 0.0),
                mode: .kinematic))
        parent.addChild(floorEntity)

        if let holeMesh = generateHoleTileMesh() {
            var holeMaterial = PhysicallyBasedMaterial()
            holeMaterial.baseColor = .init(
                tint: .init(red: 0.45, green: 0.3, blue: 0.15, alpha: 1.0))
            holeMaterial.roughness = 0.6
            holeMaterial.metallic = 0.05
            for y in 0..<height {
                for x in 0..<width {
                    if mazeMap[y][x].hasHole {
                        let holeTile = ModelEntity(mesh: holeMesh, materials: [holeMaterial])
                        holeTile.position = [Float(x) * unitSize, -0.05, Float(y) * unitSize]
                        let sideW = (unitSize - 0.8) / 2.0
                        let h: Float = 0.5  // Thicker floor for stability
                        let hs = [
                            ShapeResource.generateBox(size: [sideW, h, unitSize]).offsetBy(
                                translation: [-(unitSize / 2) + (sideW / 2), -0.2, 0]),
                            ShapeResource.generateBox(size: [sideW, h, unitSize]).offsetBy(
                                translation: [(unitSize / 2) - (sideW / 2), -0.2, 0]),
                            ShapeResource.generateBox(size: [unitSize - sideW * 2, h, sideW])
                                .offsetBy(translation: [0, -0.2, -(unitSize / 2) + (sideW / 2)]),
                            ShapeResource.generateBox(size: [unitSize - sideW * 2, h, sideW])
                                .offsetBy(translation: [0, -0.2, (unitSize / 2) - (sideW / 2)]),
                        ]
                        let solidGroup = CollisionGroup(rawValue: 1 << 0)
                        holeTile.components.set(
                            CollisionComponent(
                                shapes: hs,
                                filter: CollisionFilter(group: solidGroup, mask: solidGroup)
                            ))
                        holeTile.components.set(
                            PhysicsBodyComponent(
                                massProperties: .default,
                                material: .generate(friction: 0.2, restitution: 0.0),
                                mode: .kinematic))
                        parent.addChild(holeTile)
                    }
                }
            }
        }
    }

    private func generateContiguousFloorMesh(width: Int, height: Int) -> MeshResource? {
        var desc = MeshDescriptor()
        var pos: [SIMD3<Float>] = []
        var norm: [SIMD3<Float>] = []
        var ind: [UInt32] = []
        var uvs: [SIMD2<Float>] = []
        for z in 0...height {
            for x in 0...width {
                pos.append([
                    Float(x) * unitSize - unitSize / 2, 0, Float(z) * unitSize - unitSize / 2,
                ])
                norm.append([0, 1, 0])
                uvs.append([Float(x), Float(z)])
            }
        }
        for z in 0..<height {
            for x in 0..<width {
                if !mazeMap[z][x].hasHole {
                    let v0 = UInt32(z) * UInt32(width + 1) + UInt32(x)
                    let v1 = v0 + 1
                    let v2 = v0 + UInt32(width + 1)
                    let v3 = v2 + 1
                    ind.append(contentsOf: [v0, v3, v1, v0, v2, v3])
                }
            }
        }
        desc.positions = .init(pos)
        desc.normals = .init(norm)
        desc.textureCoordinates = .init(uvs)
        desc.primitives = .triangles(ind)
        return try? MeshResource.generate(from: [desc])
    }

    private func createRefinedWalls(parent: Entity) {
        let wallH: Float = 0.8
        let wallT: Float = 0.32  // Refined thickness (20% thinner than 0.4)
        var meshData: [(Transform, SIMD3<Float>)] = []
        var collisionData: [(Transform, SIMD3<Float>)] = []

        for (y, row) in mazeMap.enumerated() {
            for (x, cell) in row.enumerated() {
                let basePos = SIMD3<Float>(
                    Float(x) * unitSize, wallH / 2 - 0.01, Float(y) * unitSize)
                let shimmerOffset: Float = 0.002
                // Visual size includes a tiny overlap to prevent light leaks/seams
                let visualSize = SIMD3<Float>(unitSize + wallT + 0.001, wallH, wallT)
                // Physics size is exact to prevent corner jitter
                let collisionSize = SIMD3<Float>(unitSize + wallT, wallH, wallT)

                // Horizontal Walls (East-West alignment)
                if cell.walls[.south] == true {
                    var t = Transform()
                    t.translation = basePos + [0, 0, unitSize / 2]

                    var visualT = t
                    visualT.translation.y += shimmerOffset
                    meshData.append((visualT, visualSize))

                    var collT = t
                    collT.translation.y = wallH / 2
                    collisionData.append((collT, collisionSize))
                }
                if y == 0 && cell.walls[.north] == true {
                    var t = Transform()
                    t.translation = basePos + [0, 0, -unitSize / 2]

                    var visualT = t
                    visualT.translation.y += shimmerOffset
                    meshData.append((visualT, visualSize))

                    var collT = t
                    collT.translation.y = wallH / 2
                    collisionData.append((collT, collisionSize))
                }

                // Vertical Walls (North-South alignment)
                if cell.walls[.east] == true {
                    var t = Transform()
                    t.rotation = .init(angle: .pi / 2, axis: [0, 1, 0])
                    t.translation = basePos + [unitSize / 2, 0, 1e-5]

                    var visualT = t
                    visualT.translation.y -= shimmerOffset
                    meshData.append((visualT, visualSize))

                    var collT = t
                    collT.translation.y = wallH / 2
                    collisionData.append((collT, collisionSize))
                }
                if x == 0 && cell.walls[.west] == true {
                    var t = Transform()
                    t.rotation = .init(angle: .pi / 2, axis: [0, 1, 0])
                    t.translation = basePos + [-unitSize / 2, 0, 1e-5]

                    var visualT = t
                    visualT.translation.y -= shimmerOffset
                    meshData.append((visualT, visualSize))

                    var collT = t
                    collT.translation.y = wallH / 2
                    collisionData.append((collT, collisionSize))
                }
            }
        }
        if meshData.isEmpty { return }
        let walls = Entity()
        walls.name = "RefinedWalls"
        if let mesh = generateWallMesh(data: meshData) {
            var mat = PhysicallyBasedMaterial()
            // Even more premium mahogany wood
            mat.baseColor = .init(tint: .init(red: 0.32, green: 0.18, blue: 0.1, alpha: 1.0))
            mat.roughness = 0.5
            mat.metallic = 0.08
            walls.addChild(ModelEntity(mesh: mesh, materials: [mat]))
        }
        var shapes: [ShapeResource] = []
        for (t, s) in collisionData {
            shapes.append(
                ShapeResource.generateBox(size: s).offsetBy(
                    rotation: t.rotation, translation: t.translation))
        }
        let solidGroup = CollisionGroup(rawValue: 1 << 0)
        walls.components.set(
            CollisionComponent(
                shapes: shapes,
                filter: CollisionFilter(group: solidGroup, mask: solidGroup)
            ))
        walls.components.set(
            PhysicsBodyComponent(
                massProperties: .default, material: .generate(friction: 0.2, restitution: 0.0),
                mode: .kinematic))
        parent.addChild(walls)
    }

    private func generateWallMesh(data: [(Transform, SIMD3<Float>)]) -> MeshResource? {
        var desc = MeshDescriptor()
        var pos: [SIMD3<Float>] = []
        var norm: [SIMD3<Float>] = []
        var ind: [UInt32] = []
        var uvs: [SIMD2<Float>] = []
        for (i, (t, s)) in data.enumerated() {
            let offset = UInt32(i * 24)
            let h = s / 2.0
            let m = t.matrix
            let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
                (
                    [0, 1, 0],
                    [[-h.x, h.y, -h.z], [h.x, h.y, -h.z], [h.x, h.y, h.z], [-h.x, h.y, h.z]]
                ),
                (
                    [0, -1, 0],
                    [
                        [-h.x, -h.y, h.z], [h.x, -h.y, h.z], [h.x, -h.y, -h.z], [-h.x, -h.y, -h.z],
                    ]
                ),
                (
                    [0, 0, 1],
                    [[-h.x, -h.y, h.z], [-h.x, h.y, h.z], [h.x, h.y, h.z], [h.x, -h.y, h.z]]
                ),
                (
                    [0, 0, -1],
                    [
                        [h.x, -h.y, -h.z], [h.x, h.y, -h.z], [-h.x, h.y, -h.z], [-h.x, -h.y, -h.z],
                    ]
                ),
                (
                    [-1, 0, 0],
                    [
                        [-h.x, -h.y, -h.z], [-h.x, h.y, -h.z], [-h.x, h.y, h.z], [-h.x, -h.y, h.z],
                    ]
                ),
                (
                    [1, 0, 0],
                    [[h.x, -h.y, h.z], [h.x, h.y, h.z], [h.x, h.y, -h.z], [h.x, -h.y, -h.z]]
                ),
            ]
            for (fn, fv) in faces {
                let n = normalize(simd_make_float3(m * simd_make_float4(fn, 0)))
                for v in fv {
                    pos.append(simd_make_float3(m * simd_make_float4(v, 1)))
                    norm.append(n)
                    uvs.append([0, 0])
                }
            }
            for f in 0..<6 {
                let fo = offset + UInt32(f * 4)
                // Fix Winding Order (CCW: Outward facing)
                ind.append(contentsOf: [fo, fo + 2, fo + 1, fo, fo + 3, fo + 2])
            }
        }
        desc.positions = .init(pos)
        desc.normals = .init(norm)
        desc.textureCoordinates = .init(uvs)
        desc.primitives = .triangles(ind)
        return try? MeshResource.generate(from: [desc])
    }

    private func createWinZone(width: Int, height: Int, parent: Entity) {
        let wz = Entity()
        wz.name = "WinZone"
        wz.position = [Float(width - 1) * unitSize, 0, Float(height - 1) * unitSize]

        // Create a 'Trigger' group (group 2) that doesn't physically collide with the marble
        let triggerGroup = CollisionGroup(rawValue: 1 << 1)
        let solidGroup = CollisionGroup(rawValue: 1 << 0)

        wz.components.set(
            CollisionComponent(
                shapes: [.generateBox(size: [0.8, 1, 0.8])],
                filter: CollisionFilter(group: triggerGroup, mask: solidGroup)  // Only interests solids (for events)
            ))

        // Premium Neon Goal
        var winMat = PhysicallyBasedMaterial()
        winMat.baseColor = .init(tint: .init(red: 0.1, green: 0.8, blue: 0.2, alpha: 1.0))
        winMat.emissiveColor = .init(color: .green)
        winMat.emissiveIntensity = 2.0
        winMat.roughness = 0.1
        winMat.metallic = 0.9

        let pm = MeshResource.generateBox(size: [0.6, 0.02, 0.6])
        let p = ModelEntity(mesh: pm, materials: [winMat])
        p.position = [0, 0.01, 0]
        wz.addChild(p)

        // Floating Beacon
        let mm = MeshResource.generateSphere(radius: 0.15)
        let m = ModelEntity(mesh: mm, materials: [winMat])
        m.position = [0, 0.4, 0]
        wz.addChild(m)
        parent.addChild(wz)
    }

    private func createStartZone(parent: Entity) {
        // Tech Marker Base
        var baseMat = PhysicallyBasedMaterial()
        baseMat.baseColor = .init(tint: .gray)
        baseMat.metallic = 1.0
        baseMat.roughness = 0.1

        let m = ModelEntity(
            mesh: .generateBox(size: [0.65, 0.015, 0.65]),
            materials: [baseMat])
        m.position = [0, 0.01, 0]
        m.name = "StartMarker"

        // Glowing Core
        var coreMat = PhysicallyBasedMaterial()
        coreMat.baseColor = .init(tint: .cyan)
        coreMat.emissiveColor = .init(color: .cyan)
        coreMat.emissiveIntensity = 3.0

        let core = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: 0.2), materials: [coreMat])
        core.position = [0, 0.01, 0]
        m.addChild(core)

        parent.addChild(m)
    }

    private func create3DMarble(parent: Entity) {
        var marbleMaterial = PhysicallyBasedMaterial()
        // Shiny Chrome / Silver look
        marbleMaterial.baseColor = .init(tint: .init(white: 0.8, alpha: 1.0))
        marbleMaterial.roughness = 0.05
        marbleMaterial.metallic = 1.0
        let m = ModelEntity(
            mesh: .generateSphere(radius: 0.15), materials: [marbleMaterial])
        m.name = "Marble"
        m.position = [0, 0.2, 0]
        var p = PhysicsBodyComponent(
            massProperties: .default, material: .generate(friction: 0.5, restitution: 0.0),
            mode: .dynamic)
        p.linearDamping = 0.5
        p.angularDamping = 0.5
        p.isContinuousCollisionDetectionEnabled = true
        m.components.set(p)
        let solidGroup = CollisionGroup(rawValue: 1 << 0)
        let triggerGroup = CollisionGroup(rawValue: 1 << 1)

        m.components.set(
            CollisionComponent(
                shapes: [.generateSphere(radius: 0.15)],
                filter: CollisionFilter(group: solidGroup, mask: [solidGroup, triggerGroup])
            ))
        // Note: Marble mask includes triggerGroup so events fire,
        // but since WinZone has no dynamic physics body and filtering is set, it won't push.

        parent.addChild(m)
    }

    private func createDeathPlane(parent: Entity) {
        let d = Entity()
        d.name = "DeathPlane"
        d.position = [0, -3.0, 0]
        d.components.set(
            CollisionComponent(shapes: [.generateBox(width: 100, height: 0.1, depth: 100)]))
        d.components.set(PhysicsBodyComponent(massProperties: .default, mode: .kinematic))
        parent.addChild(d)
    }

    private func generateHoleTileMesh() -> MeshResource? {
        var desc = MeshDescriptor()
        var pos: [SIMD3<Float>] = []
        var norm: [SIMD3<Float>] = []
        var ind: [UInt32] = []
        var uvs: [SIMD2<Float>] = []
        let r = unitSize * 0.4
        let yt: Float = 0.05
        let hs = unitSize / 2
        let seg = 32
        for i in 0...seg {
            let a = (Float(i) / Float(seg)) * .pi * 2
            let ix = cos(a) * r
            let iz = sin(a) * r
            var ox: Float = 0
            var oz: Float = 0
            if abs(ix) >= abs(iz) {
                ox = (ix > 0 ? hs : -hs)
                oz = iz * (ox / ix)
            } else {
                oz = (iz > 0 ? hs : -hs)
                ox = ix * (oz / iz)
            }
            pos.append([ix, yt, iz])
            pos.append([ox, yt, oz])
            norm.append([0, 1, 0])
            norm.append([0, 1, 0])
            uvs.append([ix / unitSize + 0.5, iz / unitSize + 0.5])
            uvs.append([ox / unitSize + 0.5, oz / unitSize + 0.5])
            if i > 0 {
                let p1 = UInt32((i - 1) * 2)
                let p2 = p1 + 1
                let p3 = UInt32(i * 2)
                let p4 = p3 + 1
                ind.append(contentsOf: [p1, p4, p2, p1, p3, p4])
            }
        }
        let ws = UInt32(pos.count)
        for i in 0...seg {
            let a = (Float(i) / Float(seg)) * .pi * 2
            let ix = cos(a) * r
            let iz = sin(a) * r
            pos.append([ix, yt, iz])
            pos.append([ix, yt - 0.1, iz])
            let n = SIMD3<Float>(-ix, 0, -iz)
            norm.append(n)
            norm.append(n)
            uvs.append([0, 0])
            uvs.append([0, 1])
            if i > 0 {
                let ct = ws + UInt32(i * 2)
                let cb = ct + 1
                let pt = ws + UInt32((i - 1) * 2)
                let pb = pt + 1
                ind.append(contentsOf: [pt, ct, pb, ct, cb, pb])
            }
        }
        desc.positions = .init(pos)
        desc.normals = .init(norm)
        desc.textureCoordinates = .init(uvs)
        desc.primitives = .triangles(ind)
        return try? MeshResource.generate(from: [desc])
    }
}
