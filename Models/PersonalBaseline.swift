//
//  PersonalBaseline.swift
//  HealthBar
//
//  Created by Claude on 2/2/26.
//

import Foundation
import SwiftData

/// Stores rolling 4-week average for a specific day of the week
///
/// Used to compare today's nutrition against the user's typical values
/// for the same day of week (e.g., "Your purity is 15% better than your usual Monday").
@Model
final class PersonalBaseline {
    /// Unique identifier
    var id: UUID

    /// Day of week (1 = Sunday, 7 = Saturday, per Calendar convention)
    var dayOfWeek: Int

    /// Rolling average calories for this day of week
    var averageCalories: Double

    /// Rolling average purity (toxin score) for this day of week
    var averagePurity: Double

    /// Number of weeks included in the rolling average (max 4)
    var sampleCount: Int

    /// Scopes this record to an authenticated user.
    /// Defaults to "legacy" so pre-migration records remain valid without crashing.
    /// Legacy records are invisible to all real authenticated users — this is intentional.
    ///
    /// TODO: Replace currentUserEmail with a stable Firebase UID once Firebase is
    /// integrated in Phase 3. Never persist this as a permanent identifier — always
    /// read it live from AuthService at query time.
    var userId: String = "legacy"

    /// Last time this baseline was updated
    var lastUpdated: Date

    /// Initializes a personal baseline for a day of week
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - dayOfWeek: Day of week (1-7)
    ///   - averageCalories: Starting average (defaults to 0)
    ///   - averagePurity: Starting average (defaults to 0)
    ///   - sampleCount: Number of samples (defaults to 0)
    ///   - lastUpdated: Last update time (defaults to now)
    init(
        id: UUID = UUID(),
        dayOfWeek: Int,
        averageCalories: Double = 0,
        averagePurity: Double = 0,
        sampleCount: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.averageCalories = averageCalories
        self.averagePurity = averagePurity
        self.sampleCount = sampleCount
        self.lastUpdated = lastUpdated
    }

    /// Updates the rolling average with new data
    /// - Parameters:
    ///   - newCalories: New calorie total to include
    ///   - newPurity: New purity score to include
    ///   - maxSamples: Maximum samples to keep in rolling average (default 4)
    func updateWithNewData(calories: Double, purity: Double, maxSamples: Int = 4) {
        if sampleCount < maxSamples {
            // Still building up samples - simple average
            let newCount = Double(sampleCount + 1)
            averageCalories = ((averageCalories * Double(sampleCount)) + calories) / newCount
            averagePurity = ((averagePurity * Double(sampleCount)) + purity) / newCount
            sampleCount += 1
        } else {
            // At max samples - rolling average (weighted toward newer data)
            // Uses exponential moving average approximation
            let weight = 1.0 / Double(maxSamples)
            averageCalories = (averageCalories * (1 - weight)) + (calories * weight)
            averagePurity = (averagePurity * (1 - weight)) + (purity * weight)
        }

        lastUpdated = Date()
    }

    /// Returns the display name for this day of week
    var dayName: String {
        let weekdays = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard dayOfWeek >= 1 && dayOfWeek <= 7 else { return "Unknown" }
        return weekdays[dayOfWeek]
    }

    /// Returns a shortened display name (e.g., "Mon")
    var shortDayName: String {
        let weekdays = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard dayOfWeek >= 1 && dayOfWeek <= 7 else { return "?" }
        return weekdays[dayOfWeek]
    }
}
