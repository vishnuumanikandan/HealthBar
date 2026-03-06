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
    ///   - mealType: Meal category (breakfast/lunch/dinner/snack)
    ///   - fiber: Optional fiber in grams
    ///   - sugar: Optional sugar in grams
    ///   - sodium: Optional sodium in milligrams
    ///   - saturatedFat: Optional saturated fat in grams
    ///   - cholesterol: Optional cholesterol in milligrams
    ///   - potassium: Optional potassium in milligrams
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

        let descriptor = FetchDescriptor<FoodEntry>(
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

        let descriptor = FetchDescriptor<FoodEntry>(
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
        let descriptor = FetchDescriptor<FoodEntry>(
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
            // Create new goal for today
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

        let descriptor = FetchDescriptor<DailyQuest>(
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

        let descriptor = FetchDescriptor<DailyQuest>(
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

    // MARK: - Recent Foods Methods

    /// Fetches recent unique foods by fingerprint
    ///
    /// Groups entries by FoodFingerprint and returns the most recent instance of each unique food.
    /// Useful for "Recent Foods" quick-log feature.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of unique foods to return (default 15)
    ///   - daysBack: Number of days to look back (default 30)
    /// - Returns: Array of FoodEntry objects, one per unique fingerprint, sorted by most recent
    func getRecentUniqueFoods(limit: Int = 15, daysBack: Int = 30) async throws -> [FoodEntry] {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -daysBack, to: Date())!

        // Fetch all entries from the last N days, sorted by date descending
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.date >= cutoffDate
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

    /// Fetches all favorited foods (one per fingerprint)
    ///
    /// Returns the most recent instance of each unique favorited food.
    ///
    /// - Returns: Array of FoodEntry objects where isFavorite == true, one per fingerprint
    func getFavoriteFoods() async throws -> [FoodEntry] {
        // Fetch all favorited entries, sorted by date descending
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in
                entry.isFavorite == true
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

    /// Toggles favorite status for ALL entries matching a fingerprint
    ///
    /// This makes the FOOD favorite, not just individual log instances.
    /// When user favorites "Chicken Salad (450cal, 30g protein...)",
    /// all entries with the same fingerprint become favorited.
    ///
    /// - Parameter fingerprint: The food fingerprint to toggle
    func toggleFavoriteForFingerprint(_ fingerprint: FoodFingerprint) async throws {
        // Fetch all entries (we need to check fingerprints manually)
        let descriptor = FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let allEntries = try modelContext.fetch(descriptor)

        // Find first entry with matching fingerprint to determine current state
        var newFavoriteState = true
        for entry in allEntries {
            if FoodFingerprint(from: entry) == fingerprint {
                newFavoriteState = !entry.isFavorite
                break
            }
        }

        // Update all entries with matching fingerprint
        for entry in allEntries {
            if FoodFingerprint(from: entry) == fingerprint {
                entry.isFavorite = newFavoriteState
            }
        }

        try modelContext.save()
    }

    /// Adds a food entry directly (used for quick-log)
    ///
    /// - Parameter entry: The FoodEntry to insert
    func insertFoodEntry(_ entry: FoodEntry) async throws {
        modelContext.insert(entry)
        try modelContext.save()
    }

    // MARK: - Personal Baseline Methods

    /// Gets the baseline for a specific day of week
    /// - Parameter dayOfWeek: Day of week (1 = Sunday, 7 = Saturday)
    /// - Returns: The PersonalBaseline or nil if not found
    func getBaselineForDayOfWeek(_ dayOfWeek: Int) async throws -> PersonalBaseline? {
        let descriptor = FetchDescriptor<PersonalBaseline>(
            predicate: #Predicate { baseline in
                baseline.dayOfWeek == dayOfWeek
            }
        )

        return try modelContext.fetch(descriptor).first
    }

    /// Gets all personal baselines
    /// - Returns: Array of all PersonalBaseline objects (up to 7)
    func getAllBaselines() async throws -> [PersonalBaseline] {
        let descriptor = FetchDescriptor<PersonalBaseline>(
            sortBy: [SortDescriptor(\.dayOfWeek, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Updates or creates a baseline for a day of week
    /// - Parameters:
    ///   - dayOfWeek: Day of week (1-7)
    ///   - calories: Today's total calories
    ///   - purity: Today's total purity score
    func updateBaseline(dayOfWeek: Int, calories: Double, purity: Double) async throws {
        if let existing = try await getBaselineForDayOfWeek(dayOfWeek) {
            // Update existing baseline
            existing.updateWithNewData(calories: calories, purity: purity)
        } else {
            // Create new baseline
            let baseline = PersonalBaseline(
                dayOfWeek: dayOfWeek,
                averageCalories: calories,
                averagePurity: purity,
                sampleCount: 1
            )
            modelContext.insert(baseline)
        }

        try modelContext.save()
    }

    /// Calculates and updates baselines from historical data (rolling 4-week)
    ///
    /// Call this periodically (e.g., at end of day) to keep baselines updated.
    func calculateAndUpdateBaselines() async throws {
        let calendar = Calendar.current
        let today = Date()

        // Get entries from the past 4 weeks
        guard let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: today) else { return }

        let entries = try await fetchEntriesForDateRange(start: fourWeeksAgo, end: today)

        // Group entries by day of week
        var entriesByDayOfWeek: [Int: [(calories: Int, purity: Int)]] = [:]

        for entry in entries {
            let dayOfWeek = calendar.component(.weekday, from: entry.date)
            if entriesByDayOfWeek[dayOfWeek] == nil {
                entriesByDayOfWeek[dayOfWeek] = []
            }
            entriesByDayOfWeek[dayOfWeek]?.append((calories: entry.calories, purity: entry.toxinScore))
        }

        // Calculate averages and update baselines
        for dayOfWeek in 1...7 {
            guard let dayEntries = entriesByDayOfWeek[dayOfWeek], !dayEntries.isEmpty else { continue }

            // Group by actual date to get daily totals (not per-entry)
            let totalCalories = dayEntries.reduce(0) { $0 + $1.calories }
            let totalPurity = dayEntries.reduce(0) { $0 + $1.purity }
            let entryCount = dayEntries.count

            let avgCalories = Double(totalCalories) / Double(entryCount)
            let avgPurity = Double(totalPurity) / Double(entryCount)

            try await updateBaseline(dayOfWeek: dayOfWeek, calories: avgCalories, purity: avgPurity)
        }
    }

    // MARK: - Mood Entry Methods

    /// Adds a new mood entry for today
    /// - Parameter mood: The user's mood
    /// - Returns: The created MoodEntry
    func addMoodEntry(mood: Mood) async throws -> MoodEntry {
        let entry = MoodEntry(mood: mood)
        modelContext.insert(entry)
        try modelContext.save()
        return entry
    }

    /// Gets today's mood entry if one exists
    /// - Returns: The MoodEntry for today, or nil if not logged yet
    func getTodaysMood() async throws -> MoodEntry? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        let descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { entry in
                entry.date == startOfToday
            }
        )

        return try modelContext.fetch(descriptor).first
    }

    /// Checks if mood has been logged today
    /// - Returns: True if mood already logged for today
    func hasMoodLoggedToday() async throws -> Bool {
        return try await getTodaysMood() != nil
    }

    /// Gets mood entries for a date range
    /// - Parameters:
    ///   - start: Start date
    ///   - end: End date
    /// - Returns: Array of MoodEntry objects
    func getMoodEntriesForDateRange(start: Date, end: Date) async throws -> [MoodEntry] {
        let calendar = Calendar.current
        let startOfRange = calendar.startOfDay(for: start)
        let endOfRange = calendar.startOfDay(for: end)

        let descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { entry in
                entry.date >= startOfRange && entry.date <= endOfRange
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
