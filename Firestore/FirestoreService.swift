//
//  FirestoreService.swift
//  HealthBar
//
//  Created by Claude on 3/24/26.
//

import Foundation

/// Defines the Firestore sync contract for cloud persistence.
///
/// Phase 1: FoodEntry
/// Phase 2: DailyGoal, PersonalBaseline, FoodFingerprint, MoodEntry
///
/// Implementations must guarantee:
/// - Exactly one active listener per model per user session
/// - All listener callbacks dispatched on MainActor
/// - Async/await interface (no callbacks in public API except the listener closures)
/// - stopAllListeners() stops every active listener across all models
protocol FirestoreService {

    // MARK: - FoodEntry (Phase 1)

    /// Uploads (creates or overwrites) a food entry in Firestore. Idempotent.
    func uploadFoodEntry(_ entry: FoodEntryDTO) async throws

    /// Permanently deletes a food entry document from Firestore.
    func deleteFoodEntry(id: String, userId: String) async throws

    /// One-time fetch of all food entries for a user. Used for initial sync on login.
    func fetchFoodEntries(userId: String) async throws -> [FoodEntryDTO]

    /// Starts a real-time listener for a user's food entries collection.
    /// Calling with the same userId when already active is a no-op.
    /// Calling with a different userId stops all existing listeners first.
    /// The `onUpdate` closure is always dispatched on MainActor.
    func listenForFoodEntries(userId: String, onUpdate: @escaping ([FoodEntryDTO]) -> Void)

    // MARK: - DailyGoal (Phase 2)

    /// Uploads (creates or overwrites) a daily goal in Firestore. Idempotent.
    func uploadDailyGoal(_ goal: DailyGoalDTO) async throws

    /// One-time fetch of all daily goals for a user. Used for initial sync on login.
    func fetchDailyGoals(userId: String) async throws -> [DailyGoalDTO]

    /// Starts a real-time listener for a user's daily goals collection.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForDailyGoals(userId: String, onUpdate: @escaping ([DailyGoalDTO]) -> Void)

    // MARK: - PersonalBaseline (Phase 2)

    /// Uploads (creates or overwrites) a personal baseline in Firestore. Idempotent.
    func uploadPersonalBaseline(_ baseline: PersonalBaselineDTO) async throws

    /// One-time fetch of all personal baselines for a user. Used for initial sync on login.
    func fetchPersonalBaselines(userId: String) async throws -> [PersonalBaselineDTO]

    /// Starts a real-time listener for a user's personal baselines collection.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForPersonalBaselines(userId: String, onUpdate: @escaping ([PersonalBaselineDTO]) -> Void)

    // MARK: - FoodFingerprint (Phase 2)

    /// Uploads (creates or overwrites) a food fingerprint in Firestore. Idempotent.
    func uploadFoodFingerprint(_ fingerprint: FoodFingerprintDTO) async throws

    /// Permanently deletes a food fingerprint document from Firestore.
    func deleteFoodFingerprint(id: String, userId: String) async throws

    /// One-time fetch of all food fingerprints for a user. Used for initial sync on login.
    func fetchFoodFingerprints(userId: String) async throws -> [FoodFingerprintDTO]

    /// Starts a real-time listener for a user's food fingerprints collection.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForFoodFingerprints(userId: String, onUpdate: @escaping ([FoodFingerprintDTO]) -> Void)

    // MARK: - MoodEntry (Phase 2)

    /// Uploads (creates or overwrites) a mood entry in Firestore. Idempotent.
    func uploadMoodEntry(_ entry: MoodEntryDTO) async throws

    /// Permanently deletes a mood entry document from Firestore.
    func deleteMoodEntry(id: String, userId: String) async throws

    /// One-time fetch of all mood entries for a user. Used for initial sync on login.
    func fetchMoodEntries(userId: String) async throws -> [MoodEntryDTO]

    /// Starts a real-time listener for a user's mood entries collection.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForMoodEntries(userId: String, onUpdate: @escaping ([MoodEntryDTO]) -> Void)

