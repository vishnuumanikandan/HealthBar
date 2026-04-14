//
//  BadgeProgress.swift
//  HealthBar
//
//  Created by Claude on 4/8/26.
//

import Foundation
import SwiftData

/// Tracks badge unlock state for a user.
///
/// One record per (userId, badgeId) pair. Append-only — `isUnlocked` never
/// reverts from true to false. Synced to Firestore at `users/{userId}/badges/{badgeId}`.
///
/// Uniqueness is enforced in DataManager: `upsertBadgeProgress` checks for an
/// existing record before inserting, and updates in-place if found.
@Model
final class BadgeProgress {

    // MARK: - Identity

    /// Firebase UID of the owning user. Defaults to "legacy" for lightweight migration.
    var userId: String = "legacy"

    /// The badge identifier matching `BadgeDefinition.id`.
    var badgeId: String = ""

    // MARK: - State

    /// Whether this badge has been earned. Never reverted once true.
    var isUnlocked: Bool = false

    /// When the badge was first unlocked. Nil if not yet earned.
    var unlockedAt: Date? = nil

    // MARK: - Init

    init(userId: String, badgeId: String, isUnlocked: Bool = false, unlockedAt: Date? = nil) {
        self.userId = userId
        self.badgeId = badgeId
        self.isUnlocked = isUnlocked
        self.unlockedAt = unlockedAt
    }
}
