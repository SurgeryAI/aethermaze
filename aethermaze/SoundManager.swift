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
    private var effectsPlayerNode: AVAudioPlayerNode!  // For discrete SFX
    private var equalizer: AVAudioUnitEQ!

    private var lastRollBurstTime: TimeInterval = 0
    private var lastImpactTime: TimeInterval = 0
    private let marbleRadius: Double = 0.15  // meters (adjust to your marble's size)

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
        effectsPlayerNode = AVAudioPlayerNode()

        // Create a Low Pass Filter to simulate muffling of rolling
        equalizer = AVAudioUnitEQ(numberOfBands: 1)
        let filterParams = equalizer.bands[0]
        filterParams.filterType = .lowPass
        filterParams.frequency = 1000.0  // Base frequency
        filterParams.bypass = false

        engine.attach(playerNode)
        engine.attach(effectsPlayerNode)
        engine.attach(equalizer)

        let format = engine.outputNode.inputFormat(forBus: 0)

        // Connect Rolling Player: Player -> EQ -> MainMixer
        engine.connect(playerNode, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)

        // Connect Effects Player: Direct to MainMixer
        engine.connect(effectsPlayerNode, to: engine.mainMixerNode, format: format)

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

    // Synthesize a punchy "thud" for wall impacts
    private func generateImpactBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 0.15
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        let channelCount = Int(format.channelCount)

        for ch in 0..<channelCount {
            let data = buffer.floatChannelData![ch]
            for i in 0..<Int(frameCount) {
                let time = Double(i) / format.sampleRate
                let envelope = exp(-time * 25.0)  // Fast decay
                let noise = Float.random(in: -1.0...1.0) * 0.15  // Reduced from 0.3
                let sine = sin(2.0 * .pi * 80.0 * time) * 0.35  // Reduced from 0.7
                data[i] = Float(sine + Double(noise)) * Float(envelope)
            }
        }
        return buffer
    }

    // Synthesize a descending "whistle/whoosh" for hole falls
    private func generateFallBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 0.8
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        let channelCount = Int(format.channelCount)

        for ch in 0..<channelCount {
            let data = buffer.floatChannelData![ch]
            for i in 0..<Int(frameCount) {
                let time = Double(i) / format.sampleRate
                let progress = time / duration
                let freq = 600.0 * (1.0 - progress)  // Descending frequency
                let envelope = sin(.pi * progress) * (1.0 - progress)  // Fade in and out
                let sine = sin(2.0 * .pi * freq * time)
                data[i] = Float(sine) * Float(envelope) * 0.5
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
            playerNode.volume = 0.5
            playerNode.play()
        }
        if !effectsPlayerNode.isPlaying {
            effectsPlayerNode.play()
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

    // Helper to load a .wav or .mp3 from the App Bundle into a PCM buffer
    private func loadBuffer(fromResource resource: String, withExtension ext: String)
        -> AVAudioPCMBuffer?
    {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length))
            else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            print("❌ Error loading sound asset '\(resource).\(ext)': \(error)")
            return nil
        }
    }

    func playWallImpactSound() {
        guard isSoundEnabled else { return }

        // Cooldown check (e.g., 100ms) to prevent excessive noise frequency
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastImpactTime > 0.1 else { return }
        lastImpactTime = now

        let format = engine.outputNode.inputFormat(forBus: 0)

        // 1. Try to load from App Bundle (Kenney assets etc.)
        if let assetBuffer = loadBuffer(fromResource: "impact", withExtension: "wav") {
            effectsPlayerNode.scheduleBuffer(
                assetBuffer, at: nil, options: [], completionHandler: nil)
            return
        }

        // 2. Fallback to Synthesized sound if no asset is present
        if let buffer = generateImpactBuffer(format: format) {
            effectsPlayerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }

    func playFallSound() {
        guard isSoundEnabled else { return }
        let format = engine.outputNode.inputFormat(forBus: 0)

        // 1. Try to load from App Bundle
        if let assetBuffer = loadBuffer(fromResource: "fall", withExtension: "wav") {
            effectsPlayerNode.scheduleBuffer(
                assetBuffer, at: nil, options: [], completionHandler: nil)
            return
        }

        // 2. Fallback to Synthesized sound
        if let buffer = generateFallBuffer(format: format) {
            effectsPlayerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
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
