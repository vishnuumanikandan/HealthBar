//
//  DataManager.swift
//  HealthBar
//
//  Created by Claude on 1/19/26.
//

import Foundation
import SwiftData
// UGC-1a: DataManager may reference Firestore types (architecture spine allows it
// here and in the service layer). Used ONLY to classify a permission-denied NSError
// in the sendChallenge catch — all Firestore I/O still goes through firestoreService.
import FirebaseFirestore

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

    /// In-memory cache of the current user's blocklist (UGC-1a). Fetch-on-login
    /// only (NOT a listener) — loaded by `loadBlocklist`, mutated by block/unblock,
    /// reset to [] at every sign-out/user-switch teardown. The rules are the real
    /// enforcement boundary; this only powers client UX (and UGC-1b's management screen).
    ///
    /// UGC-1b-FIX: `static` — SHARED across every DataManager instance. ContentView builds a
    /// separate AppCoordinator→DataManager per tab, so a per-instance cache is invisible to the
    /// instance serving another surface: a block (or the login-time load) lands on one instance
    /// while the Add Friend directory / guild roster / guild leaderboard are served by a
    /// different instance whose cache was still empty (SMOKE-3: those three read a stale/empty
    /// blocklist and never filtered). One shared cache — loaded once, mutated by block/unblock,
    /// read by every filter on every tab — is the single source of truth. One user is signed in
    /// at a time and the teardown below clears it on sign-out/user-switch, so there is no leak.
    private(set) static var blockedUids: Set<String> = []

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
            // UGC-1a: drop the blocklist cache on sign-out / user-switch so it can't
            // leak into the next session (guest or another user). loadBlocklist
            // repopulates on the next authenticated login.
            DataManager.blockedUids = []
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

        // UGC-1a: load the private blocklist into the in-memory cache (fetch-on-login,
        // NOT a listener). Overwrites the cache; the block rules enforce server-side.
        Task { await self.loadBlocklist(userId: userId) }

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

            // --- QTEDay (D1d) ---
            if let remoteQTEDTOs = try? await firestoreService.fetchQTEDays(userId: userId) {
                let remoteKeys = Set(remoteQTEDTOs.map { $0.dateKey })
                for dto in remoteQTEDTOs {
                    applyQTEDayMerge(dto, userId: userId) // max-wins into local (create if absent)
                }
                let localDays = (try? fetchAllQTEDaysForSync(userId: userId)) ?? []
                for day in localDays where !remoteKeys.contains(day.dateKey) {
                    try? await firestoreService.uploadQTEDay(QTEDayDTO(from: day), userId: userId)
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
    /// Receive-only — never uploads. Merge rules for gamification fields:
    /// - `totalXP`, `longestStreak` → `max()` wins (never decrease)
    /// - `lastActiveDate` → `max()` wins
    /// - `claimedMilestones` → set union (milestones are never un-claimed)
    /// - `currentStreak` → Firestore value wins (NON-monotonic — a missed-day reset must
    ///   propagate across devices; `max()` would resurrect a broken streak — review finding H1)
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
            // Additive fields (monotonic): max()/union wins — never decrease.
            let mergedTotalXP = max(dto.totalXP, local.totalXP)
            let mergedLongestStreak = max(dto.longestStreak, local.longestStreak)
            let mergedLastActiveDate = max(dto.lastActiveDate, local.lastActiveDate)
            let mergedClaimedSet = Set(dto.claimedMilestonesArray).union(local.claimedMilestoneSet)
            let mergedClaimedString = mergedClaimedSet.sorted().map { String($0) }.joined(separator: ",")

            let isPending = FirestoreServiceImpl.shared.pendingProgressIds.contains(dto.id)

            // Non-monotonic fields — `rr` + the five duel-record fields (fills RR-0a's TODO(D1)).
            // These are Firestore-authoritative and can DECREASE (rr drops, win streak resets), so
            // NEVER max(). While a local write is pending, PROTECT the local value until the server
            // echo MATCHES it (equality) — a stale sync-down must not clobber a just-resolved rr /
            // streak. Not pending, or echo matches ⇒ apply the Firestore value verbatim.
            func reconcile<T: Equatable>(_ remote: T, _ localValue: T) -> T {
                (isPending && remote != localValue) ? localValue : remote
            }
            let mergedRR = reconcile(dto.resolvedRR, local.rr)
            // H1: currentStreak is NON-monotonic — GamificationManager.updateStreak resets it
            // to 1 on a missed day, so max() would resurrect a reset streak across devices
            // (inflating the published leaderboard streak + re-granting milestone badges).
            // Reconcile it Firestore-authoritatively, exactly like rr.
            let mergedCurrentStreak = reconcile(dto.currentStreak, local.currentStreak)
            let mergedWins = reconcile(dto.resolvedDuelWins, local.duelWins)
            let mergedLosses = reconcile(dto.resolvedDuelLosses, local.duelLosses)
            let mergedDraws = reconcile(dto.resolvedDuelDraws, local.duelDraws)
            let mergedCurrentWinStreak = reconcile(dto.resolvedCurrentWinStreak, local.currentWinStreak)
            let mergedBestWinStreak = reconcile(dto.resolvedBestWinStreak, local.bestWinStreak)
            // D3 per-league counters — same non-monotonic Firestore-authoritative reconcile.
            let mergedWins1 = reconcile(dto.resolvedDuelWins1, local.duelWins1)
            let mergedWins3 = reconcile(dto.resolvedDuelWins3, local.duelWins3)
            let mergedWins5 = reconcile(dto.resolvedDuelWins5, local.duelWins5)
            let mergedStreak1 = reconcile(dto.resolvedWinStreak1, local.winStreak1)
            let mergedStreak3 = reconcile(dto.resolvedWinStreak3, local.winStreak3)
            let mergedStreak5 = reconcile(dto.resolvedWinStreak5, local.winStreak5)

            if isPending {
                // Additive confirmation: Firestore must be "at least as good" as local. A stale
                // snapshot (lower additive values) is skipped entirely — which also protects the
                // non-monotonic fields (their equality guard is handled by reconcile() above).
                // H1: no `currentStreak >= local` term — currentStreak is now reconciled
                // like rr (its pending/echo guard lives in reconcile() above), so a legit
                // lower remote streak (a missed-day reset) must NOT block confirmation.
                let firestoreIsConfirmed = dto.totalXP >= local.totalXP
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
                || mergedWins != local.duelWins
                || mergedLosses != local.duelLosses
                || mergedDraws != local.duelDraws
                || mergedCurrentWinStreak != local.currentWinStreak
                || mergedBestWinStreak != local.bestWinStreak
                || mergedWins1 != local.duelWins1
                || mergedWins3 != local.duelWins3
                || mergedWins5 != local.duelWins5
                || mergedStreak1 != local.winStreak1
                || mergedStreak3 != local.winStreak3
                || mergedStreak5 != local.winStreak5

            if changed {
                local.totalXP = mergedTotalXP
                local.currentStreak = mergedCurrentStreak
                local.longestStreak = mergedLongestStreak
                local.lastActiveDate = mergedLastActiveDate
                local.claimedMilestones = mergedClaimedString
                local.rr = mergedRR
                local.duelWins = mergedWins
                local.duelLosses = mergedLosses
                local.duelDraws = mergedDraws
                local.currentWinStreak = mergedCurrentWinStreak
                local.bestWinStreak = mergedBestWinStreak
                local.duelWins1 = mergedWins1
                local.duelWins3 = mergedWins3
                local.duelWins5 = mergedWins5
                local.winStreak1 = mergedStreak1
                local.winStreak3 = mergedStreak3
                local.winStreak5 = mergedStreak5
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

        // Clean-log QTE (D1d): a low-toxin meal logged mid-duel offers a tap-timing flourish,
        // presented root-level from ContentView so ALL logging flows are covered. Guest-gated,
        // duel-gated, cap-gated, one pending at a time (a second qualifying meal while one is
        // pending is silently skipped — no queue). No local row yet ⇒ 0 clean-log points ⇒ offer.
        if !isGuest, toxinScore < DuelConstants.cleanLogToxinThreshold {
            let mealName = name
            Task { @MainActor in
                guard DuelUIState.shared.activeDuelCount > 0,
                      DuelUIState.shared.pendingCleanLogQTE == nil else { return }
                let cleanLogPoints = (await todayQTEState())?.cleanLogPoints ?? 0
                guard cleanLogPoints < DuelConstants.cleanLogPointsCap else { return }
                DuelUIState.shared.pendingCleanLogQTE = PendingCleanLogQTE(mealName: mealName)
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

        // Calories: per-entry mean, pooled by weekday (semantics unchanged).
        var caloriesByDayOfWeek: [Int: [Int]] = [:]
        // Purity: a DAILY metric, so each calendar date is scored ONCE via the canonical
        // weighted average and the baseline averages those daily scores. Pooling raw
        // per-entry toxin scores would let a 5-meal day outweigh a 1-meal day 5:1.
        var entriesByDate: [Date: [FoodEntry]] = [:]

        for entry in entries {
            let dayOfWeek = calendar.component(.weekday, from: entry.date)
            caloriesByDayOfWeek[dayOfWeek, default: []].append(entry.calories)
            entriesByDate[calendar.startOfDay(for: entry.date), default: []].append(entry)
        }

        var dailyToxinByDayOfWeek: [Int: [Int]] = [:]
        for (date, dayEntries) in entriesByDate {
            let dayOfWeek = calendar.component(.weekday, from: date)
            dailyToxinByDayOfWeek[dayOfWeek, default: []]
                .append(NutritionManager.dailyToxinScore(from: dayEntries))
        }

        for dayOfWeek in 1...7 {
            guard let dayCalories = caloriesByDayOfWeek[dayOfWeek], !dayCalories.isEmpty,
                  let dailyToxins = dailyToxinByDayOfWeek[dayOfWeek], !dailyToxins.isEmpty else { continue }

            let avgCalories = Double(dayCalories.reduce(0, +)) / Double(dayCalories.count)
            let avgDailyToxin = Double(dailyToxins.reduce(0, +)) / Double(dailyToxins.count)

            // updateBaseline is already userId-scoped
            try await updateBaseline(dayOfWeek: dayOfWeek, calories: avgCalories, purity: avgDailyToxin)
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
    ///
    /// D2 "Meals Logged" tile (F1a): a `fetchCount` — never materializes rows. The value
    /// reflects LOCALLY SYNCED entries and can read low immediately after a reinstall until
    /// Firestore sync catches up — accepted (F1a), no UI caveat.
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

        // NAV-1a: republish so earnedBadgeIds includes this unlock (the surrounding XP/food publishes race the upsert). Best-effort like every publish site — a failure self-heals on the next publish.
        if !newlyUnlocked.isEmpty { Task { await publishMyStats() } }

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

        // UGC-1a: profanity/slur chokepoint. This single site covers claim, change,
        // AND ClaimUsernameViewModel's live inline validation (it calls this
        // function) — the new error flows to the existing inline error UI, no view edit.
        guard !ProfanityFilter.containsBlockedTerm(lowercased) else {
            throw UsernameError.notAllowed
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
        // UGC-1b (chokepoint 1): belt filter on friendUid. Edges are removed at block
        // time, so this only covers multi-device staleness — but it does so for the
        // Friends tab, Home standings, feed fan-out, AND the C1 friends carousel in one
        // site (every consumer routes through fetchFriends()).
        return try modelContext.fetch(descriptor).filter { !isBlocked($0.friendUid) }
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

        // UGC-1b (chokepoint 2): hide blocked users from the Add Friend directory.
        return latestByUid.values.filter { !isBlocked($0.uid) }.sorted { $0.username < $1.username }
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

        // NAV-1a: self-check and all post-resolution work live in the uid-keyed core;
        // the resolved handle rides along as the display-only snapshot.
        try await sendFriendRequest(toUid: toUid, username: handleKey)
    }

    /// uid-keyed core of the friend-request flow (NAV-1a). The handle path
    /// (`sendFriendRequest(toHandle:)`) resolves the username to a uid and
    /// delegates here; the NAV-1a profile "Add Friend" calls it directly with a
    /// uid it already holds — no handle resolution, since usernames are mutable.
    /// `username` is a display-only snapshot stamped into the request + local row
    /// per the privacy spine (a stale value is acceptable); identity keys on `toUid`.
    func sendFriendRequest(toUid: String, username: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw FriendError.network("You must be signed in to add friends.")
        }
        guard toUid != me else { throw FriendError.cannotFriendSelf }

        switch friendshipState(with: toUid) {
        case .friends:
            throw FriendError.alreadyFriends
        case .incomingPending:
            throw FriendError.incomingExists
        case .outgoingPending:
            // Local fast-path only (cheap early exit); can be stale/empty on a fresh account,
            // so the authoritative outgoingRequestExists check below is the real gate (FR-1).
            return
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

        // FR-1: authoritative send idempotency. friendshipState reads LOCAL cache (stale/empty
        // on a fresh account) and re-send is NOT idempotent — setData over an existing request
        // doc is an UPDATE, and friendRequests/sentRequests rule `allow update: if false` (F1),
        // so a second tap would PERMISSION_DENIED. If the request is already out on the server,
        // that is exactly what the user wanted → reflect it locally and return success.
        let alreadySent: Bool
        do {
            alreadySent = try await firestoreService.outgoingRequestExists(meUid: me, toUid: toUid)
        } catch {
            throw FriendError.network(error.localizedDescription)
        }
        if alreadySent {
            insertLocalOutgoingRequest(toUid: toUid, toUsername: username, userId: me)
            return
        }

        let identity = try await fetchMyFriendIdentity(userId: me)
        do {
            try await firestoreService.sendFriendRequest(
                toUid: toUid,
                toUsername: username,
                fromUid: me,
                fromUsername: identity.username,
                fromDisplayName: identity.displayName
            )
        } catch {
            // UGC-1b (D8): a permission-denied on this FRESH create is treated as a block — the
            // friendRequests create rule's blockedEither() guard is the only deny path a
            // well-formed request hits. Same soft-copy assumption as DuelError.blocked (1a):
            // residual causes (expired auth, future rule changes) share this code, so block state
            // is never disclosed. This is the fresh-create path ONLY — the FR-1 idempotency branch
            // above already returned success for a re-send, so it is never reached here.
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                throw FriendError.blocked
            }
            throw FriendError.network(error.localizedDescription)
        }
        // FR-1: reflect outgoing-pending immediately so the button flips before the sentRequests
        // listener syncs (addFriend calls load() right after, re-deriving friendshipState).
        insertLocalOutgoingRequest(toUid: toUid, toUsername: username, userId: me)
    }

    /// FR-1: inserts (idempotently) the local outgoing FriendRequest row so friendshipState
    /// reports .outgoingPending immediately — the sentRequests listener would otherwise lag.
    /// Mirrors reconcileRequests' insert; the listener later reconciles the authoritative row.
    private func insertLocalOutgoingRequest(toUid: String, toUsername: String, userId: String) {
        let descriptor = FetchDescriptor<FriendRequest>(
            predicate: #Predicate { $0.userId == userId && $0.otherUid == toUid && $0.direction == "outgoing" }
        )
        if let count = try? modelContext.fetchCount(descriptor), count > 0 { return }
        modelContext.insert(FriendRequest(
            userId: userId, otherUid: toUid, direction: "outgoing",
            username: toUsername, displayName: toUsername, createdAt: Date()
        ))
        try? modelContext.save()
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

        // FR-1: idempotent accept. The cached row can be stale, and a second accept would
        // setData over the EXISTING friend edges — `friends` rules `allow update: if false`
        // (F1) → PERMISSION_DENIED. If the edge already exists on the server, the accept
        // already happened: clear any lingering request docs (deletes are no-op if absent)
        // and return success without re-writing the edges.
        let alreadyFriends: Bool
        do {
            alreadyFriends = try await firestoreService.friendExists(meUid: me, friendUid: fromUid)
        } catch {
            throw FriendError.network(error.localizedDescription)
        }
        if alreadyFriends {
            try? await firestoreService.declineFriendRequest(fromUid: fromUid, meUid: me)
            return
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
        try await firestoreService.removeFriend(friendUid: friendUid, meUid: me)
    }

    // MARK: - Safety: blocking + reporting (UGC-1a)

    /// Loads the blocklist into the in-memory cache on login (D5). Guests keep an
    /// empty cache. OVERWRITES the cache; a fetch failure leaves it as-is and logs
    /// (non-fatal — the block rules still enforce server-side).
    func loadBlocklist(userId: String) async {
        guard !isGuest else { return }
        do {
            let remote = try await firestoreService.fetchBlocklist(userId: userId)
            DataManager.blockedUids = Set(remote)
        } catch {
            print("⚠️ loadBlocklist failed (cache left unchanged): \(error.localizedDescription)")
        }
    }

    /// Pure cache lookup. Guests are never blocking anyone → false.
    func isBlocked(_ uid: String) -> Bool {
        guard !isGuest else { return false }
        return DataManager.blockedUids.contains(uid)
    }

    /// Blocks `uid`. Cleans up the relationship BEFORE recording the block (D4) so
    /// a cleanup failure aborts the whole call, the block is NOT recorded, and a
    /// retry re-runs cleanup idempotently. Active duels are deliberately untouched.
    func blockUser(_ uid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw BlockError.notAuthenticated
        }
        // Self / empty ⇒ nothing to do.
        guard uid != me, !uid.isEmpty else { return }
        // Idempotent: re-blocking is a no-op success (checked before the cap so a
        // full blocklist never turns a redundant re-block into an error).
        guard !DataManager.blockedUids.contains(uid) else { return }
        guard DataManager.blockedUids.count < UGCConstants.maxBlocklistSize else {
            throw BlockError.limitReached
        }

        do {
            // (1) Remove the friend edge — idempotent (no-op if not friends; delete of
            //     an absent edge is permitted). We do NOT gate on stale local
            //     friendship state (FR-1); an unconditional removeFriend is correct.
            try await removeFriend(friendUid: uid)
            // (2) Decline any incoming pending request from them + cancel any sent
            //     pending request to them (both delete-absent = no-op).
            try await declineIncomingRequest(fromUid: uid)
            try await cancelSentRequest(toUid: uid)
            // (3) Cancel my outgoing PENDING duels to them + decline incoming PENDING
            //     duels from them, via the same paths the Battle UI uses. A plain
            //     fetch (NOT loadMyDuels) — no scoring/RR side effects during a block.
            let myDuels = try await firestoreService.fetchMyDuels(uid: me)
            for duel in myDuels where duel.statusEnum == .pending {
                if duel.challengerUid == me && duel.opponentUid == uid {
                    try await cancelChallenge(duel)
                } else if duel.opponentUid == me && duel.challengerUid == uid {
                    try await declineChallenge(duel)
                }
            }
            // (4) Record the block, THEN (5) update the in-memory cache.
            try await firestoreService.addToBlocklist(userId: me, blockedUid: uid)
            DataManager.blockedUids.insert(uid)
        } catch let error as BlockError {
            throw error
        } catch {
            throw BlockError.network(error.localizedDescription)
        }
    }

    /// Unblocks `uid`: removes the Firestore entry and the cache entry. Idempotent.
    /// No friend restoration (D4).
    func unblockUser(_ uid: String) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw BlockError.notAuthenticated
        }
        do {
            try await firestoreService.removeFromBlocklist(userId: me, blockedUid: uid)
            DataManager.blockedUids.remove(uid)
        } catch {
            throw BlockError.network(error.localizedDescription)
        }
    }

    /// Submits a moderation report (UGC-1a). The reportId is deterministic per (me,
    /// target) so a duplicate report collides on the same doc; the create-only rules
    /// reject the duplicate as an update, and that permission-denied is caught here
    /// and returned as silent idempotent success ("already reported", D6).
    func submitReport(context: ReportContext, reportedUid: String,
                      contentSnapshot: String, guildCode: String?,
                      messageId: String?) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            throw BlockError.notAuthenticated
        }
        guard reportedUid != me, !reportedUid.isEmpty else { return }

        // Deterministic reportId per D6.
        let reportId: String
        switch context {
        case .chatMessage: reportId = "\(me)_msg_\(messageId ?? "")"
        case .userProfile: reportId = "\(me)_user_\(reportedUid)"
        case .guild:       reportId = "\(me)_guild_\(guildCode ?? "")"
        }

        // Trim whitespace/newlines, THEN truncate to the snapshot cap, before writing
        // (the single clamp site, D12).
        let trimmed = contentSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = String(trimmed.prefix(UGCConstants.maxReportSnapshotLength))

        let report = ReportDTO(
            reporterUid: me,
            reportedUid: reportedUid,
            contextType: context.rawValue,
            contentSnapshot: snapshot,
            guildCode: guildCode,
            messageId: messageId,
            createdAt: nil
        )
        do {
            try await firestoreService.submitReport(report, reportId: reportId)
        } catch {
            // Duplicate report ⇒ create-only rules reject the update ⇒ already reported.
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                return
            }
            throw BlockError.network(error.localizedDescription)
        }
    }

    /// UGC-1b (D6/D7): resolves the blocklist into display rows for the Blocked Users screen.
    /// Each blocked uid is looked up in the world-readable `leaderboard/{uid}` projection (the
    /// C1 rail); a uid with no leaderboard row (never published / deleted) renders as
    /// "Unknown player" but stays unblock-able (everything keys on uid). Sorted for a stable
    /// list (blockedUids is an unordered Set). Guests never block anyone → [].
    func blockedUsersDisplay() async -> [(uid: String, username: String, displayName: String)] {
        guard !isGuest else { return [] }
        let uids = Array(DataManager.blockedUids)
        guard !uids.isEmpty else { return [] }

        let entries = (try? await firestoreService.fetchLeaderboardEntries(uids: uids)) ?? []
        var byUid: [String: GlobalLeaderboardDTO] = [:]
        for entry in entries { if let id = entry.id { byUid[id] = entry } }

        let rows = uids.map { uid -> (uid: String, username: String, displayName: String) in
            if let entry = byUid[uid] {
                return (uid: uid, username: entry.username, displayName: entry.displayName)
            }
            return (uid: uid, username: "", displayName: "Unknown player")
        }
        // Stable order: by the name the row renders (displayName, else @username).
        return rows.sorted {
            let l = ($0.displayName.isEmpty ? $0.username : $0.displayName).lowercased()
            let r = ($1.displayName.isEmpty ? $1.username : $1.displayName).lowercased()
            return l < r
        }
    }

    // MARK: - Guilds (G1)

    /// Hard member cap (GUILD-CAP-1). The real enforcement is the RULES boundary,
    /// checking every membership batch against the guild doc's `memberCount` field;
    /// the client checks below are UX only, surfacing `GuildError.full` before the
    /// write. Open self-join now pre-checks too — the guild doc is get-readable by
    /// anyone authed, unlike the roster (the old best-effort no-op).
    ///
    /// KEEP IN SYNC WITH firestore.rules literal 40
    static let maxMembers = 40

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
        // R7d: "private" joins the enum — joinable by code like an open guild, but
        // hidden from the browsable directory. Kept in lockstep with the rules'
        // `joinPolicy in ['open','request','private']` on guild create/update.
        guard joinPolicy == "open" || joinPolicy == "request" || joinPolicy == "private" else {
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
        // UGC-1a: profanity/slur chokepoint for guild name AND description (either
        // hit rejects). Runs after the existing length checks. Shared by createGuild
        // and updateGuildSettings, so both entry points are covered here.
        guard !ProfanityFilter.containsBlockedTerm(trimmedName) else {
            throw GuildError.notAllowed
        }
        if let finalDesc, ProfanityFilter.containsBlockedTerm(finalDesc) {
            throw GuildError.notAllowed
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

    /// The browsable directory of joinable guilds (R7d): open + request policies only,
    /// name-ordered, capped. Empty for guests (D5) and on failure — the view model
    /// surfaces the error separately via the throwing path it wraps.
    func fetchGuildDirectory() async throws -> [GuildDTO] {
        guard !isGuest else { return [] }
        do { return try await firestoreService.fetchGuildDirectory() }
        catch { throw GuildError.network(error.localizedDescription) }
    }

    /// The roster for a guild. Readable by members (and the owner); empty for guests
    /// or when the caller is not permitted to read it.
    func guildMembers(code: String) async -> [GuildMemberDTO] {
        guard !isGuest else { return [] }
        // UGC-1b (chokepoint 3): filter blocked members from the roster. loadGuildLeaderboard()
        // sources its roster through this method (`let roster = await guildMembers(code: code)`),
        // so the guild leaderboard is covered here too — no separate filter needed there.
        return ((try? await firestoreService.fetchGuildMembers(code: code)) ?? [])
            .filter { !isBlocked($0.uid) }
    }

    /// Pending join requests for a guild (owner-only by rules). Empty otherwise.
    func joinRequests(code: String) async -> [GuildJoinRequestDTO] {
        guard !isGuest else { return [] }
        // UGC-1b (chokepoint 12): a blocked user's join request to my guild should not
        // render. The request doc itself is untouched — the owner simply doesn't see it
        // (and would never approve them anyway); leaving it unactioned is the correct
        // passive outcome.
        return ((try? await firestoreService.fetchJoinRequests(code: code)) ?? [])
            .filter { !isBlocked($0.uid) }
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

        // GUILD-CAP-1: cap pre-check now reads the guild doc's `memberCount`
        // (already fetched above; get-readable by anyone authed — the roster was
        // NOT, which is why open self-join could never enforce the cap before). A
        // KNOWN count at/over capacity throws `full`; nil = legacy pre-backfill doc
        // = UNKNOWN (never 0), so we skip the UX pre-check and let the rules decide.
        // The rules remain the enforcement boundary; this is UX.
        if let count = guild.memberCount, count >= DataManager.maxMembers {
            throw GuildError.full
        }

        let identity = try await fetchMyFriendIdentity(userId: me)
        // R7d D2: "private" routes like "open" — a direct join. Private guilds are hidden
        // from the directory, not harder to join once you hold the code; the members-create
        // rule mirrors this (`joinPolicy in ['open','private']`). Only "request" defers to
        // an approval. Without this branch a valid private code would error.
        if guild.joinPolicy == "open" || guild.joinPolicy == "private" {
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
        let guild = try await requireOwnedGuild(code: code, me: me)

        // GUILD-CAP-1: primary pre-check on the guild doc's `memberCount` (fetched
        // by requireOwnedGuild — no added read). nil = legacy pre-backfill doc =
        // UNKNOWN, so fall through to the roster assert / server enforcement.
        if let count = guild.memberCount, count >= DataManager.maxMembers {
            throw GuildError.full
        }

        // Secondary assert on the roster the owner is already entitled to read (no
        // read added beyond this pre-existing one): keeps a legacy nil-memberCount
        // guild capped during the pre-backfill window. The rules are the real boundary.
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
        // UGC-1b (chokepoint 4): hide messages from blocked senders — both existing history
        // and live updates — before the VM's closure ever sees them. Only the update callback
        // is wrapped; the ListenerRegistration itself stays inside FirestoreServiceImpl (spine).
        // Filtering is one-way: I stop seeing their messages; they still see mine.
        firestoreService.startGuildChatListener(
            code: code,
            onUpdate: { [weak self] messages in
                guard let self else { onUpdate(messages); return }
                onUpdate(messages.filter { !self.isBlocked($0.senderUid) })
            },
            onError: onError
        )
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
            if dayGoalMet(dayStart: dayStart, entriesByDay: entriesByDay, goalsByRecency: goalsByRecency, calendar: calendar) {
                goalsMet += 1
            }
        }

        // Explicit Double conversion — integer division would collapse to 0 or 1.
        return (goalsMet, Double(goalsMet) / 7.0)
    }

    /// The per-day goal-met decision, shared by weekly adherence (the streak / weeklyGoalsMet
    /// pipeline) and the D2 Goal Calendar. A day with NO entries is NOT met (absence is
    /// non-adherence, never skipped); a day with no goal on record is NOT met; otherwise the
    /// one shared predicate `NutritionManager.didMeetGoals` decides. Extracted so the calendar
    /// and streaks can never disagree — both call THIS.
    private func dayGoalMet(dayStart: Date,
                            entriesByDay: [Date: [FoodEntry]],
                            goalsByRecency: [DailyGoal],
                            calendar: Calendar) -> Bool {
        guard let dayEntries = entriesByDay[dayStart], !dayEntries.isEmpty else { return false }
        guard let goal = goalInEffect(on: dayStart, calendar: calendar, goalsByRecency: goalsByRecency) else { return false }
        return nutritionManager.didMeetGoals(entries: dayEntries, goal: goal)
    }

    /// The set of day-starts in the CURRENT calendar month whose daily goal was MET, for the
    /// D2 Goal Calendar. LOCAL SwiftData only — no network. Guest-safe: reads the caller's own
    /// `userId`-scoped rows (guests get their local days), so this is NOT a Firestore entry point
    /// and needs no `isGuest` gate. Future days are never included.
    ///
    /// single met-predicate — calendar must never disagree with streaks: each day is decided by
    /// `dayGoalMet(...)`, the SAME per-day rule the weekly-adherence / streak pipeline uses
    /// (didMeetGoals + goalInEffect + startOfDay bucketing). Reuses that exact day-bucketing
    /// (`Calendar.current`, `startOfDay`) so a day counted for a streak is the same day painted
    /// green. Throws on a local read failure so the caller can hide the section (D10).
    func goalMetDaysForCurrentMonth() async throws -> Set<Date> {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let monthInterval = calendar.dateInterval(of: .month, for: todayStart) else { return [] }

        let entries = try await fetchEntriesForDateRange(start: monthInterval.start, end: monthInterval.end)
        let entriesByDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        let goals = try await fetchAllDailyGoalsForSync(userId: userId)
        let goalsByRecency = goals.sorted { $0.date > $1.date }

        var met: Set<Date> = []
        var day = monthInterval.start
        while day < monthInterval.end {
            // Evaluate only up to and including today — future days are never "met".
            if day <= todayStart,
               dayGoalMet(dayStart: day, entriesByDay: entriesByDay, goalsByRecency: goalsByRecency, calendar: calendar) {
                met.insert(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return met
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

        // D3: also upsert my world-readable global leaderboard row from the SAME identity
        // snapshot + local UserProgress (rr + the six per-league counters). Guest-safe: the
        // buildMyStatsSnapshot guard above already returned for guests. Error-swallowed like the
        // public/stats publish — a failed upsert self-heals on the next publish.
        if let progress = try? await getUserProgress() {
            let entry = GlobalLeaderboardDTO(
                id: nil,
                username: dto.username,
                displayName: dto.displayName,
                rr: max(0, progress.rr),
                wins1: progress.duelWins1, wins3: progress.duelWins3, wins5: progress.duelWins5,
                streak1: progress.winStreak1, streak3: progress.winStreak3, streak5: progress.winStreak5,
                updatedAt: nil
            )
            try? await firestoreService.upsertLeaderboardEntry(entry, userId: userId)
        }

        // D1b: the publish chokepoints are also where my active-duel scores are pushed.
        // updateMyDuelScores writes ONLY duel docs (never saveUserProgress/publishMyStats),
        // so this cannot recurse. Guest / no-op publishes already returned above.
        await updateMyDuelScores()
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
        let rr = progress.rr

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
            rr: rr,
            weeklyGoalsMet: goalsMet,
            weeklyAdherence: adherence,
            longestStreak: longestStreak,
            joinedAt: identity.createdAt, // nil (field omitted) for legacy accounts
            badgeCount: earnedBadgeIds.count,
            earnedBadgeIds: earnedBadgeIds,
            updatedAt: nil // encoded as FieldValue.serverTimestamp() via @ServerTimestamp
        )
    }

    // MARK: - Duels (D1a)

    /// Challengeable people who live in their OWN lobby sections: my friends (Rivals) and my
    /// guild roster (Guild), deduped by uid (a person who is both is kept as `.friend`),
    /// excluding myself. Sourced from the already-readable friend list + guild members — no new
    /// private-data reads. Empty for guests.
    ///
    /// C1: the public-directory union was REMOVED. "Everyone else" is now the RR-proximity stream
    /// (`fetchNearbyRanked`) plus @handle search (`lookupChallengeCandidate`), both backed by the
    /// world-readable `leaderboard/{uid}` projection — so the challenge surface shows only ranked
    /// players, not every account ever created. `rr` is nil for these rows: neither the `Friend`
    /// model nor `GuildMemberDTO` carries rr, and the lobby renders a plaque + RR only when
    /// rr is non-nil.
    func fetchChallengeablePeople() async -> [DuelOpponentCandidate] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [] }

        var byUid: [String: DuelOpponentCandidate] = [:]

        // Friends first (they win the dedup).
        let friends = (try? await fetchFriends()) ?? []
        for f in friends where f.friendUid != me && !f.friendUid.isEmpty {
            byUid[f.friendUid] = DuelOpponentCandidate(
                uid: f.friendUid, username: f.username, displayName: f.displayName, source: .friend, rr: nil
            )
        }

        // Guild roster (add only uids not already present as a friend).
        if let guild = await myGuild(), let code = guild.id {
            for m in await guildMembers(code: code) where m.uid != me && !m.uid.isEmpty {
                if byUid[m.uid] == nil {
                    byUid[m.uid] = DuelOpponentCandidate(
                        uid: m.uid, username: m.username, displayName: m.displayName, source: .guild, rr: nil
                    )
                }
            }
        }

        return byUid.values.sorted {
            $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending
        }
    }

    // MARK: - Duels: RR-proximity challenge stream (C1)

    /// One page of the RR-proximity stream: merged rows (proximity-ordered, exclusions applied)
    /// plus the two directional cursors. A nil cursor marks that direction exhausted.
    struct ProximityPage {
        let rows: [DuelOpponentCandidate]        // merged, proximity-ordered, exclusions applied
        let upCursor: (rr: Int, uid: String)?    // nil once .up is exhausted
        let downCursor: (rr: Int, uid: String)?  // nil once .down is exhausted
        var isExhausted: Bool { upCursor == nil && downCursor == nil }
    }

    /// Pure merge of two leaderboard slices into one proximity-ordered list (C1). Sorted by
    /// `|rr − myRR|` ascending; ties broken by higher rr first, then uid ascending (a total,
    /// deterministic order). Rows whose uid is in `excluding` (friends, guild-mates, AND me —
    /// the caller stamps me in) are dropped. Candidate mapping happens AFTER this, keeping the
    /// function domain-minimal and standalone-testable (RED→GREEN vectors: proximity order,
    /// ties, equal-rr page boundary, exclusion, one-direction exhaustion, cursor advance).
    static func mergeByProximity(up: [GlobalLeaderboardDTO],
                                 down: [GlobalLeaderboardDTO],
                                 myRR: Int,
                                 excluding: Set<String>) -> [GlobalLeaderboardDTO] {
        let combined = (up + down).filter { dto in
            guard let uid = dto.id, !uid.isEmpty else { return false }
            return !excluding.contains(uid)
        }
        return combined.sorted { a, b in
            let da = abs(a.rr - myRR)
            let db = abs(b.rr - myRR)
            if da != db { return da < db }            // closer to my RR first
            if a.rr != b.rr { return a.rr > b.rr }    // tie on |Δ| → higher rr first
            return (a.id ?? "") < (b.id ?? "")        // then uid ascending (deterministic)
        }
    }

    /// One page of the RR-proximity stream around my RR. Fetches up to `proximityPerDirection`
    /// rows from each non-exhausted direction CONCURRENTLY (`async let`), then merges by proximity
    /// dropping `excluding` (friends/guild — they live in their own sections) and my own uid.
    /// Each direction's new cursor is the (rr, uid) of the LAST row Firestore returned
    /// (pre-exclusion — excluded rows still advance the cursor, or they would be re-fetched
    /// forever); a short slice (`count < limit`) marks that direction exhausted (nil cursor).
    /// First page: both directions with `after: nil`. Guest → empty exhausted page.
    func fetchNearbyRanked(myRR: Int,
                           upCursor: (rr: Int, uid: String)?,
                           downCursor: (rr: Int, uid: String)?,
                           isFirstPage: Bool,
                           excluding: Set<String>) async -> ProximityPage {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            return ProximityPage(rows: [], upCursor: nil, downCursor: nil)
        }
        let limit = DuelConstants.proximityPerDirection
        let fetchUp = isFirstPage || upCursor != nil
        let fetchDown = isFirstPage || downCursor != nil

        // Both directions concurrently; a per-direction failure degrades to an empty slice.
        async let upResult: [GlobalLeaderboardDTO] = fetchUp
            ? ((try? await firestoreService.fetchLeaderboardSlice(
                direction: .up, fromRR: myRR, after: upCursor, limit: limit)) ?? [])
            : []
        async let downResult: [GlobalLeaderboardDTO] = fetchDown
            ? ((try? await firestoreService.fetchLeaderboardSlice(
                direction: .down, fromRR: myRR, after: downCursor, limit: limit)) ?? [])
            : []
        let upSlice = await upResult
        let downSlice = await downResult

        // New cursor = last raw row if the slice was full; nil (exhausted) on a short slice or a
        // direction we did not fetch this page.
        let newUp: (rr: Int, uid: String)? = (fetchUp && upSlice.count == limit)
            ? upSlice.last.map { ($0.rr, $0.id ?? "") } : nil
        let newDown: (rr: Int, uid: String)? = (fetchDown && downSlice.count == limit)
            ? downSlice.last.map { ($0.rr, $0.id ?? "") } : nil

        var exclusions = excluding
        exclusions.insert(me)   // the .up slice includes me by construction (rr >= myRR)
        // UGC-1b (chokepoint 5): exclude blocked users from the C1 NEARBY RANKS stream.
        // mergeByProximity stays pure (exclusions are passed in); the C1 cursors-advance-
        // past-excluded invariant makes this correct with no pagination change.
        exclusions.formUnion(DataManager.blockedUids)
        let rows = Self.mergeByProximity(up: upSlice, down: downSlice, myRR: myRR, excluding: exclusions)
            .map { dto in
                // `.directory` now means "the ranked directory" (leaderboard-backed) — it carries
                // a real displayName + rr, unlike the retired usernames-index directory.
                DuelOpponentCandidate(uid: dto.id ?? "", username: dto.username,
                                      displayName: dto.displayName, source: .directory, rr: dto.rr)
            }
        return ProximityPage(rows: rows, upCursor: newUp, downCursor: newDown)
    }

    /// Resolve a typed `@handle` to a single challenge candidate for the lobby's search field (C1).
    /// Strips a leading `@`, normalizes/validates via the existing username path, resolves the uid
    /// through the public usernames index, then reads that uid's world-readable `leaderboard/{uid}`
    /// row for a real displayName + rr. Returns:
    ///  - a `.directory` candidate WITH displayName + rr when the user has published stats,
    ///  - a `.directory` candidate with just uid + handle (rr nil) when resolved but unranked,
    ///  - nil when the handle is malformed or unclaimed (→ the sheet's "no such username" caption).
    /// Guest → nil. Pure lookup; the sheet owns cancellation (latest-query-wins).
    func lookupChallengeCandidate(handle raw: String) async -> DuelOpponentCandidate? {
        guard !isGuest, currentUserId?.isEmpty == false else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let stripped = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        guard let handleKey = try? DataManager.normalizeAndValidateUsername(stripped) else { return nil }
        guard let uid = try? await firestoreService.lookupUid(forHandleKey: handleKey), !uid.isEmpty else {
            return nil
        }
        // UGC-1b (chokepoint 6): a blocked user is fully hidden from @handle search —
        // resolve to nil so the sheet shows "not found", disclosing nothing.
        guard !isBlocked(uid) else { return nil }
        // leaderboard/{uid} is world-readable (D3); `fetchMyLeaderboardEntry` reads that one doc by
        // uid — reused here for an arbitrary uid (not just "my" row). Absent/undecodable → unranked.
        if let row = try? await firestoreService.fetchMyLeaderboardEntry(userId: uid) {
            let uname = row.username.isEmpty ? handleKey : row.username
            return DuelOpponentCandidate(uid: uid, username: uname, displayName: row.displayName,
                                         source: .directory, rr: row.rr)
        }
        return DuelOpponentCandidate(uid: uid, username: handleKey, displayName: "",
                                     source: .directory, rr: nil)
    }

    // MARK: - Concurrent duel caps (D2.6)

    /// Slot usage for a league from an ALREADY post-lifecycle duel list (lazy expiry/resolution
    /// already applied — see D3, so a duel that ended yesterday never occupies a slot).
    /// `includeOutgoingPending: true` for starting paths (send/rematch/queue); `false` for the
    /// accept path. Counts my actives in the league, plus (when included) my OWN outgoing
    /// pendings; incoming pendings never count against me. Pure/local — guests never reach it.
    private func duelSlotUsage(in duels: [DuelDTO], league: Int, myUid: String,
                               includeOutgoingPending: Bool) -> Int {
        var usage = 0
        for duel in duels where duel.league == league {
            if duel.statusEnum == .active {
                usage += 1
            } else if includeOutgoingPending && duel.statusEnum == .pending && duel.challengerUid == myUid {
                usage += 1
            }
        }
        return usage
    }

    /// Per-league starting-path slot usage for the challenge/matchmaking pickers, from ONE
    /// post-lifecycle fetch. ALWAYS zero-filled for every `DuelConstants.leagues` entry, so
    /// callers never need `?? 0`. Guests get an all-zero map (they cannot reach the pickers).
    func duelSlotUsageByLeague() async -> [Int: Int] {
        var result: [Int: Int] = [:]
        for league in DuelConstants.leagues { result[league] = 0 }
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return result }
        let mine = await loadMyDuels()
        for league in DuelConstants.leagues {
            result[league] = duelSlotUsage(in: mine, league: league, myUid: me, includeOutgoingPending: true)
        }
        return result
    }

    /// Sends a direct challenge to a friend/guild-mate. Throws `DuelError`.
    func sendChallenge(to opponent: DuelOpponentCandidate, league: Int, rematchOfDuelId: String? = nil) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw DuelError.notAuthorized }
        guard DuelConstants.leagues.contains(league) else { throw DuelError.invalidLeague }
        guard opponent.uid != me, !opponent.uid.isEmpty else { throw DuelError.notAuthorized }

        // Duplicate check (decision 5): one PENDING challenge per (same pair, same league).
        // TODO (scale): if duel volume grows large, replace this fetch-and-scan with a
        // queryable pending index or lock doc — fine at current volumes.
        let mine = (try? await firestoreService.fetchMyDuels(uid: me)) ?? []
        let pair = Set([me, opponent.uid])
        let isDuplicate = mine.contains {
            $0.statusEnum == .pending && $0.league == league && Set($0.participantUids) == pair
        }
        if isDuplicate { throw DuelError.duplicateChallenge }

        // D2.6: per-league concurrent cap (starting path). Reuses the duplicate check's fetch;
        // `mine` is post-lifecycle in practice (loadMyDuels runs pervasively before any send —
        // Battle/Home/Arena all funnel through it). active + my outgoing pendings.
        if duelSlotUsage(in: mine, league: league, myUid: me, includeOutgoingPending: true)
            >= DuelConstants.maxConcurrentDuels(league: league) {
            throw DuelError.leagueAtCapacity(league: league)
        }

        // My identity via the robust path used by publishMyStats / friend requests
        // (the Codable account/info decode fails for older accounts).
        let identity: (username: String, displayName: String, createdAt: Date?)
        do {
            identity = try await fetchMyFriendIdentity(userId: me)
        } catch {
            throw DuelError.network((error as? FriendError)?.errorDescription ?? "Couldn't load your profile.")
        }

        let duel = DuelDTO(
            challengerUid: me,
            opponentUid: opponent.uid,
            challengerUsername: identity.username,
            challengerDisplayName: identity.displayName,
            opponentUsername: opponent.username,
            opponentDisplayName: opponent.displayName,
            league: league,
            respondBy: Date().addingTimeInterval(DuelConstants.responseWindow),
            rematchOfDuelId: rematchOfDuelId
        )
        do {
            _ = try await firestoreService.createDuel(duel)
        } catch {
            // UGC-1a: a permission-denied on a well-formed challenge create is treated
            // as a block — the isChallengeCreate() rule's blockedEither() guard is the
            // only deny path a valid challenge hits. The user-facing message is
            // deliberately soft because residual causes (expired auth, future rule
            // changes) share this error code; we do not disclose block state (D3).
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                throw DuelError.blocked
            }
            throw DuelError.network(error.localizedDescription)
        }
    }

    /// One-line RR-claim messages produced by the most recent `loadMyDuels()` claim
    /// pass (reset each load). BattleViewModel reads these after load to surface a toast.
    private(set) var recentDuelClaims: [String] = []

    /// Loads my duels (newest first) with the full duel lifecycle. This is the **duel
    /// synchronization entry point** — score push, lazy expiry, lazy resolution, RR claim,
    /// recap enqueue, and badge refresh — NOT a plain fetch; every duel surface (Home,
    /// Battle, Arena) funnels through it. Empty for guests.
    func loadMyDuels() async -> [DuelDTO] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else {
            await MainActor.run { DuelUIState.shared.reset() }
            return []
        }
        recentDuelClaims = []

        // Push my latest active-duel scores first, so the read below reflects them.
        await updateMyDuelScores()

        var duels = (try? await firestoreService.fetchMyDuels(uid: me)) ?? []
        let now = Date()

        // Pass 1: lazy expiry (D1a) + lazy resolution (D1b).
        for i in duels.indices {
            if duels[i].isExpiredNow {
                if let id = duels[i].id {
                    Task { try? await firestoreService.expireDuel(duelId: id) } // fire-and-forget
                }
                duels[i].status = DuelStatus.expired.rawValue
                continue
            }

            // An active duel past endAt resolves on first load. Winner is from the FROZEN
            // scores; deltas are deterministic (FNV-1a(duelId)-seeded) so every device
            // computes identical values — a resolve race has no visible effect.
            if duels[i].statusEnum == .active, let endAt = duels[i].endAt, now > endAt, let id = duels[i].id {
                let winner = DuelDTO.scoreWinner(challengerScore: duels[i].challengerScore,
                                                 opponentScore: duels[i].opponentScore)
                let deltas = DuelDTO.resolveDeltas(duelId: id, league: duels[i].league, winner: winner)
                let winnerUid: String?
                switch winner {
                case .challenger: winnerUid = duels[i].challengerUid
                case .opponent:   winnerUid = duels[i].opponentUid
                case .draw:       winnerUid = nil
                }
                // Permission-denied ⇒ someone else resolved first with IDENTICAL deltas;
                // reflect locally regardless and fall through to the claim below.
                try? await firestoreService.resolveDuel(duelId: id, winnerUid: winnerUid,
                                                        challengerDelta: deltas.challenger,
                                                        opponentDelta: deltas.opponent)
                duels[i].status = DuelStatus.resolved.rawValue
                duels[i].winnerUid = winnerUid
                duels[i].challengerRRDelta = deltas.challenger
                duels[i].opponentRRDelta = deltas.opponent
            }
        }

        // Pass 2: RR claim — apply my delta exactly once per resolved/forfeited duel whose
        // MY applied flag is false. Flag-first: if the flag write fails (already applied /
        // raced by another device), do NOT apply RR. All claims persist in one save.
        var progress: UserProgress? = nil
        for i in duels.indices {
            let duel = duels[i]
            guard let id = duel.id,
                  duel.statusEnum == .resolved || duel.statusEnum == .forfeited,
                  !duel.rrApplied(for: me),
                  duel.myRRDelta(me) != nil else { continue }

            let iAmChallenger = duel.isChallenger(me)
            do {
                try await firestoreService.markDuelRRApplied(duelId: id, isChallenger: iAmChallenger)
            } catch {
                continue // flag already true elsewhere — skip, never double-apply RR
            }
            if progress == nil { progress = try? await getUserProgress() }
            guard let p = progress else { continue }
            let preRR = p.rr
            let result = recordDuelOutcome(duel, on: p, me: me)
            let postRR = p.rr
            if !result.toast.isEmpty { recentDuelClaims.append(result.toast) }
            if result.genuineWin {
                emitFeedEvent(type: "duel_win", value: id) // create-only, deterministic id, swallowed
            }
            // D1c: queue an end-of-duel recap (presents from the Battle tab).
            let myDays = iAmChallenger ? duel.resolvedChallengerDayScores : duel.resolvedOpponentDayScores
            let theirDays = iAmChallenger ? duel.resolvedOpponentDayScores : duel.resolvedChallengerDayScores
            let summary = DuelResolutionSummary(
                duelId: id, opponentLabel: duel.opponentLabel(of: me), outcome: result.outcome,
                rrDelta: duel.myRRDelta(me) ?? 0, preRR: preRR, postRR: postRR,
                myScore: duel.myScore(me), theirScore: duel.theirScore(me), league: duel.league,
                myDayScores: myDays, theirDayScores: theirDays
            )
            await MainActor.run { DuelUIState.shared.enqueueResolution(summary) }
            if iAmChallenger { duels[i].challengerRRApplied = true } else { duels[i].opponentRRApplied = true }
        }
        // One save through the existing funnel (uploads + publishes) for all claims.
        if progress != nil { try? await saveUserProgress() }

        // D2: Battle-load sweep — reap an orphaned own queue ticket (killed app / stale).
        // Skipped while actively queue-polling (the live ticket must survive). A claimed
        // ticket ⇒ its duel is already in `duels` above; an unclaimed one is a stale orphan.
        if !isQueuePolling, let ticket = try? await firestoreService.fetchMyDuelTicket(uid: me), ticket.id != nil {
            try? await firestoreService.deleteDuelTicket(uid: me)
        }

        // D1c: refresh the cross-tab badge state (active count + unseen changes).
        let activeCount = duels.filter { $0.statusEnum == .active }.count
        let unseen = DuelSeenStore().hasUnseenChanges(in: duels, myUid: me)
        await MainActor.run {
            DuelUIState.shared.activeDuelCount = activeCount
            DuelUIState.shared.hasUnseenChanges = unseen
        }

        // UGC-1b (chokepoint 11, D2): multi-device-staleness belt — hide ONLY pending duels
        // whose counterpart is blocked. Active/resolved/forfeited/expired duels ALWAYS run to
        // completion and are never filtered (block-time cleanup + rules already prevent the
        // normal pending case). The explicit `.pending` guard ensures nothing else is dropped;
        // this runs AFTER the RR-claim/badge passes above, which see the full list.
        return duels.filter { duel in
            guard duel.statusEnum == .pending else { return true }
            let counterpart = duel.isChallenger(me) ? duel.opponentUid : duel.challengerUid
            return !isBlocked(counterpart)
        }
    }

    /// Marks duels seen (UserDefaults snapshot) and refreshes the badge unseen flag/count.
    /// `isFullList: true` when `duels` is a complete loadMyDuels result (enables pruning).
    /// Guest/no-uid → no-op. Also a no-op when `isFullList && duels.isEmpty` (a swallowed
    /// fetch failure must never wipe snapshots or zero the badge — the guest path's reset()
    /// handles the genuine signed-out case).
    func markDuelsSeen(_ duels: [DuelDTO], isFullList: Bool) async {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return }
        if isFullList && duels.isEmpty { return }

        let store = DuelSeenStore()
        if isFullList {
            store.markSeen(duels, myUid: me)                       // full replace + prune
        } else {
            for duel in duels { store.markSeen(duel, myUid: me) }  // single-merge upserts
        }
        let unseen = store.hasUnseenChanges(in: duels, myUid: me)
        await MainActor.run {
            DuelUIState.shared.hasUnseenChanges = unseen
            if isFullList {
                DuelUIState.shared.activeDuelCount = duels.filter { $0.statusEnum == .active }.count
            }
        }
    }

    // MARK: - Matchmaking (D2)

    /// True while the queue flow is actively polling. The Battle-load sweep in `loadMyDuels()`
    /// checks it so a mid-poll `loadMyDuels()` (which `pollQueue` itself calls on a match) never
    /// deletes the live ticket. `pollQueue` sets it true on entry and ALWAYS resets it via
    /// `defer`, so a throw or task cancellation can never leave the sweep disabled.
    private var isQueuePolling = false

    /// Enqueues me for a league. Guest-guarded. Stamps identity from my profile and rr from
    /// local UserProgress. Throws `DuelError`.
    func joinQueue(league: Int) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw DuelError.notAuthorized }
        guard DuelConstants.leagues.contains(league) else { throw DuelError.invalidLeague }
        // D2.6: starting-path cap (active + my outgoing pendings) from a fresh post-lifecycle list.
        let mine = await loadMyDuels()
        if duelSlotUsage(in: mine, league: league, myUid: me, includeOutgoingPending: true)
            >= DuelConstants.maxConcurrentDuels(league: league) {
            throw DuelError.leagueAtCapacity(league: league)
        }
        try await enqueueTicket(league: league, myUid: me)
    }

    /// Delete-then-create my queue ticket: a best-effort delete of my own ticket, then a fresh
    /// create. A plain overwrite (setData over an existing doc) is evaluated as an UPDATE, which
    /// the ticket rules permit only for the expiresAt keep-alive and the claim — so we always
    /// delete first. Non-atomic by design (own doc; worst case "not queued"). Reused by enqueue,
    /// the keep-alive re-stamp, and the 1a recovery.
    private func enqueueTicket(league: Int, myUid: String) async throws {
        let identity: (username: String, displayName: String, createdAt: Date?)
        do {
            identity = try await fetchMyFriendIdentity(userId: myUid)
        } catch {
            throw DuelError.network((error as? FriendError)?.errorDescription ?? "Couldn't load your profile.")
        }
        let rr = (try? await getUserProgress())?.rr ?? Rank.startingRR
        let ticket = DuelQueueTicketDTO(
            id: nil, uid: myUid,
            username: identity.username, displayName: identity.displayName,
            rr: rr, league: league,
            createdAt: nil,
            expiresAt: Date().addingTimeInterval(DuelConstants.queueTicketTTL),
            claimedBy: "", claimedAt: nil, matchedDuelId: nil
        )
        try? await firestoreService.deleteDuelTicket(uid: myUid)
        do {
            try await firestoreService.enqueueDuelTicket(ticket)
        } catch {
            throw DuelError.network(error.localizedDescription)
        }
    }

    /// One poll iteration per the pairing protocol. Returns the matched DuelDTO when a match
    /// completed (either side), else nil. Guest-guarded.
    func pollQueue(league: Int, elapsed: TimeInterval) async throws -> DuelDTO? {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return nil }
        isQueuePolling = true
        defer { isQueuePolling = false }

        // Step 1: check my own ticket (waiting-side match / keep-alive / 1a recovery).
        if let matched = await checkMyTicket(me: me, league: league) { return matched }

        // Steps 2 + 3: search compatible tickets and claim the best one. May throw
        // DuelError.leagueAtCapacity (D2.6/D6) → the sheet stops polling and surfaces it.
        return try await searchAndClaim(me: me, league: league, elapsed: elapsed)
    }

    /// Protocol step 1: inspect `duelQueue/{me}`.
    ///  - claimed  → matched as the WAITING side: pull the new duel, clean my ticket, surface it.
    ///  - missing  → step 1a recovery (matched-and-cleaned / swept): surface a fresh match or re-enqueue.
    ///  - expired  → keep-alive re-stamp (delete-then-create) so a long wait survives.
    private func checkMyTicket(me: String, league: Int) async -> DuelDTO? {
        guard let ticket = try? await firestoreService.fetchMyDuelTicket(uid: me) else {
            // 1a: my ticket is gone. A genuine match during active polling always leaves my
            // ticket CLAIMED (handled above or via the alreadyMatched path), so the only
            // "already matched" signal here is a just-created matchmade duel — distinguished by
            // having ~full time remaining. Otherwise I was swept while unclaimed → re-enqueue.
            let duels = await loadMyDuels()
            let now = Date()
            if let m = duels.first(where: { d in
                guard d.isMatchmade, d.statusEnum == .active, d.participantUids.contains(me),
                      let endAt = d.endAt else { return false }
                return endAt.timeIntervalSince(now) > Double(d.league) * DuelConstants.secondsPerDay - 120
            }) {
                return m
            }
            try? await enqueueTicket(league: league, myUid: me)   // stay queued
            return nil
        }

        if ticket.isClaimed {
            // Matched as the waiting side: the new duel arrives via the participantUids query.
            let duels = await loadMyDuels()
            try? await firestoreService.deleteDuelTicket(uid: me)  // clean my own ticket
            return duels.first { $0.id == ticket.matchedDuelId }
        }

        if ticket.isExpiredNow {
            // Keep-alive: re-stamp a fresh expiresAt (delete-then-create reuses the enqueue path
            // and needs no extra service method; the rules also permit an in-place expiresAt
            // update, which this simply does not exercise).
            try? await enqueueTicket(league: ticket.league, myUid: me)
        }
        return nil
    }

    /// Protocol steps 2 + 3: search compatible tickets in the current RR band and claim the
    /// best one (closest rr, then oldest). Deterministic — no randomness anywhere.
    private func searchAndClaim(me: String, league: Int, elapsed: TimeInterval) async throws -> DuelDTO? {
        let myRR = (try? await getUserProgress())?.rr ?? Rank.startingRR
        let band = DuelConstants.queueBand(forElapsed: elapsed)
        let candidates = (try? await firestoreService.fetchQueueCandidates(
            league: league, rrLo: myRR - band, rrHi: myRR + band,
            limit: DuelConstants.queueCandidateLimit)) ?? []

        // Filter out myself + expired tickets; lazily sweep expired ones (fire-and-forget,
        // rule-gated). Mirrors loadMyDuels' fire-and-forget expiry writes.
        var viable: [DuelQueueTicketDTO] = []
        for c in candidates {
            if c.uid == me { continue }
            if c.isExpiredNow {
                let cid = c.uid
                Task { try? await firestoreService.deleteDuelTicket(uid: cid) }
                continue
            }
            viable.append(c)
        }
        // Deterministic preference: closest rr, ties broken by oldest (createdAt asc).
        viable.sort { a, b in
            let da = abs(a.rr - myRR), db = abs(b.rr - myRR)
            if da != db { return da < db }
            return (a.createdAt ?? Date.distantFuture) < (b.createdAt ?? Date.distantFuture)
        }
        guard !viable.isEmpty else { return nil }

        // D2.6 (D6): re-check MY cap from a fresh post-lifecycle list immediately before the claim
        // transaction — a challenge accepted against me mid-queue may have filled my last slot.
        // Never from the poll loop's held state (can be a full interval stale). isQueuePolling is
        // true here, so this loadMyDuels does NOT sweep my live ticket.
        let mineAtClaim = await loadMyDuels()
        if duelSlotUsage(in: mineAtClaim, league: league, myUid: me, includeOutgoingPending: true)
            >= DuelConstants.maxConcurrentDuels(league: league) {
            throw DuelError.leagueAtCapacity(league: league)
        }

        // My identity snapshot for the matchmade duel (theirs comes FROM THE TICKET — zero
        // cross-user private reads). Best-effort so a missing username never blocks a match.
        let myIdentity = try? await fetchMyFriendIdentity(userId: me)
        let myUsername = myIdentity?.username ?? ""
        let myDisplayName = myIdentity?.displayName ?? (authService.currentUserDisplayName ?? "")

        for candidate in viable {
            // Born active, challenger == me (doc author preserves index-0 = challenger = creator).
            var duel = DuelDTO(
                challengerUid: me, opponentUid: candidate.uid,
                challengerUsername: myUsername, challengerDisplayName: myDisplayName,
                opponentUsername: candidate.username, opponentDisplayName: candidate.displayName,
                league: league, respondBy: Date()   // respondBy meaningless for matchmade
            )
            duel.status = DuelStatus.active.rawValue
            duel.matchmade = true
            duel.endAt = Date().addingTimeInterval(Double(league) * DuelConstants.secondsPerDay)

            do {
                let duelId = try await firestoreService.claimTicketAndCreateDuel(
                    candidate: candidate, myTicketUid: me, duel: duel)
                // Matched as the claiming side: loadMyDuels pushes my day-1 score onto the new
                // duel via the established funnel and refreshes badge state.
                let duels = await loadMyDuels()
                return duels.first { $0.id == duelId }
            } catch DuelError.candidateUnavailable {
                continue   // race lost on this ticket — try the next candidate
            } catch DuelError.alreadyMatched {
                // Someone matched me while I searched — my ticket is now claimed. Discover it.
                return await checkMyTicket(me: me, league: league)
            } catch {
                continue   // transient — try the next candidate / keep polling
            }
        }
        return nil   // nothing claimed — keep polling (band widens next iteration)
    }

    /// Cancels my ticket (sheet dismiss / cancel button). Never throws to the UI.
    func leaveQueue() async {
        isQueuePolling = false
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return }
        try? await firestoreService.deleteDuelTicket(uid: me)
    }

    // MARK: - Global Leaderboard (D3)

    /// LB-PAGE-1: one server-cursor page of a board for the given metric/league. Metric/league
    /// select the orderBy field (RR ignores league). Returns the (blocked-filtered) rows, the RAW
    /// fetched count (BEFORE the UGC-1b filter — the VM keys exhaustion on this), and the next-page
    /// cursor. Guest → ([], 0, nil); a failed fetch → ([], 0, nil).
    func fetchGlobalLeaderboardPage(metric: LeaderboardMetric, league: Int, after: LeaderboardCursor?) async -> (rows: [GlobalLeaderboardDTO], fetchedCount: Int, nextCursor: LeaderboardCursor?) {
        guard !isGuest else { return ([], 0, nil) }
        let field = LeaderboardMetric.orderField(metric: metric, league: league)
        let fetched = (try? await firestoreService.fetchLeaderboardPage(
            orderField: field, limit: DuelConstants.leaderboardPageLength, after: after)) ?? []
        // The next cursor is derived from the RAW (pre-filter) last document's orderField value +
        // uid — NEVER from the filtered `rows` below, whose last element may have been
        // blocked-filtered away (deriving from filtered rows would skip or repeat records at the
        // page boundary). nil when nothing was fetched (empty / exhausted). Cursor math lives here,
        // immune to filtering — never in the VM.
        let nextCursor: LeaderboardCursor? = fetched.last.flatMap { last -> LeaderboardCursor? in
            guard let uid = last.id else { return nil }
            let value: Int
            switch metric {
            case .rr: value = last.rr
            case .wins: value = last.wins(league: league)
            case .streak: value = last.streak(league: league)
            }
            return LeaderboardCursor(value: value, uid: uid)
        }
        // UGC-1b (chokepoint 7): hide blocked players from the paged board — post-fetch/pre-return.
        // The leaderboard doc id IS the owner uid, so filter on `id`.
        let rows = fetched.filter { !isBlocked($0.id ?? "") }
        return (rows, fetched.count, nextCursor)
    }

    /// My own leaderboard row + my standing on the given board via the count aggregation. Fail-soft:
    /// a failed position is nil (footer hides the position chip, never the footer). Guest → (nil, nil).
    func fetchMyLeaderboardRow(metric: LeaderboardMetric, league: Int) async -> (entry: GlobalLeaderboardDTO?, position: Int?) {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return (nil, nil) }
        guard let entry = try? await firestoreService.fetchMyLeaderboardEntry(userId: userId) else { return (nil, nil) }
        let field = LeaderboardMetric.orderField(metric: metric, league: league)
        let myValue: Int
        switch metric {
        case .rr: myValue = entry.rr
        case .wins: myValue = entry.wins(league: league)
        case .streak: myValue = entry.streak(league: league)
        }
        // UGC-1b (chokepoint 8, D3): my own row is never filtered. `position` is a server-side
        // COUNT aggregation that still counts any blocked players ranked above me — an accepted,
        // un-corrected skew (a client fix would require reading the very rows we refuse to read).
        // The standings LIST renumbers naturally via chokepoint 7; only this server-counted
        // position can drift. LB-PAGE-1 generalized it from RR-only to any board via `field`.
        let position = try? await firestoreService.fetchLeaderboardPosition(orderField: field, myValue: myValue)
        return (entry, position)
    }

    // MARK: - Duel scoring & resolution (D1b)

    /// Capped QTE points earned on a local calendar date (0…qteBonusCap). Synchronous
    /// SwiftData fetch (like questsForDate). Primitive for both qteBonus and comeback weighting.
    private func qtePoints(for date: Date) -> Int {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return 0 }
        let key = QTEDay.dateKey(for: date)
        let descriptor = FetchDescriptor<QTEDay>(
            predicate: #Predicate { $0.userId == userId && $0.dateKey == key }
        )
        guard let day = (try? modelContext.fetch(descriptor))?.first else { return 0 }
        return min(Int(DuelConstants.qteBonusCap), day.sparkPoints + day.cleanLogPoints + day.macroGuessPoints)
    }

    /// The QTE bonus term added to a duel day-score (D1d). 0 when no row / guest / no user.
    private func qteBonus(_ date: Date) -> Double { Double(qtePoints(for: date)) }

    // MARK: - QTEs (D1d)

    /// Fetch-or-create a day's QTE row for the current user. Guests never accumulate rows
    /// (they would later sync). Throws `.notAuthenticated` when there is no user.
    private func getOrCreateQTEDay(dateKey: String) throws -> QTEDay {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else {
            throw DataManagerError.notAuthenticated
        }
        let descriptor = FetchDescriptor<QTEDay>(
            predicate: #Predicate { $0.userId == userId && $0.dateKey == dateKey }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first { return existing }
        let day = QTEDay(userId: userId, dateKey: dateKey)
        modelContext.insert(day)
        try modelContext.save()
        return day
    }

    /// Read-only today state for gating the QTE cards (nil for guests / no user).
    func todayQTEState() async -> QTEDay? {
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return nil }
        let key = QTEDay.dateKey(for: Date())
        let descriptor = FetchDescriptor<QTEDay>(
            predicate: #Predicate { $0.userId == userId && $0.dateKey == key }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Records the spark attempt (once/day). No-op if already played. Returns points awarded.
    func awardSparkQTE(points: Int, dateKey: String = QTEDay.dateKey(for: Date())) async -> Int {
        guard !isGuest, let day = try? getOrCreateQTEDay(dateKey: dateKey), !day.sparkPlayed else { return 0 }
        let awarded = max(0, min(DuelConstants.sparkPointsCap, points))
        day.sparkPoints = awarded
        day.sparkPlayed = true
        try? modelContext.save()
        uploadQTEDayAndRescore(day)
        return awarded
    }

    /// Adds one clean-log hit. No-op at cap. Returns the new cleanLogPoints total.
    func awardCleanLogQTE(points: Int, dateKey: String = QTEDay.dateKey(for: Date())) async -> Int {
        guard !isGuest, let day = try? getOrCreateQTEDay(dateKey: dateKey) else { return 0 }
        day.cleanLogPoints = min(DuelConstants.cleanLogPointsCap, day.cleanLogPoints + max(0, points))
        try? modelContext.save()
        uploadQTEDayAndRescore(day)
        return day.cleanLogPoints
    }

    /// Records the macro-guess attempt (once/day). No-op if already played. Returns points awarded.
    func awardMacroGuessQTE(points: Int, dateKey: String = QTEDay.dateKey(for: Date())) async -> Int {
        guard !isGuest, let day = try? getOrCreateQTEDay(dateKey: dateKey), !day.macroGuessPlayed else { return 0 }
        let awarded = max(0, min(DuelConstants.macroGuessPointsCap, points))
        day.macroGuessPoints = awarded
        day.macroGuessPlayed = true
        try? modelContext.save()
        uploadQTEDayAndRescore(day)
        return awarded
    }

    /// Fire-and-forget: READ-MERGE-THEN-WRITE the QTE row, then rescore duels. One Task keeps
    /// the order (merge → upload → rescore); updateMyDuelScores never calls back into the
    /// publish funnel.
    private func uploadQTEDayAndRescore(_ day: QTEDay) {
        // L4/D6: guard on !isGuest — currentUserId is a non-empty "guest" for guest sessions,
        // so the old `currentUserId != ""` check let guest QTE I/O through. Callers already
        // guard !isGuest; this is defense-in-depth consistency.
        guard !isGuest, let userId = currentUserId, !userId.isEmpty else { return }
        let dateKey = day.dateKey
        // M3: uploading the raw local DTO let a stale second device clobber a higher earned
        // total (merge:true can't protect fields the DTO always encodes; max-wins lived only on
        // the read path). Fold any higher remote points into local first, upload the MERGED row,
        // THEN rescore so a merged-higher qteBonus is what lands on the duel docs. A failed
        // pre-fetch degrades to uploading local for this one write — self-heals on the next
        // award or the initial-sync backfill in startFirestoreSync.
        Task {
            if let remote = try? await firestoreService.fetchQTEDay(userId: userId, dateKey: dateKey) {
                applyQTEDayMerge(remote, userId: userId)   // max-wins/OR into local (+ saves)
            }
            let descriptor = FetchDescriptor<QTEDay>(
                predicate: #Predicate { $0.userId == userId && $0.dateKey == dateKey }
            )
            let mergedRow = (try? modelContext.fetch(descriptor))?.first ?? day
            try? await firestoreService.uploadQTEDay(QTEDayDTO(from: mergedRow), userId: userId)
            await updateMyDuelScores()
        }
    }

    /// All QTE rows for the user (initial-sync helper).
    private func fetchAllQTEDaysForSync(userId: String) throws -> [QTEDay] {
        try modelContext.fetch(FetchDescriptor<QTEDay>(predicate: #Predicate { $0.userId == userId }))
    }

    /// Field-wise MAX-WINS merge of a remote QTE doc into local (create when absent). Points are
    /// earn-only (D7); played flags OR — two-device play converges without loss.
    private func applyQTEDayMerge(_ dto: QTEDayDTO, userId: String) {
        let key = dto.dateKey
        let descriptor = FetchDescriptor<QTEDay>(
            predicate: #Predicate { $0.userId == userId && $0.dateKey == key }
        )
        if let local = (try? modelContext.fetch(descriptor))?.first {
            local.sparkPoints = min(DuelConstants.sparkPointsCap, max(local.sparkPoints, dto.sparkPoints))
            local.cleanLogPoints = min(DuelConstants.cleanLogPointsCap, max(local.cleanLogPoints, dto.cleanLogPoints))
            local.macroGuessPoints = min(DuelConstants.macroGuessPointsCap, max(local.macroGuessPoints, dto.macroGuessPoints))
            local.sparkPlayed = local.sparkPlayed || dto.sparkPlayed
            local.macroGuessPlayed = local.macroGuessPlayed || dto.macroGuessPlayed
        } else {
            modelContext.insert(dto.toQTEDay(userId: userId))
        }
        try? modelContext.save()
    }

    /// Quests for a specific date, scoped to the current user.
    private func questsForDate(_ date: Date) async throws -> [DailyQuest] {
        guard let userId = currentUserId, !userId.isEmpty else { return [] }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let descriptor = FetchDescriptor<DailyQuest>(
            predicate: #Predicate { quest in
                quest.userId == userId && quest.date >= startOfDay && quest.date < endOfDay
            }
        )
        return try modelContext.fetch(descriptor)
    }

    /// Graded day-score (0…110) for a local calendar date, per the D1b EXACT SPEC.
    /// Reuses existing per-date machinery (entries/goal-in-effect/quests + NutritionManager).
    /// Memoized by callers (updateMyDuelScores) per start-of-day.
    func dayScore(for date: Date) async -> Double {
        guard let userId = currentUserId, !userId.isEmpty else { return 0 }
        let entries = (try? await fetchEntriesForDate(date)) ?? []

        // The goal IN EFFECT on the date (goals persist until changed), exactly as adherence does.
        let goals = ((try? await fetchAllDailyGoalsForSync(userId: userId)) ?? []).sorted { $0.date > $1.date }
        let dayStart = Calendar.current.startOfDay(for: date)
        let goal = goalInEffect(on: dayStart, calendar: Calendar.current, goalsByRecency: goals)

        // Gate: no goal in effect OR no entries logged → 0 (no free points for silence; avoids /0).
        guard let goal, !entries.isEmpty else { return 0 }

        let totalCalories = nutritionManager.calculateTotalCalories(from: entries)
        let totalProtein = nutritionManager.calculateTotalMacros(from: entries).protein
        let dailyToxin = NutritionManager.dailyToxinScore(from: entries)

        // Calories — up to caloriePoints; over penalized harder than under.
        let diff = totalCalories - goal.calorieTarget
        let caloriePts: Double
        switch diff {
        case (-100)...100:    caloriePts = DuelConstants.caloriePoints           // full
        case 101...200:       caloriePts = DuelConstants.caloriePoints / 2       // slight over
        case (-300)...(-101): caloriePts = DuelConstants.caloriePoints * 2 / 3   // moderate under
        case let d where d > 200: caloriePts = 0                                 // large over
        default:              caloriePts = DuelConstants.caloriePoints / 3       // large under (< -300)
        }

        // Protein — up to proteinPoints (guard target ≤ 0 → full).
        let proteinPts = goal.proteinTarget <= 0
            ? DuelConstants.proteinPoints
            : DuelConstants.proteinPoints * min(1.0, totalProtein / goal.proteinTarget)

        // Purity — up to purityPoints; LOWER toxin is better (linear to 0 at double the target).
        let purityPts: Double
        if goal.purityTarget <= 0 {
            purityPts = dailyToxin == 0 ? DuelConstants.purityPoints : 0
        } else if dailyToxin <= goal.purityTarget {
            purityPts = DuelConstants.purityPoints
        } else {
            let target = Double(goal.purityTarget)
            purityPts = DuelConstants.purityPoints * max(0, (2 * target - Double(dailyToxin)) / target)
        }

        // Quests — up to questPoints; 0 if no quests exist that day.
        let quests = (try? await questsForDate(date)) ?? []
        let questPts: Double = quests.isEmpty ? 0 :
            DuelConstants.questPoints * (Double(quests.filter { $0.isCompleted }.count) / Double(quests.count))

        let raw = caloriePts + proteinPts + purityPts + questPts + qteBonus(date)
        let clamped = min(DuelConstants.maxDayScore, max(0, raw))
        return (clamped * 10).rounded() / 10 // 1 decimal place
    }

    /// Recompute and push MY side of every ACTIVE duel. Memoizes dayScore per start-of-day so
    /// overlapping duel-days are computed ONCE. Writes ONLY duel docs — NEVER saveUserProgress /
    /// publishMyStats (it is called FROM that funnel; a call back in would loop).
    func updateMyDuelScores() async {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return }
        let duels = (try? await firestoreService.fetchMyDuels(uid: me)) ?? []
        let active = duels.filter { $0.statusEnum == .active }
        guard !active.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()
        var cache: [Date: Double] = [:]  // start-of-day → dayScore (compute each date once)
        var qteCache: [Date: Int] = [:]  // start-of-day → capped QTE points (comeback weighting)

        for duel in active {
            guard let id = duel.id, let acceptedAt = duel.acceptedAt else { continue }
            let iAmChallenger = duel.isChallenger(me)
            let day1Start = calendar.startOfDay(for: acceptedAt)

            // Duel-days 1…currentDuelDay: calendar days from acceptedAt (decision 1), never
            // future, never past endAt.
            var dayScores: [Double] = []
            var dayStarts: [Date] = []
            for dayIndex in 0..<duel.league {
                guard let dayStart = calendar.date(byAdding: .day, value: dayIndex, to: day1Start) else { break }
                if dayStart > now { break }                              // future duel-day — stop
                if let endAt = duel.endAt, dayStart >= endAt { break }   // past the window — stop
                if let cached = cache[dayStart] {
                    dayScores.append(cached)
                } else {
                    let score = await dayScore(for: dayStart)
                    cache[dayStart] = score
                    dayScores.append(score)
                }
                dayStarts.append(dayStart)
            }

            // D1d comeback weighting (D6): the TRAILING side's QTE points are worth
            // ×comebackMultiplier. Strict < on the fetched-doc rounded totals — tied/0–0 is NOT
            // trailing. Applied to THIS duel's copy only; the base memoized dayScores are never
            // mutated. Re-clamped per day to maxDayScore, so totals stay ≤ league×110 (no
            // score-rule change). qteBonus already folded the BASE QTE into dayScore; here we add
            // only the incremental boost.
            let iAmTrailing = Int((duel.myScore(me) * 10).rounded()) < Int((duel.theirScore(me) * 10).rounded())
            if iAmTrailing {
                for i in dayScores.indices {
                    let base: Int
                    if let cached = qteCache[dayStarts[i]] {
                        base = cached
                    } else {
                        let p = qtePoints(for: dayStarts[i])
                        qteCache[dayStarts[i]] = p
                        base = p
                    }
                    guard base > 0 else { continue }
                    let boosted = min(Int(DuelConstants.qteBonusCap),
                                      Int((Double(base) * DuelConstants.comebackMultiplier).rounded()))
                    let raised = min(DuelConstants.maxDayScore, dayScores[i] + Double(boosted - base))
                    dayScores[i] = (raised * 10).rounded() / 10
                }
            }

            // Round the total to 1 decimal so equal-rounded totals become the IDENTICAL Double.
            // The resolve rule compares raw scores; this keeps it in lockstep with the client's
            // rounded-int winner determination (no raw-Double disagreement → no stuck draw).
            let total = (dayScores.reduce(0, +) * 10).rounded() / 10

            // Skip no-op writes (dayScores identical ⇒ same total; avoids write spam).
            let current = iAmChallenger ? duel.resolvedChallengerDayScores : duel.resolvedOpponentDayScores
            if current == dayScores { continue }

            // Swallow permission-denied (duel ended / froze between fetch and write).
            try? await firestoreService.updateDuelScore(duelId: id, isChallenger: iAmChallenger,
                                                        score: total, dayScores: dayScores)
        }
    }

    /// Applies MY claimed outcome to `progress` (RR floored at 0 + W/L/draw + win-streak).
    /// Returns the claim toast + whether it was a genuine (non-forfeit) win for feed emission.
    private func recordDuelOutcome(_ duel: DuelDTO, on progress: UserProgress, me: String) -> (toast: String, genuineWin: Bool, outcome: DuelResolutionSummary.Outcome) {
        guard let myDelta = duel.myRRDelta(me) else { return ("", false, .draw) }
        progress.rr = max(0, progress.rr + myDelta)

        let isForfeit = duel.forfeitedBy != nil
        let label: String
        let outcome: DuelResolutionSummary.Outcome
        var genuineWin = false
        // D3: each branch applies the IDENTICAL wins/currentWinStreak transition to the
        // league-keyed counters for this duel's league (D4 — mirror, don't reinterpret).
        if isForfeit {
            if duel.forfeitedBy == me {
                progress.duelLosses += 1
                progress.currentWinStreak = 0
                resetLeagueStreak(progress, duel.league)
                label = "FORFEIT"; outcome = .forfeitLoss
            } else {
                progress.duelWins += 1
                progress.currentWinStreak += 1
                progress.bestWinStreak = max(progress.bestWinStreak, progress.currentWinStreak)
                applyLeagueWin(progress, duel.league)
                label = "WON"; outcome = .forfeitWin // unearned; NOT a genuine win → no feed
            }
        } else if duel.winnerUid == nil {
            progress.duelDraws += 1        // draw — win streak unchanged (per-league unchanged too)
            label = "DREW"; outcome = .draw
        } else if duel.winnerUid == me {
            progress.duelWins += 1
            progress.currentWinStreak += 1
            progress.bestWinStreak = max(progress.bestWinStreak, progress.currentWinStreak)
            applyLeagueWin(progress, duel.league)
            label = "WON"; outcome = .won; genuineWin = true
        } else {
            progress.duelLosses += 1
            progress.currentWinStreak = 0
            resetLeagueStreak(progress, duel.league)
            label = "LOST"; outcome = .lost
        }

        let sign = myDelta >= 0 ? "+" : ""
        return ("Duel vs \(duel.opponentLabel(of: me)): \(label) \(sign)\(myDelta) RR", genuineWin, outcome)
    }

    /// D3: a league win — wins+1 and streak+1 for the league-keyed counters (mirrors the global
    /// win/currentWinStreak transition). Unknown league is a no-op (league is create-validated).
    private func applyLeagueWin(_ progress: UserProgress, _ league: Int) {
        switch league {
        case 1: progress.duelWins1 += 1; progress.winStreak1 += 1
        case 3: progress.duelWins3 += 1; progress.winStreak3 += 1
        case 5: progress.duelWins5 += 1; progress.winStreak5 += 1
        default: break
        }
    }

    /// D3: a league loss/forfeit-loss — reset the league-keyed streak (mirrors the global
    /// currentWinStreak = 0; there is no per-league loss counter).
    private func resetLeagueStreak(_ progress: UserProgress, _ league: Int) {
        switch league {
        case 1: progress.winStreak1 = 0
        case 3: progress.winStreak3 = 0
        case 5: progress.winStreak5 = 0
        default: break
        }
    }

    /// Forfeit an active duel. Deltas are deterministic; my RR/record applies via the same
    /// claim path on the next load (uniform). Throws `DuelError`.
    func forfeitDuel(_ duel: DuelDTO) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw DuelError.notAuthorized }
        guard let id = duel.id else { throw DuelError.notAuthorized }
        guard duel.participantUids.contains(me) else { throw DuelError.notAuthorized }
        guard duel.statusEnum == .active else { throw DuelError.alreadyResolved }

        let deltas = DuelDTO.forfeitDeltas(duelId: id, league: duel.league, forfeiterIsChallenger: duel.isChallenger(me))
        do {
            try await firestoreService.forfeitDuel(duelId: id, forfeiterUid: me,
                                                   challengerDelta: deltas.challenger,
                                                   opponentDelta: deltas.opponent)
        } catch {
            throw DuelError.network(error.localizedDescription)
        }
    }

    /// Rematch a resolved/forfeited duel within the 24h window — a fresh challenge to the same
    /// opponent + league via `sendChallenge` (all D1a checks apply), with `rematchOfDuelId` set.
    func rematch(_ duel: DuelDTO) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw DuelError.notAuthorized }
        guard let originalId = duel.id, let resolvedAt = duel.resolvedAt else { throw DuelError.rematchExpired }
        guard Date() < resolvedAt.addingTimeInterval(DuelConstants.rematchWindow) else { throw DuelError.rematchExpired }

        let opponentUid = duel.opponentUid(of: me)
        let opponentIsChallenger = duel.challengerUid == opponentUid
        let candidate = DuelOpponentCandidate(
            uid: opponentUid,
            username: opponentIsChallenger ? duel.challengerUsername : duel.opponentUsername,
            displayName: opponentIsChallenger ? duel.challengerDisplayName : duel.opponentDisplayName,
            source: .friend, // display-only for the picker; irrelevant on the direct rematch path
            rr: nil
        )
        try await sendChallenge(to: candidate, league: duel.league, rematchOfDuelId: originalId)
    }

    /// Opponent accepts a pending challenge → active, with a fixed window
    /// `endAt = now + league days`. Throws `DuelError`.
    func acceptChallenge(_ duel: DuelDTO) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw DuelError.notAuthorized }
        guard let id = duel.id else { throw DuelError.notAuthorized }
        guard !duel.isExpiredNow else { throw DuelError.expired }
        guard duel.statusEnum == .pending, duel.opponentUid == me else { throw DuelError.notAuthorized }

        // D2.6: accept-path cap — my ACTIVES in this league only (accepting is the moment it
        // becomes active). Fresh post-lifecycle list so an ended duel already freed its slot.
        let mine = await loadMyDuels()
        if duelSlotUsage(in: mine, league: duel.league, myUid: me, includeOutgoingPending: false)
            >= DuelConstants.maxConcurrentDuels(league: duel.league) {
            throw DuelError.leagueAtCapacity(league: duel.league)
        }

        let endAt = Date().addingTimeInterval(Double(duel.league) * DuelConstants.secondsPerDay)
        do {
            try await firestoreService.acceptDuel(duelId: id, endAt: endAt)
        } catch {
            throw DuelError.network(error.localizedDescription)
        }
    }

    /// Opponent declines a pending challenge. Throws `DuelError`.
    func declineChallenge(_ duel: DuelDTO) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw DuelError.notAuthorized }
        guard let id = duel.id else { throw DuelError.notAuthorized }
        guard duel.statusEnum == .pending, duel.opponentUid == me else { throw DuelError.notAuthorized }
        do {
            try await firestoreService.declineDuel(duelId: id)
        } catch {
            throw DuelError.network(error.localizedDescription)
        }
    }

    /// Challenger cancels their own pending challenge (deletes it). Throws `DuelError`.
    func cancelChallenge(_ duel: DuelDTO) async throws {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { throw DuelError.notAuthorized }
        guard let id = duel.id else { throw DuelError.notAuthorized }
        guard duel.statusEnum == .pending, duel.challengerUid == me else { throw DuelError.notAuthorized }
        do {
            try await firestoreService.cancelDuel(duelId: id)
        } catch {
            throw DuelError.network(error.localizedDescription)
        }
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
        // UGC-1b (chokepoint 10a): belt filter before fan-out. fetchFriends() already drops
        // blocked edges (chokepoint 1), so this is a redundant multi-device-staleness net —
        // kept per the complete inventory.
        let friendUids = friendModels.map { $0.friendUid }.filter { !isBlocked($0) }

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
                group.addTask { [firestoreService, me, item, blocked = DataManager.blockedUids] in
                    var result = item
                    // UGC-1b (chokepoint 10b): drop a blocked user's cheer before computing
                    // count/didCheer/recentCheererNames — their name must not surface on a
                    // mutual friend's event. A captured Set snapshot keeps the task Sendable
                    // (self is never captured here, matching the existing pattern).
                    let cheers = ((try? await firestoreService.fetchCheers(
                        ownerUid: item.friendUid, eventId: item.eventId, limit: 20)) ?? [])
                        .filter { !blocked.contains($0.cheererUid) }
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

    /// Fetches one user's published stats projection for the profile sheet.
    /// Post-B1 (NAV-1a) the read is open to any signed-in user — no longer
    /// friend-gated — so this serves stranger profiles too. nil still means
    /// "not published yet" (and remains the fold for any residual
    /// permission-denied), rendered as "hasn't shared their stats yet." The
    /// `friendUid` label is now historically inaccurate but kept (no-renames rule).
    func fetchPublicStats(friendUid: String) async throws -> PublicStatsDTO? {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return nil }
        return try await firestoreService.fetchPublicStats(friendUid: friendUid)
    }

    /// Fetches every friend's published projection keyed by uid, for the
    /// detailed friends-list rows. Same concurrent friend-gated reads as the
    /// leaderboard; friends without a published projection are simply absent
    /// (their row falls back to identity only). Fetch-on-view, never persisted.
    func fetchFriendStats() async -> [String: PublicStatsDTO] {
        guard !isGuest, let me = currentUserId, !me.isEmpty else { return [:] }

        let friendModels = (try? await fetchFriends()) ?? []
        let uids = friendModels.map { $0.friendUid }

        var statsByUid: [String: PublicStatsDTO] = [:]
        await withTaskGroup(of: (uid: String, stats: PublicStatsDTO?).self) { group in
            for uid in uids {
                group.addTask { [firestoreService] in
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
                    rr: stats.rr,
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
                    rank: Rank.stone.rawValue,
                    rr: nil,
                    weeklyGoalsMet: 0,
                    weeklyAdherence: 0.0,
                    isCurrentUser: false,
                    hasData: false
                )
            }
        }

        // PREVIEW ONLY — two extra demo rows so CLI screenshots show the full
        // gold/silver/bronze podium. Active only under the HB_PREVIEW launch
        // environment; never present in a normal app session.
        if ProcessInfo.processInfo.environment["HB_PREVIEW"] == "leaderboard" {
            entriesByUid["preview-demo-1"] = LeaderboardEntry(
                uid: "preview-demo-1", username: "pixelpete", displayName: "Pixel Pete",
                level: 18, totalXP: 7900, currentStreak: 12, rank: Rank.diamond.rawValue, rr: 1550,
                weeklyGoalsMet: 6, weeklyAdherence: 6.0 / 7.0,
                isCurrentUser: false, hasData: true
            )
            entriesByUid["preview-demo-2"] = LeaderboardEntry(
                uid: "preview-demo-2", username: "ironivy", displayName: "Iron Ivy",
                level: 4, totalXP: 760, currentStreak: 2, rank: Rank.copper.rawValue, rr: 450,
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
        let rank = progress?.rank ?? Rank.stone.rawValue
        let rr = progress?.rr

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
            rr: rr,
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
                    rr: stats.rr,
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
                    rank: Rank.stone.rawValue,
                    rr: nil,
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
    /// RR-derived rank source (RR-0b). nil when the fetched projection predates
    /// RR-0b — the row then falls back to the legacy `rank` string (untier-ed).
    let rr: Int?
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

    /// Tiered rank string ("Copper 2") when `rr` is known; the legacy published
    /// rank string capitalized otherwise. The single rank-render path for the
    /// leaderboard/guild rows — never re-implement the rr/legacy fallback per view.
    var displayRank: String { Rank.displayString(rr: rr, legacyRank: rank) }

    /// Identifiable keys on the uid only.
    var id: String { uid }
}

/// The single shared rank-display formatter (RR-0b). Lives here — not in
/// `Rank.swift` (RR-0a, frozen) — colocated with its primary consumer
/// `LeaderboardEntry.displayRank`; usable from every rank surface app-wide.
extension Rank {
    /// Tiered display ("Copper 2") when `rr` is known; the legacy rank string
    /// capitalized otherwise (may be a retired name like "Bronze" — never re-map,
    /// never invent a tier).
    static func displayString(rr: Int?, legacyRank: String) -> String {
        if let rr { return Rank.rankTier(from: rr).displayName }
        return legacyRank.capitalized
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
    case notAllowed
    case network(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInGuild:   return "You're already in a guild. Leave it before joining another."
        case .notFound:         return "No guild was found for that code."
        case .full:             return "This guild is full."
        case .ownerMustDisband: return "As the owner, you can't leave — disband the guild instead."
        case .codeCollision:    return "Couldn't generate a unique guild code. Please try again."
        case .notAuthorized:    return "You don't have permission to do that."
        case .notAllowed:       return "That name isn't allowed."
        case .network(let m):   return "Couldn't reach the server. Try again. (\(m))"
        }
    }
}

// MARK: - Duel Error (Duels D1a)

/// Errors surfaced by the duel flow, mirroring FriendError/GuildError's user-facing style.
enum DuelError: LocalizedError {
    case duplicateChallenge
    case expired
    case notAuthorized
    case invalidLeague
    case alreadyResolved
    case rematchExpired
    case network(String)
    // D2: matchmaking
    case candidateUnavailable   // a candidate ticket failed in-transaction verification (race)
    case alreadyMatched         // someone matched me first; the incoming match wins
    case notQueued              // no live ticket for me
    // D2.6: concurrent duel caps
    case leagueAtCapacity(league: Int)
    // UGC-1a: challenge create denied by a block (either party blocks the other)
    case blocked

    var errorDescription: String? {
        switch self {
        case .duplicateChallenge:   return "You already have a pending challenge with them in this league."
        case .expired:              return "This challenge is no longer available."
        case .blocked:              return "This player isn't accepting challenges from you right now."
        case .notAuthorized:        return "You can't do that."
        case .invalidLeague:        return "Choose a 1, 3, or 5-day league."
        case .alreadyResolved:      return "This duel is already over."
        case .rematchExpired:       return "The rematch window has closed."
        case .network(let m):       return "Couldn't reach the server. Try again. (\(m))"
        case .candidateUnavailable: return "That match was just taken."
        case .alreadyMatched:       return "You've already been matched."
        case .notQueued:            return "You're not in the queue."
        case .leagueAtCapacity(let league):
            return "You're at the limit for \(league)-day duels — finish one first."
        }
    }
}

// MARK: - Safety constants (UGC-1a)

/// UGC-1a magic-number home. Declared once; referenced everywhere used. The
/// values are mirrored by a comment in firestore.rules (the reports snapshot cap).
enum UGCConstants {
    /// Hard cap on a user's private blocklist (`users/{uid}/account/blocklist`).
    /// The array shape is deliberate at this scale; a `blocks/` subcollection is a
    /// future option only if this cap ever binds (D1).
    static let maxBlocklistSize = 500
    /// Max length of a report's `contentSnapshot` after trim, before write. Mirrored
    /// by the `contentSnapshot.size() <= 1000` check in the reports rules block (D12).
    static let maxReportSnapshotLength = 1000
}

// MARK: - Block Error (UGC-1a)

/// Errors surfaced by the block flow, mirroring FriendError/GuildError's style.
enum BlockError: LocalizedError {
    case notAuthenticated
    case limitReached
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to do that."
        case .limitReached:     return "You've reached the maximum number of blocked users."
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
