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

    // MARK: - Firestore Sync

    /// The Firestore sync service. Defaults to FirestoreServiceImpl.shared (singleton).
    /// Injected for testability; the default requires no changes to existing callers.
    private let firestoreService: FirestoreService

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

    /// Initializes the data manager with a SwiftData model context, auth service, and Firestore sync service.
    /// - Parameters:
    ///   - modelContext: The SwiftData context for persistence operations
    ///   - authService: The auth service for reading the current userId live.
    ///                  Defaults to `LocalAuthService.shared` so existing callers
    ///                  (e.g., `AppCoordinator(modelContext:)`) compile unchanged.
    ///   - firestoreService: The Firestore sync service. Defaults to `FirestoreServiceImpl.shared`
    ///                       so existing callers require no changes.
    init(
        modelContext: ModelContext,
        authService: any AuthService = LocalAuthService.shared,
        firestoreService: FirestoreService = FirestoreServiceImpl.shared
    ) {
        self.modelContext = modelContext
        self.authService = authService
        self.firestoreService = firestoreService
    }

    // MARK: - Setup Methods

    /// Creates default data for a newly authenticated user (DailyGoal + UserProgress).
    ///
    /// Safe to call repeatedly — it is a no-op if data already exists for this user,
    /// and a no-op if no user is authenticated (currentUserId == nil).
    /// Call this before loading any user-facing data after login.
    ///
    /// Also serves as the Firestore sync entry point:
    /// - On login (userId present): starts the Firestore listener and performs initial sync.
    /// - On logout (userId nil): stops the listener and clears the pending upload set.
    func setupDefaultData() async throws {
        // If no user is authenticated, stop any active Firestore sync and bail out.
        // This handles the logout case — setupDefaultData is called again after logout
        // by the first DataManager method that runs, ensuring cleanup occurs.
        guard let userId = currentUserId, !userId.isEmpty else {
            // Stop all Firestore listeners and clear every pending set on logout
            firestoreService.stopAllListeners()
            FirestoreServiceImpl.shared.pendingUploadIds.removeAll()
            FirestoreServiceImpl.shared.pendingDailyGoalIds.removeAll()
            FirestoreServiceImpl.shared.pendingBaselineIds.removeAll()
            FirestoreServiceImpl.shared.pendingFingerprintIds.removeAll()
            FirestoreServiceImpl.shared.pendingMoodEntryIds.removeAll()
            FirestoreServiceImpl.shared.pendingProgressIds.removeAll()
            FirestoreServiceImpl.shared.pendingQuestIds.removeAll()
            return
        }

        // Start Firestore sync for the authenticated user.
        // This is idempotent — safe to call from multiple DataManager instances.
        startFirestoreSync(userId: userId)

        // Check if UserProgress already exists for this specific user
        let progressDescriptor = FetchDescriptor<UserProgress>(
            predicate: #Predicate { progress in
                progress.userId == userId
            }
        )
        let existingProgress = try modelContext.fetch(progressDescriptor)

        var newDefaultProgress: UserProgress? = nil
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
            newDefaultProgress = progress
        }

        // Create today's goal if it doesn't exist for this user
        var newDefaultGoal: DailyGoal? = nil
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
            newDefaultGoal = defaultGoal
        }

        try modelContext.save()

        // Firestore sync: upload the newly created default UserProgress (if any).
        // Pending ID removed in applyUserProgressUpdate when listener confirms the write.
        if let progress = newDefaultProgress {
            let dto = UserProgressDTO(from: progress)
            FirestoreServiceImpl.shared.pendingProgressIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadUserProgress(dto)
            }
        }

        // Firestore sync: upload the newly created default goal (if any).
        // Pending ID removed in applyDailyGoalUpdates when listener confirms the write.
        if let goal = newDefaultGoal {
            let dto = DailyGoalDTO(from: goal)
            FirestoreServiceImpl.shared.pendingDailyGoalIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadDailyGoal(dto)
            }
        }
    }

    // MARK: - Firestore Sync Methods

    /// Starts the Firestore real-time listener and performs a one-time initial sync.
    ///
    /// Called from `setupDefaultData()` on every login. The listener call is idempotent —
    /// if three DataManager instances call this for the same userId, only one listener is
    /// registered (FirestoreServiceImpl.shared deduplicates by userId).
    ///
    /// Initial sync (one-time Task):
    ///   1. Fetch all remote entries → apply to local SwiftData (handles reinstall / empty cache).
    ///   2. Upload any local-only entries → Firestore (entries that exist locally but not remotely).
    /// The ongoing listener handles all subsequent updates; it never uploads anything.
    private func startFirestoreSync(userId: String) {

        // MARK: Real-time listeners (idempotent — safe to call from 3 DataManagers)

        firestoreService.listenForFoodEntries(userId: userId) { [weak self] dtos in
            Task { [weak self] in try? await self?.applyFirestoreUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForDailyGoals(userId: userId) { [weak self] dtos in
            Task { [weak self] in try? await self?.applyDailyGoalUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForPersonalBaselines(userId: userId) { [weak self] dtos in
            Task { [weak self] in try? await self?.applyPersonalBaselineUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForFoodFingerprints(userId: userId) { [weak self] dtos in
            // FoodFingerprint is not a SwiftData @Model — listener fires for cross-device
            // awareness of new foods but requires no local SwiftData writes.
            // FoodEntry sync (Phase 1) already carries all nutritional and favorite data.
            Task { [weak self] in await self?.applyFoodFingerprintUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForMoodEntries(userId: userId) { [weak self] dtos in
            Task { [weak self] in try? await self?.applyMoodEntryUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForUserProgress(userId: userId) { [weak self] dto in
            Task { [weak self] in try? await self?.applyUserProgressUpdate(dto, userId: userId) }
        }

        firestoreService.listenForDailyQuests(userId: userId) { [weak self] dtos in
            Task { [weak self] in try? await self?.applyDailyQuestUpdates(dtos, userId: userId) }
        }

        // MARK: One-time initial sync per model (runs once at login)
        // For each model:
        //   1. Fetch all remote records → apply to local SwiftData (cold start / reinstall)
        //   2. Upload local-only records → Firestore (exists locally but not remotely)
        // The ongoing listeners handle all subsequent changes; they never upload.

        Task {
            // --- FoodEntry ---
            if let remoteFoodDTOs = try? await firestoreService.fetchFoodEntries(userId: userId) {
                let remoteIds = Set(remoteFoodDTOs.map { $0.id })
                try? await applyFirestoreUpdates(remoteFoodDTOs, userId: userId)
                let localEntries = (try? await fetchAllFoodEntriesForSync(userId: userId)) ?? []
                for entry in localEntries where !remoteIds.contains(entry.id.uuidString) {
                    try? await firestoreService.uploadFoodEntry(FoodEntryDTO(from: entry))
                }
            }

            // --- DailyGoal ---
            if let remoteGoalDTOs = try? await firestoreService.fetchDailyGoals(userId: userId) {
                let remoteIds = Set(remoteGoalDTOs.map { $0.id })
                try? await applyDailyGoalUpdates(remoteGoalDTOs, userId: userId)
                let localGoals = (try? await fetchAllDailyGoalsForSync(userId: userId)) ?? []
                for goal in localGoals where !remoteIds.contains(goal.id.uuidString) {
                    try? await firestoreService.uploadDailyGoal(DailyGoalDTO(from: goal))
                }
            }

            // --- PersonalBaseline ---
            if let remoteBaselineDTOs = try? await firestoreService.fetchPersonalBaselines(userId: userId) {
                let remoteIds = Set(remoteBaselineDTOs.map { $0.id })
                try? await applyPersonalBaselineUpdates(remoteBaselineDTOs, userId: userId)
                let localBaselines = (try? await fetchAllBaselinesForSync(userId: userId)) ?? []
                for baseline in localBaselines where !remoteIds.contains(baseline.id.uuidString) {
                    try? await firestoreService.uploadPersonalBaseline(PersonalBaselineDTO(from: baseline))
                }
            }

            // --- FoodFingerprint ---
            // FoodFingerprint is not a @Model. "Local-only" fingerprints are derived from
            // the local FoodEntry collection. Upload any whose stable ID is not in Firestore.
            if let remoteFingerprintDTOs = try? await firestoreService.fetchFoodFingerprints(userId: userId) {
                let remoteIds = Set(remoteFingerprintDTOs.map { $0.id })
                let localEntries = (try? await fetchAllFoodEntriesForSync(userId: userId)) ?? []
                var seenIds = Set<String>()
                for entry in localEntries {
                    let dto = FoodFingerprintDTO(from: entry)
                    guard seenIds.insert(dto.id).inserted else { continue } // Deduplicate
                    if !remoteIds.contains(dto.id) {
                        try? await firestoreService.uploadFoodFingerprint(dto)
                    }
                }
            }

            // --- MoodEntry ---
            if let remoteMoodDTOs = try? await firestoreService.fetchMoodEntries(userId: userId) {
                let remoteIds = Set(remoteMoodDTOs.map { $0.id })
                try? await applyMoodEntryUpdates(remoteMoodDTOs, userId: userId)
                let localMoods = (try? await fetchAllMoodEntriesForSync(userId: userId)) ?? []
                for entry in localMoods where !remoteIds.contains(entry.id.uuidString) {
                    try? await firestoreService.uploadMoodEntry(MoodEntryDTO(from: entry))
                }
            }

            // --- UserProgress ---
            // Single-document model. Apply remote → local (merge rules apply).
            // No "local-only upload" here: setupDefaultData handles new-user upload,
            // and saveUserProgress handles all subsequent writes.
            let remoteProgressDTO = try? await firestoreService.fetchUserProgress(userId: userId)
            try? await applyUserProgressUpdate(remoteProgressDTO, userId: userId)

            // --- DailyQuest ---
            if let remotequestDTOs = try? await firestoreService.fetchDailyQuests(userId: userId) {
                let remoteIds = Set(remotequestDTOs.map { $0.id })
                try? await applyDailyQuestUpdates(remotequestDTOs, userId: userId)
                // Upload any quests that exist locally but not in Firestore (e.g. generated offline).
                let localQuests = (try? await fetchAllQuestsForSync(userId: userId)) ?? []
                for quest in localQuests where !remoteIds.contains(quest.id.uuidString) {
                    try? await firestoreService.uploadDailyQuest(DailyQuestDTO(from: quest))
                }
            }
        }
    }

    /// Diffs incoming Firestore records against local SwiftData and applies updates.
    ///
    /// This method is **receive-only** — it never uploads anything to Firestore.
    /// Upload responsibility belongs to the write paths (addFoodEntry, etc.) and
    /// the one-time initial sync in `startFirestoreSync`.
    ///
    /// Conflict rules (Phase 1):
    /// - Entry in Firestore but not SwiftData → insert locally
    /// - Entry in both, fields differ, NOT in pending set → Firestore wins (overwrite local)
    /// - Entry in both, fields differ, IS in pending set → skip (local write in-flight)
    /// - Entry in both, fields identical, IS in pending set → remove from pending (write confirmed)
    /// - Entry in both, fields identical, NOT in pending → skip (no rewrite needed)
    /// - Entry in SwiftData but not Firestore → no action (handled at login by startFirestoreSync)
    @MainActor
    private func applyFirestoreUpdates(_ dtos: [FoodEntryDTO], userId: String) async throws {
        // Fetch all local FoodEntries for this user
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in entry.userId == userId }
        )
        let localEntries = try modelContext.fetch(descriptor)
        var localById: [String: FoodEntry] = [:]
        for entry in localEntries {
            localById[entry.id.uuidString] = entry
        }

        var didChange = false

        for dto in dtos {
            if let local = localById[dto.id] {
                let isPending = FirestoreServiceImpl.shared.pendingUploadIds.contains(dto.id)
                if isPending {
                    // Local write is in-flight. Check if Firestore now reflects our write.
                    if !dto.differsFrom(local) {
                        // Firestore confirmed our write — safe to remove from pending set.
                        FirestoreServiceImpl.shared.pendingUploadIds.remove(dto.id)
                    }
                    // Whether confirmed or not, never overwrite local for a pending entry.
                } else {
                    // Not in-flight — Firestore wins if any field differs
                    if dto.differsFrom(local) {
                        local.name = dto.name
                        local.date = dto.date
                        local.calories = dto.calories
                        local.protein = dto.protein
                        local.carbs = dto.carbs
                        local.fat = dto.fat
                        local.toxinScore = dto.toxinScore
                        local.barcodeUPC = dto.barcodeUPC
                        local.createdAt = dto.createdAt
                        local.isFavorite = dto.isFavorite
                        local.mealTypeRawValue = dto.mealTypeRawValue
                        local.fiber = dto.fiber
                        local.sugar = dto.sugar
                        local.sodium = dto.sodium
                        local.saturatedFat = dto.saturatedFat
                        local.cholesterol = dto.cholesterol
                        local.potassium = dto.potassium
                        didChange = true
                    }
                    // Identical — skip (no rewrite, no churn)
                }
            } else {
                // Entry exists in Firestore but not locally → insert
                let entry = dto.toFoodEntry(userId: userId)
                modelContext.insert(entry)
                didChange = true
            }
        }

        if didChange {
            try modelContext.save()
        }
    }

    /// Fetches all FoodEntries for a user with no date filter.
    /// Used only by `startFirestoreSync` to find local-only entries to upload.
    private func fetchAllFoodEntriesForSync(userId: String) async throws -> [FoodEntry] {
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { entry in entry.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Firestore Apply: DailyGoal

    /// Diffs incoming Firestore DailyGoal records against local SwiftData and applies updates.
    /// Receive-only — never uploads. Same conflict rules as applyFirestoreUpdates (FoodEntry).
    @MainActor
    private func applyDailyGoalUpdates(_ dtos: [DailyGoalDTO], userId: String) async throws {
        let descriptor = FetchDescriptor<DailyGoal>(
            predicate: #Predicate { goal in goal.userId == userId }
        )
        let localGoals = try modelContext.fetch(descriptor)
        var localById: [String: DailyGoal] = [:]
        for goal in localGoals { localById[goal.id.uuidString] = goal }

        var didChange = false

        for dto in dtos {
            // Duplicate insert guard: re-check by id before inserting
            if let local = localById[dto.id] {
                let isPending = FirestoreServiceImpl.shared.pendingDailyGoalIds.contains(dto.id)
                if isPending {
                    if !dto.differsFrom(local) {
                        FirestoreServiceImpl.shared.pendingDailyGoalIds.remove(dto.id)
                    }
                } else if dto.differsFrom(local) {
                    local.date = dto.date
                    local.calorieTarget = dto.calorieTarget
                    local.proteinTarget = dto.proteinTarget
                    local.carbTarget = dto.carbTarget
                    local.fatTarget = dto.fatTarget
                    local.purityTarget = dto.purityTarget
                    local.fiberTarget = dto.fiberTarget
                    local.sugarTarget = dto.sugarTarget
                    local.sodiumTarget = dto.sodiumTarget
                    local.saturatedFatTarget = dto.saturatedFatTarget
                    local.cholesterolTarget = dto.cholesterolTarget
                    local.potassiumTarget = dto.potassiumTarget
                    didChange = true
                }
            } else {
                // Not in local SwiftData → insert (duplicate guard already passed via dict)
                let goal = dto.toDailyGoal(userId: userId)
                modelContext.insert(goal)
                didChange = true
            }
        }

        if didChange { try modelContext.save() }
    }

    /// Fetches all DailyGoals for a user with no date filter.
    private func fetchAllDailyGoalsForSync(userId: String) async throws -> [DailyGoal] {
        let descriptor = FetchDescriptor<DailyGoal>(
            predicate: #Predicate { goal in goal.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Firestore Apply: PersonalBaseline

    /// Diffs incoming Firestore PersonalBaseline records against local SwiftData and applies updates.
    /// Receive-only — never uploads.
    @MainActor
    private func applyPersonalBaselineUpdates(_ dtos: [PersonalBaselineDTO], userId: String) async throws {
        let descriptor = FetchDescriptor<PersonalBaseline>(
            predicate: #Predicate { baseline in baseline.userId == userId }
        )
        let localBaselines = try modelContext.fetch(descriptor)
        var localById: [String: PersonalBaseline] = [:]
        for baseline in localBaselines { localById[baseline.id.uuidString] = baseline }

        var didChange = false

        for dto in dtos {
            if let local = localById[dto.id] {
                let isPending = FirestoreServiceImpl.shared.pendingBaselineIds.contains(dto.id)
                if isPending {
                    if !dto.differsFrom(local) {
                        FirestoreServiceImpl.shared.pendingBaselineIds.remove(dto.id)
                    }
                } else if dto.differsFrom(local) {
                    local.dayOfWeek = dto.dayOfWeek
                    local.averageCalories = dto.averageCalories
                    local.averagePurity = dto.averagePurity
                    local.sampleCount = dto.sampleCount
                    local.lastUpdated = dto.lastUpdated
                    didChange = true
                }
            } else {
                let baseline = dto.toPersonalBaseline(userId: userId)
                modelContext.insert(baseline)
                didChange = true
            }
        }

        if didChange { try modelContext.save() }
    }

    /// Fetches all PersonalBaselines for a user.
    private func fetchAllBaselinesForSync(userId: String) async throws -> [PersonalBaseline] {
        let descriptor = FetchDescriptor<PersonalBaseline>(
            predicate: #Predicate { baseline in baseline.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Firestore Apply: FoodFingerprint

    /// FoodFingerprint is not a SwiftData @Model — no local writes are performed.
    /// This method exists to satisfy the listener contract and can carry future logic
    /// (e.g., populating an in-memory food library cache in a later phase).
    @MainActor
    private func applyFoodFingerprintUpdates(_ dtos: [FoodFingerprintDTO], userId: String) async {
        // No SwiftData writes: FoodFingerprint is a plain struct, not @Model.
        // Favorites and nutritional data are carried by FoodEntry (Phase 1 sync).
        // Pending set confirmation for in-flight uploads:
        for dto in dtos {
            if FirestoreServiceImpl.shared.pendingFingerprintIds.contains(dto.id) {
                FirestoreServiceImpl.shared.pendingFingerprintIds.remove(dto.id)
            }
        }
    }

    // MARK: - Firestore Apply: MoodEntry

    /// Diffs incoming Firestore MoodEntry records against local SwiftData and applies updates.
    /// Receive-only — never uploads.
    @MainActor
    private func applyMoodEntryUpdates(_ dtos: [MoodEntryDTO], userId: String) async throws {
        let descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { entry in entry.userId == userId }
        )
        let localEntries = try modelContext.fetch(descriptor)
        var localById: [String: MoodEntry] = [:]
        for entry in localEntries { localById[entry.id.uuidString] = entry }

        var didChange = false

        for dto in dtos {
            if let local = localById[dto.id] {
                let isPending = FirestoreServiceImpl.shared.pendingMoodEntryIds.contains(dto.id)
                if isPending {
                    if !dto.differsFrom(local) {
                        FirestoreServiceImpl.shared.pendingMoodEntryIds.remove(dto.id)
                    }
                } else if dto.differsFrom(local) {
                    local.date = dto.date
                    local.moodRawValue = dto.moodRawValue
                    local.createdAt = dto.createdAt
                    didChange = true
                }
            } else {
                let entry = dto.toMoodEntry(userId: userId)
                modelContext.insert(entry)
                didChange = true
            }
        }

        if didChange { try modelContext.save() }
    }

    /// Fetches all MoodEntries for a user with no date filter.
    private func fetchAllMoodEntriesForSync(userId: String) async throws -> [MoodEntry] {
        let descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { entry in entry.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Firestore Apply: UserProgress

    /// Applies an incoming Firestore UserProgress snapshot to local SwiftData using merge rules.
    ///
    /// Receive-only — never uploads. Merge rules for additive gamification fields:
    /// - `totalXP`, `currentStreak`, `longestStreak` → `max()` wins (never decrease)
    /// - `lastActiveDate` → `max()` wins
    /// - `claimedMilestones` → set union (milestones are never un-claimed)
    /// - `rank` → always recomputed from merged `totalXP`; never read from the DTO
    ///
    /// Pending confirmation uses a "at least as good" check (superset/max) rather than strict
    /// equality because a confirming snapshot from another device may show a higher value.
    @MainActor
    private func applyUserProgressUpdate(_ dto: UserProgressDTO?, userId: String) async throws {
        guard let dto = dto else { return }

        let descriptor = FetchDescriptor<UserProgress>(
            predicate: #Predicate { progress in progress.userId == userId }
        )
        let localArray = try modelContext.fetch(descriptor)

        if let local = localArray.first {
            // Compute all merged values in-memory before touching SwiftData
            let mergedTotalXP = max(dto.totalXP, local.totalXP)
            let mergedCurrentStreak = max(dto.currentStreak, local.currentStreak)
            let mergedLongestStreak = max(dto.longestStreak, local.longestStreak)
            let mergedLastActiveDate = max(dto.lastActiveDate, local.lastActiveDate)
            let mergedClaimedSet = Set(dto.claimedMilestonesArray).union(local.claimedMilestoneSet)
            let mergedClaimedString = mergedClaimedSet.sorted().map { String($0) }.joined(separator: ",")
            let mergedRank = Rank.getRank(from: mergedTotalXP).rawValue

            let isPending = FirestoreServiceImpl.shared.pendingProgressIds.contains(dto.id)
            if isPending {
                // Confirmation: Firestore must be "at least as good" as local for all additive fields.
                // A strictly higher value from a simultaneous device write is still a valid confirmation.
                let firestoreIsConfirmed = dto.totalXP >= local.totalXP
                    && dto.currentStreak >= local.currentStreak
                    && dto.longestStreak >= local.longestStreak
                    && Set(dto.claimedMilestonesArray).isSuperset(of: local.claimedMilestoneSet)
                guard firestoreIsConfirmed else { return } // Write still in-flight — skip
                FirestoreServiceImpl.shared.pendingProgressIds.remove(dto.id)
                // Fall through to apply merged values (handles concurrent write from another device)
            }

            let changed = mergedTotalXP != local.totalXP
                || mergedCurrentStreak != local.currentStreak
                || mergedLongestStreak != local.longestStreak
                || mergedLastActiveDate != local.lastActiveDate
                || mergedClaimedSet != local.claimedMilestoneSet
                || mergedRank != local.rank

            if changed {
                local.totalXP = mergedTotalXP
                local.currentStreak = mergedCurrentStreak
                local.longestStreak = mergedLongestStreak
                local.lastActiveDate = mergedLastActiveDate
                local.claimedMilestones = mergedClaimedString
                local.rank = mergedRank
                try modelContext.save()
            }
        } else {
            // Reinstall / cold start: no local UserProgress yet — insert from Firestore.
            let progress = dto.toUserProgress(userId: userId)
            // Always recompute rank from the merged totalXP (toUserProgress already does this).
            modelContext.insert(progress)
            try modelContext.save()
        }
    }

    // MARK: - Firestore Apply: DailyQuest

    /// Diffs incoming Firestore DailyQuest records against local SwiftData and applies updates.
    ///
    /// Receive-only — never uploads. Merge rules:
    /// - `isCompleted` is append-only: `local.isCompleted || dto.isCompleted` (true always wins)
    /// - All other fields: Firestore wins if different (and entry is not in-flight)
    ///
    /// Date scoping: DTOs older than 7 days are silently ignored to enforce the sync window.
    @MainActor
    private func applyDailyQuestUpdates(_ dtos: [DailyQuestDTO], userId: String) async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        let descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { quest in quest.userId == userId }
        )
        let localQuests = try modelContext.fetch(descriptor)
        var localById: [String: DailyQuest] = [:]
        for quest in localQuests { localById[quest.id.uuidString] = quest }

        var didChange = false

        for dto in dtos {
            // Enforce the 7-day sync window (double-check beyond the Firestore query filter)
            guard dto.questDate >= cutoff else { continue }

            if let local = localById[dto.id] {
                let isPending = FirestoreServiceImpl.shared.pendingQuestIds.contains(dto.id)
                if isPending {
                    if !dto.differsFrom(local) {
                        FirestoreServiceImpl.shared.pendingQuestIds.remove(dto.id)
                    }
                    // Whether confirmed or not, never overwrite local for a pending quest.
                } else {
                    // Apply merge rules — isCompleted is append-only (true always wins)
                    let mergedIsCompleted = local.isCompleted || dto.isCompleted
                    let needsUpdate = dto.title != local.title
                        || dto.questDescription != local.questDescription
                        || dto.xpReward != local.xpReward
                        || mergedIsCompleted != local.isCompleted
                        || dto.questDate != local.date
                        || dto.questType != local.questType
                    if needsUpdate {
                        local.title = dto.title
                        local.questDescription = dto.questDescription
                        local.xpReward = dto.xpReward
                        local.isCompleted = mergedIsCompleted
                        local.date = dto.questDate
                        local.questType = dto.questType
                        didChange = true
                    }
                }
            } else {
                // Quest exists in Firestore but not locally → insert
                let quest = dto.toDailyQuest(userId: userId)
                modelContext.insert(quest)
                didChange = true
            }
        }

        if didChange { try modelContext.save() }
    }

    /// Fetches all DailyQuests for a user within the 7-day sync window.
    /// Used by `startFirestoreSync` to find local-only quests to upload.
    private func fetchAllQuestsForSync(userId: String) async throws -> [DailyQuest] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { quest in quest.userId == userId && quest.date >= cutoff }
        )
        return try modelContext.fetch(descriptor)
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
        date: Date = Date(),
        photoData: Data? = nil,
        barcodeUPC: String? = nil,
        mealType: MealType = .uncategorized,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil,
        saturatedFat: Double? = nil,
        cholesterol: Double? = nil,
        potassium: Double? = nil,
        mealBundleId: String? = nil,
        mealBundleName: String? = nil
    ) async throws -> FoodEntry {
        // Guard: no insert runs without an authenticated user
        guard let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }

        let entry = FoodEntry(
            name: name,
            date: date,
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
        entry.mealBundleId = mealBundleId
        entry.mealBundleName = mealBundleName

        modelContext.insert(entry)
        try modelContext.save()

        // Firestore sync: upload after local write succeeds.
        // Add to pending set BEFORE the Task fires so the listener cannot overwrite
        // this entry with a stale snapshot while the upload is in-flight.
        // The pending ID is removed in applyFirestoreUpdates when the listener confirms
        // the entry — not here on upload completion.
        let dto = FoodEntryDTO(from: entry)
        FirestoreServiceImpl.shared.pendingUploadIds.insert(dto.id)
        Task {
            try? await firestoreService.uploadFoodEntry(dto)
        }

        // Firestore sync: also upsert the FoodFingerprint for this food.
        // FoodFingerprint has no @Model — only Firestore needs it.
        // Pending ID removed in applyFoodFingerprintUpdates when listener confirms.
        let fingerprintDTO = FoodFingerprintDTO(from: entry)
        FirestoreServiceImpl.shared.pendingFingerprintIds.insert(fingerprintDTO.id)
        Task {
            try? await firestoreService.uploadFoodFingerprint(fingerprintDTO)
        }

        return entry
    }

    /// Deletes a food entry from the database.
    func deleteFoodEntry(_ entry: FoodEntry) async throws {
        // Capture identifiers before deletion (entry will be invalid after modelContext.delete)
        let entryId = entry.id.uuidString
        let userId = entry.userId

        modelContext.delete(entry)
        try modelContext.save()

        // Firestore sync: remove the entry from Firestore after local delete succeeds.
        Task {
            try? await firestoreService.deleteFoodEntry(id: entryId, userId: userId)
        }
    }

    /// Updates an existing food entry (changes tracked by SwiftData).
    func updateFoodEntry(_ entry: FoodEntry) async throws {
        try modelContext.save()

        // Firestore sync: re-upload the entry with its updated fields.
        let dto = FoodEntryDTO(from: entry)
        Task {
            try? await firestoreService.uploadFoodEntry(dto)
        }
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

        let goalToUpload: DailyGoal
        if let existingGoal = try await getTodaysGoal() {
            // Update existing goal in-place
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
            goalToUpload = existingGoal
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
            goalToUpload = newGoal
        }

        try modelContext.save()

        // Firestore sync: upload the created/updated goal.
        // Pending ID removed in applyDailyGoalUpdates when listener confirms the write.
        let dto = DailyGoalDTO(from: goalToUpload)
        FirestoreServiceImpl.shared.pendingDailyGoalIds.insert(dto.id)
        Task {
            try? await firestoreService.uploadDailyGoal(dto)
        }
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

    /// Saves in-progress changes to UserProgress and syncs to Firestore.
    func saveUserProgress() async throws {
        try modelContext.save()

        // Firestore sync: re-upload UserProgress after every local save.
        // Pending ID removed in applyUserProgressUpdate when the listener confirms.
        guard let userId = currentUserId, !userId.isEmpty else { return }
        let descriptor = FetchDescriptor<UserProgress>(
            predicate: #Predicate { progress in progress.userId == userId }
        )
        guard let progress = (try? modelContext.fetch(descriptor))?.first else { return }
        let dto = UserProgressDTO(from: progress)
        FirestoreServiceImpl.shared.pendingProgressIds.insert(dto.id)
        Task {
            try? await firestoreService.uploadUserProgress(dto)
        }
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

        // Firestore sync: upload new quest after local insert succeeds.
        // Pending ID removed in applyDailyQuestUpdates when the listener confirms.
        let dto = DailyQuestDTO(from: quest)
        FirestoreServiceImpl.shared.pendingQuestIds.insert(dto.id)
        Task {
            try? await firestoreService.uploadDailyQuest(dto)
        }
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

    /// Saves in-progress changes to quests and syncs updated quests to Firestore.
    ///
    /// Uploads all quests for today (the most likely set to have been mutated).
    /// Called by GamificationManager after marking a quest complete or awarding XP.
    func saveQuests() async throws {
        try modelContext.save()

        // Firestore sync: upload all of today's quests after any in-memory mutation.
        // This is the primary sync path for isCompleted changes (append-only on merge).
        guard let userId = currentUserId, !userId.isEmpty else { return }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { quest in
                quest.userId == userId && quest.date >= startOfDay && quest.date < endOfDay
            }
        )
        guard let todaysQuests = try? modelContext.fetch(descriptor) else { return }
        for quest in todaysQuests {
            let dto = DailyQuestDTO(from: quest)
            FirestoreServiceImpl.shared.pendingQuestIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadDailyQuest(dto)
            }
        }
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
        var affectedEntries: [FoodEntry] = []
        for entry in allEntries {
            if FoodFingerprint(from: entry) == fingerprint {
                entry.isFavorite = newFavoriteState
                affectedEntries.append(entry)
            }
        }

        try modelContext.save()

        // Firestore sync: upload each affected entry with its updated isFavorite value.
        // toggleFavorite modifies multiple entries — each needs its own upload.
        // No pending-set entry needed here since isFavorite changes are low-stakes
        // and the listener will converge on the correct value.
        for entry in affectedEntries {
            let dto = FoodEntryDTO(from: entry)
            Task {
                try? await firestoreService.uploadFoodEntry(dto)
            }
        }
    }

    /// Inserts a pre-built FoodEntry and stamps it with the current user's identifier.
    /// Used for quick-log where the entry is constructed externally (AppCoordinator).
    func insertFoodEntry(_ entry: FoodEntry) async throws {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        // Stamp the userId — overrides whatever default was set at build time
        entry.userId = userId  // TODO: replace with Firebase UID in Phase 3
        modelContext.insert(entry)
        try modelContext.save()

        // Firestore sync: same pending-set pattern as addFoodEntry
        let dto = FoodEntryDTO(from: entry)
        FirestoreServiceImpl.shared.pendingUploadIds.insert(dto.id)
        Task {
            try? await firestoreService.uploadFoodEntry(dto)
        }

        // Firestore sync: also upsert the FoodFingerprint for this food.
        // FoodFingerprint has no @Model — only Firestore needs it.
        // Pending ID removed in applyFoodFingerprintUpdates when listener confirms.
        let fingerprintDTO = FoodFingerprintDTO(from: entry)
        FirestoreServiceImpl.shared.pendingFingerprintIds.insert(fingerprintDTO.id)
        Task {
            try? await firestoreService.uploadFoodFingerprint(fingerprintDTO)
        }
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

        let baselineToUpload: PersonalBaseline
        if let existing = try await getBaselineForDayOfWeek(dayOfWeek) {
            // Update existing baseline
            existing.updateWithNewData(calories: calories, purity: purity)
            baselineToUpload = existing
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
            baselineToUpload = baseline
        }

        try modelContext.save()

        // Firestore sync: upload the created/updated baseline.
        // Pending ID removed in applyPersonalBaselineUpdates when listener confirms the write.
        let dto = PersonalBaselineDTO(from: baselineToUpload)
        FirestoreServiceImpl.shared.pendingBaselineIds.insert(dto.id)
        Task {
            try? await firestoreService.uploadPersonalBaseline(dto)
        }
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

        // Firestore sync: upload after local write succeeds.
        // Pending ID removed in applyMoodEntryUpdates when listener confirms the write.
        let dto = MoodEntryDTO(from: entry)
        FirestoreServiceImpl.shared.pendingMoodEntryIds.insert(dto.id)
        Task {
            try? await firestoreService.uploadMoodEntry(dto)
        }

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

    // MARK: - CustomFood Methods

    /// Returns all custom foods for the current user, sorted by name
    func getCustomFoods() async throws -> [CustomFood] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }
        let descriptor = FetchDescriptor<CustomFood>(
            predicate: #Predicate { food in food.userId == userId },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Inserts a new CustomFood for the current user
    func addCustomFood(_ food: CustomFood) async throws {
        guard let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }
        food.userId = userId
        modelContext.insert(food)
        try modelContext.save()
    }

    /// Saves changes to an existing CustomFood
    func updateCustomFood(_ food: CustomFood) async throws {
        try modelContext.save()
    }

    /// Deletes a CustomFood from the store
    func deleteCustomFood(_ food: CustomFood) async throws {
        modelContext.delete(food)
        try modelContext.save()
    }

    // MARK: - SavedMeal Methods

    /// Returns all saved meals for the current user, sorted by name
    func getSavedMeals() async throws -> [SavedMeal] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }
        let descriptor = FetchDescriptor<SavedMeal>(
            predicate: #Predicate { meal in meal.userId == userId },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Inserts a new SavedMeal for the current user
    func addSavedMeal(_ meal: SavedMeal) async throws {
        guard let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }
        meal.userId = userId
        modelContext.insert(meal)
        try modelContext.save()
    }

    /// Saves changes to an existing SavedMeal
    func updateSavedMeal(_ meal: SavedMeal) async throws {
        try modelContext.save()
    }

    /// Deletes a SavedMeal from the store
    func deleteSavedMeal(_ meal: SavedMeal) async throws {
        modelContext.delete(meal)
        try modelContext.save()
    }

    // MARK: - SavedRecipe Methods

    /// Returns all saved recipes for the current user, sorted by name
    func getSavedRecipes() async throws -> [SavedRecipe] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }
        let descriptor = FetchDescriptor<SavedRecipe>(
            predicate: #Predicate { recipe in recipe.userId == userId },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Inserts a new SavedRecipe for the current user
    func addSavedRecipe(_ recipe: SavedRecipe) async throws {
        guard let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }
        recipe.userId = userId
        modelContext.insert(recipe)
        try modelContext.save()
    }

    /// Saves changes to an existing SavedRecipe
    func updateSavedRecipe(_ recipe: SavedRecipe) async throws {
        try modelContext.save()
    }

    /// Deletes a SavedRecipe from the store
    func deleteSavedRecipe(_ recipe: SavedRecipe) async throws {
        modelContext.delete(recipe)
        try modelContext.save()
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
