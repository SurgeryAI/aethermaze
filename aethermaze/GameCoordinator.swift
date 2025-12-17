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
    private var isRespawning = false

    init() {
        startTimer()
    }

    func restartLevel() {
        // [FIX] Guard against double-death or post-gameover collisions
        guard gameState == .playing, !isRespawning else { return }
        isRespawning = true

        // Logic: You USED a marble.
        // If you have used 5 and limit is 5, you are done.
        // Or is it "Lives Remaining"? The UI says "Marbles Used".
        // Let's say Limit is 5.
        // Start: Used 1. (Alive).
        // Die: Used 2.
        // ...
        // Die: Used 5. (Alive).
        // Die: Used 6 > 5 -> Game Over.

        if marblesUsed >= maxMarbles {
            gameOver()
            isRespawning = false  // Reset immediately since we aren't restarting level
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
        let levelScore = 1000 + timeBonus

        score += levelScore

        // [NEW] Bonus Marble Logic
        // Add +1 Max Marble every 2 levels completed?
        // Current Level 1 Complete -> Next is 2. (Count 1).
        // Current Level 2 Complete -> Next is 3. (Count 2). -> Bonus?
        // "Add an extra marble to the game every two levels"
        if currentLevel % 2 == 0 {
            maxMarbles += 1
        }

        currentLevel += 1
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
