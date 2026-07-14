//
//  NutritionManager.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation

/// Handles all nutrition-related calculations and business logic
///
/// Responsible for computing daily totals, checking goal completion,
/// and analyzing nutritional data. Does NOT interact with persistence directly.
@Observable
final class NutritionManager {

    // MARK: - Initialization

    init() {}

    // MARK: - Daily Calculations

    /// Calculates total calories from a list of food entries
    /// - Parameter entries: Array of FoodEntry objects
    /// - Returns: Total calories consumed
    func calculateTotalCalories(from entries: [FoodEntry]) -> Int {
        return entries.reduce(0) { $0 + $1.calories }
    }

    /// Calculates total macros from a list of food entries
    /// - Parameter entries: Array of FoodEntry objects
    /// - Returns: Tuple containing total protein, carbs, and fat in grams
    func calculateTotalMacros(from entries: [FoodEntry]) -> (protein: Double, carbs: Double, fat: Double) {
        let protein = entries.reduce(0.0) { $0 + $1.protein }
        let carbs = entries.reduce(0.0) { $0 + $1.carbs }
        let fat = entries.reduce(0.0) { $0 + $1.fat }

        return (protein: protein, carbs: carbs, fat: fat)
    }

    /// The day's toxin score: the calorie-weighted average of the entries' per-item
    /// toxin scores. Always 0–100, the same scale as a per-item score and as
    /// `DailyGoal.purityTarget` — lower is cleaner.
    ///
    ///     dailyToxinScore = round( Σ(toxinᵢ × caloriesᵢ) / Σ(caloriesᵢ) )
    ///
    /// This is the ONE place a day's `toxinScore` values are aggregated. It is static so
    /// callers (GamificationManager, AppCoordinator, DataManager) share it without holding
    /// a NutritionManager instance.
    ///
    /// Weighting by calories is what makes the number a diet-quality measure rather than a
    /// meal counter: a zero-calorie entry carries zero weight, so a diet soda cannot move a
    /// 2000-calorie day's score.
    ///
    /// Two fallbacks:
    /// - No entries → `0`.
    /// - Entries exist but `Σcalories == 0` (e.g. a day of black coffee) → the *unweighted*
    ///   mean of their toxin scores, so the day still scores rather than dividing by zero.
    ///
    /// - Parameter entries: A single day's FoodEntry objects
    /// - Returns: Weighted-average toxin score for the day (0–100)
    static func dailyToxinScore(from entries: [FoodEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }

        let totalCalories = entries.reduce(0) { $0 + $1.calories }

        guard totalCalories > 0 else {
            let sum = entries.reduce(0) { $0 + $1.toxinScore }
            return Int((Double(sum) / Double(entries.count)).rounded())
        }

        let weighted = entries.reduce(0.0) { $0 + Double($1.toxinScore) * Double($1.calories) }
        return Int((weighted / Double(totalCalories)).rounded())
    }

    // MARK: - Goal Checking

    /// Checks if all daily goals have been met
    /// - Parameters:
    ///   - entries: Today's food entries
    ///   - goal: Today's daily goal
    /// - Returns: True if all goals are met, false otherwise
    ///
    /// Goals met criteria:
    /// - Calories <= calorieTarget
    /// - Protein >= proteinTarget
    /// - Carbs within reasonable range (optional flexibility)
    /// - Fat within reasonable range (optional flexibility)
    /// - Weighted-average toxin score <= purityTarget
    func didMeetGoals(entries: [FoodEntry], goal: DailyGoal) -> Bool {
        let totalCalories = calculateTotalCalories(from: entries)
        let macros = calculateTotalMacros(from: entries)
        let toxinScore = NutritionManager.dailyToxinScore(from: entries)

        // Check each goal
        let metCalorieGoal = totalCalories <= goal.calorieTarget
        let metProteinGoal = macros.protein >= goal.proteinTarget
        let metPurityGoal = toxinScore <= goal.purityTarget

        // All core goals must be met
        return metCalorieGoal && metProteinGoal && metPurityGoal
    }

