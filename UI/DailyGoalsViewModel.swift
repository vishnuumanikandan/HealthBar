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

    // GOALFIX-1: seeded empty, never with target constants. `loadCurrentGoals`
    // populates every field from the precedence rule before the form renders (the
    // view shows a loading state until then), so a constant seeded here could only
    // ever be a wrong value the user might save over their real goals.
    var calorieTarget: Int = 0
    var proteinTarget: Double = 0
    var carbTarget: Double = 0
    var fatTarget: Double = 0
    var purityTarget: Int = 0

    // MARK: - UI State

    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var showSuccessToast: Bool = false

    // MARK: - String Bindings for Text Fields

    var calorieTargetString: String = ""
    var proteinTargetString: String = ""
    var carbTargetString: String = ""
    var fatTargetString: String = ""
    var purityTargetString: String = ""

    // Advanced Nutrition Goal Strings (optional)
    var fiberTargetString: String = ""
    var sugarTargetString: String = ""
    var sodiumTargetString: String = ""
    var saturatedFatTargetString: String = ""
    var cholesterolTargetString: String = ""
    var potassiumTargetString: String = ""

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
            // GOALFIX-1: prefill resolves through getTodaysGoal() + the precedence
            // helper. Opening this form is a read, so it must not create a row —
            // and it must show the user's real targets (carried forward from their
            // last edit), never the generic defaults.
            let goal = try await coordinator.getGoalForDisplay()
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

            // Advanced nutrition goal strings (only if set)
            fiberTargetString = goal.fiberTarget.map { String(format: "%.0f", $0) } ?? ""
            sugarTargetString = goal.sugarTarget.map { String(format: "%.0f", $0) } ?? ""
            sodiumTargetString = goal.sodiumTarget.map { String(format: "%.0f", $0) } ?? ""
            saturatedFatTargetString = goal.saturatedFatTarget.map { String(format: "%.0f", $0) } ?? ""
            cholesterolTargetString = goal.cholesterolTarget.map { String(format: "%.0f", $0) } ?? ""
            potassiumTargetString = goal.potassiumTarget.map { String(format: "%.0f", $0) } ?? ""

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
            // Parse values from strings. `isFormValid` above has already proved every
            // field parses, so there is nothing to fall back TO — GOALFIX-1 drops the
            // old `?? 2000`-style fallbacks rather than leave target constants sitting
            // in the UI layer where they could be written over the user's real goals.
            guard let calories = Int(calorieTargetString),
                  let protein = Double(proteinTargetString),
                  let carbs = Double(carbTargetString),
                  let fat = Double(fatTargetString),
                  let purity = Int(purityTargetString) else {
                errorMessage = "Please enter valid values for all fields"
                isSaving = false
                return false
            }

            // Parse advanced nutrition goals (only if entered)
            let fiberTarget = fiberTargetString.isEmpty ? nil : Double(fiberTargetString)
            let sugarTarget = sugarTargetString.isEmpty ? nil : Double(sugarTargetString)
            let sodiumTarget = sodiumTargetString.isEmpty ? nil : Double(sodiumTargetString)
            let saturatedFatTarget = saturatedFatTargetString.isEmpty ? nil : Double(saturatedFatTargetString)
            let cholesterolTarget = cholesterolTargetString.isEmpty ? nil : Double(cholesterolTargetString)
            let potassiumTarget = potassiumTargetString.isEmpty ? nil : Double(potassiumTargetString)

            try await coordinator.updateDailyGoal(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                purity: purity,
                fiberTarget: fiberTarget,
                sugarTarget: sugarTarget,
                sodiumTarget: sodiumTarget,
                saturatedFatTarget: saturatedFatTarget,
                cholesterolTarget: cholesterolTarget,
                potassiumTarget: potassiumTarget
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
