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
        createdAt: Date = Date()
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
    }
}
