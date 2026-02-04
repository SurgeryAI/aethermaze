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
    @Published var isNewHighScore: Bool = false
    @Published var leaderboardPosition: Int = 0

    // MARK: - New Engagement Features
    @Published var perfectStreak: Int = 0          // Consecutive perfect levels
    @Published var bestStreak: Int = 0             // Best streak achieved this game
    @Published var currentMultiplier: Double = 1.0  // Score multiplier based on streak
    @Published var lastLevelScore: Int = 0         // Display for level complete screen
    @Published var speedBonusEarned: Int = 0       // Speed bonus from last level
    @Published var shardsCollectedThisLevel: Int = 0  // Track shards per level
    @Published var totalShardsCollected: Int = 0   // Total shards in game
    @Published var lastShardBonus: Int = 0         // Last shard bonus earned (for UI display)
    @Published var lastShardTimeBonus: Int = 0      // Last shard time bonus earned (for UI display)
    @Published var shardCollectionTrigger: Int = 0  // Increments to trigger UI animation

    private let maxLevels: Int = 10
    private var levelStartTime: TimeInterval = 0
    private var levelInitialTime: TimeInterval = 0  // Track initial time for speed bonus
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

        // Breaking a streak when falling - but give a chance to rebuild
        if perfectStreak > 0 {
            perfectStreak = max(0, perfectStreak - 1)  // Lose one streak level, not all
            updateMultiplier()
        }

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

        // MARK: - Enhanced Scoring Algorithm
        // Base score scales with level difficulty
        let baseScore = 1000 + (currentLevel * 200)

        // Time bonus: Reward having time remaining (exponential for more remaining)
        let timeBonus = Int(timeRemaining * timeRemaining * 0.5)

        // Speed bonus: Complete level with > 50% time remaining for bonus
        let timeUsedPercent = 1.0 - (timeRemaining / levelInitialTime)
        var speedBonus = 0
        if timeUsedPercent < 0.3 {
            // Lightning fast! Under 30% time used
            speedBonus = 2000 + (currentLevel * 300)
        } else if timeUsedPercent < 0.5 {
            // Quick completion
            speedBonus = 1000 + (currentLevel * 150)
        } else if timeUsedPercent < 0.7 {
            // Decent pace
            speedBonus = 500
        }
        speedBonusEarned = speedBonus

        // Perfect Level Bonus (no falls)
        var perfectBonus = 0
        if !hasFallenThisLevel {
            perfectBonus = 1000 + (currentLevel * 100)
            // Increase streak
            perfectStreak += 1
            // Track best streak for game stats
            if perfectStreak > bestStreak {
                bestStreak = perfectStreak
            }
            updateMultiplier()
        } else {
            // Reset streak on imperfect level
            perfectStreak = 0
            updateMultiplier()
        }

        // Shard bonus: Extra reward for collecting shards (already added during collection)
        // This is tracked separately in shardsCollectedThisLevel

        // Calculate total level score with multiplier
        let rawLevelScore = baseScore + timeBonus + speedBonus + perfectBonus
        let multipliedScore = Int(Double(rawLevelScore) * currentMultiplier)
        lastLevelScore = multipliedScore

        score += multipliedScore

        // Bonus Marble Logic - Award on streak milestones too
        if currentLevel % 3 == 0 {
            maxMarbles += 1
        }
        // Bonus marble for hitting streak milestones
        if perfectStreak == 5 || perfectStreak == 7 {
            maxMarbles += 1
        }

        currentLevel += 1
        hasFallenThisLevel = false
        shardsCollectedThisLevel = 0

        // Check if game is won (completed all 10 levels)
        if currentLevel > maxLevels {
            // Final completion bonus
            let completionBonus = 5000 + (perfectStreak * 1000)
            score += completionBonus
            gameState = .gameOver
            stopTimer()
            checkForNewHighScore()
            return
        }

        gameState = .levelComplete
        stopTimer()

        // Delay slightly
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.gameState = .playing
            self.resetTimerForLevel()
            self.startTimer()
        }
    }

    private func updateMultiplier() {
        // Multiplier increases with perfect streak
        // 1x -> 1.25x -> 1.5x -> 2x -> 2.5x -> 3x (max at 5+ streak)
        switch perfectStreak {
        case 0: currentMultiplier = 1.0
        case 1: currentMultiplier = 1.25
        case 2: currentMultiplier = 1.5
        case 3: currentMultiplier = 2.0
        case 4: currentMultiplier = 2.5
        default: currentMultiplier = 3.0  // Max 3x multiplier
        }
    }

    func addTime(_ seconds: TimeInterval) {
        timeRemaining += seconds
        shardsCollectedThisLevel += 1
        totalShardsCollected += 1

        // Shard collection bonus: scales with multiplier and streak
        // Base 250, but increases with streak for that dopamine hit
        let shardBonus = Int(Double(250 + (perfectStreak * 50)) * currentMultiplier)
        score += shardBonus
        
        // Update UI trigger for point display animation
        lastShardBonus = shardBonus
        lastShardTimeBonus = Int(seconds)
        shardCollectionTrigger += 1
    }

    func resetTimerForLevel() {
        // Base time + bonus for level complexity
        let baseTime: TimeInterval = 45
        let levelBonus = TimeInterval(currentLevel * 10)
        timeRemaining = baseTime + levelBonus
        levelInitialTime = timeRemaining  // Store for speed bonus calculation
    }

    func gameOver() {
        gameState = .gameOver
        stopTimer()
        checkForNewHighScore()
    }

    func resetGame() {
        currentLevel = 1
        score = 0
        marblesUsed = 1
        maxMarbles = 5
        perfectStreak = 0
        bestStreak = 0
        currentMultiplier = 1.0
        lastLevelScore = 0
        speedBonusEarned = 0
        shardsCollectedThisLevel = 0
        totalShardsCollected = 0
        lastShardBonus = 0
        lastShardTimeBonus = 0
        shardCollectionTrigger = 0
        resetTimerForLevel()
        isRespawning = false
        hasFallenThisLevel = false
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

    private func checkForNewHighScore() {
        var scores = getHighScores()
        let oldTopScore = scores.first ?? 0

        scores.append(score)
        scores.sort(by: >)

        // Find position in leaderboard (1-indexed)
        if let position = scores.firstIndex(of: score) {
            leaderboardPosition = position + 1
        }

        // Check if new high score
        isNewHighScore = score > oldTopScore

        // Keep only top 10
        if scores.count > 10 {
            scores = Array(scores.prefix(10))
        }
        UserDefaults.standard.set(scores, forKey: highScoresKey)
    }

    func getHighScores() -> [Int] {
        return UserDefaults.standard.array(forKey: highScoresKey) as? [Int] ?? []
    }
}
