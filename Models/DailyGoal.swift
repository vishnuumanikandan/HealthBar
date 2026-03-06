//
//  DailyGoal.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftData

/// Represents daily nutrition targets for a specific date
///
/// Goals can change over time as user needs evolve. Each date can have its own targets.
/// Supports macro tracking (protein/carbs/fat) and purity goals (toxin limits).
@Model
final class DailyGoal {
    /// Unique identifier for this goal entry
    var id: UUID

    /// The date this goal applies to
    /// Allows historical tracking and future goal customization
    var date: Date

    /// Target daily calorie intake
    var calorieTarget: Int

    /// Target protein intake in grams
    var proteinTarget: Double

    /// Target carbohydrate intake in grams
    var carbTarget: Double

    /// Target fat intake in grams
    var fatTarget: Double

    /// Maximum allowed toxin score for the day (sum of all food toxin scores)
    /// Lower targets encourage cleaner eating
    var purityTarget: Int

    /// Initializes a new daily goal with nutritional targets
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - date: Date this goal applies to (defaults to today)
    ///   - calorieTarget: Daily calorie limit
    ///   - proteinTarget: Protein target in grams
    ///   - carbTarget: Carbohydrate target in grams
    ///   - fatTarget: Fat target in grams
    ///   - purityTarget: Maximum toxin score allowed per day
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        calorieTarget: Int,
        proteinTarget: Double,
        carbTarget: Double,
        fatTarget: Double,
        purityTarget: Int
    ) {
        self.id = id
        self.date = date
        self.calorieTarget = calorieTarget
        self.proteinTarget = proteinTarget
        self.carbTarget = carbTarget
        self.fatTarget = fatTarget
        self.purityTarget = purityTarget
    }
}
