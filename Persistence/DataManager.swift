//
//  DataManager.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftData

/// Handles all SwiftData persistence operations (CRUD only)
///
/// This class is responsible solely for data access and storage.
/// Business logic lives in NutritionManager and GamificationManager.
/// ViewModels should interact with AppCoordinator, not directly with this class.
@Observable
final class DataManager {

    // MARK: - Properties

    private let modelContext: ModelContext

    // MARK: - Initialization

    /// Initializes the data manager with a SwiftData model context
    /// - Parameter modelContext: The SwiftData context for persistence operations
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Setup Methods

    /// Creates default data for new users (DailyGoal and UserProgress)
    ///
    /// Call this once on first app launch to initialize the user's account.
    /// Creates a default daily goal and initial user progress with 0 XP.
    func setupDefaultData() async throws {
        // Check if UserProgress already exists
        let progressDescriptor = FetchDescriptor<UserProgress>()
        let existingProgress = try modelContext.fetch(progressDescriptor)

        if existingProgress.isEmpty {
            // Create default user progress
            let progress = UserProgress(
                totalXP: 0,
                currentStreak: 0,
                longestStreak: 0,
                lastActiveDate: Date(),
                rank: Rank.iron.rawValue
            )
            modelContext.insert(progress)
        }

        // Create today's goal if it doesn't exist
        let todaysGoal = try await getTodaysGoal()
        if todaysGoal == nil {
            let defaultGoal = DailyGoal(
                date: Date(),
                calorieTarget: 2000,
                proteinTarget: 150.0,
                carbTarget: 200.0,
                fatTarget: 65.0,
                purityTarget: 30
            )
            modelContext.insert(defaultGoal)
        }

        try modelContext.save()
    }

    // MARK: - Food Entry Methods

    /// Adds a new food entry to the database
    /// - Parameters:
    ///   - name: Display name of the food
    ///   - calories: Total calories
    ///   - protein: Protein in grams
    ///   - carbs: Carbohydrates in grams
    ///   - fat: Fat in grams
    ///   - toxinScore: Processed food score (0-100)
    ///   - photoData: Optional meal photo
    ///   - barcodeUPC: Optional barcode identifier
    /// - Returns: The newly created FoodEntry
    func addFoodEntry(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int,
        photoData: Data? = nil,
        barcodeUPC: String? = nil
    ) async throws -> FoodEntry {
        let entry = FoodEntry(
            name: name,
            date: Date(),
            photoData: photoData,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            toxinScore: toxinScore,
            barcodeUPC: barcodeUPC,
            createdAt: Date()
        )

        modelContext.insert(entry)
        try modelContext.save()

        return entry
    }

    /// Deletes a food entry from the database
    /// - Parameter entry: The FoodEntry to delete
    func deleteFoodEntry(_ entry: FoodEntry) async throws {
        modelContext.delete(entry)
        try modelContext.save()
    }

    /// Updates an existing food entry
    /// - Parameter entry: The modified FoodEntry (changes are tracked by SwiftData)
    func updateFoodEntry(_ entry: FoodEntry) async throws {
        try modelContext.save()
    }

    /// Fetches all food entries for today
    /// - Returns: Array of FoodEntry objects logged today
    func fetchTodaysEntries() async throws -> [FoodEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.date >= startOfDay && entry.date < endOfDay
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Fetches all food entries for a specific date
    /// - Parameter date: The date to fetch entries for
    /// - Returns: Array of FoodEntry objects for that date
    func fetchEntriesForDate(_ date: Date) async throws -> [FoodEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.date >= startOfDay && entry.date < endOfDay
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Fetches all food entries within a date range
    /// - Parameters:
    ///   - start: Start date (inclusive)
    ///   - end: End date (exclusive)
    /// - Returns: Array of FoodEntry objects in the range
    func fetchEntriesForDateRange(start: Date, end: Date) async throws -> [FoodEntry] {
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.date >= start && entry.date < end
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    // MARK: - Goal Methods

    /// Gets today's daily goal (creates default if none exists)
    /// - Returns: Today's DailyGoal or nil if none exists
    func getTodaysGoal() async throws -> DailyGoal? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        var descriptor = FetchDescriptor<DailyGoal>(
            predicate: #Predicate { goal in
                goal.date >= startOfDay && goal.date < endOfDay
            }
        )
        descriptor.fetchLimit = 1

        let goals = try modelContext.fetch(descriptor)
        return goals.first
    }

    /// Updates the daily goal for today
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
        if let existingGoal = try await getTodaysGoal() {
            // Update existing goal
            existingGoal.calorieTarget = calories
            existingGoal.proteinTarget = protein
            existingGoal.carbTarget = carbs
            existingGoal.fatTarget = fat
            existingGoal.purityTarget = purity
        } else {
            // Create new goal for today
            let newGoal = DailyGoal(
                date: Date(),
                calorieTarget: calories,
                proteinTarget: protein,
                carbTarget: carbs,
                fatTarget: fat,
                purityTarget: purity
            )
            modelContext.insert(newGoal)
        }

        try modelContext.save()
    }

    // MARK: - Progress Methods

    /// Fetches the singleton UserProgress object
    /// - Returns: The user's progress data
    func getUserProgress() async throws -> UserProgress {
        let descriptor = FetchDescriptor<UserProgress>()
        let progressArray = try modelContext.fetch(descriptor)

        guard let progress = progressArray.first else {
            throw DataManagerError.userProgressNotFound
        }

        return progress
    }

    /// Updates user progress (saves changes tracked by SwiftData)
    func saveUserProgress() async throws {
        try modelContext.save()
    }

    // MARK: - Quest Methods

    /// Fetches today's daily quests
    /// - Returns: Array of DailyQuest objects for today
    func getTodaysQuests() async throws -> [DailyQuest] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        var descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { quest in
                quest.date >= startOfDay && quest.date < endOfDay
            }
        )

        return try modelContext.fetch(descriptor)
    }

    /// Adds a new quest to the database
    /// - Parameter quest: The DailyQuest to add
    func addQuest(_ quest: DailyQuest) async throws {
        modelContext.insert(quest)
        try modelContext.save()
    }

    /// Deletes all quests for a specific date
    /// - Parameter date: The date to delete quests for
    func deleteQuestsForDate(_ date: Date) async throws {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        var descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { quest in
                quest.date >= startOfDay && quest.date < endOfDay
            }
        )

        let quests = try modelContext.fetch(descriptor)
        for quest in quests {
            modelContext.delete(quest)
        }

        try modelContext.save()
    }

    /// Saves changes to quests
    func saveQuests() async throws {
        try modelContext.save()
    }
}

// MARK: - Error Types

/// Custom errors for DataManager operations
enum DataManagerError: LocalizedError {
    case userProgressNotFound
    case invalidDate
    case saveFailure

    var errorDescription: String? {
        switch self {
        case .userProgressNotFound:
            return "User progress data not found. Please set up default data first."
        case .invalidDate:
            return "The provided date is invalid."
        case .saveFailure:
            return "Failed to save data to the database."
        }
    }
}
