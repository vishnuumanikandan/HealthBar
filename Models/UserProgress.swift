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

    /// Ranked Rating — the sole basis for rank. Server-authoritative (synced via
    /// UserProgressDTO) and NON-monotonic (duel losses lower it). Starts at Copper 2.
    ///
    /// The inline literal default is required for SwiftData lightweight migration of
    /// existing records; it equals `Rank.startingRR`.
    var rr: Int = 450

    /// Current rank tier as a string (e.g., "copper"). Computed from `rr` — never
    /// stored, never derived from XP. Parallels `currentLevel` (computed from XP).
    var rank: String { Rank.getRank(from: rr).rawValue }

    /// Rank plus the tier (1…3) within it, e.g. "Copper 2". For RR-0b display.
    var rankTier: RankTier { Rank.rankTier(from: rr) }

    /// Scopes this record to an authenticated user.
    /// Defaults to "legacy" so pre-migration records remain valid without crashing.
    /// Legacy records are invisible to all real authenticated users — this is intentional.
    ///
    /// TODO: Replace currentUserEmail with a stable Firebase UID once Firebase is
    /// integrated in Phase 3. Never persist this as a permanent identifier — always
    /// read it live from AuthService at query time.
    var userId: String = "legacy"

    /// Comma-separated list of claimed streak milestone raw values
    /// Uses inline default for SwiftData lightweight migration support
    var claimedMilestones: String = ""

    /// Computed property: Current level based on totalXP
    /// Each level requires 100 XP (Level 1 = 0-99 XP, Level 2 = 100-199 XP, etc.)
    var currentLevel: Int {
        return totalXP / 100 + 1
    }

    /// Returns set of claimed milestone raw values
    var claimedMilestoneSet: Set<Int> {
        guard !claimedMilestones.isEmpty else { return [] }
        return Set(claimedMilestones.split(separator: ",").compactMap { Int($0) })
    }

    /// Checks if a specific milestone has been claimed
    /// - Parameter milestone: The milestone to check
    /// - Returns: True if already claimed
    func hasClaimed(_ milestone: StreakMilestone) -> Bool {
        claimedMilestoneSet.contains(milestone.rawValue)
    }

    /// Claims a milestone (adds to claimed list)
    /// - Parameter milestone: The milestone to claim
    func claim(_ milestone: StreakMilestone) {
        guard !hasClaimed(milestone) else { return }
        if claimedMilestones.isEmpty {
            claimedMilestones = "\(milestone.rawValue)"
        } else {
            claimedMilestones += ",\(milestone.rawValue)"
        }
    }

    /// Initializes user progress with starting values
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - totalXP: Starting XP (defaults to 0)
    ///   - currentStreak: Starting streak (defaults to 0)
    ///   - longestStreak: Record streak (defaults to 0)
    ///   - lastActiveDate: Last activity date (defaults to now)
    ///   - rr: Starting Ranked Rating (defaults to Copper 2 via Rank.startingRR)
    init(
        id: UUID = UUID(),
        totalXP: Int = 0,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lastActiveDate: Date = Date(),
        rr: Int = Rank.startingRR
    ) {
        self.id = id
        self.totalXP = totalXP
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastActiveDate = lastActiveDate
        self.rr = rr
    }
}
