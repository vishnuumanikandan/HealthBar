//
//  FoodEntryDTO.swift
//  HealthBar
//
//  Created by Claude on 3/24/26.
//

import Foundation

/// Data Transfer Object for FoodEntry cloud sync via Firestore.
///
/// This is a plain Codable struct with zero SwiftData dependencies.
/// It mirrors every persisted field of the FoodEntry @Model except:
///   - `photoData` — binary blobs are not Firestore-compatible (1MB doc limit); photos do not sync in Phase 1
///   - `userId` — encoded in the Firestore path (users/{userId}/foodEntries/{id}), not in the document body
///
/// The `id` field is the string representation of FoodEntry.id (UUID.uuidString).
/// It is used as the Firestore document ID and is the single stable link between SwiftData and Firestore.
///
/// Dates are stored as Firestore Timestamps automatically by the Firestore Codable encoder.
// TODO-bundle-sync: mealBundleId/mealBundleName are local-only (deliberately excluded here) — bundles flatten to solo entries on a cross-device re-download, matching the saved-meal precedent. Add both as optional fields with a rules check if bundles ever need to survive sync.
struct FoodEntryDTO: Codable {

    // MARK: - Fields (mirrors FoodEntry, minus photoData and userId)

    /// Firestore document ID — UUID string from FoodEntry.id
    var id: String

    var name: String
    var date: Date
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var toxinScore: Int
    var barcodeUPC: String?
    var createdAt: Date
    var isFavorite: Bool
    /// Raw string value of MealType enum — serialized directly, no enum dependency
    var mealTypeRawValue: String

    // Advanced nutrition (optional)
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var saturatedFat: Double?
    var cholesterol: Double?
    var potassium: Double?

    // MARK: - Conversion: FoodEntry → FoodEntryDTO

    /// Creates a DTO from a FoodEntry SwiftData model.
    /// `photoData` is intentionally excluded — it does not sync in Phase 1.
    /// `userId` is intentionally excluded — it is encoded in the Firestore path.
    init(from entry: FoodEntry) {
        self.id = entry.id.uuidString
        self.name = entry.name
        self.date = entry.date
        self.calories = entry.calories
        self.protein = entry.protein
        self.carbs = entry.carbs
        self.fat = entry.fat
        self.toxinScore = entry.toxinScore
        self.barcodeUPC = entry.barcodeUPC
        self.createdAt = entry.createdAt
        self.isFavorite = entry.isFavorite
        self.mealTypeRawValue = entry.mealTypeRawValue
        self.fiber = entry.fiber
        self.sugar = entry.sugar
        self.sodium = entry.sodium
        self.saturatedFat = entry.saturatedFat
        self.cholesterol = entry.cholesterol
        self.potassium = entry.potassium
    }

    // MARK: - Conversion: FoodEntryDTO → FoodEntry

    /// Creates a FoodEntry SwiftData model from this DTO.
    /// - Parameter userId: The authenticated user's ID (stamped onto the new entry).
    /// - Note: `photoData` will be nil — photos do not sync in Phase 1.
    /// - Note: If `id` cannot be parsed as a UUID, a new UUID is generated (should never happen).
    func toFoodEntry(userId: String) -> FoodEntry {
        let entry = FoodEntry(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            date: date,
            photoData: nil, // Photos do not sync in Phase 1
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            toxinScore: toxinScore,
            barcodeUPC: barcodeUPC,
            createdAt: createdAt,
            isFavorite: isFavorite,
            mealType: MealType(rawValue: mealTypeRawValue) ?? .uncategorized,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            saturatedFat: saturatedFat,
            cholesterol: cholesterol,
            potassium: potassium
        )
        entry.userId = userId
        return entry
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given FoodEntry.
    ///
    /// Used by `applyFirestoreUpdates` to avoid unnecessary SwiftData rewrites
    /// and to detect when a pending upload has been confirmed by the Firestore listener.
    ///
    /// `photoData` and `userId` are not compared — they are not part of the DTO.
    func differsFrom(_ entry: FoodEntry) -> Bool {
        guard UUID(uuidString: id) == entry.id else { return true }
        return name != entry.name
            || date != entry.date
            || calories != entry.calories
            || protein != entry.protein
            || carbs != entry.carbs
            || fat != entry.fat
            || toxinScore != entry.toxinScore
            || barcodeUPC != entry.barcodeUPC
            || createdAt != entry.createdAt
            || isFavorite != entry.isFavorite
            || mealTypeRawValue != entry.mealTypeRawValue
            || fiber != entry.fiber
            || sugar != entry.sugar
            || sodium != entry.sodium
            || saturatedFat != entry.saturatedFat
            || cholesterol != entry.cholesterol
            || potassium != entry.potassium
    }
}
