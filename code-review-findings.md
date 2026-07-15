# HealthBar — Code Review Findings

**Date:** 2026-07-06
**Scope:** Entire app, with deep focus on the security/data spine (DataManager, FirestoreService(Impl), `firestore.rules`, DTOs, models, GamificationManager, AppCoordinator, auth) and logic-only review of Views/ViewModels (styling/layout deliberately excluded — a reskin is imminent).
**Method:** 14 focused reviewer agents (one per dimension) → adversarial verification of every finding (each re-traced against the actual code/rules, default-to-reject) → main-loop independent verification of the security-critical spine and every Critical/High. 21 raw findings → 17 confirmed → deduped to 16 below; 4 rejected (documented at the end).
**Deliverable:** report only. No source, rules, or config files were modified.

---

## Executive summary

The security spine is, on the whole, unusually well-built: the matchmaking transaction is race-safe, the RR delta table is in sync between `DuelConstants` and `firestore.rules`, duel resolution deltas are deterministic (FNV-1a + SplitMix64, no `hashValue`), `participantUids` exact-equality is enforced, the RR-apply flag is genuinely flag-first, non-monotonic `rr` is reconciled without `max()`, guest gating covers every new Firestore entry point, and the account-deletion cascade sweeps the new `qteDays`/`duelQueue`/`leaderboard`/duel/cheer surfaces. See **"What's sound"** below — several of these are exactly your focus items, and they check out.

However, the review found **two Critical rules-level access/integrity holes** that a modified client (the threat model your own CLAUDE.md names: "rules are the real enforcement boundary; client checks are UX only") can exploit today, plus a High cross-device data-corruption bug and a High matchmaking DoS.

| Severity | Count | Themes |
|---|---|---|
| **Critical** | 2 | Recursive-wildcard catch-all nullifies per-collection rules → unilateral friend-edge insertion + non-consensual reads; unbounded `endAt` on accept → instant 0-0 draw RR farming |
| **High** | 2 | `currentStreak` merged with `max()` (non-monotonic) → cross-device streak corruption; forgeable queue claim → matchmaking DoS |
| **Medium** | 9 | Client-authoritative RR/score projections; matchmade-league not bound; QTE upload last-writer-wins; forged guild lock; listener teardown on passive sign-out; orphaned account on migration failure; leaderboard board-switch race; undo-state clobber |
| **Low** | 4 | Ghost cheers survive deletion; `loginHandles` pre-auth email (known debt); orphaned guild-chat listener; (misc) |
| **Known debt (confirm only)** | 2 | Client-embedded Claude API key; `loginHandles get:true` |

---

# CRITICAL

## C1 — Recursive-wildcard owner catch-all nullifies every per-subcollection rule, enabling unilateral friend-edge insertion into any victim + non-consensual reads of their private projections
**Severity:** Critical · **Category:** over-permissive-rule · **File:** `firestore.rules:11-13`

**Defect.** Firestore evaluates all matching `match` blocks with **OR semantics** — there is no "most-specific-wins" and no deny. The recursive catch-all

