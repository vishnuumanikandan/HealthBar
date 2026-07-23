# CLAUDE.md — HealthBar Guardrails

Read this before touching code. These are invariants, not suggestions. If a task —
or a code-review suggestion — conflicts with anything here, STOP and flag it instead
of implementing.

## Scope discipline
- Implement ONE feature per session, exactly as specified in the provided prompt.
- Only modify files listed in the prompt's Files list — EXCEPT minimal compile fixes
  strictly required by those changes (e.g. a renamed enum case breaking another file).
  Compile fixes are the only permitted out-of-list edits, and they must be minimal.
- The project must COMPILE when you finish. Never leave a build broken because the
  breaking site "wasn't in the list" — fix it minimally and note it.
- Do NOT rename existing files, types, methods, properties, or Firestore
  collections/fields unless the prompt explicitly requires it.
- Do NOT introduce a new manager, service, repository, coordinator, helper, wrapper,
  protocol, or DTO unless the prompt explicitly requires it. Reuse existing
  abstractions.
- Do NOT implement future roadmap items. If a TODO references a future prompt
  (D1, D2, RR-2, G4...), leave it as a TODO.
- If a prompt specifies rollout order (e.g. rules deploy first, then client),
  preserve that order in the deliverable/instructions.
- If the prompt and this file conflict, stop and explain the conflict; do not
  silently resolve it yourself.

## Architecture spine
- Layers: SwiftUI Views → ViewModels (@Observable, @MainActor) → AppCoordinator →
  DataManager → FirestoreService. Never skip layers.
- NO Firestore types or calls outside FirestoreService/FirestoreServiceImpl and
  DataManager. `ListenerRegistration` NEVER leaves FirestoreServiceImpl — not into
  view models, not into views (the guild-chat listener is managed via start/stop
  methods for exactly this reason).
- NO SwiftData usage inside Views. Views talk to view models only.
- All SwiftData models are scoped by `userId`; all Firestore private data lives under
  `users/{userId}/`. Firestore documents sync via plain Codable DTOs (no SwiftData
  types in the service layer).

## Guest mode
- `isGuest` is the ONLY guest indicator. `userId == "guest"` is local scoping only.
- When `isGuest == true`: zero Firestore reads, writes, listeners, or sync init.
  Every Firestore entry point starts with the guest guard.

## Privacy spine (social features)
- ZERO cross-user reads of private data, ever. Social features work by OWNER-computed,
  owner-published projections (`users/{uid}/public/stats`) and stamped snapshots
  written INTO the other user's space (requests, shares, feed events).
- Identity/dedup/ranking always key on `uid`. Username/displayName fields in cross-user
  docs are display-only snapshots — never keys, never re-resolved.
- Security rules are the real enforcement boundary. Client checks are UX only.
  Any new collection or field written cross-user REQUIRES a rules change + deploy
  (`firebase deploy --only firestore:rules`), and shape-validating rules
  (`keys().hasOnly`, type/range checks) must be updated when a DTO gains a field —
  otherwise publishes fail silently.

## Data ownership
- Each piece of state has exactly ONE source of truth. Never duplicate persisted
  state across models/collections unless the prompt explicitly defines a projection
  (e.g. `public/stats`) — and projections are owner-published snapshots, never
  independently mutated.

## Rank / RR (post RR-0) — DO NOT REGRESS
- Rank is derived from `rr` ONLY: `Rank.getRank(from: rr)` / `Rank.rankTier(from: rr)`.
- `totalXP` drives `currentLevel` ONLY. NEVER reintroduce any XP→rank derivation,
  in code OR in UI copy ("earn XP to rank up" is a violation).
- `getRank(from:)` takes an Int — passing XP still COMPILES and is silently wrong.
  Any call site must pass `rr`.
- `rr` is NON-MONOTONIC (losses decrease it). Never merge it with `max()`; it is
  Firestore-authoritative until duel resolution (D1) adds explicit reconciliation.
- Constants live on `Rank` (`startingRR = 450`, `rrPerTier = 100`, `tiersPerRank = 3`);
  no magic numbers.
- The published `public/stats.rank` string is legacy back-compat; `rr` is authoritative.

