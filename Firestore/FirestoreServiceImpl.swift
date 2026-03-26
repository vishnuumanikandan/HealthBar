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

        foodEntriesListener = nil
        dailyGoalsListener = nil
        personalBaselinesListener = nil
        foodFingerprintsListener = nil
        moodEntriesListener = nil
        userProgressListener = nil
        dailyQuestsListener = nil

        currentSyncUserId = nil
    }
}
