# MATCH-2 — Concurrent Two-Simulator Matchmaking Verification

Report-only run. No source, rules, or config files were modified.

## Part A — Ticket lifecycle diagnosis (read-only)

### A1/A2 — The map

**(a) Claimed-ticket → active-duel reconciliation** happens in `checkMyTicket`
(`Persistence/DataManager.swift:3735-3768`), called from `pollQueue`
(`DataManager.swift:3718-3729`) while the matchmaking sheet is open. If my own
ticket is `claimed` (`ticket.isClaimed`), it pulls the new duel via
`loadMyDuels()`, deletes my own ticket, and returns the duel
(`DataManager.swift:3754-3758`). There is **no launch-time or sign-in-time**
reconciliation path for a claimed ticket outside of active polling — a claimed
ticket is only resolved by a live `MatchmakingSheet` poll, or, once the duel
exists, by the ordinary `participantUids` duel query that every `loadMyDuels()`
call already performs (`AppCoordinator.swift:1040-1042` →
`DataManager.loadMyDuels()`).

**(b) Every code path that can delete the current user's own queue ticket:**

| Trigger | Site | Deletes regardless of TTL/claim state? |
|---|---|---|
| **Battle-load sweep** — runs inside `loadMyDuels()` on *every* call where `isQueuePolling == false` | `DataManager.swift:3623-3628` | **Yes.** `fetchMyDuelTicket` → if a ticket exists (`ticket.id != nil`) → unconditional `deleteDuelTicket(uid: me)`. No expiry check, no claimed check (a claimed ticket's duel was already folded into `duels` above, so this only ever hits *unclaimed* tickets, but it does not check `expiresAt`). |
| Enqueue (delete-then-create) | `DataManager.swift:3708` (`enqueueTicket`) | Deletes my *own* prior ticket before writing a fresh one — expected, not a bug. |
| Keep-alive re-stamp while polling | `checkMyTicket`, `DataManager.swift:3761-3766` | Same delete-then-create via `enqueueTicket`; only when `isExpiredNow`. |
| Waiting-side match pickup | `checkMyTicket`, `DataManager.swift:3757` | Deletes only after confirming `ticket.isClaimed`. |
| Cancel button / sheet dismiss (`onDisappear`) | `leaveQueue()`, `DataManager.swift:3846-3851`; wired from `MatchmakingSheet.swift:90` and `:283` | By design, per the runbook's known-quirks list. |
| Lazy sweep of an **expired** *candidate's* ticket (not mine) during search | `searchAndClaim`, `DataManager.swift:3784-3787` | Only candidates I skip over, fire-and-forget, and only when `c.isExpiredNow`. |
| Account deletion | `FirestoreServiceImpl.swift:1791` (`deleteDuelTicket(uid: userId)` inside `deleteAllUserData`) | Yes, unconditionally — expected as part of full teardown. |

**`isQueuePolling`** (`DataManager.swift:3671`) is a private in-memory flag,
`true` only for the lifetime of an active `pollQueue()` call
(`DataManager.swift:3720-3721`, set on entry, reset via `defer`). It is **not
persisted** — it is `false` on every fresh app launch, every sign-in, and any
time the matchmaking sheet is not on screen.

### A2 — Direct answers

- **Does a fresh app launch (or sign-in) delete an UNCLAIMED ticket belonging
  to the current user?** **Yes.** `HomeView`'s two `.task` blocks
  (`UI/HomeView.swift:667-672` and `:676-682`) call `viewModel.loadDuels`
  (`UI/HomeViewModel.swift:193-200`) on *every* Home appearance — including the
  first appearance after a cold launch or sign-in, since Home is the landing
  tab. That funnels into `DataManager.loadMyDuels()`, whose Battle-load sweep
  (`DataManager.swift:3623-3628`) deletes any ticket that is still unclaimed at
  that moment, with **no TTL check** — a ticket created seconds earlier is
  deleted just as readily as one that is 9 minutes old. `isQueuePolling` is
  `false` at that point because the matchmaking sheet isn't open. This
  confirms MATCH-1's relaunch-cleanup hypothesis as the mechanism, but the
  actual trigger is broader than "relaunch" — it is **any** Home-tab
  appearance/fetch-on-view that lands while the ticket is unclaimed and the
  queue sheet isn't actively polling, which is exactly what a sequential
  single-simulator seeding flow (queue as A, background/switch to seed B) would
  hit.
- **Does sign-out delete it?** **No**, not directly. `setupDefaultData()`'s
  logout branch (`DataManager.swift:106-124`) only calls
  `firestoreService.stopAllListeners()` and clears the pending-upload sets; it
  never touches `duelQueue`. The ticket is only reaped the next time *that
  user's* Home tab loads (on their next sign-in) or via the passive
  expired-candidate sweep from someone else's active search
  (`DataManager.swift:3784-3787`), or via `firestore.rules`'s
  anyone-may-delete-if-expired branch (`firestore.rules:570-571`).
- **Ticket TTL:** `DuelConstants.queueTicketTTL = 10 * 60` seconds
  (`Firestore/DuelDTO.swift:111`). Enforcement is **split between client and
  rules**: the client re-stamps `expiresAt` on a keep-alive
  (`DataManager.swift:3761-3766`) and skips/sweeps expired *candidates*
  client-side (`DataManager.swift:3784-3789`); the rules independently gate the
  **claim** update on `request.time < resource.data.expiresAt`
  (`firestore.rules:562`) and allow **anyone** to delete an expired ticket
  (`firestore.rules:570-571`). The **owner-delete** branch
  (`firestore.rules:570`, `request.auth.uid == uid`) has no TTL gate at all —
  the owner can delete their own ticket at any time, which is exactly the
  branch the Battle-load sweep exercises.

**No changes made; no opinion on correctness of this behavior.**

## Part B — Concurrent verification

### Setup

- Two already-booted simulators reused (both iPhone 17 Pro): Sim1 =
  `213F5EFE` (iOS 26.4) as **Account E**, Sim2 = `43DCAC9E` (iOS 26.2) as
  **Account F**. Single build installed on both.
- Sim2 had a leftover signed-in account from a prior session; signed out
  first (clean return to login, no duelQueue side effects per Part A) before
  creating Account F.
- Account E: `matchtest.e.1783576442@healthbar.test` / `matche576442`.
- Account F: `matchtest.f.1783576442@healthbar.test` / `matchf576442`.
- Both signups hit the pre-baked "Use Strong Password?" quirk; the
  accessibility snapshot doesn't see this system sheet, so it had to be
  dismissed by tapping an unrelated on-screen field (tapping the close button
  directly isn't reachable via elementRef) before the password fields could be
  reliably re-verified and re-typed. Also hit a known first-load race
  ("Failed to load profile data") on Account F's first Profile paint
  immediately post-signup; resolved itself once the AI onboarding wizard
  completed and Home was visited (fetch-on-view).
- Both AI onboarding wizards completed with fast defaults (Male/Female,
  age 25, weight/height defaults, Moderately Active, Standard diet, no
  allergies, Good sleep, Low stress).

### Verification table

| Step | Flow | Result | Evidence |
|---|---|---|---|
| B4 | E: Battle → Find Match → 1-Day → Enter Queue | **PASS** | Screenshot: "SEARCHING…" sheet visible |
| B5 | F: Battle → Find Match → 1-Day → Enter Queue (~122s after E, outside the nominal ~30s target but well inside the 10-min TTL) | **PASS** | — |
| B6 | Both sides transition to MATCHED | **PASS** | F's screen (claiming side): "You vs MatchTest E · 1-DAY · 0—0 · Ends 23 hr 59 min" immediately after Enter Queue. E's screen (waiting side), checked next: "You vs MatchTest F · 1-DAY · 0—0 · Ends 23 hr 43/42 min." Both sides show identical duel content (league, score, correct opponent). **Zero permission-denied lines on either simulator's console during this window.** |
| B7 | E: Arena versus header + score row | **PASS** | E was already inside the Arena view post-match: "You 0 — MatchTest F · 1-DAY," Day 1 row `0 vs 0`. |
| B8 | F: Active Duels list shows matching league/opponent | **PASS** | F's Battle tab list: "Active Duels → MatchTest E · 1-DAY · Ends 23 hr 41 min · You 0 — 0 MatchTest E." |
| B9 | Delete Account E (Danger Zone) | **PASS** | Clean return to login screen. |
| B10 | F, without relaunching, Home → Battle after E's deletion | **Observation (informational, not a fail)** | On next Home fetch-on-view, F's client surfaced a duel-resolution recap: **"VICTORY (opponent forfeited) · vs MatchTest E · You 0 — 0 MatchTest E · +8 RR."** Battle tab's active-duel badge cleared afterward. Root cause (confirmed in source, not guessed): `deleteAllUserData` explicitly auto-forfeits every ACTIVE duel the deleted user participates in, via `forfeitDuel(...)` (`Firestore/FirestoreServiceImpl.swift:1862-1866`, inside the block at `:1851-1871`) — this is documented, intentional behavior ("Active (D1b): forfeit (deterministic deltas)", `FirestoreServiceImpl.swift:1848`), not an artifact of the deletion cascade missing something. F's own RR-claim pass in `loadMyDuels()` (`DataManager.swift:3582-3618`) picked up the now-`forfeited` status on the next fetch and surfaced the recap — this is F reading its own duel doc, not a cross-user read. |
| B11 | Delete Account F (Danger Zone) | **PASS** | Clean return to login screen. |
| B12 | Log grep across all session logs, both simulators | **PASS** | `grep -in "missing or insufficient permissions"` → 0 matches. `grep -in "fatal error\|EXC_BAD"` → 0 matches. |

### Elapsed time

E entered the queue at `T+0s`; F entered at `T+122s`. F (the claiming side)
matched essentially immediately on its own Enter-Queue tap — the very first
snapshot taken after F's tap already showed the Arena/versus screen. E (the
waiting side) was confirmed matched on the next check afterward. The two
simulators' on-screen clocks showed an 11:19 vs 11:35 discrepancy between the
F-side and E-side confirmation screenshots; this is consistent with real
wall-clock time spent on tool round-trips between those two checks in this
session, not with any additional matchmaking latency — the duel content
(score, league, opponent identities) was byte-for-byte consistent on both
sides at both checks.

### Permission-denied lines

**None**, on either simulator, at any point in Part B — including the B6
claim-transaction window, which is the step most likely to surface an F1/M2
rules regression.

## Verdict

**Yes — the D2 claim-by-update path is field-verified under the deployed F1
rules.** Two concurrently-live accounts, on two simulators, both entered the
matchmaking queue independently and were correctly paired by the
`claimTicketAndCreateDuel` transaction (`FirestoreServiceImpl.swift:1596-1692`)
with zero permission-denied lines, consistent duel state on both sides, and a
working score/Arena/Active-Duels view on both clients.

**Part A's map confirms (and generalizes) MATCH-1's relaunch-cleanup
hypothesis.** The killer isn't specifically "relaunch" — it's the
unconditional, TTL-blind Battle-load sweep in `loadMyDuels()`
(`DataManager.swift:3623-3628`), which fires on every Home-tab fetch-on-view
while the matchmaking sheet isn't actively polling. MATCH-1's sequential
single-simulator seeding (queue as A, then background/switch to seed B) was
structurally guaranteed to trip this sweep and delete A's still-fresh,
unclaimed ticket the moment Home reloaded for either account. Running both
accounts concurrently on two simulators — so neither one's Home tab needs to
reload while the other is mid-search — sidesteps the sweep entirely, which is
exactly why B4-B8 passed cleanly here where MATCH-1 could not produce a match.
