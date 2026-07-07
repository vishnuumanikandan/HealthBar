//
//  UserProgressDTO.swift
//  HealthBar
//
//  Created by Claude on 3/25/26.
//

import Foundation

/// Data Transfer Object for UserProgress cloud sync via Firestore.
///
/// Plain Codable struct with zero SwiftData dependencies.
/// Mirrors every persisted field of the UserProgress @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/userProgress/progress), not the body
///   - `rank` — NEVER synced; it is a computed function of `rr` (Rank.getRank(from: rr))
///
/// The `id` field is UUID.uuidString from UserProgress.id.
/// The Firestore document ID is always the fixed string "progress" (single document per user).
///
/// `claimedMilestones` is stored as a comma-separated String on the SwiftData model but
/// serialized as an Int array in Firestore for clean querying.
struct UserProgressDTO: Codable {

    // MARK: - Fields (mirrors UserProgress, minus userId and rank)

    var id: String
    var totalXP: Int
    /// Ranked Rating — synced and server-authoritative. Optional so legacy `progress`
    /// docs written before RR-0a (no `rr` key) still decode; always read via `resolvedRR`.
    var rr: Int?
    var currentStreak: Int
    var longestStreak: Int
    var lastActiveDate: Date
    /// Serialized from UserProgress.claimedMilestones (comma-string) as a sorted Int array.
    var claimedMilestonesArray: [Int]

    // MARK: - Duel record (D1b) — optional for legacy-doc decode; read via resolved accessors.
    var duelWins: Int?
    var duelLosses: Int?
    var duelDraws: Int?
    var currentWinStreak: Int?
    var bestWinStreak: Int?

    // MARK: - Per-league duel record (D3) — optional for legacy-doc decode; resolved accessors default 0.
    var duelWins1: Int?
    var duelWins3: Int?
    var duelWins5: Int?
    var winStreak1: Int?
    var winStreak3: Int?
    var winStreak5: Int?

    /// Legacy-safe RR accessor — the single place the nil→starting fallback lives.
    /// Missing/absent `rr` (older Firestore docs) resolves to `Rank.startingRR`, never 0.
    var resolvedRR: Int { rr ?? Rank.startingRR }
    var resolvedDuelWins: Int { duelWins ?? 0 }
    var resolvedDuelLosses: Int { duelLosses ?? 0 }
    var resolvedDuelDraws: Int { duelDraws ?? 0 }
    var resolvedCurrentWinStreak: Int { currentWinStreak ?? 0 }
    var resolvedBestWinStreak: Int { bestWinStreak ?? 0 }
    var resolvedDuelWins1: Int { duelWins1 ?? 0 }
    var resolvedDuelWins3: Int { duelWins3 ?? 0 }
    var resolvedDuelWins5: Int { duelWins5 ?? 0 }
    var resolvedWinStreak1: Int { winStreak1 ?? 0 }
    var resolvedWinStreak3: Int { winStreak3 ?? 0 }
    var resolvedWinStreak5: Int { winStreak5 ?? 0 }

    // NOTE: `rank` is intentionally excluded — it is a computed function of `rr`
    // (`Rank.getRank(from: rr)`) and must never be written or read from Firestore.

    // MARK: - Conversion: UserProgress → UserProgressDTO

    init(from progress: UserProgress) {
        self.id = progress.id.uuidString
        self.totalXP = progress.totalXP
        self.rr = progress.rr
        self.duelWins = progress.duelWins
        self.duelLosses = progress.duelLosses
        self.duelDraws = progress.duelDraws
        self.currentWinStreak = progress.currentWinStreak
        self.bestWinStreak = progress.bestWinStreak
        self.duelWins1 = progress.duelWins1
        self.duelWins3 = progress.duelWins3
        self.duelWins5 = progress.duelWins5
        self.winStreak1 = progress.winStreak1
        self.winStreak3 = progress.winStreak3
        self.winStreak5 = progress.winStreak5
        self.currentStreak = progress.currentStreak
        self.longestStreak = progress.longestStreak
        self.lastActiveDate = progress.lastActiveDate
        self.claimedMilestonesArray = Array(progress.claimedMilestoneSet).sorted()
    }

    // MARK: - Conversion: UserProgressDTO → UserProgress

    /// Creates a UserProgress SwiftData model from this DTO.
    /// - Parameter userId: The authenticated user's ID (stamped onto the new record).
    /// - Note: `rr` is seeded from the DTO (legacy nil → `Rank.startingRR`); `rank` is
    ///   not set here — it is computed from `rr`.
    /// - Note: `claimedMilestones` is reconstructed as a comma-separated String from the array.
    func toUserProgress(userId: String) -> UserProgress {
        let progress = UserProgress(
            id: UUID(uuidString: id) ?? UUID(),
            totalXP: totalXP,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            lastActiveDate: lastActiveDate,
            rr: resolvedRR  // legacy nil → Rank.startingRR
        )
        progress.userId = userId
        progress.claimedMilestones = claimedMilestonesArray.sorted().map { String($0) }.joined(separator: ",")
        progress.duelWins = resolvedDuelWins
        progress.duelLosses = resolvedDuelLosses
        progress.duelDraws = resolvedDuelDraws
        progress.currentWinStreak = resolvedCurrentWinStreak
        progress.bestWinStreak = resolvedBestWinStreak
        progress.duelWins1 = resolvedDuelWins1
        progress.duelWins3 = resolvedDuelWins3
        progress.duelWins5 = resolvedDuelWins5
        progress.winStreak1 = resolvedWinStreak1
        progress.winStreak3 = resolvedWinStreak3
        progress.winStreak5 = resolvedWinStreak5
        return progress
    }

    // MARK: - Diff Helper

    /// Returns true if any synced field in this DTO differs from the given UserProgress.
    ///
    /// `rank` is not compared — it is computed from `rr`, not part of the DTO.
    /// `claimedMilestonesArray` is compared as a Set for order-independence.
    func differsFrom(_ progress: UserProgress) -> Bool {
        guard UUID(uuidString: id) == progress.id else { return true }
        return totalXP != progress.totalXP
            || resolvedRR != progress.rr
            || resolvedDuelWins != progress.duelWins
            || resolvedDuelLosses != progress.duelLosses
            || resolvedDuelDraws != progress.duelDraws
            || resolvedCurrentWinStreak != progress.currentWinStreak
            || resolvedBestWinStreak != progress.bestWinStreak
            || resolvedDuelWins1 != progress.duelWins1
            || resolvedDuelWins3 != progress.duelWins3
            || resolvedDuelWins5 != progress.duelWins5
            || resolvedWinStreak1 != progress.winStreak1
            || resolvedWinStreak3 != progress.winStreak3
            || resolvedWinStreak5 != progress.winStreak5
            || currentStreak != progress.currentStreak
            || longestStreak != progress.longestStreak
            || lastActiveDate != progress.lastActiveDate
            || Set(claimedMilestonesArray) != progress.claimedMilestoneSet
    }
}
