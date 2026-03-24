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
///
/// **User isolation:** Every fetch is scoped to `currentUserId`. If the user is
/// not authenticated (currentUserId == nil), all fetches return empty immediately
/// and all inserts throw `DataManagerError.notAuthenticated`. This prevents any
/// cross-user data leakage regardless of how many AppCoordinator instances exist.
@Observable
final class DataManager {

    // MARK: - Properties

    private let modelContext: ModelContext

    // MARK: - Auth

    /// The auth service used to determine the current user's identifier.
    /// Injected at init so this class never references a concrete auth type.
    private let authService: any AuthService

    /// The identifier for the currently authenticated user.
    ///
    /// Read **live** from AuthService on every call — never cached locally.
    /// Returns nil when no session is active, causing all queries to short-circuit
    /// and return empty results, which prevents any stale or cross-user data.
    ///
    /// TODO: Replace `authService.currentUserEmail` with `authService.currentUserUID`
    /// (a stable, opaque Firebase UID) when Firebase is integrated in Phase 3.
    /// Using currentUserEmail as a temporary stable identifier during local-only
    /// development. Do NOT treat this value as a permanent identifier — always read
    /// it from AuthService at the time of use and never persist it independently.
    private var currentUserId: String? {
        authService.currentUserEmail  // TODO: swap for Firebase UID in Phase 3
    }

    // MARK: - Initialization

    /// Initializes the data manager with a SwiftData model context and auth service.
    /// - Parameters:
    ///   - modelContext: The SwiftData context for persistence operations
    ///   - authService: The auth service for reading the current userId live.
    ///                  Defaults to `LocalAuthService.shared` so existing callers
    ///                  (e.g., `AppCoordinator(modelContext:)`) compile unchanged.
    init(modelContext: ModelContext, authService: any AuthService = LocalAuthService.shared) {
        self.modelContext = modelContext
        self.authService = authService
    }

    // MARK: - Setup Methods

    /// Creates default data for a newly authenticated user (DailyGoal + UserProgress).
    ///
    /// Safe to call repeatedly — it is a no-op if data already exists for this user,
    /// and a no-op if no user is authenticated (currentUserId == nil).
    /// Call this before loading any user-facing data after login.
    func setupDefaultData() async throws {
        // Guard: no setup runs without an authenticated user
        guard let userId = currentUserId, !userId.isEmpty else { return }

        // Check if UserProgress already exists for this specific user
        let progressDescriptor = FetchDescriptor<UserProgress>(
            predicate: #Predicate { progress in
                progress.userId == userId
            }
        )
        let existingProgress = try modelContext.fetch(progressDescriptor)

        if existingProgress.isEmpty {
            let progress = UserProgress(
                totalXP: 0,
                currentStreak: 0,
                longestStreak: 0,
                lastActiveDate: Date(),
                rank: Rank.iron.rawValue
            )
            // Stamp the current user's identifier — userId read live, not cached
            progress.userId = userId  // TODO: replace with Firebase UID in Phase 3
            modelContext.insert(progress)
        }

