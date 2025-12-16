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

    func restartLevel() {
        // In a real app, we might subtract score or lives here
        // For simplicity, we just toggle 'playing' to reset positions in the view
        gameState = .playing
    }

    func nextLevel() {
        currentLevel += 1
        gameState = .levelComplete

        // Delay slightly before starting next level gameplay or waiting for user input
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.gameState = .playing
        }
    }

    func gameOver() {
        gameState = .gameOver
        // Logic to restart from level 1 or retry
    }

    func resetGame() {
        currentLevel = 1
        score = 0
        gameState = .playing
    }
}
