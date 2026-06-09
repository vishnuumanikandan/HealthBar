//
//  CustomFoodDTO.swift
//  HealthBar
//
//  Created by Claude on 4/1/26.
//

import Foundation

/// Data Transfer Object for CustomFood cloud sync via Firestore.
///
/// Mirrors every persisted field of the CustomFood @Model except:
///   - `userId` — encoded in the Firestore path (users/{userId}/customFoods/{id}), not the document body
///
/// Firestore path: users/{userId}/customFoods/{id}
struct CustomFoodDTO: Codable {

    // MARK: - Fields

    /// Firestore document ID — UUID string from CustomFood.id
    var id: String

    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSizeName: String
    var servingSizeAmount: Double
    var servingUnit: String
    var toxinScore: Int
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var createdAt: Date

    // MARK: - Conversion: CustomFood → CustomFoodDTO

    init(from food: CustomFood) {
        self.id = food.id.uuidString
        self.name = food.name
        self.calories = food.calories
        self.protein = food.protein
        self.carbs = food.carbs
        self.fat = food.fat
        self.servingSizeName = food.servingSizeName
        self.servingSizeAmount = food.servingSizeAmount
        self.servingUnit = food.servingUnit
        self.toxinScore = food.toxinScore
        self.fiber = food.fiber
        self.sugar = food.sugar
        self.sodium = food.sodium
        self.createdAt = food.createdAt
    }

    // MARK: - Conversion: CustomFoodDTO → CustomFood

    func toCustomFood(userId: String) -> CustomFood {
        let food = CustomFood(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            servingSizeName: servingSizeName,
            servingSizeAmount: servingSizeAmount,
            servingUnit: servingUnit,
            toxinScore: toxinScore,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium
        )
        food.id = UUID(uuidString: id) ?? UUID()
        food.userId = userId
        food.createdAt = createdAt
        return food
    }

    // MARK: - Diff Helper

    /// Returns true if any persisted field in this DTO differs from the given CustomFood.
    func differsFrom(_ food: CustomFood) -> Bool {
        guard UUID(uuidString: id) == food.id else { return true }
        return name != food.name
            || calories != food.calories
            || protein != food.protein
            || carbs != food.carbs
            || fat != food.fat
            || servingSizeName != food.servingSizeName
            || servingSizeAmount != food.servingSizeAmount
            || servingUnit != food.servingUnit
            || toxinScore != food.toxinScore
            || fiber != food.fiber
            || sugar != food.sugar
            || sodium != food.sodium
    }
}
