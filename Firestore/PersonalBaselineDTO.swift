//
//  PersonalBaselineDTO.swift
//  HealthBar
//
//  Created by Claude on 3/25/26.
//

import Foundation

/// Data Transfer Object for PersonalBaseline cloud sync via Firestore.
///
/// Plain Codable struct with zero SwiftData dependencies.
/// Mirrors every persisted field of the PersonalBaseline @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/personalBaselines/{id}), not the document body
///
/// The `id` field is UUID.uuidString from PersonalBaseline.id and is used as the Firestore document ID.
struct PersonalBaselineDTO: Codable {

    // MARK: - Fields (mirrors PersonalBaseline, minus userId)

    var id: String
    var dayOfWeek: Int
    var averageCalories: Double
    var averagePurity: Double
    var sampleCount: Int
    var lastUpdated: Date

    // MARK: - Conversion: PersonalBaseline → PersonalBaselineDTO

    init(from baseline: PersonalBaseline) {
        self.id = baseline.id.uuidString
        self.dayOfWeek = baseline.dayOfWeek
        self.averageCalories = baseline.averageCalories
        self.averagePurity = baseline.averagePurity
        self.sampleCount = baseline.sampleCount
        self.lastUpdated = baseline.lastUpdated
    }

    // MARK: - Conversion: PersonalBaselineDTO → PersonalBaseline

    /// Creates a PersonalBaseline SwiftData model from this DTO.
    /// - Parameter userId: The authenticated user's ID (stamped onto the new baseline).
    func toPersonalBaseline(userId: String) -> PersonalBaseline {
        let baseline = PersonalBaseline(
            id: UUID(uuidString: id) ?? UUID(),
            dayOfWeek: dayOfWeek,
            averageCalories: averageCalories,
            averagePurity: averagePurity,
            sampleCount: sampleCount,
            lastUpdated: lastUpdated
        )
        baseline.userId = userId
        return baseline
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given PersonalBaseline.
    /// Used by `applyPersonalBaselineUpdates` to avoid unnecessary SwiftData rewrites.
    func differsFrom(_ baseline: PersonalBaseline) -> Bool {
        guard UUID(uuidString: id) == baseline.id else { return true }
        return dayOfWeek != baseline.dayOfWeek
            || averageCalories != baseline.averageCalories
            || averagePurity != baseline.averagePurity
            || sampleCount != baseline.sampleCount
            || lastUpdated != baseline.lastUpdated
    }
}
