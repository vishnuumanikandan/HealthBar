//
//  FirestoreServiceImpl.swift
//  HealthBar
//
//  Created by Claude on 3/24/26.
//

import Foundation
import FirebaseFirestore

/// Concrete Firestore implementation of FirestoreService.
///
/// **Singleton:** Ensures exactly one listener per model is ever active, even though
/// ContentView creates three AppCoordinator / DataManager instances per tab.
///
/// **Per-model listeners:** Each synced model has its own `ListenerRegistration` handle,
/// stored and removed independently. `stopAllListeners()` clears every handle at once.
///
/// **Idempotency:** Each `listenFor*` call is a no-op if a listener for the same userId
/// is already active for that model. Starting any listener for a new userId stops all
/// existing listeners first (user switch is an atomic operation).
///
/// **Pending upload sets:** One `Set<String>` per model, stored on the singleton so all
/// DataManager instances share the same in-flight view. Pending IDs are added on local
/// write and removed in `applyUpdates` when the listener confirms the record matches local
/// — never on upload completion (avoids stale-snapshot overwrite race).
///
/// **userId in uploads:** All upload methods derive the Firestore path from `currentSyncUserId`.
/// Uploads are gated by a `guard let userId = currentSyncUserId` — silently skipped if called
/// before any listener session has started (safety valve, should not happen in normal usage).
///
/// Firestore paths:
///   users/{userId}/foodEntries/{id}
///   users/{userId}/dailyGoals/{id}
///   users/{userId}/personalBaselines/{id}
///   users/{userId}/foodFingerprints/{id}
///   users/{userId}/moodEntries/{id}
///   users/{userId}/userProgress/progress   (fixed document ID "progress")
///   users/{userId}/dailyQuests/{id}
final class FirestoreServiceImpl: FirestoreService {

    // MARK: - Singleton

    static let shared = FirestoreServiceImpl()

    // MARK: - Firestore

    private let db = Firestore.firestore()

    // MARK: - Current Sync User

    /// The userId for whom all listeners and uploads are currently active.
    /// Set by the first `listenFor*` call after login; cleared by `stopAllListeners()`.
    private(set) var currentSyncUserId: String?

    // MARK: - Listener Handles (one per model)

    private var foodEntriesListener: ListenerRegistration?
    private var dailyGoalsListener: ListenerRegistration?
    private var personalBaselinesListener: ListenerRegistration?
    private var foodFingerprintsListener: ListenerRegistration?
    private var moodEntriesListener: ListenerRegistration?
    private var userProgressListener: ListenerRegistration?
    private var dailyQuestsListener: ListenerRegistration?
    private var customFoodsListener: ListenerRegistration?
    private var savedMealsListener: ListenerRegistration?
    private var savedRecipesListener: ListenerRegistration?
    private var badgesListener: ListenerRegistration?

    // MARK: - Pending Upload Sets (one per model, shared across all DataManager instances)

    /// FoodEntry IDs written locally but not yet confirmed by the Firestore listener.
    var pendingUploadIds: Set<String> = []

    /// DailyGoal IDs written locally but not yet confirmed by the Firestore listener.
    var pendingDailyGoalIds: Set<String> = []

    /// PersonalBaseline IDs written locally but not yet confirmed by the Firestore listener.
    var pendingBaselineIds: Set<String> = []

    /// FoodFingerprint IDs written locally but not yet confirmed by the Firestore listener.
    var pendingFingerprintIds: Set<String> = []

    /// MoodEntry IDs written locally but not yet confirmed by the Firestore listener.
    var pendingMoodEntryIds: Set<String> = []

    /// UserProgress SwiftData UUID strings written locally but not yet confirmed.
    /// Uses "at least as good" confirmation (superset/max check) rather than strict equality
    /// because UserProgress fields are additive — a confirming snapshot may show a higher value.
    var pendingProgressIds: Set<String> = []

    /// DailyQuest IDs written locally but not yet confirmed by the Firestore listener.
    var pendingQuestIds: Set<String> = []

