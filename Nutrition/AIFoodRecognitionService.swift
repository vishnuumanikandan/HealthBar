//
//  AIFoodRecognitionService.swift
//  HealthBar
//
//  Created by Claude on 5/28/26.
//

import Foundation

/// Sends a natural-language meal description (with optional photo) to the Claude API
/// and returns structured `[RecognizedFoodItem]`.
///
/// Responsibility boundary: request → decode → normalize/validate → return.
/// No UI state, persistence, retry logic, gamification, or `FoodEntry`/SwiftData/Firestore references.
@Observable
final class AIFoodRecognitionService {

    // MARK: - Private Wire Types

    /// Text-only request (string content).
    private struct APIRequestTextOnly: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    /// Multimodal request (content-block array).
    private struct APIRequestMultimodal: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: [ContentBlock]
        }

        enum ContentBlock: Encodable {
            case image(ImageBlock)
            case text(TextBlock)

            struct ImageBlock: Encodable {
                let type = "image"
                let source: Source
                struct Source: Encodable {
                    let type = "base64"
                    let media_type = "image/jpeg"
                    let data: String
                }
            }

            struct TextBlock: Encodable {
                let type = "text"
                let text: String
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .image(let block): try container.encode(block)
                case .text(let block): try container.encode(block)
                }
            }
        }
    }

    private struct APIResponse: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable { let type: String; let text: String }
    }

    private struct RecognitionResponse: Decodable {
        let items: [RawItem]?
        let clarification: String?
        let clarifications: [RawClarification]?

        struct RawItem: Decodable {
            let name: String?
            let quantity: String?
            let calories: Int?
            let protein: Double?
            let carbs: Double?
            let fat: Double?
            let confidence: String?
            let confidenceReason: String?
        }

        struct RawClarification: Decodable {
            let itemIndex: Int?
            let question: String?
            let importance: Double?
            let defaultOptionIndex: Int?
            let options: [RawOption]?

            struct RawOption: Decodable {
                let label: String?
                let dCalories: Int?
                let dProtein: Double?
                let dCarbs: Double?
                let dFat: Double?
            }
        }
    }

    // MARK: - Constants

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-4-6"
    private static let maxTokens = 1024
    private static let maxInputLength = 500
    private static let maxItems = 20
    private static let maxClarificationsTotal = 3
    private static let maxOptionsPerClarification = 4
    private static let minImportance = 0.15
    private static let maxDeltaCalories = 2000
    private static let maxDeltaMacro = 250.0

    private static let systemPromptBase = """
    Return ONLY a JSON object, no prose, no markdown fences. Schema:\
    {"items":[{"name":String,"quantity":String,"calories":Int,"protein":Number,"carbs":Number,"fat":Number,"confidence":"high"|"medium"|"low","confidenceReason":String|null}],\
    "clarification":String|null,\
    "clarifications":[{"itemIndex":Int,"question":String,"importance":Number,"defaultOptionIndex":Int,"options":[{"label":String,"dCalories":Int,"dProtein":Number,"dCarbs":Number,"dFat":Number}]}]}\
    Example: "2 scrambled eggs, toast" → {"items":[{"name":"Scrambled Eggs","quantity":"2 eggs","calories":182,"protein":12.6,"carbs":1.6,"fat":13.6,"confidence":"high","confidenceReason":null},{"name":"Toast","quantity":"1 slice","calories":79,"protein":2.7,"carbs":14.7,"fat":1.0,"confidence":"medium","confidenceReason":null}],"clarification":null,"clarifications":[]}\
    Set confidence:"low" when portion or identity is uncertain. If input is too vague to estimate any items, return {"items":[],"clarification":"<your question>","clarifications":[]}.\
    Emit clarifications ONLY for genuinely ambiguous items — unknown portion, likely-hidden added fats (oil/butter/dressing/sauce), or ambiguous size. High-confidence items get none.\
    Max 3 clarifications total; max 4 options each; options mutually exclusive; labels ≤14 chars.\
    Each option's deltas are relative to that item's returned baseline macros. Exactly one option per question is the default (defaultOptionIndex) with all-zero deltas.\
    Set importance per clarification by expected calorie swing: portion of staples, added oil/butter, dressing, sauce score high; herbs, lettuce, spices, garnishes score low.\
    Provide confidenceReason for every non-high-confidence item — the single biggest source of uncertainty.\
    Each option's deltas must stay within ±2000 calories and ±250g per macro.\
    Option deltas must be nutritionally plausible: calorie delta ≈ P·4 + C·4 + F·9. Do not return calorie-only deltas with zero macro change.
    """

    private static let imageReconciliationRule = """
     When both text and image are provided: prefer the text for food identity when they conflict; use the image to estimate portion/quantity and to include clearly visible foods the text omitted. Return ONLY the JSON object.
    """

    // MARK: - Dependencies

    private let session: URLSession

    // MARK: - Initialization

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Recognizes food items from a natural-language description and/or a photo.
    ///
    /// At least one of `description` (non-empty after trimming) or `imageData` must be provided.
    /// When both are present, a multimodal request is sent; when only text, a text-only request.
    /// `imageData` must be finalized JPEG bytes (caller's responsibility).
    ///
    /// - Parameters:
    ///   - description: The user's meal description (e.g. "two eggs, toast, black coffee"). May be nil or empty if image present.
    ///   - imageData: Optional JPEG image data. Must be < 1MB, longest edge ≤ 1568px.
    /// - Returns: An array of recognized food items with estimated macros.
    /// - Throws: `AIFoodRecognitionError` on failure.
    func recognize(description: String?, imageData: Data? = nil) async throws -> [RecognizedFoodItem] {
        // Validate API key
        let key = APIConfig.claudeAPIKey
        guard !key.isEmpty else {
            throw AIFoodRecognitionError.missingAPIKey
        }

        // Validate at least one usable input
        let trimmed = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty
        let hasImage = imageData != nil

        guard hasText || hasImage else {
            throw AIFoodRecognitionError.noFoodFound
        }

        // Truncate text to max length
        let input = String(trimmed.prefix(Self.maxInputLength))

        print("[AIFoodRecognition] Request started — text: \(hasText), image: \(hasImage)\(hasImage ? ", imageBytes: \(imageData!.count)" : "")")

        // Build request body
        let bodyData: Data

        if let imageData = imageData {
            // Multimodal request: image + text content blocks
            let systemPrompt = Self.systemPromptBase + Self.imageReconciliationRule

            let textContent = hasText ? input : "Identify the foods in this image and estimate their nutrition."

            let contentBlocks: [APIRequestMultimodal.ContentBlock] = [
                .image(.init(source: .init(data: imageData.base64EncodedString()))),
                .text(.init(text: textContent))
            ]

            let requestBody = APIRequestMultimodal(
                model: Self.model,
                max_tokens: Self.maxTokens,
                system: systemPrompt,
                messages: [.init(role: "user", content: contentBlocks)]
            )

            guard let encoded = try? JSONEncoder().encode(requestBody) else {
                throw AIFoodRecognitionError.decodingFailed
            }
            bodyData = encoded
        } else {
            // Text-only request (Feature 1 path, unchanged)
            let requestBody = APIRequestTextOnly(
                model: Self.model,
                max_tokens: Self.maxTokens,
                system: Self.systemPromptBase,
                messages: [.init(role: "user", content: input)]
            )

            guard let encoded = try? JSONEncoder().encode(requestBody) else {
                throw AIFoodRecognitionError.decodingFailed
            }
            bodyData = encoded
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
        var items = normalizeItems(recognitionResponse.items ?? [])

        if items.isEmpty {
            if let clarification = recognitionResponse.clarification, !clarification.isEmpty {
                print("[AIFoodRecognition] Needs clarification: \(clarification)")
                throw AIFoodRecognitionError.needsClarification(clarification)
            }
            print("[AIFoodRecognition] Empty recognition result")
            throw AIFoodRecognitionError.noFoodFound
        }

        // Parse and attach clarifications
        if let rawClarifications = recognitionResponse.clarifications, !rawClarifications.isEmpty {
            attachClarifications(rawClarifications, to: &items)
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

            // Parse confidenceReason
            var reason: String? = nil
            if let rawReason = raw.confidenceReason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawReason.isEmpty {
                reason = String(rawReason.prefix(40))
            }

            results.append(RecognizedFoodItem(
                id: UUID(),
                name: clampedName,
                quantityText: quantity,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                confidence: confidence,
                baselineCalories: calories,
                baselineProtein: protein,
                baselineCarbs: carbs,
                baselineFat: fat,
                confidenceReason: reason
            ))
        }

        return results
    }

    // MARK: - Clarification Parsing

    private func attachClarifications(
        _ rawClarifications: [RecognitionResponse.RawClarification],
        to items: inout [RecognizedFoodItem]
    ) {
        var allParsed: [(clarification: FoodClarification, itemIndex: Int)] = []

        for raw in rawClarifications {
            guard let itemIndex = raw.itemIndex,
                  itemIndex >= 0, itemIndex < items.count else {
                print("[AIFoodRecognition] Dropping clarification with out-of-range itemIndex: \(raw.itemIndex ?? -1)")
                continue
            }

            guard let question = raw.question?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !question.isEmpty else { continue }

            guard let rawOptions = raw.options, !rawOptions.isEmpty else { continue }

            let importance = clamp(raw.importance ?? 0, 0...1)
            let defaultIdx = raw.defaultOptionIndex ?? -1

            // Build options, dropping invalid ones
            var options: [FoodClarificationOption] = []
            for rawOpt in rawOptions.prefix(Self.maxOptionsPerClarification) {
                guard let label = rawOpt.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !label.isEmpty else { continue }

                let dCal = rawOpt.dCalories ?? 0
                let dP = rawOpt.dProtein ?? 0
                let dC = rawOpt.dCarbs ?? 0
                let dF = rawOpt.dFat ?? 0

                // Drop options exceeding delta caps
                if abs(dCal) > Self.maxDeltaCalories ||
                   abs(dP) > Self.maxDeltaMacro ||
                   abs(dC) > Self.maxDeltaMacro ||
                   abs(dF) > Self.maxDeltaMacro {
                    print("[AIFoodRecognition] Dropping option '\(label)' — delta exceeds caps (dCal=\(dCal), dP=\(dP), dC=\(dC), dF=\(dF))")
                    continue
                }

                // Drop malformed non-numeric deltas (already handled by Decodable, but guard)
                options.append(FoodClarificationOption(
                    id: UUID(),
                    label: String(label.prefix(14)),
                    deltaCalories: dCal,
                    deltaProtein: dP,
                    deltaCarbs: dC,
                    deltaFat: dF
                ))
            }

            // Resolve selectedOptionID before any dropping
            var selectedID: UUID
            if defaultIdx >= 0, defaultIdx < options.count {
                selectedID = options[defaultIdx].id
            } else if let zeroOption = options.first(where: {
                $0.deltaCalories == 0 && $0.deltaProtein == 0 && $0.deltaCarbs == 0 && $0.deltaFat == 0
            }) {
                selectedID = zeroOption.id
            } else if let first = options.first {
                selectedID = first.id
            } else {
                continue
            }

            // Must have at least 2 options
            guard options.count >= 2 else {
                print("[AIFoodRecognition] Dropping clarification '\(question)' — fewer than 2 valid options")
                continue
            }

            // If the selected option was dropped, re-resolve
            if !options.contains(where: { $0.id == selectedID }) {
                selectedID = options.first(where: {
                    $0.deltaCalories == 0 && $0.deltaProtein == 0 && $0.deltaCarbs == 0 && $0.deltaFat == 0
                })?.id ?? options[0].id
            }

            let itemId = items[itemIndex].id

            allParsed.append((
                clarification: FoodClarification(
                    id: UUID(),
                    affectsItemId: itemId,
                    question: question,
                    importance: importance,
                    options: options,
                    selectedOptionID: selectedID
                ),
                itemIndex: itemIndex
            ))
        }

        // Sort by importance descending
        allParsed.sort { $0.clarification.importance > $1.clarification.importance }

        // Cap at maxClarificationsTotal
        if allParsed.count > Self.maxClarificationsTotal {
            allParsed = Array(allParsed.prefix(Self.maxClarificationsTotal))
        }

        // Drop low-importance clarifications
        let beforeDrop = allParsed.count
        allParsed.removeAll { $0.clarification.importance < Self.minImportance }
        let dropped = beforeDrop - allParsed.count
        if dropped > 0 {
            print("[AIFoodRecognition] Dropped \(dropped) clarification(s) below importance threshold (\(Self.minImportance))")
        }

        // Attach to items
        for parsed in allParsed {
            items[parsed.itemIndex].clarifications.append(parsed.clarification)
        }

        // Sort each item's clarifications by importance descending
        for i in items.indices {
            items[i].clarifications.sort { $0.importance > $1.importance }
        }

        let totalAttached = allParsed.count
        print("[AIFoodRecognition] Attached \(totalAttached) clarification(s)")
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
