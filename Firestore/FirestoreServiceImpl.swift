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
    private var friendsListener: ListenerRegistration?
    private var incomingRequestsListener: ListenerRegistration?
    private var sentRequestsListener: ListenerRegistration?

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

    private func friendsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("friends")
    }

    private func incomingRequestsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("friendRequests")
    }

    private func sentRequestsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("sentRequests")
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

    private func loginHandleDocument(for handleKey: String) -> DocumentReference {
        db.collection("loginHandles").document(handleKey)
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

    // MARK: - FirestoreService: Username Login Mapping

    func lookupLoginEmail(forHandleKey handleKey: String) async throws -> String? {
        let snapshot = try await loginHandleDocument(for: handleKey).getDocument()
        guard snapshot.exists else { return nil }
        return snapshot.data()?["email"] as? String
    }

    func upsertLoginHandle(handleKey: String, uid: String, email: String) async throws {
        try await loginHandleDocument(for: handleKey).setData([
            "uid": uid,
            "email": email
        ])
    }

    func deleteLoginHandle(handleKey: String, uid: String) async throws {
        // Owner guard mirrors the usernames release: only delete a mapping
        // that points at this uid (never clobber a reassigned handle).
        let ref = loginHandleDocument(for: handleKey)
        let snapshot = try await ref.getDocument()
        guard let data = snapshot.data(), data["uid"] as? String == uid else { return }
        try await deleteDocument(ref: ref)
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

    // MARK: - FirestoreService: Friends (Phase 2)

    /// Commits a WriteBatch via withCheckedThrowingContinuation, mapping any
    /// commit failure to FriendError.network (mirrors the deleteDocument style).
    private func commitFriendBatch(_ batch: WriteBatch) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                batch.commit { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            throw FriendError.network(error.localizedDescription)
        }
    }

    func lookupUid(forHandleKey handleKey: String) async throws -> String? {
        let snapshot = try await usernameDocument(for: handleKey).getDocument()
        guard snapshot.exists else { return nil }
        return snapshot.data()?["uid"] as? String
    }

    func incomingRequestExists(meUid: String, fromUid: String) async throws -> Bool {
        let snapshot = try await incomingRequestsCollection(for: meUid).document(fromUid).getDocument()
        return snapshot.exists
    }

    func outgoingRequestExists(meUid: String, toUid: String) async throws -> Bool {
        let snapshot = try await sentRequestsCollection(for: meUid).document(toUid).getDocument()
        return snapshot.exists
    }

    func friendExists(meUid: String, friendUid: String) async throws -> Bool {
        let snapshot = try await friendsCollection(for: meUid).document(friendUid).getDocument()
        return snapshot.exists
    }

    func fetchAllUsernames() async throws -> [DirectoryUser] {
        // Document ID == handleKey, so ordering by ID is alphabetical by username.
        let snapshot = try await db.collection("usernames")
            .order(by: FieldPath.documentID())
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            guard let uid = doc.data()["uid"] as? String else { return nil }
            let claimedAt = (doc.data()["claimedAt"] as? Timestamp)?.dateValue()
            return DirectoryUser(uid: uid, username: doc.documentID, claimedAt: claimedAt)
        }
    }

    func sendFriendRequest(toUid: String, toUsername: String,
                           fromUid: String, fromUsername: String, fromDisplayName: String) async throws {
        let batch = db.batch()
        batch.setData([
            "fromUid": fromUid,
            "fromUsername": fromUsername,
            "fromDisplayName": fromDisplayName,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: incomingRequestsCollection(for: toUid).document(fromUid))
        batch.setData([
            "toUid": toUid,
            "toUsername": toUsername,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: sentRequestsCollection(for: fromUid).document(toUid))
        try await commitFriendBatch(batch)
    }

    func acceptFriendRequest(fromUid: String, fromUsername: String, fromDisplayName: String,
                             meUid: String, meUsername: String, meDisplayName: String) async throws {
        let batch = db.batch()
        // Both friend edges — each side stamped with the counterparty's identity.
        batch.setData([
            "friendUid": fromUid,
            "friendUsername": fromUsername,
            "friendDisplayName": fromDisplayName,
            "since": FieldValue.serverTimestamp()
        ], forDocument: friendsCollection(for: meUid).document(fromUid))
        batch.setData([
            "friendUid": meUid,
            "friendUsername": meUsername,
            "friendDisplayName": meDisplayName,
            "since": FieldValue.serverTimestamp()
        ], forDocument: friendsCollection(for: fromUid).document(meUid))
        // The request being accepted.
        batch.deleteDocument(incomingRequestsCollection(for: meUid).document(fromUid))
        batch.deleteDocument(sentRequestsCollection(for: fromUid).document(meUid))
        // The reverse pair from a simultaneous cross-send (no-op if absent).
        batch.deleteDocument(incomingRequestsCollection(for: fromUid).document(meUid))
        batch.deleteDocument(sentRequestsCollection(for: meUid).document(fromUid))
        try await commitFriendBatch(batch)
    }

    func declineFriendRequest(fromUid: String, meUid: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(incomingRequestsCollection(for: meUid).document(fromUid))
        batch.deleteDocument(sentRequestsCollection(for: fromUid).document(meUid))
        try await commitFriendBatch(batch)
    }

    func cancelSentRequest(toUid: String, meUid: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(sentRequestsCollection(for: meUid).document(toUid))
        batch.deleteDocument(incomingRequestsCollection(for: toUid).document(meUid))
        try await commitFriendBatch(batch)
    }

    func removeFriend(friendUid: String, meUid: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(friendsCollection(for: meUid).document(friendUid))
        batch.deleteDocument(friendsCollection(for: friendUid).document(meUid))
        try await commitFriendBatch(batch)
    }

    func listenForFriends(userId: String, onUpdate: @escaping ([FriendDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: friendsListener) else { return }
        friendsListener?.remove()
        friendsListener = friendsCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                // .estimate resolves not-yet-committed FieldValue.serverTimestamp()
                // values so locally pending writes still decode.
                let dtos = snapshot.documents.compactMap { try? $0.data(as: FriendDTO.self, with: .estimate) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    func listenForIncomingRequests(userId: String, onUpdate: @escaping ([IncomingRequestDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: incomingRequestsListener) else { return }
        incomingRequestsListener?.remove()
        incomingRequestsListener = incomingRequestsCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: IncomingRequestDTO.self, with: .estimate) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    func listenForSentRequests(userId: String, onUpdate: @escaping ([SentRequestDTO]) -> Void) {
        guard shouldRegisterListener(userId: userId, existingHandle: sentRequestsListener) else { return }
        sentRequestsListener?.remove()
        sentRequestsListener = sentRequestsCollection(for: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard self != nil, let snapshot, error == nil else { return }
                let dtos = snapshot.documents.compactMap { try? $0.data(as: SentRequestDTO.self, with: .estimate) }
                Task { @MainActor in onUpdate(dtos) }
            }
    }

    // MARK: - FirestoreService: Public Stats (Friend System Phase 3)

    /// Fixed single-document reference for a user's public stats projection.
    /// The document ID is always "stats" — one friend-readable doc per user.
    private func publicStatsDocument(for userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("public").document("stats")
    }

    func publishPublicStats(_ stats: PublicStatsDTO, userId: String) async throws {
        // Merge so a future added field never clobbers existing ones — same
        // clobber protection as writeAccountInfo.
        try publicStatsDocument(for: userId).setData(from: stats, merge: true)
    }

    func fetchPublicStats(friendUid: String) async throws -> PublicStatsDTO? {
        do {
            let snapshot = try await publicStatsDocument(for: friendUid).getDocument()
            guard snapshot.exists else { return nil }
            return try? snapshot.data(as: PublicStatsDTO.self)
        } catch {
            // permission-denied means the friendship edge is missing (unfriended
            // mid-refresh) — treated as "not published" so that user drops off
            // the leaderboard instead of failing the whole load.
            return nil
        }
    }

    // MARK: - FirestoreService: Activity Feed (Friend System Phase 7)

    /// users/{userId}/feedEvents — friend-readable milestone events.
    private func feedEventsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("feedEvents")
    }

    func publishFeedEvent(_ event: FeedEventDTO, userId: String) async throws {
        // Deterministic doc id ⇒ idempotent. No merge: a re-emit is a full set
        // on the same id (overwrite for the owner / rejected-as-update under
        // create-only rules) — never a duplicate. createdAt (@ServerTimestamp,
        // nil) encodes the server sentinel, so the client never stamps time.
        try feedEventsCollection(for: userId).document(event.id).setData(from: event)
    }

    func pruneFeedEvents(userId: String, keep: Int) async throws {
        let snapshot = try await feedEventsCollection(for: userId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        let documents = snapshot.documents
        guard documents.count > keep else { return }

        // Everything past the newest `keep` is stale. Deleting an event doc does
        // NOT cascade into its `cheers` subcollection (Phase 8), so collect each
        // stale event's cheer docs and delete them alongside the event doc.
        let stale = documents[keep...]
        var refs: [DocumentReference] = []
        for doc in stale {
            if let cheersSnap = try? await doc.reference.collection("cheers").getDocuments() {
                refs.append(contentsOf: cheersSnap.documents.map { $0.reference })
            }
            refs.append(doc.reference)
        }
        try await deleteInBatches(refs)
    }

    /// Deletes the given document references in commit batches of ≤450 (under
    /// Firestore's 500-write hard limit). No-op on an empty array.
    private func deleteInBatches(_ refs: [DocumentReference]) async throws {
        var index = 0
        while index < refs.count {
            let batch = db.batch()
            let end = min(index + 450, refs.count)
            for ref in refs[index..<end] {
                batch.deleteDocument(ref)
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

    func fetchFeedEvents(friendUid: String, limit: Int) async throws -> [FeedEventDTO] {
        do {
            let snapshot = try await feedEventsCollection(for: friendUid)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: FeedEventDTO.self) }
        } catch {
            // permission-denied ⇒ the friend edge is gone (unfriended mid-fetch):
            // treat as no events so the rest of the feed still renders.
            return []
        }
    }

    func fetchMyFeedEvents(userId: String, limit: Int) async throws -> [FeedEventDTO] {
        let snapshot = try await feedEventsCollection(for: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FeedEventDTO.self) }
    }

    // MARK: - FirestoreService: Cheers (Friend System Phase 8)

    /// users/{ownerUid}/feedEvents/{eventId}/cheers — one doc per cheerer.
    private func cheersCollection(ownerUid: String, eventId: String) -> CollectionReference {
        feedEventsCollection(for: ownerUid).document(eventId).collection("cheers")
    }

    func addCheer(ownerUid: String, eventId: String,
                  cheererUid: String, username: String, displayName: String) async throws {
        // Doc id = cheererUid ⇒ idempotent. createdAt (@ServerTimestamp, nil)
        // encodes the server sentinel. A re-cheer is a set on the same id which
        // the create-only rules reject; callers swallow that as a no-op.
        let cheer = CheerDTO(cheererUid: cheererUid, username: username, displayName: displayName, createdAt: nil)
        try cheersCollection(ownerUid: ownerUid, eventId: eventId).document(cheererUid).setData(from: cheer)
    }

    func removeCheer(ownerUid: String, eventId: String, cheererUid: String) async throws {
        try await deleteDocument(ref: cheersCollection(ownerUid: ownerUid, eventId: eventId).document(cheererUid))
    }

    func fetchCheers(ownerUid: String, eventId: String, limit: Int) async throws -> [CheerDTO] {
        do {
            let snapshot = try await cheersCollection(ownerUid: ownerUid, eventId: eventId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: CheerDTO.self) }
        } catch {
            // permission-denied (unfriended) ⇒ no cheers, never fails the feed.
            return []
        }
    }

    // MARK: - FirestoreService: Meal/Recipe Sharing (Friend System Phase 9)

    /// users/{userId}/sharedItems — the recipient's private share inbox.
    private func sharedItemsCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("sharedItems")
    }

    func sendSharedItem(_ item: SharedItemDTO, toUid: String) async throws {
        // Fresh shareId per send (the caller generated it). createdAt
        // (@ServerTimestamp, nil) encodes the server sentinel; @DocumentID is
        // omitted from the body, so the written shape matches the rules exactly.
        let shareId = item.id ?? UUID().uuidString

        // Encode, then AWAIT the server write. The Codable `setData(from:)`
        // overload is fire-and-forget — it returns after the local/offline write
        // and never reports a server-side rules rejection, so a denied share
        // would look like a success. Awaiting the dictionary `setData(_:)` makes
        // a permission-denied (e.g. not actually friends) throw so the UI can
        // surface it instead of silently dropping the share.
        let data = try Firestore.Encoder().encode(item)
        try await sharedItemsCollection(for: toUid).document(shareId).setData(data)
    }

    func fetchSharedItems(userId: String, kind: String, limit: Int) async throws -> [SharedItemDTO] {
        // Equality filter on `kind` + order-by on `createdAt` ⇒ needs the
        // composite index (kind ASC, createdAt DESC) in firestore.indexes.json.
        // Server-side filter only — never fetch the whole inbox and filter locally.
        let snapshot = try await sharedItemsCollection(for: userId)
            .whereField("kind", isEqualTo: kind)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SharedItemDTO.self) }
    }

    func fetchAllSharedItems(userId: String, limit: Int) async throws -> [SharedItemDTO] {
        // Order-by on a single field only ⇒ uses the automatic single-field
        // index; no composite index needed. Kind filtering happens client-side
        // (the unified inbox shows both kinds anyway).
        let snapshot = try await sharedItemsCollection(for: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: SharedItemDTO.self) }
    }

    func deleteSharedItem(id: String, userId: String) async throws {
        try await deleteDocument(ref: sharedItemsCollection(for: userId).document(id))
    }

    // MARK: - FirestoreService: Guilds (G1)

    /// Top-level guild document: guilds/{guildCode}.
    private func guildDocument(code: String) -> DocumentReference {
        db.collection("guilds").document(code)
    }

    /// Roster subcollection: guilds/{guildCode}/members.
    private func guildMembers(code: String) -> CollectionReference {
        guildDocument(code: code).collection("members")
    }

    /// Pending requests subcollection: guilds/{guildCode}/joinRequests.
    private func guildJoinRequests(code: String) -> CollectionReference {
        guildDocument(code: code).collection("joinRequests")
    }

    /// Top-level one-guild lock: guildMemberships/{uid} (uid == doc id).
    private func guildMembershipDocument(for uid: String) -> DocumentReference {
        db.collection("guildMemberships").document(uid)
    }

    /// Commits a guild WriteBatch, mapping any failure to GuildError.network.
    /// A create over an existing guild code or an existing membership lock fails
    /// here (create-only rules) — the caller treats that as a collision/abort.
    private func commitGuildBatch(_ batch: WriteBatch) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                batch.commit { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            throw GuildError.network(error.localizedDescription)
        }
    }

    /// Deletes a single guild-related document, mapping failure to GuildError.network.
    private func deleteGuildDocument(_ ref: DocumentReference) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ref.delete { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            throw GuildError.network(error.localizedDescription)
        }
    }

    func createGuild(code: String, name: String, joinPolicy: String, description: String?,
                     ownerUid: String, ownerUsername: String, ownerDisplayName: String) async throws {
        let batch = db.batch()

        // Guild doc — create-only by rules (a collision over an existing code fails).
        // description is omitted when nil so the written key set stays within the
        // rules' hasOnly([name, ownerUid, joinPolicy, description, createdAt]).
        var guildData: [String: Any] = [
            "name": name,
            "ownerUid": ownerUid,
            "joinPolicy": joinPolicy,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let description, !description.isEmpty {
            guildData["description"] = description
        }
        batch.setData(guildData, forDocument: guildDocument(code: code))

        // Founder's owner member doc.
        batch.setData([
            "uid": ownerUid,
            "username": ownerUsername,
            "displayName": ownerDisplayName,
            "role": "owner",
            "joinedAt": FieldValue.serverTimestamp()
        ], forDocument: guildMembers(code: code).document(ownerUid))

        // Founder's one-guild lock (create-only; an existing lock means the caller
        // is already in a guild and the whole batch is rejected).
        batch.setData([
            "uid": ownerUid,
            "guildCode": code,
            "role": "owner",
            "joinedAt": FieldValue.serverTimestamp()
        ], forDocument: guildMembershipDocument(for: ownerUid))

        try await commitGuildBatch(batch)
    }

    func fetchGuild(code: String) async throws -> GuildDTO? {
        let snapshot = try await guildDocument(code: code).getDocument()
        guard snapshot.exists else { return nil }
        // .estimate resolves a not-yet-committed createdAt sentinel; guildCode
        // (the doc id) is not a stored field, so stamp it from documentID.
        guard var dto = try? snapshot.data(as: GuildDTO.self, with: .estimate) else { return nil }
        dto.id = snapshot.documentID
        return dto
    }

    func fetchMyGuild(uid: String) async throws -> GuildDTO? {
        let snapshot = try await guildMembershipDocument(for: uid).getDocument()
        guard snapshot.exists else { return nil }
        // Prefer the typed decode; fall back to a raw read so a pending/legacy
        // timestamp can never hide an existing membership. No collectionGroup, no index.
        let code: String?
        if let membership = try? snapshot.data(as: GuildMembershipDTO.self, with: .estimate) {
            code = membership.guildCode
        } else {
            code = snapshot.data()?["guildCode"] as? String
        }
        guard let guildCode = code else { return nil }
        return try await fetchGuild(code: guildCode)
    }

    func fetchGuildMembers(code: String) async throws -> [GuildMemberDTO] {
        let snapshot = try await guildMembers(code: code).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: GuildMemberDTO.self, with: .estimate) }
    }

    func fetchJoinRequests(code: String) async throws -> [GuildJoinRequestDTO] {
        do {
            let snapshot = try await guildJoinRequests(code: code).getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: GuildJoinRequestDTO.self, with: .estimate) }
        } catch {
            // Owner-only by rules: a non-owner read is permission-denied. Treat as
            // empty (consistent with fetchCheers / fetchPublicStats) rather than crash.
            return []
        }
    }

    func joinOpenGuild(code: String, uid: String, username: String, displayName: String) async throws {
        let batch = db.batch()
        batch.setData([
            "uid": uid,
            "username": username,
            "displayName": displayName,
            "role": "member",
            "joinedAt": FieldValue.serverTimestamp()
        ], forDocument: guildMembers(code: code).document(uid))
        batch.setData([
            "uid": uid,
            "guildCode": code,
            "role": "member",
            "joinedAt": FieldValue.serverTimestamp()
        ], forDocument: guildMembershipDocument(for: uid))
        try await commitGuildBatch(batch)
    }

    func requestToJoinGuild(code: String, uid: String, username: String, displayName: String) async throws {
        // No lock yet — the lock is written on approval. Awaiting the dictionary
        // setData surfaces a rules rejection (e.g. wrong-policy guild) as a throw.
        do {
            try await guildJoinRequests(code: code).document(uid).setData([
                "uid": uid,
                "username": username,
                "displayName": displayName,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch {
            throw GuildError.network(error.localizedDescription)
        }
    }

    func cancelJoinRequest(code: String, uid: String) async throws {
        try await deleteGuildDocument(guildJoinRequests(code: code).document(uid))
    }

    func approveJoinRequest(code: String, request: GuildJoinRequestDTO) async throws {
        let batch = db.batch()
        // Member doc stamped from the request (identity the requester provided).
        batch.setData([
            "uid": request.uid,
            "username": request.username,
            "displayName": request.displayName,
            "role": "member",
            "joinedAt": FieldValue.serverTimestamp()
        ], forDocument: guildMembers(code: code).document(request.uid))
        // The requester's one-guild lock (create fails if they joined elsewhere meanwhile).
        batch.setData([
            "uid": request.uid,
            "guildCode": code,
            "role": "member",
            "joinedAt": FieldValue.serverTimestamp()
        ], forDocument: guildMembershipDocument(for: request.uid))
        // Consume the request.
        batch.deleteDocument(guildJoinRequests(code: code).document(request.uid))
        try await commitGuildBatch(batch)
    }

    func denyJoinRequest(code: String, requesterUid: String) async throws {
        try await deleteGuildDocument(guildJoinRequests(code: code).document(requesterUid))
    }

    func leaveGuild(code: String, uid: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(guildMembers(code: code).document(uid))
        batch.deleteDocument(guildMembershipDocument(for: uid))
        try await commitGuildBatch(batch)
    }

    func kickMember(code: String, memberUid: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(guildMembers(code: code).document(memberUid))
        batch.deleteDocument(guildMembershipDocument(for: memberUid))
        try await commitGuildBatch(batch)
    }

    func updateGuildSettings(code: String, name: String, joinPolicy: String, description: String?) async throws {
        // updateData leaves ownerUid/createdAt untouched (rules require them
        // immutable). A cleared description removes the field entirely.
        var data: [String: Any] = [
            "name": name,
            "joinPolicy": joinPolicy
        ]
        if let description, !description.isEmpty {
            data["description"] = description
        } else {
            data["description"] = FieldValue.delete()
        }
        do {
            try await guildDocument(code: code).updateData(data)
        } catch {
            throw GuildError.network(error.localizedDescription)
        }
    }

    func disbandGuild(code: String) async throws {
        do {
            // Gather members + requests. Each member's lock is deleted alongside
            // the member doc; the guild doc is deleted LAST so the lock-delete
            // rule's get(guild) still resolves while the locks are removed.
            let membersSnapshot = try await guildMembers(code: code).getDocuments()
            let requestsSnapshot = try await guildJoinRequests(code: code).getDocuments()

            // Messages (G3) — subcollections do NOT cascade, so disband must
            // delete chat history too, before the guild doc.
            let messagesSnapshot = try await guildMessages(code: code).getDocuments()

            var refs: [DocumentReference] = []
            for doc in membersSnapshot.documents {
                refs.append(doc.reference)                                   // member doc
                refs.append(guildMembershipDocument(for: doc.documentID))    // that member's lock
            }
            for doc in requestsSnapshot.documents {
                refs.append(doc.reference)                                   // request doc
            }
            for doc in messagesSnapshot.documents {
                refs.append(doc.reference)                                   // message doc
            }

            try await deleteInBatches(refs)                                  // ≤450/batch, BEFORE the guild doc
            try await deleteGuildDocument(guildDocument(code: code))         // finally the guild itself
        } catch let error as GuildError {
            throw error
        } catch {
            throw GuildError.network(error.localizedDescription)
        }
    }

    // MARK: - FirestoreService: Guild chat (G3)

    /// guilds/{code}/messages — the chat subcollection.
    private func guildMessages(code: String) -> CollectionReference {
        guildDocument(code: code).collection("messages")
    }

    /// The SINGLE screen-scoped chat listener. Deliberately separate from the
    /// always-on global registry: it is owned by the chat screen's lifecycle, not
    /// by login/logout. The ListenerRegistration stays inside this service so no
    /// Firestore type leaks into the view layer.
    private var guildChatListener: ListenerRegistration?

    func startGuildChatListener(code: String,
                                onUpdate: @escaping ([GuildMessageDTO]) -> Void,
                                onError: @escaping (Error) -> Void) {
        // Defensive: a second chat screen can never orphan the first listener.
        stopGuildChatListener()
        // Secondary documentID() ordering is a deterministic tie-break — Firestore
        // timestamps are not unique, so two messages sharing a createdAt would
        // otherwise reorder unstably across snapshots. Same (descending) direction
        // as createdAt ⇒ served by the automatic single-field index (no composite).
        guildChatListener = guildMessages(code: code)
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: 50)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    Task { @MainActor in onError(error) }
                    return
                }
                guard let snapshot = snapshot else { return }
                // Decode-tolerant; stamp the doc id; reverse desc → chronological.
                let messages: [GuildMessageDTO] = snapshot.documents.compactMap { doc in
                    guard var dto = try? doc.data(as: GuildMessageDTO.self) else { return nil }
                    dto.id = doc.documentID
                    return dto
                }.reversed()
                Task { @MainActor in onUpdate(messages) }
            }
    }

    func stopGuildChatListener() {
        guildChatListener?.remove()
        guildChatListener = nil
    }

    func sendGuildMessage(code: String, msg: GuildMessageDTO) async throws {
        // Dictionary write with a generated auto-id: awaiting setData surfaces a
        // rules rejection (e.g. a raced eject) as a throw; createdAt is the server
        // sentinel. The DTO is a field carrier — its id/createdAt are unused here.
        do {
            try await guildMessages(code: code).document().setData([
                "senderUid": msg.senderUid,
                "senderUsername": msg.senderUsername,
                "senderDisplayName": msg.senderDisplayName,
                "text": msg.text,
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch {
            throw GuildChatError.network(error.localizedDescription)
        }
    }

    func deleteGuildMessage(code: String, msgId: String) async throws {
        do {
            try await guildMessages(code: code).document(msgId).delete()
        } catch {
            throw GuildChatError.network(error.localizedDescription)
        }
    }

    // MARK: - FirestoreService: Duels (D1a)

    /// Top-level `duels` collection — a duel is owned by neither participant
    /// (precedent: guilds).
    private var duelsCollection: CollectionReference {
        db.collection("duels")
    }

    private func duelDocument(id: String) -> DocumentReference {
        db.collection("duels").document(id)
    }

    func createDuel(_ duel: DuelDTO) async throws -> String {
        // Write EXACTLY the create rule's field set (keys().hasOnly). `createdAt` is
        // the server sentinel; `respondBy` is the client-computed cutoff. `id`,
        // `acceptedAt`, `endAt`, and the reserved fields are intentionally absent.
        let ref = duelsCollection.document()
        var data: [String: Any] = [
            "participantUids": duel.participantUids,
            "challengerUid": duel.challengerUid,
            "opponentUid": duel.opponentUid,
            "challengerUsername": duel.challengerUsername,
            "challengerDisplayName": duel.challengerDisplayName,
            "opponentUsername": duel.opponentUsername,
            "opponentDisplayName": duel.opponentDisplayName,
            "league": duel.league,
            "status": duel.status,
            "createdAt": FieldValue.serverTimestamp(),
            "respondBy": Timestamp(date: duel.respondBy),
            "challengerScore": duel.challengerScore,
            "opponentScore": duel.opponentScore
        ]
        // D1b rematch: present ONLY when this challenge is a rematch of a prior duel
        // (the create rule permits it via the extended `hasOnly` list + is-string guard).
        if let rematchOfDuelId = duel.rematchOfDuelId {
            data["rematchOfDuelId"] = rematchOfDuelId
        }
        try await ref.setData(data)
        return ref.documentID
    }

    func fetchMyDuels(uid: String) async throws -> [DuelDTO] {
        let snapshot = try await duelsCollection
            .whereField("participantUids", arrayContains: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        // Decode-tolerant: skip any doc that fails to decode. Stamp the doc id.
        return snapshot.documents.compactMap { doc in
            guard var dto = try? doc.data(as: DuelDTO.self) else { return nil }
            dto.id = doc.documentID
            return dto
        }
    }

    func acceptDuel(duelId: String, endAt: Date) async throws {
        try await duelDocument(id: duelId).updateData([
            "status": DuelStatus.active.rawValue,
            "acceptedAt": FieldValue.serverTimestamp(),
            "endAt": Timestamp(date: endAt)
        ])
    }

    func declineDuel(duelId: String) async throws {
        try await duelDocument(id: duelId).updateData(["status": DuelStatus.declined.rawValue])
    }

    func expireDuel(duelId: String) async throws {
        try await duelDocument(id: duelId).updateData(["status": DuelStatus.expired.rawValue])
    }

    func cancelDuel(duelId: String) async throws {
        try await duelDocument(id: duelId).delete()
    }

    // MARK: - FirestoreService: Duels (D1b)

    func updateDuelScore(duelId: String, isChallenger: Bool, score: Double, dayScores: [Double]) async throws {
        // Touch ONLY my side's three score fields (matches the isOwnScoreWrite() rule).
        try await duelDocument(id: duelId).updateData([
            (isChallenger ? "challengerScore" : "opponentScore"): score,
            (isChallenger ? "challengerDayScores" : "opponentDayScores"): dayScores,
            (isChallenger ? "challengerScoreUpdatedAt" : "opponentScoreUpdatedAt"): FieldValue.serverTimestamp()
        ])
    }

    func resolveDuel(duelId: String, winnerUid: String?, challengerDelta: Int, opponentDelta: Int) async throws {
        var data: [String: Any] = [
            "status": DuelStatus.resolved.rawValue,
            "resolvedAt": FieldValue.serverTimestamp(),
            "challengerRRDelta": challengerDelta,
            "opponentRRDelta": opponentDelta
        ]
        if let winnerUid { data["winnerUid"] = winnerUid }  // omitted on a draw
        try await duelDocument(id: duelId).updateData(data)
    }

    func forfeitDuel(duelId: String, forfeiterUid: String, challengerDelta: Int, opponentDelta: Int) async throws {
        try await duelDocument(id: duelId).updateData([
            "status": DuelStatus.forfeited.rawValue,
            "forfeitedBy": forfeiterUid,
            "resolvedAt": FieldValue.serverTimestamp(),
            "challengerRRDelta": challengerDelta,
            "opponentRRDelta": opponentDelta
        ])
    }

    func markDuelRRApplied(duelId: String, isChallenger: Bool) async throws {
        try await duelDocument(id: duelId).updateData([
            (isChallenger ? "challengerRRApplied" : "opponentRRApplied"): true
        ])
    }

    // MARK: - FirestoreService: QTE Days (D1d)

    private func qteDaysCollection(for userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("qteDays")
    }

    func uploadQTEDay(_ day: QTEDayDTO, userId: String) async throws {
        // Doc id = dateKey (one per day). NOTE: merge:true does NOT protect the point fields —
        // QTEDayDTO always encodes every field, so each upload overwrites them. Field-wise
        // max-wins is the CALLER's job: it reads + merges the remote day BEFORE this upload
        // (DataManager.uploadQTEDayAndRescore — review finding M3).
        try qteDaysCollection(for: userId).document(day.dateKey).setData(from: day, merge: true)
    }

    func fetchQTEDays(userId: String) async throws -> [QTEDayDTO] {
        let snapshot = try await qteDaysCollection(for: userId).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: QTEDayDTO.self) }
    }

    func fetchQTEDay(userId: String, dateKey: String) async throws -> QTEDayDTO? {
        let snapshot = try await qteDaysCollection(for: userId).document(dateKey).getDocument()
        guard snapshot.exists else { return nil }
        return try? snapshot.data(as: QTEDayDTO.self)
    }

    // MARK: - FirestoreService: Matchmaking (D2)

    /// Top-level `duelQueue` collection — doc-id-as-lock (one ticket per user; the
    /// `guildMemberships` precedent).
    private var duelQueueCollection: CollectionReference {
        db.collection("duelQueue")
    }

    private func duelQueueDocument(for uid: String) -> DocumentReference {
        db.collection("duelQueue").document(uid)
    }

    func enqueueDuelTicket(_ ticket: DuelQueueTicketDTO) async throws {
        // Write EXACTLY the create rule's field set (keys().hasOnly). `createdAt` is the
        // server sentinel; `expiresAt` is the client-computed cutoff; `claimedBy` MUST start
        // as "". The claim fields (claimedBy != "" / claimedAt / matchedDuelId) and `id` are
        // intentionally absent. Enqueue is delete-then-create at the DataManager layer — a
        // setData over an existing doc evaluates as an UPDATE, which the ticket rules permit
        // only for the expiresAt keep-alive and the claim.
        let data: [String: Any] = [
            "uid": ticket.uid,
            "username": ticket.username,
            "displayName": ticket.displayName,
            "rr": ticket.rr,
            "league": ticket.league,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: ticket.expiresAt),
            "claimedBy": ""
        ]
        try await duelQueueDocument(for: ticket.uid).setData(data)
    }

    func fetchMyDuelTicket(uid: String) async throws -> DuelQueueTicketDTO? {
        let snapshot = try await duelQueueDocument(for: uid).getDocument()
        guard snapshot.exists, var dto = try? snapshot.data(as: DuelQueueTicketDTO.self) else { return nil }
        dto.id = snapshot.documentID
        return dto
    }

    func fetchQueueCandidates(league: Int, rrLo: Int, rrHi: Int, limit: Int) async throws -> [DuelQueueTicketDTO] {
        // Equality on league + claimedBy, range/order on rr → needs the composite index
        // (league ASC, claimedBy ASC, rr ASC) in firestore.indexes.json.
        let snapshot = try await duelQueueCollection
            .whereField("league", isEqualTo: league)
            .whereField("claimedBy", isEqualTo: "")
            .whereField("rr", isGreaterThanOrEqualTo: rrLo)
            .whereField("rr", isLessThanOrEqualTo: rrHi)
            .order(by: "rr")
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            guard var dto = try? doc.data(as: DuelQueueTicketDTO.self) else { return nil }
            dto.id = doc.documentID
            return dto
        }
    }

    func deleteDuelTicket(uid: String) async throws {
        try await deleteDocument(ref: duelQueueDocument(for: uid))
    }

    func claimTicketAndCreateDuel(candidate: DuelQueueTicketDTO, myTicketUid: String,
                                  duel: DuelDTO) async throws -> String {
        let myTicketRef = duelQueueDocument(for: myTicketUid)
        let candidateRef = duelQueueDocument(for: candidate.uid)
        // Pre-generate the duel doc (random id) so the ticket update can point at it and we
        // can return a stable id across transaction retries.
        let duelRef = duelsCollection.document()

        // The matchmade duel body — the same manual-dict style as createDuel, writing EXACTLY
        // the matchmade create rule's key set. Born active: createdAt/acceptedAt are server
        // sentinels; respondBy/endAt are client-computed Dates; scores 0; matchmade == true.
        let endAt = duel.endAt ?? Date().addingTimeInterval(Double(duel.league) * DuelConstants.secondsPerDay)
        let duelData: [String: Any] = [
            "participantUids": duel.participantUids,
            "challengerUid": duel.challengerUid,
            "opponentUid": duel.opponentUid,
            "challengerUsername": duel.challengerUsername,
            "challengerDisplayName": duel.challengerDisplayName,
            "opponentUsername": duel.opponentUsername,
            "opponentDisplayName": duel.opponentDisplayName,
            "league": duel.league,
            "status": DuelStatus.active.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "respondBy": Timestamp(date: duel.respondBy),
            "acceptedAt": FieldValue.serverTimestamp(),
            "endAt": Timestamp(date: endAt),
            "challengerScore": 0.0,
            "opponentScore": 0.0,
            "challengerDayScores": [Double](),
            "opponentDayScores": [Double](),
            "matchmade": true
        ]

        do {
            try await db.runTransaction { transaction, errorPointer in
                // Step 0 — read MY OWN ticket. Missing or already claimed ⇒ someone matched me
                // while I searched; the incoming match wins. Abort with alreadyMatched. This
                // single read collapses the mutual-claim race to exactly one duel.
                let mySnapshot: DocumentSnapshot
                do {
                    mySnapshot = try transaction.getDocument(myTicketRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                let myClaimedBy = mySnapshot.data()?["claimedBy"] as? String
                if !mySnapshot.exists || !(myClaimedBy ?? "").isEmpty {
                    errorPointer?.pointee = NSError(domain: "DuelQueueError", code: 1,
                                                    userInfo: [NSLocalizedDescriptionKey: "already_matched"])
                    return nil
                }

                // Verify the candidate's ticket inside the transaction: exists, unclaimed,
                // not expired, same league. Any failure ⇒ candidateUnavailable (caller tries
                // the next candidate).
                let candidateSnapshot: DocumentSnapshot
                do {
                    candidateSnapshot = try transaction.getDocument(candidateRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                let cData = candidateSnapshot.data()
                let cClaimedBy = cData?["claimedBy"] as? String
                let cLeague = cData?["league"] as? Int
                let cExpiresAt = (cData?["expiresAt"] as? Timestamp)?.dateValue()
                let unavailable = !candidateSnapshot.exists
                    || !(cClaimedBy ?? "not-empty").isEmpty
                    || cLeague != duel.league
                    || cExpiresAt == nil
                    || (cExpiresAt.map { $0 <= Date() } ?? true)
                if unavailable {
                    errorPointer?.pointee = NSError(domain: "DuelQueueError", code: 2,
                                                    userInfo: [NSLocalizedDescriptionKey: "candidate_unavailable"])
                    return nil
                }

                // Claim THEIR ticket, create the duel, delete MY ticket — all atomic. The duel
                // create rule proves the claim via getAfter(candidate ticket).
                transaction.updateData([
                    "claimedBy": duel.challengerUid,
                    "claimedAt": FieldValue.serverTimestamp(),
                    "matchedDuelId": duelRef.documentID
                ], forDocument: candidateRef)
                transaction.setData(duelData, forDocument: duelRef)
                transaction.deleteDocument(myTicketRef)
                return nil
            }
        } catch let error as NSError {
            if error.domain == "DuelQueueError" {
                if error.code == 1 { throw DuelError.alreadyMatched }
                if error.code == 2 { throw DuelError.candidateUnavailable }
            }
            throw DuelError.network(error.localizedDescription)
        }
        return duelRef.documentID
    }

    // MARK: - FirestoreService: Global Leaderboard (D3)

    /// Top-level `leaderboard` collection — owner-published, world-readable ladder projection.
    private var leaderboardCollection: CollectionReference {
        db.collection("leaderboard")
    }

    private func leaderboardDocument(for uid: String) -> DocumentReference {
        db.collection("leaderboard").document(uid)
    }

    func upsertLeaderboardEntry(_ entry: GlobalLeaderboardDTO, userId: String) async throws {
        // Manual dict of EXACTLY the create/update rule's field set (keys().hasOnly). `id` is
        // never written; `updatedAt` is the server sentinel. setData WITHOUT merge — a full
        // overwrite keeps stale keys impossible.
        let data: [String: Any] = [
            "username": entry.username,
            "displayName": entry.displayName,
            "rr": entry.rr,
            "wins1": entry.wins1,
            "wins3": entry.wins3,
            "wins5": entry.wins5,
            "streak1": entry.streak1,
            "streak3": entry.streak3,
            "streak5": entry.streak5,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await leaderboardDocument(for: userId).setData(data)
    }

    func fetchLeaderboard(orderField: String, limit: Int) async throws -> [GlobalLeaderboardDTO] {
        // Single-field orderBy + limit — automatic single-field index, no composite (D8).
        let snapshot = try await leaderboardCollection
            .order(by: orderField, descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            guard var dto = try? doc.data(as: GlobalLeaderboardDTO.self) else { return nil }
            dto.id = doc.documentID
            return dto
        }
    }

    func fetchMyLeaderboardEntry(userId: String) async throws -> GlobalLeaderboardDTO? {
        let snapshot = try await leaderboardDocument(for: userId).getDocument()
        guard snapshot.exists, var dto = try? snapshot.data(as: GlobalLeaderboardDTO.self) else { return nil }
        dto.id = snapshot.documentID
        return dto
    }

    func fetchLeaderboardPosition(myRR: Int) async throws -> Int {
        // Standard competition ranking: count of higher-RR rows + 1. count() aggregation on a
        // single inequality filter — automatic index, no composite.
        let snapshot = try await leaderboardCollection
            .whereField("rr", isGreaterThan: myRR)
            .count
            .getAggregation(source: .server)
        return snapshot.count.intValue + 1
    }

    // MARK: - FirestoreService: Account Deletion

    /// Deletes all Firestore data under users/{userId}/ in batches of ≤500.
    /// Deletes all known subcollections first, then the root users/{userId} document.
    func deleteAllUserData(userId: String) async throws {
        // Guild teardown FIRST (G1). Read the one-guild lock; if this user owns a
        // guild, disband it; if they are a plain member, leave. If the teardown
        // throws (or the lock read fails), the whole deletion aborts here — we do
        // NOT proceed to delete the user, so a guild can never be orphaned under a
        // deleted owner. disband/leave are idempotent, so a retry is safe. The lock
        // and member doc are removed by disband/leave, so no guild data survives.
        let membershipSnapshot = try await guildMembershipDocument(for: userId).getDocument()
        if let membershipData = membershipSnapshot.data(),
           let guildCode = membershipData["guildCode"] as? String {
            let role = membershipData["role"] as? String
            if role == "owner" {
                try await disbandGuild(code: guildCode)
            } else {
                try await leaveGuild(code: guildCode, uid: userId)
            }
        }

        // Release the username handle (top-level, not a subcollection) before deleting user data.
        // Only delete if the doc's uid matches this user (guard against reassigned handles).
        if let username = try? await fetchUsername(userId: userId), !username.isEmpty {
            let usernameRef = usernameDocument(for: username)
            let usernameSnap = try? await usernameRef.getDocument()
            if let data = usernameSnap?.data(), data["uid"] as? String == userId {
                try? await deleteDocument(ref: usernameRef)
            }
            // Release the username → email login mapping too (owner-guarded).
            try? await deleteLoginHandle(handleKey: username, uid: userId)
        }

        // D2: delete my matchmaking queue ticket (top-level, like the username handle — NOT
        // covered by the subcollection sweep). Best-effort; a claimed-but-uncleaned ticket is
        // fine to delete (the duel already exists).
        try? await deleteDuelTicket(uid: userId)

        // D3: delete my global leaderboard row (top-level, best-effort). A failed delete leaves
        // a ghost row — acceptable, consistent with the username-release posture.
        try? await deleteDocument(ref: leaderboardDocument(for: userId))

        // Cross-user cleanup (Friend System Phase 2): remove every edge and request
        // mirror that points at this user from OTHER users' spaces, so no dangling
        // friend rows survive the deletion. Each deleted doc's ID equals this user's
        // uid, which is exactly what the friends/sentRequests/friendRequests delete
        // rules permit. Batched at ≤450 writes (Firestore hard limit is 500).
        var crossUserDeletes: [DocumentReference] = []

        if let friendsSnapshot = try? await friendsCollection(for: userId).getDocuments() {
            for doc in friendsSnapshot.documents {
                // Reciprocal edge in the friend's space: users/{friendUid}/friends/{me}
                crossUserDeletes.append(friendsCollection(for: doc.documentID).document(userId))
            }
        }
        if let sentSnapshot = try? await sentRequestsCollection(for: userId).getDocuments() {
            for doc in sentSnapshot.documents {
                // Incoming request in the recipient's space: users/{toUid}/friendRequests/{me}
                crossUserDeletes.append(incomingRequestsCollection(for: doc.documentID).document(userId))
            }
        }
        if let incomingSnapshot = try? await incomingRequestsCollection(for: userId).getDocuments() {
            for doc in incomingSnapshot.documents {
                // Mirror in the sender's space: users/{fromUid}/sentRequests/{me}
                crossUserDeletes.append(sentRequestsCollection(for: doc.documentID).document(userId))
            }
        }

        var crossIndex = 0
        while crossIndex < crossUserDeletes.count {
            let batch = db.batch()
            let end = min(crossIndex + 450, crossUserDeletes.count)
            for ref in crossUserDeletes[crossIndex..<end] {
                batch.deleteDocument(ref)
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
            crossIndex = end
        }

        // Duels (D1a): self-contained top-level docs — NOT under users/{uid}, so the
        // per-subcollection sweep below never reaches them. Delete my pending OUTGOING
        // challenges and decline pending INCOMING ones. ACTIVE duels are left untouched;
        // the opponent resolves them normally against a frozen score.
        // Non-fatal: duel cleanup failures are swallowed and the deletion continues —
        // duels are self-contained snapshots, so nothing orphans. Pending: delete my
        // outgoing / decline my incoming. Active (D1b): forfeit (deterministic deltas). If a
        // forfeit write fails, the duel stays active and the OTHER participant still resolves
        // it normally against a frozen score — no cleanup job exists or is needed.
        if let duelSnapshot = try? await duelsCollection
            .whereField("participantUids", arrayContains: userId).getDocuments() {
            for doc in duelSnapshot.documents {
                guard let dto = try? doc.data(as: DuelDTO.self) else { continue }
                switch dto.statusEnum {
                case .pending:
                    if dto.challengerUid == userId {
                        try? await doc.reference.delete()               // cancel my outgoing
                    } else {
                        try? await declineDuel(duelId: doc.documentID)  // decline my incoming
                    }
                case .active:
                    let deltas = DuelDTO.forfeitDeltas(duelId: doc.documentID, league: dto.league,
                                                       forfeiterIsChallenger: dto.challengerUid == userId)
                    try? await forfeitDuel(duelId: doc.documentID, forfeiterUid: userId,
                                           challengerDelta: deltas.challenger, opponentDelta: deltas.opponent)
                default:
                    break  // resolved / forfeited / declined / expired: nothing to do
                }
            }
        }

        // Cascade (Phase 8): each feedEvents/{eventId} may have a `cheers`
        // subcollection that the generic per-subcollection delete below does NOT
        // reach (it removes only the event docs). Delete every event's cheers
        // first, while the event docs still exist to enumerate.
        if let eventsSnapshot = try? await feedEventsCollection(for: userId).getDocuments() {
            var cheerDeletes: [DocumentReference] = []
            for eventDoc in eventsSnapshot.documents {
                if let cheersSnap = try? await eventDoc.reference.collection("cheers").getDocuments() {
                    cheerDeletes.append(contentsOf: cheersSnap.documents.map { $0.reference })
                }
            }
            try await deleteInBatches(cheerDeletes)
        }

        // "public" holds the friend-readable stats projection (public/stats).
        // Deleting the root users/{userId} document does NOT cascade into
        // subcollections, so it must be listed here explicitly.
        let knownSubcollections = [
            "foodEntries", "dailyGoals", "dailyQuests", "moodEntries",
            "customFoods", "savedMeals", "savedRecipes", "personalBaselines",
            "foodFingerprints", "userProgress", "profile", "account", "badges",
            "friends", "friendRequests", "sentRequests", "public", "feedEvents",
            "sharedItems", "qteDays"
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
        friendsListener?.remove()
        incomingRequestsListener?.remove()
        sentRequestsListener?.remove()

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
        friendsListener = nil
        incomingRequestsListener = nil
        sentRequestsListener = nil

        // Clear the pending-upload sets too (the doc comment above promises this) so in-flight
        // IDs from the previous session can't bleed into the next login and wrongly protect a
        // stale local value. The M6 passive-sign-out teardown funnels through here as well.
        pendingUploadIds.removeAll()
        pendingDailyGoalIds.removeAll()
        pendingBaselineIds.removeAll()
        pendingFingerprintIds.removeAll()
        pendingMoodEntryIds.removeAll()
        pendingProgressIds.removeAll()
        pendingQuestIds.removeAll()
        pendingCustomFoodIds.removeAll()
        pendingSavedMealIds.removeAll()
        pendingSavedRecipeIds.removeAll()
        pendingBadgeIds.removeAll()

        currentSyncUserId = nil
    }
}
