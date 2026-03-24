//
//  MoodEntry.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import Foundation
import SwiftData

/// Stores a daily mood check entry
///
/// One entry per day - the user logs how they're feeling.
/// Used for long-term mood tracking and potential insights.
@Model
final class MoodEntry {
    /// Unique identifier
    var id: UUID

    /// The date this mood was logged for (normalized to start of day)
    var date: Date

    /// The mood value stored as a string (for SwiftData compatibility)
    var moodRawValue: String

    /// Scopes this record to an authenticated user.
    /// Defaults to "legacy" so pre-migration records remain valid without crashing.
    /// Legacy records are invisible to all real authenticated users — this is intentional.
    ///
    /// TODO: Replace currentUserEmail with a stable Firebase UID once Firebase is
    /// integrated in Phase 3. Never persist this as a permanent identifier — always
    /// read it live from AuthService at query time.
    var userId: String = "legacy"

    /// When this entry was created
    var createdAt: Date

    /// Computed property for type-safe mood access
    var mood: Mood {
        get { Mood(rawValue: moodRawValue) ?? .okay }
        set { moodRawValue = newValue.rawValue }
    }

    /// Initializes a new mood entry
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - date: The date this mood is for (defaults to today)
    ///   - mood: The user's mood
    ///   - createdAt: When this was logged (defaults to now)
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        mood: Mood,
        createdAt: Date = Date()
    ) {
        self.id = id
        // Normalize to start of day for consistent querying
        self.date = Calendar.current.startOfDay(for: date)
        self.moodRawValue = mood.rawValue
        self.createdAt = createdAt
    }
}
