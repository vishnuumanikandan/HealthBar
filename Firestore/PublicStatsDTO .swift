//
//  PublicStatsDTO.swift
//  HealthBar
//
//  Created by Claude on 6/10/26.
//

import FirebaseFirestore
import Foundation

/// Data Transfer Object for the friend-readable public stats projection.
///
/// Firestore path: users/{ownerUid}/public/stats (fixed document ID "stats")
///
/// Owner-computed, owner-published: each user computes these values from their
/// OWN local data (UserProgress + the 7-day adherence metric) and publishes
/// the result. Friends read only this projection — never the underlying
/// private food entries, goals, or account info. Reads are rule-gated on the
/// owner's friends list.
///
/// `username`/`displayName` are snapshots of the owner's identity at publish
/// time and are UI decoration only — ranking, dedup, and self-detection key
/// on the uid (the document's parent), never on these fields.
///
/// `updatedAt` uses @ServerTimestamp: encoded as FieldValue.serverTimestamp()
/// when nil at publish time, decoded as the server-resolved Date.
///
/// The Phase 4 profile fields (`longestStreak`, `joinedAt`, `badgeCount`,
/// `earnedBadgeIds`) are optional so projections published before Phase 4
/// still decode — readers default them to 0 / nil / []. `earnedBadgeIds`
/// carries badge IDs only; the viewer resolves emoji/title locally via
/// `BadgeDefinition.find(id:)` — another user's badges subcollection is
/// never read.
struct PublicStatsDTO: Codable {
    var username: String
    var displayName: String
    var level: Int
    var totalXP: Int
    var currentStreak: Int
    var rank: String
    var weeklyGoalsMet: Int
    var weeklyAdherence: Double
    var longestStreak: Int?
    var joinedAt: Date?
    var badgeCount: Int?
    var earnedBadgeIds: [String]?
    @ServerTimestamp var updatedAt: Date?
}
