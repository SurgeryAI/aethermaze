//
//  GameCoordinator.swift
//  aethermaze
//
//  Created by Marc L. Melcher on 12/16/25.
//

import Combine
import SwiftUI

enum GameState {
    case playing
    case levelComplete
    case gameOver
}

class GameCoordinator: ObservableObject {
    @Published var gameState: GameState = .playing
    @Published var currentLevel: Int = 1
    @Published var score: Int = 0
    @Published var marblesUsed: Int = 1
    @Published var timeRemaining: TimeInterval = 60
    @Published var maxMarbles: Int = 5
    private var levelStartTime: TimeInterval = 0
    private var timer: AnyCancellable?
    @Published var hasFallenThisLevel: Bool = false
    private var isRespawning = false

    init() {
        resetTimerForLevel()
        startTimer()
    }

    func restartLevel() {
        // [FIX] Guard against double-death or post-gameover collisions
        guard gameState == .playing, !isRespawning else { return }
        isRespawning = true
        hasFallenThisLevel = true

        // Logic: You USED a marble.
        if marblesUsed >= maxMarbles {
            gameOver()
            isRespawning = false
            return
        }

        marblesUsed += 1

        // [TIME-HEIST] Penalty for falling is now TIME
        timeRemaining = max(0, timeRemaining - 10)

        if timeRemaining <= 0 {
            gameOver()
            isRespawning = false
            return
        }

        gameState = .playing
        // startTimer() // Timer continues from current remaining

        // Reset debounce after a short delay to allow physics to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isRespawning = false
        }
    }

    func nextLevel() {
        guard gameState == .playing else { return }

        // Scoring Formula
        // [MODIFIED] timeRemaining is now the resource
        let timeBonus = Int(timeRemaining) * 20
        var levelScore = 1000 + timeBonus

        // [NEW] Perfect Level Bonus
        if !hasFallenThisLevel {
            levelScore += 500
        }

        score += levelScore

        // [NEW] Bonus Marble Logic
        if currentLevel % 2 == 0 {
            maxMarbles += 1
        }

        currentLevel += 1
        hasFallenThisLevel = false
        gameState = .levelComplete
        stopTimer()

        // Delay slightly
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.gameState = .playing
            self.resetTimerForLevel()
            self.startTimer()
        }
    }

    func addTime(_ seconds: TimeInterval) {
        timeRemaining += seconds
        // Add a small score bonus for collecting a shard too?
        score += 100
    }

    func resetTimerForLevel() {
        // Base time + bonus for level complexity
        let baseTime: TimeInterval = 45
        let levelBonus = TimeInterval(currentLevel * 10)
        timeRemaining = baseTime + levelBonus
    }

    func gameOver() {
        gameState = .gameOver
        stopTimer()
        saveHighScore(score: score)
    }

    func resetGame() {
        currentLevel = 1
        score = 0
        marblesUsed = 1
        maxMarbles = 5
        resetTimerForLevel()
        isRespawning = false
        gameState = .playing
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    self.gameOver()
                }
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Persistence
    private let highScoresKey = "AetherMazeHighScores"

    func saveHighScore(score: Int) {
        var scores = getHighScores()
        scores.append(score)
        scores.sort(by: >)
        if scores.count > 10 {
            scores = Array(scores.prefix(10))
        }
        UserDefaults.standard.set(scores, forKey: highScoresKey)
    }

    func getHighScores() -> [Int] {
        return UserDefaults.standard.array(forKey: highScoresKey) as? [Int] ?? []
    }
}
