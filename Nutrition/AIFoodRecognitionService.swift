//
//  AIFoodRecognitionService.swift
//  HealthBar
//
//  Created by Claude on 5/28/26.
//

import FirebaseFunctions
import Foundation

// MARK: - Food Category

/// The user-declared kind of item being logged (AILOG-1a). Drives the per-category
/// estimation guidance injected into the recognition prompt and — in AILOG-1b — the
/// input sheet's category chips and per-field labels.
///
/// `CaseIterable` order IS the AILOG-1b chip order. Raw values are pinned wire/prompt
/// format: they appear verbatim in prompt text and in 1b's UI state, so a case name may
/// be renamed but a raw value must NEVER change. `meal` is the default.
enum FoodCategory: String, CaseIterable, Identifiable {
    case meal = "meal"
    case snack = "snack"
    case drink = "drink"
    case fruit = "fruit"
    case veggie = "veggie"
    case sweet = "sweet"

    var id: String { rawValue }

    /// All-caps label for the category chip (AILOG-1b).
    var displayName: String {
        switch self {
        case .meal:   return "MEAL"
        case .snack:  return "SNACK"
        case .drink:  return "DRINK"
        case .fruit:  return "FRUIT"
        case .veggie: return "VEGGIE"
        case .sweet:  return "SWEET"
        }
    }

    /// The three input-field labels AILOG-1b renders (field 1 = item, 2 = amount,
    /// 3 = extras).
    struct FieldLabels {
        let item: String
        let amount: String
        let extras: String
    }

    /// The single source table of per-field labels — AILOG-1b reads this and never
    /// redefines these strings.
    var fieldLabels: FieldLabels {
        switch self {
        case .meal:
            return FieldLabels(item: "What did you eat?", amount: "How much did you eat?", extras: "Seasonings, sauces, or oil?")
        case .snack:
            return FieldLabels(item: "What did you eat?", amount: "How much did you eat?", extras: "Brand or toppings?")
        case .drink:
            return FieldLabels(item: "What did you drink?", amount: "What size?", extras: "Milk, sweeteners, or mix-ins?")
        case .fruit:
            return FieldLabels(item: "What did you eat?", amount: "How much did you eat?", extras: "Anything on it?")
        case .veggie:
            return FieldLabels(item: "What did you eat?", amount: "How much did you eat?", extras: "Anything on it?")
        case .sweet:
            return FieldLabels(item: "What did you eat?", amount: "How much did you eat?", extras: "Brand or toppings?")
        }
    }

    // AIPROXY-1b: `guidance` was deleted here. Per-category estimation guidance is
    // prompt text, and prompts moved server-side with the bundled key — it now lives
    // in `functions/src/prompts.ts` (`CATEGORY_GUIDANCE`), which is the only copy.
    // A second copy here would be dead text that a future reader could edit expecting
    // a behavior change that can no longer happen.
}

// MARK: - Public Types

/// One recognition round's output.
struct RecognitionResult {
    let items: [RecognizedFoodItem]
}

/// Sends a natural-language meal description (with optional photo) to the Claude API
/// and returns structured `[RecognizedFoodItem]`.
///
/// Responsibility boundary: request → decode → normalize/validate → return.
/// No UI state, persistence, retry logic, gamification, or `FoodEntry`/SwiftData/Firestore references.
@Observable
final class AIFoodRecognitionService {

    // MARK: - Private Wire Types

    // AIPROXY-1b: the Anthropic request/response types are gone. The client no longer
    // knows about models, token caps, system prompts, or content blocks — the `aiProxy`
    // callable owns all of it and returns the model's text verbatim. What survives here
    // is the parsing of THAT text, which was always client-side.

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
            let toxinScore: Int?
            let fiber: Double?
            let sugar: Double?
            let sodium: Double?
            let saturatedFat: Double?
            let cholesterol: Double?
            let potassium: Double?
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

    /// The deployed `aiProxy` region. MUST match `FUNCTION_REGION` in
    /// `functions/src/index.ts` — a callable built for the wrong region resolves a URL
    /// that does not exist and fails as a transport error. Every callable construction
    /// in this file reads this symbol; never inline the string.
    private static let aiProxyRegion = "us-central1"

    /// The callable's deployed name.
    private static let callableName = "aiProxy"

    /// The `details.code` the function attaches to its daily-limit `resource-exhausted`
    /// error. Matched as a field, never by parsing the localized message.
    private static let aiDailyLimitCode = "AI_DAILY_LIMIT"

    /// Shown when the server's per-day credit ceiling is hit. Declared ONCE — every
    /// surface that shows this state reads this symbol.
    ///
    /// Deliberately promises no reset time: the server's day boundary is UTC, so a
    /// "resets at midnight" promise would be wrong for most of the world.
    static let aiDailyLimitMessage = "You've used all your QuickLog credits for today. They refresh daily."

