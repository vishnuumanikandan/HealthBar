//
//  SavedRecipeDTO.swift
//  HealthBar
//
//  Created by Claude on 4/1/26.
//

import Foundation

/// Data Transfer Object for SavedRecipe cloud sync via Firestore.
///
/// Mirrors every persisted field of the SavedRecipe @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/savedRecipes/{id}), not the document body
///   - `photoData` — binary blobs exceed Firestore's 1 MB document limit; photos remain local-only
///
/// Ingredients are stored as a UTF-8 JSON string (the same JSON produced by SavedRecipe.ingredientsData)
/// so the DTO round-trips losslessly without introducing a new nested Codable type.
///
/// Firestore path: users/{userId}/savedRecipes/{id}
struct SavedRecipeDTO: Codable {

    // MARK: - Fields

    /// Firestore document ID — UUID string from SavedRecipe.id
    var id: String

    var name: String

    /// Number of servings the finished recipe yields
    var yield: Int

    /// UTF-8 JSON representation of [SavedMealComponent] (ingredients).
    /// Decoded via JSONDecoder in toSavedRecipe(userId:).
    var ingredientsJSON: String

    /// Calorie-weighted average purity score (0–100, lower = cleaner)
    var purityScore: Int

    var createdAt: Date

    // MARK: - Conversion: SavedRecipe → SavedRecipeDTO

    init(from recipe: SavedRecipe) {
        self.id = recipe.id.uuidString
        self.name = recipe.name
        self.yield = recipe.yield
        self.ingredientsJSON = String(data: recipe.ingredientsData, encoding: .utf8) ?? "[]"
        self.purityScore = recipe.purityScore
        self.createdAt = recipe.createdAt
    }

    // MARK: - Conversion: SavedRecipeDTO → SavedRecipe

    func toSavedRecipe(userId: String) -> SavedRecipe {
        let recipe = SavedRecipe(name: name, yield: yield)
        recipe.id = UUID(uuidString: id) ?? UUID()
        recipe.userId = userId
        recipe.ingredientsData = ingredientsJSON.data(using: .utf8) ?? Data()
        recipe.purityScore = purityScore
        recipe.createdAt = createdAt
        return recipe
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given SavedRecipe.
    /// photoData is excluded — it is not part of the DTO.
    func differsFrom(_ recipe: SavedRecipe) -> Bool {
        guard UUID(uuidString: id) == recipe.id else { return true }
        let localIngredientsJSON = String(data: recipe.ingredientsData, encoding: .utf8) ?? "[]"
        return name != recipe.name
            || yield != recipe.yield
            || ingredientsJSON != localIngredientsJSON
            || purityScore != recipe.purityScore
    }
}
