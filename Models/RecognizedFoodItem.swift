//
//  RecognizedFoodItem.swift
//  HealthBar
//
//  Created by Claude on 5/28/26.
//

import Foundation

/// A food item recognized by an AI service, ready for user review before logging.
///
/// Input-agnostic by design — no field references text, images, or any specific
/// recognition source. Reused identically by text description, photo recognition,
/// or any future input.
struct RecognizedFoodItem: Identifiable, Equatable {

    /// Client-side ID assigned on decode — never from the API.
    let id: UUID

    /// Display name of the food item (e.g. "Scrambled Eggs").
    var name: String

    /// Human-readable quantity label (e.g. "2 eggs", "1 slice") — display only, never used in math.
    var quantityText: String

    /// Estimated calories (whole number).
    var calories: Int

    /// Estimated protein in grams.
    var protein: Double

    /// Estimated carbohydrates in grams.
    var carbs: Double

    /// Estimated fat in grams.
    var fat: Double

    /// How confident the AI is in this estimate.
    var confidence: Confidence

    enum Confidence: String, Equatable {
        case high
        case medium
        case low
    }
}
