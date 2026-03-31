//
//  SavedMeal.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import Foundation
import SwiftData

// MARK: - SavedMealComponent

/// A single food item inside a SavedMeal or SavedRecipe, storing
/// denormalized nutrition at the recorded quantity.
///
/// Stored as JSON inside SavedMeal.componentsData / SavedRecipe.ingredientsData.
struct SavedMealComponent: Codable, Identifiable, Hashable {
    var id: UUID
    var foodName: String
    /// The user-specified quantity (e.g., 2 for 2 eggs)
    var quantity: Double
    /// Unit label shown next to quantity (e.g., "eggs", "g", "cup")
    var servingUnit: String
    /// Calories at this quantity
    var calories: Int
    /// Protein in grams at this quantity
    var protein: Double
    /// Carbs in grams at this quantity
    var carbs: Double
    /// Fat in grams at this quantity
    var fat: Double
    /// Purity/toxin score (0–100, lower = cleaner). Sourced from the food's toxinScore at time of addition.
    var toxinScore: Int

    init(
        foodName: String,
        quantity: Double,
        servingUnit: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int = 0
    ) {
        self.id = UUID()
        self.foodName = foodName
        self.quantity = quantity
        self.servingUnit = servingUnit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.toxinScore = toxinScore
    }
}

// MARK: - SavedMeal

/// A reusable bundle of food items that can be logged as a single action.
///
/// Nutrition is never stored on the meal itself — it is always derived by
/// summing the component calories/macros at their saved quantities.
@Model
final class SavedMeal {

    var id: UUID

    /// Display name (e.g., "Pre-Workout Snack", "Sunday Breakfast")
    var name: String

    /// JSON-encoded array of SavedMealComponent.
    /// Use the `components` computed property for type-safe access.
    var componentsData: Data

    /// Scopes this record to an authenticated user.
    var userId: String = "legacy"

    /// Optional meal photo (lightweight migration inline default)
    var photoData: Data? = nil

    var createdAt: Date

    // MARK: - Computed Nutrition (always derived, never stored)

    var components: [SavedMealComponent] {
        get {
            (try? JSONDecoder().decode([SavedMealComponent].self, from: componentsData)) ?? []
        }
        set {
            componentsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var totalCalories: Int {
        components.reduce(0) { $0 + $1.calories }
    }

    var totalProtein: Double {
        components.reduce(0.0) { $0 + $1.protein }
    }

    var totalCarbs: Double {
        components.reduce(0.0) { $0 + $1.carbs }
    }

    var totalFat: Double {
        components.reduce(0.0) { $0 + $1.fat }
    }

    init(name: String, components: [SavedMealComponent] = []) {
        self.id = UUID()
        self.name = name
        self.componentsData = (try? JSONEncoder().encode(components)) ?? Data()
        self.createdAt = Date()
    }
}
