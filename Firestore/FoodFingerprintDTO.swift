//
//  FoodFingerprintDTO.swift
//  HealthBar
//
//  Created by Claude on 3/25/26.
//

import Foundation

/// Data Transfer Object for FoodFingerprint cloud sync via Firestore.
///
/// Plain Codable struct with zero SwiftData dependencies.
///
/// **Note on stable ID:** FoodFingerprint is a plain Swift struct (not a SwiftData @Model).
/// It has no `id` field — it is identified by its content (it is Hashable/Equatable by value).
/// `FoodFingerprintDTO.id` is therefore a deterministic string derived from the content fields,
/// ensuring the same food always maps to the same Firestore document.
///
/// **Derivation:** `id = "\(name)|\(calories)|\(protein)|\(carbs)|\(fat)|\(barcodeUPC ?? "")`
/// where protein/carbs/fat are rounded to 1 decimal (matching FoodFingerprint.init rounding).
/// Any `/` in the name is replaced with `_` since Firestore document IDs cannot contain `/`.
///
/// **Note on SwiftData:** Since FoodFingerprint is not a @Model, listener updates from
/// Firestore do not write to SwiftData. The collection serves as a cross-device food library
/// index. FoodEntry sync (Phase 1) already carries all nutritional and favorite data.
///
/// Firestore path: users/{userId}/foodFingerprints/{id}
struct FoodFingerprintDTO: Codable {

    // MARK: - Fields

    /// Deterministic document ID derived from content fields (see stableId helper).
    var id: String

    var name: String
    var calories: Int
    var protein: Double  // Rounded to 1 decimal place
    var carbs: Double    // Rounded to 1 decimal place
    var fat: Double      // Rounded to 1 decimal place
    var barcodeUPC: String?

    // MARK: - Stable ID Generation

    /// Produces a stable, deterministic Firestore document ID from FoodFingerprint fields.
    /// Uses the same rounding as FoodFingerprint.init for consistency.
    static func stableId(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        barcodeUPC: String?
    ) -> String {
        let roundedProtein = String(format: "%.1f", (protein * 10).rounded() / 10)
        let roundedCarbs   = String(format: "%.1f", (carbs * 10).rounded() / 10)
        let roundedFat     = String(format: "%.1f", (fat * 10).rounded() / 10)
        let raw = "\(name)|\(calories)|\(roundedProtein)|\(roundedCarbs)|\(roundedFat)|\(barcodeUPC ?? "")"
        // Firestore document IDs cannot contain '/'; replace with '_'
        return raw.replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Conversion: FoodFingerprint → FoodFingerprintDTO

    init(from fingerprint: FoodFingerprint) {
        self.id = FoodFingerprintDTO.stableId(
            name: fingerprint.name,
            calories: fingerprint.calories,
            protein: fingerprint.protein,
            carbs: fingerprint.carbs,
            fat: fingerprint.fat,
            barcodeUPC: fingerprint.barcodeUPC
        )
        self.name = fingerprint.name
        self.calories = fingerprint.calories
        // FoodFingerprint.init already rounds to 1 decimal; store as-is
        self.protein = fingerprint.protein
        self.carbs = fingerprint.carbs
        self.fat = fingerprint.fat
        self.barcodeUPC = fingerprint.barcodeUPC
    }

    /// Convenience init from a FoodEntry (derives fingerprint inline).
    init(from entry: FoodEntry) {
        self.init(from: FoodFingerprint(from: entry))
    }

    // MARK: - Conversion: FoodFingerprintDTO → FoodFingerprint

    /// Reconstructs a FoodFingerprint value type from this DTO.
    func toFoodFingerprint() -> FoodFingerprint {
        FoodFingerprint(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            barcodeUPC: barcodeUPC
        )
    }
}