    /// Checks if calorie goal is met
    /// - Parameters:
    ///   - entries: Food entries to check
    ///   - goal: Daily goal
    /// - Returns: True if calories are at or under target
    func didMeetCalorieGoal(entries: [FoodEntry], goal: DailyGoal) -> Bool {
        let totalCalories = calculateTotalCalories(from: entries)
        return totalCalories <= goal.calorieTarget
    }

    /// Checks if protein goal is met
    /// - Parameters:
    ///   - entries: Food entries to check
    ///   - goal: Daily goal
    /// - Returns: True if protein meets or exceeds target
    func didMeetProteinGoal(entries: [FoodEntry], goal: DailyGoal) -> Bool {
        let macros = calculateTotalMacros(from: entries)
        return macros.protein >= goal.proteinTarget
    }

    /// Checks if purity goal is met
    /// - Parameters:
    ///   - entries: Food entries to check
    ///   - goal: Daily goal
    /// - Returns: True if the weighted-average toxin score is at or below target
    func didMeetPurityGoal(entries: [FoodEntry], goal: DailyGoal) -> Bool {
        let toxinScore = NutritionManager.dailyToxinScore(from: entries)
        return toxinScore <= goal.purityTarget
    }

    // MARK: - Progress Tracking

    /// Calculates progress percentage toward calorie goal
    /// - Parameters:
    ///   - entries: Food entries
    ///   - goal: Daily goal
    /// - Returns: Progress as percentage (0.0 to 1.0+)
    func calorieProgress(entries: [FoodEntry], goal: DailyGoal) -> Double {
        let totalCalories = calculateTotalCalories(from: entries)
        guard goal.calorieTarget > 0 else { return 0.0 }
        return Double(totalCalories) / Double(goal.calorieTarget)
    }

    /// Calculates progress percentage toward protein goal
    /// - Parameters:
    ///   - entries: Food entries
    ///   - goal: Daily goal
    /// - Returns: Progress as percentage (0.0 to 1.0+)
    func proteinProgress(entries: [FoodEntry], goal: DailyGoal) -> Double {
        let macros = calculateTotalMacros(from: entries)
        guard goal.proteinTarget > 0 else { return 0.0 }
        return macros.protein / goal.proteinTarget
    }

    /// Calculates remaining calories until goal is met
    /// - Parameters:
    ///   - entries: Food entries
    ///   - goal: Daily goal
    /// - Returns: Calories remaining (negative if over goal)
    func remainingCalories(entries: [FoodEntry], goal: DailyGoal) -> Int {
        let totalCalories = calculateTotalCalories(from: entries)
        return goal.calorieTarget - totalCalories
    }

    /// Calculates remaining protein until goal is met
    /// - Parameters:
    ///   - entries: Food entries
    ///   - goal: Daily goal
    /// - Returns: Protein remaining in grams (negative if over goal)
    func remainingProtein(entries: [FoodEntry], goal: DailyGoal) -> Double {
        let macros = calculateTotalMacros(from: entries)
        return goal.proteinTarget - macros.protein
    }

    // MARK: - Meal Analysis

    /// Counts the number of meals logged today
    /// - Parameter entries: Food entries
    /// - Returns: Count of food entries (simple meal count)
    func mealCount(from entries: [FoodEntry]) -> Int {
        return entries.count
    }

    /// Checks if any entries have photos
    /// - Parameter entries: Food entries
    /// - Returns: True if at least one entry has a photo
    func hasPhotos(entries: [FoodEntry]) -> Bool {
        return entries.contains { $0.photoData != nil }
    }

    /// Counts entries with photos
    /// - Parameter entries: Food entries
    /// - Returns: Number of entries with photos
    func photoCount(from entries: [FoodEntry]) -> Int {
        return entries.filter { $0.photoData != nil }.count
    }
}
