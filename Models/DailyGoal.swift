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

    /// Maximum allowed toxin score for the day (0-100), compared against the day's
    /// calorie-weighted average toxin score — see NutritionManager.dailyToxinScore.
    /// Lower targets encourage cleaner eating
    var purityTarget: Int

    /// Scopes this record to an authenticated user.
    /// Defaults to "legacy" so pre-migration records remain valid without crashing.
    /// Legacy records are invisible to all real authenticated users — this is intentional.
    ///
    /// TODO: Replace currentUserEmail with a stable Firebase UID once Firebase is
    /// integrated in Phase 3. Never persist this as a permanent identifier — always
    /// read it live from AuthService at query time.
    var userId: String = "legacy"

    // MARK: - Advanced Nutrition Goals (Optional)
    // These targets are only shown when "Track Advanced Nutrition" is enabled
    // Uses inline defaults for SwiftData lightweight migration support

    /// Target fiber intake in grams (minimum - user should aim to reach or exceed)
    var fiberTarget: Double? = nil

    /// Maximum sugar intake in grams (user should stay under)
    var sugarTarget: Double? = nil

    /// Maximum sodium intake in milligrams (user should stay under)
    var sodiumTarget: Double? = nil

    /// Maximum saturated fat intake in grams (user should stay under)
    var saturatedFatTarget: Double? = nil

    /// Maximum cholesterol intake in milligrams (user should stay under)
    var cholesterolTarget: Double? = nil

    /// Target potassium intake in milligrams (minimum - user should aim to reach)
    var potassiumTarget: Double? = nil

    // MARK: - Water Goal (WATER-1)

    /// Daily water goal in CUPS (cups-canonical — see `WaterConstants`). Optional with an
    /// inline default, exactly like the advanced-nutrition fields above, so SwiftData
    /// lightweight migration accepts it.
    ///
    /// `nil` means "never set" and renders/edits as `WaterConstants.defaultGoalCups`.
    /// Syncs through `DailyGoalDTO` on the existing goal path — the count does NOT (it
    /// lives in the local-only `WaterDay`).
    var waterGoalCups: Int? = nil

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
        purityTarget: Int,
        // Advanced nutrition goals (optional)
        fiberTarget: Double? = nil,
        sugarTarget: Double? = nil,
        sodiumTarget: Double? = nil,
        saturatedFatTarget: Double? = nil,
        cholesterolTarget: Double? = nil,
        potassiumTarget: Double? = nil,
        // Water goal in cups (WATER-1)
        waterGoalCups: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.calorieTarget = calorieTarget
        self.proteinTarget = proteinTarget
        self.carbTarget = carbTarget
        self.fatTarget = fatTarget
        self.purityTarget = purityTarget
        // Advanced nutrition goals
        self.fiberTarget = fiberTarget
        self.sugarTarget = sugarTarget
        self.sodiumTarget = sodiumTarget
        self.saturatedFatTarget = saturatedFatTarget
        self.cholesterolTarget = cholesterolTarget
        self.potassiumTarget = potassiumTarget
        // Water goal
        self.waterGoalCups = waterGoalCups
    }
}
