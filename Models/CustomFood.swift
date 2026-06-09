//
//  CustomFood.swift
//  HealthBar
//
//  Created by Claude on 3/29/26.
//

import Foundation
import SwiftData

/// A user-created custom food entry stored in the personal food library.
///
/// Custom foods appear in the "My Foods" tab and are also searchable
/// from the All Foods tab. They can be logged via ServingSizePickerSheet
/// or added as components to meals and recipes.
@Model
final class CustomFood {

    /// Unique identifier
    var id: UUID

    /// Display name of the food (e.g., "Mom's Pasta")
    var name: String

    /// Calories per base serving
    var calories: Int

    /// Protein in grams per base serving
    var protein: Double

    /// Carbohydrates in grams per base serving
    var carbs: Double

    /// Fat in grams per base serving
    var fat: Double

    /// Human-readable serving size label (e.g., "1 cup", "100g", "1 plate")
    var servingSizeName: String

    /// The numeric base amount for this serving (denominator for scaling)
    /// e.g., 100 if servingUnit is "g" and nutrition is per 100g; 1 if "cup"
    var servingSizeAmount: Double

    /// The unit label for quantity entry (e.g., "g", "cup", "oz", "serving")
    var servingUnit: String

    /// Toxin/processing score (0-100, lower is cleaner); defaults to 0 for custom foods
    var toxinScore: Int = 0

    /// Optional fiber in grams per base serving
    var fiber: Double? = nil

    /// Optional sugar in grams per base serving
    var sugar: Double? = nil

    /// Optional sodium in milligrams per base serving
    var sodium: Double? = nil

    /// Scopes this record to an authenticated user.
    /// Defaults to "legacy" for lightweight migration safety.
    var userId: String = "legacy"

    /// When this custom food was created
    var createdAt: Date

    init(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        servingSizeName: String = "1 serving",
        servingSizeAmount: Double = 1.0,
        servingUnit: String = "serving",
        toxinScore: Int = 0,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSizeName = servingSizeName
        self.servingSizeAmount = servingSizeAmount
        self.servingUnit = servingUnit
        self.toxinScore = toxinScore
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
        self.createdAt = Date()
    }
}
