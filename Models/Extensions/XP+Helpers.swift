//
//  XP+Helpers.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation

/// Global helper functions for XP and level calculations
///
/// These functions provide the game progression math for HealthBar's leveling system.
/// Level progression is linear: each level requires exactly 100 XP.

/// Calculates the total XP required to reach a specific level
/// - Parameter level: Target level (must be >= 1)
/// - Returns: Total XP needed to reach that level
///
/// Example: Level 1 = 0 XP, Level 2 = 100 XP, Level 10 = 900 XP
func xpForLevel(_ level: Int) -> Int {
    guard level >= 1 else { return 0 }
    return (level - 1) * 100
}

/// Calculates the current level based on total XP
/// - Parameter xp: Total XP earned
/// - Returns: Current level (minimum 1)
///
/// Example: 0-99 XP = Level 1, 100-199 XP = Level 2, etc.
func levelFromXP(_ xp: Int) -> Int {
    guard xp >= 0 else { return 1 }
    return (xp / 100) + 1
}

/// Calculates how much XP is needed to reach the next level
/// - Parameter currentXP: User's current total XP
/// - Returns: XP required to reach the next level
///
/// Example: At 150 XP (Level 2), need 50 more XP to reach Level 3 (200 XP total)
func xpForNextLevel(_ currentXP: Int) -> Int {
    let currentLevel = levelFromXP(currentXP)
    let nextLevelXP = xpForLevel(currentLevel + 1)
    return nextLevelXP - currentXP
}

/// Calculates the progress percentage toward the next level
/// - Parameter currentXP: User's current total XP
/// - Returns: Progress as a percentage (0.0 to 1.0)
///
/// Example: At 150 XP (Level 2, 50/100 progress to Level 3), returns 0.5
func levelProgress(_ currentXP: Int) -> Double {
    let currentLevel = levelFromXP(currentXP)
    let currentLevelMinXP = xpForLevel(currentLevel)
    let xpIntoCurrentLevel = currentXP - currentLevelMinXP
    return Double(xpIntoCurrentLevel) / 100.0
}
