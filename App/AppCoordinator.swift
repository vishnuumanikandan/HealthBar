//
//  AppCoordinator.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftData

/// Central orchestrator for HealthBar business logic
///
/// Coordinates between DataManager (persistence), NutritionManager (nutrition logic),
/// and GamificationManager (XP/quests/streaks). ViewModels should interact with this class.
///
/// Usage example:
/// ```swift
/// let coordinator = AppCoordinator(modelContext: context)
/// await coordinator.setupApp()
/// let todayStats = try await coordinator.getTodaysSummary()
/// ```
@Observable
final class AppCoordinator {

    // MARK: - Properties

    private let dataManager: DataManager
    private let nutritionManager: NutritionManager
    private let gamificationManager: GamificationManager

    // MARK: - Initialization

    /// Initializes the app coordinator with a SwiftData model context and auth service.
    /// - Parameters:
    ///   - modelContext: SwiftData context for persistence
    ///   - authService: The auth service DataManager reads the current userId from live.
    ///                  Defaults to `LocalAuthService.shared` so all existing call sites
    ///                  (e.g., `AppCoordinator(modelContext: ctx)` in ContentView) compile
    ///                  unchanged — no View modifications are required.
    init(modelContext: ModelContext, authService: any AuthService = LocalAuthService.shared) {
        self.dataManager = DataManager(modelContext: modelContext, authService: authService)
        self.nutritionManager = NutritionManager()
        self.gamificationManager = GamificationManager()
    }

    // MARK: - Setup

    /// Sets up the app for a new user (creates default data)
    ///
    /// Call this once on first app launch.
    func setupApp() async throws {
        try await dataManager.setupDefaultData()
    }

    // MARK: - Food Entry Operations

    /// Adds a food entry and checks quest progress
    /// - Parameters:
    ///   - name: Food name
    ///   - calories: Total calories
    ///   - protein: Protein in grams
    ///   - carbs: Carbs in grams
    ///   - fat: Fat in grams
    ///   - toxinScore: Toxin score (0-100)
    ///   - photoData: Optional photo
    ///   - barcodeUPC: Optional barcode
    ///   - fiber: Optional fiber in grams
    ///   - sugar: Optional sugar in grams
    ///   - sodium: Optional sodium in milligrams
    ///   - saturatedFat: Optional saturated fat in grams
    ///   - cholesterol: Optional cholesterol in milligrams
    ///   - potassium: Optional potassium in milligrams
    /// - Returns: The created FoodEntry and any XP earned from quest completion
    ///
    /// Note: Meal type is auto-assigned based on current time (not editable by user)
    func addFoodEntry(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int,
        date: Date = Date(),
        photoData: Data? = nil,
        barcodeUPC: String? = nil,
        mealType: MealType? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil,
        saturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        potassium: Double? = nil,
        mealBundleId: String? = nil,
        mealBundleName: String? = nil
    ) async throws -> (entry: FoodEntry, xpEarned: Int) {
        // Use caller-provided meal type if given, otherwise auto-assign from the entry's date
        let resolvedMealType = mealType ?? MealType.fromTime(date)

        // Add the food entry
        let entry = try await dataManager.addFoodEntry(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            toxinScore: toxinScore,
            date: date,
            photoData: photoData,
            barcodeUPC: barcodeUPC,
            mealType: resolvedMealType,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            saturatedFat: saturatedFat,
            cholesterol: cholesterol,
            potassium: potassium,
            mealBundleId: mealBundleId,
            mealBundleName: mealBundleName
        )

        // Check and update quest progress
        let xpEarned = try await checkAndUpdateQuestProgress()

        return (entry: entry, xpEarned: xpEarned)
    }

    /// Deletes a food entry and rechecks quest progress
    /// - Parameter entry: Food entry to delete
    func deleteFoodEntry(_ entry: FoodEntry) async throws {
        try await dataManager.deleteFoodEntry(entry)

        // Recheck quest progress since data changed
        _ = try await checkAndUpdateQuestProgress()
    }

