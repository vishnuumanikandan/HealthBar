//
//  BadgeProgressDTO.swift
//  HealthBar
//
//  Created by Claude on 4/8/26.
//

import Foundation

/// Data Transfer Object for BadgeProgress cloud sync via Firestore.
///
/// Firestore path: users/{userId}/badges/{badgeId}
/// The document ID is the badgeId — one document per badge per user.
struct BadgeProgressDTO: Codable {
    var userId: String
    var badgeId: String
    var isUnlocked: Bool
    var unlockedAt: Date?

    init(userId: String, badgeId: String, isUnlocked: Bool, unlockedAt: Date?) {
        self.userId = userId
        self.badgeId = badgeId
        self.isUnlocked = isUnlocked
        self.unlockedAt = unlockedAt
    }

    init(from progress: BadgeProgress) {
        self.userId = progress.userId
        self.badgeId = progress.badgeId
        self.isUnlocked = progress.isUnlocked
        self.unlockedAt = progress.unlockedAt
    }
}
