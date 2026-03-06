//
//  UserProgress.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftData

/// Tracks user's lifetime progress, XP, streaks, and rank
///
/// This is a singleton model - only one instance should exist per user.
/// Handles all gamification progression data.
@Model
final class UserProgress {
    /// Unique identifier (singleton - only one instance per user)
    var id: UUID

    /// Total lifetime XP earned across all activities
    var totalXP: Int

    /// Current consecutive days meeting daily goals
    var currentStreak: Int

    /// Record streak for motivation and achievement tracking
    var longestStreak: Int

    /// Last date the user was active (for streak calculation)
    /// Used to determine if streak should continue or reset
    var lastActiveDate: Date

    /// Current rank tier as a string (e.g., "iron", "bronze")
    /// Computed from totalXP using Rank enum
    var rank: String

    /// Computed property: Current level based on totalXP
    /// Each level requires 100 XP (Level 1 = 0-99 XP, Level 2 = 100-199 XP, etc.)
    var currentLevel: Int {
        return totalXP / 100 + 1
    }

    /// Initializes user progress with starting values
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - totalXP: Starting XP (defaults to 0)
    ///   - currentStreak: Starting streak (defaults to 0)
    ///   - longestStreak: Record streak (defaults to 0)
    ///   - lastActiveDate: Last activity date (defaults to now)
    ///   - rank: Starting rank (defaults to "iron")
    init(
        id: UUID = UUID(),
        totalXP: Int = 0,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lastActiveDate: Date = Date(),
        rank: String = "iron"
    ) {
        self.id = id
        self.totalXP = totalXP
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastActiveDate = lastActiveDate
        self.rank = rank
    }
}
