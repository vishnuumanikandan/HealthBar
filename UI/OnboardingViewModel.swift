//
//  OnboardingViewModel.swift
//  HealthBar
//
//  Created by Claude on 3/31/26.
//

import Foundation

/// ViewModel for the AI Goal Questionnaire onboarding flow.
///
/// Manages 14-step state, Mifflin-St Jeor calculations, Claude API call,
/// draft persistence (UserDefaults), and userId-change safety.
@Observable
@MainActor
final class OnboardingViewModel {

    // MARK: - Step Navigation

    var currentStep: Int = 0
    let totalSteps: Int = 14   // steps 0–13

    // MARK: - Step 1: Sex

    var sex: String = "male"   // "male" | "female"

    // MARK: - Step 2: Age

    var age: Int = 25

    // MARK: - Step 3: Weight & Height (inputs in user's chosen unit)

    var useImperial: Bool = true

    /// Weight input string. In lbs when useImperial, in kg when metric.
    var weightInput: String = ""

    /// Height feet part (imperial only).
    var heightFtInput: String = ""

    /// Height inches part (imperial only).
    var heightInInput: String = ""

    /// Height cm (metric only).
    var heightCmInput: String = ""

    // MARK: - Step 4: Goal Weight

    /// Goal weight input string. In lbs when useImperial, in kg when metric.
    var goalWeightInput: String = ""

    // MARK: - Step 5: Weekly Pace

    var weeklyPaceLbs: Double = 1.0

    // MARK: - Step 6: Activity Level

    /// "sedentary", "light", "moderate", "active", "very_active"
    var activityLevel: String = "moderate"

    // MARK: - Step 7: Diet Style

    /// "standard", "keto", "vegan", "vegetarian", "paleo", "mediterranean"
    var dietStyle: String = "standard"

    // MARK: - Step 8: Meals Per Day

    var mealsPerDay: Int = 3

    // MARK: - Step 9: Allergies

    /// Subset of ["gluten", "dairy", "nuts", "soy", "eggs"]. Empty means none.
    var allergies: [String] = []

    // MARK: - Step 10: Sleep Quality

    /// "poor", "fair", "good"
    var sleepQuality: String = "fair"

    // MARK: - Step 11: Stress Level

    /// "low", "moderate", "high"
    var stressLevel: String = "moderate"

    // MARK: - Step 12: Calculating (auto-advance)

    var isProcessing: Bool = false

    // MARK: - Step 13: Results

    var calculatedCalories: Int = 0
    var calculatedProtein: Int = 0
    var calculatedCarbs: Int = 0
    var calculatedFat: Int = 0
    var aiTip: String = ""
    var saveError: String? = nil
    var isSaving: Bool = false

    // MARK: - Edit Mode

    /// True when opened from "Edit Health Profile" (existingProfile was provided).
    /// Controls which features are unlocked: close button, step jumping, smart API skip.
    let isEditMode: Bool

    /// Snapshot of the profile at open time. Used to detect significant changes
    /// before deciding whether to spend an API credit on Claude.
    private let existingProfile: UserProfile?

    // MARK: - Dependencies

    private let coordinator: AppCoordinator
    let authService: any AuthService

    /// Tracks the last known userId to detect account switches.
    private var lastKnownUserId: String?

    // MARK: - Init

    init(
        coordinator: AppCoordinator,
        authService: any AuthService,
        existingProfile: UserProfile? = nil
    ) {
        self.coordinator = coordinator
        self.authService = authService
        self.lastKnownUserId = authService.currentUserEmail
        self.isEditMode = existingProfile != nil
        self.existingProfile = existingProfile

        if let profile = existingProfile {
            populateFromProfile(profile)
        } else if let userId = authService.currentUserEmail {
            loadDraft(userId: userId)
        }
    }

    // MARK: - Navigation

    func nextStep() {
        checkForUserIdChange()
        guard currentStep < totalSteps - 1 else { return }
        guard canAdvance(from: currentStep) else { return }
        // Drafts are only used for new-account flows; edit mode uses the saved profile as truth.
        if !isEditMode, let userId = authService.currentUserEmail {
            saveDraft(userId: userId)
        }
        currentStep += 1
    }

    func previousStep() {
        guard currentStep > 1 else { return }   // Step 0 has its own CTA
        currentStep -= 1
    }

    /// Jump directly to a data step (1–11). Edit mode only — new-account users must step through.
    func jumpToStep(_ step: Int) {
        guard isEditMode, step >= 1, step <= 11 else { return }
        currentStep = step
    }

