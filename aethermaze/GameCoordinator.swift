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
    private var levelStartTime: TimeInterval = 0
    private var timer: AnyCancellable?

    init() {
        startTimer()
    }

    func restartLevel() {
        marblesUsed += 1
        // Penalty for falling? Maybe just the marble count is the penalty.
        // Let's deduct a small amount from score if positive, to discourage spamming.
        if score > 0 {
            score = max(0, score - 50)
        }

        gameState = .playing
        // Reset level timer for the new attempt?
        // Or keep running? Plan said "Level Time tracking", so reset makes sense for "this run".
        // But for "Total Time" it should probably keep going.
        // Let's reset elapsed time for the level to give them a fair shot at the time bonus.
        elapsedTime = 0
        startTimer()
    }

    func nextLevel() {
        guard gameState == .playing else { return }

        // Scoring Formula:
        // Base: 1000
        // Time Bonus: max(0, 500 - (seconds * 10)) -> Lose bonus after 50 seconds
        let timeBonus = max(0, 500 - (Int(elapsedTime) * 10))
        let levelScore = 1000 + timeBonus

        score += levelScore

        currentLevel += 1
        gameState = .levelComplete
        stopTimer()

        // Delay slightly before starting next level gameplay or waiting for user input
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.gameState = .playing
            // New level usually implies new marble (if we were tracking inventory),
            // but here "used" is total stats.
            // We just start the timer.
            self.elapsedTime = 0
            self.startTimer()
        }
    }

    func gameOver() {
        gameState = .gameOver
        stopTimer()
        // Logic to restart from level 1 or retry
    }

    func resetGame() {
        currentLevel = 1
        score = 0
        marblesUsed = 1
        elapsedTime = 0
        gameState = .playing
        startTimer()
    }

    private func startTimer() {
        stopTimer()
        elapsedTime = 0
        timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                self?.elapsedTime += 1
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}
