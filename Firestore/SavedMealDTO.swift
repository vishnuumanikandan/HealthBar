//
//  SavedMealDTO.swift
//  HealthBar
//
//  Created by Claude on 4/1/26.
//

import Foundation

/// Data Transfer Object for SavedMeal cloud sync via Firestore.
///
/// Mirrors every persisted field of the SavedMeal @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/savedMeals/{id}), not the document body
///   - `photoData` — binary blobs exceed Firestore's 1 MB document limit; photos remain local-only
///
/// Components are stored as a UTF-8 JSON string (the same JSON produced by SavedMeal.componentsData)
/// so the DTO round-trips losslessly without introducing a new nested Codable type.
///
/// Firestore path: users/{userId}/savedMeals/{id}
struct SavedMealDTO: Codable {

    // MARK: - Fields

    /// Firestore document ID — UUID string from SavedMeal.id
    var id: String

    var name: String

    /// UTF-8 JSON representation of [SavedMealComponent].
    /// Decoded via JSONDecoder in toSavedMeal(userId:).
    var componentsJSON: String

    var createdAt: Date

    // MARK: - Conversion: SavedMeal → SavedMealDTO

    init(from meal: SavedMeal) {
        self.id = meal.id.uuidString
        self.name = meal.name
        self.componentsJSON = String(data: meal.componentsData, encoding: .utf8) ?? "[]"
        self.createdAt = meal.createdAt
    }

    // MARK: - Conversion: SavedMealDTO → SavedMeal

    func toSavedMeal(userId: String) -> SavedMeal {
        let meal = SavedMeal(name: name)
        meal.id = UUID(uuidString: id) ?? UUID()
        meal.userId = userId
        meal.componentsData = componentsJSON.data(using: .utf8) ?? Data()
        meal.createdAt = createdAt
        return meal
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given SavedMeal.
    /// photoData is excluded — it is not part of the DTO.
    func differsFrom(_ meal: SavedMeal) -> Bool {
        guard UUID(uuidString: id) == meal.id else { return true }
        let localComponentsJSON = String(data: meal.componentsData, encoding: .utf8) ?? "[]"
        return name != meal.name || componentsJSON != localComponentsJSON
    }
}