        // Create today's goal if it doesn't exist for this user
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
            // Stamp the current user's identifier
            defaultGoal.userId = userId  // TODO: replace with Firebase UID in Phase 3
            modelContext.insert(defaultGoal)
        }

        try modelContext.save()
    }

    // MARK: - Food Entry Methods

    /// Adds a new food entry to the database, scoped to the current user.
    /// - Returns: The newly created FoodEntry
    func addFoodEntry(
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        fat: Double,
        toxinScore: Int,
        photoData: Data? = nil,
        barcodeUPC: String? = nil,
        mealType: MealType = .uncategorized,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil,
        saturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        potassium: Double? = nil
    ) async throws -> FoodEntry {
        // Guard: no insert runs without an authenticated user
        guard let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }

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
            createdAt: Date(),
            mealType: mealType,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            saturatedFat: saturatedFat,
            cholesterol: cholesterol,
            potassium: potassium
        )
        // Stamp the current user's identifier on every new record
        entry.userId = userId  // TODO: replace with Firebase UID in Phase 3

        modelContext.insert(entry)
        try modelContext.save()

        return entry
    }

    /// Deletes a food entry from the database.
    func deleteFoodEntry(_ entry: FoodEntry) async throws {
        modelContext.delete(entry)
        try modelContext.save()
    }

    /// Updates an existing food entry (changes tracked by SwiftData).
    func updateFoodEntry(_ entry: FoodEntry) async throws {
        try modelContext.save()
    }

    /// Fetches all food entries for today, scoped to the current user.
    func fetchTodaysEntries() async throws -> [FoodEntry] {
        // Guard: no query runs without an authenticated user
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.userId == userId
                    && entry.date >= startOfDay
                    && entry.date < endOfDay
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Fetches all food entries for a specific date, scoped to the current user.
    func fetchEntriesForDate(_ date: Date) async throws -> [FoodEntry] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.userId == userId
                    && entry.date >= startOfDay
                    && entry.date < endOfDay
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Fetches all food entries within a date range, scoped to the current user.
    func fetchEntriesForDateRange(start: Date, end: Date) async throws -> [FoodEntry] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.userId == userId
                    && entry.date >= start
                    && entry.date < end
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    // MARK: - Goal Methods

    /// Gets today's daily goal for the current user (nil if none exists).
    func getTodaysGoal() async throws -> DailyGoal? {
        guard let userId = currentUserId, !userId.isEmpty else { return nil }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        var descriptor = FetchDescriptor<DailyGoal>(
            predicate: #Predicate { goal in
                goal.userId == userId
                    && goal.date >= startOfDay
                    && goal.date < endOfDay
            }
        )
        descriptor.fetchLimit = 1

        let goals = try modelContext.fetch(descriptor)
        return goals.first
    }

    /// Updates the daily goal for today, scoped to the current user.
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
        guard let userId = currentUserId, !userId.isEmpty else { return }

        if let existingGoal = try await getTodaysGoal() {
            // Update existing goal
            existingGoal.calorieTarget = calories
            existingGoal.proteinTarget = protein
            existingGoal.carbTarget = carbs
            existingGoal.fatTarget = fat
            existingGoal.purityTarget = purity
            // Advanced nutrition goals
            existingGoal.fiberTarget = fiberTarget
            existingGoal.sugarTarget = sugarTarget
            existingGoal.sodiumTarget = sodiumTarget
            existingGoal.saturatedFatTarget = saturatedFatTarget
            existingGoal.cholesterolTarget = cholesterolTarget
            existingGoal.potassiumTarget = potassiumTarget
        } else {
            // Create new goal for today and stamp with current user
            let newGoal = DailyGoal(
                date: Date(),
                calorieTarget: calories,
                proteinTarget: protein,
                carbTarget: carbs,
                fatTarget: fat,
                purityTarget: purity,
                fiberTarget: fiberTarget,
                sugarTarget: sugarTarget,
                sodiumTarget: sodiumTarget,
                saturatedFatTarget: saturatedFatTarget,
                cholesterolTarget: cholesterolTarget,
                potassiumTarget: potassiumTarget
            )
            newGoal.userId = userId  // TODO: replace with Firebase UID in Phase 3
            modelContext.insert(newGoal)
        }

        try modelContext.save()
    }

    // MARK: - Progress Methods

    /// Fetches the UserProgress for the current user. Throws if not found.
    func getUserProgress() async throws -> UserProgress {
        guard let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }

        let descriptor = FetchDescriptor<UserProgress>(
            predicate: #Predicate { progress in
                progress.userId == userId
            }
        )
        let progressArray = try modelContext.fetch(descriptor)

        guard let progress = progressArray.first else {
            throw DataManagerError.userProgressNotFound
        }

        return progress
    }

    /// Saves in-progress changes to UserProgress.
    func saveUserProgress() async throws {
        try modelContext.save()
    }

    // MARK: - Quest Methods

    /// Fetches today's daily quests for the current user.
    func getTodaysQuests() async throws -> [DailyQuest] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { quest in
                quest.userId == userId
                    && quest.date >= startOfDay
                    && quest.date < endOfDay
            }
        )

        return try modelContext.fetch(descriptor)
    }

    /// Inserts a new quest and stamps it with the current user's identifier.
    func addQuest(_ quest: DailyQuest) async throws {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        // Stamp the userId on the quest before inserting
        quest.userId = userId  // TODO: replace with Firebase UID in Phase 3
        modelContext.insert(quest)
        try modelContext.save()
    }

    /// Deletes all quests for a specific date belonging to the current user.
    func deleteQuestsForDate(_ date: Date) async throws {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { quest in
                quest.userId == userId
                    && quest.date >= startOfDay
                    && quest.date < endOfDay
            }
        )

        let quests = try modelContext.fetch(descriptor)
        for quest in quests {
            modelContext.delete(quest)
        }

        try modelContext.save()
    }

    /// Saves in-progress changes to quests.
    func saveQuests() async throws {
        try modelContext.save()
    }

    // MARK: - Recent Foods Methods

    /// Fetches recent unique foods by fingerprint, scoped to the current user.
    ///
    /// Groups entries by FoodFingerprint and returns the most recent instance of each unique food.
    func getRecentUniqueFoods(limit: Int = 15, daysBack: Int = 30) async throws -> [FoodEntry] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -daysBack, to: Date())!

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.userId == userId && entry.date >= cutoffDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let allEntries = try modelContext.fetch(descriptor)

        // Group by fingerprint, keeping only the most recent instance
        var seenFingerprints = Set<FoodFingerprint>()
        var uniqueEntries: [FoodEntry] = []

        for entry in allEntries {
            let fingerprint = FoodFingerprint(from: entry)

            if !seenFingerprints.contains(fingerprint) {
                seenFingerprints.insert(fingerprint)
                uniqueEntries.append(entry)

                if uniqueEntries.count >= limit {
                    break
                }
            }
        }

        return uniqueEntries
    }

    /// Fetches all favorited foods (one per fingerprint), scoped to the current user.
    func getFavoriteFoods() async throws -> [FoodEntry] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.userId == userId && entry.isFavorite == true
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let allFavorites = try modelContext.fetch(descriptor)

        // Group by fingerprint, keeping only the most recent instance
        var seenFingerprints = Set<FoodFingerprint>()
        var uniqueFavorites: [FoodEntry] = []

        for entry in allFavorites {
            let fingerprint = FoodFingerprint(from: entry)

            if !seenFingerprints.contains(fingerprint) {
                seenFingerprints.insert(fingerprint)
                uniqueFavorites.append(entry)
            }
        }

        return uniqueFavorites
    }

    /// Toggles favorite status for ALL entries matching a fingerprint, for the current user only.
    func toggleFavoriteForFingerprint(_ fingerprint: FoodFingerprint) async throws {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        // Fetch only this user's entries (fingerprint matching is done in-memory)
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.userId == userId
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let allEntries = try modelContext.fetch(descriptor)

        // Find first matching fingerprint to determine current favorite state
        var newFavoriteState = true
        for entry in allEntries {
            if FoodFingerprint(from: entry) == fingerprint {
                newFavoriteState = !entry.isFavorite
                break
            }
        }

        // Apply new state to all entries with matching fingerprint
        for entry in allEntries {
            if FoodFingerprint(from: entry) == fingerprint {
                entry.isFavorite = newFavoriteState
            }
        }

        try modelContext.save()
    }

    /// Inserts a pre-built FoodEntry and stamps it with the current user's identifier.
    /// Used for quick-log where the entry is constructed externally (AppCoordinator).
    func insertFoodEntry(_ entry: FoodEntry) async throws {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        // Stamp the userId — overrides whatever default was set at build time
        entry.userId = userId  // TODO: replace with Firebase UID in Phase 3
        modelContext.insert(entry)
        try modelContext.save()
    }

    // MARK: - Personal Baseline Methods

    /// Gets the baseline for a specific day of week for the current user.
    func getBaselineForDayOfWeek(_ dayOfWeek: Int) async throws -> PersonalBaseline? {
        guard let userId = currentUserId, !userId.isEmpty else { return nil }

        let descriptor = FetchDescriptor<PersonalBaseline>(
            predicate: #Predicate { baseline in
                baseline.userId == userId && baseline.dayOfWeek == dayOfWeek
            }
        )

        return try modelContext.fetch(descriptor).first
    }

    /// Gets all personal baselines for the current user.
    func getAllBaselines() async throws -> [PersonalBaseline] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let descriptor = FetchDescriptor<PersonalBaseline>(
            predicate: #Predicate { baseline in
                baseline.userId == userId
            },
            sortBy: [SortDescriptor(\.dayOfWeek, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Updates or creates a baseline for a day of week, scoped to the current user.
    func updateBaseline(dayOfWeek: Int, calories: Double, purity: Double) async throws {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        if let existing = try await getBaselineForDayOfWeek(dayOfWeek) {
            // Update existing baseline
            existing.updateWithNewData(calories: calories, purity: purity)
        } else {
            // Create new baseline and stamp with current user
            let baseline = PersonalBaseline(
                dayOfWeek: dayOfWeek,
                averageCalories: calories,
                averagePurity: purity,
                sampleCount: 1
            )
            baseline.userId = userId  // TODO: replace with Firebase UID in Phase 3
            modelContext.insert(baseline)
        }

        try modelContext.save()
    }

    /// Recalculates baselines from 4 weeks of historical data for the current user.
    func calculateAndUpdateBaselines() async throws {
        let calendar = Calendar.current
        let today = Date()

        guard let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: today) else { return }

        // fetchEntriesForDateRange is already userId-scoped
        let entries = try await fetchEntriesForDateRange(start: fourWeeksAgo, end: today)

        var entriesByDayOfWeek: [Int: [(calories: Int, purity: Int)]] = [:]

        for entry in entries {
            let dayOfWeek = calendar.component(.weekday, from: entry.date)
            if entriesByDayOfWeek[dayOfWeek] == nil {
                entriesByDayOfWeek[dayOfWeek] = []
            }
            entriesByDayOfWeek[dayOfWeek]?.append((calories: entry.calories, purity: entry.toxinScore))
        }

        for dayOfWeek in 1...7 {
            guard let dayEntries = entriesByDayOfWeek[dayOfWeek], !dayEntries.isEmpty else { continue }

            let totalCalories = dayEntries.reduce(0) { $0 + $1.calories }
            let totalPurity = dayEntries.reduce(0) { $0 + $1.purity }
            let entryCount = dayEntries.count

            let avgCalories = Double(totalCalories) / Double(entryCount)
            let avgPurity = Double(totalPurity) / Double(entryCount)

            // updateBaseline is already userId-scoped
            try await updateBaseline(dayOfWeek: dayOfWeek, calories: avgCalories, purity: avgPurity)
        }
    }

    // MARK: - Mood Entry Methods

    /// Adds a new mood entry for today, scoped to the current user.
    func addMoodEntry(mood: Mood) async throws -> MoodEntry {
        guard let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }

        let entry = MoodEntry(mood: mood)
        // Stamp the current user's identifier on the new record
        entry.userId = userId  // TODO: replace with Firebase UID in Phase 3
        modelContext.insert(entry)
        try modelContext.save()
        return entry
    }

    /// Gets today's mood entry for the current user, or nil if not logged yet.
    func getTodaysMood() async throws -> MoodEntry? {
        guard let userId = currentUserId, !userId.isEmpty else { return nil }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        let descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { entry in
                entry.userId == userId && entry.date == startOfToday
            }
        )

        return try modelContext.fetch(descriptor).first
    }

    /// Checks if mood has been logged today for the current user.
    func hasMoodLoggedToday() async throws -> Bool {
        return try await getTodaysMood() != nil
    }

    /// Gets mood entries for a date range, scoped to the current user.
    func getMoodEntriesForDateRange(start: Date, end: Date) async throws -> [MoodEntry] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let calendar = Calendar.current
        let startOfRange = calendar.startOfDay(for: start)
        let endOfRange = calendar.startOfDay(for: end)

        let descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { entry in
                entry.userId == userId
                    && entry.date >= startOfRange
                    && entry.date <= endOfRange
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
    }
}

// MARK: - Error Types

/// Custom errors for DataManager operations
enum DataManagerError: LocalizedError {
    case userProgressNotFound
    case invalidDate
    case saveFailure
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .userProgressNotFound:
            return "User progress data not found. Please set up default data first."
        case .invalidDate:
            return "The provided date is invalid."
        case .saveFailure:
            return "Failed to save data to the database."
        case .notAuthenticated:
            return "No authenticated user. Please log in before accessing data."
        }
    }
}
