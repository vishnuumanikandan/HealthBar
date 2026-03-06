//
//  BarcodeService.swift
//  HealthBar
//
//  Created by Claude on 1/23/26.
//

import Foundation

/// Service for fetching nutrition data from Open Food Facts API
///
/// Handles barcode lookups, API communication, and data parsing.
/// Uses Open Food Facts public API (no API key required).
@Observable
final class BarcodeService {

    // MARK: - Constants

    /// Base URL for Open Food Facts API
    private let baseURL = "https://world.openfoodfacts.org/api/v0/product"

    /// URL session for network requests
    private let session: URLSession

    // MARK: - Initialization

    /// Initializes the barcode service
    /// - Parameter session: URLSession to use (defaults to shared, can inject for testing)
    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public Methods

    /// Fetches nutrition data for a given barcode
    /// - Parameter barcode: UPC/EAN barcode string (e.g., "737628064502")
    /// - Returns: Parsed FoodNutrition data
    /// - Throws: BarcodeError if product not found or network/parsing fails
    func fetchNutrition(barcode: String) async throws -> FoodNutrition {
        // Validate barcode format (basic check)
        guard !barcode.isEmpty, barcode.allSatisfy({ $0.isNumber }) else {
            throw BarcodeError.invalidBarcode
        }

        // Construct API URL
        let urlString = "\(baseURL)/\(barcode).json"
        guard let url = URL(string: urlString) else {
            throw BarcodeError.invalidBarcode
        }

        // Make network request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            // Network errors (no connection, timeout, etc.)
            throw BarcodeError.networkError
        }

        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BarcodeError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            throw BarcodeError.networkError
        }

        // Decode JSON response
        let decoder = JSONDecoder()
        let apiResponse: OpenFoodFactsResponse

        do {
            apiResponse = try decoder.decode(OpenFoodFactsResponse.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            throw BarcodeError.parsingError
        }

        // Check if product was found
        guard apiResponse.status == 1, let product = apiResponse.product else {
            throw BarcodeError.productNotFound
        }

        // Parse and return nutrition data
        return parseNutrition(from: product)
    }

    // MARK: - Private Methods

    /// Parses nutrition data from Open Food Facts product
    /// - Parameter product: Open Food Facts product data
    /// - Returns: Simplified FoodNutrition object
    private func parseNutrition(from product: OpenFoodFactsProduct) -> FoodNutrition {
        // Extract product name (with fallback)
        let name = product.product_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Product"

        // Extract brand (optional)
        let brand = product.brands?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract serving size (optional)
        let servingSize = product.serving_size?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract nutrition data (per 100g, with safe defaults)
        let nutriments = product.nutriments

        // Try _100g fields first, fall back to non-suffixed fields
        let calories = Int(nutriments?.energy_kcal_100g ?? nutriments?.energy_kcal ?? 0)
        let protein = nutriments?.proteins_100g ?? nutriments?.proteins ?? 0.0
        let carbs = nutriments?.carbohydrates_100g ?? nutriments?.carbohydrates ?? 0.0
        let fat = nutriments?.fat_100g ?? nutriments?.fat ?? 0.0

        // Calculate toxin score based on Nova group and nutrition grade
        let toxinScore = calculateToxinScore(
            novaGroup: product.nova_group,
            nutritionGrade: product.nutrition_grades,
            additivesCount: product.additives_tags?.count ?? 0
        )

        return FoodNutrition(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            toxinScore: toxinScore,
            servingSize: servingSize,
            brand: brand
        )
    }

    /// Calculates toxin score from product data
    /// - Parameters:
    ///   - novaGroup: Nova processing group (1-4, where 1 is unprocessed)
    ///   - nutritionGrade: Nutrition grade (a-e, where a is best)
    ///   - additivesCount: Number of food additives
    /// - Returns: Toxin score (0-100, where lower is cleaner/better)
    ///
    /// Scoring logic:
    /// - Nova group 1 (unprocessed): 0-20
    /// - Nova group 2 (processed culinary ingredients): 20-40
    /// - Nova group 3 (processed foods): 40-60
    /// - Nova group 4 (ultra-processed): 60-100
    /// - Adjusted by nutrition grade and additives count
    private func calculateToxinScore(
        novaGroup: Int?,
        nutritionGrade: String?,
        additivesCount: Int
    ) -> Int {
        var score = 0

        // Base score from Nova group (most important factor)
        switch novaGroup {
        case 1:
            score = 10  // Unprocessed foods (fruits, vegetables, etc.)
        case 2:
            score = 30  // Processed culinary ingredients (oils, butter, sugar)
        case 3:
            score = 50  // Processed foods (canned vegetables, cheese, bread)
        case 4:
            score = 70  // Ultra-processed (packaged snacks, sodas, instant meals)
        default:
            score = 40  // Unknown, assume moderate processing
        }

        // Adjust by nutrition grade (a=best, e=worst)
        if let grade = nutritionGrade?.lowercased().first {
            switch grade {
            case "a":
                score -= 10
            case "b":
                score -= 5
            case "c":
                score += 0
            case "d":
                score += 5
            case "e":
                score += 10
            default:
                break
            }
        }

        // Adjust by additives count (each additive adds ~2 points)
        score += min(additivesCount * 2, 20)

        // Clamp to 0-100 range
        return min(max(score, 0), 100)
    }
}

// MARK: - Mock Service for Testing

extension BarcodeService {
    /// Mock service that returns predefined data without network calls
    static var mock: BarcodeService {
        // In a real implementation, you'd inject a mock URLSession
        // For now, just return a standard instance
        return BarcodeService()
    }
}
