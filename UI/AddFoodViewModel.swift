//
//  AddFoodViewModel.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftUI

/// ViewModel for adding a new food entry
///
/// Handles form state, validation, and submission.
@Observable
final class AddFoodViewModel {

    // MARK: - Properties

    private let coordinator: AppCoordinator

    // MARK: - Form State

    var foodName = ""
    var calories = ""
    var protein = ""
    var carbs = ""
    var fat = ""
    var toxinScore = ""

    // MARK: - UI State

    var isSubmitting = false
    var errorMessage: String?
    var showSuccessMessage = false
    var xpEarned = 0

    // MARK: - Validation

    /// Checks if the form is valid
    var isFormValid: Bool {
        !foodName.isEmpty &&
        !calories.isEmpty &&
        !protein.isEmpty &&
        !carbs.isEmpty &&
        !fat.isEmpty &&
        !toxinScore.isEmpty &&
        Int(calories) != nil &&
        Double(protein) != nil &&
        Double(carbs) != nil &&
        Double(fat) != nil &&
        Int(toxinScore) != nil
    }

    /// Validation error messages
    var validationErrors: [String] {
        var errors: [String] = []

        if foodName.isEmpty {
            errors.append("Food name is required")
        }
        if calories.isEmpty || Int(calories) == nil {
            errors.append("Valid calorie count required")
        }
        if protein.isEmpty || Double(protein) == nil {
            errors.append("Valid protein amount required")
        }
        if carbs.isEmpty || Double(carbs) == nil {
            errors.append("Valid carb amount required")
        }
        if fat.isEmpty || Double(fat) == nil {
            errors.append("Valid fat amount required")
        }
        if toxinScore.isEmpty || Int(toxinScore) == nil {
            errors.append("Valid toxin score required (0-100)")
        } else if let score = Int(toxinScore), score < 0 || score > 100 {
            errors.append("Toxin score must be between 0 and 100")
        }

        return errors
    }

    // MARK: - Initialization

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Actions

    /// Submits the food entry
    func submitFood() async -> Bool {
        guard isFormValid else {
            errorMessage = validationErrors.first
            return false
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let result = try await coordinator.addFoodEntry(
                name: foodName,
                calories: Int(calories)!,
                protein: Double(protein)!,
                carbs: Double(carbs)!,
                fat: Double(fat)!,
                toxinScore: Int(toxinScore)!
            )

            xpEarned = result.xpEarned
            showSuccessMessage = true
            clearForm()
            isSubmitting = false
            return true

        } catch {
            errorMessage = "Failed to add food: \(error.localizedDescription)"
            isSubmitting = false
            return false
        }
    }

    /// Clears the form
    func clearForm() {
        foodName = ""
        calories = ""
        protein = ""
        carbs = ""
        fat = ""
        toxinScore = ""
    }

    /// Dismisses success message
    func dismissSuccessMessage() {
        showSuccessMessage = false
        xpEarned = 0
    }
}