    private static let maxInputLength = 500
    private static let maxItems = 20
    private static let maxClarificationsTotal = 3
    private static let maxOptionsPerClarification = 4
    private static let minImportance = 0.15
    private static let maxDeltaCalories = 2000
    private static let maxDeltaMacro = 250.0
    private static let fallbackToxinScore = 30
    private static let maxMicroGrams = 500.0         // fiber, sugar, saturatedFat
    private static let maxMicroMilligrams = 10_000.0 // sodium, cholesterol, potassium

    // AIPROXY-1b: every prompt constant that used to sit here — `imageOnlyPrompt`,
    // `systemPromptGeneral`, `systemPromptSchemaOnward`, `imageReconciliationRule` —
    // moved to `functions/src/prompts.ts`. Prompt text is only enforceable where the
    // API key lives, so it belongs on the server with it.

    // MARK: - Initialization

    init() {}

    /// The callable handle. `Functions.functions(region:)` memoizes per (app, region),
    /// so building it per request is cheap and avoids holding a reference that would
    /// outlive a Firebase reconfiguration.
    private func aiProxyCallable() -> HTTPSCallable {
        Functions.functions(region: Self.aiProxyRegion).httpsCallable(Self.callableName)
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
    ///   - category: Optional user-declared food category (AILOG-1a). When present, adds that
    ///     category's estimation guidance to the prompt plus a `Category:` input line.
    ///   - amount: Optional user-stated amount/size (AILOG-1a). Rendered as the `Amount:` input line.
    ///   - extras: Optional user-stated seasonings/mix-ins/toppings (AILOG-1a). Rendered as the `Extras:` input line.
    /// - Returns: The recognized items.
    /// - Throws: `AIFoodRecognitionError` on failure.
    func recognize(
        description: String?,
        imageData: Data? = nil,
        category: FoodCategory? = nil,
        amount: String? = nil,
        extras: String? = nil
    ) async throws -> RecognitionResult {
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

        // Build the callable payload. Maps 1:1 onto the `foodRecognition` request:
        // absent fields are OMITTED, never sent as null/empty, mirroring the server's
        // own presence checks. Prompt assembly happens server-side from these fields.
        var payload: [String: Any] = ["kind": "foodRecognition"]
        if hasText {
            payload["text"] = input
        }
        if let imageData {
            // The describe-meal pipeline compresses to JPEG exclusively before it
            // reaches here, so the media type is a constant rather than a sniffed value.
            payload["imageBase64"] = imageData.base64EncodedString()
            payload["mediaType"] = "image/jpeg"
        }
        if let category {
            payload["category"] = category.rawValue
        }
        let trimmedAmount = (amount ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAmount.isEmpty {
            payload["amount"] = trimmedAmount
        }
        let trimmedExtras = (extras ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExtras.isEmpty {
            payload["extras"] = trimmedExtras
        }

        // The proxy returns the model's text verbatim — the same string the raw API
        // path used to dig out of a content block.
        let modelText = try await callAIProxy(payload: payload)

        // Parse the JSON content (strip fences, extract braces)
        let recognitionResponse = try parseRecognitionJSON(modelText)

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
        return RecognitionResult(items: items)
    }

    // MARK: - Onboarding Goals

    /// Asks the proxy for personalized calorie/macro targets and a coaching tip.
    ///
    /// Returns the model's raw text reply, or `nil` on ANY failure — including the daily
    /// limit. Onboarding has an established local-math fallback and deliberately surfaces
    /// no error UI, so every failure collapses to the same silent `nil` the caller
    /// already handles.
    ///
    /// - Parameter profileSummaryText: The serialized profile summary, built by the caller.
    func generateOnboardingGoals(profileSummaryText: String) async -> String? {
        let trimmed = profileSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            return try await callAIProxy(payload: ["kind": "onboardingGoals", "text": trimmed])
        } catch {
            print("[AIFoodRecognition] onboardingGoals failed: \(error) — falling back to local math")
            return nil
        }
    }

    // MARK: - Callable Transport

    /// Invokes `aiProxy` and returns the model text from its `{ text, requestsRemainingToday }`
    /// response.
    ///
    /// `requestsRemainingToday` is deliberately ignored — no surface displays remaining
    /// credits yet, and reading it here would invite a UI that AIPROXY-1b does not build.
    private func callAIProxy(payload: [String: Any]) async throws -> String {
        do {
            let result = try await aiProxyCallable().call(payload)
            guard let dict = result.data as? [String: Any],
                  let text = dict["text"] as? String else {
                print("[AIFoodRecognition] Malformed aiProxy response envelope")
                throw AIFoodRecognitionError.decodingFailed
            }
            return text
        } catch let error as AIFoodRecognitionError {
            throw error
        } catch is CancellationError {
            print("[AIFoodRecognition] Request cancelled")
            throw CancellationError()
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    /// The ONE place a callable error becomes an `AIFoodRecognitionError`.
    ///
    /// Matching is on the error CODE and on `details.code` — never on message text.
    /// A localized description is presentation, not contract: it changes with locale and
    /// SDK version, so string-matching it would fail silently and unpredictably.
    private static func mapCallableError(_ error: Error) -> AIFoodRecognitionError {
        let ns = error as NSError

        // Anything not from the Functions SDK is transport or decoding.
        guard ns.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: ns.code) else {
            print("[AIFoodRecognition] Non-Functions error from aiProxy: \(error)")
            return .requestFailed
        }

        switch code {
        case .resourceExhausted:
            // ONLY the function's own daily-limit marker earns the credits copy. A future
            // server-side throttle also arrives as resource-exhausted, and must not
            // masquerade as "you used all your credits".
            let details = ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            if let detailCode = details?["code"] as? String, detailCode == aiDailyLimitCode {
                print("[AIFoodRecognition] Daily AI limit reached")
                return .dailyLimitReached
            }
            print("[AIFoodRecognition] resource-exhausted WITHOUT \(aiDailyLimitCode) — treating as a generic failure")
            return .requestFailed

        case .unauthenticated:
            print("[AIFoodRecognition] aiProxy rejected an unauthenticated call")
            return .notSignedIn

        case .invalidArgument:
            // The client validates the same preconditions the server does, so a rejection
            // here means the two contracts have drifted — a defect to fix, not a user state.
            print("[AIFoodRecognition] CONTRACT DRIFT: aiProxy returned invalid-argument — client and server request contracts disagree: \(ns.localizedDescription)")
            return .requestFailed

        default:
            print("[AIFoodRecognition] aiProxy failed (\(code)): \(ns.localizedDescription)")
            return .requestFailed
        }
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

            // Toxin score: missing → fallback; present → clamped into 0...100 (never swapped for fallback).
            let toxin = clamp(raw.toxinScore ?? Self.fallbackToxinScore, 0...100)

            // Advanced micros — range clamps (nil-preserving; negatives clamp to 0, not nil).
            var fiber = raw.fiber.map { clamp($0, 0...Self.maxMicroGrams) }
            var sugar = raw.sugar.map { clamp($0, 0...Self.maxMicroGrams) }
            let sodium = raw.sodium.map { clamp($0, 0...Self.maxMicroMilligrams) }
            var saturatedFat = raw.saturatedFat.map { clamp($0, 0...Self.maxMicroGrams) }
            let cholesterol = raw.cholesterol.map { clamp($0, 0...Self.maxMicroMilligrams) }
            let potassium = raw.potassium.map { clamp($0, 0...Self.maxMicroMilligrams) }

            // Consistency clamps (after range clamps, using final macros): a component can't exceed its parent.
            if let sf = saturatedFat, sf > fat {
                print("[AIFoodRecognition] Clamped saturatedFat for '\(clampedName)': \(sf) → \(fat)")
                saturatedFat = fat
            }
            if let sg = sugar, sg > carbs {
                print("[AIFoodRecognition] Clamped sugar for '\(clampedName)': \(sg) → \(carbs)")
                sugar = carbs
            }
            if let fb = fiber, fb > carbs {
                print("[AIFoodRecognition] Clamped fiber for '\(clampedName)': \(fb) → \(carbs)")
                fiber = carbs
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
                toxinScore: toxin,
                fiber: fiber,
                sugar: sugar,
                sodium: sodium,
                saturatedFat: saturatedFat,
                cholesterol: cholesterol,
                potassium: potassium,
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

/// AIPROXY-1b removed `missingAPIKey`, `network(Error)`, and `apiError(status:)`. All
/// three were produced ONLY by the deleted bundled-key/URLSession path: there is no
/// client API key to be missing, and callable transport and HTTP status now arrive as
/// Functions error codes that `mapCallableError` folds into `requestFailed`. They were
/// unreachable after the migration, and `missingAPIKey`'s copy ("AI logging isn't set up
/// yet") would have been actively misleading.
enum AIFoodRecognitionError: Error {
    case dailyLimitReached
    case notSignedIn
    case requestFailed
    case decodingFailed
    case noFoodFound
    case needsClarification(String)

    var userMessage: String {
        switch self {
        case .dailyLimitReached:
            return AIFoodRecognitionService.aiDailyLimitMessage
        case .notSignedIn:
            // Guest gates make this unreachable in practice; it must never read as the
            // credits message, which would tell a signed-out user to wait for a reset
            // that will never help them.
            return "Couldn't verify your account. Sign in and try again, or add food manually."
        case .requestFailed:
            // Preserves the pre-migration network copy verbatim.
            return "Couldn't reach the server. Check your connection and try again."
        case .decodingFailed:
            return "Couldn't understand the response. Try rephrasing or add food manually."
        case .noFoodFound:
            return "No foods recognized. Try being more specific about what you ate."
        case .needsClarification(let question):
            return question
        }
    }
}
