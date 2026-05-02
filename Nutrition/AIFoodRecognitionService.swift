//
//  AIFoodRecognitionService.swift
//  HealthBar
//
//  Created by Claude on 5/28/26.
//

import Foundation

/// Sends a natural-language meal description to the Claude API and returns
/// structured `[RecognizedFoodItem]`.
///
/// Responsibility boundary: request → decode → normalize/validate → return.
/// No UI state, persistence, retry logic, gamification, or `FoodEntry`/SwiftData/Firestore references.
@Observable
final class AIFoodRecognitionService {

    // MARK: - Private Wire Types

    private struct APIRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct APIResponse: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable { let type: String; let text: String }
    }

    private struct RecognitionResponse: Decodable {
        let items: [RawItem]?
        let clarification: String?

        struct RawItem: Decodable {
            let name: String?
            let quantity: String?
            let calories: Int?
            let protein: Double?
            let carbs: Double?
            let fat: Double?
            let confidence: String?
        }
    }

    // MARK: - Constants

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-4-20250514"
    private static let maxTokens = 1024
    private static let maxInputLength = 500
    private static let maxItems = 20

    private static let systemPrompt = """
    Return ONLY a JSON object, no prose, no markdown fences. Schema:\
    {"items":[{"name":String,"quantity":String,"calories":Int,"protein":Number,"carbs":Number,"fat":Number,"confidence":"high"|"medium"|"low"}],"clarification":String|null}\
    Example: "2 scrambled eggs, toast" → {"items":[{"name":"Scrambled Eggs","quantity":"2 eggs","calories":182,"protein":12.6,"carbs":1.6,"fat":13.6,"confidence":"high"},{"name":"Toast","quantity":"1 slice","calories":79,"protein":2.7,"carbs":14.7,"fat":1.0,"confidence":"medium"}],"clarification":null}\
    Set confidence:"low" when portion or identity is uncertain. If input is too vague to estimate any items, return {"items":[],"clarification":"<your question>"}.
    """

    // MARK: - Dependencies

    private let session: URLSession

    // MARK: - Initialization

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Recognizes food items from a natural-language description.
    ///
    /// - Parameter description: The user's meal description (e.g. "two eggs, toast, black coffee").
    /// - Returns: An array of recognized food items with estimated macros.
    /// - Throws: `AIFoodRecognitionError` on failure.
    func recognize(description: String) async throws -> [RecognizedFoodItem] {
        // Validate API key
        let key = APIConfig.claudeAPIKey
        guard !key.isEmpty else {
            throw AIFoodRecognitionError.missingAPIKey
        }

        // Validate input
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIFoodRecognitionError.noFoodFound
        }

        // Truncate to max length
        let input = String(trimmed.prefix(Self.maxInputLength))

        print("[AIFoodRecognition] Request started for: \(input)")

        // Build request
        let requestBody = APIRequest(
            model: Self.model,
            max_tokens: Self.maxTokens,
            system: Self.systemPrompt,
            messages: [APIRequest.Message(role: "user", content: input)]
        )

        guard let bodyData = try? JSONEncoder().encode(requestBody) else {
            throw AIFoodRecognitionError.decodingFailed
        }

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        // Execute network request
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            print("[AIFoodRecognition] Request cancelled")
            throw CancellationError()
        } catch {
            print("[AIFoodRecognition] Network error: \(error)")
            throw AIFoodRecognitionError.network(error)
        }

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIFoodRecognitionError.network(URLError(.badServerResponse))
        }
        guard httpResponse.statusCode == 200 else {
            print("[AIFoodRecognition] API status error: \(httpResponse.statusCode)")
            throw AIFoodRecognitionError.apiError(status: httpResponse.statusCode)
        }

        // Decode API envelope
        let apiResponse: APIResponse
        do {
            apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            print("[AIFoodRecognition] Envelope decode failed: \(error)")
            throw AIFoodRecognitionError.decodingFailed
        }

        // Extract text block
        guard let textBlock = apiResponse.content.first(where: { $0.type == "text" }) else {
            print("[AIFoodRecognition] No text block in response")
            throw AIFoodRecognitionError.decodingFailed
        }

        // Parse the JSON content (strip fences, extract braces)
        let recognitionResponse = try parseRecognitionJSON(textBlock.text)

        // Convert and validate items
        let items = normalizeItems(recognitionResponse.items ?? [])

        if items.isEmpty {
            if let clarification = recognitionResponse.clarification, !clarification.isEmpty {
                print("[AIFoodRecognition] Needs clarification: \(clarification)")
                throw AIFoodRecognitionError.needsClarification(clarification)
            }
            print("[AIFoodRecognition] Empty recognition result")
            throw AIFoodRecognitionError.noFoodFound
        }

        print("[AIFoodRecognition] Recognized \(items.count) item(s)")
        return items
    }

    // MARK: - JSON Parsing

    private func parseRecognitionJSON(_ rawText: String) throws -> RecognitionResponse {
        // Strip markdown fences if present
        var text = rawText
        text = text.replacingOccurrences(of: "```json", with: "")
        text = text.replacingOccurrences(of: "```", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract from first { to last }
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}") else {
            print("[AIFoodRecognition] Parse failure: no JSON braces found")
            throw AIFoodRecognitionError.decodingFailed
        }

        let jsonString = String(text[firstBrace...lastBrace])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AIFoodRecognitionError.decodingFailed
        }

        do {
            return try JSONDecoder().decode(RecognitionResponse.self, from: jsonData)
        } catch {
            print("[AIFoodRecognition] JSON decode failed: \(error)")
            throw AIFoodRecognitionError.decodingFailed
        }
    }

    // MARK: - Normalization & Validation

    private func normalizeItems(_ rawItems: [RecognitionResponse.RawItem]) -> [RecognizedFoodItem] {
        var results: [RecognizedFoodItem] = []

        for raw in rawItems.prefix(Self.maxItems) {
            // Name: trimmed, non-empty, ≤60 chars
            let name = (raw.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                print("[AIFoodRecognition] Dropping item with empty name")
                continue
            }
            let clampedName = String(name.prefix(60))

            let quantity = (raw.quantity ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // Clamp macros
            var calories = clamp(raw.calories ?? 0, 0...5000)
            var protein = clamp(raw.protein ?? 0, 0...1000)
            var carbs = clamp(raw.carbs ?? 0, 0...1000)
            var fat = clamp(raw.fat ?? 0, 0...1000)

            // Parse confidence
            var confidence: RecognizedFoodItem.Confidence
            switch raw.confidence?.lowercased() {
            case "high": confidence = .high
            case "low": confidence = .low
            default: confidence = .medium
            }

            // Atwater cross-check
            let derived = Int(round(protein * 4 + carbs * 4 + fat * 9))
            if calories == 0 && derived > 0 {
                print("[AIFoodRecognition] Calories reconciled from 0 → \(derived) for '\(clampedName)'")
                calories = derived
            } else if derived > 0 {
                let deviation = abs(Double(calories) - Double(derived)) / Double(max(derived, 1))
                if deviation > 0.35 {
                    print("[AIFoodRecognition] Atwater mismatch for '\(clampedName)': reported=\(calories), derived=\(derived), deviation=\(String(format: "%.0f%%", deviation * 100))")
                    calories = derived
                    confidence = .low
                }
            }

            // Re-clamp after reconciliation
            calories = clamp(calories, 0...5000)

            results.append(RecognizedFoodItem(
                id: UUID(),
                name: clampedName,
                quantityText: quantity,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                confidence: confidence
            ))
        }

        return results
    }

    // MARK: - Helpers

    private func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Error Type

enum AIFoodRecognitionError: Error {
    case missingAPIKey
    case network(Error)
    case apiError(status: Int)
    case decodingFailed
    case noFoodFound
    case needsClarification(String)

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            return "AI logging isn't set up yet. You can still add food manually."
        case .network:
            return "Couldn't reach the server. Check your connection and try again."
        case .apiError(let status):
            return "Something went wrong (error \(status)). Try again or add food manually."
        case .decodingFailed:
            return "Couldn't understand the response. Try rephrasing or add food manually."
        case .noFoodFound:
            return "No foods recognized. Try being more specific about what you ate."
        case .needsClarification(let question):
            return question
        }
    }
}
