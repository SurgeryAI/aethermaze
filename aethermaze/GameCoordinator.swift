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
    @Published var elapsedTime: TimeInterval = 0
    @Published var maxMarbles: Int = 5
    private var levelStartTime: TimeInterval = 0
    private var timer: AnyCancellable?
    @Published var hasFallenThisLevel: Bool = false
    private var isRespawning = false

    init() {
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

        // Penalty for falling?
        if score > 0 {
            score = max(0, score - 50)
        }

        gameState = .playing
        elapsedTime = 0
        startTimer()

        // Reset debounce after a short delay to allow physics to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isRespawning = false
        }
    }

    func nextLevel() {
        guard gameState == .playing else { return }

        // Scoring Formula
        let timeBonus = max(0, 500 - (Int(elapsedTime) * 10))
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
            self.elapsedTime = 0
            self.startTimer()
        }
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
        elapsedTime = 0
        isRespawning = false
        gameState = .playing
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        // Don't reset elapsedTime here if we want cumulative, but for level-based scoring we might.
        // Actually, let's keep it simple: restartLevel resets level timer. nextLevel resets level timer.
        // If we want total game time, we need a separate var.
        // For now, let's stick to existing logic.
        timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                self?.elapsedTime += 1
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
