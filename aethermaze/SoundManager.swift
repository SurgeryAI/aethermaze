//
// To guarantee immediate muting if velocity updates stop,
// call checkRollingSoundTimeout() regularly in your main update/game loop.
//

import AVFoundation
import Combine
import SwiftUI

class SoundManager {

    static let shared = SoundManager()

    private var engine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var equalizer: AVAudioUnitEQ!

    private var lastRollBurstTime: TimeInterval = 0
    private let marbleRadius: Double = 0.15  // meters (adjust to your marble's size)

    private var impactPlayer: AVAudioPlayer?

    var isSoundEnabled: Bool {
        // If key doesn't exist (first launch), return true (enabled by default)
        // Otherwise return the stored value
        let exists = UserDefaults.standard.object(forKey: "isSoundEnabled") != nil
        let value: Bool
        if !exists {
            value = true
            print("🔊 Sound setting not found, defaulting to ENABLED")
        } else {
            value = UserDefaults.standard.bool(forKey: "isSoundEnabled")
            print("🔊 Sound setting from UserDefaults: \(value ? "ENABLED" : "DISABLED")")
        }
        return value
    }

    private var isPlaying = false

    init() {
        configureAudioSession()
        setupAudioEngine()
    }

    private func configureAudioSession() {
        #if os(iOS)
            do {
                let session = AVAudioSession.sharedInstance()
                // Changed from .ambient to .playback for higher volume and priority
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                print("✅ Audio session configured successfully")
                print(
                    "📱 Audio session category: \(session.category), volume: \(session.outputVolume)"
                )
            } catch {
                print("❌ Failed to configure audio session: \(error)")
            }
        #endif
    }

    private func setupAudioEngine() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // Create a Low Pass Filter to simulate muffling of rolling
        equalizer = AVAudioUnitEQ(numberOfBands: 1)
        let filterParams = equalizer.bands[0]
        filterParams.filterType = .lowPass
        filterParams.frequency = 1000.0  // Base frequency
        filterParams.bypass = false

        engine.attach(playerNode)
        engine.attach(equalizer)

        let format = engine.outputNode.inputFormat(forBus: 0)

        // Connect: Player -> EQ -> MainMixer
        engine.connect(playerNode, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)

        // Do NOT schedule any buffer for playerNode here (no continuous rolling noise)
    }

    private func generateRollBurstBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let burstDuration: Double = 0.035  // 35 ms burst
        let frameCount = AVAudioFrameCount(format.sampleRate * burstDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        let channelCount = Int(format.channelCount)
        for channel in 0..<channelCount {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frameCount) {
                data[i] = Float.random(in: -1.0...1.0) * 0.22
            }
        }
        return buffer
    }

    func startEngine() {
        if !engine.isRunning {
            do {
                try engine.start()
                print("Audio Engine started successfully")
            } catch {
                print("Audio Engine failed: \(error)")
            }
        }
        if !playerNode.isPlaying {
            // Do not schedule buffer here; play is called only when scheduling bursts
            playerNode.volume = 0.5
        }
    }

    func updateRollingSound(velocity: Float) {
        // Debug: Check if sound is enabled
        print(
            "🔊 updateRollingSound called - velocity: \(velocity), isSoundEnabled: \(isSoundEnabled)"
        )

        guard isSoundEnabled else {
            print("🔇 Sound is DISABLED, stopping player")
            if playerNode.isPlaying {
                playerNode.stop()
            }
            return
        }

        let speed = Double(velocity)
        let minSpeed = 0.25  // meters/sec: only roll at meaningful speed
        if speed < minSpeed {
            print("⚡️ Speed too low (\(speed) < \(minSpeed)), stopping player")
            if playerNode.isPlaying {
                playerNode.stop()
            }
            return
        }

        // Calculate roll frequency: f = v / (2πr)
        let rollFreq = max(speed / (2 * .pi * marbleRadius), 1.0)
        let now = Date().timeIntervalSinceReferenceDate
        let interval = 1.0 / rollFreq

        if now - lastRollBurstTime > interval {
            lastRollBurstTime = now
            print("🎵 Playing sound burst - speed: \(speed), rollFreq: \(rollFreq)")

            // Schedule a short noise burst
            let format = engine.outputNode.inputFormat(forBus: 0)
            if let burst = generateRollBurstBuffer(format: format) {
                playerNode.scheduleBuffer(burst, at: nil, options: [], completionHandler: nil)
                if !playerNode.isPlaying {
                    print("▶️ Starting playerNode.play()")
                    playerNode.play()
                }
            } else {
                print("❌ Failed to generate burst buffer")
            }
        }
    }

    func playImpactSound() {
        guard isSoundEnabled else { return }
        if let url = Bundle.main.url(forResource: "impact", withExtension: "wav") {
            impactPlayer = try? AVAudioPlayer(contentsOf: url)
            impactPlayer?.volume = 1.0
            impactPlayer?.prepareToPlay()
            impactPlayer?.play()
        }
    }

    /// Call this regularly (e.g. from your game loop) to ensure rolling sound is muted if updates stop
    func checkRollingSoundTimeout() {
        let now = Date().timeIntervalSinceReferenceDate
        // If no rolling sound burst in the last 0.25 seconds, stop playerNode if playing
        if now - lastRollBurstTime > 0.25 {
            if playerNode.isPlaying {
                playerNode.stop()
            }
        }
    }
}
