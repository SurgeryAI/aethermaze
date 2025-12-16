//
//  GravityVector.swift
//  aethermaze
//
//  Created by Marc L. Melcher on 12/16/25.
//


import CoreMotion
import Combine
import SwiftUI

// Struct to represent the gravity vector applied to the scene
struct GravityVector {
    let x: Float
    let y: Float
    let z: Float
}

// Observable object to manage device motion updates
final class MotionController: ObservableObject {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    
    // Published property to notify views/logic of new gravity values
    @Published var currentGravity = GravityVector(x: 0, y: -9.8, z: 0)
    
    private let tiltMultiplier: Float = 25.0 // Controls sensitivity

    init() {
        startMotionUpdates()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Core Motion is not available on this device.")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0 // 60 updates per second
        queue.qualityOfService = .userInteractive

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] (motion, error) in
            guard let self = self, let data = motion else { return }

            // Get attitude components for smooth, filtered rotation data
            let roll = data.attitude.roll // Tilt Left/Right
            let pitch = data.attitude.pitch // Tilt Forward/Backward

            // Update the published gravity vector on the main thread
            DispatchQueue.main.async {
                self.currentGravity = GravityVector(
                    x: Float(sin(roll)) * self.tiltMultiplier,
                    y: -9.8, // Constant downward force
                    z: Float(sin(pitch)) * self.tiltMultiplier
                )
            }
        }
    }
}