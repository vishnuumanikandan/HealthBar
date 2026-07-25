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

    // MARK: - Tutorial (TUT-1a)
    // First-session tutorial state. MONOTONIC: the completed-step set only grows;
    // the two bools only go false→true (union/OR merge in DataManager). The
    // comma-separated step-id String mirrors `claimedMilestones`'s encoding; inline
    // defaults = SwiftData lightweight migration (everyone does the tutorial — existing
    // accounts default to not-yet-seen/skipped with no completed steps).
    var tutorialSeen: Bool = false
    var tutorialSkipped: Bool = false
    var tutorialCompletedSteps: String = ""   // comma-separated step ids

    // MARK: - Duel record (D1b)
    // Server-authoritative and NON-monotonic (win streak resets; W/L/D accumulate).
    // Inline defaults = SwiftData lightweight migration. Published to leaderboard/{uid} in D3.
    var duelWins: Int = 0
    var duelLosses: Int = 0
    var duelDraws: Int = 0
    var currentWinStreak: Int = 0
    var bestWinStreak: Int = 0

    // MARK: - Per-league duel record (D3) — starts at 0 (no retroactive backfill).
    // Same server-authoritative, non-monotonic posture as the global duel record.
    var duelWins1: Int = 0
    var duelWins3: Int = 0
    var duelWins5: Int = 0
    var winStreak1: Int = 0
    var winStreak3: Int = 0
    var winStreak5: Int = 0

    // MARK: - Daily-goal XP (FIXES-1)
    // The last date the 50-XP "all three daily goals met" bonus was awarded. nil =
    // never awarded. MONOTONIC — merged latest-date-wins (Firestore or local, whichever
    // is later), exactly like the tutorial fields; never reconciled, never
    // Firestore-confirmed. A plain client `Date` (matching `lastActiveDate`'s
    // convention), never a server timestamp. Inline nil default = SwiftData lightweight
    // migration (existing records decode with no award yet).
    var lastDailyGoalXPDate: Date? = nil

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

    // MARK: - Tutorial helpers (TUT-1a) — mirror the milestone helpers above.

    /// Returns the set of completed tutorial step ids (empty String → empty set).
    var tutorialCompletedStepSet: Set<String> {
        guard !tutorialCompletedSteps.isEmpty else { return [] }
        return Set(tutorialCompletedSteps.split(separator: ",").map { String($0) })
    }

    /// Checks whether a specific tutorial step has been completed.
    func hasCompletedTutorialStep(_ id: String) -> Bool {
        tutorialCompletedStepSet.contains(id)
    }

    /// Completes a tutorial step (append-if-absent — mirrors `claim(_:)`).
    func completeTutorialStep(_ id: String) {
        guard !hasCompletedTutorialStep(id) else { return }
        if tutorialCompletedSteps.isEmpty {
            tutorialCompletedSteps = id
        } else {
            tutorialCompletedSteps += ",\(id)"
        }
    }

    /// Done := skipped OR all catalog steps completed (Decision 5). Delegates to the
    /// single `TutorialState.done` predicate — never restates it here.
    var tutorialDone: Bool {
        TutorialState(seen: tutorialSeen, skipped: tutorialSkipped, completed: tutorialCompletedStepSet).done
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
