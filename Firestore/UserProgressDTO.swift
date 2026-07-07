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

    /// Legacy-safe RR accessor — the single place the nil→starting fallback lives.
    /// Missing/absent `rr` (older Firestore docs) resolves to `Rank.startingRR`, never 0.
    var resolvedRR: Int { rr ?? Rank.startingRR }

    // NOTE: `rank` is intentionally excluded — it is a computed function of `rr`
    // (`Rank.getRank(from: rr)`) and must never be written or read from Firestore.

    // MARK: - Conversion: UserProgress → UserProgressDTO

    init(from progress: UserProgress) {
        self.id = progress.id.uuidString
        self.totalXP = progress.totalXP
        self.rr = progress.rr
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
            || currentStreak != progress.currentStreak
            || longestStreak != progress.longestStreak
            || lastActiveDate != progress.lastActiveDate
            || Set(claimedMilestonesArray) != progress.claimedMilestoneSet
    }
}
