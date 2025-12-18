//
//  HapticManager.swift
//  aethermaze
//
//  Created by Marc L. Melcher on 12/16/25.
//

import Foundation

#if os(iOS)
    import UIKit
#endif

class HapticManager {
    static let shared = HapticManager()

    private init() {}

    func playCollisionHaptic() {
        #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        #endif
    }

    func playSuccessHaptic() {
        #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        #endif
    }

    func playFailureHaptic() {
        #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        #endif
    }

    private var lastRollingHapticTime: TimeInterval = 0

    func playRollingHaptic(intensity: Float) {
        #if os(iOS)
            let now = Date().timeIntervalSince1970
            // Throttle to max 10 times per second
            guard now - lastRollingHapticTime > 0.1 else { return }

            if intensity > 0.2 {
                let generator = UISelectionFeedbackGenerator()
                generator.prepare()
                generator.selectionChanged()
                lastRollingHapticTime = now
            }
        #endif
    }
}
