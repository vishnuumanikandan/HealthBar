//
//  DailyGoalDTO.swift
//  HealthBar
//
//  Created by Claude on 3/25/26.
//

import Foundation

/// Data Transfer Object for DailyGoal cloud sync via Firestore.
///
/// Plain Codable struct with zero SwiftData dependencies.
/// Mirrors every persisted field of the DailyGoal @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/dailyGoals/{id}), not the document body
///
/// The `id` field is UUID.uuidString from DailyGoal.id and is used as the Firestore document ID.
struct DailyGoalDTO: Codable {

    // MARK: - Fields (mirrors DailyGoal, minus userId)

    var id: String
    var date: Date
    var calorieTarget: Int
    var proteinTarget: Double
    var carbTarget: Double
    var fatTarget: Double
    var purityTarget: Int

    // Advanced nutrition goals (optional)
    var fiberTarget: Double?
    var sugarTarget: Double?
    var sodiumTarget: Double?
    var saturatedFatTarget: Double?
    var cholesterolTarget: Double?
    var potassiumTarget: Double?

    // Water goal in cups (WATER-1). Optional, exactly like the siblings above.
    var waterGoalCups: Int?

    // MARK: - Conversion: DailyGoal → DailyGoalDTO

    init(from goal: DailyGoal) {
        self.id = goal.id.uuidString
        self.date = goal.date
        self.calorieTarget = goal.calorieTarget
        self.proteinTarget = goal.proteinTarget
        self.carbTarget = goal.carbTarget
        self.fatTarget = goal.fatTarget
        self.purityTarget = goal.purityTarget
        self.fiberTarget = goal.fiberTarget
        self.sugarTarget = goal.sugarTarget
        self.sodiumTarget = goal.sodiumTarget
        self.saturatedFatTarget = goal.saturatedFatTarget
        self.cholesterolTarget = goal.cholesterolTarget
        self.potassiumTarget = goal.potassiumTarget
        self.waterGoalCups = goal.waterGoalCups
    }

    // MARK: - Conversion: DailyGoalDTO → DailyGoal

    /// Creates a DailyGoal SwiftData model from this DTO.
    /// - Parameter userId: The authenticated user's ID (stamped onto the new goal).
    func toDailyGoal(userId: String) -> DailyGoal {
        let goal = DailyGoal(
            id: UUID(uuidString: id) ?? UUID(),
            date: date,
            calorieTarget: calorieTarget,
            proteinTarget: proteinTarget,
            carbTarget: carbTarget,
            fatTarget: fatTarget,
            purityTarget: purityTarget,
            fiberTarget: fiberTarget,
            sugarTarget: sugarTarget,
            sodiumTarget: sodiumTarget,
            saturatedFatTarget: saturatedFatTarget,
            cholesterolTarget: cholesterolTarget,
            potassiumTarget: potassiumTarget,
            waterGoalCups: waterGoalCups
        )
        goal.userId = userId
        return goal
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given DailyGoal.
    /// Used by `applyDailyGoalUpdates` to avoid unnecessary SwiftData rewrites.
    func differsFrom(_ goal: DailyGoal) -> Bool {
        guard UUID(uuidString: id) == goal.id else { return true }
        return date != goal.date
            || calorieTarget != goal.calorieTarget
            || proteinTarget != goal.proteinTarget
            || carbTarget != goal.carbTarget
            || fatTarget != goal.fatTarget
            || purityTarget != goal.purityTarget
            || fiberTarget != goal.fiberTarget
            || sugarTarget != goal.sugarTarget
            || sodiumTarget != goal.sodiumTarget
            || saturatedFatTarget != goal.saturatedFatTarget
            || cholesterolTarget != goal.cholesterolTarget
            || potassiumTarget != goal.potassiumTarget
            || waterGoalCups != goal.waterGoalCups
    }
}