    /// Returns true if the user may advance past the given step.
    func canAdvance(from step: Int) -> Bool {
        switch step {
        case 0:  return true
        case 1:  return true   // sex always has a value
        case 2:  return age >= 13 && age <= 80
        case 3:  return computedWeightKg >= 30 && computedHeightCm >= 120
        case 4:  return computedGoalWeightKg > 0
        case 5:  return true   // pace always selected
        case 6:  return true   // activity always selected
        case 7:  return true   // diet always selected
        case 8:  return mealsPerDay >= 2 && mealsPerDay <= 5
        case 9:  return true   // allergies can be empty
        case 10: return true   // sleep always selected
        case 11: return true   // stress always selected
        default: return false
        }
    }

    // MARK: - Calculations

    /// Clamped weight in kg derived from current input and unit toggle.
    var computedWeightKg: Double {
        let raw: Double
        if useImperial {
            raw = (Double(weightInput) ?? 0) / 2.20462
        } else {
            raw = Double(weightInput) ?? 0
        }
        return max(30, min(300, raw))
    }

    /// Clamped height in cm derived from current inputs and unit toggle.
    var computedHeightCm: Double {
        let raw: Double
        if useImperial {
            let ft = Double(heightFtInput) ?? 0
            let inches = Double(heightInInput) ?? 0
            raw = (ft * 12 + inches) * 2.54
        } else {
            raw = Double(heightCmInput) ?? 0
        }
        return max(120, min(230, raw))
    }

    /// Clamped goal weight in kg derived from current input and unit toggle.
    var computedGoalWeightKg: Double {
        let raw: Double
        if useImperial {
            raw = (Double(goalWeightInput) ?? 0) / 2.20462
        } else {
            raw = Double(goalWeightInput) ?? 0
        }
        return max(20, raw)
    }

    /// Directional weight change label shown on the goal weight step.
    var weightDirectionLabel: String {
        let current = computedWeightKg
        let goal = computedGoalWeightKg
        guard current > 0 && goal > 0 else { return "" }
        let diffKg = current - goal
        let diffLbs = abs(diffKg * 2.20462)
        if useImperial {
            let display = String(format: "%.1f", abs(current * 2.20462 - goal * 2.20462))
            if diffKg > 0.5  { return "You want to lose \(display) lbs" }
            if diffKg < -0.5 { return "You want to gain \(display) lbs" }
        } else {
            let display = String(format: "%.1f", abs(diffKg))
            if diffKg > 0.5  { return "You want to lose \(display) kg" }
            if diffKg < -0.5 { return "You want to gain \(display) kg" }
        }
        _ = diffLbs
        return "You're at your goal weight"
    }

    // MARK: - BMR / TDEE / Macros

    private func calculateBMR() -> Double {
        let w = max(30, min(300, computedWeightKg))
        let h = max(120, min(230, computedHeightCm))
        let a = Double(max(13, min(80, age)))
        if sex == "male" {
            return 10 * w + 6.25 * h - 5 * a + 5
        } else {
            return 10 * w + 6.25 * h - 5 * a - 161
        }
    }

    private func calculateTDEE(bmr: Double) -> Double {
        let multipliers: [String: Double] = [
            "sedentary": 1.2,
            "light":     1.375,
            "moderate":  1.55,
            "active":    1.725,
            "very_active": 1.9
        ]
        return bmr * (multipliers[activityLevel] ?? 1.55)
    }

    private func calculateCalorieTarget(tdee: Double) -> Int {
        let deficit = min(weeklyPaceLbs * 500, 1000)
        return max(1200, Int(tdee - deficit))
    }

    private func macroGrams(calories: Int) -> (protein: Int, carbs: Int, fat: Int) {
        // Diet style → (protein%, carbs%, fat%)
        let splits: [String: (Double, Double, Double)] = [
            "standard":      (0.30, 0.40, 0.30),
            "keto":          (0.25, 0.05, 0.70),
            "vegan":         (0.20, 0.55, 0.25),
            "vegetarian":    (0.25, 0.50, 0.25),
            "paleo":         (0.35, 0.25, 0.40),
            "mediterranean": (0.25, 0.45, 0.30)
        ]
        let (pPct, cPct, fPct) = splits[dietStyle] ?? (0.30, 0.40, 0.30)
        let kcal = Double(calories)
        return (
            protein: max(1, Int(kcal * pPct / 4)),
            carbs:   max(1, Int(kcal * cPct / 4)),
            fat:     max(1, Int(kcal * fPct / 9))
        )
    }

