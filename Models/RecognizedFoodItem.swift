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

    /// AI-estimated processing/toxin score (0–100). Service-normalized, never absent.
    var toxinScore: Int

    /// Advanced micronutrients — `nil` when the AI could not reasonably estimate the field.
    /// Units: fiber/sugar/saturatedFat in grams; sodium/cholesterol/potassium in milligrams.
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var saturatedFat: Double?
    var cholesterol: Double?
    var potassium: Double?

    /// Immutable baseline macro snapshot captured at decode (= the AI's initial values).
    let baselineCalories: Int
    let baselineProtein: Double
    let baselineCarbs: Double
    let baselineFat: Double

    /// Short phrase explaining why an item is uncertain. `nil` for high-confidence items.
    var confidenceReason: String?

    /// Clarifying questions attached to this item, ordered by importance descending.
    var clarifications: [FoodClarification]

    enum Confidence: String, Equatable {
        case high
        case medium
        case low
    }

    init(
        id: UUID,
        name: String,
        quantityText: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        confidence: Confidence,
        toxinScore: Int = 30,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil,
        saturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        potassium: Double? = nil,
        baselineCalories: Int? = nil,
        baselineProtein: Double? = nil,
        baselineCarbs: Double? = nil,
        baselineFat: Double? = nil,
        confidenceReason: String? = nil,
        clarifications: [FoodClarification] = []
    ) {
        self.id = id
        self.name = name
        self.quantityText = quantityText
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.confidence = confidence
        self.toxinScore = toxinScore
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
        self.saturatedFat = saturatedFat
        self.cholesterol = cholesterol
        self.potassium = potassium
        self.baselineCalories = baselineCalories ?? calories
        self.baselineProtein = baselineProtein ?? protein
        self.baselineCarbs = baselineCarbs ?? carbs
        self.baselineFat = baselineFat ?? fat
        self.confidenceReason = confidenceReason
        self.clarifications = clarifications
    }
}