    /// Updates a food entry
    /// - Parameter entry: Modified food entry
    func updateFoodEntry(_ entry: FoodEntry) async throws {
        try await dataManager.updateFoodEntry(entry)

        // Recheck quest progress
        _ = try await checkAndUpdateQuestProgress()
    }

    // MARK: - Daily Summary

    /// Gets a complete summary of today's nutrition and progress
    /// - Returns: TodaySummary object with all daily stats
    func getTodaysSummary() async throws -> TodaySummary {
        // Ensure default UserProgress and DailyGoal exist for this user before reading.
        // This is idempotent — a no-op for returning users and a no-op if not logged in.
        // Bootstraps new users the first time they land on the Home tab after login.
        try await dataManager.setupDefaultData()

        let entries = try await dataManager.fetchTodaysEntries()
        let goal = try await getCurrentGoal()
        let progress = try await dataManager.getUserProgress()
        let quests = try await getTodaysQuests()

        let totalCalories = nutritionManager.calculateTotalCalories(from: entries)
        let macros = nutritionManager.calculateTotalMacros(from: entries)
        let toxinScore = nutritionManager.calculateTotalToxinScore(from: entries)
        let metGoals = nutritionManager.didMeetGoals(entries: entries, goal: goal)

        let currentLevel = gamificationManager.calculateLevel(from: progress.totalXP)
        let xpForNext = gamificationManager.xpForNextLevel(currentXP: progress.totalXP)
        let currentRank = gamificationManager.getCurrentRank(from: progress.totalXP)

        return TodaySummary(
            entries: entries,
            totalCalories: totalCalories,
            totalProtein: macros.protein,
            totalCarbs: macros.carbs,
            totalFat: macros.fat,
            totalToxinScore: toxinScore,
            goal: goal,
            metGoals: metGoals,
            currentLevel: currentLevel,
            totalXP: progress.totalXP,
            xpForNextLevel: xpForNext,
            currentStreak: progress.currentStreak,
            longestStreak: progress.longestStreak,
            currentRank: currentRank,
            quests: quests
        )
    }

    // MARK: - Goal Management

    /// Gets today's goal (creates default if missing)
    /// - Returns: Today's DailyGoal
    func getCurrentGoal() async throws -> DailyGoal {
        if let goal = try await dataManager.getTodaysGoal() {
            return goal
        }

        // Create default goal if none exists
        try await dataManager.updateDailyGoal(
            calories: 2000,
            protein: 150.0,
            carbs: 200.0,
            fat: 65.0,
            purity: 30
        )

        return try await dataManager.getTodaysGoal()!
    }

    /// Updates today's daily goal
    /// - Parameters:
    ///   - calories: New calorie target
    ///   - protein: New protein target
    ///   - carbs: New carb target
    ///   - fat: New fat target
    ///   - purity: New purity target
    ///   - fiberTarget: Optional fiber target in grams
    ///   - sugarTarget: Optional sugar limit in grams
    ///   - sodiumTarget: Optional sodium limit in milligrams
    ///   - saturatedFatTarget: Optional saturated fat limit in grams
    ///   - cholesterolTarget: Optional cholesterol limit in milligrams
    ///   - potassiumTarget: Optional potassium target in milligrams
    func updateDailyGoal(
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        purity: Int,
        fiberTarget: Double? = nil,
        sugarTarget: Double? = nil,
        sodiumTarget: Double? = nil,
        saturatedFatTarget: Double? = nil,
        cholesterolTarget: Double? = nil,
        potassiumTarget: Double? = nil
    ) async throws {
        try await dataManager.updateDailyGoal(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            purity: purity,
            fiberTarget: fiberTarget,
            sugarTarget: sugarTarget,
            sodiumTarget: sodiumTarget,
            saturatedFatTarget: saturatedFatTarget,
            cholesterolTarget: cholesterolTarget,
            potassiumTarget: potassiumTarget
        )
    }

    // MARK: - Progress & XP

