//
//  DailyQuest.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftData

/// Represents a daily challenge or objective for the user
///
/// Quests reset daily and provide XP rewards for healthy behaviors.
/// Categorized by type (nutrition, logging, streak, etc.) for variety.
@Model
final class DailyQuest {
    /// Unique identifier for the quest
    var id: UUID

    /// Display title of the quest (e.g., "Eat 3 fiber-rich foods")
    var title: String

    /// Detailed description explaining the quest objective
    var questDescription: String

    /// XP awarded when the quest is completed
    var xpReward: Int

    /// Tracks whether the quest has been completed today
    var isCompleted: Bool

    /// Date this quest is active for (quests reset daily)
    var date: Date

    /// Scopes this record to an authenticated user.
    /// Defaults to "legacy" so pre-migration records remain valid without crashing.
    /// Legacy records are invisible to all real authenticated users — this is intentional.
    ///
    /// TODO: Replace currentUserEmail with a stable Firebase UID once Firebase is
    /// integrated in Phase 3. Never persist this as a permanent identifier — always
    /// read it live from AuthService at query time.
    var userId: String = "legacy"

    /// Category of quest for variety and tracking
    /// Examples: "nutrition", "logging", "streak", "purity", "balance"
    var questType: String

    /// Initializes a new daily quest
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - title: Quest display title
    ///   - description: Detailed quest description
    ///   - xpReward: XP awarded on completion
    ///   - isCompleted: Completion status (defaults to false)
    ///   - date: Date the quest is active (defaults to today)
    ///   - questType: Category of quest (e.g., "nutrition")
    init(
        id: UUID = UUID(),
        title: String,
        questDescription: String,
        xpReward: Int,
        isCompleted: Bool = false,
        date: Date = Date(),
        questType: String
    ) {
        self.id = id
        self.title = title
        self.questDescription = questDescription
        self.xpReward = xpReward
        self.isCompleted = isCompleted
        self.date = date
        self.questType = questType
    }
}