## Locks & invariants (doc-id-as-lock)
- `usernames/{handle}` — username uniqueness. Claimed only via the claim transaction.
- `guildMemberships/{uid}` — ONE guild per user, enforced server-side. The lock and
  the `guilds/{code}/members/{uid}` doc are ALWAYS written/deleted in the same batch.
  Never write one without the other.
- Server-side invariants live in rules + lock docs. A client-only check is not an
  invariant.

## Firestore lessons (paid for; do not relearn)
- Subcollections DO NOT cascade-delete. Every deletion of a parent must explicitly
  delete children first. Current cascades that must be maintained:
  - Guild disband: messages + members + joinRequests + each member's
    guildMemberships lock → THEN the guild doc.
  - Feed event deletion/pruning: cheers subcollection first.
  - Account deletion (`deleteAllUserData`): includes `public/stats`, feed events +
    cheers, friend edges (reciprocal), sharedItems, username release, and guild
    teardown (disband-if-owner / leave-if-member). If guild teardown fails, ABORT
    the account deletion.
- Server-timestamp fields (`@ServerTimestamp` / sentinel) are NOT type-checked in rules.
- An equality filter + order-by on a different field REQUIRES a composite index
  (deploy `firestore.indexes.json`); without it the query throws at runtime.
- Batches cap at 500 ops — chunk at ≤450.
- Deterministic doc IDs collide across users; composite identity (`uid + "_" + id`)
  where lists merge multiple users' docs.
- Listener ordering needs a `documentID()` tie-break when timestamps can collide.
- Prod rules are TRANSITIONAL since GUILD-RULES-1 — bi-generational GUILD-CAP arms; strict forms restore at 2.1 via the TODO-strict-rules-at-2.1 comments.

## Listener policy
- Default is fetch-on-view + pull-to-refresh. The global listener registry
  (stopAllListeners) is for always-on user-data sync only.
- The ONLY screen-scoped listener is guild chat: started on appear, stopped on
  disappear, held inside FirestoreServiceImpl, NOT in the global registry.
  Do not add new listeners without an explicit prompt instruction.

## UI discipline
- All new UI styles through `DesignSystem` tokens (colors, fonts, spacing, radii).
  NO hard-coded colors/fonts — an app-wide reskin is planned and priced on this.
- Profile VIEWING is open to any signed-in user as of NAV-1a (`public/stats` reads
  ungated, `FriendProfileView` renders a stranger mode); entry points (leaderboards,
  rosters, chat) thread the taps in NAV-1b. Comparison and Remove Friend remain
  friend-gated (`viewModel.isFriend`); challenge-from-profile stays out
  (`TODO-profile-challenge`). Cross-user reads still touch ONLY the owner-published
  `public/stats` projection — never private data.

## When in doubt
- Preserve existing behavior. Never guess: prefer a clearly-marked TODO over invented
  behavior, the existing pattern over a new one, the boring option over the clever
  one, and flagging over silently deciding.

## Lessons (D3a)
- Per-tab DataManager instances: ContentView creates one DataManager per tab. Any state that must be consistent across tabs MUST be `static` or live on `FirestoreServiceImpl.shared` — instance state silently forks per tab (the `blockedUids` dead-filter bug).
- Rank raw values are Firestore wire format — pinned forever: before touching `Rank`, read its type doc. They appear in immutable `feedEvents/rank_<rawValue>` doc IDs and in `public/stats.rank`; changing one orphans published milestones (decoded back via `Rank(rawValue:)` → nil → the row is silently dropped forever). Rename the Swift case identity only; NEVER change or "tidy" a raw value; new cases pin an explicit raw value from day one.
- AppCoordinator rides every DataManager signature change: any change adding or altering a DataManager method signature lists AppCoordinator as MODIFIED and updates its passthrough in the same diff.
- Git hygiene in agent sessions: NEVER `git reset --hard`. Use `git stash -u` for anything in the way (recoverable). If a hard reset ever seems necessary, STOP and ask before running it.
- Active duels persist through a block: the Arena opponent head still opens the shared duel surface for both participants (SMOKE-5C finding, accepted). `TODO-block-active-duel`: proper resolution is block-forfeits/ends-the-duel — a duel-lifecycle pass, post-2.1.