    /// Adds XP manually (for special events or achievements)
    /// - Parameter amount: XP to add
    /// - Returns: Tuple indicating level up and new level
    func addXP(_ amount: Int) async throws -> (didLevelUp: Bool, newLevel: Int) {
        var progress = try await dataManager.getUserProgress()
        let result = gamificationManager.addXP(amount: amount, to: &progress)
        try await dataManager.saveUserProgress()
        return result
    }

    /// Updates streak and awards daily goal XP if met
    ///
    /// Call this once per day (e.g., at midnight or on first app open)
    func checkAndAwardDailyXP() async throws -> (xpAwarded: Int, newStreak: Int) {
        var progress = try await dataManager.getUserProgress()
        let entries = try await dataManager.fetchTodaysEntries()
        let goal = try await getCurrentGoal()

        // Update streak
        let newStreak = gamificationManager.updateStreak(for: &progress)

        // Check if goals met and award XP
        let metGoals = nutritionManager.didMeetGoals(entries: entries, goal: goal)
        let xpAwarded = gamificationManager.awardDailyGoalXP(to: &progress, metGoals: metGoals)

        try await dataManager.saveUserProgress()

        return (xpAwarded: xpAwarded, newStreak: newStreak)
    }

    // MARK: - Quest Management

    /// Gets today's quests (generates new ones if needed)
    /// - Returns: Array of today's DailyQuests
    func getTodaysQuests() async throws -> [DailyQuest] {
        let existingQuests = try await dataManager.getTodaysQuests()

        // If quests exist for today, return them
        if !existingQuests.isEmpty {
            return existingQuests
        }

        // Generate new quests for today
        let newQuests = gamificationManager.generateDailyQuests()
        for quest in newQuests {
            try await dataManager.addQuest(quest)
        }

        return newQuests
    }

    /// Checks quest progress and auto-completes eligible quests
    /// - Returns: Total XP earned from newly completed quests
    private func checkAndUpdateQuestProgress() async throws -> Int {
        var quests = try await dataManager.getTodaysQuests()
        let entries = try await dataManager.fetchTodaysEntries()
        let goal = try await getCurrentGoal()
        var progress = try await dataManager.getUserProgress()

        let xpEarned = gamificationManager.checkQuestProgress(
            quests: &quests,
            entries: entries,
            goal: goal,
            progress: &progress
        )

        // Save updates
        try await dataManager.saveQuests()
        try await dataManager.saveUserProgress()

        return xpEarned
    }

    /// Manually completes a quest (for testing or special cases)
    /// - Parameter quest: Quest to complete
    /// - Returns: XP earned
    func completeQuest(_ quest: DailyQuest) async throws -> Int {
        var questCopy = quest
        var progress = try await dataManager.getUserProgress()

        let xpEarned = gamificationManager.completeQuest(quest: &questCopy, progress: &progress)

        try await dataManager.saveQuests()
        try await dataManager.saveUserProgress()

        return xpEarned
    }

    /// Resets quests if it's a new day
    func resetQuestsIfNeeded() async throws {
        let quests = try await dataManager.getTodaysQuests()

        guard let firstQuest = quests.first else { return }

        let shouldReset = gamificationManager.shouldResetQuests(lastDate: firstQuest.date)

        if shouldReset {
            // Delete old quests
            try await dataManager.deleteQuestsForDate(firstQuest.date)

            // Generate new quests
            let newQuests = gamificationManager.generateDailyQuests()
            for quest in newQuests {
                try await dataManager.addQuest(quest)
            }
        }
    }

    // MARK: - Streak Milestones

    /// Checks if any streak milestones have been reached and returns the first unclaimed one
    /// - Returns: The milestone that was claimed, or nil if none
    func checkForStreakMilestone() async throws -> StreakMilestone? {
        var progress = try await dataManager.getUserProgress()

        // Check for milestone
        if let milestone = gamificationManager.checkForMilestone(streak: progress.currentStreak, progress: &progress) {
            // Save updated progress
            try await dataManager.saveUserProgress()
            return milestone
        }

        return nil
    }

    // MARK: - Personal Baselines

