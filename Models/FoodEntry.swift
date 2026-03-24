//
//  FoodEntry.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftData

/// Represents a single food item logged by the user
///
/// Stores complete nutritional data, optional photo, and metadata for tracking meals.
/// Designed to support future AI analysis and barcode scanning features.
@Model
final class FoodEntry {
    /// Unique identifier for the food entry
    var id: UUID

    /// Display name of the food (e.g., "Grilled Chicken Salad")
    var name: String

    /// Date and time when the food was consumed
    var date: Date

    /// Optional photo of the meal (stored as Data for SwiftData compatibility)
    var photoData: Data?

    /// Total calories in the food item
    var calories: Int

    /// Protein content in grams
    var protein: Double

    /// Carbohydrate content in grams
    var carbs: Double

    /// Fat content in grams
    var fat: Double

    /// Toxin/processed food score (0-100, where lower is better/cleaner)
    /// Used for purity tracking and gamification
    var toxinScore: Int

    /// Optional UPC barcode for packaged foods (supports future barcode scanning)
    var barcodeUPC: String?

    /// Timestamp when this entry was created (for sorting and audit purposes)
    var createdAt: Date

    /// Scopes this record to an authenticated user.
    /// Defaults to "legacy" so pre-migration records remain valid without crashing.
    /// Legacy records are invisible to all real authenticated users — this is intentional.
    ///
    /// TODO: Replace currentUserEmail with a stable Firebase UID once Firebase is
    /// integrated in Phase 3. Never persist this as a permanent identifier — always
    /// read it live from AuthService at query time.
    var userId: String = "legacy"

    /// Whether this food is marked as a favorite for quick re-logging
    /// When toggled, applies to ALL entries with matching FoodFingerprint
    /// Uses inline default for SwiftData lightweight migration support
    var isFavorite: Bool = false

    /// Meal type (breakfast/lunch/dinner/snack) - auto-assigned based on time
    /// Uses inline default for SwiftData lightweight migration support
    var mealTypeRawValue: String = "uncategorized"

    /// Computed property for type-safe meal type access
    var mealType: MealType {
        get { MealType(rawValue: mealTypeRawValue) ?? .uncategorized }
        set { mealTypeRawValue = newValue.rawValue }
    }

    // MARK: - Advanced Nutrition (Optional)
    // These fields are only shown when "Track Advanced Nutrition" is enabled in settings
    // Uses inline defaults for SwiftData lightweight migration support

    /// Fiber content in grams (optional)
    var fiber: Double? = nil

    /// Sugar content in grams (optional)
    var sugar: Double? = nil

    /// Sodium content in milligrams (optional)
    var sodium: Double? = nil

    /// Saturated fat content in grams (optional)
    var saturatedFat: Double? = nil

    /// Cholesterol content in milligrams (optional)
    var cholesterol: Double? = nil

    /// Potassium content in milligrams (optional)
    var potassium: Double? = nil

    /// Initializes a new food entry with complete nutritional data
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - name: Display name of the food
    ///   - date: When the food was consumed (defaults to now)
    ///   - photoData: Optional meal photo
    ///   - calories: Total calories
    ///   - protein: Protein in grams
    ///   - carbs: Carbohydrates in grams
    ///   - fat: Fat in grams
    ///   - toxinScore: Processed food score (0-100)
    ///   - barcodeUPC: Optional barcode identifier
    ///   - createdAt: Creation timestamp (defaults to now)
    ///   - isFavorite: Whether this food is favorited (defaults to false)
    ///   - mealType: Meal category (defaults to uncategorized, usually auto-assigned)
    init(
        id: UUID = UUID(),
        name: String,
        date: Date = Date(),
        photoData: Data? = nil,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int,
        barcodeUPC: String? = nil,
        createdAt: Date = Date(),
        isFavorite: Bool = false,
        mealType: MealType = .uncategorized,
        // Advanced nutrition (optional)
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil,
        saturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        potassium: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.photoData = photoData
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.toxinScore = toxinScore
        self.barcodeUPC = barcodeUPC
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.mealTypeRawValue = mealType.rawValue
        // Advanced nutrition
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
        self.saturatedFat = saturatedFat
        self.cholesterol = cholesterol
        self.potassium = potassium
    }
}
