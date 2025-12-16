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
}