    // MARK: - Claude API

    private struct ClaudeAPIRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct ClaudeAPIResponse: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable { let type: String; let text: String }
    }

    private struct ClaudeTargetResponse: Codable {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let tip: String
    }

    private func isValid(_ r: ClaudeTargetResponse) -> Bool {
        guard r.calories >= 1000 && r.calories <= 6000 else { return false }
        guard r.protein > 0 && r.carbs > 0 && r.fat > 0 else { return false }
        let macroKcal = r.protein * 4 + r.carbs * 4 + r.fat * 9
        let tolerance = Double(r.calories) * 0.10
        return abs(Double(macroKcal - r.calories)) <= tolerance
    }

    private func callClaudeAPI(
        localCalories: Int,
        localProtein: Int,
        localCarbs: Int,
        localFat: Int
    ) async -> ClaudeTargetResponse? {
        let key = APIConfig.claudeAPIKey
        guard !key.isEmpty else { return nil }

        let profileSummary: [String: Any] = [
            "sex": sex,
            "age": age,
            "weightKg": computedWeightKg,
            "heightCm": computedHeightCm,
            "goalWeightKg": computedGoalWeightKg,
            "weeklyPaceLbs": weeklyPaceLbs,
            "activityLevel": activityLevel,
            "dietStyle": dietStyle,
            "mealsPerDay": mealsPerDay,
            "allergies": allergies,
            "sleepQuality": sleepQuality,
            "stressLevel": stressLevel,
            "formulaCalories": localCalories,
            "formulaProtein": localProtein,
            "formulaCarbs": localCarbs,
            "formulaFat": localFat
        ]

        guard let profileJSON = try? JSONSerialization.data(withJSONObject: profileSummary),
              let profileString = String(data: profileJSON, encoding: .utf8) else {
            return nil
        }

        let systemPrompt = """
        You are a concise nutrition coach. Return ONLY a JSON object, no prose, no markdown fences.
        {"calories": Int, "protein": Int, "carbs": Int, "fat": Int, "tip": String}
        tip must be exactly 2 sentences, personalized to the user's profile.
        """

        let requestBody = ClaudeAPIRequest(
            model: "claude-sonnet-4-6",
            max_tokens: 256,
            system: systemPrompt,
            messages: [ClaudeAPIRequest.Message(role: "user", content: profileString)]
        )

        guard let bodyData = try? JSONEncoder().encode(requestBody) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[OnboardingVM] Claude API: missing HTTP response")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                print("[OnboardingVM] Claude API non-200 (\(httpResponse.statusCode)): \(String(body.prefix(200)))")
                return nil
            }

            let apiResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
            guard let textBlock = apiResponse.content.first(where: { $0.type == "text" }) else {
                print("[OnboardingVM] Claude API: no text block in response")
                return nil
            }

            // Extraction mirrors the recognition service (strip fences → slice braces →
            // decode). Fixes markdown-fenced / preamble replies that previously threw and
            // silently fell back to the generic coaching tip.
            return extractTargetResponse(from: textBlock.text)
        } catch {
            print("[OnboardingVM] Claude API error: \(error)")
            return nil
        }
    }

    /// Extracts and decodes the target JSON from Claude's raw text reply.
    ///
    /// Replicates `AIFoodRecognitionService.parseRecognitionJSON` (B2b): (1) strip
    /// ```json / ``` fences, (2) trim whitespace/newlines, (3) slice the first `{`
    /// through the last `}` — this step ALWAYS runs, it is not a fallback, (4) decode.
    /// Kept private here per B2b (no shared helper, no new type; the recognition
    /// service is referenced, not edited). A missing brace or a decode failure logs
    /// the first 200 characters of the raw text and returns nil → the caller's
    /// local-math + fallback-tip path.
    private func extractTargetResponse(from rawText: String) -> ClaudeTargetResponse? {
        // (1) strip markdown fences if present
        var text = rawText
        text = text.replacingOccurrences(of: "```json", with: "")
        text = text.replacingOccurrences(of: "```", with: "")
        // (2) trim whitespace/newlines
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // (3) slice from the first { through the last } — always runs
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}") else {
            print("[OnboardingVM] Tip parse failure — no JSON braces in: \(String(rawText.prefix(200)))")
            return nil
        }
        let jsonString = String(text[firstBrace...lastBrace])
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        // (4) decode
        do {
            return try JSONDecoder().decode(ClaudeTargetResponse.self, from: jsonData)
        } catch {
            print("[OnboardingVM] Tip decode failed: \(error) — raw: \(String(rawText.prefix(200)))")
            return nil
        }
    }

    // MARK: - Significant Change Detection

    /// Returns true if the current inputs differ meaningfully from a saved profile.
    ///
    /// "Meaningful" means a change that would actually shift calorie/macro targets —
    /// i.e. core biometrics, pace, activity, or diet style. Minor tweaks like
    /// updating allergies or meal count don't warrant a fresh API call.
    private func hasSignificantChanges(from profile: UserProfile) -> Bool {
        if sex != profile.sex { return true }
        if age != profile.age { return true }
        if abs(computedWeightKg - profile.weightKg) > 2.0 { return true }
        if abs(computedHeightCm - profile.heightCm) > 2.0 { return true }
        if abs(computedGoalWeightKg - profile.goalWeightKg) > 2.0 { return true }
        if weeklyPaceLbs != profile.weeklyPaceLbs { return true }
        if activityLevel != profile.activityLevel { return true }
        if dietStyle != profile.dietStyle { return true }
        return false
    }

    // MARK: - Step 12: Calculate + Fetch AI

    /// Runs the full calculation pipeline: local formulas → Claude API → validation → results.
    /// Advances to step 13 (Results) on completion. Safe to call multiple times
    /// (isProcessing guard prevents re-entrancy).
    ///
    /// In edit mode, Claude is only called when `hasSignificantChanges` is true.
    /// Minor edits (allergies, meals/day, sleep, stress) reuse local math + the
    /// existing coaching tip so we don't burn API credits unnecessarily.
    func calculateAndFetchAI() async {
        guard !isProcessing else { return }
        isProcessing = true

        let bmr = calculateBMR()
        let tdee = calculateTDEE(bmr: bmr)
        let localCalories = calculateCalorieTarget(tdee: tdee)
        let (localProtein, localCarbs, localFat) = macroGrams(calories: localCalories)

        // Edit mode fast-path: skip Claude when nothing meaningful changed
        if isEditMode, let existing = existingProfile, !hasSignificantChanges(from: existing) {
            calculatedCalories = localCalories
            calculatedProtein  = localProtein
            calculatedCarbs    = localCarbs
            calculatedFat      = localFat
            aiTip = existing.aiTip  // keep the coaching tip that was already generated
            isProcessing = false
            currentStep = 13
            return
        }

        let claudeResponse = await callClaudeAPI(
            localCalories: localCalories,
            localProtein: localProtein,
            localCarbs: localCarbs,
            localFat: localFat
        )

        if let r = claudeResponse, isValid(r) {
            calculatedCalories = r.calories
            calculatedProtein  = r.protein
            calculatedCarbs    = r.carbs
            calculatedFat      = r.fat
            aiTip = r.tip
        } else {
            calculatedCalories = localCalories
            calculatedProtein  = localProtein
            calculatedCarbs    = localCarbs
            calculatedFat      = localFat
            // Use Claude's tip even when falling back on local macros, if tip is present
            aiTip = claudeResponse?.tip ?? "Stay consistent and focus on small daily improvements."
        }

        isProcessing = false
        currentStep = 13
    }

    // MARK: - Save Results

    /// Builds a UserProfile from current state and saves via AppCoordinator.
    /// Clears the draft on success.
    func saveResults() async throws {
        guard let userId = authService.currentUserEmail, !userId.isEmpty else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let profile = UserProfile(
            userId: userId,
            sex: sex,
            age: max(13, min(80, age)),
            weightKg: computedWeightKg,
            heightCm: computedHeightCm,
            goalWeightKg: computedGoalWeightKg,
            weeklyPaceLbs: weeklyPaceLbs,
            activityLevel: activityLevel,
            dietStyle: dietStyle,
            mealsPerDay: mealsPerDay,
            allergies: allergies,
            sleepQuality: sleepQuality,
            stressLevel: stressLevel,
            aiTip: aiTip
        )

        do {
            try await coordinator.completeOnboarding(
                profile: profile,
                calories: calculatedCalories,
                protein: calculatedProtein,
                carbs: calculatedCarbs,
                fat: calculatedFat
            )
            clearDraft(userId: userId)
        } catch {
            saveError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Draft Persistence

    private static let draftSchemaVersion = 1

    private struct OnboardingDraft: Codable {
        let schemaVersion: Int
        var sex: String
        var age: Int
        var weightInput: String
        var heightFtInput: String
        var heightInInput: String
        var heightCmInput: String
        var goalWeightInput: String
        var weeklyPaceLbs: Double
        var activityLevel: String
        var dietStyle: String
        var mealsPerDay: Int
        var allergies: [String]
        var sleepQuality: String
        var stressLevel: String
        var useImperial: Bool
        var currentStep: Int
    }

    func saveDraft(userId: String) {
        let draft = OnboardingDraft(
            schemaVersion: Self.draftSchemaVersion,
            sex: sex,
            age: age,
            weightInput: weightInput,
            heightFtInput: heightFtInput,
            heightInInput: heightInInput,
            heightCmInput: heightCmInput,
            goalWeightInput: goalWeightInput,
            weeklyPaceLbs: weeklyPaceLbs,
            activityLevel: activityLevel,
            dietStyle: dietStyle,
            mealsPerDay: mealsPerDay,
            allergies: allergies,
            sleepQuality: sleepQuality,
            stressLevel: stressLevel,
            useImperial: useImperial,
            currentStep: currentStep
        )
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: draftKey(userId: userId))
        }
    }

    func loadDraft(userId: String) {
        guard
            let data = UserDefaults.standard.data(forKey: draftKey(userId: userId)),
            let draft = try? JSONDecoder().decode(OnboardingDraft.self, from: data),
            draft.schemaVersion == Self.draftSchemaVersion
        else { return }

        sex = draft.sex
        age = draft.age
        weightInput = draft.weightInput
        heightFtInput = draft.heightFtInput
        heightInInput = draft.heightInInput
        heightCmInput = draft.heightCmInput
        goalWeightInput = draft.goalWeightInput
        weeklyPaceLbs = draft.weeklyPaceLbs
        activityLevel = draft.activityLevel
        dietStyle = draft.dietStyle
        mealsPerDay = draft.mealsPerDay
        allergies = draft.allergies
        sleepQuality = draft.sleepQuality
        stressLevel = draft.stressLevel
        useImperial = draft.useImperial
        // Clamp to step 11 max (never restore to calculating/results screen)
        currentStep = min(draft.currentStep, 11)
    }

    func clearDraft(userId: String) {
        UserDefaults.standard.removeObject(forKey: draftKey(userId: userId))
    }

    private func draftKey(userId: String) -> String {
        "onboarding_draft_\(userId)"
    }

    // MARK: - User Switch Safety

    private func checkForUserIdChange() {
        let current = authService.currentUserEmail
        if current != lastKnownUserId {
            if let old = lastKnownUserId {
                clearDraft(userId: old)
            }
            resetForNewUser()
            lastKnownUserId = current
        }
    }

    func resetForNewUser() {
        currentStep = 0
        sex = "male"
        age = 25
        weightInput = ""
        heightFtInput = ""
        heightInInput = ""
        heightCmInput = ""
        goalWeightInput = ""
        weeklyPaceLbs = 1.0
        activityLevel = "moderate"
        dietStyle = "standard"
        mealsPerDay = 3
        allergies = []
        sleepQuality = "fair"
        stressLevel = "moderate"
        useImperial = true
        isProcessing = false
        calculatedCalories = 0
        calculatedProtein = 0
        calculatedCarbs = 0
        calculatedFat = 0
        aiTip = ""
        saveError = nil

        if let userId = authService.currentUserEmail {
            loadDraft(userId: userId)
        }
    }

    // MARK: - Pre-populate from existing profile

    private func populateFromProfile(_ profile: UserProfile) {
        sex = profile.sex
        age = profile.age
        activityLevel = profile.activityLevel
        dietStyle = profile.dietStyle
        mealsPerDay = profile.mealsPerDay
        allergies = profile.allergies
        sleepQuality = profile.sleepQuality
        stressLevel = profile.stressLevel
        weeklyPaceLbs = profile.weeklyPaceLbs

        // Convert stored metric to imperial display inputs
        if useImperial {
            weightInput = String(format: "%.1f", profile.weightKg * 2.20462)
            goalWeightInput = String(format: "%.1f", profile.goalWeightKg * 2.20462)
            let totalInches = profile.heightCm / 2.54
            heightFtInput = String(Int(totalInches / 12))
            heightInInput = String(format: "%.0f", totalInches.truncatingRemainder(dividingBy: 12))
        } else {
            weightInput = String(format: "%.1f", profile.weightKg)
            goalWeightInput = String(format: "%.1f", profile.goalWeightKg)
            heightCmInput = String(format: "%.0f", profile.heightCm)
        }
    }
}
