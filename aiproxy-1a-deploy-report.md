# AIPROXY-1a — Cloud Function Deploy Report

**Run date:** 2026-08-03 (log timestamps 2026-08-03T22:51–23:14 UTC)
**Project:** `healthbar-e055c` · billing: **Blaze** (upgraded this session, $300/90-day GCP trial credit active)
**Deployed source:** `e2427da` (main — merge of PR #69) · initial deploy was `36dab4f` (merge of PR #68)
**PRs:** #68 (1a + AMEND) · #69 (init fix + `TODO-nodejs22-before-2026-10-30`)
**Function:** `aiProxy` · 2nd-gen callable · `us-central1` · 512MiB · timeout 120s · nodejs20
**Function URL:** `https://us-central1-healthbar-e055c.cloudfunctions.net/aiProxy`
**Cloud Run service:** `https://aiproxy-u6vxoc6ata-uc.a.run.app` · initial revision `aiproxy-00001-zed`
**Secret:** `ANTHROPIC_API_KEY` version 1, state `ENABLED`, bound via `defineSecret`, granted to `513228134028-compute@developer.gserviceaccount.com`

## Why this file exists

The runbook's final step is "record the function URL/region and probe outcomes." Recording them
in a chat session or a browser tab is not recording them. This repo already paid for that lesson
in July, when the only record of a rules rollback lived in console history and had to be
reconstructed. Deploy state that exists solely in someone's console history is state nobody can
diff, grep, or hand to the next session — hence a committed artifact, following the
`smoke-run-report.md` precedent.

Scope note: **AIPROXY-1a ships zero client changes.** Every `.swift` file is untouched and the
live app still calls Anthropic directly with the bundled key. The function deployed here is live
but **idle** — nothing calls it until AIPROXY-1b migrates the client.

## Runbook step results

| # | Step | Result | Evidence |
|---|------|--------|----------|
| 1 | VERIFY Blaze | PASS | Project was on Spark at session start; upgraded by the operator. Verified by evidence rather than assertion: `firebase ext:list` successfully **enabled** `firebaseextensions.googleapis.com`, and API enablement fails outright on Spark. Prior to upgrade, `firebase functions:list` returned `403 SERVICE_DISABLED` for `cloudfunctions.googleapis.com` — expected for a project that had never deployed functions, and **not** a Spark/Blaze signal either way. |
| 2 | New Anthropic key `healthbar-aiproxy` | PASS (operator) | Created in the same capped workspace as the $50 spend limit. See Finding 3 — the first key was leaked into a chat transcript and rotated before use. |
| 3 | `firebase functions:secrets:set ANTHROPIC_API_KEY` | PASS (operator, second attempt) | First attempt failed with `400 Secret Payload cannot be empty` — see Finding 2. Re-run in a real terminal succeeded. Verified without exposing the value: `firebase functions:secrets:get ANTHROPIC_API_KEY` → version `1`, state `ENABLED`. |
| 4 | `firebase deploy --only functions:aiProxy` | PASS (two deploys) | Deploy 1 from `36dab4f`: `Successful create operation`. Enabled `cloudfunctions`, `cloudbuild`, `artifactregistry`, `run`, `eventarc` APIs; granted `roles/secretmanager.secretAccessor` on the secret. Deploy 2 from `e2427da` after the init fix: `Successful update operation`. Both deploys exited non-zero on an Artifact Registry cleanup-policy warning **after** the function deployed successfully — see Finding 4. |
| P1 | Authed `foodRecognition`, text-only | **PASS** (2nd run) | `200`, `requestsRemainingToday: 14` — proving the counter went 0→1 — and 1324 chars returned. Model output conformed to the frozen schema: `{"items":[{"name":"Scrambled Eggs","quantity":"2 large eggs","calories":182,"protein":12.6,"carbs":1.6,"fat":13.6,"toxinScore":10,"fiber":0,"sugar":0.6,"sodium":180,"saturatedFat":4.1,"cholesterol":372,"potassium":176,"confidence":"high",...}]}`. Failed on the first run — see Finding 1. |
| P2 | Authed `foodRecognition`, image + text + `category: "meal"` | **PASS** (2nd run) | `200`, `requestsRemainingToday: 13` (counter 1→2) through the multimodal content-block path. Reconciliation-rule verification: see Finding 5 — it cannot be read from logs by design, so corroborated via token accounting. |
| P3 | Unauthenticated call | **PASS** | `401` / `UNAUTHENTICATED`. Log line: `{"appCheckPresent":false,"outcome":"unauthenticated","message":"aiProxy rejected"}`. |
| P4 | Bad / dead kinds | **PASS** (4/4) | All returned `400` / `INVALID_ARGUMENT`: `kind: "describeMeal"` → dead kind stays dead · `kind: "photoRecognition"` → dead kind stays dead · `kind: "somethingElse"` → unknown kind · `{kind: "foodRecognition", category: "meal"}` with neither `text` nor `imageBase64` → the AMEND's `hasText \|\| hasImage` guard. Each logged its `kind` for triage. |
| P5 | Daily limit | **PASS** | Counter hand-set to `15` in the console, then one call → `429`, body `{"error":{"details":{"code":"AI_DAILY_LIMIT"},"message":"Daily AI limit reached.","status":"RESOURCE_EXHAUSTED"}}`. The `details.code` survives the callable wire format intact — this is the field AIPROXY-1b maps to the friendly credits copy. Counter doc and account deleted after. |
| P6 | Log check | **PASS** | Every log line carries `uid`, `kind`, `outcome`, `appCheckPresent: false` as specified. `appCheckPresent: false` is **expected** — no App Check client config exists yet and `enforceAppCheck` is deliberately `false` (monitor-only). Every logging branch was exercised across the session: `ok`, `invalid-argument`, `unauthenticated`, `resource-exhausted`, and `counter-error`. |

## Findings

### 1. `getApps().length` is not `getApp()` — every authed request failed (FIXED, PR #69)

The highest-value result of the entire deploy. **Probe P1 caught a bug that 38 offline assembly
checks could not**, and it would have shipped silently to 1b.

Symptom: every authenticated request died before reaching Anthropic.

```
outcome: counter-error
"The default Firebase app does not exist. Make sure you call initializeApp()
 before using any of the Firebase services."
```

P3 and P4 passed throughout, because both return before touching Firestore — which made the
failure look partial rather than total and is exactly why a positive control (P1) runs first.

Root cause — the lazy initializer asked the wrong question:

```ts
if (getApps().length === 0) { initializeApp(); }
firestoreInstance = getFirestore();
```

`getApps()` returns **every** app, including named ones. `getFirestore()` needs the **default**
app specifically. The callable runtime verifies the auth token before the handler runs — visible
in the logs as `Callable request verification passed` immediately preceding each failure — and
initialises its own **named** app while doing so. By the time `db()` ran, `getApps().length` was
already non-zero, the guard skipped `initializeApp()`, and the default app was never created.

Why local checks were green: importing the module alone leaves `getApps()` empty, so the bug
only exists once token verification has run. Confirmed locally — `require('firebase-functions/v2/https')`
then `getApps()` returns `length = 0`. No amount of offline testing would have surfaced this.

Fix (PR #69):

```ts
try { app = getApp(); } catch { app = initializeApp(); }
firestoreInstance = getFirestore(app);
```

`getApp()` throws iff the default app is absent — precisely the precondition `getFirestore()`
requires. The try/catch is also correct when something else initialises the default app first,
where an unconditional module-scope `initializeApp()` would throw at load and take the whole
function down. Verified by reproducing the precondition directly:

```
precondition: getApps().length = 1 | default app absent
OLD guard would call initializeApp()? false      <- the bug
NEW guard branch taken: initializeApp            <- the fix
default app now exists: [DEFAULT]
```

**The failure was fail-safe.** The throw landed inside `consumeDailyCredit` *before* the
increment, so no user credit was burned and no Anthropic call was made during the broken window.

### 2. `functions:secrets:set` silently submits an empty payload without a TTY

The first secret-set attempt was run through Claude Code's `!` passthrough and failed:

```
Error: Request to .../secrets/ANTHROPIC_API_KEY:addVersion had HTTP Error: 400,
Secret Payload cannot be empty.
```

The passthrough is a pipe, not a TTY. The interactive prompt read nothing and submitted an empty
value. It does **not** hang or report a missing-terminal error — it fails downstream at the API,
where the message points at the payload rather than the cause.

Residual state: the secret *container* `ANTHROPIC_API_KEY` was created with **zero versions**.
Harmless — the next successful set became version 1. A secret with no versions simply cannot be
accessed.

Resolution: re-run in a real terminal (Terminal.app / iTerm), where the prompt gets a TTY. This
is also the safer path — the key never enters a chat transcript or shell history.

**Trap to avoid on the non-interactive route:** `--data-file <path>` reads the file *verbatim*,
and most editors append a trailing newline that becomes part of the secret value. An API key
stored as `sk-ant-...\n` then fails every request with a `401` that reads like a bad key rather
than a formatting bug. If the file route is unavoidable, build it with `printf '%s' 'value' > /tmp/k`
(never `echo`, never an editor) and `rm -P` after. The interactive prompt strips the newline
correctly.

### 3. First Anthropic key leaked into a chat transcript; rotated before use

The initially created `healthbar-aiproxy` key was pasted into a chat transcript, which is stored
and logged. It was never used — revoked and replaced, and only the replacement was entered at the
`functions:secrets:set` prompt.

Worth recording because the paste bought nothing: the operator was running `secrets:set`
themselves, and that command reads from a local prompt that never touches the conversation. The
exposure was pure cost. This is the same failure class as `TODO-revoke-bundled-key-at-2.2` and the
CLAUDE.md lesson that a secret sitting anywhere readable is a published secret — which is the
reason AIPROXY-1a exists at all.

### 4. Deploy exits non-zero on the Artifact Registry cleanup policy (function still deploys)

Both deploys ended with:

```
✔  functions[aiProxy(us-central1)] Successful create operation.
⚠  No cleanup policy detected for repositories in us-central1.
Error: Functions successfully deployed but could not set up cleanup policy in location us-central1.
```

**The function deploys fine** — the non-zero exit is only the cleanup-policy step. Any CI that
gates on `firebase deploy`'s exit code would report a false failure here. Resolved this session
by running `firebase functions:artifacts:setpolicy --force`, which set the **default 1-day**
retention on `projects/healthbar-e055c/locations/us-central1/repositories/gcf-artifacts`.
Without it, container images accumulate on every deploy and bill slowly and invisibly.

### 5. The reconciliation rule cannot be verified from logs — the runbook contradicts the spec

The runbook asks to "verify via logs that the multimodal path included the reconciliation rule in
the system prompt." **This is not possible, by design.** AIPROXY-1a explicitly requires that
prompt text never appears in logs, callable responses, or `HttpsError` details. The runbook step
and the logging rule are in direct conflict; the logging rule wins.

Substitute evidence, which is stronger than a log line would have been:

- **Offline:** the 38-case assembly parity check drives the real `parseRequest` → `buildAnthropicBody`
  pipeline, including the case `system prompt: category + image = guidance AND rule`, with
  expectations built from bytes extracted out of the Swift sources.
- **Live token accounting:** P1 `input_tokens = 902` (text-only, no category, no rule);
  P2 `input_tokens = 981` (image + `category: "meal"` + rule). The **+79** delta is consistent
  with P2's system prompt adding the `meal` guidance (149 bytes ≈ 32 tokens) plus the
  reconciliation rule (220 bytes ≈ 48 tokens) ≈ 80 predicted, with near-identical user text in
  both calls. Consistent with both pieces present; inconsistent with either missing.

Future runbooks should not ask for log-based prompt verification. Token accounting is the
available lever.

### 6. Transient `401` for ~40s after first create — IAM propagation, not a defect

The first probe run returned a Google **infrastructure** `401` for P1 and P2 — an HTML error page
(`Your client does not have permission to the requested URL /aiProxy`), not the function's own
JSON `unauthenticated`. Cloud Run logs show
`The request was not authorized to invoke this service. The access token could not be verified.`

P3 and P4, run seconds later in the same pass, reached the function code and returned proper
JSON. The `allUsers` invoker binding on the underlying Cloud Run service had not finished
propagating when the first requests fired.

**Distinguishing the two is the operational point:** an HTML body means the request never reached
the function; a JSON body with `"status":"UNAUTHENTICATED"` means it did and the function rejected
it. Only the latter is P3 passing. Wait ~1 minute after a first create before probing.

## Verification writes

All writes touched throwaway `@r7ctester` uids only. Four throwaway accounts were created and
**all four deleted**; counter docs from every run removed via
`firebase firestore:delete "users/<uid>" -r --force`. No production uid was touched at any point.
Nothing left behind.

Real Anthropic traffic in this session: 3 successful calls (P1, P2, and the P5 seed call),
totalling roughly 2,800 input and 1,400 output tokens. P4's and P5's rejections consumed no
Anthropic quota — validation and the limit check both run before the upstream call.

## Configuration confirmed live

- Region pinned in code to `us-central1`, co-located with Firestore (`nam5`, verified via `firestore:databases:get`).
- `enforceAppCheck: false` (monitor-only) with a structured warning on every token-less request.
- Daily limit 15/uid/day, counter at `users/{uid}/aiUsage/{yyyyMMdd}`, client-inaccessible — `aiUsage`
  is deliberately absent from the `users/` rules allowlist. No rules change was needed or made;
  `firestore.rules` and `firestore.indexes.json` are untouched by AIPROXY-1a.
- Artifact Registry cleanup policy: 1 day.

## Open items

| Item | Status |
|---|---|
| `TODO-nodejs22-before-2026-10-30` | Node.js 20 deprecated 2026-04-30, **decommissioned 2026-10-30**. After that date `firebase deploy` refuses the codebase, so a broken `aiProxy` could not be redeployed in an emergency. Fix: `functions/package.json` `engines.node` + `firebase.json` `functions[0].runtime` → `nodejs22`, rebuild, redeploy, re-probe. |
| `TODO-revoke-bundled-key-at-2.2` | The bundled client key remains live and un-revoked **by design** — pre-1b builds depend on it. `aiProxy` uses its own separate key, so revoking the bundled one never touches the proxy. |
| `aiUsage` deletion cascade | `deleteAllUserData` does not know about `aiUsage`, and subcollections never cascade. Needs more than a `knownSubcollections` entry: client-SDK deletes run under rules and `aiUsage` is off the allowlist. 1b picks a rules block permitting owner delete, or server-side cleanup. |
| GCP budget alert | Recommended at Blaze upgrade. The $300 trial credit expires in 90 days; on day 91 billing is real. Note the credit is **GCP-only** and does nothing for Anthropic spend — the $50 Anthropic cap is the guard that matters for model calls. |
| AIPROXY-1b | Client migration. `aiProxy` is live but idle until then. |