    /// Gets the baseline for today's day of week
    /// - Returns: PersonalBaseline for today's weekday, or nil if not enough data
    func getTodaysBaseline() async throws -> PersonalBaseline? {
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        return try await dataManager.getBaselineForDayOfWeek(dayOfWeek)
    }

    /// Updates personal baselines from historical data
    ///
    /// Should be called periodically (e.g., at app launch or end of day)
    func updatePersonalBaselines() async throws {
        try await dataManager.calculateAndUpdateBaselines()
    }

    /// Compares today's purity against the baseline
    /// - Returns: Difference as a fraction (e.g., -0.15 means 15% better, +0.10 means 10% worse)
    func getPurityVsBaseline() async throws -> Double? {
        guard let baseline = try await getTodaysBaseline(),
              baseline.sampleCount >= 1,
              baseline.averagePurity > 0 else {
            return nil
        }

        let entries = try await dataManager.fetchTodaysEntries()
        let todaysPurity = entries.reduce(0) { $0 + $1.toxinScore }

        // Calculate difference (positive = worse than baseline, negative = better)
        let difference = (Double(todaysPurity) - baseline.averagePurity) / baseline.averagePurity
        return difference
    }

    // MARK: - Mood Tracking

    /// Logs the user's mood for today
    /// - Parameter mood: The mood to log
    /// - Returns: The created MoodEntry
    @discardableResult
    func logMood(_ mood: Mood) async throws -> MoodEntry {
        return try await dataManager.addMoodEntry(mood: mood)
    }

    /// Checks if mood has already been logged today
    /// - Returns: True if already logged
    func checkIfMoodLoggedToday() async throws -> Bool {
        return try await dataManager.hasMoodLoggedToday()
    }

    /// Gets today's mood entry if exists
    /// - Returns: The MoodEntry or nil
    func getTodaysMood() async throws -> MoodEntry? {
        return try await dataManager.getTodaysMood()
    }

    // MARK: - Daily Insights

    /// Gets daily insights data for the insights card
    /// - Returns: DailyInsights with meal count, protein progress, and purity trend
    func getDailyInsights() async throws -> DailyInsights {
        let entries = try await dataManager.fetchTodaysEntries()
        let goal = try await getCurrentGoal()

        // Calculate meal count
        let mealCount = entries.count

        // Calculate protein progress
        let totalProtein = entries.reduce(0.0) { $0 + $1.protein }
        let proteinProgress = goal.proteinTarget > 0 ? totalProtein / goal.proteinTarget : 0
        let proteinGoalHit = proteinProgress >= 1.0

        // Get purity vs baseline
        let purityVsBaseline = try await getPurityVsBaseline()

        // Get day name
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let dayName = dayFormatter.string(from: Date())

        return DailyInsights(
            mealCount: mealCount,
            proteinGoalHit: proteinGoalHit,
            proteinProgress: proteinProgress,
            purityVsBaseline: purityVsBaseline,
            dayName: dayName
        )
    }

    // MARK: - Weekly Summary

    /// Gets weekly summary data for the weekly view
    /// - Returns: WeeklySummary with Mon-Sun data
    func getWeeklySummary() async throws -> WeeklySummary {
        let calendar = Calendar.current
        let today = Date()

        // Find the start of this week (Monday)
        var startOfWeek = today
        while calendar.component(.weekday, from: startOfWeek) != 2 { // 2 = Monday
            startOfWeek = calendar.date(byAdding: .day, value: -1, to: startOfWeek)!
        }
        startOfWeek = calendar.startOfDay(for: startOfWeek)

        // Get goal for reference
        let goal = try await getCurrentGoal()

        // Build day summaries for Mon-Sun
        var daySummaries: [DaySummary] = []

        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek)!

