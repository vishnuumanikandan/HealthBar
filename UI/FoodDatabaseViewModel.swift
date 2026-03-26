//
//  FoodDatabaseViewModel.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import Foundation
import SwiftUI

/// ViewModel for the Food Database screen and its 5 tabs.
///
/// Manages search state, custom foods, saved meals, saved recipes, and
/// coordinates food logging via the AppCoordinator.
@Observable
@MainActor
final class FoodDatabaseViewModel {

    // MARK: - Properties

    let coordinator: AppCoordinator

    // MARK: - Built-in Food Search

    /// Live-filtered results from the built-in ingredient library
    var filteredBuiltInFoods: [BuiltInFood] = BuiltInFoods.all

    /// Current search text for the All Foods tab
    var allFoodsSearchText: String = "" {
        didSet { filterBuiltInFoods() }
    }

    // MARK: - Custom Foods (My Foods tab)

    var customFoods: [CustomFood] = []
    var myFoodsSearchText: String = "" {
        didSet { filterCustomFoods() }
    }
    var filteredCustomFoods: [CustomFood] = []
    var showingAddCustomFood: Bool = false
    var editingCustomFood: CustomFood? = nil

    // MARK: - Saved Meals (My Meals tab)

    var savedMeals: [SavedMeal] = []
    var showingMealBuilder: Bool = false
    var editingMeal: SavedMeal? = nil

    // MARK: - Saved Recipes (My Recipes tab)

    var savedRecipes: [SavedRecipe] = []
    var showingRecipeBuilder: Bool = false
    var editingRecipe: SavedRecipe? = nil

    // MARK: - Serving Size Picker

    /// The food item selected for serving size adjustment before logging
    var pendingLogFood: LoggableFood? = nil
    var showingServingSizePicker: Bool = false

    // MARK: - Toast

    var toastMessage: String? = nil
    var showToast: Bool = false

    // MARK: - Loading

