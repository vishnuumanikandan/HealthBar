//
//  FirestoreService.swift
//  HealthBar
//
//  Created by Claude on 3/24/26.
//

import Foundation

/// A public entry from the top-level usernames index (uid + claimed handle).
/// Used by the Add Friends user directory. Contains no private account data.
/// `claimedAt` disambiguates when one uid owns multiple handle docs (orphans
/// from earlier claims) — the latest claim is the user's current handle.
struct DirectoryUser {
    let uid: String
    let username: String
    let claimedAt: Date?
}

/// Direction of a `fetchLeaderboardSlice` page relative to a reference RR (C1 — the
/// RR-proximity challenge stream). `.up` pages upward from my RR (rr ascending), `.down`
/// pages downward (rr descending); the client interleaves the two by `|rr − myRR|`.
enum LeaderboardSliceDirection {
    case up
    case down
}

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

    // MARK: - AccountInfo (account/info document)

    /// Writes (creates or overwrites) the account/info document for a user.
    /// Firestore path: users/{userId}/account/info (fixed document ID "info").
    func writeAccountInfo(_ info: AccountInfoDTO, userId: String) async throws

    /// One-time fetch of the account/info document. Returns nil if it doesn't exist yet.
    func fetchAccountInfo(userId: String) async throws -> AccountInfoDTO?

    // MARK: - BadgeProgress (badges collection)

    /// Uploads (creates or overwrites) a badge progress document.
    /// Firestore path: users/{userId}/badges/{badgeId}.
    func uploadBadgeProgress(_ badge: BadgeProgressDTO, userId: String) async throws

    /// Starts a real-time listener for a user's badges collection.
    /// Append-only: callers must never revert isUnlocked from true to false.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForBadges(userId: String, onUpdate: @escaping ([BadgeProgressDTO]) -> Void)

    // MARK: - Username (Friend System Phase 1)

    /// One-time read: returns the canonical username owned by `userId`, or nil if unclaimed.
    /// Reads users/{userId}/account/info and returns its `username` field.
    func fetchUsername(userId: String) async throws -> String?

    /// Non-authoritative availability probe for UI feedback only.
    /// Returns true if no usernames/{handleKey} document exists for the given canonical handle.
    /// The claim transaction remains the sole source of truth; never gate the claim on this result.
    func isUsernameAvailable(_ handleKey: String) async throws -> Bool

    /// Atomically claims `handleKey` for `userId` and writes it into account/info.
    /// Runs inside a single Firestore transaction for uniqueness enforcement.
    func claimUsername(_ handleKey: String, userId: String) async throws

    // MARK: - Username Login Mapping

    /// Resolves a username to its login email via the public loginHandles mapping.
    /// Works pre-auth (rules allow unauthenticated single-document get, no list).
    /// Returns nil when no mapping exists for the handle.
    func lookupLoginEmail(forHandleKey handleKey: String) async throws -> String?

    /// Creates or overwrites the username → login-email mapping used for sign-in.
    /// Firestore path: loginHandles/{handleKey} = { uid, email }.
    func upsertLoginHandle(handleKey: String, uid: String, email: String) async throws

    /// Deletes a username → email mapping if it is owned by `uid` (owner-guarded).
    /// No-op when the mapping is absent or owned by someone else.
    func deleteLoginHandle(handleKey: String, uid: String) async throws

    /// Atomically changes the user's username from `oldHandleKey` to `newHandleKey`.
    /// Runs inside a single Firestore transaction:
    ///   1. Verify old handle is owned by this user.
    ///   2. Verify new handle is unclaimed.
    ///   3. Delete old usernames/{oldHandleKey}.
    ///   4. Create usernames/{newHandleKey}.
    ///   5. Merge-write username + lastUsernameChangeAt into account/info.
    func changeUsername(from oldHandleKey: String, to newHandleKey: String, userId: String) async throws

    // MARK: - Friends (Phase 2)

    /// Resolve a handle to a uid via the public usernames index. Returns nil if unclaimed.
    func lookupUid(forHandleKey handleKey: String) async throws -> String?

    /// Fresh server existence check of my own incoming request from `fromUid`
    /// (users/{meUid}/friendRequests/{fromUid}). Used to block reverse-duplicate sends.
    func incomingRequestExists(meUid: String, fromUid: String) async throws -> Bool

    /// Fresh server existence check of my OUTGOING request to `toUid`
    /// (users/{meUid}/sentRequests/{toUid}). FR-1 send idempotency: a re-send is an UPDATE,
    /// which the request rules deny (`allow update: if false`), so an existing request is
    /// treated as a silent success rather than re-written.
    func outgoingRequestExists(meUid: String, toUid: String) async throws -> Bool

    /// Fresh server existence check of the friend edge users/{meUid}/friends/{friendUid}.
    /// FR-1 accept idempotency: a re-accept would UPDATE the edge (rule-denied), so an
    /// existing edge means the accept already happened — clean up requests, don't re-write.
    func friendExists(meUid: String, friendUid: String) async throws -> Bool

    /// One-time fetch of the entire public usernames index, ordered alphabetically
    /// by handle (= document ID). Powers the Add Friends user directory.
    func fetchAllUsernames() async throws -> [DirectoryUser]

    /// Atomic (WriteBatch): create the incoming request in the recipient's space AND the
    /// sender's own sentRequests mirror. Caller passes its own identity for stamping.
    /// D3b: `fromAvatar*` is the sender's own preset avatar (from its local profile), stamped
    /// into the incoming-request doc only (the sentRequests mirror is untouched — SentRequestDTO
    /// carries no avatar). nil ⇒ the avatar keys are omitted from the write.
    func sendFriendRequest(toUid: String, toUsername: String,
                           fromUid: String, fromUsername: String, fromDisplayName: String,
                           fromAvatarIcon: String?, fromAvatarColor: String?) async throws

    /// Atomic (WriteBatch): create both friend edges, delete the incoming request and the
    /// sender's mirror. `me*` = accepter identity, `from*` = original sender identity (from the request doc).
    /// Also deletes the reverse request pair (users/{fromUid}/friendRequests/{meUid} and
    /// users/{meUid}/sentRequests/{fromUid}) — a no-op when absent — so no pending request
    /// survives becoming friends, even after a simultaneous cross-send.
    /// D3b: the edge in the SENDER's space (friend == me) is stamped with MY avatar (`meAvatar*`,
    /// from my local profile); the edge in MY space (friend == sender) is stamped with the
    /// sender's avatar (`fromAvatar*`, copied from the request snapshot — no profile/public-stats
    /// fetch). Either nil ⇒ that edge's avatar keys are omitted.
    func acceptFriendRequest(fromUid: String, fromUsername: String, fromDisplayName: String,
                             meUid: String, meUsername: String, meDisplayName: String,
                             fromAvatarIcon: String?, fromAvatarColor: String?,
                             meAvatarIcon: String?, meAvatarColor: String?) async throws

    /// Atomic (WriteBatch): delete the incoming request and the sender's mirror.
    func declineFriendRequest(fromUid: String, meUid: String) async throws

    /// Atomic (WriteBatch): delete the sender's mirror and the recipient's incoming request.
    func cancelSentRequest(toUid: String, meUid: String) async throws

    /// Atomic (WriteBatch): delete both friend edges.
    func removeFriend(friendUid: String, meUid: String) async throws

    /// Starts a real-time listener for a user's friends collection.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForFriends(userId: String, onUpdate: @escaping ([FriendDTO]) -> Void)

    /// Starts a real-time listener for a user's incoming friend requests.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForIncomingRequests(userId: String, onUpdate: @escaping ([IncomingRequestDTO]) -> Void)

    /// Starts a real-time listener for a user's outgoing request mirrors.
    /// Same idempotency and MainActor guarantees as listenForFoodEntries.
    func listenForSentRequests(userId: String, onUpdate: @escaping ([SentRequestDTO]) -> Void)

    // MARK: - Public stats / leaderboard (Friend System Phase 3)

    /// Owner publishes their own stats projection. Overwrites users/{userId}/public/stats.
    func publishPublicStats(_ stats: PublicStatsDTO, userId: String) async throws

    /// Read a single friend's published stats. Returns nil if the friend has not
    /// published yet. Authorized by rules only when the caller is in `friendUid`'s
    /// friends list — permission-denied is surfaced as nil, never a crash, so an
    /// unfriended user simply drops off the leaderboard.
    func fetchPublicStats(friendUid: String) async throws -> PublicStatsDTO?

    // MARK: - Activity feed (Friend System Phase 7)

    /// Owner emits a milestone event. Idempotent: the deterministic eventId
    /// (`<type>_<value>`) means a re-emitted milestone collides on the same
    /// document — no duplicate. Authorized for the owner only.
    func publishFeedEvent(_ event: FeedEventDTO, userId: String) async throws

    /// Owner prunes their own events beyond the newest `keep`: queries own
    /// feedEvents ordered by createdAt desc and deletes everything past index
    /// keep-1 (batched). Bounded storage, no TTL infrastructure.
    func pruneFeedEvents(userId: String, keep: Int) async throws

    /// Fetch a friend's recent events (createdAt desc, capped at `limit`).
    /// Friend-gated by rules; permission-denied (unfriended) ⇒ [], consistent
    /// with fetchPublicStats. Undecodable docs are skipped.
    func fetchFeedEvents(friendUid: String, limit: Int) async throws -> [FeedEventDTO]

    /// Owner reads their OWN recent events (createdAt desc, capped at `limit`)
    /// for the "Your milestones" receipts strip. Permitted by the owner read rule.
    func fetchMyFeedEvents(userId: String, limit: Int) async throws -> [FeedEventDTO]

    // MARK: - Cheers (Friend System Phase 8)

    /// Cheer a friend's event. Create-only; doc ID = cheererUid ⇒ one cheer per
    /// person per event. Re-cheer of an existing cheer is rejected by the rules
    /// (update: false); callers swallow that as the expected no-op — same
    /// contract as Phase 7 event emission.
    func addCheer(ownerUid: String, eventId: String,
                  cheererUid: String, username: String, displayName: String) async throws

    /// Remove my cheer (delete users/{ownerUid}/feedEvents/{eventId}/cheers/{cheererUid}).
    /// Deleting an absent doc is a no-op.
    func removeCheer(ownerUid: String, eventId: String, cheererUid: String) async throws

    /// Fetch cheers for one event (createdAt desc, capped at `limit`).
    /// Friend-gated by rules; permission-denied ⇒ []. Undecodable docs skipped.
    func fetchCheers(ownerUid: String, eventId: String, limit: Int) async throws -> [CheerDTO]

    // MARK: - Meal/recipe sharing (Friend System Phase 9)

    /// Deliver a share into a friend's inbox (cross-user create; rules require
    /// the sender to be in the recipient's friends list at send time).
    func sendSharedItem(_ item: SharedItemDTO, toUid: String) async throws

    /// Recipient fetches their inbox filtered by kind ("meal" | "recipe"),
    /// createdAt desc, capped at `limit`. Owner-only read. The equality filter
    /// plus order-by REQUIRES the composite index (kind ASC, createdAt DESC) in
    /// firestore.indexes.json — without it the query throws FAILED_PRECONDITION.
    /// Undecodable docs are skipped.
    func fetchSharedItems(userId: String, kind: String, limit: Int) async throws -> [SharedItemDTO]

    /// Recipient fetches their ENTIRE inbox (both kinds), createdAt desc, capped
    /// at `limit`. Owner-only read; ordering on a single field uses the automatic
    /// single-field index — no composite index required. Undecodable docs skipped.
    func fetchAllSharedItems(userId: String, limit: Int) async throws -> [SharedItemDTO]

    /// Recipient removes a share (after save or dismiss). Absent ⇒ no-op.
    func deleteSharedItem(id: String, userId: String) async throws

    // MARK: - Guilds (G1)

    /// Create a guild + the founder's owner member doc + the founder's guildMemberships lock,
    /// all in one batch. Caller supplies a candidate guildCode and its own stamped identity.
    /// Throws on code collision OR if the lock already exists (caller already in a guild).
    /// D3b: `ownerAvatar*` is the founder's own preset avatar (from its local profile), stamped
    /// into the owner member doc only (the lock carries no avatar). nil ⇒ keys omitted.
    func createGuild(code: String, name: String, joinPolicy: String, description: String?,
                     ownerUid: String, ownerUsername: String, ownerDisplayName: String,
                     ownerAvatarIcon: String?, ownerAvatarColor: String?) async throws

    /// Read a guild by code (for the join screen). nil if not found.
    func fetchGuild(code: String) async throws -> GuildDTO?

    /// The browsable guild directory (R7d): the joinable, non-`private` guilds, name-ordered
    /// and capped at `GuildConstants.directoryFetchCap`. Read-only; no listener.
    ///
    /// The `joinPolicy in ['open','request']` constraint is load-bearing, NOT a convenience
    /// filter: the rules' `list` clause denies any query that could return a `private` guild,
    /// so an unconstrained fetch is permission-denied. Do not relax it.
    func fetchGuildDirectory() async throws -> [GuildDTO]

    /// The current user's guild via an O(1) read of guildMemberships/{uid} → its guildCode →
    /// fetchGuild(code:). Returns nil if the lock doc is absent (not in a guild). No collectionGroup.
    func fetchMyGuild(uid: String) async throws -> GuildDTO?

    /// Roster (members) and pending requests (owner-only read on requests).
    func fetchGuildMembers(code: String) async throws -> [GuildMemberDTO]
    func fetchJoinRequests(code: String) async throws -> [GuildJoinRequestDTO]

    /// Open-policy self-join: batch create my member doc (role "member") + my guildMemberships lock.
    /// D3b: `avatar*` = my own preset avatar (local profile), stamped into the member doc only; nil ⇒ keys omitted.
    func joinOpenGuild(code: String, uid: String, username: String, displayName: String,
                       avatarIcon: String?, avatarColor: String?) async throws

    /// Request-policy: create my own join-request doc (no lock yet — lock is written on approval).
    /// D3b: `avatar*` = my own preset avatar (local profile), stamped into the request doc; nil ⇒ keys omitted.
    func requestToJoinGuild(code: String, uid: String, username: String, displayName: String,
                            avatarIcon: String?, avatarColor: String?) async throws

    /// Cancel my own pending request.
    func cancelJoinRequest(code: String, uid: String) async throws

    /// Owner approves: batch create the requester's member doc (stamped from the request) +
    /// the requester's guildMemberships lock + delete the request. The lock create fails if the
    /// requester is already in a guild, which correctly aborts the approval.
    func approveJoinRequest(code: String, request: GuildJoinRequestDTO) async throws

    /// Owner denies: delete the request.
    func denyJoinRequest(code: String, requesterUid: String) async throws

    /// Member leaves: batch delete own member doc + own guildMemberships lock. (Owner must disband.)
    func leaveGuild(code: String, uid: String) async throws

    /// Owner kicks: batch delete the member's doc + that member's guildMemberships lock.
    func kickMember(code: String, memberUid: String) async throws

    /// Owner updates settings (name and/or joinPolicy and/or description). ownerUid/createdAt immutable.
    func updateGuildSettings(code: String, name: String, joinPolicy: String, description: String?) async throws

    /// Owner disbands: delete ALL member docs + ALL request docs + ALL members' guildMemberships
    /// locks + ALL messages (chunked ≤450/batch) THEN the guild doc.
    func disbandGuild(code: String) async throws

    // MARK: - Guild chat (G3)

    /// Start the screen-scoped live listener on the latest 50 messages of a guild
    /// (order createdAt desc, limit 50). onUpdate fires on every snapshot with the messages
    /// in CHRONOLOGICAL order (the impl reverses the desc query). onError fires on a terminal
    /// listener error (e.g. permission-denied after the user leaves/guild disbands) so the VM
    /// can tear down and exit. The service holds the single registration internally — this is
    /// the only screen-scoped listener in the app and is NOT part of the global registry.
    func startGuildChatListener(code: String,
                                onUpdate: @escaping ([GuildMessageDTO]) -> Void,
                                onError: @escaping (Error) -> Void)

    /// Remove the chat listener (idempotent). Called on chat screen disappear.
    func stopGuildChatListener()

    /// Send a message (member-gated by rules). Caller stamps its own identity; text pre-validated.
    func sendGuildMessage(code: String, msg: GuildMessageDTO) async throws

    /// Delete a message: sender (own) or owner (moderation) — enforced by rules.
    func deleteGuildMessage(code: String, msgId: String) async throws

    // MARK: - Duels (D1a)

    /// Create a pending challenge. Caller supplies the fully-stamped DTO (both
    /// identities); returns the new duelId (Firestore auto-id).
    func createDuel(_ duel: DuelDTO) async throws -> String

    /// My duels, newest first (`participantUids` arrayContains), limited to ~50.
    /// Requires the composite index (participantUids CONTAINS + createdAt DESC).
    func fetchMyDuels(uid: String) async throws -> [DuelDTO]

    /// Opponent accepts: status pending→active, sets acceptedAt (server) + endAt (client date).
    func acceptDuel(duelId: String, endAt: Date) async throws

    /// Opponent declines: status pending→declined.
    func declineDuel(duelId: String) async throws

    /// Either participant flips a stale pending duel: status pending→expired.
    func expireDuel(duelId: String) async throws

    /// Challenger cancels own pending challenge: deletes the doc.
    func cancelDuel(duelId: String) async throws

    // MARK: - Duels (D1b)

    /// Own-side score write: sets my score/dayScores/scoreUpdatedAt(server) on an active duel.
    func updateDuelScore(duelId: String, isChallenger: Bool, score: Double, dayScores: [Double]) async throws

    /// Resolver writes the outcome of an ended duel (winner per scores; deltas pre-rolled by caller).
    func resolveDuel(duelId: String, winnerUid: String?, challengerDelta: Int, opponentDelta: Int) async throws

    /// Forfeit an active duel (caller is the forfeiter; deltas deterministic per DuelDTO.forfeitDeltas).
    func forfeitDuel(duelId: String, forfeiterUid: String, challengerDelta: Int, opponentDelta: Int) async throws

    /// Own-side applied flag, false→true. Throws (permission-denied) if already applied — callers
    /// treat that as "do not apply RR".
    func markDuelRRApplied(duelId: String, isChallenger: Bool) async throws

    // MARK: - QTE Days (D1d)

    /// Upserts users/{userId}/qteDays/{dateKey} (setData merge:true).
    func uploadQTEDay(_ day: QTEDayDTO, userId: String) async throws

    /// All QTE day docs for the user (bounded — at most one per active day; no index needed).
    func fetchQTEDays(userId: String) async throws -> [QTEDayDTO]

    /// One QTE day doc (deterministic doc id = dateKey); nil when absent or undecodable.
    /// Feeds the read-merge-then-write upload path (review finding M3).
    func fetchQTEDay(userId: String, dateKey: String) async throws -> QTEDayDTO?

    // MARK: - Matchmaking (D2)

    /// Creates/overwrites MY queue ticket (setData; rules restrict overwrite to unclaimed).
    func enqueueDuelTicket(_ ticket: DuelQueueTicketDTO) async throws

    /// My own ticket, or nil.
    func fetchMyDuelTicket(uid: String) async throws -> DuelQueueTicketDTO?

    /// Unclaimed candidates for a league within [rrLo, rrHi], ordered by rr, limited.
    /// Requires the composite index (league ASC, claimedBy ASC, rr ASC).
    func fetchQueueCandidates(league: Int, rrLo: Int, rrHi: Int, limit: Int) async throws -> [DuelQueueTicketDTO]

    /// Deletes a ticket (own cancel/sweep, or anyone's expired ticket — rules enforce).
    func deleteDuelTicket(uid: String) async throws

    /// The claim transaction (pairing protocol step 3). Reads my own ticket (aborting with
    /// `DuelError.alreadyMatched` if someone matched me first), verifies the candidate's
    /// ticket, then atomically claims it (`claimedBy`/`claimedAt`/`matchedDuelId`), creates
    /// the born-active matchmade duel, and deletes my own ticket. Returns the new duelId.
    /// Throws `DuelError.candidateUnavailable` when in-transaction verification fails.
    func claimTicketAndCreateDuel(candidate: DuelQueueTicketDTO, myTicketUid: String,
                                  duel: DuelDTO) async throws -> String

    // MARK: - Global Leaderboard (D3)

    /// Upserts leaderboard/{userId} (setData WITHOUT merge — the doc is small and the rule pins
    /// the exact field set; a full overwrite keeps stale keys impossible).
    func upsertLeaderboardEntry(_ entry: GlobalLeaderboardDTO, userId: String) async throws

    /// LB-PAGE-1: one server-cursor page of a board. orderBy(field, descending) + documentID()
    /// tie-break + limit, `start(after: [value, uid])` when a cursor is supplied. Single-field
    /// orderBy (+ implicit `__name__`) — automatic index, no composite (mirrors `fetchLeaderboardSlice`).
    func fetchLeaderboardPage(orderField: String, limit: Int, after: LeaderboardCursor?) async throws -> [GlobalLeaderboardDTO]

    /// My own row (nil if never published).
    func fetchMyLeaderboardEntry(userId: String) async throws -> GlobalLeaderboardDTO?

    /// Board position: count(field > myValue) + 1 via the count() aggregation. LB-PAGE-1
    /// generalized across boards (RR/Wins/Streak) by parameterizing the field.
    func fetchLeaderboardPosition(orderField: String, myValue: Int) async throws -> Int

    /// One directional slice of the leaderboard around an RR value (C1 — RR-proximity stream).
    /// - `.up`:   rr >= fromRR, ordered rr ASC,  then documentID ASC
    /// - `.down`: rr <  fromRR, ordered rr DESC, then documentID DESC
    /// `after` is the (rr, uid) of the last row previously consumed in this direction; nil for
    /// the first page. Returns up to `limit` rows (undecodable docs skipped). Single-field
    /// range + orderBy on `rr` (implicit `__name__` secondary) — automatic index, no composite.
    func fetchLeaderboardSlice(direction: LeaderboardSliceDirection,
                               fromRR: Int,
                               after: (rr: Int, uid: String)?,
                               limit: Int) async throws -> [GlobalLeaderboardDTO]

    /// UGC-1b (D7): leaderboard rows for a specific set of uids (the Blocked Users screen
    /// resolves display identity this way). Chunked at ≤10 per `documentID() in` query and
    /// concatenated; uids with no leaderboard doc are simply absent from the result. No
    /// ordering — the caller sorts. documentID-only ⇒ no composite index (indexes untouched).
    func fetchLeaderboardEntries(uids: [String]) async throws -> [GlobalLeaderboardDTO]

    // MARK: - Safety: blocklist + reports (UGC-1a)

    /// One-time read of the caller's blocklist doc (users/{userId}/account/blocklist).
    /// A missing doc or missing `blockedUids` field returns [].
    func fetchBlocklist(userId: String) async throws -> [String]

    /// Adds `blockedUid` to the caller's blocklist via setData(merge:) + arrayUnion —
    /// creates the doc if absent. Idempotent (arrayUnion de-dupes).
    func addToBlocklist(userId: String, blockedUid: String) async throws

    /// Removes `blockedUid` via setData(merge:) + arrayRemove. No-throw when the
    /// doc or entry is absent (arrayRemove of a missing element is a no-op).
    func removeFromBlocklist(userId: String, blockedUid: String) async throws

    /// Creates reports/{reportId}. Errors are NOT swallowed here — DataManager
    /// interprets permission-denied (duplicate report) as idempotent success (D6).
    func submitReport(_ report: ReportDTO, reportId: String) async throws

    // MARK: - Feedback (FEEDBACK-1)

    /// Creates users/{uid}/feedback/{autoId} with an auto-id (addDocument) — a
    /// private, create-only drop-box. Awaits server acknowledgement so a rules
    /// rejection or other server error THROWS rather than being swallowed (the
    /// compose sheet surfaces it inline). No reads, no listeners; the path uid is
    /// resolved from the active sync session, like every upload* method.
    func submitFeedback(_ dto: FeedbackDTO) async throws

    // MARK: - Account Deletion

    /// Deletes all Firestore data under users/{userId}/ in batches.
    ///
    /// Deletes all known subcollections (each document in batches of ≤500),
    /// then deletes the root users/{userId} document.
    /// This must succeed before the Firebase Auth account is deleted.
    func deleteAllUserData(userId: String) async throws

    // MARK: - Lifecycle

    /// Stops every active listener across all models and clears the sync user.
    /// Safe to call when no listeners are active. Must be called on logout.
    func stopAllListeners()
}