            // Only fetch data for days up to and including today
            if date <= today {
                let entries = try await dataManager.fetchEntriesForDate(date)

                let totalCalories = entries.reduce(0) { $0 + $1.calories }
                let totalProtein = entries.reduce(0.0) { $0 + $1.protein }
                let totalPurity = entries.reduce(0) { $0 + $1.toxinScore }

                daySummaries.append(DaySummary(
                    date: date,
                    calories: totalCalories,
                    protein: totalProtein,
                    purityScore: totalPurity,
                    mealCount: entries.count
                ))
            } else {
                // Future day - no data
                daySummaries.append(DaySummary(
                    date: date,
                    calories: 0,
                    protein: 0,
                    purityScore: 0,
                    mealCount: 0
                ))
            }
        }

        return WeeklySummary(
            days: daySummaries,
            calorieGoal: goal.calorieTarget,
            proteinGoal: goal.proteinTarget,
            purityGoal: goal.purityTarget
        )
    }

    // MARK: - Historical Data

    /// Fetches food entries for a specific date
    /// - Parameter date: Date to fetch entries for
    /// - Returns: Array of FoodEntry objects
    func getEntriesForDate(_ date: Date) async throws -> [FoodEntry] {
        return try await dataManager.fetchEntriesForDate(date)
    }

    /// Fetches food entries for a date range
    /// - Parameters:
    ///   - start: Start date
    ///   - end: End date
    /// - Returns: Array of FoodEntry objects
    func getEntriesForDateRange(start: Date, end: Date) async throws -> [FoodEntry] {
        return try await dataManager.fetchEntriesForDateRange(start: start, end: end)
    }

    // MARK: - User Progress

    /// Gets current user progress
    /// - Returns: UserProgress object
    func getUserProgress() async throws -> UserProgress {
        return try await dataManager.getUserProgress()
    }

    // MARK: - Recent Foods & Favorites

    /// Gets recent unique foods for quick-log feature
    ///
    /// Returns one entry per unique FoodFingerprint, sorted by most recent.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of foods to return (default 15)
    ///   - daysBack: Number of days to look back (default 30)
    /// - Returns: Array of FoodEntry, one per unique food
    func getRecentUniqueFoods(limit: Int = 15, daysBack: Int = 30) async throws -> [FoodEntry] {
        return try await dataManager.getRecentUniqueFoods(limit: limit, daysBack: daysBack)
    }

    /// Gets all favorited foods for quick-log feature
    ///
    /// Returns one entry per unique favorited FoodFingerprint.
    ///
    /// - Returns: Array of favorited FoodEntry objects
    func getFavoriteFoods() async throws -> [FoodEntry] {
        return try await dataManager.getFavoriteFoods()
    }

    /// Toggles favorite status for a food (applies to ALL matching entries)
    ///
    /// When user favorites a food, all entries with the same fingerprint are marked as favorite.
    /// This makes the FOOD favorite, not just one log instance.
    ///
    /// - Parameter entry: The food entry to toggle favorite status for
    func toggleFavorite(_ entry: FoodEntry) async throws {
        let fingerprint = FoodFingerprint(from: entry)
        try await dataManager.toggleFavoriteForFingerprint(fingerprint)
    }

    // MARK: - CustomFood

    func getCustomFoods() async throws -> [CustomFood] {
        return try await dataManager.getCustomFoods()
    }

    func addCustomFood(_ food: CustomFood) async throws {
        try await dataManager.addCustomFood(food)
    }

    func updateCustomFood(_ food: CustomFood) async throws {
        try await dataManager.updateCustomFood(food)
    }

    func deleteCustomFood(_ food: CustomFood) async throws {
        try await dataManager.deleteCustomFood(food)
    }

    // MARK: - SavedMeal

    func getSavedMeals() async throws -> [SavedMeal] {
        return try await dataManager.getSavedMeals()
    }

    func addSavedMeal(_ meal: SavedMeal) async throws {
        try await dataManager.addSavedMeal(meal)
    }

    func updateSavedMeal(_ meal: SavedMeal) async throws {
        try await dataManager.updateSavedMeal(meal)
    }

    func deleteSavedMeal(_ meal: SavedMeal) async throws {
        try await dataManager.deleteSavedMeal(meal)
    }

    /// Logs all components of a saved meal as a grouped bundle of FoodEntries.
    /// All entries share the same mealBundleId so they display as one row in the log.
    /// Returns total XP earned from quest completions.
    @discardableResult
    func logSavedMeal(
        _ meal: SavedMeal,
        date: Date = Date(),
        mealType: MealType? = nil
    ) async throws -> Int {
        let resolvedMealType = mealType ?? MealType.fromTime(date)
        let bundleId = UUID().uuidString  // shared across all components
        for component in meal.components {
            _ = try await addFoodEntry(
                name: component.foodName,
                calories: component.calories,
                protein: component.protein,
                carbs: component.carbs,
                fat: component.fat,
                toxinScore: component.toxinScore,
                date: date,
                mealType: resolvedMealType,
                mealBundleId: bundleId,
                mealBundleName: meal.name
            )
        }
        return try await checkAndUpdateQuestProgress()
    }

    // MARK: - SavedRecipe

    func getSavedRecipes() async throws -> [SavedRecipe] {
        return try await dataManager.getSavedRecipes()
    }

    func addSavedRecipe(_ recipe: SavedRecipe) async throws {
        try await dataManager.addSavedRecipe(recipe)
    }

    func updateSavedRecipe(_ recipe: SavedRecipe) async throws {
        try await dataManager.updateSavedRecipe(recipe)
    }

    func deleteSavedRecipe(_ recipe: SavedRecipe) async throws {
        try await dataManager.deleteSavedRecipe(recipe)
    }

    /// Saves a recipe's per-serving nutrition as a new CustomFood in My Foods.
    @discardableResult
    func saveRecipeAsFood(_ recipe: SavedRecipe) async throws -> CustomFood {
        let food = CustomFood(
            name: recipe.name,
            calories: recipe.perServingCalories,
            protein: recipe.perServingProtein,
            carbs: recipe.perServingCarbs,
            fat: recipe.perServingFat,
            servingSizeName: "1 serving",
            servingSizeAmount: 1.0,
            servingUnit: "serving",
            toxinScore: recipe.purityScore
        )
        try await dataManager.addCustomFood(food)
        return food
    }

    // MARK: - MealType Update (for drag-and-drop)

    /// Updates the meal type of an existing food entry.
    func updateMealType(of entry: FoodEntry, to mealType: MealType) async throws {
        entry.mealType = mealType
        try await dataManager.updateFoodEntry(entry)
    }

    /// Quick-logs a food by creating a copy with today's date
    ///
    /// Creates a new FoodEntry with all the same nutrition data but today's date.
    /// Meal type is auto-assigned based on current time (not preserved from original).
    /// Checks quest progress and awards XP as normal.
    ///
    /// - Parameter entry: The food entry to re-log
    /// - Returns: The new entry and any XP earned
    // MARK: - UserProfile / Onboarding

    /// Fetches the UserProfile for the current user, or nil if none exists.
    func getUserProfile() async throws -> UserProfile? {
        return try await dataManager.getUserProfile()
    }

    /// Returns true if the current user has a completed UserProfile.
    /// Returns false on any error or if no profile exists.
    func checkOnboardingCompleted() async -> Bool {
        do {
            let profile = try await dataManager.getUserProfile()
            return profile?.setupCompleted == true
        } catch {
            return false
        }
    }

    /// Fetches the UserProfile from Firestore and overwrites local if different.
    func syncUserProfileFromFirestore() async throws {
        try await dataManager.syncUserProfileFromFirestore()
    }

    /// Completes the onboarding flow: saves the UserProfile and overwrites DailyGoal targets.
    ///
    /// - Parameters:
    ///   - profile: UserProfile with all fields populated. setupCompleted is set to true here.
    ///   - calories: AI/formula calorie target (overwrites DailyGoal completely).
    ///   - protein: Protein target in grams.
    ///   - carbs: Carbohydrate target in grams.
    ///   - fat: Fat target in grams.
    func completeOnboarding(
        profile: UserProfile,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int
    ) async throws {
        profile.setupCompleted = true
        profile.updatedAt = Date()
        try await dataManager.upsertUserProfile(profile)
        try await dataManager.updateDailyGoalTargets(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )
    }

    func quickLogFood(
        _ entry: FoodEntry,
        date: Date = Date(),
        mealType: MealType? = nil
    ) async throws -> (entry: FoodEntry, xpEarned: Int) {
        let resolvedDate = date
        let resolvedMealType = mealType ?? MealType.fromTime(resolvedDate)

        // Create a new entry with same nutrition data but the specified date
        let newEntry = FoodEntry(
            name: entry.name,
            date: resolvedDate,
            photoData: entry.photoData,
            calories: entry.calories,
            protein: entry.protein,
            carbs: entry.carbs,
            fat: entry.fat,
            toxinScore: entry.toxinScore,
            barcodeUPC: entry.barcodeUPC,
            createdAt: Date(),
            isFavorite: entry.isFavorite,
            mealType: resolvedMealType
        )

        // Insert into database
        try await dataManager.insertFoodEntry(newEntry)

        // Check and update quest progress
        let xpEarned = try await checkAndUpdateQuestProgress()

        return (entry: newEntry, xpEarned: xpEarned)
    }

    // MARK: - Badge Relay

    /// Returns all BadgeProgress records for the current user.
    func getAllBadgeProgress() async throws -> [BadgeProgress] {
        return try await dataManager.getAllBadgeProgress()
    }

    /// Fires badge checks for streak and XP triggers after daily XP is awarded.
    func checkBadgesAfterStreakUpdate() async {
        if let badges = try? await dataManager.checkAndUnlockBadges(trigger: .streakUpdated), !badges.isEmpty {
            BadgeToastQueue.shared.enqueue(badges)
        }
    }

    func checkBadgesAfterXPAwarded() async {
        if let badges = try? await dataManager.checkAndUnlockBadges(trigger: .xpAwarded), !badges.isEmpty {
            BadgeToastQueue.shared.enqueue(badges)
        }
    }

    func checkBadgesAfterQuestsCompleted() async {
        if let badges = try? await dataManager.checkAndUnlockBadges(trigger: .questsChecked), !badges.isEmpty {
            BadgeToastQueue.shared.enqueue(badges)
        }
    }

    // MARK: - UserProfile DisplayName Update

    /// Updates the displayName in the current user's UserProfile (local SwiftData only).
    /// The caller (AccountViewModel) is responsible for also updating Firebase Auth and Firestore.
    func updateUserProfileDisplayName(_ name: String) async throws {
        guard let profile = try await dataManager.getUserProfile() else { return }
        profile.displayName = name.trimmingCharacters(in: .whitespaces)
        try await dataManager.upsertUserProfile(profile)
    }

    // MARK: - Guest Mode

    /// Migrates all SwiftData records from userId=="guest" to the given authenticated userId.
    /// Called by ContentView after a guest user signs up, before setting isGuest=false.
    func migrateGuestData(to newUserId: String) async throws {
        try await dataManager.migrateGuestData(to: newUserId)
    }

    /// Deletes all SwiftData records scoped to userId=="guest".
    /// Called when a guest user confirms sign-out.
    func deleteAllGuestData() async throws {
        try await dataManager.deleteAllGuestData()
    }

    /// Explicitly starts Firestore sync for the current user.
    /// Called after guest→auth migration completes — do not rely on automatic triggers.
    func startFirestoreSyncForCurrentUser() {
        dataManager.startFirestoreSyncForCurrentUser()
    }
}

// MARK: - Supporting Types

/// Summary of today's nutrition and gamification data
struct TodaySummary {
    let entries: [FoodEntry]
    let totalCalories: Int
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let totalToxinScore: Int
    let goal: DailyGoal
    let metGoals: Bool
    let currentLevel: Int
    let totalXP: Int
    let xpForNextLevel: Int
    let currentStreak: Int
    let longestStreak: Int
    let currentRank: Rank
    let quests: [DailyQuest]
}