```
match /users/{userId}/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

grants the owner full write to **every** document under their own space, *including* `users/{me}/friendRequests/{X}` — overriding the specific `friendRequests` create rule (`firestore.rules:70-79`) that requires `auth.uid == fromUid == X`. That forged doc is the exact capability the `friends` create rule trusts.

**Exploit (traced, holds end-to-end):** Attacker `M` (modified client / direct REST):
1. `create users/M/friendRequests/X = {}` — allowed by the catch-all (`auth.uid == M == userId`); the friendRequests-specific rule's `fromUid == X` check never applies.
2. `create users/X/friends/M = {friendUid:'M', friendUsername:'a', friendDisplayName:'a', since:…}` — the `friends` create path-2 (`firestore.rules:124-125`) passes because `auth.uid == friendUid == M` **and** `pendingReq(M, X) = exists(users/M/friendRequests/X) == true`. `M` is now in `X`'s friends list with **zero consent** — directly contradicting the block's own comment (`firestore.rules:108-109`: "neither party can unilaterally insert themselves into a list").
3. The forged edge satisfies every friend-gated read boundary keyed on `exists(users/X/friends/reader)`: `public/stats` (`:150`), `feedEvents` (`:210`), `cheers` (`:240`), and `sharedItems` delivery (`:281`). `M` now reads `X`'s owner-published projections and can deliver items into `X`'s inbox.

**Secondary blast radius (same root cause):** because the catch-all grants the owner `write` over their own `users/{me}/public/stats`, the shape/type/range validation at `firestore.rules:163-193` is **also nullified for the owner** — a modified client can publish `public/stats` with arbitrary `rr`/`level` (even out of the declared ranges). (`leaderboard/{uid}` is top-level, *not* under `users/`, so it is unaffected by the catch-all — its own rule still bounds `rr >= 0`; see M5.)

**Recommendation (no fix applied):** Do not gate a cross-user friend-edge write on the existence of a doc in the requester's **own** space (which the catch-all makes forgeable). Either scope the catch-all so it does not cover the cross-user-relevant subcollections (`friendRequests`, `friends`, `public`, `feedEvents`, `sharedItems`, cheers) and let the restrictive per-collection rules stand alone, or base `pendingReq` on a doc the requester cannot self-write. This is a broad footgun — the catch-all currently neuters owner-side validation on *every* subcollection under `users/{uid}/`.

---

## C2 — Accept transition never bounds `endAt` → born-ended 0-0 duel pays both sides a positive draw delta (unbounded RR / leaderboard farming)
**Severity:** Critical · **Category:** rr-manipulation · **File:** `firestore.rules:631-643` (missing bound admitted at `:633`)

**Defect.** `isPendingTransition()` lets the opponent flip `pending → active` while writing `endAt` in the `affectedKeys().hasOnly(['status','acceptedAt','endAt'])` set, with the **only** time check being `request.time < resource.data.respondBy`. The value of `endAt` is never constrained (not even to the future). `isMatchmadeCreate()` has the same gap (`firestore.rules:603` checks only `endAt is timestamp`).

**Exploit (traced, every link holds):** Attacker controls accounts `A` and `B` (trivial ladder threat model):
1. `A` challenges `B` (`isChallengeCreate` pins `challengerScore == opponentScore == 0`, `firestore.rules:571-572`).
2. `B`'s patched client accepts with `endAt = Date.distantPast` — `acceptDuel(duelId:endAt:)` writes it verbatim (`FirestoreServiceImpl.swift:1442-1448`); `isPendingTransition` passes.
3. Duel is now `active` with `request.time > endAt`. `isOwnScoreWrite` requires `request.time < endAt` (`firestore.rules:649`), so scores stay frozen at 0-0.
4. Either account resolves as a draw: `isResolve` draw branch (`firestore.rules:714-717`) passes (`0 == 0`, no `winnerUid`, `drawDeltaOk` on both deltas), and `drawDelta` is a **positive** `+10/+15/+20` (`DuelDTO.swift:60-62`). Both accounts gain RR (`DataManager.swift:4074`, `progress.rr = max(0, progress.rr + myDelta)`).
5. `isRRApplyFlag` only stops re-applying the *same* duel; there is no create-side cooldown, so the pair loops fresh challenge docs with **no league wait** → arbitrary RR and top of the world-readable D3 leaderboard.

**Recommendation (no fix applied):** In `isPendingTransition` (accept branch) and `isMatchmadeCreate`, require `endAt` to be sufficiently in the future relative to `request.time` (e.g. `request.resource.data.endAt > request.time` and bounded to `league * secondsPerDay ± skew`). Bounding `endAt` closes the instant-resolve path.

---

# HIGH

## H1 — `currentStreak` (non-monotonic) is merged with `max()` → a broken streak can never sync a decrease and is resurrected across devices
**Severity:** High · **Category:** sync-merge-correctness · **File:** `Persistence/DataManager.swift:726`

**Defect.** `applyUserProgressUpdate` reconciles `let mergedCurrentStreak = max(dto.currentStreak, local.currentStreak)` and the doc comment at `:706` classifies `currentStreak` as monotonic ("max() wins (never decrease)"). But `currentStreak` is **non-monotonic**: `GamificationManager.updateStreak` resets it to `1` on a missed day (`GamificationManager.swift:115`). This is precisely the "non-monotonic field merged with `max()`" antipattern the invariants forbid for `rr` — applied here to a sibling field via misclassification. The pending-confirmation guard repeats the same wrong assumption (`DataManager.swift:761`, `dto.currentStreak >= local.currentStreak`).

**Failure scenario (multi-device, same account):** Device A and B both show a 10-day streak (Firestore `currentStreak = 10`). After missing 2 days, the user logs on Device A → `updateStreak` resets to `1`, uploads `1`. Device B's listener receives `currentStreak = 1`, but `isPending == false`, so `max(1, 10) = 10` — B keeps the stale 10. Any later save on B (e.g. an XP award) re-uploads `10`, overwriting the correct reset in Firestore; A then syncs `max(10,1) = 10`. The broken streak is **resurrected on both devices**. It's actually stickier than that: `lastActiveDate` is *also* `max()`-merged (`:728`), so B's `lastActiveDate` advances while `currentStreak` stays 10 → a later same-day log on B sees `dayDifference == 0` and never recomputes the reset. Downstream: inflated `currentStreak` is projected into the friend-leaderboard `public/stats` via `publishMyStats` and wrongly re-grants streak milestone badges (`week_warrior >= 7`, `month_legend >= 30`, `DataManager.swift:2409-2410`).

**Recommendation (no fix applied):** Treat `currentStreak` as non-monotonic like `rr` — reconcile it Firestore-authoritatively via the existing `reconcile()` helper (`DataManager.swift:739`) instead of `max()`, and drop it from the `>=` confirmation guard. `longestStreak` is genuinely monotonic and can stay on `max()`.

## H2 — Queue claim is not linked to an actual duel → any user can freeze any/all queue tickets (matchmaking DoS)
**Severity:** High · **Category:** forgeable-claim · **File:** `firestore.rules:505-519` (missing linkage at `:512`)

**Defect.** The cross-user claim branch of the `duelQueue` update rule lets any authenticated user set `claimedBy = self`, `claimedAt`, `matchedDuelId = <any string>` on a victim's unclaimed ticket. `matchedDuelId` is only checked `is string` — unlike the duel-*create* side (`isMatchmadeCreate`, `firestore.rules:615-618`), the claim side has **no `getAfter` proof** that a duel referencing the ticket exists. The reciprocal proof is one-directional: you can't create a matchmade duel without a claim, but you *can* write a claim with no duel.

**Failure scenario:** An attacker issues a plain `updateData` on `duelQueue/{victimUid}` with `claimedBy = attacker, claimedAt = ts, matchedDuelId = "x"` — no transaction, no duel. The rule passes. The victim's ticket now reads `claimedBy != ""`, so it's invisible to every legitimate searcher (`fetchQueueCandidates` filters `claimedBy == ""`, `FirestoreServiceImpl.swift:1560`). The victim's own poll sees `isClaimed`, deletes its ticket, and finds no matching duel (`DataManager.swift:3694-3698`) → re-enqueues → attacker re-claims → permanent churn. Tickets are world-readable (`firestore.rules:481`), so scripting this across the queue freezes matchmaking for everyone.

**Recommendation (no fix applied):** The create side is provable via `getAfter`, but the claim side cannot symmetrically prove a duel exists from within the update rule — so a rules-only fix isn't clean. Either accept the queue as a known griefing surface and make the client tolerant of phantom claims (today it self-deletes and churns), or move matchmaking behind server-authoritative logic (Cloud Function) so a claim can never be written without an atomic duel.

---

# MEDIUM

## M1 — RR deltas are only range-checked at resolve/forfeit, not pinned to the deterministic value → per-duel self-favorable RR
**Severity:** Medium · **Category:** rr-manipulation · **File:** `firestore.rules:696-737` (bounds at `:704-712`)

`isResolve()`/`isForfeit()` bound the written deltas only to league **ranges** (e.g. L5 win `50…60`, loss `-40…-30`); they don't require the exact deterministic `DuelDTO.resolveDeltas` value (SplitMix64 seeded by `duelId`) — Firestore rules can't recompute the RNG. Since applied RR is read straight from the stored field (`DataManager.swift:4073-4074`, `progress.rr += myRRDelta`), a patched client that wins the resolve write picks the most self-favorable in-range value every match (winner writes top-of-win-range, loser writes least-negative loss). Bounded (~5-11 RR/duel) but persistent and cumulative on real ranked outcomes. Same architectural root as M5 (client-authoritative RR).

## M2 — Matchmade duel `league` is not bound to the claimed ticket → claimer unilaterally picks the league
**Severity:** Medium · **Category:** ranked-integrity · **File:** `firestore.rules:588-618`

`isMatchmadeCreate` proves the claim via `getAfter(claimedBy == me, matchedDuelId == duelId)` but never checks the created duel's `league` equals the **claimed ticket's** `league` (only that it's in `[1,3,5]`). A victim who enqueues `league = 1` can be matched into a `league = 5` duel (5-day window, league-5-scaled RR swings) they never opted into — e.g. a forfeit-win if the victim stops logging after the 1-day duration they expected. **Recommendation:** add `request.resource.data.league == getAfter(duelQueue/{opponentUid}).data.league` to `isMatchmadeCreate`.

## M3 — QTE max-wins merge exists only on the read path; the full-DTO `merge:true` upload is last-writer-wins per field
**Severity:** Medium · **Category:** data-consistency · **File:** `Firestore/FirestoreServiceImpl.swift:1508`

`uploadQTEDay` does `setData(from: day, merge: true)`, but `QTEDayDTO` always encodes every point field, so `merge:true` never protects them — every upload overwrites `sparkPoints`/`cleanLogPoints`/`macroGuessPoints`. The earn-only max-wins/OR reconciliation exists **only** on the read path (`DataManager.applyQTEDayMerge`, `:3912-3916`). A stale/offline second device therefore clobbers a higher earned total in Firestore and pushes a lower `qteBonus` into the duel doc, defeating the DTO's stated "two-device play converges without loss." Self-undercount only (no forgery past caps), and local values never decrease, so it's silent — but it can alter a duel's `qteBonus` (≤10 pts) and thus a winner. The initial-sync backfill only pushes *missing* days (`DataManager.swift:396`), so the clobbered value isn't re-uploaded. **Recommendation:** read-merge (max) the remote day before uploading, or upload per-field maxes rather than the raw local DTO. (The code comment "merge:true so a field write never clobbers others" is misleading and worth correcting.)

## M4 — Forged `guildMemberships` lock with an arbitrary `guildCode` defeats the guild-mate read gate on `public/stats`
**Severity:** Medium · **Category:** over-permissive-rule · **File:** `firestore.rules:451-461` (self path at `:456`)

The one-guild lock's self-create path validates only `guildCode is string` — never that the guild exists or that a matching `guilds/{code}/members/{uid}` doc is written. The `public/stats` read gate trusts this lock (`firestore.rules:151-153`: reads `get(guildMemberships/reader).data.guildCode` then `exists(guilds/thatCode/members/ownerUid)`). An ex-member (or anyone who knows a guild code) can forge `guildMemberships/self = {guildCode: G}` and read `public/stats` of any member of `G`, re-creating the lock at will after being kicked. Bounded (codes are unguessable ~8.5e11 space and rosters are member-only, so target uids must be known; leaked data is an owner-published projection, not strictly-private). **Recommendation:** on the self-create path, require the matching member doc via `getAfter(guilds/{guildCode}/members/{uid}).data.uid == uid`, mirroring the `isMatchmadeCreate` proof.

## M5 — Global leaderboard `rr`/`wins`/`streak` (and `public/stats.rr`) are owner-writable with no ceiling and no authoritativeness link → self-inflation of the world ladder
**Severity:** Medium · **Category:** leaderboard-manipulation · **File:** `firestore.rules:532-545` (bound at `:539`)

`leaderboard/{uid}` bounds `rr` only with `rr is int && rr >= 0` (no ceiling, no derivation check); `wins*`/`streak*` are unbounded ≥0. A modified client publishes `rr = 999999` and tops the world-readable board for every viewer, with no duel played (`upsertLeaderboardEntry`, `FirestoreServiceImpl.swift:1690-1702`). **This is systemic, not a self-contained bug:** the authoritative `UserProgressDTO.rr` under `users/{uid}/` is itself unvalidated (see C1 — the owner catch-all), so RR is fundamentally client-authoritative; a leaderboard ceiling alone wouldn't restore integrity. Reported so the gap is visible and its blast radius (the entire competitive ladder is spoofable by a modified client) is on record. **Recommendation:** treat as an accepted client-authoritative tradeoff, or move RR/score mutation server-side (Cloud Function) if world-ladder integrity matters. Same class as the API-key debt below — confirm, don't patch client-side.

## M6 — Passive Firebase sign-out (token revocation / password change elsewhere) never calls `stopAllListeners()` → dead listeners on same-account re-login
**Severity:** Medium · **Category:** listener-teardown · **File:** `Auth/FirebaseAuthService.swift:134-136`

The auth state-change listener clears `currentUserEmail`/`isLoggedIn` on `user == nil` but does **not** call `FirestoreServiceImpl.shared.stopAllListeners()`. Only the explicit `logout()`/`continueAsGuest()` buttons do. If a token is revoked mid-session (password changed on another device), `currentSyncUserId` stays equal to the old uid and every `ListenerRegistration` stays non-nil; on same-account re-login, `shouldRegisterListener` returns false ("already listening") and the session runs on dead listeners with no cross-device sync until app relaunch — exactly the failure `logout()`'s own comment (`:243-248`) says it exists to prevent. (Uncommon precondition; fetch-on-view + pull-to-refresh still work; recoverable by relaunch.) **Recommendation:** have the auth listener call `stopAllListeners()` (and clear pending sets) whenever `user` becomes nil while not in guest mode. *Note: the finding's secondary `deleteAccount` example is a red herring — a deleted uid is never reused — but the token-revocation vector is real.*

## M7 — `cancelMigration()` leaves a stale guest session over an orphaned, already-signed-in Firebase account
**Severity:** Medium · **Category:** guest-transition · **File:** `Auth/FirebaseAuthService.swift:168-171`

During guest→signup, `createUser()` signs in the real account first (Firebase-level) while `isGuest` stays true pending SwiftData migration. If migration throws, `cancelMigration()` only clears `pendingMigrationUserId` — it does **not** sign the new account back out or reset guest mode. Result: the real account exists and is signed in, but the app shows a guest; retrying create hits `emailAlreadyRegistered`, the guest's local data is never migrated, and on cold launch `guestModeKey` restores guest mode while the account's token sits orphaned in the keychain — stranded until a manual logout/login. **Recommendation:** on migration failure, `try? Auth.auth().signOut()` before reverting to guest, or offer a distinct retry-migration path for the signed-in account.

## M8 — Global leaderboard board-switch race: a slow fetch clobbers a newer selection's rows
**Severity:** Medium · **Category:** race-condition · **File:** `UI/GlobalLeaderboardViewModel.swift:99` *(found independently by two reviewers)*

Each metric/league picker change spawns an unstructured `Task { await boardChanged() }` with no cancellation and no in-flight guard; `loadBoard()` captures `field` at entry but assigns `rows = result` **unconditionally** after the `await`. Rapidly toggling Wins → Streak, if the slower `wins1` fetch resolves after `streak1`, leaves `rows` holding the wins-ordered board while `metric == .streak` — `valueText`/`captionText` then render streak labels over a wins-ordered list until the next toggle/refresh. No spinner masks it (`ProgressView` only shows while `isLoading && !hasLoaded`). Transient and self-healing (the cache holds the correct board), but a visibly wrong ranking on plausible interaction. **Recommendation:** guard the write with a generation token, or re-derive `currentField` after the `await` and bail if it changed.

## M9 — Rapid successive `deleteWithUndo` wipes the new delete's undo state and resurrects the item
**Severity:** Medium · **Category:** race-condition · **File:** `UI/FoodLogViewModel.swift:523`

A second delete inside the 5s undo window spawns `Task { await permanentlyDelete(A) }`, then synchronously sets up B's undo state. The spawned finalize of A runs first: `permanentlyDelete(A)` calls `loadTodaysData()` (re-reads the DB where B still lives → B reappears), then unconditionally sets `showUndoToast = false; recentlyDeleted = nil; deletionTask = nil` — clobbering B's just-set undo affordance and dismissing its toast, while B's orphaned 5s timer still fires and deletes B with no undo. Deterministic on two rapid deletes. **Recommendation:** finalize the previous delete synchronously (await before setting up the new undo), or guard the finalize path so it doesn't reset undo state for a superseded entry.

---

# LOW

## L1 — Cheers placed on other users' feed events survive account deletion
**Severity:** Low · **Category:** deletion-cascade · **File:** `Firestore/FirestoreServiceImpl.swift:1858`

`deleteAllUserData` deletes cheers only under the deleting user's **own** `feedEvents`; cheer docs this user wrote into *other* users' spaces (`users/{ownerUid}/feedEvents/{eventId}/cheers/{myUid}`) have no cleanup path and persist as ghost snapshots (inflated cheer count + stale display name visible to the owner) until that event is pruned past the `keep` window — never if the owner has ≤ `keep` events. No cross-user private read; display-only snapshot. **Recommendation:** either document this as sanctioned stamped-snapshot posture, or add a cleanup pass (requires a query, since no sender-side ledger exists).

## L2 — `loginHandles get:true` exposes username→email pre-auth (known accepted debt — blast radius note)
**Severity:** Low · **Category:** known-debt · **File:** `firestore.rules:46`

`allow get: if true` lets any unauthenticated caller resolve a known username to its login email one lookup at a time (`list` is denied, so no bulk harvest). This is already documented accepted debt (project memory); the proper fix is a Cloud Function that preserves pre-auth username sign-in, not built. Re-stated here only to keep the blast radius on record: per-known-handle single email disclosure, no scale enumeration.

## L3 — `GuildChatViewModel.start()` can register an orphaned screen-scoped listener if the view disappears during the `fetchFriends` await
**Severity:** Low · **Category:** listener-lifecycle · **File:** `UI/GuildChatViewModel.swift:68`

`start()` awaits `fetchFriends()` before `startGuildChat()`. If the chat screen disappears during that await, `onDisappear`'s `stop()` runs first (removes nothing — not started yet), then `start()` resumes and registers a live snapshot listener with no matching teardown. Because guild chat is deliberately outside the global `stopAllListeners` registry, the orphan keeps consuming reads until the next chat open's defensive `stopGuildChatListener()` or app restart. Closures are `[weak self]`, so no retain cycle or crash — just a wasted subscription. **Recommendation:** register the listener before/independently of the friends fetch, or add `Task.checkCancellation()` after the await.

## L4 — Defense-in-depth: `uploadQTEDayAndRescore` guards `currentUserId` (non-empty for guests) rather than `!isGuest`
**Severity:** Low · **Category:** guest-gating · **File:** `Persistence/DataManager.swift:3892-3893`

The private helper guards only `currentUserId != ""` — which is true for guests (`userId == "guest"`). It is unreachable for guests today because all callers (`award*QTE`, `getOrCreateQTEDay`) guard `!isGuest` first, so this is not a live hole — but it's the one new Firestore-touching path whose own guard uses the wrong indicator. **Recommendation:** add `!isGuest` for defense-in-depth consistency with every sibling entry point.

---

# Known debt — confirmed blast radius, not fixed (per review scope)

## KD1 — Claude API key is embedded client-side and sent directly to Anthropic
**File:** `App/APIConfig.swift` + `Nutrition/AIFoodRecognitionService.swift:166,227`

`APIConfig.claudeAPIKey` reads `CLAUDE_API_KEY` from `Config.plist` — a **plaintext plist bundled into the shipped app** (`Bundle.main.url(forResource: "Config", withExtension: "plist")`). `AIFoodRecognitionService` sends it as the `x-api-key` header straight to `https://api.anthropic.com/v1/messages`. **Blast radius:** anyone who extracts the IPA (trivial — the plist is plaintext in the app bundle) obtains a live Claude API key and can bill arbitrary usage to your Anthropic account until the key is rotated. There is no proxy, rate limit, or per-user quota between the client and Anthropic. This is the same class as KD2/M5: it can only be closed by moving the call server-side (a backend/Cloud Function that holds the key and the client never sees it). **Confirmed, not fixed, per instruction.**

