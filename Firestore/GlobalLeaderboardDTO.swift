//
//  GlobalLeaderboardDTO.swift
//  HealthBar
//
//  Created by Claude on 7/6/26.
//

import FirebaseFirestore
import Foundation

/// Data Transfer Object for a top-level `leaderboard/{uid}` document (D3 — global ladder).
///
/// Owner-published, WORLD-readable projection (any authenticated user) — the deliberate
/// privacy posture of a global ladder. `public/stats` cannot serve it: its read rule is the
/// friend/guild privacy gate, so a collection-group query there would require world-readable
/// rules and destroy the gate. Hence a new queryable top-level directory keyed doc-id-as-uid
/// (precedent for top-level: `usernames/`, `duelQueue/`).
///
/// Contains ONLY ladder fields + identity snapshots; private data never lands here.
/// `username`/`displayName` are eventually-consistent snapshots (refreshed on the owner's next
/// publish) — display-only, never keys. Following the guild/duel convention for top-level docs,
/// `id` is the Firestore document ID (= uid; set from `documentID` on read, never encoded — the
/// service writes a manual dict of exactly the rule's field set). `updatedAt` is a server
/// timestamp (written as the sentinel, decoded via `@ServerTimestamp`).
struct GlobalLeaderboardDTO: Codable, Identifiable, Equatable {
    /// Firestore document ID (= owner uid). Set from `documentID` on read; never encoded.
    var id: String?

    // Display snapshots (display-only; all logic keys on the uid / doc id).
    var username: String
    var displayName: String

    /// Ranked Rating — the global board's sort key.
    var rr: Int

    // Per-league duel counters (D3). Field names are deliberately short — they are `orderBy`
    // targets and rule-validated keys.
    var wins1: Int
    var wins3: Int
    var wins5: Int
    var streak1: Int
    var streak3: Int
    var streak5: Int

    @ServerTimestamp var updatedAt: Date?

    // MARK: - Convenience (client-side)

    /// Wins for a league (1/3/5), else 0.
    func wins(league: Int) -> Int {
        switch league { case 1: return wins1; case 3: return wins3; case 5: return wins5; default: return 0 }
    }
    /// Current win streak for a league (1/3/5), else 0.
    func streak(league: Int) -> Int {
        switch league { case 1: return streak1; case 3: return streak3; case 5: return streak5; default: return 0 }
    }
}
