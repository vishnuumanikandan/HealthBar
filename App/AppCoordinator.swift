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

    /// Initializes the app coordinator with a SwiftData model context
    /// - Parameter modelContext: SwiftData context for persistence
    init(modelContext: ModelContext) {
        self.dataManager = DataManager(modelContext: modelContext)
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
    /// - Returns: The created FoodEntry and any XP earned from quest completion
    func addFoodEntry(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int,
        photoData: Data? = nil,
        barcodeUPC: String? = nil
    ) async throws -> (entry: FoodEntry, xpEarned: Int) {
        // Add the food entry
        let entry = try await dataManager.addFoodEntry(
            name: name,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            toxinScore: toxinScore,
            photoData: photoData,
            barcodeUPC: barcodeUPC
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
    func updateDailyGoal(
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        purity: Int
    ) async throws {
        try await dataManager.updateDailyGoal(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            purity: purity
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