## KD2 — `loginHandles get:true` (see L2)

---

# Considered and dismissed

**Rejected by adversarial verification (factually checked, no real defect):**

1. **Shared items survive in recipients' inboxes after account deletion** (`FirestoreServiceImpl.swift:1018`) — *working as designed.* `firestore.rules:300-303` encode recipient-ownership (`allow update: if false`, delete only by `recipientUid`, "No sender unsend"); a delivered share is deliberately the recipient's property (like a sent email). No sender-side ledger exists to enumerate, and the identity fields are display-only snapshots never re-resolved. Not a broken cascade.
2. **Global leaderboard forgeable rr/wins/streak** — a *duplicate* of M5; one verifier rejected it as "architectural, not a fixable missing check," the other kept it at Medium as a blast-radius note. Retained as **M5** with that framing.
3. **`insertFoodEntry` omits the `!isGuest` guard** (`DataManager.swift:1624`) — *unreachable.* Entering guest mode always routes through `continueAsGuest()`/`logout()`, both of which call `stopAllListeners()` → `currentSyncUserId = nil`; the service uploads begin with `guard let userId = currentSyncUserId else { return }`, so both fire-and-forget Tasks no-op. No cross-user write is reachable.
4. **`HomeViewModel.loadDuels` has no in-flight guard; `.task` + pull-to-refresh can overlap** (`HomeViewModel.swift:194`) — *idempotent by design.* `DataManager.loadMyDuels` is race-safe at every mutating step: deterministic duelId-seeded deltas + swallowed permission-denied on concurrent resolve; flag-first RR claim (`markDuelRRApplied` before apply, `continue` on throw) prevents double RR and double recaps; both passes read fresh server state. The only cost is redundant Firestore work, not wrong state.

