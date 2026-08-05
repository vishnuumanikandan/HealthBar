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
- Prod rules: live ruleset c725190f-0d3b-45ca-9ebb-732c939d3796 (consolidated 2.1 deploy, 2026-07-25: FEEDBACK-1 block + DUEL-FEED-1 widening). The bi-generational GUILD-CAP arms remain TRANSITIONAL by ruling (Option A, 2026-07-25): the strict TODO-strict-rules-at-2.1 conversions are ADOPTION-GATED — they deploy only after 2.1 dominates installs, via their own prompt + attended deploy + a memberCount true-up backfill. Strict edits must NOT merge to main before their deploy window: `deploy --only firestore:rules` ships the whole file, so anything staged on main rides the next deploy whether intended or not.

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
- AILOG-1a removed the empty-items `detailRequest` bridge — vague zero-item recognitions fall to `noFoodFound`; clarifications are the sole question mechanism. (Spec's "detailRequest is universally inert" + the acceptance allowlist grep required dropping the surfacing use; the sanctioned `clarification` path survives and 1b's structured fields shrink the vague-input class. Accepted tradeoff.)

## Lessons (2.1 close-out)
- hasOnly breaks in both directions: a deploy must never shrink a rule's key set (breaks the shipped client), and a client must never ship a write that widens a rule-pinned affectedKeys set before the widened rule deploys (the new client's own pushes permission-deny — and try? chokepoints swallow it silently).
- DEPLOY-marker staging taxonomy: additive new-path rule blocks may sit undeployed on main indefinitely (feature dark until deploy); widenings of an existing client write path are merge-safe but RELEASE-BLOCKING — rules deploy must precede any build reaching users.
- dayScore is guest-zero as of DUEL-CLARITY-1; any future non-guest-guarded caller must handle it.
- Post-AILOG-1b, model clarifying questions surface via the error card (Q&A UI retired).
- .onDisappear fires on programmatic dismissal too — success paths that dismiss-then-present race their own cleanup; clear session state at the open site, never the disappear site.
- VM snapshots must never render state a live store owns — one renderer, one source (the #50 FirstQuestsCard bug).
- TUT-1b's databaseLog fires-on-return residual: RETIRED by TUT-2 (site deleted).
- PHPicker is out-of-process and cannot be sim-automated; photo flows verify on device only.
- Per-day award idempotency pattern: date field + startOfDay comparison, never Date equality (FIXES-1).
- AppFont TEXTSIZE-1 invariant: every size-producing member of AppFont applies SettingsManager.shared.textScaleFactor exactly once at Font construction. Members that DELEGATE to another AppFont member (serifTitle → display) must not pre-scale — that double-applies the factor.
- GoalMath.maintainBandKg (±0.5 kg) is a SHARED CONVENTION with weightDirectionLabel — if one changes, both must.
- A secret bundled in the client is a PUBLISHED secret. `APIConfig.claudeAPIKey` ships inside the app binary, so anyone with the .ipa has it — no obfuscation changes that, and rotating in place just publishes a new key. The only fix is moving the call behind a server the key never leaves (AIPROXY-1a's `aiProxy`). Corollary: rate limits, model choice, and prompt text are only enforceable where the secret lives — a client-side "limit" is UX, exactly like a client-side rules check. (AIPROXY-1b removed `APIConfig.swift` and the bundled key from the build; revocation stays adoption-gated — `TODO-revoke-bundled-key-at-2.2`.)
- Wire contracts are specced from CALL SITES, not from feature names. `aiProxy`'s request shape was derived field-by-field from `recognize(description:imageData:category:amount:extras:)` and from the profile-summary dictionary — which is why the 1b migration was a payload swap with the public signature and the key-value set both unchanged. A contract named after the feature ("describeMeal", "photoRecognition") drifts the moment the feature grows a field; one mirrored off the call site cannot. Corollary now enforced in code: `invalid-argument` from the proxy is a CONTRACT-DRIFT defect, not a user state, because the client validates exactly what the server does — it logs as drift and never surfaces a user-facing "you did something wrong".
- A rule granting `delete` WITHOUT `read` cannot be swept by query. `getDocuments()` on such a collection permission-denies forever, not just until the rule deploys — so a cascade over it MUST address deterministic doc ids instead (`aiUsage` = the function's UTC `yyyyMMdd` keys, reconstructed client-side; deleting a day that never existed is a harmless no-op). Any "delete-only, owner-only" grant needs its deletion path designed around the missing list, and a client-side key generator must mirror the server's calendar EXACTLY — explicit Gregorian + UTC + manual zero-padding, never `DateFormatter`, which is locale- and calendar-sensitive.
- `View` conformance makes the whole type `@MainActor` — including its `static` helpers. A decode helper called inside `Task.detached` therefore hops STRAIGHT BACK to the main actor, silently defeating the off-main work, and Swift 5 mode reports it only as a warning ("cannot be called from outside of the actor; this is an error in the Swift 6 language mode"). `nonisolated` on such helpers is load-bearing, not decoration (PHOTOPERF-1). Corollary to the known MEALROW-1 rule: `static let` stored properties are illegal in generic types, and the `static var {…}` computed workaround is WRONG for a cache — it hands out a fresh instance per access. Shared storage for a generic view goes in a file-scope enum.
- Named TODOs parked this era: TODO-nodejs22-before-2026-10-30 (HARD DEADLINE, not adoption-gated — unlike every other TODO on this line it has an externally-imposed date. Node.js 20 was deprecated 2026-04-30 and is DECOMMISSIONED 2026-10-30; after that date `firebase deploy` REFUSES the functions codebase, so a broken aiProxy could not be redeployed in an emergency. Fix is `functions/package.json` engines.node + `firebase.json` functions[0].runtime → nodejs22, rebuild, redeploy, re-probe. Do it well before the date, not on it) · TODO-revoke-bundled-key-at-2.2 (ADOPTION-GATED: the bundled client key stays live and un-revoked while pre-1b builds are still calling Anthropic directly. Revoking it before 1b dominates installs breaks AI logging + onboarding personalisation on every older build. Sequence: 1b ships → 1b dominates installs → revoke the bundled key in the Anthropic console → strip `APIConfig.claudeAPIKey`. The `aiProxy` function uses its OWN key, `healthbar-aiproxy`, so revoking the bundled one never touches the proxy. Blocked on the same missing rail as the strict-rules deferral — see TODO-force-update-rail) · TODO-dish-toxin (composite Dish saves toxin 0, mirroring manual flow) · TODO-photo-decode-sweep (the sheet / one-off photo surfaces — `AddFoodFormView`, `EditMealView`, `DescribeMealView`, `FoodDatabaseView` — still decode inline via `UIImage(data:)` on the main thread. PHOTOPERF-1 left them deliberately: none is scroll-hot, so each pays the decode once on a surface the user has just opened, not per-cell during a fling. Converting them is mechanical — swap to `DownsampledPhotoView` with the rendered frame as `targetSize` — but each needs its own placeholder decision, so it wants its own prompt) · TODO-arena-primer-detection (primer opened from Arena doesn't fire tutorial step 5; one closure wire when ArenaView is next touched) · TODO-orphaned-updateStreak (GamificationManager.updateStreak lost its only caller when dead checkAndAwardDailyXP was deleted; never ran in prod) · TODO-force-update-rail (no minimum-version flag exists; the client cannot be warned to update — this forced the Option A strict-rules deferral) · TODO-pace-gain-guidance (gain pace 1.5/2.0 clamps to the +500 surplus cap with no UI note) · TODO-ai-direction-validation (isValid does not bound AI output by goal direction; intentionally deferred — a hard bound could reject legitimate AI personalization) · TODO-calculator-direction-parity (standalone TDEE/goal calculators keep the pre-GOALS-1 deficit-only math) · TODO-dynamic-type (text scale caps at 1.3×; larger needs adaptive layout on the layout-frozen surfaces) · TODO-ios18-floor-decision (ANALYTICS-GATED to 2.3+. LOWERTARGET-1 moved the floor 26.2 → 26.0 — a same-major move, which is why it needed zero `#available` guards and could ship as a pure pbxproj diff. Going BELOW 26 is a different class of change: it re-admits every pre-26 API divergence and would put real availability guards into feature code, so decide it from the installed-base split, never from "the build happens to compile". Corollary that made this its own PR: never combine a deployment-target change with feature work — availability guards buried in a feature diff make both the guard and the feature unreviewable).
