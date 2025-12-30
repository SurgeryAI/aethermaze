import AVFoundation
import Combine
import SwiftUI

class SoundManager {

    static let shared = SoundManager()

    private var engine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var equalizer: AVAudioUnitEQ!

    var isSoundEnabled: Bool {
        // If key doesn't exist (first launch), return true (enabled by default)
        // Otherwise return the stored value
        if UserDefaults.standard.object(forKey: "isSoundEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "isSoundEnabled")
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
                try session.setCategory(.ambient, mode: .default)
                try session.setActive(true)
            } catch {
                print("Failed to configure audio session: \(error)")
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

        // Prepare Buffer (Brown Noise or similar)
        if let buffer = generateNoiseBuffer(format: format) {
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        }
    }

    private func generateNoiseBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Brown Noise: Integrate white noise. Sounds like a deep rumble/rolling.
        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let channelCount = Int(format.channelCount)
        for channel in 0..<channelCount {
            let data = buffer.floatChannelData![channel]
            var lastValue: Float = 0
            for i in 0..<Int(frameCount) {
                let white = Float.random(in: -1.0...1.0) * 0.1
                var brown = lastValue + white

                // Keep it in range (-1.0 to 1.0) and prevent DC drift
                if brown > 1.0 { brown = 2.0 - brown } else if brown < -1.0 { brown = -2.0 - brown }

                // Subtle high-pass filter to prevent DC offset build-up
                brown *= 0.99

                data[i] = brown * 0.8  // Increased base volume for better visibility
                lastValue = brown
            }
        }
        return buffer
    }

    func startEngine() {
        if !engine.isRunning {
            do {
                try engine.start()
                playerNode.volume = 0
                playerNode.play()
                isPlaying = true
            } catch {
                print("Audio Engine failed: \(error)")
            }
        }
    }

    func updateRollingSound(velocity: Float) {
        let speed = Double(velocity)
        let maxSpeed = 4.0  // Reference max speed

        let threshold: Float = 0.05  // Lower threshold
        if speed < Double(threshold) || !isSoundEnabled {
            if isPlaying {
                playerNode.volume = 0
                playerNode.pause()
                isPlaying = false
            }
            return
        }

        // Volume logic: subtle rumble
        let normalized = min(speed / maxSpeed, 1.0)
        let targetVolume = Float(normalized * 1.2)  // Boosted from 0.5 to 1.2 so it's actually audible

        // Frequency scaling
        let minFreq = 100.0
        let maxFreq = 600.0
        let targetFreq = minFreq + (maxFreq - minFreq) * normalized

        if !isPlaying {
            playerNode.play()
            isPlaying = true
        }

        playerNode.volume = targetVolume
        equalizer.bands[0].frequency = Float(targetFreq)
    }
}
