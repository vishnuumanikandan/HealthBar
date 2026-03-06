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

    /// Calculates total toxin score from a list of food entries
    /// - Parameter entries: Array of FoodEntry objects
    /// - Returns: Total toxin score (sum of all entries)
    func calculateTotalToxinScore(from entries: [FoodEntry]) -> Int {
        return entries.reduce(0) { $0 + $1.toxinScore }
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
    /// - Toxin score <= purityTarget
    func didMeetGoals(entries: [FoodEntry], goal: DailyGoal) -> Bool {
        let totalCalories = calculateTotalCalories(from: entries)
        let macros = calculateTotalMacros(from: entries)
        let toxinScore = calculateTotalToxinScore(from: entries)

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
    /// - Returns: True if toxin score is at or below target
    func didMeetPurityGoal(entries: [FoodEntry], goal: DailyGoal) -> Bool {
        let toxinScore = calculateTotalToxinScore(from: entries)
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
