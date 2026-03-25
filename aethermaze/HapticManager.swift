//
//  HapticManager.swift
//  aethermaze
//
//  Created by Marc L. Melcher on 12/16/25.
//

import Foundation
import SwiftUI

#if os(iOS)
    import UIKit
#endif

class HapticManager {
    static let shared = HapticManager()

    var isHapticsEnabled: Bool = true

    private init() {
        if let _ = UserDefaults.standard.object(forKey: "isHapticsEnabled") {
            isHapticsEnabled = UserDefaults.standard.bool(forKey: "isHapticsEnabled")
        }
    }

    func playCollisionHaptic() {
        guard isHapticsEnabled else { return }
        #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        #endif
    }

    func playSuccessHaptic() {
        guard isHapticsEnabled else { return }
        #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        #endif
    }

    func playFailureHaptic() {
        guard isHapticsEnabled else { return }
        #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        #endif
    }

    private var lastRollingHapticTime: TimeInterval = 0

    func playRollingHaptic(intensity: Float) {
        guard isHapticsEnabled else { return }
        #if os(iOS)
            let now = Date().timeIntervalSince1970
            // Throttle to max 5 times per second
            guard now - lastRollingHapticTime > 0.2 else { return }

            if intensity > 0.3 {
                let generator = UISelectionFeedbackGenerator()
                generator.prepare()
                generator.selectionChanged()
                lastRollingHapticTime = now
            }
        #endif
    }
}
