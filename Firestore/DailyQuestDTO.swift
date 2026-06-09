//
//  DailyQuestDTO.swift
//  HealthBar
//
//  Created by Claude on 3/25/26.
//

import Foundation

/// Data Transfer Object for DailyQuest cloud sync via Firestore.
///
/// Plain Codable struct with zero SwiftData dependencies.
/// Mirrors every persisted field of the DailyQuest @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/dailyQuests/{id}), not the body
///
/// The `id` field is UUID.uuidString from DailyQuest.id and is used as the Firestore document ID.
///
/// CRITICAL: `isCompleted` is append-only. A quest marked complete on any device must never
/// be reverted to incomplete by a sync from another device. The merge rule is: `true` wins.
///
/// Date field: `questDate` maps to DailyQuest.date. Stored as Firestore Timestamp.
/// Quests are scoped to the current day + previous 7 days to prevent unbounded collection growth.
struct DailyQuestDTO: Codable {

    // MARK: - Fields (mirrors DailyQuest, minus userId)

    var id: String
    var title: String
    var questDescription: String
    var xpReward: Int
    /// Append-only: `true` always wins — never overwrite true with false during sync.
    var isCompleted: Bool
    /// Maps to DailyQuest.date — field name is `questDate` in Firestore.
    /// Used in range queries to enforce the 7-day sync window.
    var questDate: Date
    var questType: String

    // MARK: - Conversion: DailyQuest → DailyQuestDTO

    init(from quest: DailyQuest) {
        self.id = quest.id.uuidString
        self.title = quest.title
        self.questDescription = quest.questDescription
        self.xpReward = quest.xpReward
        self.isCompleted = quest.isCompleted
        self.questDate = quest.date
        self.questType = quest.questType
    }

    // MARK: - Conversion: DailyQuestDTO → DailyQuest

    /// Creates a DailyQuest SwiftData model from this DTO.
    /// - Parameter userId: The authenticated user's ID (stamped onto the new record).
    func toDailyQuest(userId: String) -> DailyQuest {
        let quest = DailyQuest(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            questDescription: questDescription,
            xpReward: xpReward,
            isCompleted: isCompleted,
            date: questDate,
            questType: questType
        )
        quest.userId = userId
        return quest
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given DailyQuest.
    ///
    /// Note: comparing raw `isCompleted` values, NOT the merge-rule result.
    /// The merge rule (true wins) is applied inside `applyDailyQuestUpdates`, not here.
    func differsFrom(_ quest: DailyQuest) -> Bool {
        guard UUID(uuidString: id) == quest.id else { return true }
        return title != quest.title
            || questDescription != quest.questDescription
            || xpReward != quest.xpReward
            || isCompleted != quest.isCompleted
            || questDate != quest.date
            || questType != quest.questType
    }
}
