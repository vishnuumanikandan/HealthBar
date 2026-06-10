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

    // MARK: - FirestoreService: Account Deletion

    /// Deletes all Firestore data under users/{userId}/ in batches of ≤500.
    /// Deletes all known subcollections first, then the root users/{userId} document.
    func deleteAllUserData(userId: String) async throws {
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
            "sharedItems"
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

        currentSyncUserId = nil
    }
}