**Independently checked by the main loop and confirmed sound (not findings):** the mutual-claim matchmaking double-match (the transaction reads my own ticket first and aborts `alreadyMatched`, claiming candidate + creating duel + deleting my ticket atomically — `FirestoreServiceImpl.swift:1611-1663`); the RR delta table drift (DuelConstants ↔ rules match exactly across leagues 1/3/5); Swift `hashValue` in the duel path (none — FNV-1a + SplitMix64 with wrapping ops, `DuelDTO.swift:348-406`).

---

# What's sound (verified against your focus items)

These were reviewed deeply and are correct — worth recording so they aren't re-litigated:

- **`participantUids` exact-equality** — enforced in both `isChallengeCreate()` and `isMatchmadeCreate()` (`firestore.rules:567,592`, `== [challengerUid, opponentUid]`).
- **Matchmaking claim + `getAfter` proof** — duel create requires `getAfter(candidate ticket).claimedBy == me && matchedDuelId == duelId` (`firestore.rules:615-618`); the claim update restricts cross-user writes to exactly `[claimedBy, claimedAt, matchedDuelId]` on an unclaimed, unexpired ticket. *(The reverse linkage gap is H2 — a claim with no duel — but the create→claim direction is sound.)*
- **Matchmaking race safety** — the transaction reads *my own* ticket first, aborts `alreadyMatched`, then claims-candidate + creates-duel + deletes-my-ticket atomically; the mutual-claim race collapses to one duel via the read-write conflict on both tickets (`FirestoreServiceImpl.swift:1611-1663`). Sound.
- **RR delta table sync** — `DuelConstants` (`DuelDTO.swift:51-71`) matches the rules helpers `winDeltaOk`/`lossDeltaOk`/`drawDeltaOk`/`forfeitLossDeltaOk`/`forfeitWinnerDeltaOk` (`firestore.rules:672-693`) exactly across all three leagues. No drift. *(The residual is M1 — ranges vs exact value — not drift.)*
- **Deterministic deltas** — FNV-1a (`&*` wrapping) + SplitMix64 seeded by `duelId`, no `hashValue`/`Hasher`; rounded-int score comparison avoids raw `Double ==` (`DuelDTO.swift:348-406`). Cross-device stable.
- **RR flag-first ordering** — `markDuelRRApplied` precedes `recordDuelOutcome`; a flag-write throw `continue`s without applying (`DataManager.swift:3535-3538`). At-most-once, never double-applied.
- **Non-monotonic `rr` merge** — `reconcile()` takes remote `rr` verbatim, never `max()`, protecting local only while a write is pending (`DataManager.swift:739-741`). Correct. *(The same discipline is missing for `currentStreak` — that's H1.)*
- **Account-deletion cascade** — guild-teardown-first-with-abort, then `qteDays`/`duelQueue`/`leaderboard`/duels/cheers/cross-user friend edges/username+loginHandle all swept, batched ≤450 (`FirestoreServiceImpl.swift:1739-1908`). The `knownSubcollections` list includes the new `qteDays`. *(The one gap is L1 — outbound cheers on others' events.)*
- **Guest gating** — every new duel/matchmaking/leaderboard/QTE entry point in DataManager opens with `guard !isGuest` (`sendChallenge`, `joinQueue`, `pollQueue`, `leaveQueue`, `fetchGlobalLeaderboard`, `loadMyDuels`, `acceptChallenge`, `forfeitDuel`, `award*QTE`, …). *(One private helper uses the wrong indicator — L4 — but is unreachable for guests.)*
- **Score bounds** — per-side scores are range-checked to `[0, league * 110]` and day-score lists capped at `league` entries (`firestore.rules:654-667`). *(Bounded, but client-asserted — the integrity ceiling is M1/M5.)*