    var isLoading: Bool = false

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Load

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        async let foods: () = loadCustomFoods()
        async let meals: () = loadSavedMeals()
        async let recipes: () = loadSavedRecipes()
        _ = await (foods, meals, recipes)
    }

    func loadCustomFoods() async {
        do {
            customFoods = try await coordinator.getCustomFoods()
            filterCustomFoods()
        } catch {
            customFoods = []
            filteredCustomFoods = []
        }
    }

    func loadSavedMeals() async {
        do { savedMeals = try await coordinator.getSavedMeals() } catch { savedMeals = [] }
    }

    func loadSavedRecipes() async {
        do { savedRecipes = try await coordinator.getSavedRecipes() } catch { savedRecipes = [] }
    }

    // MARK: - Search / Filter

    func filterBuiltInFoods() {
        let q = allFoodsSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filteredBuiltInFoods = BuiltInFoods.all
        } else {
            filteredBuiltInFoods = BuiltInFoods.all.filter { $0.name.lowercased().contains(q) }
        }
    }

    func filterCustomFoods() {
        let q = myFoodsSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filteredCustomFoods = customFoods
        } else {
            filteredCustomFoods = customFoods.filter { $0.name.lowercased().contains(q) }
        }
    }

    /// Returns a merged list of built-in + custom foods filtered by query.
    /// Used by MiniFoodPickerView inside meal/recipe builders.
    func searchAllFoods(query: String) -> [LoggableFood] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var results: [LoggableFood] = []

        // Custom foods first (user's personal library)
        let matchedCustom = customFoods.filter { q.isEmpty || $0.name.lowercased().contains(q) }
        results += matchedCustom.map { LoggableFood(from: $0) }

        // Then built-ins
        let matchedBuiltIn = BuiltInFoods.all.filter { q.isEmpty || $0.name.lowercased().contains(q) }
        results += matchedBuiltIn.map { LoggableFood(from: $0) }

        return results
    }

    // MARK: - Logging

    /// Opens the serving size picker for a built-in food
    func beginLog(builtIn food: BuiltInFood) {
        pendingLogFood = LoggableFood(from: food)
        showingServingSizePicker = true
    }

    /// Opens the serving size picker for a custom food
    func beginLog(custom food: CustomFood) {
        pendingLogFood = LoggableFood(from: food)
        showingServingSizePicker = true
    }

    /// Opens the serving size picker to log a saved recipe directly (per-serving nutrition)
    func beginLog(recipe: SavedRecipe) {
        pendingLogFood = LoggableFood(from: recipe)
        showingServingSizePicker = true
    }

    /// Opens the serving size picker for a favorited FoodEntry (re-log)
    func beginLog(entry: FoodEntry) {
        pendingLogFood = LoggableFood(
            id: entry.id,
            name: entry.name,
            caloriesPerBase: entry.calories,
            proteinPerBase: entry.protein,
            carbsPerBase: entry.carbs,
            fatPerBase: entry.fat,
            baseAmount: 1.0,
            unit: "serving",
            servingDescription: "1 serving",
            toxinScore: entry.toxinScore
        )
        showingServingSizePicker = true
    }

    /// Logs a food at the given scaled quantity. Called from ServingSizePickerSheet.
    func confirmLog(
        food: LoggableFood,
        quantity: Double,
        date: Date,
        mealType: MealType
    ) async {
        let scaled = food.scaled(to: quantity)
        do {
            _ = try await coordinator.addFoodEntry(
                name: food.name,
                calories: scaled.calories,
                protein: scaled.protein,
                carbs: scaled.carbs,
                fat: scaled.fat,
                toxinScore: food.toxinScore,
                date: date,
                mealType: mealType
            )
            showToastMessage("\(food.name) logged!")
        } catch {
            showToastMessage("Couldn't log — try again")
        }
    }

    // MARK: - Custom Food CRUD

    func saveCustomFood(_ food: CustomFood, isNew: Bool) async {
        do {
            if isNew {
                try await coordinator.addCustomFood(food)
            } else {
                try await coordinator.updateCustomFood(food)
            }
            await loadCustomFoods()
        } catch {
            showToastMessage("Couldn't save food")
        }
    }

    func deleteCustomFood(_ food: CustomFood) async {
        do {
            try await coordinator.deleteCustomFood(food)
            await loadCustomFoods()
        } catch {
            showToastMessage("Couldn't delete food")
        }
    }

    // MARK: - Saved Meal CRUD

    func saveMeal(_ meal: SavedMeal, isNew: Bool) async {
        do {
            if isNew {
                try await coordinator.addSavedMeal(meal)
            } else {
                try await coordinator.updateSavedMeal(meal)
            }
            await loadSavedMeals()
        } catch {
            showToastMessage("Couldn't save meal")
        }
    }

    func deleteSavedMeal(_ meal: SavedMeal) async {
        do {
            try await coordinator.deleteSavedMeal(meal)
            await loadSavedMeals()
        } catch {
            showToastMessage("Couldn't delete meal")
        }
    }

    func logMeal(_ meal: SavedMeal, date: Date, mealType: MealType) async {
        do {
            _ = try await coordinator.logSavedMeal(meal, date: date, mealType: mealType)
            showToastMessage("\(meal.name) logged!")
        } catch {
            showToastMessage("Couldn't log meal — try again")
        }
    }

    // MARK: - Saved Recipe CRUD

    func saveRecipe(_ recipe: SavedRecipe, isNew: Bool) async {
        do {
            if isNew {
                try await coordinator.addSavedRecipe(recipe)
            } else {
                try await coordinator.updateSavedRecipe(recipe)
            }
            await loadSavedRecipes()
        } catch {
            showToastMessage("Couldn't save recipe")
        }
    }

    func deleteRecipe(_ recipe: SavedRecipe) async {
        do {
            try await coordinator.deleteSavedRecipe(recipe)
            await loadSavedRecipes()
        } catch {
            showToastMessage("Couldn't delete recipe")
        }
    }

    func saveRecipeAsFood(_ recipe: SavedRecipe) async {
        if customFoods.contains(where: { $0.name.caseInsensitiveCompare(recipe.name) == .orderedSame }) {
            showToastMessage("\(recipe.name) is already in My Foods")
            return
        }
        do {
            let food = try await coordinator.saveRecipeAsFood(recipe)
            await loadCustomFoods()
            showToastMessage("\(food.name) saved to My Foods!")
        } catch {
            showToastMessage("Couldn't save recipe as food")
        }
    }

    // MARK: - Toast

    func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { showToast = false }
            }
        }
    }
}

// MARK: - LoggableFood convenience init (no external food source)

extension LoggableFood {
    init(id: UUID, name: String, caloriesPerBase: Int, proteinPerBase: Double,
         carbsPerBase: Double, fatPerBase: Double, baseAmount: Double,
         unit: String, servingDescription: String, toxinScore: Int) {
        self.id = id
        self.name = name
        self.caloriesPerBase = caloriesPerBase
        self.proteinPerBase = proteinPerBase
        self.carbsPerBase = carbsPerBase
        self.fatPerBase = fatPerBase
        self.baseAmount = baseAmount
        self.unit = unit
        self.servingDescription = servingDescription
        self.toxinScore = toxinScore
    }
}
