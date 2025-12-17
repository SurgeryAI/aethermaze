import AVFoundation
import Combine
import SwiftUI

class SoundManager: ObservableObject {

    static let shared = SoundManager()

    private var engine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var equalizer: AVAudioUnitEQ!
    private var isPlaying = false

    init() {
        setupAudioEngine()
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
        // Generate 1 second of random noise
        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let channelCount = Int(format.channelCount)
        for channel in 0..<channelCount {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frameCount) {
                // Simple white noise: random -1.0 to 1.0
                data[i] = Float.random(in: -1.0...1.0) * 0.5  // Reduce volume
            }
        }
        return buffer
    }

    func startEngine() {
        if !engine.isRunning {
            try? engine.start()
            playerNode.volume = 0  // Start silent
            playerNode.play()
            isPlaying = true
        }
    }

    func updateRollingSound(velocity: Float) {
        // Adjust based on speed
        // Speed 0 -> Silent
        // Speed Max (~5.0?) -> Loud, Higher Pitch/Freq

        let speed = Double(velocity)
        let maxSpeed = 3.0  // Reference max speed

        let threshold: Float = 0.03
        if speed < 0.1 {
            playerNode.volume = 0
            return
        }

        // Volume: 0 to 1

        if velocity > threshold {
            let normalized = min(speed / maxSpeed, 1.0)
            // Volume uses quadratic curve for smoother fade-in
            let targetVolume = pow(normalized, 2)

            // Frequency: 80Hz to 800Hz capped range
            let minFreq = 80.0
            let maxFreq = 800.0
            let targetFreq = minFreq + (maxFreq - minFreq) * normalized

            playerNode.volume = Float(targetVolume)
            equalizer.bands[0].frequency = Float(targetFreq)

            if !isPlaying {
                playerNode.play()
                isPlaying = true
            }
        } else {
            playerNode.volume = 0.0
            if isPlaying {
                playerNode.pause()
                isPlaying = false
            }
        }
    }
}
