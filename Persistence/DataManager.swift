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

    // MARK: - Nutrition (adherence metric only)

    /// Stateless calculator reused for the 7-day adherence metric (Friend System
    /// Phase 3). Goal-evaluation logic stays in the Nutrition module — this is a
    /// private instance, not a merge of the modules.
    private let nutritionManager = NutritionManager()

    /// The identifier for the currently authenticated user.
    ///
    /// Read **live** from AuthService on every call — never cached locally.
    /// Returns nil when no session is active, causing all queries to short-circuit
    /// and return empty results, which prevents any stale or cross-user data.
    /// Returns "guest" when in guest mode — used as a local SwiftData scoping key only.
    private var currentUserId: String? {
        authService.currentUserEmail
    }

    /// True when the user is in an anonymous guest session.
    ///
    /// Used as the single gate for ALL Firestore entry points in this class.
    /// "guest" userId must never appear in any Firestore path.
    /// Always check this property — never infer guest state from userId.
    /// Internal (not private) so AppCoordinator can surface it for the profile
    /// comparison's `canCompare` gate (Friend System Phase 6).
    var isGuest: Bool { authService.isGuest }

    /// The current authenticated user's uid (Firebase UID), or nil for guests and
    /// unauthenticated sessions. Exposed (read-only) so the Guild UI can identify
    /// the owner and the current user within a roster — all guild logic still keys
    /// on uids stamped server-side; this never widens write access.
    var authenticatedUserId: String? {
        guard !isGuest, let id = currentUserId, !id.isEmpty else { return nil }
        return id
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
            FirestoreServiceImpl.shared.pendingCustomFoodIds.removeAll()
            FirestoreServiceImpl.shared.pendingSavedMealIds.removeAll()
            FirestoreServiceImpl.shared.pendingSavedRecipeIds.removeAll()
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

        if existingProgress.isEmpty {
            let progress = UserProgress(
                totalXP: 0,
                currentStreak: 0,
                longestStreak: 0,
                lastActiveDate: Date(),
                rr: Rank.startingRR
            )
            // Stamp the current user's identifier — userId read live, not cached
            progress.userId = userId
            modelContext.insert(progress)
            // NOTE: Do NOT upload to Firestore here.
            // The initial sync in startFirestoreSync will fetch Firestore first.
            // If a document already exists (returning user / reinstall), the merge
            // rules in applyUserProgressUpdate will restore real XP/streaks.
            // If no document exists (genuinely new user), uploadLocalProgressToFirestore
            // handles the first upload. Uploading 0 XP here would overwrite real data.
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
            defaultGoal.userId = userId
            modelContext.insert(defaultGoal)
            newDefaultGoal = defaultGoal
        }

        try modelContext.save()

        // Firestore sync: upload the newly created default goal (if any).
        // Skipped for guest users — no Firestore writes in guest mode.
        if !isGuest, let goal = newDefaultGoal {
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
        // Guest mode: never register any Firestore listeners or perform any remote I/O.
        // "guest" userId must never appear in a Firestore path.
        guard !isGuest else { return }

        // MARK: Real-time listeners (idempotent — safe to call from 3 DataManagers)
        //
        // Listener closures capture self STRONGLY on purpose: registration is
        // one-shot per user+model, so whichever DataManager registers must stay
        // alive for as long as its listeners do — even when the registrar is a
        // transient coordinator (e.g. the guest→account migration path). A weak
        // capture here left registered listeners pointing at a deallocated
        // DataManager: snapshots kept arriving but nothing reconciled until app
        // relaunch. Lifetime stays bounded — stopAllListeners (logout / user
        // switch) releases these closures and with them the DataManager.

        firestoreService.listenForFoodEntries(userId: userId) { dtos in
            Task { try? await self.applyFirestoreUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForDailyGoals(userId: userId) { dtos in
            Task { try? await self.applyDailyGoalUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForPersonalBaselines(userId: userId) { dtos in
            Task { try? await self.applyPersonalBaselineUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForFoodFingerprints(userId: userId) { dtos in
            // FoodFingerprint is not a SwiftData @Model — listener fires for cross-device
            // awareness of new foods but requires no local SwiftData writes.
            // FoodEntry sync (Phase 1) already carries all nutritional and favorite data.
            Task { await self.applyFoodFingerprintUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForMoodEntries(userId: userId) { dtos in
            Task { try? await self.applyMoodEntryUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForUserProgress(userId: userId) { dto in
            Task { try? await self.applyUserProgressUpdate(dto, userId: userId) }
        }

        firestoreService.listenForDailyQuests(userId: userId) { dtos in
            Task { try? await self.applyDailyQuestUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForCustomFoods(userId: userId) { dtos in
            Task { try? await self.applyCustomFoodUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForSavedMeals(userId: userId) { dtos in
            Task { try? await self.applySavedMealUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForSavedRecipes(userId: userId) { dtos in
            Task { try? await self.applySavedRecipeUpdates(dtos, userId: userId) }
        }

        firestoreService.listenForBadges(userId: userId) { dtos in
            Task { try? await self.applyBadgeUpdates(dtos, userId: userId) }
        }

        // Friend System Phase 2: server-authoritative, listener-driven.
        // These reconciles are the ONLY local writers for Friend/FriendRequest rows
        // — mutation paths never touch SwiftData and no pending sets exist for them.
        firestoreService.listenForFriends(userId: userId) { dtos in
            Task { try? await self.reconcileFriends(dtos, userId: userId) }
        }

        firestoreService.listenForIncomingRequests(userId: userId) { dtos in
            let snapshots = dtos.map {
                RequestSnapshot(otherUid: $0.fromUid, username: $0.fromUsername,
                                displayName: $0.fromDisplayName, createdAt: $0.createdAt)
            }
            Task { try? await self.reconcileRequests(snapshots, direction: "incoming", userId: userId) }
        }

        firestoreService.listenForSentRequests(userId: userId) { dtos in
            let snapshots = dtos.map {
                RequestSnapshot(otherUid: $0.toUid, username: $0.toUsername,
                                displayName: nil, createdAt: $0.createdAt)
            }
            Task { try? await self.reconcileRequests(snapshots, direction: "outgoing", userId: userId) }
        }

        // Sync displayName from account/info on login (source of truth for display name).
        Task { await self.syncDisplayNameFromAccountInfo(userId: userId) }

        // Backfill/heal the username → email login mapping on every login so
        // accounts that claimed a handle before this feature can sign in by username.
        Task { await self.syncLoginHandle(userId: userId) }

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
            // Fetch Firestore FIRST to decide direction — never blindly upload on reinstall.
            // If a document exists → merge it locally (restores real XP/streaks after reinstall).
            // If no document exists → genuinely new user → upload the local default 0 XP doc.
            // This prevents the bug where reinstall uploads 0 XP before seeing existing data.
            let remoteProgressDTO = try? await firestoreService.fetchUserProgress(userId: userId)
            if let remoteProgressDTO = remoteProgressDTO {
                try? await applyUserProgressUpdate(remoteProgressDTO, userId: userId)
            } else {
                // No Firestore document at all — new user. Upload the locally created default.
                await uploadLocalProgressToFirestore(userId: userId)
            }

            // --- DailyQuest ---
            if let remotequestDTOs = try? await firestoreService.fetchDailyQuests(userId: userId) {
                let remoteIds = Set(remotequestDTOs.map { $0.id })
                try? await applyDailyQuestUpdates(remotequestDTOs, userId: userId)
                // Upload local quests that don't exist in Firestore by UUID.
                // Guard: only upload if Firestore has NO quest for the same day + questType.
                // Prevents re-uploading freshly generated quests when Firestore already has
                // that type for today (stale ones from a previous install).
                let localQuests = (try? await fetchAllQuestsForSync(userId: userId)) ?? []
                for quest in localQuests where !remoteIds.contains(quest.id.uuidString) {
                    let hasMatchInFirestore = remotequestDTOs.contains {
                        Calendar.current.isDate($0.questDate, inSameDayAs: quest.date)
                            && $0.questType == quest.questType
                    }
                    if !hasMatchInFirestore {
                        try? await firestoreService.uploadDailyQuest(DailyQuestDTO(from: quest))
                    }
                }
            }

            // --- CustomFood ---
            if let remoteCustomFoodDTOs = try? await firestoreService.fetchCustomFoods(userId: userId) {
                let remoteIds = Set(remoteCustomFoodDTOs.map { $0.id })
                try? await applyCustomFoodUpdates(remoteCustomFoodDTOs, userId: userId)
                let localFoods = (try? await fetchAllCustomFoodsForSync(userId: userId)) ?? []
                for food in localFoods where !remoteIds.contains(food.id.uuidString) {
                    try? await firestoreService.uploadCustomFood(CustomFoodDTO(from: food))
                }
            }

            // --- SavedMeal ---
            if let remoteSavedMealDTOs = try? await firestoreService.fetchSavedMeals(userId: userId) {
                let remoteIds = Set(remoteSavedMealDTOs.map { $0.id })
                try? await applySavedMealUpdates(remoteSavedMealDTOs, userId: userId)
                let localMeals = (try? await fetchAllSavedMealsForSync(userId: userId)) ?? []
                for meal in localMeals where !remoteIds.contains(meal.id.uuidString) {
                    try? await firestoreService.uploadSavedMeal(SavedMealDTO(from: meal))
                }
            }

            // --- SavedRecipe ---
            if let remoteSavedRecipeDTOs = try? await firestoreService.fetchSavedRecipes(userId: userId) {
                let remoteIds = Set(remoteSavedRecipeDTOs.map { $0.id })
                try? await applySavedRecipeUpdates(remoteSavedRecipeDTOs, userId: userId)
                let localRecipes = (try? await fetchAllSavedRecipesForSync(userId: userId)) ?? []
                for recipe in localRecipes where !remoteIds.contains(recipe.id.uuidString) {
                    try? await firestoreService.uploadSavedRecipe(SavedRecipeDTO(from: recipe))
                }
            }

            // --- Public stats projection (Friend Leaderboard, Phase 3) ---
            // Publish after the initial sync has merged remote progress, so
            // friends see fresh numbers from the first app open of the day.
            await publishMyStats()
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

    /// Uploads the current local UserProgress to Firestore.
    /// Called only when Firestore has no existing progress document (genuinely new user).
    /// @MainActor required for modelContext access.
    @MainActor
    private func uploadLocalProgressToFirestore(userId: String) async {
        let descriptor = FetchDescriptor<UserProgress>(
            predicate: #Predicate { p in p.userId == userId }
        )
        guard let progress = (try? modelContext.fetch(descriptor))?.first else { return }
        Task { try? await firestoreService.uploadUserProgress(UserProgressDTO(from: progress)) }
    }

    // MARK: - Firestore Apply: UserProgress

    /// Applies an incoming Firestore UserProgress snapshot to local SwiftData using merge rules.
    ///
    /// Receive-only — never uploads. Merge rules for additive gamification fields:
    /// - `totalXP`, `currentStreak`, `longestStreak` → `max()` wins (never decrease)
    /// - `lastActiveDate` → `max()` wins
    /// - `claimedMilestones` → set union (milestones are never un-claimed)
    /// - `rr` → Firestore value wins (server-authoritative, NON-monotonic — never `max()`);
    ///   `rank` is a computed function of `rr`, never stored or read from the DTO
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
            // `rr` is server-authoritative and NON-monotonic (losses lower it) — Firestore wins,
            // never `max()`. Legacy docs without `rr` resolve to Rank.startingRR via resolvedRR.
            let mergedRR = dto.resolvedRR

            let isPending = FirestoreServiceImpl.shared.pendingProgressIds.contains(dto.id)
            if isPending {
                // Confirmation: Firestore must be "at least as good" as local for all additive fields.
                // A strictly higher value from a simultaneous device write is still a valid confirmation.
                // `rr` is intentionally excluded — it is non-monotonic, not additive.
                // TODO (D1): when duel resolution writes rr, add non-monotonic reconciliation for rr
                // here (a stale sync-down must not clobber a just-resolved local rr).
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
                || mergedRR != local.rr

            if changed {
                local.totalXP = mergedTotalXP
                local.currentStreak = mergedCurrentStreak
                local.longestStreak = mergedLongestStreak
                local.lastActiveDate = mergedLastActiveDate
                local.claimedMilestones = mergedClaimedString
                local.rr = mergedRR
                try modelContext.save()
            }
        } else {
            // Reinstall / cold start: no local UserProgress yet — insert from Firestore.
            // `toUserProgress` seeds `rr` (legacy nil → Rank.startingRR); rank is computed from rr.
            let progress = dto.toUserProgress(userId: userId)
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
                // Quest exists in Firestore but not locally by UUID.
                // Guard against stale quests from previous installs: skip the insert if a
                // local quest already exists for the same day + questType. Local data
                // (freshly generated this install) takes priority for that slot.
                let alreadyHasSlot = localQuests.contains {
                    Calendar.current.isDate($0.date, inSameDayAs: dto.questDate)
                        && $0.questType == dto.questType
                }
                guard !alreadyHasSlot else { continue }
                let quest = dto.toDailyQuest(userId: userId)
                modelContext.insert(quest)
                didChange = true
            }
        }

        // MARK: Dedup cleanup — remove local duplicates accumulated from multiple reinstalls.
        // For each (day, questType) slot, keep the best copy and delete the rest.
        // Priority: quest that exists in Firestore > completed quest > first in list.
        let remoteUUIDs = Set(dtos.map { $0.id })
        var slotMap: [String: [DailyQuest]] = [:]
        for quest in localQuests {
            let dayStart = Calendar.current.startOfDay(for: quest.date)
            let key = "\(dayStart.timeIntervalSince1970)-\(quest.questType)"
            slotMap[key, default: []].append(quest)
        }
        for (_, duplicates) in slotMap where duplicates.count > 1 {
            let sorted = duplicates.sorted {
                let aInFirestore = remoteUUIDs.contains($0.id.uuidString)
                let bInFirestore = remoteUUIDs.contains($1.id.uuidString)
                if aInFirestore != bInFirestore { return aInFirestore }
                if $0.isCompleted != $1.isCompleted { return $0.isCompleted }
                return true
            }
            for duplicate in sorted.dropFirst() {
                modelContext.delete(duplicate)
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

    // MARK: - Firestore Apply: CustomFood

    /// Diffs incoming Firestore CustomFood records against local SwiftData and applies updates.
    /// Receive-only — never uploads. Same conflict rules as applyFirestoreUpdates (FoodEntry).
    @MainActor
    private func applyCustomFoodUpdates(_ dtos: [CustomFoodDTO], userId: String) async throws {
        let descriptor = FetchDescriptor<CustomFood>(
            predicate: #Predicate { food in food.userId == userId }
        )
        let localFoods = try modelContext.fetch(descriptor)
        var localById: [String: CustomFood] = [:]
        for food in localFoods { localById[food.id.uuidString] = food }

        var didChange = false

        for dto in dtos {
            if let local = localById[dto.id] {
                let isPending = FirestoreServiceImpl.shared.pendingCustomFoodIds.contains(dto.id)
                if isPending {
                    if !dto.differsFrom(local) {
                        FirestoreServiceImpl.shared.pendingCustomFoodIds.remove(dto.id)
                    }
                } else if dto.differsFrom(local) {
                    local.name = dto.name
                    local.calories = dto.calories
                    local.protein = dto.protein
                    local.carbs = dto.carbs
                    local.fat = dto.fat
                    local.servingSizeName = dto.servingSizeName
                    local.servingSizeAmount = dto.servingSizeAmount
                    local.servingUnit = dto.servingUnit
                    local.toxinScore = dto.toxinScore
                    local.fiber = dto.fiber
                    local.sugar = dto.sugar
                    local.sodium = dto.sodium
                    didChange = true
                }
            } else {
                let food = dto.toCustomFood(userId: userId)
                modelContext.insert(food)
                didChange = true
            }
        }

        if didChange { try modelContext.save() }
    }

    /// Fetches all CustomFoods for a user with no filter.
    private func fetchAllCustomFoodsForSync(userId: String) async throws -> [CustomFood] {
        let descriptor = FetchDescriptor<CustomFood>(
            predicate: #Predicate { food in food.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Firestore Apply: SavedMeal

    /// Diffs incoming Firestore SavedMeal records against local SwiftData and applies updates.
    /// Receive-only — never uploads.
    @MainActor
    private func applySavedMealUpdates(_ dtos: [SavedMealDTO], userId: String) async throws {
        let descriptor = FetchDescriptor<SavedMeal>(
            predicate: #Predicate { meal in meal.userId == userId }
        )
        let localMeals = try modelContext.fetch(descriptor)
        var localById: [String: SavedMeal] = [:]
        for meal in localMeals { localById[meal.id.uuidString] = meal }

        var didChange = false

        for dto in dtos {
            if let local = localById[dto.id] {
                let isPending = FirestoreServiceImpl.shared.pendingSavedMealIds.contains(dto.id)
                if isPending {
                    if !dto.differsFrom(local) {
                        FirestoreServiceImpl.shared.pendingSavedMealIds.remove(dto.id)
                    }
                } else if dto.differsFrom(local) {
                    local.name = dto.name
                    local.componentsData = dto.componentsJSON.data(using: .utf8) ?? Data()
                    didChange = true
                }
            } else {
                let meal = dto.toSavedMeal(userId: userId)
                modelContext.insert(meal)
                didChange = true
            }
        }

        if didChange { try modelContext.save() }
    }

    /// Fetches all SavedMeals for a user with no filter.
    private func fetchAllSavedMealsForSync(userId: String) async throws -> [SavedMeal] {
        let descriptor = FetchDescriptor<SavedMeal>(
            predicate: #Predicate { meal in meal.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Firestore Apply: SavedRecipe

    /// Diffs incoming Firestore SavedRecipe records against local SwiftData and applies updates.
    /// Receive-only — never uploads.
    @MainActor
    private func applySavedRecipeUpdates(_ dtos: [SavedRecipeDTO], userId: String) async throws {
        let descriptor = FetchDescriptor<SavedRecipe>(
            predicate: #Predicate { recipe in recipe.userId == userId }
        )
        let localRecipes = try modelContext.fetch(descriptor)
        var localById: [String: SavedRecipe] = [:]
        for recipe in localRecipes { localById[recipe.id.uuidString] = recipe }

        var didChange = false

        for dto in dtos {
            if let local = localById[dto.id] {
                let isPending = FirestoreServiceImpl.shared.pendingSavedRecipeIds.contains(dto.id)
                if isPending {
                    if !dto.differsFrom(local) {
                        FirestoreServiceImpl.shared.pendingSavedRecipeIds.remove(dto.id)
                    }
                } else if dto.differsFrom(local) {
                    local.name = dto.name
                    local.yield = dto.yield
                    local.ingredientsData = dto.ingredientsJSON.data(using: .utf8) ?? Data()
                    local.purityScore = dto.purityScore
                    didChange = true
                }
            } else {
                let recipe = dto.toSavedRecipe(userId: userId)
                modelContext.insert(recipe)
                didChange = true
            }
        }

        if didChange { try modelContext.save() }
    }

    /// Fetches all SavedRecipes for a user with no filter.
    private func fetchAllSavedRecipesForSync(userId: String) async throws -> [SavedRecipe] {
        let descriptor = FetchDescriptor<SavedRecipe>(
            predicate: #Predicate { recipe in recipe.userId == userId }
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

        // Firestore sync: upload after local write succeeds. Skipped for guest users.
        if !isGuest {
            let dto = FoodEntryDTO(from: entry)
            FirestoreServiceImpl.shared.pendingUploadIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadFoodEntry(dto)
            }

            let fingerprintDTO = FoodFingerprintDTO(from: entry)
            FirestoreServiceImpl.shared.pendingFingerprintIds.insert(fingerprintDTO.id)
            Task {
                try? await firestoreService.uploadFoodFingerprint(fingerprintDTO)
            }

            // Friend Leaderboard (Phase 3): a logged food can change today's
            // adherence even when no XP is awarded — refresh the projection.
            Task {
                await publishMyStats()
            }
        }

        // Badge check: first meal, 100 meals
        Task {
            if let badges = try? await checkAndUnlockBadges(trigger: .foodLogged), !badges.isEmpty {
                await MainActor.run { BadgeToastQueue.shared.enqueue(badges) }
            }
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
        // Skipped for guest users — "guest" must never appear in a Firestore path.
        if !isGuest {
            Task {
                try? await firestoreService.deleteFoodEntry(id: entryId, userId: userId)
            }

            // Friend Leaderboard (Phase 3): deletion can change today's adherence.
            Task {
                await publishMyStats()
            }
        }
    }

    /// Updates an existing food entry (changes tracked by SwiftData).
    func updateFoodEntry(_ entry: FoodEntry) async throws {
        try modelContext.save()

        // Firestore sync: re-upload the entry with its updated fields. Skipped for guests.
        if !isGuest {
            let dto = FoodEntryDTO(from: entry)
            Task {
                try? await firestoreService.uploadFoodEntry(dto)
            }

            // Friend Leaderboard (Phase 3): edited macros can change adherence.
            Task {
                await publishMyStats()
            }
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

        // Firestore sync: upload the created/updated goal. Skipped for guests.
        if !isGuest {
            let dto = DailyGoalDTO(from: goalToUpload)
            FirestoreServiceImpl.shared.pendingDailyGoalIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadDailyGoal(dto)
            }
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

        // Firestore sync: re-upload UserProgress after every local save. Skipped for guests.
        guard !isGuest else { return }
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

        // Friend Leaderboard (Phase 3): single publish chokepoint. Every
        // UserProgress mutation (XP, streak, rank, milestones) funnels through
        // this save, so this one hook keeps the friend-readable projection
        // fresh for all award paths. Fire-and-forget — never blocks UI.
        Task {
            await publishMyStats()
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

        // Firestore sync: upload new quest after local insert succeeds. Skipped for guests.
        if !isGuest {
            let dto = DailyQuestDTO(from: quest)
            FirestoreServiceImpl.shared.pendingQuestIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadDailyQuest(dto)
            }
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
        // Skipped for guest users.
        guard !isGuest else { return }
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

        // Friend Leaderboard (Phase 3): quick-logged food changes adherence.
        // publishMyStats guest-guards itself, so no extra gate is needed here.
        Task {
            await publishMyStats()
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

        // Firestore sync: upload after local write succeeds. Skipped for guests.
        if !isGuest {
            let dto = MoodEntryDTO(from: entry)
            FirestoreServiceImpl.shared.pendingMoodEntryIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadMoodEntry(dto)
            }
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

        // Firestore sync: upload after local write succeeds. Skipped for guests.
        if !isGuest {
            let dto = CustomFoodDTO(from: food)
            FirestoreServiceImpl.shared.pendingCustomFoodIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadCustomFood(dto)
            }
        }
    }

    /// Saves changes to an existing CustomFood
    func updateCustomFood(_ food: CustomFood) async throws {
        try modelContext.save()

        // Firestore sync: re-upload the food with its updated fields. Skipped for guests.
        if !isGuest {
            let dto = CustomFoodDTO(from: food)
            Task {
                try? await firestoreService.uploadCustomFood(dto)
            }
        }
    }

    /// Deletes a CustomFood from the store
    func deleteCustomFood(_ food: CustomFood) async throws {
        let foodId = food.id.uuidString
        let userId = food.userId

        modelContext.delete(food)
        try modelContext.save()

        // Firestore sync: remove the document after local delete succeeds. Skipped for guests.
        if !isGuest {
            Task {
                try? await firestoreService.deleteCustomFood(id: foodId, userId: userId)
            }
        }
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

        // Firestore sync: upload after local write succeeds. Skipped for guests.
        if !isGuest {
            let dto = SavedMealDTO(from: meal)
            FirestoreServiceImpl.shared.pendingSavedMealIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadSavedMeal(dto)
            }
        }
    }

    /// Saves changes to an existing SavedMeal
    func updateSavedMeal(_ meal: SavedMeal) async throws {
        try modelContext.save()

        // Firestore sync: re-upload the meal with its updated fields. Skipped for guests.
        if !isGuest {
            let dto = SavedMealDTO(from: meal)
            Task {
                try? await firestoreService.uploadSavedMeal(dto)
            }
        }
    }

    /// Deletes a SavedMeal from the store
    func deleteSavedMeal(_ meal: SavedMeal) async throws {
        let mealId = meal.id.uuidString
        let userId = meal.userId

        modelContext.delete(meal)
        try modelContext.save()

        // Firestore sync: remove the document after local delete succeeds. Skipped for guests.
        if !isGuest {
            Task {
                try? await firestoreService.deleteSavedMeal(id: mealId, userId: userId)
            }
        }
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

        // Firestore sync: upload after local write succeeds. Skipped for guests.
        if !isGuest {
            let dto = SavedRecipeDTO(from: recipe)
            FirestoreServiceImpl.shared.pendingSavedRecipeIds.insert(dto.id)
            Task {
                try? await firestoreService.uploadSavedRecipe(dto)
            }
        }
    }

    /// Saves changes to an existing SavedRecipe
    func updateSavedRecipe(_ recipe: SavedRecipe) async throws {
        try modelContext.save()

        // Firestore sync: re-upload the recipe with its updated fields. Skipped for guests.
        if !isGuest {
            let dto = SavedRecipeDTO(from: recipe)
            Task {
                try? await firestoreService.uploadSavedRecipe(dto)
            }
        }
    }

    /// Deletes a SavedRecipe from the store
    func deleteSavedRecipe(_ recipe: SavedRecipe) async throws {
        let recipeId = recipe.id.uuidString
        let userId = recipe.userId

        modelContext.delete(recipe)
        try modelContext.save()

        // Firestore sync: remove the document after local delete succeeds. Skipped for guests.
        if !isGuest {
            Task {
                try? await firestoreService.deleteSavedRecipe(id: recipeId, userId: userId)
            }
        }
    }

    // MARK: - Quick-Log Capture (Phase 10)

    /// Converts AI-recognized items into SavedMealComponents (pure, no side
    /// effects). Excludes any item with a blank name or a negative macro/calorie
    /// value; the rest convert. Purity defaults to 50 (neutral) — the AI gives no
    /// toxin data, and 0 would falsely claim "perfectly clean."
    static func components(from items: [RecognizedFoodItem]) -> [SavedMealComponent] {
        items.compactMap { item -> SavedMealComponent? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            guard item.calories >= 0, item.protein >= 0, item.carbs >= 0, item.fat >= 0 else { return nil }

            let (quantity, unit) = parseQuantity(item.quantityText)
            return SavedMealComponent(
                foodName: name,
                quantity: quantity,
                servingUnit: unit,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                toxinScore: 50
            )
        }
    }

    /// Deterministic quantity parse: a leading decimal or simple fraction →
    /// (number, remainder-as-unit); otherwise (1, full text). Empty ⇒ (1, "serving").
    static func parseQuantity(_ text: String) -> (quantity: Double, unit: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (1, "serving") }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let leading = String(parts.first ?? "")
        if let number = parseLeadingNumber(leading) {
            let remainder = parts.count > 1
                ? String(parts[1]).trimmingCharacters(in: .whitespaces)
                : ""
            return (number, remainder.isEmpty ? "serving" : remainder)
        }
        // No leading number — keep the whole text as the unit, quantity 1.
        return (1, trimmed)
    }

    /// Parses a single leading token as a Double or a simple integer fraction
    /// ("1/2" → 0.5). Returns nil if neither.
    private static func parseLeadingNumber(_ token: String) -> Double? {
        if token.contains("/") {
            let sides = token.split(separator: "/")
            if sides.count == 2, let n = Int(sides[0]), let d = Int(sides[1]), d != 0 {
                return Double(n) / Double(d)
            }
            return nil
        }
        return Double(token)
    }

    /// Identity signature for true-duplicate detection: case-insensitive name
    /// plus the component set (ignoring per-component UUIDs — those regenerate on
    /// every conversion). Two saves with the same name and the same items produce
    /// the same signature, so we never create a second identical meal/recipe.
    static func contentSignature(name: String, components: [SavedMealComponent]) -> String {
        let body = components
            .map { "\($0.foodName.lowercased())|\($0.quantity)|\($0.calories)|\($0.protein)|\($0.carbs)|\($0.fat)|\($0.toxinScore)" }
            .sorted()
            .joined(separator: ";")
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "##" + body
    }

    /// Calorie-weighted average purity — mirrors RecipeBuilderView.recipePurityScore.
    static func recipePurity(of components: [SavedMealComponent]) -> Int {
        let totalCalories = components.reduce(0) { $0 + $1.calories }
        guard totalCalories > 0 else { return 0 }
        let weighted = components.reduce(0.0) { $0 + Double($1.calories) * Double($1.toxinScore) }
        return Int(weighted / Double(totalCalories))
    }

    /// Converts + saves recognized items as a SavedMeal via the existing add
    /// pipeline. Returns the created model so the caller can chain Share (Phase 9).
    func saveQuickLog(asMealNamed name: String, items: [RecognizedFoodItem]) async throws -> SavedMeal {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw QuickLogError.emptyName }

        let components = DataManager.components(from: items)
        guard !components.isEmpty else { throw QuickLogError.nothingToSave }

        // Dedup: if an identical meal (same name + items) already exists, return
        // it instead of creating a duplicate.
        let signature = DataManager.contentSignature(name: trimmed, components: components)
        let existing = (try? await getSavedMeals()) ?? []
        if let dup = existing.first(where: {
            DataManager.contentSignature(name: $0.name, components: $0.components) == signature
        }) {
            return dup
        }

        // Same construction MealBuilderView uses — SavedMeal(name:components:)
        // encodes componentsData; addSavedMeal handles local save + Firestore.
        let meal = SavedMeal(name: trimmed, components: components)
        try await addSavedMeal(meal)
        return meal
    }

    /// Converts + saves recognized items as a SavedRecipe via the existing add
    /// pipeline. Sets yield (≥1) and the calorie-weighted purityScore.
    func saveQuickLog(asRecipeNamed name: String, yield: Int, items: [RecognizedFoodItem]) async throws -> SavedRecipe {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw QuickLogError.emptyName }

        let components = DataManager.components(from: items)
        guard !components.isEmpty else { throw QuickLogError.nothingToSave }

        // Dedup: identical recipe = same name + items + yield.
        let resolvedYield = max(1, yield)
        let signature = DataManager.contentSignature(name: trimmed, components: components) + "#y\(resolvedYield)"
        let existing = (try? await getSavedRecipes()) ?? []
        if let dup = existing.first(where: {
            DataManager.contentSignature(name: $0.name, components: $0.ingredients) + "#y\($0.yield)" == signature
        }) {
            return dup
        }

        // Same construction RecipeBuilderView uses.
        let recipe = SavedRecipe(name: trimmed, yield: resolvedYield, ingredients: components)
        recipe.purityScore = DataManager.recipePurity(of: components)
        try await addSavedRecipe(recipe)
        return recipe
    }

    // MARK: - UserProfile Methods

    /// Fetches the UserProfile for the current user.
    ///
    /// Returns the most recently updated profile if duplicates exist (and deletes them).
    /// Returns nil if no profile exists or no user is authenticated.
    func getUserProfile() async throws -> UserProfile? {
        guard let userId = currentUserId, !userId.isEmpty else { return nil }

        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { profile in profile.userId == userId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let profiles = try modelContext.fetch(descriptor)

        // Clean up duplicates: keep the most recently updated, delete the rest
        if profiles.count > 1 {
            for duplicate in profiles.dropFirst() {
                modelContext.delete(duplicate)
            }
            try modelContext.save()
        }

        return profiles.first
    }

    /// Upserts a UserProfile for the current user.
    ///
    /// If a profile already exists, updates it in-place (preserving the SwiftData object identity).
    /// If no profile exists, inserts the provided profile.
    /// Always stamps userId and saves context. Syncs to Firestore after local save.
    func upsertUserProfile(_ profile: UserProfile) async throws {
        guard let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }

        let existing = try await getUserProfile()

        if let existing = existing {
            // Update in-place — preserve the existing SwiftData object
            existing.sex = profile.sex
            existing.age = profile.age
            existing.weightKg = profile.weightKg
            existing.heightCm = profile.heightCm
            existing.goalWeightKg = profile.goalWeightKg
            existing.weeklyPaceLbs = profile.weeklyPaceLbs
            existing.activityLevel = profile.activityLevel
            existing.dietStyle = profile.dietStyle
            existing.mealsPerDay = profile.mealsPerDay
            existing.allergies = profile.allergies
            existing.sleepQuality = profile.sleepQuality
            existing.stressLevel = profile.stressLevel
            existing.aiTip = profile.aiTip
            existing.setupCompleted = profile.setupCompleted
            existing.updatedAt = profile.updatedAt
        } else {
            profile.userId = userId
            modelContext.insert(profile)
        }

        try modelContext.save()

        // Firestore sync: full document replace (source of truth). Skipped for guests.
        if !isGuest {
            let profileToSync = existing ?? profile
            let dto = UserProfileDTO(from: profileToSync)
            Task {
                try? await firestoreService.uploadUserProfile(dto, userId: userId)
            }
        }
    }

    /// Updates today's DailyGoal calorie + macro targets, overwriting completely (no merge).
    ///
    /// Gets or creates today's goal, then overwrites the four main macro targets.
    /// Other goal fields (purity, advanced nutrition) are left unchanged.
    func updateDailyGoalTargets(calories: Int, protein: Int, carbs: Int, fat: Int) async throws {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        if let existing = try await getTodaysGoal() {
            existing.calorieTarget = calories
            existing.proteinTarget = Double(protein)
            existing.carbTarget = Double(carbs)
            existing.fatTarget = Double(fat)
            try modelContext.save()

            // Firestore sync. Skipped for guests.
            if !isGuest {
                let dto = DailyGoalDTO(from: existing)
                FirestoreServiceImpl.shared.pendingDailyGoalIds.insert(dto.id)
                Task {
                    try? await firestoreService.uploadDailyGoal(dto)
                }
            }
        } else {
            // No goal exists yet — create one with sensible purity default
            let goal = DailyGoal(
                date: Date(),
                calorieTarget: calories,
                proteinTarget: Double(protein),
                carbTarget: Double(carbs),
                fatTarget: Double(fat),
                purityTarget: 30
            )
            goal.userId = userId
            modelContext.insert(goal)
            try modelContext.save()

            // Firestore sync. Skipped for guests.
            if !isGuest {
                let dto = DailyGoalDTO(from: goal)
                FirestoreServiceImpl.shared.pendingDailyGoalIds.insert(dto.id)
                Task {
                    try? await firestoreService.uploadDailyGoal(dto)
                }
            }
        }
    }

    /// Syncs the UserProfile from Firestore, overwriting local if different.
    ///
    /// If Firestore has no record → no-op.
    /// If local exists and matches → no-op.
    /// If local doesn't exist or differs → upsert from Firestore DTO.
    func syncUserProfileFromFirestore() async throws {
        // Guest mode: never read from Firestore.
        guard !isGuest else { return }
        guard let userId = currentUserId, !userId.isEmpty else { return }

        guard let dto = try await firestoreService.fetchUserProfile(userId: userId) else { return }

        let local = try await getUserProfile()
        if let local = local, !dto.differsFrom(local) { return }

        // Build a profile from the remote DTO and upsert locally (skip remote re-upload)
        let remoteProfile = dto.toUserProfile(userId: userId)
        if let existing = local {
            existing.sex = remoteProfile.sex
            existing.age = remoteProfile.age
            existing.weightKg = remoteProfile.weightKg
            existing.heightCm = remoteProfile.heightCm
            existing.goalWeightKg = remoteProfile.goalWeightKg
            existing.weeklyPaceLbs = remoteProfile.weeklyPaceLbs
            existing.activityLevel = remoteProfile.activityLevel
            existing.dietStyle = remoteProfile.dietStyle
            existing.mealsPerDay = remoteProfile.mealsPerDay
            existing.allergies = remoteProfile.allergies
            existing.sleepQuality = remoteProfile.sleepQuality
            existing.stressLevel = remoteProfile.stressLevel
            existing.aiTip = remoteProfile.aiTip
            existing.setupCompleted = remoteProfile.setupCompleted
            existing.updatedAt = remoteProfile.updatedAt
        } else {
            modelContext.insert(remoteProfile)
        }
        try modelContext.save()
    }

    // MARK: - DisplayName Sync

    /// Fetches account/info from Firestore and updates UserProfile.displayName locally.
    ///
    /// Called once per login from startFirestoreSync. Does NOT re-upload to Firestore
    /// to avoid an infinite loop (Firestore → local only).
    func syncDisplayNameFromAccountInfo(userId: String) async {
        // Called from startFirestoreSync which is already guarded, but double-check for safety.
        guard !isGuest, !userId.isEmpty else { return }

        let accountInfo = try? await firestoreService.fetchAccountInfo(userId: userId)

        let resolvedName: String
        if let name = accountInfo?.displayName, !name.isEmpty {
            resolvedName = name
        } else if let firebaseName = authService.currentUserDisplayName, !firebaseName.isEmpty {
            resolvedName = firebaseName
        } else {
            return // Nothing to sync
        }

        guard let profile = try? await getUserProfile() else { return }
        guard profile.displayName != resolvedName else { return }

        profile.displayName = resolvedName
        try? modelContext.save()
    }

    // MARK: - Badge Methods

    /// Returns the BadgeProgress record for the given badge, scoped to current user.
    func getBadgeProgress(badgeId: String) async throws -> BadgeProgress? {
        guard let userId = currentUserId, !userId.isEmpty else { return nil }
        let descriptor = FetchDescriptor<BadgeProgress>(
            predicate: #Predicate { $0.userId == userId && $0.badgeId == badgeId }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Returns all BadgeProgress records for the current user.
    func getAllBadgeProgress() async throws -> [BadgeProgress] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }
        let descriptor = FetchDescriptor<BadgeProgress>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Creates or updates a BadgeProgress record. Append-only: never reverts isUnlocked from true.
    func upsertBadgeProgress(badgeId: String, isUnlocked: Bool, unlockedAt: Date?) async throws {
        guard let userId = currentUserId, !userId.isEmpty else { return }

        if let existing = try await getBadgeProgress(badgeId: badgeId) {
            // Never revert an already-unlocked badge
            if existing.isUnlocked { return }
            existing.isUnlocked = isUnlocked
            existing.unlockedAt = unlockedAt
        } else {
            let progress = BadgeProgress(
                userId: userId,
                badgeId: badgeId,
                isUnlocked: isUnlocked,
                unlockedAt: unlockedAt
            )
            modelContext.insert(progress)
        }
        try modelContext.save()
    }

    /// Returns the total number of food entries for the current user (across all dates).
    func countAllFoodEntries() async throws -> Int {
        guard let userId = currentUserId, !userId.isEmpty else { return 0 }
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try modelContext.fetchCount(descriptor)
    }

    /// Returns true if every DailyQuest for today is completed (for the current user).
    func areAllQuestsCompletedToday() async throws -> Bool {
        guard let userId = currentUserId, !userId.isEmpty else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { $0.userId == userId && $0.date >= today && $0.date < tomorrow }
        )
        let quests = try modelContext.fetch(descriptor)
        guard !quests.isEmpty else { return false }
        return quests.allSatisfy { $0.isCompleted }
    }

    /// Checks badge unlock conditions for the given trigger. Idempotent — safe to call repeatedly.
    ///
    /// Returns only newly-unlocked badges (badges that were locked before this call).
    /// Callers should enqueue the result into `BadgeToastQueue.shared`.
    @discardableResult
    func checkAndUnlockBadges(trigger: BadgeTrigger) async throws -> [BadgeDefinition] {
        var newlyUnlocked: [BadgeDefinition] = []

        func unlock(_ badgeId: String) async throws {
            guard let def = BadgeDefinition.find(id: badgeId) else { return }
            let existing = try await getBadgeProgress(badgeId: badgeId)
            if existing?.isUnlocked == true { return }

            try await upsertBadgeProgress(badgeId: badgeId, isUnlocked: true, unlockedAt: Date())

            // Firestore sync for badge unlock. Skipped for guests.
            if !isGuest, let userId = currentUserId, !userId.isEmpty {
                let dto = BadgeProgressDTO(
                    userId: userId,
                    badgeId: badgeId,
                    isUnlocked: true,
                    unlockedAt: Date()
                )
                FirestoreServiceImpl.shared.pendingBadgeIds.insert(badgeId)
                Task { try? await firestoreService.uploadBadgeProgress(dto, userId: userId) }
            }

            newlyUnlocked.append(def)

            // Friend activity feed (Phase 7): this closure only reaches here on a
            // genuine false→true unlock (already-unlocked badges early-returned),
            // so this emits exactly one event per newly earned badge.
            emitFeedEvent(type: "badge", value: badgeId)
        }

        switch trigger {
        case .foodLogged:
            let count = try await countAllFoodEntries()
            if count >= 1 { try await unlock("first_flame") }
            if count >= 100 { try await unlock("century") }

        case .streakUpdated:
            let streakProgress = try await getUserProgress()
            if streakProgress.currentStreak >= 7 { try await unlock("week_warrior") }
            if streakProgress.currentStreak >= 30 { try await unlock("month_legend") }

        case .questsChecked:
            if try await areAllQuestsCompletedToday() { try await unlock("goal_getter") }

        case .xpAwarded:
            let xpProgress = try await getUserProgress()
            if xpProgress.currentLevel >= 5 { try await unlock("level_up") }
        }

        return newlyUnlocked
    }

    // MARK: - Username (Friend System Phase 1)

    /// Returns the current user's canonical username, or nil if unclaimed.
    /// Returns nil for guests and unauthenticated sessions (no Firestore read).
    func currentUsername() async -> String? {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return nil }
        return try? await firestoreService.fetchUsername(userId: userId)
    }

    /// True when an authenticated (non-guest) user has not yet claimed a username.
    /// Always false for guests (guests never claim).
    /// Returns false on network failure — never force the gate when we can't verify.
    func needsUsername() async -> Bool {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return false }
        do {
            let name = try await firestoreService.fetchUsername(userId: userId)
            return (name ?? "").isEmpty
        } catch {
            // Network failure — don't force the gate, let the user through.
            // The gate will re-evaluate on next .task(id:) trigger.
            return false
        }
    }

    /// Validates + claims a username for the current user.
    /// Validation runs locally first (throws UsernameError.invalidFormat on failure),
    /// then delegates the atomic claim to FirestoreService.
    /// Guests and unauthenticated callers throw UsernameError.notAuthenticated.
    func claimUsername(_ raw: String) async throws {
        guard !isGuest else { throw UsernameError.notAuthenticated }
        guard let userId = currentUserId, !userId.isEmpty else { throw UsernameError.notAuthenticated }
        let handleKey = try DataManager.normalizeAndValidateUsername(raw)
        try await firestoreService.claimUsername(handleKey, userId: userId)

        // Write the username → email login mapping so this handle can be used
        // to sign in. Non-fatal: the login backfill heals a missed write.
        if let email = authService.currentUserActualEmail, !email.isEmpty {
            try? await firestoreService.upsertLoginHandle(handleKey: handleKey, uid: userId, email: email)
        }
    }

    /// Creates or repairs the username → email login mapping for the current user.
    /// Called once per login from startFirestoreSync; safe to call repeatedly.
    /// Logs the outcome so a rules rejection is visible in the Xcode console
    /// instead of failing silently.
    func syncLoginHandle(userId: String) async {
        guard !isGuest, !userId.isEmpty else { return }
        guard let username = try? await firestoreService.fetchUsername(userId: userId),
              !username.isEmpty else {
            print("HealthBar loginHandle backfill: skipped — no username on account/info")
            return
        }
        guard let email = authService.currentUserActualEmail, !email.isEmpty else {
            print("HealthBar loginHandle backfill: skipped — no auth email")
            return
        }

        // Skip the write when the mapping is already correct.
        if let existing = try? await firestoreService.lookupLoginEmail(forHandleKey: username),
           existing == email {
            print("HealthBar loginHandle backfill: @\(username) already mapped")
            return
        }

        do {
            try await firestoreService.upsertLoginHandle(handleKey: username, uid: userId, email: email)
            print("HealthBar loginHandle backfill: wrote mapping for @\(username)")
        } catch {
            print("HealthBar loginHandle backfill FAILED for @\(username): \(error.localizedDescription)")
        }
    }

    /// Fetches the full AccountInfoDTO for the current user.
    /// Returns nil for guests and unauthenticated sessions (no Firestore read).
    func fetchAccountInfo() async -> AccountInfoDTO? {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return nil }
        return try? await firestoreService.fetchAccountInfo(userId: userId)
    }

    /// Changes the current user's username from their existing handle to a new one.
    /// Enforces a 30-day cooldown between username changes.
    /// Guests and unauthenticated callers throw UsernameError.notAuthenticated.
    func changeUsername(to raw: String) async throws {
        guard !isGuest else { throw UsernameError.notAuthenticated }
        guard let userId = currentUserId, !userId.isEmpty else { throw UsernameError.notAuthenticated }

        // Read old handle + cooldown directly from document fields (not Codable)
        // to avoid decode failures from FieldValue.serverTimestamp() type mismatches.
        let oldHandle = try await firestoreService.fetchUsername(userId: userId)

        guard let oldHandle, !oldHandle.isEmpty else {
            // No existing username — use the initial claim flow instead
            let handleKey = try DataManager.normalizeAndValidateUsername(raw)
            try await firestoreService.claimUsername(handleKey, userId: userId)
            return
        }

        // Enforce 30-day cooldown by reading the raw field
        let snapshot = try await FirestoreServiceImpl.shared.fetchAccountInfoRaw(userId: userId)
        if let lastChangeTimestamp = snapshot?["lastUsernameChangeAt"] {
            let lastChange: Date
            if let ts = lastChangeTimestamp as? Date {
                lastChange = ts
            } else if let ts = lastChangeTimestamp as? NSNumber {
                lastChange = Date(timeIntervalSince1970: ts.doubleValue)
            } else {
                lastChange = .distantPast
            }
            let cooldownEnd = Calendar.current.date(byAdding: .day, value: 30, to: lastChange)!
            if Date() < cooldownEnd {
                throw UsernameError.cooldownActive(cooldownEnd)
            }
        }

        let newHandle = try DataManager.normalizeAndValidateUsername(raw)

        // Same handle — no-op
        guard newHandle != oldHandle else { return }

        try await firestoreService.changeUsername(from: oldHandle, to: newHandle, userId: userId)

        // Move the username → email login mapping to the new handle.
        // Non-fatal: the login backfill heals a missed write.
        try? await firestoreService.deleteLoginHandle(handleKey: oldHandle, uid: userId)
        if let email = authService.currentUserActualEmail, !email.isEmpty {
            try? await firestoreService.upsertLoginHandle(handleKey: newHandle, uid: userId, email: email)
        }
    }

    /// Returns the date when the user can next change their display name, or nil if no cooldown is active.
    /// Weekly cooldown (7 days from lastDisplayNameChangeAt).
    func displayNameCooldownEnd() async -> Date? {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return nil }
        guard let data = try? await FirestoreServiceImpl.shared.fetchAccountInfoRaw(userId: userId) else { return nil }
        let lastChange: Date?
        if let ts = data["lastDisplayNameChangeAt"] as? Date {
            lastChange = ts
        } else {
            lastChange = nil
        }
        guard let lastChange else { return nil }
        let cooldownEnd = Calendar.current.date(byAdding: .day, value: 7, to: lastChange)!
        return Date() < cooldownEnd ? cooldownEnd : nil
    }

    /// Returns the date when the user can next change their username, or nil if no cooldown is active.
    /// Monthly cooldown (30 days from lastUsernameChangeAt).
    func usernameCooldownEnd() async -> Date? {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return nil }
        guard let data = try? await FirestoreServiceImpl.shared.fetchAccountInfoRaw(userId: userId) else { return nil }
        let lastChange: Date?
        if let ts = data["lastUsernameChangeAt"] as? Date {
            lastChange = ts
        } else {
            lastChange = nil
        }
        guard let lastChange else { return nil }
        let cooldownEnd = Calendar.current.date(byAdding: .day, value: 30, to: lastChange)!
        return Date() < cooldownEnd ? cooldownEnd : nil
    }

    /// Normalizes and validates a raw username input.
    /// Returns the canonical lowercased handle on success; throws UsernameError.invalidFormat on failure.
    static func normalizeAndValidateUsername(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()

        let regex = try! NSRegularExpression(pattern: "^[a-z][a-z0-9_]{2,19}$")
        let range = NSRange(lowercased.startIndex..., in: lowercased)
        guard regex.firstMatch(in: lowercased, range: range) != nil else {
            throw UsernameError.invalidFormat
        }

        let reserved: Set<String> = [
            "admin", "root", "support", "system", "healthbar",
            "healthbarapp", "guest", "null", "undefined", "me", "you",
            "official", "staff", "team", "founder", "developer",
            "mod", "moderator"
        ]
        guard !reserved.contains(lowercased) else {
            throw UsernameError.invalidFormat
        }

        return lowercased
    }

    // MARK: - Friends (Friend System Phase 2)

    /// Normalized request snapshot fed into reconcileRequests for both directions.
    /// Incoming requests carry the sender's display name; outgoing mirrors carry nil.
    private struct RequestSnapshot {
        let otherUid: String
        let username: String
        let displayName: String?
        let createdAt: Date
    }

    /// Reconciles the Firestore friends snapshot into local SwiftData.
    ///
    /// The single local writer for Friend rows: upserts from DTOs, deletes locals
    /// absent from the snapshot, one save if anything changed. Scoped to `userId`.
    @MainActor
    private func reconcileFriends(_ dtos: [FriendDTO], userId: String) async throws {
        let descriptor = FetchDescriptor<Friend>(
            predicate: #Predicate { $0.userId == userId }
        )
        let locals = try modelContext.fetch(descriptor)
        var localByUid: [String: Friend] = [:]
        for friend in locals { localByUid[friend.friendUid] = friend }

        var didChange = false
        var remoteUids = Set<String>()

        for dto in dtos {
            remoteUids.insert(dto.friendUid)
            if let local = localByUid[dto.friendUid] {
                if local.username != dto.friendUsername
                    || local.displayName != dto.friendDisplayName
                    || local.since != dto.since {
                    local.username = dto.friendUsername
                    local.displayName = dto.friendDisplayName
                    local.since = dto.since
                    didChange = true
                }
            } else {
                modelContext.insert(Friend(
                    userId: userId,
                    friendUid: dto.friendUid,
                    username: dto.friendUsername,
                    displayName: dto.friendDisplayName,
                    since: dto.since
                ))
                didChange = true
            }
        }

        for local in locals where !remoteUids.contains(local.friendUid) {
            modelContext.delete(local)
            didChange = true
        }

        if didChange { try modelContext.save() }
    }

    /// Reconciles one direction of friend requests into local SwiftData.
    ///
    /// CRITICAL: fetches and deletes only rows matching `userId` AND the passed
    /// `direction`, so the incoming-requests listener never deletes outgoing rows
    /// and vice-versa.
    @MainActor
    private func reconcileRequests(_ snapshots: [RequestSnapshot], direction: String, userId: String) async throws {
        let descriptor = FetchDescriptor<FriendRequest>(
            predicate: #Predicate { $0.userId == userId && $0.direction == direction }
        )
        let locals = try modelContext.fetch(descriptor)
        var localByUid: [String: FriendRequest] = [:]
        for request in locals { localByUid[request.otherUid] = request }

        var didChange = false
        var remoteUids = Set<String>()

        for snapshot in snapshots {
            remoteUids.insert(snapshot.otherUid)
            if let local = localByUid[snapshot.otherUid] {
                if local.username != snapshot.username
                    || local.displayName != snapshot.displayName
                    || local.createdAt != snapshot.createdAt {
                    local.username = snapshot.username
                    local.displayName = snapshot.displayName
                    local.createdAt = snapshot.createdAt
                    didChange = true
                }
            } else {
                modelContext.insert(FriendRequest(
                    userId: userId,
                    otherUid: snapshot.otherUid,
                    direction: direction,
                    username: snapshot.username,
                    displayName: snapshot.displayName,
                    createdAt: snapshot.createdAt
                ))
                didChange = true
            }
        }

        for local in locals where !remoteUids.contains(local.otherUid) {
            modelContext.delete(local)
            didChange = true
        }

        if didChange { try modelContext.save() }
    }

    /// Returns all cached friends for the current user (listener-maintained).
    func fetchFriends() async throws -> [Friend] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Friend>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Returns all cached friend requests for the current user in one direction
    /// ("incoming" or "outgoing").
    func fetchRequests(direction: String) async throws -> [FriendRequest] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }
        let descriptor = FetchDescriptor<FriendRequest>(
            predicate: #Predicate { $0.userId == userId && $0.direction == direction }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Local-only lookup of a cached incoming request. Used by acceptIncomingRequest
    /// to read the sender's identity snapshot — keeps accept listener-owned (no
    /// Firestore read for the snapshot).
    func fetchIncomingRequest(fromUid: String) -> FriendRequest? {
        guard let userId = currentUserId, !userId.isEmpty else { return nil }
        var descriptor = FetchDescriptor<FriendRequest>(
            predicate: #Predicate { $0.userId == userId && $0.otherUid == fromUid && $0.direction == "incoming" }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Classifies the relationship with `uid` from cached local rows only.
    ///
    /// Pure, local, synchronous — no network. Order of precedence:
    /// friends > incomingPending > outgoingPending > none. Local state can be
    /// stale, so sendFriendRequest still performs the authoritative server read.
    func friendshipState(with uid: String) -> FriendshipState {
        guard let userId = currentUserId, !userId.isEmpty else { return .none }

        let friendDescriptor = FetchDescriptor<Friend>(
            predicate: #Predicate { $0.userId == userId && $0.friendUid == uid }
        )
        if let count = try? modelContext.fetchCount(friendDescriptor), count > 0 {
            return .friends
        }

        let incomingDescriptor = FetchDescriptor<FriendRequest>(
            predicate: #Predicate { $0.userId == userId && $0.otherUid == uid && $0.direction == "incoming" }
        )
        if let count = try? modelContext.fetchCount(incomingDescriptor), count > 0 {
            return .incomingPending
        }

        let outgoingDescriptor = FetchDescriptor<FriendRequest>(
            predicate: #Predicate { $0.userId == userId && $0.otherUid == uid && $0.direction == "outgoing" }
        )
        if let count = try? modelContext.fetchCount(outgoingDescriptor), count > 0 {
            return .outgoingPending
        }

        return .none
    }

    /// Returns every user in the public usernames directory except me, sorted
    /// alphabetically by username. Reads only the public usernames index — no
    /// private account data. Empty for guests (no Firestore reads in guest mode).
    ///
    /// One row per uid: when a uid owns multiple handle docs (orphans left by
    /// earlier claims), only the latest claim — the user's current handle —
    /// is kept. Duplicate uids would also break SwiftUI ForEach identity.
    func fetchAllUsers() async throws -> [DirectoryUser] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [] }
        let users: [DirectoryUser]
        do {
            users = try await firestoreService.fetchAllUsernames()
        } catch {
            throw FriendError.network(error.localizedDescription)
        }

        var latestByUid: [String: DirectoryUser] = [:]
        for user in users where user.uid != me {
            if let existing = latestByUid[user.uid] {
                let newClaim = user.claimedAt ?? .distantPast
                let oldClaim = existing.claimedAt ?? .distantPast
                if newClaim > oldClaim {
                    latestByUid[user.uid] = user
                }
            } else {
                latestByUid[user.uid] = user
            }
        }

        return latestByUid.values.sorted { $0.username < $1.username }
    }

    /// Fetches my identity for stamping into cross-user writes.
    ///
    /// Reads account/info fields RAW, never via AccountInfoDTO Codable decode:
    /// older accounts' account/info docs are missing displayName/email/createdAt
    /// (only `username` was merged in by the claim transaction), which makes the
    /// full decode fail and return nil. Same reason fetchUsername reads raw.
    /// A missing username should be impossible past the Phase 1 claim gate.
    ///
    /// `createdAt` rides along from the same raw account/info read (nil for
    /// legacy accounts whose doc never got the field) — publishMyStats uses it
    /// as the published `joinedAt` without a second fetch.
    private func fetchMyFriendIdentity(userId: String) async throws -> (username: String, displayName: String, createdAt: Date?) {
        let fetchedUsername = try? await firestoreService.fetchUsername(userId: userId)
        guard let username = fetchedUsername, !username.isEmpty else {
            throw FriendError.network("Your account has no username yet.")
        }

        let raw = try? await FirestoreServiceImpl.shared.fetchAccountInfoRaw(userId: userId)
        var displayName = (raw?["displayName"] as? String) ?? ""
        if displayName.isEmpty {
            displayName = authService.currentUserDisplayName ?? username
        }
        return (username, displayName, raw?["createdAt"] as? Date)
    }

    /// Resolves a typed handle and validates before sending a friend request.
    ///
    /// Steps: 1. normalize + validate locally (invalid input never hits the network)
    ///        2. resolve uid via the public usernames index → nil ⇒ userNotFound
    ///        3. self-request ⇒ cannotFriendSelf
    ///        4. local relationship checks (friends / incoming / outgoing-idempotent)
    ///        5. AUTHORITATIVE reverse-request check: fresh server read of MY OWN
    ///           incoming request doc users/{me}/friendRequests/{uid} (own space —
    ///           no cross-user read). Closes the reverse-duplicate window local
    ///           state can miss. The rare exact-simultaneous cross-send is benign:
    ///           the first accept deletes both request directions.
    ///        6. send, stamping my identity from account/info
    func sendFriendRequest(toHandle raw: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw FriendError.network("You must be signed in to add friends.")
        }

        let handleKey = try DataManager.normalizeAndValidateUsername(raw)

        let resolvedUid: String?
        do {
            resolvedUid = try await firestoreService.lookupUid(forHandleKey: handleKey)
        } catch {
            throw FriendError.network(error.localizedDescription)
        }
        guard let toUid = resolvedUid else { throw FriendError.userNotFound }
        guard toUid != me else { throw FriendError.cannotFriendSelf }

        switch friendshipState(with: toUid) {
        case .friends:
            throw FriendError.alreadyFriends
        case .incomingPending:
            throw FriendError.incomingExists
        case .outgoingPending:
            return // Already sent — doc id == recipient uid makes re-send idempotent anyway.
        case .none:
            break
        }

        let reverseExists: Bool
        do {
            reverseExists = try await firestoreService.incomingRequestExists(meUid: me, fromUid: toUid)
        } catch {
            throw FriendError.network(error.localizedDescription)
        }
        if reverseExists { throw FriendError.incomingExists }

        let identity = try await fetchMyFriendIdentity(userId: me)
        try await firestoreService.sendFriendRequest(
            toUid: toUid,
            toUsername: handleKey,
            fromUid: me,
            fromUsername: identity.username,
            fromDisplayName: identity.displayName
        )
    }

    /// Accepts a cached incoming request. The from* snapshot comes from the LOCAL
    /// row (listener-owned); my own identity comes from account/info. The accept
    /// batch deletes BOTH request directions so no pending request survives
    /// becoming friends, even after a simultaneous cross-send.
    func acceptIncomingRequest(fromUid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw FriendError.network("You must be signed in to use friends.")
        }
        guard let request = fetchIncomingRequest(fromUid: fromUid) else {
            throw FriendError.network("That request is no longer available.")
        }

        let identity = try await fetchMyFriendIdentity(userId: me)
        try await firestoreService.acceptFriendRequest(
            fromUid: fromUid,
            fromUsername: request.username,
            fromDisplayName: request.displayName ?? "",
            meUid: me,
            meUsername: identity.username,
            meDisplayName: identity.displayName
        )
    }

    /// Declines an incoming request: deletes it and the sender's mirror.
    /// Deleting an absent doc is a no-op — safe if the sender just cancelled.
    func declineIncomingRequest(fromUid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw FriendError.network("You must be signed in to use friends.")
        }
        try await firestoreService.declineFriendRequest(fromUid: fromUid, meUid: me)
    }

    /// Cancels my outgoing request: deletes my mirror and the recipient's incoming doc.
    func cancelSentRequest(toUid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw FriendError.network("You must be signed in to use friends.")
        }
        try await firestoreService.cancelSentRequest(toUid: toUid, meUid: me)
    }

    /// Removes a friendship: deletes both edges (unfriend is mutual).
    func removeFriend(friendUid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw FriendError.network("You must be signed in to use friends.")
        }
        // TESTING ONLY — no real edges exist for the placeholder; succeed as a
        // no-op (it reappears on the next load, by design).
        if friendUid == PlaceholderFriend.uid { return }
        try await firestoreService.removeFriend(friendUid: friendUid, meUid: me)
    }

    // MARK: - Guilds (G1)

    /// Soft member cap. Enforced reliably only where the caller can read the
    /// roster (the owner, during approval). On open self-join the prospective
    /// member cannot read the roster by the security rules, so the cap there is a
    /// best-effort no-op and a rare over-cap race is accepted (per the G1 spec).
    static let maxMembers = 30

    /// 8-char uppercase code from an unambiguous alphabet (no 0/O/1/I). Created
    /// create-only; collisions are retried in createGuild.
    static func generateGuildCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var code = ""
        for _ in 0..<8 { code.append(alphabet.randomElement()!) }
        return code
    }

    /// Validates name/description/policy and returns the cleaned tuple, throwing
    /// GuildError on invalid input. Shared by createGuild and updateGuildSettings.
    private func validatedGuildFields(name: String, joinPolicy: String, description: String?) throws -> (name: String, description: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 30 else {
            throw GuildError.network("Guild name must be 1–30 characters.")
        }
        guard joinPolicy == "open" || joinPolicy == "request" else {
            throw GuildError.network("Invalid join policy.")
        }
        let trimmedDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDesc: String?
        if let trimmedDesc, !trimmedDesc.isEmpty {
            guard trimmedDesc.count <= 140 else {
                throw GuildError.network("Description must be 140 characters or fewer.")
            }
            finalDesc = trimmedDesc
        } else {
            finalDesc = nil
        }
        return (trimmedName, finalDesc)
    }

    /// Fetches the guild and asserts the current user owns it. Throws notFound /
    /// notAuthorized / network. Used by all owner-only actions.
    private func requireOwnedGuild(code: String, me: String) async throws -> GuildDTO {
        let guildOpt: GuildDTO?
        do { guildOpt = try await firestoreService.fetchGuild(code: code) }
        catch { throw GuildError.network(error.localizedDescription) }
        guard let guild = guildOpt else { throw GuildError.notFound }
        guard guild.ownerUid == me else { throw GuildError.notAuthorized }
        return guild
    }

    /// Creates a guild owned by the current user. Validates input, stamps identity
    /// from account/info, generates a code, and retries on collision up to 5×.
    func createGuild(name: String, joinPolicy: String, description: String?) async throws -> GuildDTO {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in to create a guild.")
        }
        // One guild per user (UX guard; the server lock is authoritative).
        if await myGuild() != nil { throw GuildError.alreadyInGuild }

        let fields = try validatedGuildFields(name: name, joinPolicy: joinPolicy, description: description)
        let identity = try await fetchMyFriendIdentity(userId: me)

        for _ in 0..<5 {
            let code = DataManager.generateGuildCode()
            do {
                try await firestoreService.createGuild(
                    code: code, name: fields.name, joinPolicy: joinPolicy, description: fields.description,
                    ownerUid: me, ownerUsername: identity.username, ownerDisplayName: identity.displayName
                )
                // Prefer the authoritative server copy; fall back to a local build.
                if let created = try? await firestoreService.fetchGuild(code: code) {
                    return created
                }
                return GuildDTO(id: code, name: fields.name, ownerUid: me,
                                joinPolicy: joinPolicy, description: fields.description, createdAt: Date())
            } catch {
                // Create-only collision (or transient failure) — try a new code.
                continue
            }
        }
        throw GuildError.codeCollision
    }

    /// The current user's guild via the O(1) membership-lock lookup. nil for guests.
    func myGuild() async -> GuildDTO? {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return nil }
        return try? await firestoreService.fetchMyGuild(uid: me)
    }

    /// The roster for a guild. Readable by members (and the owner); empty for guests
    /// or when the caller is not permitted to read it.
    func guildMembers(code: String) async -> [GuildMemberDTO] {
        guard !isGuest else { return [] }
        return (try? await firestoreService.fetchGuildMembers(code: code)) ?? []
    }

    /// Pending join requests for a guild (owner-only by rules). Empty otherwise.
    func joinRequests(code: String) async -> [GuildJoinRequestDTO] {
        guard !isGuest else { return [] }
        return (try? await firestoreService.fetchJoinRequests(code: code)) ?? []
    }

    /// Joins a guild by code. Open guilds self-join; request guilds create a
    /// pending request. Throws alreadyInGuild / notFound / full / network.
    func joinGuild(code: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in to join a guild.")
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedCode.isEmpty else { throw GuildError.notFound }

        if await myGuild() != nil { throw GuildError.alreadyInGuild }

        let guildOpt: GuildDTO?
        do { guildOpt = try await firestoreService.fetchGuild(code: trimmedCode) }
        catch { throw GuildError.network(error.localizedDescription) }
        guard let guild = guildOpt, let guildCode = guild.id else { throw GuildError.notFound }

        // Soft cap. Best-effort: the roster read is permitted only for members, so
        // for an open self-join (the joiner is not yet a member) this read is
        // typically denied — `try?` then skips the check and the join proceeds.
        // The cap is enforced reliably in approveRequest, where the owner can read.
        if let members = try? await firestoreService.fetchGuildMembers(code: guildCode),
           members.count >= DataManager.maxMembers {
            throw GuildError.full
        }

        let identity = try await fetchMyFriendIdentity(userId: me)
        if guild.joinPolicy == "open" {
            try await firestoreService.joinOpenGuild(code: guildCode, uid: me,
                                                     username: identity.username, displayName: identity.displayName)
        } else {
            try await firestoreService.requestToJoinGuild(code: guildCode, uid: me,
                                                          username: identity.username, displayName: identity.displayName)
        }
    }

    /// Cancels my own pending join request for a guild.
    func cancelMyJoinRequest(code: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in.")
        }
        try await firestoreService.cancelJoinRequest(code: code, uid: me)
    }

    /// Owner approves a pending request. Re-checks the member cap first (the owner
    /// can read the roster), so approvals can never exceed the cap.
    func approveRequest(code: String, request: GuildJoinRequestDTO) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in.")
        }
        _ = try await requireOwnedGuild(code: code, me: me)

        let members: [GuildMemberDTO]
        do { members = try await firestoreService.fetchGuildMembers(code: code) }
        catch { throw GuildError.network(error.localizedDescription) }
        guard members.count < DataManager.maxMembers else { throw GuildError.full }

        try await firestoreService.approveJoinRequest(code: code, request: request)
    }

    /// Owner denies a pending request.
    func denyRequest(code: String, requesterUid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in.")
        }
        _ = try await requireOwnedGuild(code: code, me: me)
        try await firestoreService.denyJoinRequest(code: code, requesterUid: requesterUid)
    }

    /// Owner removes a member. The owner cannot kick themselves (they must disband).
    func kickMember(code: String, memberUid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in.")
        }
        let guild = try await requireOwnedGuild(code: code, me: me)
        guard memberUid != guild.ownerUid else { throw GuildError.notAuthorized }
        try await firestoreService.kickMember(code: code, memberUid: memberUid)
    }

    /// Leaves a guild. The owner cannot leave — they must disband instead.
    func leaveGuild(code: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in.")
        }
        let guildOpt: GuildDTO?
        do { guildOpt = try await firestoreService.fetchGuild(code: code) }
        catch { throw GuildError.network(error.localizedDescription) }
        guard let guild = guildOpt else { throw GuildError.notFound }
        if guild.ownerUid == me { throw GuildError.ownerMustDisband }
        try await firestoreService.leaveGuild(code: code, uid: me)
    }

    /// Owner updates the guild's name, join policy, and/or description.
    func updateGuildSettings(code: String, name: String, joinPolicy: String, description: String?) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in.")
        }
        _ = try await requireOwnedGuild(code: code, me: me)
        let fields = try validatedGuildFields(name: name, joinPolicy: joinPolicy, description: description)
        try await firestoreService.updateGuildSettings(code: code, name: fields.name,
                                                       joinPolicy: joinPolicy, description: fields.description)
    }

    /// Owner disbands the guild (cascades members + requests + locks + messages, then the doc).
    func disbandGuild(code: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw GuildError.network("You must be signed in.")
        }
        _ = try await requireOwnedGuild(code: code, me: me)
        try await firestoreService.disbandGuild(code: code)
    }

    // MARK: - Guild chat (G3)

    /// Start the screen-scoped chat listener. The VM supplies the update/error
    /// callbacks; the single ListenerRegistration lives in the service. No-op for guests.
    func startGuildChat(code: String,
                        onUpdate: @escaping ([GuildMessageDTO]) -> Void,
                        onError: @escaping (Error) -> Void) {
        guard !isGuest else { return }
        firestoreService.startGuildChatListener(code: code, onUpdate: onUpdate, onError: onError)
    }

    /// Stop the chat listener (idempotent). MUST be called when the chat screen disappears.
    func stopGuildChat() {
        firestoreService.stopGuildChatListener()
    }

    /// Send a chat message. Trims + validates (1–500), stamps identity, writes with
    /// a server timestamp. Rules also enforce membership + 1–500 bounds.
    func sendGuildMessage(code: String, text: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw GuildChatError.notAuthenticated }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GuildChatError.empty }
        guard trimmed.count <= 500 else { throw GuildChatError.tooLong }

        let identity = try await fetchMyFriendIdentity(userId: me)
        let msg = GuildMessageDTO(
            senderUid: me,
            senderUsername: identity.username,
            senderDisplayName: identity.displayName,
            text: trimmed,
            createdAt: nil
        )
        try await firestoreService.sendGuildMessage(code: code, msg: msg)
    }

    /// Delete a chat message. Rules enforce sender-or-owner.
    func deleteGuildMessage(code: String, msgId: String) async throws {
        guard !isGuest else { throw GuildChatError.notAuthenticated }
        try await firestoreService.deleteGuildMessage(code: code, msgId: msgId)
    }

    // MARK: - Public Stats / Leaderboard (Friend System Phase 3)

    /// Computes the rolling 7-day macro-goal adherence from the current user's
    /// OWN local data. The single source of truth for the leaderboard metric:
    /// the owner publishes it, the leaderboard sorts on it.
    ///
    /// For each of the last 7 calendar days (today inclusive), evaluates
    /// `NutritionManager.didMeetGoals` with that day's entries and the DailyGoal
    /// in effect that day. A day with NO logged entries counts as NOT met —
    /// absence is non-adherence, never skipped.
    ///
    /// Returns (weeklyGoalsMet 0...7, weeklyAdherence 0.0...1.0).
    private func computeWeeklyAdherence() async -> (goalsMet: Int, adherence: Double) {
        guard let userId = currentUserId, !userId.isEmpty else { return (0, 0.0) }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: todayStart),
              let windowEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return (0, 0.0)
        }

        let entries = (try? await fetchEntriesForDateRange(start: windowStart, end: windowEnd)) ?? []
        let entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }

        let goals = (try? await fetchAllDailyGoalsForSync(userId: userId)) ?? []
        let goalsByRecency = goals.sorted { $0.date > $1.date }

        var goalsMet = 0
        for offset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            // No entries that day → not met (do not skip the day).
            guard let dayEntries = entriesByDay[dayStart], !dayEntries.isEmpty else { continue }
            guard let goal = goalInEffect(on: dayStart, calendar: calendar, goalsByRecency: goalsByRecency) else { continue }
            if nutritionManager.didMeetGoals(entries: dayEntries, goal: goal) {
                goalsMet += 1
            }
        }

        // Explicit Double conversion — integer division would collapse to 0 or 1.
        return (goalsMet, Double(goalsMet) / 7.0)
    }

    /// The DailyGoal in effect on a given day: that day's own goal when one was
    /// retained, else the most recent earlier goal (goals persist until changed),
    /// else the oldest goal on record (day predates the first goal). nil only
    /// when the user has no goals at all — that day then counts as not met.
    private func goalInEffect(on dayStart: Date, calendar: Calendar, goalsByRecency: [DailyGoal]) -> DailyGoal? {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        if let sameDay = goalsByRecency.first(where: { $0.date >= dayStart && $0.date < dayEnd }) {
            return sameDay
        }
        if let earlier = goalsByRecency.first(where: { $0.date < dayStart }) {
            return earlier
        }
        return goalsByRecency.last
    }

    /// Computes the owner's friend-readable stats projection from local
    /// UserProgress + the adherence metric and publishes it to
    /// users/{me}/public/stats. Owner-computed, owner-published — nothing here
    /// reads another user's data.
    ///
    /// Fire-and-forget safe: never throws and never blocks UI. Guests and
    /// unauthenticated sessions are a strict no-op (no Firestore I/O).
    func publishMyStats() async {
        guard let userId = currentUserId, !userId.isEmpty else { return }
        // The snapshot builder applies the same guest/auth gate and produces the
        // identical payload — publish is now a thin wrapper over it.
        guard let dto = await buildMyStatsSnapshot() else { return }
        try? await firestoreService.publishPublicStats(dto, userId: userId)
    }

    /// Builds the current user's stats projection from LOCAL data only (no
    /// network, no self-read of `public/stats`). Returns nil for
    /// guests/unauthenticated.
    ///
    /// Shared by `publishMyStats()` (the only writer of the projection) and the
    /// Friend System Phase 6 profile comparison, so the published payload and
    /// the "you vs. them" comparison can never diverge. Local data is fresher
    /// than the friend-readable doc and avoids a redundant self-read.
    func buildMyStatsSnapshot() async -> PublicStatsDTO? {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return nil }

        // Snapshot progress fields before the next awaits (never hold a @Model
        // across suspension points).
        guard let progress = try? await getUserProgress() else { return nil }
        let level = progress.currentLevel
        let totalXP = progress.totalXP
        let currentStreak = progress.currentStreak
        let longestStreak = progress.longestStreak
        let rank = progress.rank

        // Earned badge IDs only (Phase 4 profile) — friends resolve them to
        // emoji/title locally via BadgeDefinition; the badges subcollection
        // itself stays owner-only. Sorted so re-publishes are byte-stable.
        let badgeRows = (try? await getAllBadgeProgress()) ?? []
        let earnedBadgeIds = badgeRows.filter { $0.isUnlocked }.map { $0.badgeId }.sorted()

        let (goalsMet, adherence) = await computeWeeklyAdherence()

        // Identity snapshot via the same raw account/info read used for friend
        // request stamping (full Codable decode fails for older accounts).
        // No username yet (pre-claim-gate edge) → nothing to publish under.
        guard let identity = try? await fetchMyFriendIdentity(userId: userId) else { return nil }

        return PublicStatsDTO(
            username: identity.username,
            displayName: identity.displayName,
            level: level,
            totalXP: totalXP,
            currentStreak: currentStreak,
            rank: rank,
            weeklyGoalsMet: goalsMet,
            weeklyAdherence: adherence,
            longestStreak: longestStreak,
            joinedAt: identity.createdAt, // nil (field omitted) for legacy accounts
            badgeCount: earnedBadgeIds.count,
            earnedBadgeIds: earnedBadgeIds,
            updatedAt: nil // encoded as FieldValue.serverTimestamp() via @ServerTimestamp
        )
    }

    // MARK: - Activity Feed (Friend System Phase 7)

    /// Builds and publishes a milestone feed event, then prunes to the 30
    /// newest. Guest/unauthenticated ⇒ no-op.
    ///
    /// Fire-and-forget: spawns a Task, returns immediately, and never blocks or
    /// fails the caller's progress save. All errors are swallowed — including
    /// the expected permission-denied when a re-emitted event hits the immutable
    /// create-only rules (idempotency = "no duplicates," not "must succeed
    /// twice"); never surfaced, never retried.
    ///
    /// Lives here (not in GamificationManager, which stays pure) because it
    /// needs Firestore + identity + the guest gate. Identity is read via the
    /// raw-read `fetchMyFriendIdentity` (the same snapshot publishMyStats uses),
    /// which tolerates older accounts whose account/info fails Codable decode.
    func emitFeedEvent(type: String, value: String) {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return }
        Task {
            guard let identity = try? await fetchMyFriendIdentity(userId: userId) else { return }
            let event = FeedEventDTO(
                type: type,
                value: value,
                username: identity.username,
                displayName: identity.displayName,
                createdAt: nil // server timestamp via @ServerTimestamp
            )
            try? await firestoreService.publishFeedEvent(event, userId: userId)
            try? await firestoreService.pruneFeedEvents(userId: userId, keep: 30)
        }
    }

    /// Merges friends' recent milestone events into one reverse-chronological
    /// feed. Fetch-on-view, in-memory — no listeners, nothing persisted. Guest
    /// ⇒ []. My OWN events are never included (the feed shows friends only; the
    /// app already celebrates my own milestones in-place).
    ///
    /// Per-friend fetches fan out concurrently; a friend that errors or has no
    /// readable events contributes nothing (partial feed still renders). Events
    /// whose type/value no longer resolve locally (removed badge/rank) are
    /// dropped. Merged newest-first and capped at 50.
    func loadActivityFeed() async -> [FeedItem] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [] }

        // Local friend edges only (Phase 2). The placeholder test friend is not
        // a real user and has no feedEvents subcollection, so it is naturally
        // absent — fetchFriends() never returns it.
        let friendModels = (try? await fetchFriends()) ?? []
        let friendUids = friendModels.map { $0.friendUid }

        var items: [FeedItem] = []
        await withTaskGroup(of: [FeedItem].self) { group in
            for uid in friendUids {
                group.addTask { [firestoreService] in
                    let dtos = (try? await firestoreService.fetchFeedEvents(friendUid: uid, limit: 10)) ?? []
                    return dtos.compactMap { dto in
                        let item = FeedItem(dto: dto, friendUid: uid)
                        // Drop events whose type/value no longer resolve locally.
                        return item.resolvedText == nil ? nil : item
                    }
                }
            }
            for await partial in group {
                items.append(contentsOf: partial)
            }
        }

        // TESTING ONLY — fabricated events from the placeholder friend so the
        // Activity segment isn't empty without a second account. Merges and
        // sorts alongside real events. Grep "PlaceholderFriend" to remove.
        items.append(contentsOf: PlaceholderFriend.feedItems())

        items.sort { $0.createdAt > $1.createdAt }
        let capped = Array(items.prefix(50))

        // Cheers (Phase 8): one cheers query per displayed item, concurrently.
        // A per-item failure leaves that item at cheerCount 0 / didCheer false —
        // the feed never fails wholesale. No denormalized counter on the event
        // doc (events stay immutable); a Cloud-Function `cheerCount` is the
        // documented future lever, not built here.
        var enriched: [FeedItem] = []
        await withTaskGroup(of: FeedItem.self) { group in
            for item in capped {
                group.addTask { [firestoreService, me, item] in
                    // TESTING ONLY — placeholder items keep their fabricated
                    // cheer fields (the fixture has no real cheers subcollection).
                    if item.friendUid == PlaceholderFriend.uid { return item }
                    var result = item
                    let cheers = (try? await firestoreService.fetchCheers(
                        ownerUid: item.friendUid, eventId: item.eventId, limit: 20)) ?? []
                    result.cheerCount = cheers.count
                    result.didCheer = cheers.contains { $0.cheererUid == me }
                    result.recentCheererNames = cheers.prefix(3).map {
                        $0.displayName.isEmpty ? "@\($0.username)" : $0.displayName
                    }
                    return result
                }
            }
            for await item in group {
                enriched.append(item)
            }
        }

        // Task-group completion order is nondeterministic — restore newest-first.
        enriched.sort { $0.createdAt > $1.createdAt }
        return enriched
    }

    /// Cheer a friend's event (Friend System Phase 8). guard !isGuest; never
    /// self-cheer (rules also enforce). Identity snapshot via the raw-read
    /// `fetchMyFriendIdentity` (the Codable account/info decode fails for older
    /// accounts), same as event emission.
    ///
    /// A genuine permission-denied (unfriended between feed load and tap)
    /// propagates so the UI can surface it. A re-cheer never reaches here: the
    /// UI's per-row in-flight flag + `didCheer` state machine route an
    /// already-cheered event to `uncheer` instead.
    func cheer(ownerUid: String, eventId: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return }
        guard ownerUid != me else { return }
        guard let identity = try? await fetchMyFriendIdentity(userId: me) else { return }
        try await firestoreService.addCheer(
            ownerUid: ownerUid, eventId: eventId,
            cheererUid: me, username: identity.username, displayName: identity.displayName)
    }

    /// Remove my cheer (Friend System Phase 8). Deleting an absent doc is a no-op.
    func uncheer(ownerUid: String, eventId: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return }
        try await firestoreService.removeCheer(ownerUid: ownerUid, eventId: eventId, cheererUid: me)
    }

    /// Owner receipts (Friend System Phase 8): my own recent events with the
    /// cheers each received, newest-first. Guest ⇒ []. Resolves display text the
    /// same way feed rows do and drops events that no longer resolve.
    func loadMyMilestones() async -> [OwnEventItem] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [] }

        let events = (try? await firestoreService.fetchMyFeedEvents(userId: me, limit: 5)) ?? []

        var items: [OwnEventItem] = []
        await withTaskGroup(of: OwnEventItem?.self) { group in
            for event in events {
                // Capture only Sendable primitives, not the DTO.
                let type = event.type
                let value = event.value
                let eid = event.id
                let created = event.createdAt ?? .distantPast
                group.addTask { [firestoreService, me] in
                    guard FeedEventDisplay.text(type: type, value: value) != nil else { return nil }
                    let cheers = (try? await firestoreService.fetchCheers(
                        ownerUid: me, eventId: eid, limit: 20)) ?? []
                    return OwnEventItem(
                        eventId: eid,
                        type: type,
                        value: value,
                        createdAt: created,
                        cheerCount: cheers.count,
                        recentCheererNames: cheers.prefix(3).map {
                            $0.displayName.isEmpty ? "@\($0.username)" : $0.displayName
                        }
                    )
                }
            }
            for await item in group {
                if let item { items.append(item) }
            }
        }
        items.sort { $0.createdAt > $1.createdAt }

        // TESTING ONLY — fabricated owner milestones so the "Your milestones"
        // strip is visible without real emitted events. Grep "PlaceholderFriend".
        if items.isEmpty {
            items = PlaceholderFriend.ownMilestones()
        }
        return items
    }

    // MARK: - Meal/Recipe Sharing (Friend System Phase 9)

    /// Share a meal snapshot to a friend's inbox. Photos never travel (the DTO
    /// excludes them by design); meals send yield 1 / purity 0 (ignored on import).
    func shareMeal(_ meal: SavedMeal, toFriendUid: String) async throws {
        let json = String(data: meal.componentsData, encoding: .utf8) ?? "[]"
        try await sendShare(kind: "meal", name: meal.name, contentJSON: json,
                            yield: 1, purityScore: 0, toFriendUid: toFriendUid)
    }

    /// Share a recipe snapshot to a friend's inbox (carries yield + purityScore).
    func shareRecipe(_ recipe: SavedRecipe, toFriendUid: String) async throws {
        let json = String(data: recipe.ingredientsData, encoding: .utf8) ?? "[]"
        try await sendShare(kind: "recipe", name: recipe.name, contentJSON: json,
                            yield: recipe.yield, purityScore: recipe.purityScore, toFriendUid: toFriendUid)
    }

    /// Shared send path: guest/self guards, friend re-check, size guard, identity
    /// stamp, deliver. The rules are the real authorization boundary.
    private func sendShare(kind: String, name: String, contentJSON: String,
                           yield: Int, purityScore: Int, toFriendUid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw ShareError.notAuthenticated }
        guard toFriendUid != me else { throw ShareError.network("You can't share with yourself.") }

        let friends = (try? await fetchFriends()) ?? []
        guard friends.contains(where: { $0.friendUid == toFriendUid }) else {
            throw ShareError.network("You can only share with friends.")
        }

        // Friendly client-side cap; the rules enforce a 200 KB hard backstop.
        guard contentJSON.utf8.count <= 100_000 else { throw ShareError.tooLarge }

        // Identity snapshot via the raw-read helper (the Codable account/info
        // decode fails for older accounts), same as event emission / cheers.
        guard let identity = try? await fetchMyFriendIdentity(userId: me) else {
            throw ShareError.notAuthenticated
        }

        let dto = SharedItemDTO(
            id: nil, // doc id assigned at send (fresh UUID); @DocumentID omitted from body
            fromUid: me,
            fromUsername: identity.username,
            fromDisplayName: identity.displayName,
            kind: kind,
            name: name,
            contentJSON: contentJSON,
            yield: yield,
            purityScore: purityScore,
            createdAt: nil
        )
        do {
            try await firestoreService.sendSharedItem(dto, toUid: toFriendUid)
        } catch {
            throw ShareError.network(error.localizedDescription)
        }
    }

    /// Inbox fetch scoped to one kind ("meal" | "recipe") — filtered SERVER-side.
    /// Guest ⇒ []. (Retained for callers that want a single kind.)
    func loadSharedItems(kind: String) async -> [SharedItemDTO] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [] }
        return (try? await firestoreService.fetchSharedItems(userId: me, kind: kind, limit: 50)) ?? []
    }

    /// The recipient's ENTIRE share inbox (both kinds), newest first. Guest ⇒ [].
    /// Uses a single-field ordered query (no composite index) so it never fails
    /// silently on a missing/not-yet-built index — this is what the Friends-tab
    /// "Shared with you" strip loads.
    func loadSharedItems() async -> [SharedItemDTO] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [] }
        return (try? await firestoreService.fetchAllSharedItems(userId: me, limit: 50)) ?? []
    }

    /// Share a single logged food entry as a one-item meal snapshot.
    func shareFoodEntry(_ entry: FoodEntry, toFriendUid: String) async throws {
        try await shareFoodEntries([entry], named: entry.name, toFriendUid: toFriendUid)
    }

    /// Share a set of logged food entries (e.g. a logged meal bundle) as a
    /// multi-item meal snapshot — reuses the Phase 9 delivery path verbatim.
    func shareFoodEntries(_ entries: [FoodEntry], named name: String, toFriendUid: String) async throws {
        let components = entries.map { entry in
            SavedMealComponent(
                foodName: entry.name,
                quantity: 1,
                servingUnit: "serving",
                calories: entry.calories,
                protein: entry.protein,
                carbs: entry.carbs,
                fat: entry.fat,
                toxinScore: entry.toxinScore
            )
        }
        let json = String(data: (try? JSONEncoder().encode(components)) ?? Data(), encoding: .utf8) ?? "[]"
        try await sendShare(kind: "meal", name: name, contentJSON: json,
                            yield: 1, purityScore: 0, toFriendUid: toFriendUid)
    }

    /// Import a share into the recipient's own collection through the EXISTING
    /// save pipeline (decode → validate → fresh-UUID DTO → toSaved* → addSaved*).
    /// The share is removed ONLY after the save succeeds; a failed delete leaves
    /// it in the inbox (re-import yields an independent copy — never upsert).
    func importSharedItem(_ item: SharedItemDTO) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw ShareError.notAuthenticated }

        // Decode the snapshot. Empty array or decode failure ⇒ malformed.
        guard let data = item.contentJSON.data(using: .utf8),
              let components = try? JSONDecoder().decode([SavedMealComponent].self, from: data),
              !components.isEmpty else {
            throw ShareError.malformed
        }
        // Every component's macros (and quantity) must be non-negative.
        let valid = components.allSatisfy {
            $0.calories >= 0 && $0.protein >= 0 && $0.carbs >= 0 && $0.fat >= 0 && $0.quantity >= 0
        }
        guard valid else { throw ShareError.malformed }

        // FRESH UUID — never the sender's id, so a genuinely new import is an
        // independent copy. But skip creating a duplicate of one already saved
        // (same name + items), so a re-import doesn't spam the collection.
        let now = Date()
        switch item.kind {
        case "meal":
            let signature = DataManager.contentSignature(name: item.name, components: components)
            let existing = (try? await getSavedMeals()) ?? []
            let isDuplicate = existing.contains {
                DataManager.contentSignature(name: $0.name, components: $0.components) == signature
            }
            if !isDuplicate {
                let dto = SavedMealDTO(
                    id: UUID().uuidString, name: item.name,
                    componentsJSON: item.contentJSON, createdAt: now)
                try await addSavedMeal(dto.toSavedMeal(userId: me))
            }
        case "recipe":
            let signature = DataManager.contentSignature(name: item.name, components: components) + "#y\(max(1, item.yield))"
            let existing = (try? await getSavedRecipes()) ?? []
            let isDuplicate = existing.contains {
                DataManager.contentSignature(name: $0.name, components: $0.ingredients) + "#y\($0.yield)" == signature
            }
            if !isDuplicate {
                let dto = SavedRecipeDTO(
                    id: UUID().uuidString, name: item.name, yield: item.yield,
                    ingredientsJSON: item.contentJSON, purityScore: item.purityScore, createdAt: now)
                try await addSavedRecipe(dto.toSavedRecipe(userId: me))
            }
        default:
            throw ShareError.malformed
        }

        // Only now remove the share (whether newly saved or already present, the
        // share is resolved). A failed delete is acceptable. NEVER delete before
        // the save succeeds.
        if let shareId = item.id {
            try? await firestoreService.deleteSharedItem(id: shareId, userId: me)
        }
    }

    /// Dismiss a share without saving. Guest ⇒ no-op.
    func dismissSharedItem(_ item: SharedItemDTO) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return }
        guard let shareId = item.id else { return }
        try await firestoreService.deleteSharedItem(id: shareId, userId: me)
    }

    /// Fetches one friend's published stats projection for the profile sheet
    /// (Friend System Phase 4). Reuses the leaderboard's friend-gated service
    /// read — nil means not published yet OR permission-denied (unfriended),
    /// both rendered as "hasn't shared their stats yet."
    func fetchPublicStats(friendUid: String) async throws -> PublicStatsDTO? {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return nil }
        // TESTING ONLY — the placeholder friend's stats are fabricated locally.
        if friendUid == PlaceholderFriend.uid { return PlaceholderFriend.stats }
        return try await firestoreService.fetchPublicStats(friendUid: friendUid)
    }

    /// Fetches every friend's published projection keyed by uid, for the
    /// detailed friends-list rows. Same concurrent friend-gated reads as the
    /// leaderboard; friends without a published projection are simply absent
    /// (their row falls back to identity only). Fetch-on-view, never persisted.
    func fetchFriendStats() async -> [String: PublicStatsDTO] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [:] }

        let friendModels = (try? await fetchFriends()) ?? []
        var uids = friendModels.map { $0.friendUid }
        // TESTING ONLY — placeholder friend rides along (fabricated stats).
        uids.append(PlaceholderFriend.uid)

        var statsByUid: [String: PublicStatsDTO] = [:]
        await withTaskGroup(of: (uid: String, stats: PublicStatsDTO?).self) { group in
            for uid in uids {
                group.addTask { [firestoreService] in
                    if uid == PlaceholderFriend.uid { return (uid, PlaceholderFriend.stats) }
                    return (uid, try? await firestoreService.fetchPublicStats(friendUid: uid))
                }
            }
            for await result in group {
                if let stats = result.stats {
                    statsByUid[result.uid] = stats
                }
            }
        }
        return statsByUid
    }

    /// Builds the ranked friend leaderboard: my own locally computed row plus
    /// each friend's published projection, fetched concurrently and ranked
    /// client-side in memory.
    ///
    /// Fetch-on-view only — no listeners are opened and nothing is persisted
    /// to SwiftData. Guests get an empty list (no Firestore reads in guest mode).
    func loadLeaderboard() async -> [LeaderboardEntry] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [] }

        // Value snapshots of the listener-maintained Friend rows — never carry
        // @Model references into the concurrent fan-out.
        let friendModels = (try? await fetchFriends()) ?? []
        let friendRefs = friendModels.map {
            (uid: $0.friendUid, username: $0.username, displayName: $0.displayName)
        }

        // Concurrent per-friend fetch (task-group fan-out, never a serial loop).
        // nil — not published yet, permission-denied, or a network failure —
        // keeps that friend as a zeroed "no data yet" row instead of failing
        // the whole board.
        var statsByUid: [String: PublicStatsDTO] = [:]
        await withTaskGroup(of: (uid: String, stats: PublicStatsDTO?).self) { group in
            for friend in friendRefs {
                group.addTask { [firestoreService] in
                    (friend.uid, try? await firestoreService.fetchPublicStats(friendUid: friend.uid))
                }
            }
            for await result in group {
                if let stats = result.stats {
                    statsByUid[result.uid] = stats
                }
            }
        }

        // Deduplicate by uid (hard requirement). Friends are written first and
        // my own row last, so the current-user row always wins a duplicate.
        var entriesByUid: [String: LeaderboardEntry] = [:]
        for friend in friendRefs {
            if let stats = statsByUid[friend.uid] {
                entriesByUid[friend.uid] = LeaderboardEntry(
                    uid: friend.uid,
                    username: stats.username,
                    displayName: stats.displayName,
                    level: stats.level,
                    totalXP: stats.totalXP,
                    currentStreak: stats.currentStreak,
                    rank: stats.rank,
                    weeklyGoalsMet: stats.weeklyGoalsMet,
                    weeklyAdherence: stats.weeklyAdherence,
                    isCurrentUser: false,
                    hasData: true
                )
            } else {
                // Identity from the local Friend snapshot only — never fetch
                // account/info (or anything else) for another user.
                entriesByUid[friend.uid] = LeaderboardEntry(
                    uid: friend.uid,
                    username: friend.username,
                    displayName: friend.displayName,
                    level: 1,
                    totalXP: 0,
                    currentStreak: 0,
                    rank: Rank.iron.rawValue,
                    weeklyGoalsMet: 0,
                    weeklyAdherence: 0.0,
                    isCurrentUser: false,
                    hasData: false
                )
            }
        }

        // TESTING ONLY — placeholder friend row, built from the same fabricated
        // stats the profile sheet shows (PlaceholderFriend).
        entriesByUid[PlaceholderFriend.uid] = LeaderboardEntry(
            uid: PlaceholderFriend.uid,
            username: PlaceholderFriend.username,
            displayName: PlaceholderFriend.displayName,
            level: PlaceholderFriend.stats.level,
            totalXP: PlaceholderFriend.stats.totalXP,
            currentStreak: PlaceholderFriend.stats.currentStreak,
            rank: PlaceholderFriend.stats.rank,
            weeklyGoalsMet: PlaceholderFriend.stats.weeklyGoalsMet,
            weeklyAdherence: PlaceholderFriend.stats.weeklyAdherence,
            isCurrentUser: false,
            hasData: true
        )

        // PREVIEW ONLY — two extra demo rows so CLI screenshots show the full
        // gold/silver/bronze podium. Active only under the HB_PREVIEW launch
        // environment; never present in a normal app session.
        if ProcessInfo.processInfo.environment["HB_PREVIEW"] == "leaderboard" {
            entriesByUid["preview-demo-1"] = LeaderboardEntry(
                uid: "preview-demo-1", username: "pixelpete", displayName: "Pixel Pete",
                level: 18, totalXP: 7900, currentStreak: 12, rank: Rank.diamond.rawValue,
                weeklyGoalsMet: 6, weeklyAdherence: 6.0 / 7.0,
                isCurrentUser: false, hasData: true
            )
            entriesByUid["preview-demo-2"] = LeaderboardEntry(
                uid: "preview-demo-2", username: "ironivy", displayName: "Iron Ivy",
                level: 4, totalXP: 760, currentStreak: 2, rank: "bronze",  // RR-0a: bronze case removed; preview-only literal
                weeklyGoalsMet: 3, weeklyAdherence: 3.0 / 7.0,
                isCurrentUser: false, hasData: true
            )
        }

        entriesByUid[me] = await buildMyLeaderboardEntry(userId: me)

        // Deterministic ranking: no-data rows always last regardless of zeros,
        // then adherence desc → total XP desc → streak desc → username asc.
        return entriesByUid.values.sorted { lhs, rhs in
            if lhs.hasData != rhs.hasData { return lhs.hasData }
            if lhs.weeklyAdherence != rhs.weeklyAdherence { return lhs.weeklyAdherence > rhs.weeklyAdherence }
            if lhs.totalXP != rhs.totalXP { return lhs.totalXP > rhs.totalXP }
            if lhs.currentStreak != rhs.currentStreak { return lhs.currentStreak > rhs.currentStreak }
            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }
    }

    /// My own leaderboard row, built from local UserProgress + the locally
    /// computed adherence — the owner's published projection is never read back.
    private func buildMyLeaderboardEntry(userId: String) async -> LeaderboardEntry {
        let progress = try? await getUserProgress()
        let level = progress?.currentLevel ?? 1
        let totalXP = progress?.totalXP ?? 0
        let currentStreak = progress?.currentStreak ?? 0
        let rank = progress?.rank ?? Rank.iron.rawValue

        let (goalsMet, adherence) = await computeWeeklyAdherence()

        let identity = try? await fetchMyFriendIdentity(userId: userId)
        let username = identity?.username ?? ""
        let displayName = identity?.displayName
            ?? authService.currentUserDisplayName
            ?? username

        return LeaderboardEntry(
            uid: userId,
            username: username,
            displayName: displayName,
            level: level,
            totalXP: totalXP,
            currentStreak: currentStreak,
            rank: rank,
            weeklyGoalsMet: goalsMet,
            weeklyAdherence: adherence,
            isCurrentUser: true,
            hasData: true
        )
    }

    // MARK: - Guild Leaderboard (G2)

    /// Builds the ranked entries for the current user's guild: my own locally
    /// computed row plus each guild-mate's published `public/stats` projection,
    /// fetched concurrently and ranked client-side by the view.
    ///
    /// Reuses the friend-leaderboard machinery (LeaderboardEntry, fetchPublicStats,
    /// buildMyLeaderboardEntry). Fetch-on-view only — no listeners, nothing
    /// persisted. Returns [] for guests / not-in-a-guild (the screen isn't
    /// reachable in those states). Guild-mate reads require the G2 same-guild
    /// `public/stats` read-rule extension; until it is deployed, other members
    /// resolve to nil and render as "no data yet".
    func loadGuildLeaderboard() async -> [LeaderboardEntry] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [] }
        guard let guild = await myGuild(), let code = guild.id else { return [] }

        // Roster snapshot (G1). My own row is built locally, so exclude me from
        // the fan-out — never self-read public/stats.
        let roster = await guildMembers(code: code)
        let others = roster.filter { $0.uid != me }

        // Friendship resolved ONCE here (not per-row in the view): the view drives
        // the friend-only profile tap from each entry's isFriend flag.
        let friendModels = (try? await fetchFriends()) ?? []
        let friendUids = Set(friendModels.map { $0.friendUid })

        // Concurrent per-member fetch (task-group fan-out — guilds are small).
        // nil (unpublished / permission-denied / network) ⇒ a zeroed "no data
        // yet" row, never a wholesale failure.
        var statsByUid: [String: PublicStatsDTO] = [:]
        await withTaskGroup(of: (uid: String, stats: PublicStatsDTO?).self) { group in
            for member in others {
                group.addTask { [firestoreService] in
                    (member.uid, try? await firestoreService.fetchPublicStats(friendUid: member.uid))
                }
            }
            for await result in group {
                if let stats = result.stats { statsByUid[result.uid] = stats }
            }
        }

        // Deduplicate by uid via the dictionary; my own row is written last so it
        // always wins a conflict (concrete keep-one, current-user precedence).
        var entriesByUid: [String: LeaderboardEntry] = [:]
        for member in others {
            let isFriend = friendUids.contains(member.uid)
            if let stats = statsByUid[member.uid] {
                entriesByUid[member.uid] = LeaderboardEntry(
                    uid: member.uid,
                    username: stats.username,
                    displayName: stats.displayName,
                    level: stats.level,
                    totalXP: stats.totalXP,
                    currentStreak: stats.currentStreak,
                    rank: stats.rank,
                    weeklyGoalsMet: stats.weeklyGoalsMet,
                    weeklyAdherence: stats.weeklyAdherence,
                    isCurrentUser: false,
                    hasData: true,
                    isFriend: isFriend
                )
            } else {
                // Identity from the roster snapshot only — never read another
                // user's account/info.
                entriesByUid[member.uid] = LeaderboardEntry(
                    uid: member.uid,
                    username: member.username,
                    displayName: member.displayName,
                    level: 1,
                    totalXP: 0,
                    currentStreak: 0,
                    rank: Rank.iron.rawValue,
                    weeklyGoalsMet: 0,
                    weeklyAdherence: 0.0,
                    isCurrentUser: false,
                    hasData: false,
                    isFriend: isFriend
                )
            }
        }

        entriesByUid[me] = await buildMyLeaderboardEntry(userId: me)

        // Unsorted: the view applies the metric-specific comparator + tie-breakers.
        return Array(entriesByUid.values)
    }

    // MARK: - Guest Mode Methods

    /// Migrates all SwiftData records from userId=="guest" to the new authenticated userId.
    ///
    /// Rules (strict):
    /// 1. Fetch all records where userId == "guest".
    /// 2. For each record: if a record with newUserId and same id already exists → delete the
    ///    guest copy (no duplicates). Otherwise → reassign userId in-place.
    /// 3. Single modelContext.save() after all updates are applied.
    ///
    /// Called from ContentView when pendingMigrationUserId becomes non-nil.
    /// DataManager Firestore guards are still active during this call (isGuest == true).
    func migrateGuestData(to newUserId: String) async throws {
        guard !newUserId.isEmpty, newUserId != "guest" else { return }

        // Migrate all @Model types in-place. Never create duplicates.
        // For each type: fetch guest records, then reassign userId if no record with the
        // same UUID already exists for newUserId. Delete guest copy if duplicate found.
        let guestFoodEntries = try modelContext.fetch(
            FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingFoodIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for entry in guestFoodEntries {
            if existingFoodIds.contains(entry.id.uuidString) {
                modelContext.delete(entry)
            } else {
                entry.userId = newUserId
            }
        }

        let guestGoals = try modelContext.fetch(
            FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingGoalIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for goal in guestGoals {
            if existingGoalIds.contains(goal.id.uuidString) {
                modelContext.delete(goal)
            } else {
                goal.userId = newUserId
            }
        }

        let guestProgress = try modelContext.fetch(
            FetchDescriptor<UserProgress>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingProgressIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<UserProgress>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for progress in guestProgress {
            if existingProgressIds.contains(progress.id.uuidString) {
                modelContext.delete(progress)
            } else {
                progress.userId = newUserId
            }
        }

        let guestQuests = try modelContext.fetch(
            FetchDescriptor<DailyQuest>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingQuestIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<DailyQuest>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for quest in guestQuests {
            if existingQuestIds.contains(quest.id.uuidString) {
                modelContext.delete(quest)
            } else {
                quest.userId = newUserId
            }
        }

        let guestMoods = try modelContext.fetch(
            FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingMoodIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for mood in guestMoods {
            if existingMoodIds.contains(mood.id.uuidString) {
                modelContext.delete(mood)
            } else {
                mood.userId = newUserId
            }
        }

        let guestBaselines = try modelContext.fetch(
            FetchDescriptor<PersonalBaseline>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingBaselineIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<PersonalBaseline>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for baseline in guestBaselines {
            if existingBaselineIds.contains(baseline.id.uuidString) {
                modelContext.delete(baseline)
            } else {
                baseline.userId = newUserId
            }
        }

        let guestCustomFoods = try modelContext.fetch(
            FetchDescriptor<CustomFood>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingCustomFoodIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<CustomFood>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for food in guestCustomFoods {
            if existingCustomFoodIds.contains(food.id.uuidString) {
                modelContext.delete(food)
            } else {
                food.userId = newUserId
            }
        }

        let guestMeals = try modelContext.fetch(
            FetchDescriptor<SavedMeal>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingMealIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<SavedMeal>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for meal in guestMeals {
            if existingMealIds.contains(meal.id.uuidString) {
                modelContext.delete(meal)
            } else {
                meal.userId = newUserId
            }
        }

        let guestRecipes = try modelContext.fetch(
            FetchDescriptor<SavedRecipe>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingRecipeIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<SavedRecipe>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for recipe in guestRecipes {
            if existingRecipeIds.contains(recipe.id.uuidString) {
                modelContext.delete(recipe)
            } else {
                recipe.userId = newUserId
            }
        }

        let guestBadges = try modelContext.fetch(
            FetchDescriptor<BadgeProgress>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingBadgeIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<BadgeProgress>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.badgeId } ?? []
        )
        for badge in guestBadges {
            if existingBadgeIds.contains(badge.badgeId) {
                modelContext.delete(badge)
            } else {
                badge.userId = newUserId
            }
        }

        let guestProfiles = try modelContext.fetch(
            FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userId == "guest" })
        )
        let existingProfileIds = Set(
            (try? modelContext.fetch(
                FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userId == newUserId })
            ))?.map { $0.id.uuidString } ?? []
        )
        for profile in guestProfiles {
            if existingProfileIds.contains(profile.id.uuidString) {
                modelContext.delete(profile)
            } else {
                profile.userId = newUserId
            }
        }

        // Single save after all in-place updates and deletes.
        try modelContext.save()
    }

    /// Deletes all SwiftData records belonging to the guest user ("guest" userId).
    /// Called when a guest taps "Sign Out" and confirms they want to delete local data.
    func deleteAllGuestData() async throws {
        let guestEntries = try modelContext.fetch(
            FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.userId == "guest" })
        )
        for entry in guestEntries { modelContext.delete(entry) }

        let guestGoals = try modelContext.fetch(
            FetchDescriptor<DailyGoal>(predicate: #Predicate { $0.userId == "guest" })
        )
        for goal in guestGoals { modelContext.delete(goal) }

        let guestProgress = try modelContext.fetch(
            FetchDescriptor<UserProgress>(predicate: #Predicate { $0.userId == "guest" })
        )
        for progress in guestProgress { modelContext.delete(progress) }

        let guestQuests = try modelContext.fetch(
            FetchDescriptor<DailyQuest>(predicate: #Predicate { $0.userId == "guest" })
        )
        for quest in guestQuests { modelContext.delete(quest) }

        let guestMoods = try modelContext.fetch(
            FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.userId == "guest" })
        )
        for mood in guestMoods { modelContext.delete(mood) }

        let guestBaselines = try modelContext.fetch(
            FetchDescriptor<PersonalBaseline>(predicate: #Predicate { $0.userId == "guest" })
        )
        for baseline in guestBaselines { modelContext.delete(baseline) }

        let guestCustomFoods = try modelContext.fetch(
            FetchDescriptor<CustomFood>(predicate: #Predicate { $0.userId == "guest" })
        )
        for food in guestCustomFoods { modelContext.delete(food) }

        let guestMeals = try modelContext.fetch(
            FetchDescriptor<SavedMeal>(predicate: #Predicate { $0.userId == "guest" })
        )
        for meal in guestMeals { modelContext.delete(meal) }

        let guestRecipes = try modelContext.fetch(
            FetchDescriptor<SavedRecipe>(predicate: #Predicate { $0.userId == "guest" })
        )
        for recipe in guestRecipes { modelContext.delete(recipe) }

        let guestBadges = try modelContext.fetch(
            FetchDescriptor<BadgeProgress>(predicate: #Predicate { $0.userId == "guest" })
        )
        for badge in guestBadges { modelContext.delete(badge) }

        let guestProfiles = try modelContext.fetch(
            FetchDescriptor<UserProfile>(predicate: #Predicate { $0.userId == "guest" })
        )
        for profile in guestProfiles { modelContext.delete(profile) }

        try modelContext.save()
    }

    /// Explicitly starts Firestore sync for the currently authenticated user.
    /// Called after guest→auth migration completes to begin syncing without
    /// relying on automatic triggers.
    func startFirestoreSyncForCurrentUser() {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return }
        startFirestoreSync(userId: userId)
    }

    /// Applies badge updates received from the Firestore listener. Append-only.
    ///
    /// - Skips badges in `pendingBadgeIds` (local write in-flight — our data is newer).
    /// - Removes from `pendingBadgeIds` when Firestore confirms `isUnlocked == true`.
    /// - Never reverts `isUnlocked` from true to false.
    func applyBadgeUpdates(_ dtos: [BadgeProgressDTO], userId: String) async throws {
        for dto in dtos {
            // Skip if we have a pending local write for this badge
            if FirestoreServiceImpl.shared.pendingBadgeIds.contains(dto.badgeId) {
                if dto.isUnlocked {
                    FirestoreServiceImpl.shared.pendingBadgeIds.remove(dto.badgeId)
                }
                continue
            }

            let descriptor = FetchDescriptor<BadgeProgress>(
                predicate: #Predicate { $0.userId == userId && $0.badgeId == dto.badgeId }
            )
            let existing = try modelContext.fetch(descriptor).first

            if let existing = existing {
                if existing.isUnlocked { continue } // Never revert
                existing.isUnlocked = dto.isUnlocked
                existing.unlockedAt = dto.unlockedAt
            } else {
                let progress = BadgeProgress(
                    userId: userId,
                    badgeId: dto.badgeId,
                    isUnlocked: dto.isUnlocked,
                    unlockedAt: dto.unlockedAt
                )
                modelContext.insert(progress)
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Friendship State

/// Local relationship classification between the current user and another uid.
/// Derived only from cached @Model rows — pure, synchronous, possibly stale.
/// Order of precedence: friends > incomingPending > outgoingPending > none.
enum FriendshipState {
    case none
    case outgoingPending
    case incomingPending
    case friends
}

// MARK: - Leaderboard Entry

/// One ranked row of the friend leaderboard (Friend System Phase 3).
///
/// Plain value type — friends' stats live in memory only, never in SwiftData.
/// `uid` is the sole identity, ranking, and dedup key; `username`/`displayName`
/// are display-only snapshots and may be stale.
struct LeaderboardEntry: Identifiable, Equatable {
    let uid: String
    let username: String
    let displayName: String
    let level: Int
    let totalXP: Int
    let currentStreak: Int
    let rank: String
    let weeklyGoalsMet: Int
    let weeklyAdherence: Double
    let isCurrentUser: Bool

    /// False when this friend has not published a projection yet — rendered as
    /// "no data yet" and always sorted to the bottom.
    let hasData: Bool

    /// True when this entry's uid is a friend of the current user. Populated by
    /// the guild leaderboard (G2) — resolved once during load so the view can
    /// drive the friend-only profile tap from this flag (no per-row lookup).
    /// Unused by the friend leaderboard (every row there is already a friend),
    /// where it harmlessly stays `false`.
    var isFriend: Bool = false

    /// Identifiable keys on the uid only.
    var id: String { uid }
}

// MARK: - Placeholder Friend (TESTING ONLY)

/// TESTING ONLY — a fake friend every signed-in user sees, so the friends
/// list, leaderboard, and profile sheet can be exercised without a second
/// account. Lives entirely in memory: never written to SwiftData (the friend
/// listeners' reconcile would delete it) and never written to Firestore.
/// Grep "PlaceholderFriend" and delete every reference to remove the fixture.
enum PlaceholderFriend {
    static let uid = "placeholder-test-friend"
    static let username = "testbuddy"
    static let displayName = "Test Buddy"

    /// Fabricated projection that exercises every field of the profile sheet:
    /// rank pill, level, both streaks, member-since, adherence, badge grid.
    static let stats = PublicStatsDTO(
        username: username,
        displayName: displayName,
        level: 12,
        totalXP: 4200,
        currentStreak: 5,
        rank: Rank.gold.rawValue,
        weeklyGoalsMet: 5,
        weeklyAdherence: 5.0 / 7.0,
        longestStreak: 21,
        joinedAt: Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)),
        badgeCount: 3,
        earnedBadgeIds: ["first_flame", "goal_getter", "week_warrior"],
        updatedAt: Date()
    )

    /// TESTING ONLY — fabricated activity-feed events so the Friends → Activity
    /// segment shows content without a second account. Exercises all four event
    /// types; timestamps are relative to now so the "Xh ago" labels read live.
    /// Values line up with the fabricated `stats` above (Level 12, Gold, its
    /// earned badges). Grep "PlaceholderFriend" to remove the whole fixture.
    static func feedItems() -> [FeedItem] {
        let now = Date()
        func event(_ type: String, _ value: String, hoursAgo: Double,
                   cheers: Int = 0, names: [String] = []) -> FeedItem {
            let dto = FeedEventDTO(
                type: type,
                value: value,
                username: username,
                displayName: displayName,
                createdAt: now.addingTimeInterval(-hoursAgo * 3600)
            )
            var item = FeedItem(dto: dto, friendUid: uid)
            // Fabricated cheer counts/names (Phase 8) so the feed shows the
            // cheer affordance populated. didCheer stays false so tapping toggles.
            item.cheerCount = cheers
            item.recentCheererNames = names
            return item
        }
        return [
            event("streak", "30", hoursAgo: 2, cheers: 3, names: ["Sam", "Priya", "Alex"]),
            event("level", "12", hoursAgo: 8, cheers: 1, names: ["Sam"]),
            event("badge", "week_warrior", hoursAgo: 26),
            event("rank", Rank.gold.rawValue, hoursAgo: 50, cheers: 2, names: ["Jordan", "Riley"]),
            event("badge", "first_flame", hoursAgo: 80)
        ]
    }

    /// TESTING ONLY — fabricated OWN milestones (Phase 8) so the "Your
    /// milestones" receipts strip is visible without real emitted events.
    /// Used by loadMyMilestones() only when the user has no real events.
    static func ownMilestones() -> [OwnEventItem] {
        let now = Date()
        func own(_ type: String, _ value: String, hoursAgo: Double,
                 cheers: Int, names: [String]) -> OwnEventItem {
            OwnEventItem(
                eventId: "\(type)_\(value)",
                type: type,
                value: value,
                createdAt: now.addingTimeInterval(-hoursAgo * 3600),
                cheerCount: cheers,
                recentCheererNames: names
            )
        }
        return [
            own("level", "8", hoursAgo: 5, cheers: 4, names: ["Test Buddy", "Sam", "Priya"]),
            own("streak", "7", hoursAgo: 30, cheers: 2, names: ["Alex", "Jordan"])
        ]
    }
}

// MARK: - Badge Trigger

/// Events that can trigger badge unlock checks.
enum BadgeTrigger {
    case foodLogged
    case streakUpdated
    case questsChecked
    case xpAwarded
}

// MARK: - Guild Error (Guilds Prompt G1)

/// Errors surfaced by the guild flow, mirroring FriendError's user-facing style.
enum GuildError: LocalizedError {
    case alreadyInGuild
    case notFound
    case full
    case ownerMustDisband
    case codeCollision
    case notAuthorized
    case network(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInGuild:   return "You're already in a guild. Leave it before joining another."
        case .notFound:         return "No guild was found for that code."
        case .full:             return "This guild is full."
        case .ownerMustDisband: return "As the owner, you can't leave — disband the guild instead."
        case .codeCollision:    return "Couldn't generate a unique guild code. Please try again."
        case .notAuthorized:    return "You don't have permission to do that."
        case .network(let m):   return "Couldn't reach the server. Try again. (\(m))"
        }
    }
}

// MARK: - Guild Chat Error (Guilds Prompt G3)

/// Errors surfaced by guild chat, mirroring GuildError's user-facing style.
enum GuildChatError: LocalizedError {
    case empty
    case tooLong
    case notAuthenticated
    case network(String)

    var errorDescription: String? {
        switch self {
        case .empty:            return "Message can't be empty."
        case .tooLong:          return "Messages are limited to 500 characters."
        case .notAuthenticated: return "You must be signed in to chat."
        case .network(let m):   return "Couldn't send. Try again. (\(m))"
        }
    }
}

// MARK: - Share Error (Friend System Phase 9)

/// Errors surfaced by meal/recipe sharing and import, mirroring FriendError.
enum ShareError: LocalizedError {
    case tooLarge
    case malformed
    case notAuthenticated
    case network(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return "This item is too large to share."
        case .malformed:
            return "This share couldn't be read."
        case .notAuthenticated:
            return "You must be signed in to do that."
        case .network(let message):
            return message
        }
    }
}

// MARK: - Quick-Log Error (Phase 10)

/// Errors surfaced by the quick-log save flow (AI items → SavedMeal/Recipe).
enum QuickLogError: LocalizedError {
    case emptyName
    case nothingToSave

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Please name this meal or recipe."
        case .nothingToSave:
            return "Nothing to save."
        }
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