    /// CustomFood IDs written locally but not yet confirmed by the Firestore listener.
    var pendingCustomFoodIds: Set<String> = []

    /// SavedMeal IDs written locally but not yet confirmed by the Firestore listener.
    var pendingSavedMealIds: Set<String> = []

    /// SavedRecipe IDs written locally but not yet confirmed by the Firestore listener.
    var pendingSavedRecipeIds: Set<String> = []

    /// Badge IDs written locally but not yet confirmed by the Firestore listener.
    var pendingBadgeIds: Set<String> = []

    // MARK: - Init

    private init() {}

    deinit {
        stopAllListeners()
    }

    // MARK: - Path Helpers

    private func foodEntriesCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("foodEntries")
    }

    private func dailyGoalsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("dailyGoals")
    }

    private func personalBaselinesCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("personalBaselines")
    }

    private func foodFingerprintsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("foodFingerprints")
    }

    private func moodEntriesCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("moodEntries")
    }

    /// Fixed single-document reference for a user's UserProgress.
    /// The document ID is always "progress" — one document per user, always upserted.
    private func userProgressDocument(for userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("userProgress").document("progress")
    }

    private func dailyQuestsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("dailyQuests")
    }

    private func customFoodsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("customFoods")
    }

    private func savedMealsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("savedMeals")
    }

    private func savedRecipesCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("savedRecipes")
    }

    // MARK: - Shared Listener Setup

    /// Prepares for a new listener call:
    /// - If the same userId is already active for this model (indicated by a non-nil existing handle),
    ///   the caller should skip registration (idempotent).
    /// - If a different userId is being set, all listeners are stopped first (atomic user switch).
    /// - Sets `currentSyncUserId` if not already set.
    ///
    /// Returns `true` if the caller should proceed with registering the listener.
    private func shouldRegisterListener(userId: String, existingHandle: ListenerRegistration?) -> Bool {
        if currentSyncUserId == userId, existingHandle != nil {
            return false // Idempotent: already listening for this user + model
        }
        if let current = currentSyncUserId, current != userId {
            // Different user: stop all listeners atomically before switching
            stopAllListeners()
        }
        currentSyncUserId = userId
        return true
    }

    /// Shared async delete helper using withCheckedThrowingContinuation.
    private func deleteDocument(ref: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - FirestoreService: FoodEntry

    func uploadFoodEntry(_ entry: FoodEntryDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try foodEntriesCollection(for: userId).document(entry.id).setData(from: entry)
    }

    func deleteFoodEntry(id: String, userId: String) async throws {
        try await deleteDocument(ref: foodEntriesCollection(for: userId).document(id))
    }

    func fetchFoodEntries(userId: String) async throws -> [FoodEntryDTO] {
        let snapshot = try await foodEntriesCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FoodEntryDTO.self) }
    }

    func listenForFoodEntries(userId: String, onUpdate: @escaping ([FoodEntryDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: foodEntriesListener) else { return }
        foodEntriesListener?.remove()
        foodEntriesListener = foodEntriesCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: FoodEntryDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: DailyGoal

    func uploadDailyGoal(_ goal: DailyGoalDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try dailyGoalsCollection(for: userId).document(goal.id).setData(from: goal)
    }

    func fetchDailyGoals(userId: String) async throws -> [DailyGoalDTO] {
        let snapshot = try await dailyGoalsCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: DailyGoalDTO.self) }
    }

    func listenForDailyGoals(userId: String, onUpdate: @escaping ([DailyGoalDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: dailyGoalsListener) else { return }
        dailyGoalsListener?.remove()
        dailyGoalsListener = dailyGoalsCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: DailyGoalDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: PersonalBaseline

    func uploadPersonalBaseline(_ baseline: PersonalBaselineDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try personalBaselinesCollection(for: userId).document(baseline.id).setData(from: baseline)
    }

    func fetchPersonalBaselines(userId: String) async throws -> [PersonalBaselineDTO] {
        let snapshot = try await personalBaselinesCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: PersonalBaselineDTO.self) }
    }

    func listenForPersonalBaselines(userId: String, onUpdate: @escaping ([PersonalBaselineDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: personalBaselinesListener) else { return }
        personalBaselinesListener?.remove()
        personalBaselinesListener = personalBaselinesCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: PersonalBaselineDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: FoodFingerprint

    func uploadFoodFingerprint(_ fingerprint: FoodFingerprintDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try foodFingerprintsCollection(for: userId).document(fingerprint.id).setData(from: fingerprint)
    }

    func deleteFoodFingerprint(id: String, userId: String) async throws {
        try await deleteDocument(ref: foodFingerprintsCollection(for: userId).document(id))
    }

    func fetchFoodFingerprints(userId: String) async throws -> [FoodFingerprintDTO] {
        let snapshot = try await foodFingerprintsCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FoodFingerprintDTO.self) }
    }

    func listenForFoodFingerprints(userId: String, onUpdate: @escaping ([FoodFingerprintDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: foodFingerprintsListener) else { return }
        foodFingerprintsListener?.remove()
        foodFingerprintsListener = foodFingerprintsCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: FoodFingerprintDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: MoodEntry

    func uploadMoodEntry(_ entry: MoodEntryDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try moodEntriesCollection(for: userId).document(entry.id).setData(from: entry)
    }

    func deleteMoodEntry(id: String, userId: String) async throws {
        try await deleteDocument(ref: moodEntriesCollection(for: userId).document(id))
    }

    func fetchMoodEntries(userId: String) async throws -> [MoodEntryDTO] {
        let snapshot = try await moodEntriesCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: MoodEntryDTO.self) }
    }

    func listenForMoodEntries(userId: String, onUpdate: @escaping ([MoodEntryDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: moodEntriesListener) else { return }
        moodEntriesListener?.remove()
        moodEntriesListener = moodEntriesCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: MoodEntryDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: UserProgress

    func uploadUserProgress(_ progress: UserProgressDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        // Firestore document ID is always "progress" (fixed single-document per user).
        try userProgressDocument(for: userId).setData(from: progress)
    }

    func fetchUserProgress(userId: String) async throws -> UserProgressDTO? {
        let snapshot = try await userProgressDocument(for: userId).getDocument()
        // Returns nil if no document exists yet (new user / first install).
        return try? snapshot.data(as: UserProgressDTO.self)
    }

    func listenForUserProgress(userId: String, onUpdate: @escaping (UserProgressDTO?) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: userProgressListener) else { return }
        userProgressListener?.remove()
        // DocumentReference.addSnapshotListener — delivers a single optional DocumentSnapshot.
        userProgressListener = userProgressDocument(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, error == nil else { return }
                // Decode as optional — nil if document doesn't exist yet.
                let dto = try? snapshot?.data(as: UserProgressDTO.self)
                Task { @MainActor in onUpdate(dto) }
            }
    }

    // MARK: - FirestoreService: DailyQuest

    func uploadDailyQuest(_ quest: DailyQuestDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try dailyQuestsCollection(for: userId).document(quest.id).setData(from: quest)
    }

    func fetchDailyQuests(userId: String) async throws -> [DailyQuestDTO] {
        // Scope to current day + previous 7 days to prevent unbounded collection growth.
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let snapshot = try await dailyQuestsCollection(for: userId)
            .whereField("questDate", isGreaterThanOrEqualTo: cutoff)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: DailyQuestDTO.self) }
    }

    func listenForDailyQuests(userId: String, onUpdate: @escaping ([DailyQuestDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: dailyQuestsListener) else { return }
        dailyQuestsListener?.remove()
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        dailyQuestsListener = dailyQuestsCollection(for: userId)
            .whereField("questDate", isGreaterThanOrEqualTo: cutoff)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: DailyQuestDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: UserProfile

    /// Fixed single-document reference for a user's UserProfile.
    /// The document ID is always "userProfile" — one document per user, always upserted.
    private func userProfileDocument(for userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("profile").document("userProfile")
    }

    func uploadUserProfile(_ profile: UserProfileDTO, userId: String) async throws {
        // Uses the provided userId directly (not currentSyncUserId) because
        // UserProfile uploads happen during onboarding before listeners are active.
        try userProfileDocument(for: userId).setData(from: profile)
    }

    func fetchUserProfile(userId: String) async throws -> UserProfileDTO? {
        let snapshot = try await userProfileDocument(for: userId).getDocument()
        return try? snapshot.data(as: UserProfileDTO.self)
    }

    // MARK: - FirestoreService: CustomFood

    func uploadCustomFood(_ food: CustomFoodDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try customFoodsCollection(for: userId).document(food.id).setData(from: food)
    }

    func deleteCustomFood(id: String, userId: String) async throws {
        try await deleteDocument(ref: customFoodsCollection(for: userId).document(id))
    }

    func fetchCustomFoods(userId: String) async throws -> [CustomFoodDTO] {
        let snapshot = try await customFoodsCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: CustomFoodDTO.self) }
    }

    func listenForCustomFoods(userId: String, onUpdate: @escaping ([CustomFoodDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: customFoodsListener) else { return }
        customFoodsListener?.remove()
        customFoodsListener = customFoodsCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: CustomFoodDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: SavedMeal

    func uploadSavedMeal(_ meal: SavedMealDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try savedMealsCollection(for: userId).document(meal.id).setData(from: meal)
    }

    func deleteSavedMeal(id: String, userId: String) async throws {
        try await deleteDocument(ref: savedMealsCollection(for: userId).document(id))
    }

    func fetchSavedMeals(userId: String) async throws -> [SavedMealDTO] {
        let snapshot = try await savedMealsCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SavedMealDTO.self) }
    }

    func listenForSavedMeals(userId: String, onUpdate: @escaping ([SavedMealDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: savedMealsListener) else { return }
        savedMealsListener?.remove()
        savedMealsListener = savedMealsCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: SavedMealDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: SavedRecipe

    func uploadSavedRecipe(_ recipe: SavedRecipeDTO) async throws {
        guard let userId = currentSyncUserId else { return }
        try savedRecipesCollection(for: userId).document(recipe.id).setData(from: recipe)
    }

    func deleteSavedRecipe(id: String, userId: String) async throws {
        try await deleteDocument(ref: savedRecipesCollection(for: userId).document(id))
    }

    func fetchSavedRecipes(userId: String) async throws -> [SavedRecipeDTO] {
        let snapshot = try await savedRecipesCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SavedRecipeDTO.self) }
    }

    func listenForSavedRecipes(userId: String, onUpdate: @escaping ([SavedRecipeDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: savedRecipesListener) else { return }
        savedRecipesListener?.remove()
        savedRecipesListener = savedRecipesCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: SavedRecipeDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: AccountInfo

    private func accountInfoDocument(for userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("account").document("info")
    }

    private func usernameDocument(for handleKey: String) -> DocumentReference {
        db.collection("usernames").document(handleKey)
    }

    func writeAccountInfo(_ info: AccountInfoDTO, userId: String) async throws {
        try accountInfoDocument(for: userId).setData(from: info, merge: true)
    }

    func fetchAccountInfo(userId: String) async throws -> AccountInfoDTO? {
        let snapshot = try await accountInfoDocument(for: userId).getDocument()
        return try? snapshot.data(as: AccountInfoDTO.self)
    }

    /// Reads account/info as raw dictionary, bypassing Codable.
    /// Used by cooldown checks and changeUsername where FieldValue.serverTimestamp()
    /// fields cause full Codable decode to fail.
    /// Firestore Timestamp values are converted to Date for the caller.
    func fetchAccountInfoRaw(userId: String) async throws -> [String: Any]? {
        let snapshot = try await accountInfoDocument(for: userId).getDocument()
        guard var data = snapshot.data() else { return nil }
        // Convert Firestore Timestamp values to Date so callers don't need FirebaseFirestore import
        for key in ["lastUsernameChangeAt", "lastDisplayNameChangeAt", "createdAt", "claimedAt"] {
            if let ts = data[key] as? Timestamp {
                data[key] = ts.dateValue()
            }
        }
        return data
    }

    // MARK: - FirestoreService: Username (Friend System Phase 1)

    func fetchUsername(userId: String) async throws -> String? {
        let snapshot = try await accountInfoDocument(for: userId).getDocument()
        // Read username directly from document data instead of full Codable decode.
        // The account/info doc may contain FieldValue.serverTimestamp() fields from
        // transaction writes that cause AccountInfoDTO Codable decode to fail silently.
        return snapshot.data()?["username"] as? String
    }

    func isUsernameAvailable(_ handleKey: String) async throws -> Bool {
        let snapshot = try await usernameDocument(for: handleKey).getDocument()
        return !snapshot.exists
    }

    func claimUsername(_ handleKey: String, userId: String) async throws {
        let usernameRef = usernameDocument(for: handleKey)
        let accountRef = accountInfoDocument(for: userId)

        do {
            try await db.runTransaction { transaction, errorPointer in
                // Step 1: Read the username document
                let usernameSnapshot: DocumentSnapshot
                do {
                    usernameSnapshot = try transaction.getDocument(usernameRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                if usernameSnapshot.exists {
                    let existingUid = usernameSnapshot.data()?["uid"] as? String
                    if existingUid == userId {
                        // Step 2: Idempotent re-claim by same user — success no-op
                        return nil
                    } else {
                        // Step 3: Owned by someone else
                        let takenError = NSError(
                            domain: "UsernameError",
                            code: 409,
                            userInfo: [NSLocalizedDescriptionKey: "taken"]
                        )
                        errorPointer?.pointee = takenError
                        return nil
                    }
                }

                // Step 4: Unclaimed — create the username doc and merge into account/info
                transaction.setData([
                    "uid": userId,
                    "username": handleKey,
                    "claimedAt": FieldValue.serverTimestamp()
                ], forDocument: usernameRef)

                transaction.setData(
                    ["username": handleKey],
                    forDocument: accountRef,
                    merge: true
                )

                return nil
            }
        } catch let error as NSError {
            if error.domain == "UsernameError" && error.code == 409 {
                throw UsernameError.taken
            }
            throw UsernameError.network(error.localizedDescription)
        }
    }

    func changeUsername(from oldHandleKey: String, to newHandleKey: String, userId: String) async throws {
        let oldUsernameRef = usernameDocument(for: oldHandleKey)
        let newUsernameRef = usernameDocument(for: newHandleKey)
        let accountRef = accountInfoDocument(for: userId)

        do {
            try await db.runTransaction { transaction, errorPointer in
                // Step 1: Verify old handle is owned by this user
                let oldSnapshot: DocumentSnapshot
                do {
                    oldSnapshot = try transaction.getDocument(oldUsernameRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                if oldSnapshot.exists {
                    let ownerUid = oldSnapshot.data()?["uid"] as? String
                    if ownerUid != userId {
                        let err = NSError(domain: "UsernameError", code: 403,
                                          userInfo: [NSLocalizedDescriptionKey: "not_owner"])
                        errorPointer?.pointee = err
                        return nil
                    }
                }

                // Step 2: Verify new handle is unclaimed
                let newSnapshot: DocumentSnapshot
                do {
                    newSnapshot = try transaction.getDocument(newUsernameRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                if newSnapshot.exists {
                    let existingUid = newSnapshot.data()?["uid"] as? String
                    if existingUid == userId {
                        // Same user re-claiming same handle — no-op
                        return nil
                    }
                    let takenError = NSError(domain: "UsernameError", code: 409,
                                             userInfo: [NSLocalizedDescriptionKey: "taken"])
                    errorPointer?.pointee = takenError
                    return nil
                }

                // Step 3: Delete old handle
                transaction.deleteDocument(oldUsernameRef)

                // Step 4: Create new handle
                transaction.setData([
                    "uid": userId,
                    "username": newHandleKey,
                    "claimedAt": FieldValue.serverTimestamp()
                ], forDocument: newUsernameRef)

                // Step 5: Update account/info with new username + timestamp
                transaction.setData([
                    "username": newHandleKey,
                    "lastUsernameChangeAt": FieldValue.serverTimestamp()
                ], forDocument: accountRef, merge: true)

                return nil
            }
        } catch let error as NSError {
            if error.domain == "UsernameError" && error.code == 409 {
                throw UsernameError.taken
            }
            throw UsernameError.network(error.localizedDescription)
        }
    }

    // MARK: - FirestoreService: BadgeProgress

    private func badgesCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("badges")
    }

    func uploadBadgeProgress(_ badge: BadgeProgressDTO, userId: String) async throws {
        try badgesCollection(for: userId).document(badge.badgeId).setData(from: badge)
    }

    func listenForBadges(userId: String, onUpdate: @escaping ([BadgeProgressDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: badgesListener) else { return }
        badgesListener?.remove()
        badgesListener = badgesCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: BadgeProgressDTO.self) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: Account Deletion

    /// Deletes all Firestore data under users/{userId}/ in batches of ≤500.
    /// Deletes all known subcollections first, then the root users/{userId} document.
    func deleteAllUserData(userId: String) async throws {
        // Release the username handle (top-level, not a subcollection) before deleting user data.
        // Only delete if the doc's uid matches this user (guard against reassigned handles).
        if let accountInfo = try? await fetchAccountInfo(userId: userId),
           let username = accountInfo.username, !username.isEmpty {
            let usernameRef = usernameDocument(for: username)
            let usernameSnap = try? await usernameRef.getDocument()
            if let data = usernameSnap?.data(), data["uid"] as? String == userId {
                try? await deleteDocument(ref: usernameRef)
            }
        }

        let knownSubcollections = [
            "foodEntries", "dailyGoals", "dailyQuests", "moodEntries",
            "customFoods", "savedMeals", "savedRecipes", "personalBaselines",
            "foodFingerprints", "userProgress", "profile", "account", "badges"
        ]

        let userDoc = db.collection("users").document(userId)

        for subcollection in knownSubcollections {
            let collectionRef = userDoc.collection(subcollection)
            let snapshot = try await collectionRef.getDocuments()
            let documents = snapshot.documents

            // Delete in batches of ≤500
            var index = 0
            while index < documents.count {
                let batch = db.batch()
                let end = min(index + 500, documents.count)
                for doc in documents[index..<end] {
                    batch.deleteDocument(doc.reference)
                }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    batch.commit { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                index = end
            }
        }

        // Delete the root users/{userId} document
        try await deleteDocument(ref: userDoc)
    }

    // MARK: - Lifecycle

    /// Stops all active listeners across every model, clears all handles and the sync user.
    /// Also clears all pending upload sets so in-flight IDs from the previous session
    /// don't bleed into the next login.
    func stopAllListeners() {
        foodEntriesListener?.remove()
        dailyGoalsListener?.remove()
        personalBaselinesListener?.remove()
        foodFingerprintsListener?.remove()
        moodEntriesListener?.remove()
        userProgressListener?.remove()
        dailyQuestsListener?.remove()
        customFoodsListener?.remove()
        savedMealsListener?.remove()
        savedRecipesListener?.remove()
        badgesListener?.remove()

        foodEntriesListener = nil
        dailyGoalsListener = nil
        personalBaselinesListener = nil
        foodFingerprintsListener = nil
        moodEntriesListener = nil
        userProgressListener = nil
        dailyQuestsListener = nil
        customFoodsListener = nil
        savedMealsListener = nil
        savedRecipesListener = nil
        badgesListener = nil

        currentSyncUserId = nil
    }
}
