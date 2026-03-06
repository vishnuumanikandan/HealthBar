//
//  DailyGoalsViewModel.swift
//  HealthBar
//
//  Created by Claude on 1/26/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Daily Goals editing screen
///
/// Handles loading current goals, validating input, and saving changes.
/// Interacts with AppCoordinator for all business logic.
@Observable
final class DailyGoalsViewModel {

    // MARK: - Form State

    var calorieTarget: Int = 2000
    var proteinTarget: Double = 150
    var carbTarget: Double = 200
    var fatTarget: Double = 65
    var purityTarget: Int = 50

    // MARK: - UI State

    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var showSuccessToast: Bool = false

    // MARK: - String Bindings for Text Fields

    var calorieTargetString: String = "2000"
    var proteinTargetString: String = "150"
    var carbTargetString: String = "200"
    var fatTargetString: String = "65"
    var purityTargetString: String = "50"

    // MARK: - Private Properties

    private let coordinator: AppCoordinator

    // MARK: - Initialization

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Computed Properties

    /// Validates that all inputs are valid numbers within acceptable ranges
    var isFormValid: Bool {
        guard let calories = Int(calorieTargetString), calories > 0, calories <= 10000 else { return false }
        guard let protein = Double(proteinTargetString), protein >= 0, protein <= 500 else { return false }
        guard let carbs = Double(carbTargetString), carbs >= 0, carbs <= 1000 else { return false }
        guard let fat = Double(fatTargetString), fat >= 0, fat <= 500 else { return false }
        guard let purity = Int(purityTargetString), purity >= 0, purity <= 100 else { return false }
        return true
    }

    // MARK: - Public Methods

    /// Loads current goals from DataManager
    @MainActor
    func loadCurrentGoals() async {
        isLoading = true
        errorMessage = nil

        do {
            let goal = try await coordinator.getCurrentGoal()
            calorieTarget = goal.calorieTarget
            proteinTarget = goal.proteinTarget
            carbTarget = goal.carbTarget
            fatTarget = goal.fatTarget
            purityTarget = goal.purityTarget

            // Update string bindings
            calorieTargetString = "\(goal.calorieTarget)"
            proteinTargetString = String(format: "%.0f", goal.proteinTarget)
            carbTargetString = String(format: "%.0f", goal.carbTarget)
            fatTargetString = String(format: "%.0f", goal.fatTarget)
            purityTargetString = "\(goal.purityTarget)"

        } catch {
            errorMessage = "Failed to load goals: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Saves goals to DataManager
    /// - Returns: True if save was successful
    @MainActor
    func saveGoals() async -> Bool {
        guard isFormValid else {
            errorMessage = "Please enter valid values for all fields"
            return false
        }

        isSaving = true
        errorMessage = nil

        do {
            // Parse values from strings
            let calories = Int(calorieTargetString) ?? 2000
            let protein = Double(proteinTargetString) ?? 150
            let carbs = Double(carbTargetString) ?? 200
            let fat = Double(fatTargetString) ?? 65
            let purity = Int(purityTargetString) ?? 50

            try await coordinator.updateDailyGoal(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                purity: purity
            )

            // Success feedback
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            showSuccessToast = true
            isSaving = false
            return true

        } catch {
            errorMessage = "Failed to save goals: \(error.localizedDescription)"

            // Error haptic
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif

            isSaving = false
            return false
        }
    }
}
