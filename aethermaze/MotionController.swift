//
//  GravityVector.swift
//  aethermaze
//
//  Created by Marc L. Melcher on 12/16/25.
//

import Combine
import CoreMotion
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

    // [NEW] Keyboard Tilt (Manual override for Simulator)
    @Published var keyboardPitch: Float = 0
    @Published var keyboardRoll: Float = 0

    private let tiltMultiplier: Float = 25.0  // Controls sensitivity (Motion)
    private let keyboardSensitivity: Float = 0.05  // Incremental tilt speed

    init() {
        startMotionUpdates()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Core Motion is not available on this device.")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 updates per second
        queue.qualityOfService = .userInteractive

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] (motion, error) in
            guard let self = self, let data = motion else { return }

            // Get attitude components for smooth, filtered rotation data
            let roll = data.attitude.roll  // Tilt Left/Right
            let pitch = data.attitude.pitch  // Tilt Forward/Backward

            // Smoothing Factor (0.0 to 1.0) - Lower = Smoother but laggier
            // 0.2 is usually a good balance for controls
            let alpha: Float = 0.2

            // Update the published gravity vector on the main thread
            DispatchQueue.main.async {
                let targetX = Float(sin(roll)) * self.tiltMultiplier
                let targetZ = Float(sin(pitch)) * self.tiltMultiplier

                // Exponential Moving Average: Current = (1-alpha)*Previous + alpha*Target
                self.currentGravity = GravityVector(
                    x: (1.0 - alpha) * self.currentGravity.x + alpha * targetX,
                    y: -9.8,
                    z: (1.0 - alpha) * self.currentGravity.z + alpha * targetZ
                )
            }
        }
    }

    // MARK: - Keyboard Handling
    func updateKeyboardTilt(pitchDelta: Float, rollDelta: Float) {
        // Clamp to a reasonable tilt (approx 30 degrees)
        keyboardPitch = max(-0.5, min(0.5, keyboardPitch + pitchDelta * keyboardSensitivity))
        keyboardRoll = max(-0.5, min(0.5, keyboardRoll + rollDelta * keyboardSensitivity))
    }

    func resetKeyboardTilt() {
        keyboardPitch = 0
        keyboardRoll = 0
    }
}
