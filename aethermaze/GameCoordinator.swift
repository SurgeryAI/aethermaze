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
    @Published var elapsedTime: TimeInterval = 0
    private var timer: AnyCancellable?

    init() {
        startTimer()
    }

    func restartLevel() {
        // In a real app, we might subtract score or lives here
        // For simplicity, we just toggle 'playing' to reset positions in the view
        gameState = .playing
        startTimer()
    }

    func nextLevel() {
        guard gameState == .playing else { return }

        currentLevel += 1
        gameState = .levelComplete
        stopTimer()

        // Delay slightly before starting next level gameplay or waiting for user input
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.gameState = .playing
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
