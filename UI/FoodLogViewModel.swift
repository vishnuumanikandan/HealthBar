//
//  FoodLogViewModel.swift
//  HealthBar
//
//  Created by Claude on 1/22/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Food Log feature
///
/// Manages today's food entries, daily goals, and progress calculations.
/// Uses @Observable macro (not @ObservableObject) for iOS 17+ compatibility.
@Observable
final class FoodLogViewModel {

    // MARK: - Properties

    /// Reference to the app coordinator for data operations
    private let coordinator: AppCoordinator

    // MARK: - Data State

    /// Today's food entries
    var todaysEntries: [FoodEntry] = []

    /// Today's daily goal
    var currentGoal: DailyGoal?

    /// Today's complete summary data
    var todaysSummary: TodaySummary?

    // MARK: - Computed Totals (Raw Data Only)

    /// Total calories consumed today
    var totalCalories: Int {
        todaysSummary?.totalCalories ?? 0
    }

    /// Total protein consumed today (in grams)
    var totalProtein: Double {
        todaysSummary?.totalProtein ?? 0.0
    }

    /// Total carbs consumed today (in grams)
    var totalCarbs: Double {
        todaysSummary?.totalCarbs ?? 0.0
    }

    /// Total fat consumed today (in grams)
    var totalFat: Double {
        todaysSummary?.totalFat ?? 0.0
    }

    /// Total toxin score for today
    var totalToxinScore: Int {
        todaysSummary?.totalToxinScore ?? 0
    }

    // MARK: - Progress Calculations

    /// Calculates calorie progress percentage
    var calorieProgress: Double {
        guard let goal = currentGoal, goal.calorieTarget > 0 else { return 0.0 }
        return Double(totalCalories) / Double(goal.calorieTarget)
    }

    /// Calculates protein progress percentage
    var proteinProgress: Double {
        guard let goal = currentGoal, goal.proteinTarget > 0 else { return 0.0 }
        return totalProtein / goal.proteinTarget
    }

    /// Calculates carbs progress percentage
    var carbProgress: Double {
        guard let goal = currentGoal, goal.carbTarget > 0 else { return 0.0 }
        return totalCarbs / goal.carbTarget
    }

    /// Calculates fat progress percentage
    var fatProgress: Double {
        guard let goal = currentGoal, goal.fatTarget > 0 else { return 0.0 }
        return totalFat / goal.fatTarget
    }

    /// Formatted calorie text for center of ring
    var calorieText: String {
        guard let goal = currentGoal else {
            return "\(totalCalories)"
        }
        return "\(totalCalories)\n/ \(goal.calorieTarget)"
    }

    // MARK: - UI State

    /// Loading state indicator
    var isLoading: Bool = false

    /// Controls visibility of add food sheet
    var showingAddFood: Bool = false

    /// Error message to display
    var errorMessage: String?

    /// Success message after adding food
    var showSuccessMessage: Bool = false
    var lastAddedFoodName: String = ""
    var lastEarnedXP: Int = 0

    /// Track which entry is being deleted (for loading state)
    var deletingEntryId: UUID?

    // MARK: - Form State (for AddFoodFormView)

    /// Form field: Food name
    var formFoodName: String = ""

    /// Form field: Calories
    var formCalories: String = ""

    /// Form field: Protein (in grams)
    var formProtein: String = ""

    /// Form field: Carbs (in grams)
    var formCarbs: String = ""

    /// Form field: Fat (in grams)
    var formFat: String = ""

    /// Form field: Toxin score (0-100)
    var formToxinScore: Double = 30.0

    /// Form submitting state
    var isSubmittingForm: Bool = false

    /// Form validation errors (real-time)
    var formValidationErrors: [String: String] = [:]

    // MARK: - Initialization

    /// Initializes the view model with an app coordinator
    /// - Parameter coordinator: The app coordinator for business logic
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Data Loading

    /// Loads today's data (entries, goals, summary)
    func loadTodaysData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch complete summary from coordinator
            let summary = try await coordinator.getTodaysSummary()

            // Update state
            todaysSummary = summary
            todaysEntries = summary.entries
            currentGoal = summary.goal

            isLoading = false
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Refreshes all data (for pull-to-refresh)
    func refreshData() async {
        await loadTodaysData()
    }

    // MARK: - Food Entry Operations

    /// Adds a new food entry
    /// - Parameters:
    ///   - name: Food name
    ///   - calories: Total calories
    ///   - protein: Protein in grams
    ///   - carbs: Carbs in grams
    ///   - fat: Fat in grams
    ///   - toxinScore: Toxin score (0-100, lower is better)
    func addFoodEntry(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int
    ) async {
        errorMessage = nil

        do {
            let result = try await coordinator.addFoodEntry(
                name: name,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                toxinScore: toxinScore
            )

            // Store success info
            lastAddedFoodName = name
            lastEarnedXP = result.xpEarned

            // Reload data to get updated summary
            await loadTodaysData()

            // Show success message
            showSuccessMessage = true

        } catch {
            errorMessage = "Failed to add food: \(error.localizedDescription)"
        }
    }