    // MARK: - UserProgress (Phase 3)

    /// Uploads (creates or overwrites) the single UserProgress document for a user. Idempotent.
    /// Firestore path: users/{userId}/userProgress/progress (fixed document ID "progress").
    func uploadUserProgress(_ progress: UserProgressDTO) async throws

    /// One-time fetch of the UserProgress document. Returns nil if no document exists yet.
    /// Used for initial sync on login.
    func fetchUserProgress(userId: String) async throws -> UserProgressDTO?

    /// Starts a real-time listener for the single UserProgress document.
    /// Delivers nil to the closure if the document does not exist.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForUserProgress(userId: String, onUpdate: @escaping (UserProgressDTO?) -> Void)

    // MARK: - DailyQuest (Phase 3)

    /// Uploads (creates or overwrites) a daily quest in Firestore. Idempotent.
    func uploadDailyQuest(_ quest: DailyQuestDTO) async throws

    /// One-time fetch of quests scoped to the current day + previous 7 days.
    /// Used for initial sync on login.
    func fetchDailyQuests(userId: String) async throws -> [DailyQuestDTO]

    /// Starts a real-time listener for a user's daily quests scoped to the past 7 days.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForDailyQuests(userId: String, onUpdate: @escaping ([DailyQuestDTO]) -> Void)

    // MARK: - UserProfile (Phase 4)

    /// Uploads (creates or overwrites) the single UserProfile document for a user. Idempotent.
    /// Firestore path: users/{userId}/profile/userProfile (fixed document ID "userProfile").
    func uploadUserProfile(_ profile: UserProfileDTO, userId: String) async throws

    /// One-time fetch of the UserProfile document. Returns nil if no document exists yet.
    func fetchUserProfile(userId: String) async throws -> UserProfileDTO?

    // MARK: - CustomFood (Phase 5)

    /// Uploads (creates or overwrites) a custom food in Firestore. Idempotent.
    func uploadCustomFood(_ food: CustomFoodDTO) async throws

    /// Permanently deletes a custom food document from Firestore.
    func deleteCustomFood(id: String, userId: String) async throws

    /// One-time fetch of all custom foods for a user. Used for initial sync on login.
    func fetchCustomFoods(userId: String) async throws -> [CustomFoodDTO]

    /// Starts a real-time listener for a user's custom foods collection.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForCustomFoods(userId: String, onUpdate: @escaping ([CustomFoodDTO]) -> Void)

    // MARK: - SavedMeal (Phase 5)

    /// Uploads (creates or overwrites) a saved meal in Firestore. Idempotent.
    func uploadSavedMeal(_ meal: SavedMealDTO) async throws

    /// Permanently deletes a saved meal document from Firestore.
    func deleteSavedMeal(id: String, userId: String) async throws

    /// One-time fetch of all saved meals for a user. Used for initial sync on login.
    func fetchSavedMeals(userId: String) async throws -> [SavedMealDTO]

    /// Starts a real-time listener for a user's saved meals collection.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForSavedMeals(userId: String, onUpdate: @escaping ([SavedMealDTO]) -> Void)

    // MARK: - SavedRecipe (Phase 5)

    /// Uploads (creates or overwrites) a saved recipe in Firestore. Idempotent.
    func uploadSavedRecipe(_ recipe: SavedRecipeDTO) async throws

    /// Permanently deletes a saved recipe document from Firestore.
    func deleteSavedRecipe(id: String, userId: String) async throws

    /// One-time fetch of all saved recipes for a user. Used for initial sync on login.
    func fetchSavedRecipes(userId: String) async throws -> [SavedRecipeDTO]

    /// Starts a real-time listener for a user's saved recipes collection.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForSavedRecipes(userId: String, onUpdate: @escaping ([SavedRecipeDTO]) -> Void)

    // MARK: - Lifecycle

    /// Stops every active listener across all models and clears the sync user.
    /// Safe to call when no listeners are active. Must be called on logout.
    func stopAllListeners()
}
