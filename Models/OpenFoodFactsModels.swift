//
//  OpenFoodFactsModels.swift
//  HealthBar
//
//  Created by Claude on 1/23/26.
//

import Foundation

// MARK: - Open Food Facts API Response Models

/// Response from Open Food Facts API
struct OpenFoodFactsResponse: Codable {
    /// Status code (1 = success, 0 = not found)
    let status: Int

    /// Product data (nil if not found)
    let product: OpenFoodFactsProduct?

    /// Status message
    let status_verbose: String?
}

/// Product data from Open Food Facts
struct OpenFoodFactsProduct: Codable {
    /// Product name
    let product_name: String?

    /// Nutrition data per 100g
    let nutriments: OpenFoodFactsNutriments?

    /// Serving size (e.g., "30g", "1 bar (50g)")
    let serving_size: String?

    /// Nutrition grade (a-e, where a is best)
    let nutrition_grades: String?

    /// Nova group (1-4, where 1 is unprocessed, 4 is ultra-processed)
    let nova_group: Int?

    /// List of additives
    let additives_tags: [String]?

    /// Brand name
    let brands: String?

    /// Product image URL
    let image_url: String?
}

/// Nutrition information per 100g
struct OpenFoodFactsNutriments: Codable {
    /// Energy in kcal per 100g
    let energy_kcal_100g: Double?

    /// Alternative energy field (some products use this)
    let energy_kcal: Double?

    /// Protein in grams per 100g
    let proteins_100g: Double?

    /// Protein alternative field
    let proteins: Double?

    /// Carbohydrates in grams per 100g
    let carbohydrates_100g: Double?

    /// Carbs alternative field
    let carbohydrates: Double?

    /// Fat in grams per 100g
    let fat_100g: Double?

    /// Fat alternative field
    let fat: Double?

    /// Fiber in grams per 100g (optional)
    let fiber_100g: Double?

    /// Sugar in grams per 100g (optional)
    let sugars_100g: Double?

    /// Sodium in grams per 100g (optional)
    let sodium_100g: Double?

    /// Saturated fat in grams per 100g (optional)
    let saturated_fat_100g: Double?

    /// Cholesterol in milligrams per 100g (optional)
    let cholesterol_100g: Double?

    /// Potassium in milligrams per 100g (optional)
    let potassium_100g: Double?

    // Custom coding keys to handle dashes in JSON keys
    enum CodingKeys: String, CodingKey {
        case energy_kcal_100g = "energy-kcal_100g"
        case energy_kcal = "energy-kcal"
        case proteins_100g
        case proteins
        case carbohydrates_100g
        case carbohydrates
        case fat_100g
        case fat
        case fiber_100g
        case sugars_100g
        case sodium_100g
        case saturated_fat_100g = "saturated-fat_100g"
        case cholesterol_100g
        case potassium_100g
    }
}

// MARK: - Parsed Food Nutrition Data

/// Simplified nutrition data extracted from API
struct FoodNutrition {
    let name: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let toxinScore: Int
    let servingSize: String?
    let brand: String?

    // MARK: - Advanced Nutrition (Optional)

    /// Fiber in grams
    let fiber: Double?

    /// Sugar in grams
    let sugar: Double?

    /// Sodium in milligrams
    let sodium: Double?

    /// Saturated fat in grams
    let saturatedFat: Double?

    /// Cholesterol in milligrams
    let cholesterol: Double?

    /// Potassium in milligrams
    let potassium: Double?

    // MARK: - Product Image (Optional)

    /// Product image data (resized JPEG)
    let photoData: Data?
}

// MARK: - Barcode Errors

enum BarcodeError: LocalizedError {
    case productNotFound
    case invalidBarcode
    case networkError
    case parsingError
    case cameraPermissionDenied

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Product not found in database. Please enter nutrition manually."
        case .invalidBarcode:
            return "Invalid barcode. Please try again."
        case .networkError:
            return "Network error. Please check your connection and try again."
        case .parsingError:
            return "Failed to read product data. Please enter manually."
        case .cameraPermissionDenied:
            return "Camera permission denied. Please enable in Settings."
        }
    }
}

// MARK: - Mock Data for Previews

extension OpenFoodFactsResponse {
    /// Mock response for testing and previews
    static var mock: OpenFoodFactsResponse {
        OpenFoodFactsResponse(
            status: 1,
            product: .mock,
            status_verbose: "product found"
        )
    }
}

extension OpenFoodFactsProduct {
    /// Mock product for testing and previews
    static var mock: OpenFoodFactsProduct {
        OpenFoodFactsProduct(
            product_name: "Mock Protein Bar",
            nutriments: .mock,
            serving_size: "50g",
            nutrition_grades: "b",
            nova_group: 3,
            additives_tags: ["en:e300", "en:e322"],
            brands: "Mock Brand",
            image_url: nil
        )
    }
}

extension OpenFoodFactsNutriments {
    /// Mock nutriments for testing and previews
    static var mock: OpenFoodFactsNutriments {
        OpenFoodFactsNutriments(
            energy_kcal_100g: 400,
            energy_kcal: nil,
            proteins_100g: 20.0,
            proteins: nil,
            carbohydrates_100g: 50.0,
            carbohydrates: nil,
            fat_100g: 14.0,
            fat: nil,
            fiber_100g: 5.0,
            sugars_100g: 20.0,
            sodium_100g: 0.5,
            saturated_fat_100g: 4.0,
            cholesterol_100g: 25.0,
            potassium_100g: 300.0
        )
    }
}

extension FoodNutrition {
    /// Mock nutrition data for testing and previews
    static var mock: FoodNutrition {
        FoodNutrition(
            name: "Mock Protein Bar",
            calories: 200,
            protein: 10.0,
            carbs: 25.0,
            fat: 7.0,
            toxinScore: 35,
            servingSize: "50g",
            brand: "Mock Brand",
            fiber: 2.5,
            sugar: 10.0,
            sodium: 250.0,
            saturatedFat: 2.0,
            cholesterol: 12.5,
            potassium: 150.0,
            photoData: nil
        )
    }
}
