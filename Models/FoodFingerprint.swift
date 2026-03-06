//
//  FoodFingerprint.swift
//  HealthBar
//
//  Created by Claude on 1/24/26.
//

import Foundation

/// Represents a unique food identity based on nutrition profile
///
/// Used to determine uniqueness for Recent Foods and Favorites.
/// Two foods with identical fingerprints are considered the same food item.
///
/// This approach solves the problem of:
/// - Same name, different calories (e.g., "Chicken Breast" raw vs cooked)
/// - Same name, different brands (e.g., "Protein Shake")
/// - Barcode vs manual entries that should be treated as different
struct FoodFingerprint: Hashable, Equatable {
    /// Food name
    let name: String

    /// Total calories
    let calories: Int

    /// Protein in grams (rounded to 1 decimal for comparison)
    let protein: Double

    /// Carbs in grams (rounded to 1 decimal for comparison)
    let carbs: Double

    /// Fat in grams (rounded to 1 decimal for comparison)
    let fat: Double

    /// Optional barcode UPC (barcode entries are distinct from manual entries)
    let barcodeUPC: String?

    /// Creates a fingerprint from a FoodEntry
    /// - Parameter entry: The food entry to create a fingerprint from
    init(from entry: FoodEntry) {
        self.name = entry.name
        self.calories = entry.calories
        // Round to 1 decimal place for comparison (avoids floating point issues)
        self.protein = (entry.protein * 10).rounded() / 10
        self.carbs = (entry.carbs * 10).rounded() / 10
        self.fat = (entry.fat * 10).rounded() / 10
        self.barcodeUPC = entry.barcodeUPC
    }

    /// Creates a fingerprint from individual values
    init(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        barcodeUPC: String?
    ) {
        self.name = name
        self.calories = calories
        self.protein = (protein * 10).rounded() / 10
        self.carbs = (carbs * 10).rounded() / 10
        self.fat = (fat * 10).rounded() / 10
        self.barcodeUPC = barcodeUPC
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(calories)
        hasher.combine(protein)
        hasher.combine(carbs)
        hasher.combine(fat)
        hasher.combine(barcodeUPC)
    }

    // MARK: - Equatable

    static func == (lhs: FoodFingerprint, rhs: FoodFingerprint) -> Bool {
        return lhs.name == rhs.name &&
               lhs.calories == rhs.calories &&
               lhs.protein == rhs.protein &&
               lhs.carbs == rhs.carbs &&
               lhs.fat == rhs.fat &&
               lhs.barcodeUPC == rhs.barcodeUPC
    }
}
