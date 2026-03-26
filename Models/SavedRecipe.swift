//
//  SavedRecipe.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import Foundation
import SwiftData

/// A user-built recipe that calculates per-serving nutrition from its ingredients.
///
/// The end result of a recipe is saved as a new `CustomFood` entry in My Foods,
/// where the user can then log it via the normal Serving Size Picker flow.
/// The recipe itself is stored here so the user can edit it later.
@Model
final class SavedRecipe {

    var id: UUID

    /// Display name (e.g., "Chicken Fried Rice")
    var name: String

    /// Number of servings the finished recipe yields
    var yield: Int

    /// JSON-encoded array of SavedMealComponent (the ingredients).
    /// Use the `ingredients` computed property for type-safe access.
    var ingredientsData: Data

    /// Scopes this record to an authenticated user.
    var userId: String = "legacy"

    /// Optional recipe photo (lightweight migration inline default)
    var photoData: Data? = nil

    var createdAt: Date

    // MARK: - Computed Nutrition

    var ingredients: [SavedMealComponent] {
        get {
            (try? JSONDecoder().decode([SavedMealComponent].self, from: ingredientsData)) ?? []
        }
        set {
            ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// Total calories for the whole recipe
    var totalCalories: Int {
        ingredients.reduce(0) { $0 + $1.calories }
    }

    /// Total protein for the whole recipe
    var totalProtein: Double {
        ingredients.reduce(0.0) { $0 + $1.protein }
    }

    /// Total carbs for the whole recipe
    var totalCarbs: Double {
        ingredients.reduce(0.0) { $0 + $1.carbs }
    }

    /// Total fat for the whole recipe
    var totalFat: Double {
        ingredients.reduce(0.0) { $0 + $1.fat }
    }

    /// Calories per serving (total ÷ yield)
    var perServingCalories: Int {
        yield > 0 ? Int((Double(totalCalories) / Double(yield)).rounded()) : 0
    }

    /// Protein per serving
    var perServingProtein: Double {
        yield > 0 ? totalProtein / Double(yield) : 0
    }

    /// Carbs per serving
    var perServingCarbs: Double {
        yield > 0 ? totalCarbs / Double(yield) : 0
    }

    /// Fat per serving
    var perServingFat: Double {
        yield > 0 ? totalFat / Double(yield) : 0
    }

    init(name: String, yield: Int = 1, ingredients: [SavedMealComponent] = []) {
        self.id = UUID()
        self.name = name
        self.yield = max(1, yield)
        self.ingredientsData = (try? JSONEncoder().encode(ingredients)) ?? Data()
        self.createdAt = Date()
    }
}