    /// Deletes a food entry
    /// - Parameter entry: The food entry to delete
    func deleteEntry(_ entry: FoodEntry) async {
        errorMessage = nil
        deletingEntryId = entry.id

        do {
            try await coordinator.deleteFoodEntry(entry)

            // Reload data to get updated summary
            await loadTodaysData()

        } catch {
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
        }

        deletingEntryId = nil
    }

    /// Returns true if the given entry is currently being deleted
    func isDeleting(_ entry: FoodEntry) -> Bool {
        deletingEntryId == entry.id
    }

    // MARK: - UI Helpers

    /// Dismisses the success message
    func dismissSuccessMessage() {
        showSuccessMessage = false
        lastAddedFoodName = ""
        lastEarnedXP = 0
    }

    /// Returns true if there are no entries logged today
    var hasNoEntries: Bool {
        todaysEntries.isEmpty
    }

    // MARK: - Form Management

    /// Resets all form fields to their default values
    func resetForm() {
        formFoodName = ""
        formCalories = ""
        formProtein = ""
        formCarbs = ""
        formFat = ""
        formToxinScore = 30.0
        formValidationErrors = [:]
        isSubmittingForm = false
    }

    /// Validates a specific form field in real-time
    /// - Parameter field: The field name to validate
    func validateField(_ field: String) {
        switch field {
        case "foodName":
            if formFoodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                formValidationErrors["foodName"] = "Food name is required"
            } else {
                formValidationErrors.removeValue(forKey: "foodName")
            }

        case "calories":
            if let caloriesInt = Int(formCalories), caloriesInt >= 0 {
                formValidationErrors.removeValue(forKey: "calories")
            } else if !formCalories.isEmpty {
                formValidationErrors["calories"] = "Enter a valid number"
            } else {
                formValidationErrors.removeValue(forKey: "calories")
            }

        case "protein":
            if let proteinDouble = Double(formProtein), proteinDouble >= 0 {
                formValidationErrors.removeValue(forKey: "protein")
            } else if !formProtein.isEmpty {
                formValidationErrors["protein"] = "Enter a valid number"
            } else {
                formValidationErrors.removeValue(forKey: "protein")
            }

        case "carbs":
            if let carbsDouble = Double(formCarbs), carbsDouble >= 0 {
                formValidationErrors.removeValue(forKey: "carbs")
            } else if !formCarbs.isEmpty {
                formValidationErrors["carbs"] = "Enter a valid number"
            } else {
                formValidationErrors.removeValue(forKey: "carbs")
            }

        case "fat":
            if let fatDouble = Double(formFat), fatDouble >= 0 {
                formValidationErrors.removeValue(forKey: "fat")
            } else if !formFat.isEmpty {
                formValidationErrors["fat"] = "Enter a valid number"
            } else {
                formValidationErrors.removeValue(forKey: "fat")
            }

        default:
            break
        }
    }

    /// Validates all form fields
    /// - Returns: True if form is valid, false otherwise
    func validateAllFields() -> Bool {
        // Validate food name
        if formFoodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formValidationErrors["foodName"] = "Food name is required"
            return false
        }

        // Validate calories
        guard let caloriesInt = Int(formCalories), caloriesInt >= 0 else {
            formValidationErrors["calories"] = "Enter a valid calorie count"
            return false
        }

        // Validate protein
        guard let proteinDouble = Double(formProtein), proteinDouble >= 0 else {
            formValidationErrors["protein"] = "Enter a valid protein amount"
            return false
        }

        // Validate carbs
        guard let carbsDouble = Double(formCarbs), carbsDouble >= 0 else {
            formValidationErrors["carbs"] = "Enter a valid carb amount"
            return false
        }

        // Validate fat
        guard let fatDouble = Double(formFat), fatDouble >= 0 else {
            formValidationErrors["fat"] = "Enter a valid fat amount"
            return false
        }

        // Clear all validation errors if everything is valid
        formValidationErrors = [:]
        return true
    }

    /// Submits the form with current field values
    func submitForm() async {
        guard validateAllFields() else { return }

        isSubmittingForm = true
        errorMessage = nil

        await addFoodEntry(
            name: formFoodName.trimmingCharacters(in: .whitespacesAndNewlines),
            calories: Int(formCalories) ?? 0,
            protein: Double(formProtein) ?? 0.0,
            carbs: Double(formCarbs) ?? 0.0,
            fat: Double(formFat) ?? 0.0,
            toxinScore: Int(formToxinScore)
        )

        isSubmittingForm = false

        // Reset form on success
        if errorMessage == nil {
            resetForm()
        }
    }
}
