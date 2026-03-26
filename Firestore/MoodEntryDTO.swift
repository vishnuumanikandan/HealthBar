//
//  MoodEntryDTO.swift
//  HealthBar
//
//  Created by Claude on 3/25/26.
//

import Foundation

/// Data Transfer Object for MoodEntry cloud sync via Firestore.
///
/// Plain Codable struct with zero SwiftData dependencies.
/// Mirrors every persisted field of the MoodEntry @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/moodEntries/{id}), not the document body
///
/// The `id` field is UUID.uuidString from MoodEntry.id and is used as the Firestore document ID.
/// `moodRawValue` stores the Mood enum's rawValue string — no enum dependency on the DTO.
struct MoodEntryDTO: Codable {

    // MARK: - Fields (mirrors MoodEntry, minus userId)

    var id: String
    var date: Date      // Stored as Firestore Timestamp; normalized to start of day on insert
    var moodRawValue: String
    var createdAt: Date

    // MARK: - Conversion: MoodEntry → MoodEntryDTO

    init(from entry: MoodEntry) {
        self.id = entry.id.uuidString
        self.date = entry.date
        self.moodRawValue = entry.moodRawValue
        self.createdAt = entry.createdAt
    }

    // MARK: - Conversion: MoodEntryDTO → MoodEntry

    /// Creates a MoodEntry SwiftData model from this DTO.
    /// - Parameter userId: The authenticated user's ID (stamped onto the new entry).
    /// - Note: `date` is expected to already be normalized to start of day (MoodEntry.init normalizes on creation).
    func toMoodEntry(userId: String) -> MoodEntry {
        let entry = MoodEntry(
            id: UUID(uuidString: id) ?? UUID(),
            date: date,
            mood: Mood(rawValue: moodRawValue) ?? .okay,
            createdAt: createdAt
        )
        entry.userId = userId
        return entry
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given MoodEntry.
    /// Used by `applyMoodEntryUpdates` to avoid unnecessary SwiftData rewrites.
    func differsFrom(_ entry: MoodEntry) -> Bool {
        guard UUID(uuidString: id) == entry.id else { return true }
        return date != entry.date
            || moodRawValue != entry.moodRawValue
            || createdAt != entry.createdAt
    }
}
